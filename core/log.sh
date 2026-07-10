# ---------------------------------------------------------------------------
# log.sh  --  Dual-output logging system
#
# Produces:
#   - Human-readable log  (printed to stdout/stderr + .log file)
#   - Machine-readable log (JSON Lines .jsonl file)
#
# Usage:
#   abf_init_logging <service> <operation> [log_dir]
#   abf_log_info    "message"
#   abf_log_success "message"
#   abf_log_warning "message"
#   abf_log_error   "message"
# ---------------------------------------------------------------------------

ABF_LOG_DIR=""
ABF_LOG_FILE=""
ABF_LOG_JSON_FILE=""

abf_init_logging() {
    local service="$1"
    local operation="$2"
    local log_dir="${3:-${ABF_LOG_DIR:-}}"
    local timestamp
    timestamp=$(date -u +"%Y%m%d-%H%M%S")

    ABF_LOG_DIR="$log_dir"
    ABF_LOG_FILE="${log_dir}/${service}_${operation}_${timestamp}.log"
    ABF_LOG_JSON_FILE="${log_dir}/${service}_${operation}_${timestamp}.jsonl"

    mkdir -p "$log_dir" 2>/dev/null || true
}

# ------------------------------------------------------------------
# Public log helpers
# ------------------------------------------------------------------

abf_log_debug() {
    [[ "${ABF_VERBOSE:-}" == "true" ]] || return 0
    _abf_log "DEBUG" "$1"
}
abf_log_info()    { _abf_log "INFO"    "$1"; }
abf_log_success() { _abf_log "SUCCESS" "$1"; }
abf_log_warning() { _abf_log "WARNING" "$1"; }
abf_log_error()   { _abf_log "ERROR"   "$1"; }

# ------------------------------------------------------------------
# Internal
# ------------------------------------------------------------------

_abf_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S%z")

    _abf_write_human "$timestamp" "$level" "$message"
    _abf_write_machine "$timestamp" "$level" "$message"
}

_abf_write_human() {
    local timestamp="$1"
    local level="$2"
    local message="$3"
    local line="[${timestamp}] [$(printf '%-7s' "${level}")] ${message}"

    if [[ "$level" == "ERROR" ]]; then
        echo "$line" >&2
    else
        echo "$line"
    fi

    if [[ -n "${ABF_LOG_FILE:-}" ]]; then
        echo "$line" >> "$ABF_LOG_FILE" 2>/dev/null || true
    fi
}

_abf_write_machine() {
    local timestamp="$1"
    local level="$2"
    local message="$3"
    local escaped
    escaped=$(printf '%s' "$message" | sed 's/"/\\"/g')

    if [[ -n "${ABF_LOG_JSON_FILE:-}" ]]; then
        printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
            "$timestamp" "$level" "$escaped" \
            >> "$ABF_LOG_JSON_FILE" 2>/dev/null || true
    fi
}
