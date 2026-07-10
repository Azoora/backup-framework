# ---------------------------------------------------------------------------
# Local filesystem destination module
#
# Syncs the Restic repository to another local path (e.g. an Umbrel SSD).
# Uses rsync for efficient mirroring.
#
# Configurable via LOCAL_DESTINATION_PATH.
# ---------------------------------------------------------------------------

LOCAL_DESTINATION_PATH="${LOCAL_DESTINATION_PATH:-/mnt/umbrel/backups/restic}"

destination_name() {
    echo "Local"
}

destination_check() {
    local dest_dir
    dest_dir=$(dirname "$LOCAL_DESTINATION_PATH")

    if [[ ! -d "$dest_dir" ]]; then
        echo "  ✗ Local destination path parent does not exist: ${dest_dir}"
        return 1
    fi

    if [[ ! -w "$dest_dir" ]]; then
        echo "  ✗ Local destination path parent is not writable: ${dest_dir}"
        return 1
    fi

    echo "  ✓ Local destination reachable"
    return 0
}

destination_sync() {
    local repo_path="$1"

    if [[ "$repo_path" != /* ]]; then
        abf_log_warning "Local destination: source is not a local path — skipping"
        return 1
    fi

    local dest_dir
    dest_dir=$(dirname "$LOCAL_DESTINATION_PATH")

    if [[ ! -d "$dest_dir" ]]; then
        abf_log_info "Local destination: creating parent directory ${dest_dir}"
        mkdir -p "$dest_dir" 2>/dev/null || {
            abf_log_error "Local destination: cannot create directory ${dest_dir}"
            return 1
        }
    fi

    if [[ ! -w "$dest_dir" ]]; then
        abf_log_error "Local destination: directory not writable: ${dest_dir}"
        return 1
    fi

    abf_log_info "Local destination: syncing to ${LOCAL_DESTINATION_PATH}"
    rsync -a --delete "$repo_path/" "$LOCAL_DESTINATION_PATH/" 2>/dev/null || {
        abf_log_error "Local destination: rsync failed"
        return 1
    }

    if [[ ! -f "${LOCAL_DESTINATION_PATH}/config" ]]; then
        abf_log_error "Local destination: sync verification failed — config file missing"
        return 1
    fi

    abf_log_success "Local destination: sync completed and verified"
    return 0
}
