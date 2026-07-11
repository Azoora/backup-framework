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
# Destination manifest
# ------------------------------------------------------------------

abf_destination_exists() {
    local name="$1"
    _abf_destination_manifest_lines | grep -qFx "$name" 2>/dev/null
}

_abf_destination_manifest_lines() {
    grep -v '^#' "${ABF_ROOT}/destinations/manifest.conf" 2>/dev/null \
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
# Destination module loader
# ------------------------------------------------------------------

abf_load_destination_module() {
    local name="$1"
    local module="${ABF_ROOT}/destinations/${name}/module.sh"

    if [[ ! -f "$module" ]]; then
        abf_log_error "Destination module not found: ${module}"
        return 1
    fi

    source "$module"

    if ! declare -F "destination_sync" &>/dev/null; then
        abf_log_error "Destination module missing required function: destination_sync"
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
# 7. destination sync         -- sync repo to configured destinations
# 8. service_post_backup      -- cleanup
# 9. notification             -- send email
# ------------------------------------------------------------------

abf_run_backup() {
    local service_name="$1"
    local rc="$ABF_EXIT_OK"
    local repo_verify_rc="$ABF_EXIT_OK"
    local dest_results=()

    ABF_BACKUP_START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S%z")
    ABF_BACKUP_END_TIME=""
    ABF_BACKUP_DURATION=""
    ABF_BACKUP_REPO_VERIFY_STATUS=""
    ABF_BACKUP_DEST_RESULTS=""

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

    # ----- privilege check -----
    _abf_check_backup_privileges "$service_name" || {
        rc="$ABF_EXIT_CONFIG_ERROR"
        _abf_call_optional service_cleanup "backup"
        _abf_notify_result "$rc" "$service_name"
        trap - EXIT; abf_lock_release "$ABF_LOCK_SERVICE"; ABF_LOCK_SERVICE=""
        return "$rc"
    }

    # ----- pre-backup -----
    service_pre_backup || {
        rc="$ABF_EXIT_BACKUP_FAILED"
        service_post_backup
        _abf_call_optional service_cleanup "backup"
        _abf_notify_result "$rc" "$service_name"
        trap - EXIT; abf_lock_release "$ABF_LOCK_SERVICE"; ABF_LOCK_SERVICE=""
        return "$rc"
    }
    ABF_STAGING_DIR="${ABF_SERVICE_STAGING_DIR:-}"

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

    if abf_restic_verify; then
        repo_verify_rc="$ABF_EXIT_OK"
    else
        repo_verify_rc="$ABF_EXIT_VERIFICATION_FAILED"
        abf_log_warning "Restic verification reported issues for ${service_name}"
    fi

    # ----- retention -----
    _abf_retention_apply "$service_name"

    # ----- destination sync -----
    if [[ -n "${BACKUP_DESTINATIONS:-}" ]]; then
        dest_results=()
        IFS=',' read -ra dest_list <<< "$BACKUP_DESTINATIONS"
        for dest in "${dest_list[@]}"; do
            dest=$(echo "$dest" | xargs)
            local label="$dest"
            if abf_load_destination_module "$dest" 2>/dev/null; then
                abf_load_destination_config "$dest" 2>/dev/null
                if declare -F "destination_name" &>/dev/null; then
                    local dn
                    dn=$(destination_name 2>/dev/null) && [[ -n "$dn" ]] && label="$dn"
                fi
            fi
            if _abf_sync_destination "$dest" "$service_name"; then
                dest_results+=("${label}:SUCCESS")
            else
                dest_results+=("${label}:FAILED")
            fi
        done
    fi

    # ----- cleanup -----
    service_post_backup
    _abf_call_optional service_cleanup "backup"

    # ----- timing -----
    ABF_BACKUP_END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S%z")
    if [[ -n "$ABF_BACKUP_START_TIME" ]]; then
        local start_s end_s diff_s
        start_s=$(date -d "$ABF_BACKUP_START_TIME" +%s 2>/dev/null || echo "0")
        end_s=$(date -d "$ABF_BACKUP_END_TIME" +%s 2>/dev/null || echo "0")
        diff_s=$(( end_s - start_s ))
        if [[ $diff_s -ge 0 ]]; then
            local hours mins secs
            hours=$(( diff_s / 3600 ))
            mins=$(( (diff_s % 3600) / 60 ))
            secs=$(( diff_s % 60 ))
            ABF_BACKUP_DURATION=$(printf "%02d:%02d:%02d" "$hours" "$mins" "$secs")
        fi
    fi

    # ----- repo verify status -----
    if [[ "$repo_verify_rc" -eq "$ABF_EXIT_OK" ]]; then
        ABF_BACKUP_REPO_VERIFY_STATUS="SUCCESS"
    else
        ABF_BACKUP_REPO_VERIFY_STATUS="FAILED"
    fi

    # ----- destination results -----
    if [[ ${#dest_results[@]} -gt 0 ]]; then
        ABF_BACKUP_DEST_RESULTS=""
        for entry in "${dest_results[@]}"; do
            if [[ -n "$ABF_BACKUP_DEST_RESULTS" ]]; then
                ABF_BACKUP_DEST_RESULTS+=", "
            fi
            ABF_BACKUP_DEST_RESULTS+="${entry}"
        done
    fi

    # ----- summary -----
    _abf_print_summary "$service_name" "$rc" "$repo_verify_rc" "${dest_results[@]}"

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
    local yes="${4:-false}"
    local target_dir="${5:-}"
    local components="${6:-}"
    local replace_all="${7:-false}"
    local rc="$ABF_EXIT_OK"

    export ABF_RESTORE_TARGET="$target_dir"
    export ABF_RESTORE_REPLACE_ALL="$replace_all"

    if [[ -n "$components" ]]; then
        abf_load_service_module "$service_name" || return "$ABF_EXIT_SERVICE_NOT_FOUND"
        local resolved
        resolved=$(_abf_resolve_components "$components")
        export ABF_RESTORE_COMPONENTS="$resolved"
    else
        export ABF_RESTORE_COMPONENTS=""
    fi

    abf_log_info "Starting restore for service: ${service_name}"

    abf_load_service_module "$service_name" || return "$ABF_EXIT_SERVICE_NOT_FOUND"
    abf_load_service_config "$service_name"
    _abf_call_optional service_healthcheck "restore"

    # ----- lock -----
    abf_lock_init
    abf_lock_acquire "$service_name" || return "$ABF_EXIT_LOCK_ERROR"
    ABF_LOCK_SERVICE="$service_name"
    trap 'abf_lock_release "$ABF_LOCK_SERVICE"; ABF_LOCK_SERVICE=""; trap - EXIT' EXIT

    # ----- privilege check (skip data dir check for --target) -----
    if [[ -z "$target_dir" ]]; then
        _abf_check_restore_privileges "$service_name" || {
            rc="$ABF_EXIT_RESTORE_FAILED"
            trap - EXIT; abf_lock_release "$ABF_LOCK_SERVICE"; ABF_LOCK_SERVICE=""
            return "$rc"
        }
    fi

    # ----- confirmation -----
    _abf_require_confirmation "$dry_run" "$yes" "$replace_all"
    local confirm_rc=$?
    if [[ $confirm_rc -eq 1 ]]; then
        # User cancelled — clean exit, not an error
        trap - EXIT; abf_lock_release "$ABF_LOCK_SERVICE"; ABF_LOCK_SERVICE=""
        return "$ABF_EXIT_OK"
    elif [[ $confirm_rc -ne 0 ]]; then
        # Non-interactive without --yes
        rc="$confirm_rc"
        trap - EXIT; abf_lock_release "$ABF_LOCK_SERVICE"; ABF_LOCK_SERVICE=""
        return "$rc"
    fi

    # ----- pre-restore -----
    service_pre_restore "$snapshot" "$dry_run" || {
        rc="$ABF_EXIT_RESTORE_FAILED"
        service_post_restore
        _abf_call_optional service_cleanup "restore"
        trap - EXIT; abf_lock_release "$ABF_LOCK_SERVICE"; ABF_LOCK_SERVICE=""
        return "$rc"
    }

    abf_log_info "Restoring snapshot ${snapshot} for ${service_name}..."

    if [[ "$dry_run" == "true" ]]; then
        service_restore "$snapshot" "true" || rc="$ABF_EXIT_RESTORE_FAILED"
    else
        local staging
        staging=$(mktemp -d -t "abf-restore-XXXXXX")

        abf_log_info "Decrypting backup..."
        if abf_restic_init "$(_abf_get_storage_repo)"; then
            abf_restic_restore "$snapshot" "$staging" "$service_name" || {
                rc="$ABF_EXIT_RESTORE_FAILED"
            }
        fi

        # ----- pre-restore backup (safety net, skipped for --target) -----
        if [[ -z "$target_dir" ]]; then
            local prefix
            prefix=$(_abf_svc_var_prefix "$service_name")
            local data_dir_var="${prefix}_DATA_DIR"
            local data_dir="${!data_dir_var:-}"
            if [[ -n "$data_dir" ]] && [[ -d "$data_dir" ]]; then
                _abf_create_pre_restore_backup "$service_name" "$data_dir"
            fi
        fi

        ABF_RESTORE_STAGING="$staging"
        abf_log_info "Copying files to service directory..."
        service_restore "$snapshot" "false" || rc="$ABF_EXIT_RESTORE_FAILED"
        rm -rf "$staging"
    fi

    abf_log_info "Running verification..."
    service_verify_restore || {
        rc="$ABF_EXIT_VERIFICATION_FAILED"
        abf_log_warning "Restore verification reported issues"
    }

    service_post_restore
    _abf_call_optional service_cleanup "restore"

    if [[ "$rc" -eq "$ABF_EXIT_OK" ]]; then
        abf_log_success "Restore completed for service: ${service_name}"
    fi

    trap - EXIT
    abf_lock_release "$ABF_LOCK_SERVICE"
    ABF_LOCK_SERVICE=""
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
    # Replace hyphens with underscores so the prefix forms a valid bash variable name
    echo "SERVICE_$(echo "$name" | tr '[:lower:]-' '[:upper:]_')"
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

    local details=""
    details="${details}Snapshot ID: ${ABF_SNAPSHOT_ID:-none}"
    if [[ -n "${ABF_RESTIC_REPO:-}" ]]; then
        details="${details}"$'\n'"Repository: ${ABF_RESTIC_REPO}"
    fi

    abf_notify_send "$status" "$service_name" "$details" || true
}

# ------------------------------------------------------------------
# Destination sync
# ------------------------------------------------------------------

_abf_sync_destination() {
    local dest="$1"
    local service_name="$2"

    if ! abf_destination_exists "$dest"; then
        abf_log_warning "Destination '${dest}' is not registered in destinations/manifest.conf"
        return 1
    fi

    abf_load_destination_module "$dest" 2>/dev/null || return 1
    abf_load_destination_config "$dest" 2>/dev/null

    local repo_url
    repo_url=$(_abf_get_storage_repo 2>/dev/null) || {
        abf_log_warning "Destination '${dest}': no storage repo available — skipping"
        return 1
    }

    abf_log_info "Destination '${dest}': syncing repository"
    if destination_sync "$repo_url"; then
        abf_log_success "Destination '${dest}': sync succeeded"
        return 0
    else
        abf_log_error "Destination '${dest}': sync failed"
        return 1
    fi
}

# ------------------------------------------------------------------
# Destination check
# ------------------------------------------------------------------

abf_destination_check_all() {
    local dests="${BACKUP_DESTINATIONS:-}"
    local overall_rc="$ABF_EXIT_OK"

    if [[ -z "$dests" ]]; then
        echo "No destinations configured."
        echo "Set BACKUP_DESTINATIONS in abf.conf (e.g. BACKUP_DESTINATIONS=\"local,onedrive\")."
        return 0
    fi

    echo "Checking destinations..."
    echo ""

    IFS=',' read -ra dest_list <<< "$dests"
    for dest in "${dest_list[@]}"; do
        dest=$(echo "$dest" | xargs)

        if ! abf_destination_exists "$dest"; then
            echo "  ✗ '${dest}' is not registered in destinations/manifest.conf"
            overall_rc="$ABF_EXIT_DESTINATION_ERROR"
            continue
        fi

        abf_load_destination_module "$dest" 2>/dev/null || {
            echo "  ✗ ${dest}: module not found"
            overall_rc="$ABF_EXIT_DESTINATION_ERROR"
            continue
        }
        abf_load_destination_config "$dest" 2>/dev/null

        if declare -F "destination_check" &>/dev/null; then
            destination_check || overall_rc="$ABF_EXIT_DESTINATION_ERROR"
        else
            echo "  ✓ ${dest} configured"
        fi
    done

    return "$overall_rc"
}

_abf_print_summary() {
    local service_name="$1"
    local backup_rc="$2"
    local verify_rc="$3"
    shift 3
    local -a dest_results=("$@")

    local backup_status repo_verify_status entry name status

    if [[ "$backup_rc" -eq "$ABF_EXIT_OK" ]]; then
        backup_status="SUCCESS"
    else
        backup_status="FAILED"
    fi

    if [[ "$verify_rc" -eq "$ABF_EXIT_OK" ]]; then
        repo_verify_status="SUCCESS"
    else
        repo_verify_status="FAILED"
    fi

    echo ""
    echo "========================================"
    echo "  Backup Summary — ${service_name}"
    echo "========================================"
    printf "  %-22s %s\n" "Backup:" "${backup_status}"
    printf "  %-22s %s\n" "Repository Verify:" "${repo_verify_status}"

    for entry in "${dest_results[@]}"; do
        name="${entry%%:*}"
        status="${entry#*:}"
        printf "  %-22s %s\n" "${name}:" "${status}"
    done

    echo "========================================"
    echo ""
}

# ------------------------------------------------------------------
# Privilege detection
# ------------------------------------------------------------------

_abf_check_backup_privileges() {
    local service_name="$1"
    local errors=0

    # Check restic password file is readable
    local pw_file="${ABF_RESTIC_PASSWORD_FILE:-/etc/abf/restic-password}"
    if [[ -n "$pw_file" ]]; then
        if [[ -e "$pw_file" && ! -r "$pw_file" ]]; then
            abf_log_error "Cannot read restic password file: ${pw_file}"
            ((errors++))
        fi
    fi

    # Check service data directory is readable
    local prefix
    prefix=$(_abf_svc_var_prefix "$service_name")
    local data_dir_var="${prefix}_DATA_DIR"
    local data_dir="${!data_dir_var:-}"
    if [[ -n "$data_dir" ]] && [[ -e "$data_dir" && ! -r "$data_dir" ]]; then
        abf_log_error "Cannot read service data directory: ${data_dir}"
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        abf_log_error "Backup requires elevated privileges."
        echo ""
        echo "  Run: sudo abf backup ${service_name}"
        return 1
    fi

    return 0
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

    # --- Destination module checks ---
    if [[ -n "${BACKUP_DESTINATIONS:-}" ]]; then
        if [[ ! -f "${ABF_ROOT}/destinations/manifest.conf" ]]; then
            echo "  [ERROR] Destination manifest not found at destinations/manifest.conf"
            errors=$((errors + 1))
            exit_code="$ABF_EXIT_CONFIG_ERROR"
        fi
        IFS=',' read -ra dest_list <<< "$BACKUP_DESTINATIONS"
        for dest in "${dest_list[@]}"; do
            dest=$(echo "$dest" | xargs)
            if [[ ! -f "${ABF_ROOT}/destinations/${dest}/module.sh" ]]; then
                echo "  [ERROR] Destination module not found: destinations/${dest}/module.sh"
                errors=$((errors + 1))
                exit_code="$ABF_EXIT_CONFIG_ERROR"
            fi
        done
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
    if ! command -v rsync &>/dev/null; then
        echo "  [ERROR] rsync not installed (required for restore operations)"
        errors=$((errors + 1))
        exit_code="$ABF_EXIT_CONFIG_ERROR"
    fi
    if ! command -v sqlite3 &>/dev/null; then
        echo "  [WARN]  sqlite3 not installed (recommended for consistent SQLite backups)"
        warnings=$((warnings + 1))
    fi

    # --- Destination dependency checks ---
    if [[ -n "${BACKUP_DESTINATIONS:-}" ]]; then
        IFS=',' read -ra dest_list <<< "$BACKUP_DESTINATIONS"
        for dest in "${dest_list[@]}"; do
            dest=$(echo "$dest" | xargs)
            if [[ "$dest" == "onedrive" ]] && ! command -v rclone &>/dev/null; then
                echo "  [ERROR] Rclone not installed (required for OneDrive destination)"
                errors=$((errors + 1))
                exit_code="$ABF_EXIT_CONFIG_ERROR"
            fi
            if [[ "$dest" == "local" ]] && ! command -v rsync &>/dev/null; then
                echo "  [ERROR] rsync not installed (required for local destination)"
                errors=$((errors + 1))
                exit_code="$ABF_EXIT_CONFIG_ERROR"
            fi
        done
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
