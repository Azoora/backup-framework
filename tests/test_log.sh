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
