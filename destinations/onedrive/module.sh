# ---------------------------------------------------------------------------
# OneDrive (Rclone) destination module
#
# Syncs the Restic repository to Microsoft OneDrive via rclone.
# Uses rclone sync for efficient mirroring.
#
# Configurable via ONEDRIVE_REMOTE and ONEDRIVE_PATH.
# ---------------------------------------------------------------------------

ONEDRIVE_REMOTE="${ONEDRIVE_REMOTE:-OneDrive}"
ONEDRIVE_PATH="${ONEDRIVE_PATH:-Backups}"

destination_name() {
    echo "OneDrive"
}

destination_check() {
    if ! command -v rclone &>/dev/null; then
        echo "  ✗ OneDrive: rclone not installed"
        return 1
    fi

    if ! rclone lsd "${ONEDRIVE_REMOTE}:" &>/dev/null; then
        echo "  ✗ OneDrive: remote '${ONEDRIVE_REMOTE}' not configured"
        echo "    Configure with: rclone config"
        return 1
    fi

    echo "  ✓ OneDrive reachable"
    return 0
}

destination_sync() {
    local repo_path="$1"
    local service_name="${2:-}"

    if ! command -v rclone &>/dev/null; then
        abf_log_error "OneDrive destination: rclone not found"
        return 1
    fi

    if ! rclone lsd "${ONEDRIVE_REMOTE}:" &>/dev/null; then
        abf_log_warning "OneDrive destination: remote '${ONEDRIVE_REMOTE}' not configured"
        abf_log_info "Configure with: rclone config"
        return 1
    fi

    local dest_path
    if [[ -n "$service_name" ]]; then
        local display_name
        display_name=$(_abf_service_display_name "$service_name")
        dest_path="Backups/$(_abf_hostname_display)/${display_name}"
    else
        dest_path="${ONEDRIVE_PATH}"
    fi

    abf_log_info "OneDrive destination: syncing to ${ONEDRIVE_REMOTE}:${dest_path}"

    if [[ "$repo_path" == /* ]]; then
        rclone sync "$repo_path/" "${ONEDRIVE_REMOTE}:${dest_path}/" 2>/dev/null || {
            abf_log_error "OneDrive destination: rclone sync failed"
            return 1
        }
    elif [[ "$repo_path" == rclone:* ]]; then
        local src_remote="${repo_path#rclone:}"
        rclone sync "${src_remote}/" "${ONEDRIVE_REMOTE}:${dest_path}/" 2>/dev/null || {
            abf_log_error "OneDrive destination: rclone sync failed"
            return 1
        }
    else
        abf_log_error "OneDrive destination: unsupported repo path type: ${repo_path}"
        return 1
    fi

    if ! rclone ls "${ONEDRIVE_REMOTE}:${dest_path}/config" &>/dev/null; then
        abf_log_error "OneDrive destination: sync verification failed — config file missing"
        return 1
    fi

    abf_log_success "OneDrive destination: sync completed and verified"
    return 0
}
