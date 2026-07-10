# ---------------------------------------------------------------------------
# Tests for configuration loading
# ---------------------------------------------------------------------------

test_load_config_from_custom_dir() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-cfg-XXXXXX")

    echo 'ABF_LOG_DIR="/tmp/test-log"' > "$tmpdir/abf.conf"
    echo 'STORAGE_DEFAULT="local"' > "$tmpdir/storage.conf"

    source "${ABF_ROOT}/core/config.sh"
    abf_load_config "$tmpdir" || return 1

    assert_eq "/tmp/test-log" "${ABF_LOG_DIR:-}" "ABF_LOG_DIR"
    assert_eq "local" "${STORAGE_DEFAULT:-}" "STORAGE_DEFAULT"
}

test_load_config_inherits_env() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-cfg-XXXXXX")

    echo 'ABF_LOG_DIR="/var/log/abf"' > "$tmpdir/abf.conf"

    source "${ABF_ROOT}/core/config.sh"
    abf_load_config "$tmpdir" || return 1

    assert_eq "/var/log/abf" "${ABF_LOG_DIR:-}" "ABF_LOG_DIR should come from config"
}

test_load_config_missing_directory() {
    source "${ABF_ROOT}/core/config.sh"
    if abf_load_config "/nonexistent/abf-test-dir" 2>/dev/null; then
        echo "  FAIL: Expected non-zero exit for missing directory"
        return 1
    fi
    return 0
}

test_discover_config_dir_fallback() {
    source "${ABF_ROOT}/core/config.sh"
    local result
    result=$(_abf_discover_config_dir)
    assert_eq "${ABF_ROOT}/config" "$result" "fallback config dir"
}

test_load_service_config() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-svc-XXXXXX")
    mkdir -p "$tmpdir/services"

    echo 'SERVICE_TEST_DATA_DIR="/opt/test"' > "$tmpdir/services/test.conf"

    source "${ABF_ROOT}/core/config.sh"
    ABF_CONFIG_DIR="$tmpdir"
    ABF_ROOT="${ABF_ROOT}"

    abf_load_service_config "test"

    assert_eq "/opt/test" "${SERVICE_TEST_DATA_DIR:-}" "SERVICE_TEST_DATA_DIR"
}

test_validate_config_missing_log_dir() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/core.sh"

    unset ABF_LOG_DIR
    ABF_ROOT="${ABF_ROOT}"

    if abf_validate_config 2>/dev/null; then
        echo "  FAIL: Validation should fail when ABF_LOG_DIR is not set"
        return 1
    fi
    return 0
}

test_validate_config_missing_service_module() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/core.sh"

    export ABF_LOG_DIR="/tmp"
    ABF_ROOT="${ABF_ROOT}"

    # Temporarily remove a service module to trigger validation failure
    local test_svc="__nonexistent_test_svc__"
    echo "$test_svc" > /tmp/abf-test-manifest-$$.conf

    # Override manifest path by temporarily replacing services/manifest.conf
    local orig_manifest="${ABF_ROOT}/services/manifest.conf"
    cp "$orig_manifest" /tmp/abf-test-manifest-orig-$$.conf
    echo "$test_svc" >> /tmp/abf-test-manifest-orig-$$.conf

    # Run validation with modified manifest
    local rc=0
    (
        # shellcheck disable=SC1091
        source "${ABF_ROOT}/core/core.sh"
        export ABF_ROOT="${ABF_ROOT}"
        # Override manifest just for the test by patching the function
        _abf_manifest_lines() { echo "$test_svc"; }
        abf_validate_config 2>/dev/null
    ) && rc=1 || rc=0

    if [[ "$rc" -ne 0 ]]; then
        echo "  FAIL: Validation should fail for missing service module"
        return 1
    fi
    return 0
}

test_validate_config_missing_password_file() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "config-test" "test" "/tmp"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/core.sh"

    export ABF_LOG_DIR="/tmp"
    export ABF_STORAGE_BACKEND="onedrive"
    export ABF_RESTIC_PASSWORD_FILE="/tmp/abf-nonexistent-pw-file-$$"

    if abf_validate_config 2>/dev/null; then
        echo "  FAIL: Validation should fail when password file missing"
        return 1
    fi
    return 0
}

test_validate_config_valid() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/core.sh"

    export ABF_LOG_DIR="/tmp"
    export ABF_STORAGE_BACKEND="local"

    if ! abf_validate_config 2>/dev/null; then
        echo "  FAIL: Validation should pass for local storage"
        return 1
    fi
    return 0
}

test_validate_config_outputs_summary() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/core.sh"

    export ABF_LOG_DIR="/tmp"
    export ABF_STORAGE_BACKEND="local"

    local output
    output=$(abf_validate_config 2>/dev/null || true)

    if ! echo "$output" | grep -q "error(s)\|warning(s)\|valid"; then
        echo "  FAIL: Validation output should contain summary"
        return 1
    fi
    return 0
}

test_validate_config_reports_all_errors() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/core.sh"

    unset ABF_LOG_DIR
    export ABF_STORAGE_BACKEND="local"

    local output
    output=$(abf_validate_config 2>/dev/null || true)

    assert_contains "$output" "ABF_LOG_DIR" "Reports missing ABF_LOG_DIR"
    assert_contains "$output" "error(s)" "Summary shows error count"
    return 0
}

test_validate_config_with_warnings() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/core.sh"

    export ABF_LOG_DIR="/tmp"
    export ABF_STORAGE_BACKEND="local"

    local output
    output=$(abf_validate_config 2>/dev/null || true)

    if ! echo "$output" | grep -q "\[WARN\]\|\[ERROR\]"; then
        assert_contains "$output" "valid" "Clean config with missing optional deps shows valid"
    fi
    return 0
}
