# ---------------------------------------------------------------------------
# lock.sh  --  Service-level backup locking
#
# Prevents concurrent backup jobs for the same service.
# Uses PID-based lock files with stale detection.
# ---------------------------------------------------------------------------

ABF_LOCK_DIR="${ABF_LOCK_DIR:-}"
ABF_LOCK_SERVICE=""

# ------------------------------------------------------------------
# Initialization
# ------------------------------------------------------------------

abf_lock_init() {
    ABF_LOCK_DIR="${ABF_LOCK_DIR:-${ABF_TEMP_DIR:-/tmp/abf}/locks}"
    mkdir -p "$ABF_LOCK_DIR" 2>/dev/null || true
}

# ------------------------------------------------------------------
# Acquire lock
# ------------------------------------------------------------------

abf_lock_acquire() {
    local service_name="$1"

    if [[ -z "$ABF_LOCK_DIR" ]]; then
        abf_lock_init
    fi

    local lock_file="${ABF_LOCK_DIR}/${service_name}.lock"

    if [[ -f "$lock_file" ]]; then
        local pid
        pid=$(cat "$lock_file" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            abf_log_error "Another backup is already running for ${service_name} (PID: ${pid})"
            return "$ABF_EXIT_LOCK_ERROR"
        fi
        abf_log_warning "Removed stale lock file for ${service_name} (PID ${pid} no longer running)"
        rm -f "$lock_file"
    fi

    echo "$$" > "$lock_file"
    abf_log_debug "Lock acquired for ${service_name} (PID: $$)"
    return "$ABF_EXIT_OK"
}

# ------------------------------------------------------------------
# Release lock
# ------------------------------------------------------------------

abf_lock_release() {
    local service_name="$1"

    if [[ -z "${ABF_LOCK_DIR:-}" ]]; then
        return "$ABF_EXIT_OK"
    fi

    local lock_file="${ABF_LOCK_DIR}/${service_name}.lock"

    if [[ -f "$lock_file" ]]; then
        local pid
        pid=$(cat "$lock_file" 2>/dev/null || echo "")
        if [[ "$pid" == "$$" ]]; then
            rm -f "$lock_file"
            abf_log_debug "Lock released for ${service_name}"
        fi
    fi

    return "$ABF_EXIT_OK"
}
