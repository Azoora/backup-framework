# ---------------------------------------------------------------------------
# OneDrive (Rclone) storage module
#
# Provides a restic repository URL backed by Microsoft OneDrive via rclone.
# Restic natively supports rclone as a backend, so no separate upload step
# is needed -- restic handles both encryption and transport.
# ---------------------------------------------------------------------------

STORAGE_ONEDRIVE_REMOTE="${STORAGE_ONEDRIVE_REMOTE:-onedrive}"
STORAGE_ONEDRIVE_PATH="${STORAGE_ONEDRIVE_PATH:-abf-restic}"

storage_pre_upload() {
    if ! command -v rclone &>/dev/null; then
        abf_log_error "rclone not found -- required for OneDrive storage"
        return 1
    fi
    abf_log_info "OneDrive: checking remote '${STORAGE_ONEDRIVE_REMOTE}'"
    if ! rclone lsd "${STORAGE_ONEDRIVE_REMOTE}:" &>/dev/null; then
        abf_log_warning "OneDrive: remote '${STORAGE_ONEDRIVE_REMOTE}' not configured"
        abf_log_info "Configure with: rclone config"
        return 1
    fi
    return 0
}

storage_get_repo_url() {
    local service_name="${1:-}"
    if [[ -n "$service_name" ]]; then
        local display_name
        display_name=$(_abf_service_display_name "$service_name")
        echo "rclone:${STORAGE_ONEDRIVE_REMOTE}:Backups/$(_abf_hostname_display)/${display_name}"
    else
        echo "rclone:${STORAGE_ONEDRIVE_REMOTE}:${STORAGE_ONEDRIVE_PATH}"
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
    abf_log_info "OneDrive: cleanup (context: ${context})"
    return 0
}
