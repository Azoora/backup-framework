# ---------------------------------------------------------------------------
# restic.sh  --  Restic encryption and storage integration
#
# All restic operations go through this module.
# The repository URL is provided by the active storage plugin.
# ---------------------------------------------------------------------------

ABF_RESTIC_REPO=""
ABF_RESTIC_SNAPSHOT_ID=""

# ------------------------------------------------------------------
# Initialization
# ------------------------------------------------------------------

abf_restic_init() {
    local repo_url="$1"

    if ! command -v restic &>/dev/null; then
        abf_log_error "restic not found -- install restic or disable encryption"
        return "$ABF_EXIT_STORAGE_ERROR"
    fi

    ABF_RESTIC_REPO="$repo_url"

    if [[ ! -f "${ABF_RESTIC_PASSWORD_FILE:-/etc/abf/restic-password}" ]]; then
        abf_log_error "Restic password file not found: ${ABF_RESTIC_PASSWORD_FILE:-/etc/abf/restic-password}"
        return "$ABF_EXIT_CONFIG_ERROR"
    fi

    # Initialize repo if it doesn't exist
    if ! _restic_run "snapshots" --quiet &>/dev/null; then
        abf_log_info "Initializing new restic repository: ${repo_url}"
        _restic_run "init" || {
            abf_log_error "Failed to initialize restic repository"
            return "$ABF_EXIT_STORAGE_ERROR"
        }
        abf_log_success "Restic repository initialized"
    fi

    return "$ABF_EXIT_OK"
}

# ------------------------------------------------------------------
# Backup
# ------------------------------------------------------------------

abf_restic_backup() {
    local source_dir="$1"
    local service_name="$2"

    if [[ -z "$ABF_RESTIC_REPO" ]]; then
        abf_log_error "Restic repository not configured"
        return "$ABF_EXIT_CONFIG_ERROR"
    fi

    if [[ ! -d "$source_dir" ]]; then
        abf_log_error "Source directory not found: ${source_dir}"
        return "$ABF_EXIT_BACKUP_FAILED"
    fi

    abf_log_info "Restic: creating encrypted backup of ${service_name}"

    local output
    output=$(_restic_run "backup" "$source_dir" \
        --tag "$service_name" \
        --host "$(hostname)" 2>&1) || {
        abf_log_error "Restic backup failed"
        echo "$output" | while IFS= read -r line; do
            abf_log_debug "restic: ${line}"
        done
        return "$ABF_EXIT_BACKUP_FAILED"
    }

    # Extract snapshot ID from output
    ABF_RESTIC_SNAPSHOT_ID=$(echo "$output" | grep -oP 'snapshot \K[a-f0-9]{8,}' | head -1 || true)
    local size
    size=$(echo "$output" | grep -oP 'added: \K[^,]+' | head -1 || echo "unknown")

    abf_log_success "Restic: backup completed (snapshot: ${ABF_RESTIC_SNAPSHOT_ID:-unknown}, size: ${size})"
    return "$ABF_EXIT_OK"
}

# ------------------------------------------------------------------
# Restore
# ------------------------------------------------------------------

abf_restic_restore() {
    local snapshot="$1"
    local target_dir="$2"
    local service_name="$3"

    abf_log_info "Restic: restoring snapshot ${snapshot}"

    _restic_run "restore" "$snapshot" \
        --target "$target_dir" \
        --tag "$service_name" 2>&1 | while IFS= read -r line; do
        abf_log_debug "restic: ${line}"
    done

    local rc=$?
    if [[ $rc -eq 0 ]]; then
        abf_log_success "Restic: restore completed"
    else
        abf_log_error "Restic: restore failed"
    fi
    return $rc
}

# ------------------------------------------------------------------
# Verification
# ------------------------------------------------------------------

abf_restic_verify() {
    if [[ -z "${ABF_RESTIC_REPO:-}" ]]; then
        return "$ABF_EXIT_OK"
    fi

    abf_log_info "Restic: verifying repository integrity"

    _restic_run "check" --read-data-subset=5% 2>&1 | while IFS= read -r line; do
        abf_log_debug "restic: ${line}"
    done

    local rc=$?
    if [[ $rc -eq 0 ]]; then
        abf_log_success "Restic: repository integrity check passed"
    else
        abf_log_error "Restic: repository integrity check FAILED"
    fi
    return "$rc"
}

# ------------------------------------------------------------------
# Snapshot listing
# ------------------------------------------------------------------

abf_restic_list_snapshots() {
    local service_name="${1:-}"

    if [[ -z "$ABF_RESTIC_REPO" ]]; then
        return 0
    fi

    local filter=()
    if [[ -n "$service_name" ]]; then
        filter=(--tag "$service_name")
    fi

    _restic_run "snapshots" "${filter[@]}" 2>/dev/null | tail -n +3 | head -n -1 || true
}

# ------------------------------------------------------------------
# Retention
# ------------------------------------------------------------------

abf_restic_forget() {
    local service_name="$1"

    local keep_daily="${ABF_RETENTION_KEEP_DAILY:-7}"
    local keep_weekly="${ABF_RETENTION_KEEP_WEEKLY:-4}"
    local keep_monthly="${ABF_RETENTION_KEEP_MONTHLY:-3}"
    local keep_yearly="${ABF_RETENTION_KEEP_YEARLY:-0}"

    abf_log_info "Restic: applying retention policy (daily=${keep_daily}, weekly=${keep_weekly}, monthly=${keep_monthly})"

    _restic_run "forget" \
        --tag "$service_name" \
        --keep-daily "$keep_daily" \
        --keep-weekly "$keep_weekly" \
        --keep-monthly "$keep_monthly" \
        --keep-yearly "$keep_yearly" \
        --prune 2>&1 | while IFS= read -r line; do
        abf_log_debug "restic: ${line}"
    done

    local rc=$?
    if [[ $rc -eq 0 ]]; then
        abf_log_success "Restic: retention policy applied"
    else
        abf_log_warning "Restic: retention policy encountered issues"
    fi
    return "$rc"
}

# ------------------------------------------------------------------
# Latest snapshot lookup
# ------------------------------------------------------------------

abf_restic_get_latest_snapshot() {
    local service_name="${1:-}"

    if [[ -z "${ABF_RESTIC_REPO:-}" ]]; then
        return 1
    fi

    local filter=()
    if [[ -n "$service_name" ]]; then
        filter=(--tag "$service_name")
    fi

    _restic_run "snapshots" "${filter[@]}" --json 2>/dev/null \
        | grep -oP '"short_id"\s*:\s*"\K[a-f0-9]+' \
        | tail -1 || true
}

# ------------------------------------------------------------------
# Internal
# ------------------------------------------------------------------

_restic_run() {
    local cmd="$1"
    shift

    restic -r "$ABF_RESTIC_REPO" \
        --password-file "${ABF_RESTIC_PASSWORD_FILE:-/etc/abf/restic-password}" \
        "$cmd" "$@"
}
