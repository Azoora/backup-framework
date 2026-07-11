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

# ==================================================================
# Repository diagnostic regression tests
#
# These tests reproduce the real production bug where 'abf doctor'
# reported "Repository unreachable" immediately after a successful
# backup. The root cause was diagnotic checks using -f (file exists)
# instead of -r (file is readable) for the restic password file.
# ==================================================================

test_diag_repository_accessible_with_snapshot() {
    if ! command -v restic &>/dev/null; then
        echo "  SKIP: restic not installed"
        return 0
    fi

    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-diag-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "diag-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/restic.sh"
    source "${ABF_ROOT}/core/diagnostics.sh"

    local repo="${tmpdir}/repo"
    local pw_file="${tmpdir}/restic-password"
    echo "test-pw" > "$pw_file"
    chmod 600 "$pw_file"

    restic init -r "$repo" --password-file "$pw_file" &>/dev/null || {
        echo "  FAIL: restic init failed"
        rm -rf "$tmpdir"
        return 1
    }

    echo "snapshot-data" > "${tmpdir}/data.txt"
    restic -r "$repo" --password-file "$pw_file" backup "${tmpdir}/data.txt" &>/dev/null || {
        echo "  FAIL: restic backup failed"
        rm -rf "$tmpdir"
        return 1
    }

    # Use a global variable so the mock function works inside subshells
    export DIAG_TEST_REPO="$repo"
    _abf_get_storage_repo() { echo "$DIAG_TEST_REPO"; }
    export ABF_RESTIC_PASSWORD_FILE="$pw_file"

    # ---- Test repository check ----
    ABF_DIAG_RESULTS=()
    _abf_diag_check_repository
    local repo_ok=false
    for entry in "${ABF_DIAG_RESULTS[@]}"; do
        if echo "$entry" | grep -q "repository"; then
            assert_contains "$entry" "OK" "Repository reachable after backup"
            assert_contains "$entry" "$repo" "Message includes repo path"
            repo_ok=true
        fi
    done
    $repo_ok || { echo "  FAIL: No repository check result"; rm -rf "$tmpdir"; return 1; }

    # ---- Test backup age check ----
    ABF_DIAG_RESULTS=()
    _abf_diag_check_backup_age
    local age_found=false
    for entry in "${ABF_DIAG_RESULTS[@]}"; do
        if echo "$entry" | grep -q "backup_age"; then
            assert_contains "$entry" "OK" "Backup age OK after recent snapshot"
            assert_contains "$entry" "day(s)" "Message includes age"
            age_found=true
        fi
    done
    $age_found || { echo "  FAIL: No backup age result"; rm -rf "$tmpdir"; return 1; }

    # Cleanup
    unset DIAG_TEST_REPO
    rm -rf "$tmpdir"
    return 0
}

test_diag_repository_unreadable_password_file() {
    if ! command -v restic &>/dev/null; then
        echo "  SKIP: restic not installed"
        return 0
    fi

    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-diag-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "diag-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/restic.sh"
    source "${ABF_ROOT}/core/diagnostics.sh"

    local repo="${tmpdir}/repo"
    local pw_file="${tmpdir}/restic-password"
    echo "test-pw" > "$pw_file"

    restic init -r "$repo" --password-file "$pw_file" &>/dev/null || {
        echo "  FAIL: restic init failed"
        rm -rf "$tmpdir"
        return 1
    }

    echo "snapshot-data" > "${tmpdir}/data.txt"
    restic -r "$repo" --password-file "$pw_file" backup "${tmpdir}/data.txt" &>/dev/null || {
        echo "  FAIL: restic backup failed"
        rm -rf "$tmpdir"
        return 1
    }

    # Simulate the production scenario: password file exists but is NOT readable
    # by the current user (e.g. root-owned mode 600, non-root doctor)
    chmod 000 "$pw_file"

    export DIAG_TEST_REPO="$repo"
    _abf_get_storage_repo() { echo "$DIAG_TEST_REPO"; }
    export ABF_RESTIC_PASSWORD_FILE="$pw_file"

    # ---- Repository check must detect unreadable password ----
    ABF_DIAG_RESULTS=()
    _abf_diag_check_repository || true
    local repo_err=false
    for entry in "${ABF_DIAG_RESULTS[@]}"; do
        if echo "$entry" | grep -q "repository"; then
            assert_contains "$entry" "ERROR" "Repository check ERROR for unreadable password"
            assert_contains "$entry" "is not readable" "Message says 'not readable' not 'unreachable'"
            assert_contains "$entry" "sudo abf doctor" "Message suggests 'sudo abf doctor'"
            repo_err=true
        fi
    done
    $repo_err || { unset DIAG_TEST_REPO; chmod 600 "$pw_file"; rm -rf "$tmpdir"; return 1; }

    # ---- Backup age check must skip cleanly (no restic call) ----
    ABF_DIAG_RESULTS=()
    _abf_diag_check_backup_age || true
    local age_empty=true
    for entry in "${ABF_DIAG_RESULTS[@]}"; do
        if echo "$entry" | grep -q "backup_age"; then
            age_empty=false
        fi
    done
    $age_empty || { unset DIAG_TEST_REPO; chmod 600 "$pw_file"; rm -rf "$tmpdir"; return 1; }

    unset DIAG_TEST_REPO
    chmod 600 "$pw_file"
    rm -rf "$tmpdir"
    return 0
}

test_diag_repository_missing_password_file() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-diag-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "diag-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/diagnostics.sh"

    local repo="${tmpdir}/repo"
    export DIAG_TEST_REPO="$repo"
    _abf_get_storage_repo() { echo "$DIAG_TEST_REPO"; }
    export ABF_RESTIC_PASSWORD_FILE="${tmpdir}/nonexistent-pw"

    ABF_DIAG_RESULTS=()
    _abf_diag_check_repository || true
    local found_err=false
    for entry in "${ABF_DIAG_RESULTS[@]}"; do
        if echo "$entry" | grep -q "repository"; then
            assert_contains "$entry" "ERROR" "Repository check ERROR for missing password file"
            assert_contains "$entry" "not found" "Message says 'not found' not 'not readable'"
            found_err=true
        fi
    done
    $found_err || { unset DIAG_TEST_REPO; rm -rf "$tmpdir"; return 1; }

    unset DIAG_TEST_REPO
    rm -rf "$tmpdir"
    return 0
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
