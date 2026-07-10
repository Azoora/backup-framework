# ---------------------------------------------------------------------------
# Local filesystem destination module
#
# Syncs the Restic repository to another local path (e.g. an Umbrel SSD).
# Uses rsync for efficient mirroring.
#
# Configurable via DESTINATION_LOCAL_PATH.
# ---------------------------------------------------------------------------

DESTINATION_LOCAL_PATH="${DESTINATION_LOCAL_PATH:-/mnt/umbrel/backups/restic}"

destination_name() {
    echo "Local"
}

destination_sync() {
    local repo_path="$1"

    if [[ "$repo_path" != /* ]]; then
        abf_log_warning "Local destination: source is not a local path — skipping"
        return 1
    fi

    local dest_dir
    dest_dir=$(dirname "$DESTINATION_LOCAL_PATH")

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

    abf_log_info "Local destination: syncing to ${DESTINATION_LOCAL_PATH}"
    rsync -a --delete "$repo_path/" "$DESTINATION_LOCAL_PATH/" 2>/dev/null || {
        abf_log_error "Local destination: rsync failed"
        return 1
    }

    if [[ ! -f "${DESTINATION_LOCAL_PATH}/config" ]]; then
        abf_log_error "Local destination: sync verification failed — config file missing"
        return 1
    fi

    abf_log_success "Local destination: sync completed and verified"
    return 0
}
