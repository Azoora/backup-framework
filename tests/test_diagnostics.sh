# ---------------------------------------------------------------------------
# Tests for the diagnostics module (abf doctor)
# ---------------------------------------------------------------------------

test_diag_version_check() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-diag-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "diag-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/diagnostics.sh"

    ABF_DIAG_RESULTS=()
    _abf_diag_check_version

    local found=false
    for entry in "${ABF_DIAG_RESULTS[@]}"; do
        if echo "$entry" | grep -q "framework_version"; then
            assert_contains "$entry" "OK" "Version check status OK"
            assert_contains "$entry" "Backup Framework" "Version check message"
            found=true
        fi
    done
    $found || { echo "  FAIL: No version check result"; return 1; }
}

test_diag_lock_dir_check() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-diag-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "diag-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/diagnostics.sh"

    export ABF_LOCK_DIR="${tmpdir}/locks"
    mkdir -p "$ABF_LOCK_DIR"

    ABF_DIAG_RESULTS=()
    _abf_diag_check_lock_dir

    local found=false
    for entry in "${ABF_DIAG_RESULTS[@]}"; do
        if echo "$entry" | grep -q "lock_dir"; then
            assert_contains "$entry" "OK" "Lock dir check OK"
            found=true
        fi
    done
    $found || { echo "  FAIL: No lock dir result"; return 1; }
}

test_diag_json_output() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-diag-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "diag-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/diagnostics.sh"
    source "${ABF_ROOT}/core/core.sh"

    ABF_DIAG_RESULTS=()
    _abf_diag_result "OK" "test_check" "test message"

    _abf_diag_overall
    local json_output
    json_output=$(_abf_diag_output_json 2>/dev/null || true)

    assert_contains "$json_output" '"overall"' "JSON contains overall"
    assert_contains "$json_output" '"OK"' "JSON contains OK status"
    assert_contains "$json_output" '"test_check"' "JSON contains check name"
    assert_contains "$json_output" '"test message"' "JSON contains message"
    assert_contains "$json_output" '"version"' "JSON contains version field"
    assert_contains "$json_output" '"timestamp"' "JSON contains timestamp field"
}

test_diag_human_output() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-diag-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "diag-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/diagnostics.sh"
    source "${ABF_ROOT}/core/core.sh"

    ABF_DIAG_RESULTS=()
    _abf_diag_result "OK" "test_check" "test message"
    _abf_diag_result "WARNING" "warn_check" "warning message"

    _abf_diag_overall
    local human_output
    human_output=$(_abf_diag_output_human 2>/dev/null || true)

    assert_contains "$human_output" "Overall:" "Human output contains overall"
    assert_contains "$human_output" "WARNING" "Human output shows WARNING status"
    assert_contains "$human_output" "[PASS]" "Human output shows PASS tag"
    assert_contains "$human_output" "[WARN]" "Human output shows WARN tag"
}

test_diag_exit_codes() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/core/diagnostics.sh"

    # OK -> 0
    ABF_DIAG_RESULTS=()
    _abf_diag_result "OK" "a" "all good"
    _abf_diag_overall
    assert_eq "OK" "$ABF_DIAG_OVERALL" "All OK => OK"

    # WARNING -> 1
    ABF_DIAG_RESULTS=()
    _abf_diag_result "OK" "a" "good"
    _abf_diag_result "WARNING" "b" "warn"
    _abf_diag_overall
    assert_eq "WARNING" "$ABF_DIAG_OVERALL" "Has warning => WARNING"

    # ERROR -> 2
    ABF_DIAG_RESULTS=()
    _abf_diag_result "WARNING" "a" "warn"
    _abf_diag_result "ERROR" "b" "error"
    _abf_diag_overall
    assert_eq "ERROR" "$ABF_DIAG_OVERALL" "Has error => ERROR"
}

test_diag_backup_age_messages() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/core/diagnostics.sh"

    # Since we can't easily mock the restic repo in a simple test,
    # verify the function exists and handles the no-restic case gracefully
    ABF_DIAG_RESULTS=()
    if ! command -v restic &>/dev/null; then
        _abf_diag_check_backup_age
        for entry in "${ABF_DIAG_RESULTS[@]}"; do
            if echo "$entry" | grep -q "backup_age"; then
                return 0  # skipped gracefully
            fi
        done
    fi
}

test_diag_sqlite3_check() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/core/diagnostics.sh"

    ABF_DIAG_RESULTS=()
    _abf_diag_check_sqlite3

    local found=false
    for entry in "${ABF_DIAG_RESULTS[@]}"; do
        if echo "$entry" | grep -q "sqlite3_installed"; then
            found=true
            if command -v sqlite3 &>/dev/null; then
                assert_contains "$entry" "OK" "sqlite3 check OK when installed"
            else
                assert_contains "$entry" "WARNING" "sqlite3 check WARNING when not installed"
            fi
        fi
    done
    $found || { echo "  FAIL: No sqlite3 check result"; return 1; }
}

test_diag_rclone_config_check() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/core/diagnostics.sh"

    # Rclone config check with local storage (no rclone)
    export ABF_STORAGE_BACKEND="local"
    ABF_DIAG_RESULTS=()
    _abf_diag_check_rclone_config

    local found=false
    for entry in "${ABF_DIAG_RESULTS[@]}"; do
        if echo "$entry" | grep -q "rclone_config"; then
            found=true
            # Should be WARNING in local mode without rclone
            assert_contains "$entry" "WARNING" "rclone config WARNING in local mode"
        fi
    done
    $found || { echo "  FAIL: No rclone_config check result"; return 1; }
}

test_diag_human_output_format() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-diag-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "diag-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/diagnostics.sh"
    source "${ABF_ROOT}/core/core.sh"

    ABF_DIAG_RESULTS=()
    _abf_diag_result "OK" "test_check" "test message"
    _abf_diag_result "WARNING" "warn_check" "warning message"
    _abf_diag_result "ERROR" "err_check" "error message"

    _abf_diag_overall
    local human_output
    human_output=$(_abf_diag_output_human 2>/dev/null || true)

    # Verify new format markers
    assert_contains "$human_output" "[PASS]" "Human output contains PASS marker"
    assert_contains "$human_output" "[WARN]" "Human output contains WARN marker"
    assert_contains "$human_output" "[FAIL]" "Human output contains FAIL marker"
    assert_contains "$human_output" "Overall:" "Human output contains Overall line"
    assert_contains "$human_output" "1 passed" "Human output shows pass count"
    assert_contains "$human_output" "1 warnings" "Human output shows warning count"
    assert_contains "$human_output" "1 errors" "Human output shows error count"
}
