# ---------------------------------------------------------------------------
# restore.sh  --  Restore safety and validation helpers
#
# Restore-specific functions used by the pipeline in core.sh.
# Separated to keep restore logic modular and testable.
#
# Phase 2 additions:
#   _abf_create_pre_restore_backup  -- snap current state before restore
#   _abf_resolve_components          -- expand short names via service hook
# ---------------------------------------------------------------------------

# ------------------------------------------------------------------
# Privilege check for restore
#
# Validates that:
#   - The restic password file is readable
#   - The service data directory exists and is writable
# ------------------------------------------------------------------

_abf_check_restore_privileges() {
    local service_name="$1"
    local errors=0

    local pw_file="${ABF_RESTIC_PASSWORD_FILE:-/etc/abf/restic-password}"
    if [[ -n "$pw_file" ]]; then
        if [[ -e "$pw_file" && ! -r "$pw_file" ]]; then
            abf_log_error "Cannot read restic password file: ${pw_file}"
            ((errors++))
        fi
    fi

    local prefix
    prefix=$(_abf_svc_var_prefix "$service_name")
    local data_dir_var="${prefix}_DATA_DIR"
    local data_dir="${!data_dir_var:-}"
    if [[ -z "$data_dir" ]]; then
        abf_log_error "Service data directory not configured for ${service_name}"
        ((errors++))
    elif [[ ! -d "$data_dir" ]]; then
        abf_log_error "Service data directory does not exist: ${data_dir}"
        ((errors++))
    elif [[ ! -w "$data_dir" ]]; then
        abf_log_error "Service data directory is not writable: ${data_dir}"
        abf_log_error "Restore requires write access to: ${data_dir}"
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        abf_log_error "Restore privilege check failed"
        echo ""
        echo "  Run: sudo abf restore ${service_name}" >&2
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------
# Interactive check
#
# Returns 0 if stdin is a terminal (interactive session).
# Can be overridden in tests.
# ------------------------------------------------------------------

_abf_is_interactive() {
    [[ -t 0 ]]
}

# ------------------------------------------------------------------
# Confirmation prompt
#
# Returns ABF_EXIT_OK to proceed, ABF_EXIT_RESTORE_ABORTED to abort.
#
# Skips confirmation when:
#   - dry_run is true (preview mode)
#   - yes is true (--yes flag provided)
#
# When confirm is needed and stdin is not a TTY, fails with error.
# ------------------------------------------------------------------

_abf_require_confirmation() {
    local dry_run="$1"
    local yes="$2"
    local replace_all="${3:-false}"

    [[ "$dry_run" == "true" ]] && return 0
    [[ "$yes" == "true" ]] && return 0

    if ! _abf_is_interactive; then
        abf_log_error "Interactive confirmation required. Re-run with --yes."
        return "$ABF_EXIT_RESTORE_ABORTED"
    fi

    echo ""
    if [[ "$replace_all" == "true" ]]; then
        echo "WARNING: --replace-all mode enabled."
        echo "Existing files in restored components will be DELETED before restore."
        echo ""
    fi
    echo -n "This restore will overwrite existing data. Continue? [y/N] "
    read -r confirm
    if [[ ! "${confirm:-}" =~ ^[yY] ]]; then
        echo "Restore cancelled by user."
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------
# Pre-restore backup
#
# Creates a timestamped snapshot of the component files that will be
# overwritten during restore. The backup is stored in:
#   ${ABF_TEMP_DIR}/pre_restore/<service>/<timestamp>/
#
# Not called when --target is provided (no production data touched).
#
# The backup includes a .metadata file listing the service name,
# original location, and timestamp for recovery purposes.
# ------------------------------------------------------------------

_abf_create_pre_restore_backup() {
    local service_name="$1"
    local data_dir="$2"

    local pre_dir="${ABF_TEMP_DIR:-/tmp/abf}/pre_restore/${service_name}"
    local timestamp
    timestamp=$(date +%Y%m%dT%H%M%S)
    local backup_dir="${pre_dir}/${timestamp}"

    mkdir -p "$backup_dir" || {
        abf_log_error "Failed to create pre-restore backup directory: ${backup_dir}"
        return 1
    }

    if ! command -v rsync &>/dev/null; then
        abf_log_error "rsync is required for pre-restore backup. Install rsync and try again."
        return 1
    fi

    local components="${ABF_RESTORE_COMPONENTS:-}"
    if [[ -z "$components" ]]; then
        if declare -F service_resolve_components &>/dev/null; then
            components=$(service_resolve_components "")
        else
            components=""
        fi
    fi

    if [[ -z "$components" ]]; then
        abf_log_info "No components specified -- backing up entire data directory"
        rsync -a "$data_dir/" "$backup_dir/"
    else
        local IFS=','
        for comp in $components; do
            local src="${data_dir}/${comp}"
            if [[ -e "$src" ]]; then
                abf_log_info "  Pre-backup: ${comp}"
                rsync -aR "${src}" "$backup_dir/"
            else
                abf_log_info "  Skipping pre-backup (not found): ${comp}"
            fi
        done
    fi

    cat > "${backup_dir}/.metadata" <<EOF
SERVICE=${service_name}
TIMESTAMP=${timestamp}
DATA_DIR=${data_dir}
COMPONENTS=${components}
EOF

    abf_log_success "Pre-restore backup created: ${backup_dir}"
    return 0
}

# ------------------------------------------------------------------
# Resolve component short names using service module
#
# If the service module provides service_resolve_components(), use it.
# Otherwise, return the raw string unchanged.
# ------------------------------------------------------------------

_abf_resolve_components() {
    local raw="${1:-}"
    if declare -F service_resolve_components &>/dev/null; then
        service_resolve_components "$raw"
    else
        echo "$raw"
    fi
}
