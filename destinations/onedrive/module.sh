# ---------------------------------------------------------------------------
# OneDrive (Rclone) destination module
#
# Syncs the Restic repository to Microsoft OneDrive via rclone.
# Uses rclone sync for efficient mirroring.
#
# Configurable via DESTINATION_ONEDRIVE_REMOTE and DESTINATION_ONEDRIVE_PATH.
# ---------------------------------------------------------------------------

DESTINATION_ONEDRIVE_REMOTE="${DESTINATION_ONEDRIVE_REMOTE:-onedrive}"
DESTINATION_ONEDRIVE_PATH="${DESTINATION_ONEDRIVE_PATH:-abf-restic-backup}"

destination_name() {
    echo "OneDrive"
}

destination_sync() {
    local repo_path="$1"

    if ! command -v rclone &>/dev/null; then
        abf_log_error "OneDrive destination: rclone not found"
        return 1
    fi

    if ! rclone lsd "${DESTINATION_ONEDRIVE_REMOTE}:" &>/dev/null; then
        abf_log_warning "OneDrive destination: remote '${DESTINATION_ONEDRIVE_REMOTE}' not configured"
        abf_log_info "Configure with: rclone config"
        return 1
    fi

    abf_log_info "OneDrive destination: syncing to ${DESTINATION_ONEDRIVE_REMOTE}:${DESTINATION_ONEDRIVE_PATH}"

    if [[ "$repo_path" == /* ]]; then
        rclone sync "$repo_path/" "${DESTINATION_ONEDRIVE_REMOTE}:${DESTINATION_ONEDRIVE_PATH}/" 2>/dev/null || {
            abf_log_error "OneDrive destination: rclone sync failed"
            return 1
        }
    elif [[ "$repo_path" == rclone:* ]]; then
        local src_remote="${repo_path#rclone:}"
        rclone sync "${src_remote}/" "${DESTINATION_ONEDRIVE_REMOTE}:${DESTINATION_ONEDRIVE_PATH}/" 2>/dev/null || {
            abf_log_error "OneDrive destination: rclone sync failed"
            return 1
        }
    else
        abf_log_error "OneDrive destination: unsupported repo path type: ${repo_path}"
        return 1
    fi

    if ! rclone ls "${DESTINATION_ONEDRIVE_REMOTE}:${DESTINATION_ONEDRIVE_PATH}/config" &>/dev/null; then
        abf_log_error "OneDrive destination: sync verification failed — config file missing"
        return 1
    fi

    abf_log_success "OneDrive destination: sync completed and verified"
    return 0
}
