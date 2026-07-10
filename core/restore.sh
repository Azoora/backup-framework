# ---------------------------------------------------------------------------
# restore.sh  --  Restore safety and validation helpers
#
# Restore-specific functions used by the pipeline in core.sh.
# Separated to keep restore logic modular and testable.
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

    [[ "$dry_run" == "true" ]] && return 0
    [[ "$yes" == "true" ]] && return 0

    if ! _abf_is_interactive; then
        abf_log_error "Interactive confirmation required. Re-run with --yes."
        return "$ABF_EXIT_RESTORE_ABORTED"
    fi

    echo ""
    echo -n "This restore will overwrite existing data. Continue? [y/N] "
    read -r confirm
    if [[ ! "${confirm:-}" =~ ^[yY] ]]; then
        echo "Restore cancelled by user."
        return 1
    fi

    return 0
}
