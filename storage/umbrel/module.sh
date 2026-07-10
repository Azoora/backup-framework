# ---------------------------------------------------------------------------
# Umbrel Home Server storage module  --  Milestone 3
#
# Lifecycle hooks called by the storage engine.
# Replicates backups to an Umbrel Home Server.
# ---------------------------------------------------------------------------

STORAGE_UMBEL_HOST="${STORAGE_UMBREL_HOST:-}"
STORAGE_UMBREL_PATH="${STORAGE_UMBREL_PATH:-abf-backups}"

storage_pre_upload() {
    if [[ -z "$STORAGE_UMBREL_HOST" ]]; then
        abf_log_error "Umbrel: STORAGE_UMBREL_HOST not configured"
        return 1
    fi
    abf_log_info "Umbrel: target host ${STORAGE_UMBREL_HOST}"
    return 0
}

storage_upload() {
    local source_path="$1"
    abf_log_info "Umbrel: upload not yet implemented (Milestone 3)"
    return 1
}

storage_download() {
    local remote_path="$1"
    local dest_dir="$2"
    abf_log_info "Umbrel: download not yet implemented (Milestone 3)"
    return 1
}

storage_list() {
    abf_log_info "Umbrel: list not yet implemented (Milestone 3)"
    return 0
}

storage_delete() {
    local remote_path="$1"
    abf_log_info "Umbrel: delete not yet implemented (Milestone 3)"
    return 1
}

storage_cleanup() {
    local context="${1:-}"
    abf_log_info "Umbrel: cleanup (context: ${context})"
    return 0
}
