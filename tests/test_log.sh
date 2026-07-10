# ---------------------------------------------------------------------------
# Tests for logging system
# ---------------------------------------------------------------------------

test_init_logging_creates_directory() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-log-XXXXXX")
    local log_dir="${tmpdir}/logs"

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test-svc" "backup" "$log_dir"

    assert_eq "$log_dir" "${ABF_LOG_DIR:-}" "ABF_LOG_DIR"
    if [[ ! -d "$log_dir" ]]; then
        echo "  FAIL: Log directory should exist: $log_dir"
        return 1
    fi
}

test_log_info_writes_to_files() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-log-XXXXXX")

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test-svc" "backup" "$tmpdir"

    abf_log_info "Hello world"

    if [[ ! -f "$ABF_LOG_FILE" ]]; then
        echo "  FAIL: Human log should exist: $ABF_LOG_FILE"
        return 1
    fi
    if [[ ! -f "$ABF_LOG_JSON_FILE" ]]; then
        echo "  FAIL: JSON log should exist: $ABF_LOG_JSON_FILE"
        return 1
    fi

    local human_content
    human_content=$(cat "$ABF_LOG_FILE")
    assert_contains "$human_content" "Hello world" "Human log contains message"
    assert_contains "$human_content" "INFO" "Human log contains level"

    local json_content
    json_content=$(cat "$ABF_LOG_JSON_FILE")
    assert_contains "$json_content" "Hello world" "JSON log contains message"
    assert_contains "$json_content" '"level":"INFO"' "JSON log contains uppercase level"
}

test_log_success() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-log-XXXXXX")

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test" "backup" "$tmpdir"
    abf_log_success "All good"

    local content
    content=$(cat "$ABF_LOG_FILE")
    assert_contains "$content" "SUCCESS" "Success log has SUCCESS level"
    assert_contains "$content" "All good" "Success log has message"
}

test_log_error() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-log-XXXXXX")

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test" "backup" "$tmpdir"
    abf_log_error "Something broke"

    local content
    content=$(cat "$ABF_LOG_FILE")
    assert_contains "$content" "ERROR" "Error log has ERROR level"
    assert_contains "$content" "Something broke" "Error log has message"
}

test_log_falls_back_to_console_when_dir_unwritable() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-log-XXXXXX")
    local log_dir="${tmpdir}/readonly"
    mkdir -p "$log_dir"
    chmod 555 "$log_dir"

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test-svc" "backup" "$log_dir"

    # Log file variables should be cleared (fallback to console)
    if [[ -n "${ABF_LOG_FILE:-}" ]]; then
        echo "  FAIL: ABF_LOG_FILE should be empty when dir is unwritable (got: ${ABF_LOG_FILE})"
        chmod 755 "$log_dir"
        return 1
    fi
    if [[ -n "${ABF_LOG_JSON_FILE:-}" ]]; then
        echo "  FAIL: ABF_LOG_JSON_FILE should be empty when dir is unwritable"
        chmod 755 "$log_dir"
        return 1
    fi

    chmod 755 "$log_dir"
    return 0
}

test_log_no_permission_denied_on_console_when_unwritable() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-log-XXXXXX")
    local log_dir="${tmpdir}/readonly"
    mkdir -p "$log_dir"
    chmod 555 "$log_dir"

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test-svc" "backup" "$log_dir"

    # Capture stderr while logging — must not contain "Permission denied"
    local stderr_output
    stderr_output=$(abf_log_error "This should not leak file errors" 2>&1 1>/dev/null)

    chmod 755 "$log_dir"

    if echo "$stderr_output" | grep -qi "permission denied\|cannot create\|no such file"; then
        echo "  FAIL: Error messages leaked to console: $stderr_output"
        return 1
    fi

    return 0
}

test_log_no_redirect_errors_on_console() {
    # Direct test: verify that file redirect failures never leak to the console
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-log-XXXXXX")
    # Create a parent dir that is NOT writable, so child dir creation fails
    local parent="${tmpdir}/readonly-parent"
    mkdir -p "$parent"
    chmod 555 "$parent"
    local log_dir="${parent}/logs"

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test-svc" "backup" "$log_dir"

    # Log with INFO (stdout) — must NOT contain shell redirect errors
    local stdout_output
    stdout_output=$(abf_log_info "Console only" 2>/dev/null)
    if echo "$stdout_output" | grep -qi "no such file\|permission denied\|cannot"; then
        echo "  FAIL: Redirect error leaked to stdout: $stdout_output"
        chmod 755 "$parent"
        return 1
    fi

    # Log with ERROR (stderr) — must NOT contain shell redirect errors
    local stderr_output
    stderr_output=$(abf_log_error "Console only error" 2>&1 1>/dev/null)
    if echo "$stderr_output" | grep -qi "no such file\|permission denied\|cannot"; then
        echo "  FAIL: Redirect error leaked to stderr: $stderr_output"
        chmod 755 "$parent"
        return 1
    fi

    chmod 755 "$parent"
    return 0
}
