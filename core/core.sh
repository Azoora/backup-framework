# ---------------------------------------------------------------------------
# core.sh  --  Core backup engine
#
# Orchestrates backup and restore by delegating to service lifecycle hooks.
# The core engine never contains service-specific logic.
#
# Service module lifecycle hooks:
#   service_pre_backup   service_backup   service_verify_backup   service_post_backup
#   service_pre_restore  service_restore  service_verify_restore  service_post_restore
#   service_healthcheck  service_cleanup
#
# Milestone 2 adds:
#   - Restic encryption/storage in the backup pipeline
#   - Email notifications on completion
#   - Retention policy via restic forget
# ---------------------------------------------------------------------------

ABF_STAGING_DIR=""
ABF_SNAPSHOT_ID=""

# ------------------------------------------------------------------
# Manifest
# ------------------------------------------------------------------

abf_load_manifest() {
    local manifest="${ABF_ROOT}/services/manifest.conf"
    if [[ ! -f "$manifest" ]]; then
        abf_log_error "Service manifest not found: ${manifest}"
        return 1
    fi
    return 0
}

abf_service_exists() {
    local name="$1"
    _abf_manifest_lines | grep -qFx "$name" 2>/dev/null
}

abf_list_services() {
    _abf_manifest_lines
}

_abf_manifest_lines() {
    grep -v '^#' "${ABF_ROOT}/services/manifest.conf" 2>/dev/null \
        | grep -v '^[[:space:]]*$' || true
}

# ------------------------------------------------------------------
# Storage manifest
# ------------------------------------------------------------------

abf_storage_exists() {
    local name="$1"
    _abf_storage_manifest_lines | grep -qFx "$name" 2>/dev/null
}

_abf_storage_manifest_lines() {
    grep -v '^#' "${ABF_ROOT}/storage/manifest.conf" 2>/dev/null \
        | grep -v '^[[:space:]]*$' || true
}

# ------------------------------------------------------------------
# Service module loader
# ------------------------------------------------------------------

abf_load_service_module() {
    local name="$1"
    local module="${ABF_ROOT}/services/${name}/module.sh"

    if [[ ! -f "$module" ]]; then
        abf_log_error "Service module not found: ${module}"
        return 1
    fi

    source "$module"

    local required_funcs=(
        service_pre_backup service_backup service_verify_backup service_post_backup
        service_pre_restore service_restore service_verify_restore service_post_restore
    )
    for func in "${required_funcs[@]}"; do
        if ! declare -F "$func" &>/dev/null; then
            abf_log_error "Service module missing required function: ${func}"
            return 1
        fi
    done

    return 0
}

# ------------------------------------------------------------------
# Storage module loader
# ------------------------------------------------------------------

abf_load_storage_module() {
    local name="$1"
    local module="${ABF_ROOT}/storage/${name}/module.sh"

    if [[ ! -f "$module" ]]; then
        abf_log_error "Storage module not found: ${module}"
        return 1
    fi

    source "$module"

    if ! declare -F "storage_get_repo_url" &>/dev/null; then
        abf_log_error "Storage module missing required function: storage_get_repo_url"
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------
# Lifecycle helper: call optional hook if it exists
# ------------------------------------------------------------------

_abf_call_optional() {
    local hook="$1"
    shift
    if declare -F "$hook" &>/dev/null; then
        "$hook" "$@"
    fi
}

# ------------------------------------------------------------------
# Backup pipeline (Milestone 2)
#
# 1. service_pre_backup      -- validate, create staging dir
# 2. service_backup           -- populate staging dir with files
# 3. restic backup            -- encrypt and store
# 4. service_verify_backup    -- verify backup
# 5. restic verify            -- verify repository integrity
# 6. retention                -- forget old snapshots
# 7. notification             -- send email
# 8. service_post_backup      -- cleanup
# ------------------------------------------------------------------

abf_run_backup() {
    local service_name="$1"
    local rc="$ABF_EXIT_OK"

    abf_log_info "Starting backup for service: ${service_name}"

    # Acquire lock -- prevents concurrent backups
    abf_lock_init
    abf_lock_acquire "$service_name" || return "$ABF_EXIT_LOCK_ERROR"
    ABF_LOCK_SERVICE="$service_name"

    # Safety net: release lock on unexpected script exit
    trap 'abf_lock_release "$ABF_LOCK_SERVICE"; ABF_LOCK_SERVICE=""; trap - EXIT' EXIT

    abf_load_service_module "$service_name" || {
        trap - EXIT; abf_lock_release "$ABF_LOCK_SERVICE"; ABF_LOCK_SERVICE=""
        return "$ABF_EXIT_SERVICE_NOT_FOUND"
    }
    abf_load_service_config "$service_name"
    _abf_call_optional service_healthcheck "backup"

    # ----- pre-backup -----
    service_pre_backup || {
        rc="$ABF_EXIT_BACKUP_FAILED"
        service_post_backup
        _abf_call_optional service_cleanup "backup"
        _abf_notify_result "$rc" "$service_name"
        trap - EXIT; abf_lock_release "$ABF_LOCK_SERVICE"; ABF_LOCK_SERVICE=""
        return "$rc"
    }
    ABF_STAGING_DIR="${ABF_VW_TEMP_DIR:-}"

    # ----- backup (populate staging dir) -----
    service_backup || {
        rc="$ABF_EXIT_BACKUP_FAILED"
        service_verify_backup || true
        service_post_backup
        _abf_call_optional service_cleanup "backup"
        _abf_notify_result "$rc" "$service_name"
        trap - EXIT; abf_lock_release "$ABF_LOCK_SERVICE"; ABF_LOCK_SERVICE=""
        return "$rc"
    }

    # ----- restic: encrypt and store -----
    _abf_restic_backup_stage "$service_name" || {
        rc="$ABF_EXIT_BACKUP_FAILED"
        service_post_backup
        _abf_call_optional service_cleanup "backup"
        _abf_notify_result "$rc" "$service_name"
        trap - EXIT; abf_lock_release "$ABF_LOCK_SERVICE"; ABF_LOCK_SERVICE=""
        return "$rc"
    }

    # ----- verify -----
    service_verify_backup || {
        rc="$ABF_EXIT_VERIFICATION_FAILED"
        abf_log_warning "Backup verification reported issues for ${service_name}"
    }

    abf_restic_verify || {
        abf_log_warning "Restic verification reported issues for ${service_name}"
    }

    # ----- retention -----
    _abf_retention_apply "$service_name"

    # ----- cleanup -----
    service_post_backup
    _abf_call_optional service_cleanup "backup"

    # ----- notification -----
    _abf_notify_result "$rc" "$service_name"

    if [[ "$rc" -eq "$ABF_EXIT_OK" ]]; then
        abf_log_success "Backup completed for service: ${service_name}"
    fi

    trap - EXIT
    abf_lock_release "$ABF_LOCK_SERVICE"
    ABF_LOCK_SERVICE=""
    return "$rc"
}

# ------------------------------------------------------------------
# Restore pipeline (Milestone 2)
#
# 1. service_pre_restore      -- validate
# 2. restic restore           -- decrypt and restore from repo
# 3. service_restore          -- copy files to service location
# 4. service_verify_restore   -- verify
# 5. service_post_restore     -- cleanup
# ------------------------------------------------------------------

abf_run_restore() {
    local service_name="$1"
    local snapshot="${2:-}"
    local dry_run="${3:-false}"
    local rc="$ABF_EXIT_OK"

    abf_log_info "Starting restore for service: ${service_name}"

    abf_load_service_module "$service_name" || return "$ABF_EXIT_SERVICE_NOT_FOUND"
    abf_load_service_config "$service_name"
    _abf_call_optional service_healthcheck "restore"

    service_pre_restore "$snapshot" "$dry_run" || {
        rc="$ABF_EXIT_RESTORE_FAILED"
        service_post_restore
        _abf_call_optional service_cleanup "restore"
        return "$rc"
    }

    if [[ "$dry_run" == "true" ]]; then
        service_restore "$snapshot" "true" || rc="$ABF_EXIT_RESTORE_FAILED"
    else
        # Restic restore into staging dir, then service copies from there
        local staging
        staging=$(mktemp -d -t "abf-restore-XXXXXX")

        if abf_restic_init "$(_abf_get_storage_repo)"; then
            abf_restic_restore "$snapshot" "$staging" "$service_name" || {
                rc="$ABF_EXIT_RESTORE_FAILED"
            }
        fi

        # Pass staging dir to service via environment
        ABF_RESTORE_STAGING="$staging"
        service_restore "$snapshot" "false" || rc="$ABF_EXIT_RESTORE_FAILED"
        rm -rf "$staging"
    fi

    service_verify_restore || {
        rc="$ABF_EXIT_VERIFICATION_FAILED"
        abf_log_warning "Restore verification reported issues"
    }

    service_post_restore
    _abf_call_optional service_cleanup "restore"

    if [[ "$rc" -eq "$ABF_EXIT_OK" ]]; then
        abf_log_success "Restore completed for service: ${service_name}"
    fi
    return "$rc"
}

# ------------------------------------------------------------------
# Snapshot listing
# ------------------------------------------------------------------

abf_list_snapshots() {
    local service_name="${1:-}"

    local repo
    repo=$(_abf_get_storage_repo 2>/dev/null) || {
        echo "No storage backend configured — no snapshots to list."
        return 0
    }

    abf_restic_init "$repo" 2>/dev/null || {
        echo "Could not connect to repository: ${repo}"
        return 1
    }

    if [[ -n "$service_name" ]]; then
        abf_load_service_config "$service_name"
    fi

    abf_restic_list_snapshots "$service_name"
}

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

_abf_svc_var_prefix() {
    local name="$1"
    echo "SERVICE_$(echo "$name" | tr '[:lower:]' '[:upper:]')"
}

_abf_get_storage_repo() {
    local backend="${ABF_STORAGE_BACKEND:-local}"
    abf_load_storage_module "$backend" 2>/dev/null || return 1
    abf_load_storage_config "$backend" 2>/dev/null
    # Redirect stdout to stderr so pre_upload log messages don't pollute the repo URL
    { _abf_call_optional storage_pre_upload; } 1>&2 || return 1
    storage_get_repo_url 2>/dev/null || return 1
}

_abf_restic_backup_stage() {
    local service_name="$1"
    local repo
    repo=$(_abf_get_storage_repo) || return "$ABF_EXIT_OK"  # no storage configured

    abf_restic_init "$repo" || return 1
    abf_restic_backup "$ABF_STAGING_DIR" "$service_name" || return 1
    ABF_SNAPSHOT_ID="$ABF_RESTIC_SNAPSHOT_ID"
    return 0
}

_abf_retention_apply() {
    local service_name="$1"
    if [[ -n "${ABF_RESTIC_REPO:-}" ]]; then
        abf_apply_retention "$service_name"
    fi
}

_abf_notify_result() {
    local rc="$1"
    local service_name="$2"
    local status="SUCCESS"

    if [[ "$rc" -eq "$ABF_EXIT_OK" ]]; then
        status="SUCCESS"
    elif [[ "$rc" -eq "$ABF_EXIT_VERIFICATION_FAILED" ]]; then
        status="WARNING"
    else
        status="FAILED"
    fi

    local details="Snapshot: ${ABF_SNAPSHOT_ID:-none}"
    if [[ -n "${ABF_RESTIC_REPO:-}" ]]; then
        details="${details}\nRepository: ${ABF_RESTIC_REPO}"
    fi

    abf_notify_send "$status" "$service_name" "$details" || true
}

# ------------------------------------------------------------------
# Config validation
# ------------------------------------------------------------------

abf_validate_config() {
    local exit_code="$ABF_EXIT_OK"
    local errors=0
    local warnings=0

    # --- Config value checks ---
    if [[ -z "${ABF_LOG_DIR:-}" ]]; then
        echo "  [ERROR] ABF_LOG_DIR is not set in abf.conf"
        errors=$((errors + 1))
        exit_code="$ABF_EXIT_CONFIG_ERROR"
    fi

    if [[ ! -f "${ABF_ROOT}/services/manifest.conf" ]]; then
        echo "  [ERROR] Service manifest not found at services/manifest.conf"
        errors=$((errors + 1))
        exit_code="$ABF_EXIT_CONFIG_ERROR"
    fi

    while IFS= read -r svc; do
        if [[ ! -f "${ABF_ROOT}/services/${svc}/module.sh" ]]; then
            echo "  [ERROR] Service '${svc}' listed in manifest but module.sh not found"
            errors=$((errors + 1))
            exit_code="$ABF_EXIT_CONFIG_ERROR"
        fi
    done < <(_abf_manifest_lines)

    # --- Storage module check ---
    local backend="${ABF_STORAGE_BACKEND:-local}"
    if [[ ! -f "${ABF_ROOT}/storage/${backend}/module.sh" ]]; then
        echo "  [ERROR] Storage module not found: storage/${backend}/module.sh"
        errors=$((errors + 1))
        exit_code="$ABF_EXIT_CONFIG_ERROR"
    fi

    # --- Password file check ---
    if [[ ! -f "${ABF_RESTIC_PASSWORD_FILE:-/etc/abf/restic-password}" ]]; then
        echo "  [ERROR] Restic password file not found: ${ABF_RESTIC_PASSWORD_FILE:-/etc/abf/restic-password}"
        errors=$((errors + 1))
        exit_code="$ABF_EXIT_CONFIG_ERROR"
    fi

    # --- Dependency checks ---
    if ! command -v restic &>/dev/null; then
        echo "  [WARN]  Restic not installed (required for encrypted backups)"
        warnings=$((warnings + 1))
    fi
    if ! command -v rclone &>/dev/null; then
        if [[ "$backend" != "local" ]]; then
            echo "  [ERROR] Rclone not installed (required for configured remote storage)"
            errors=$((errors + 1))
            exit_code="$ABF_EXIT_CONFIG_ERROR"
        else
            echo "  [WARN]  Rclone not installed (recommended for remote storage)"
            warnings=$((warnings + 1))
        fi
    fi
    if ! command -v sqlite3 &>/dev/null; then
        echo "  [WARN]  sqlite3 not installed (recommended for consistent SQLite backups)"
        warnings=$((warnings + 1))
    fi

    # --- Summary ---
    echo ""
    if [[ "$errors" -gt 0 ]] || [[ "$warnings" -gt 0 ]]; then
        echo "  Configuration: ${errors} error(s), ${warnings} warning(s)"
    else
        echo "  Configuration: valid"
    fi

    return $exit_code
}

# ------------------------------------------------------------------
# Health check
# ------------------------------------------------------------------

abf_healthcheck() {
    local service_name="$1"
    abf_load_service_module "$service_name" 2>/dev/null || return "$ABF_EXIT_SERVICE_NOT_FOUND"
    abf_load_service_config "$service_name"
    _abf_call_optional service_healthcheck "healthcheck"
    return "$ABF_EXIT_OK"
}
