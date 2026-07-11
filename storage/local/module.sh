# ---------------------------------------------------------------------------
# Local filesystem storage module
#
# Stores Restic repositories on the local filesystem.
# Repository location is configurable via STORAGE_LOCAL_REPO_PATH.
# All backup/restore/list/verify operations use Restic natively
# against the local path.
# ---------------------------------------------------------------------------

STORAGE_LOCAL_REPO_PATH="${STORAGE_LOCAL_REPO_PATH:-/tmp/abf/restic}"

storage_pre_upload() {
    local dir
    dir=$(dirname "$STORAGE_LOCAL_REPO_PATH")

    if [[ ! -d "$dir" ]]; then
        abf_log_info "Local: creating parent directory ${dir}"
        mkdir -p "$dir" 2>/dev/null || {
            abf_log_error "Local: cannot create directory ${dir}"
            return 1
        }
    fi

    if [[ ! -w "$dir" ]]; then
        abf_log_error "Local: directory not writable: ${dir}"
        return 1
    fi

    abf_log_info "Local: repository path ${STORAGE_LOCAL_REPO_PATH}"
    return 0
}

storage_get_repo_url() {
    local service_name="${1:-}"
    if [[ -n "$service_name" ]]; then
        local display_name
        display_name=$(_abf_service_display_name "$service_name")
        echo "${STORAGE_LOCAL_REPO_PATH}/${display_name}"
    else
        echo "${STORAGE_LOCAL_REPO_PATH}"
    fi
}

storage_list() {
    local repo
    repo=$(storage_get_repo_url)

    if [[ -z "${ABF_RESTIC_PASSWORD_FILE:-}" ]]; then
        ABF_RESTIC_PASSWORD_FILE="/etc/abf/restic-password"
    fi

    if [[ ! -f "$ABF_RESTIC_PASSWORD_FILE" ]]; then
        return 0
    fi

    restic -r "$repo" --password-file "$ABF_RESTIC_PASSWORD_FILE" snapshots 2>/dev/null || true
}

storage_cleanup() {
    local context="${1:-}"
    abf_log_info "Local: cleanup (context: ${context})"
    return 0
}
