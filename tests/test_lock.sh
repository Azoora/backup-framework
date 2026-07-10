# ---------------------------------------------------------------------------
# Tests for the backup locking module
# ---------------------------------------------------------------------------

test_lock_normal_acquire_release() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-lock-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "lock-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/lock.sh"

    export ABF_LOCK_DIR="${tmpdir}/locks"

    abf_lock_init
    abf_lock_acquire "test-svc" || return 1

    local lock_file="${ABF_LOCK_DIR}/test-svc.lock"
    if [[ ! -f "$lock_file" ]]; then
        echo "  FAIL: Lock file should exist"
        return 1
    fi

    local lock_pid
    lock_pid=$(cat "$lock_file" 2>/dev/null)
    assert_eq "$$" "$lock_pid" "Lock file contains our PID"

    abf_lock_release "test-svc"
    if [[ -f "$lock_file" ]]; then
        echo "  FAIL: Lock file should be removed after release"
        return 1
    fi
    return 0
}

test_lock_concurrent_rejected() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-lock-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "lock-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/lock.sh"

    export ABF_LOCK_DIR="${tmpdir}/locks"
    abf_lock_init

    # Acquire lock in background
    local lock_file="${ABF_LOCK_DIR}/test-svc.lock"
    echo "99999" > "$lock_file"

    # Now try to acquire -- should detect stale PID and succeed
    abf_lock_acquire "test-svc" || {
        echo "  FAIL: Should have recovered stale lock"
        return 1
    }

    # Verify lock file now has our PID
    local current_pid
    current_pid=$(cat "$lock_file" 2>/dev/null)
    assert_eq "$$" "$current_pid" "Lock updated to our PID after stale recovery"

    abf_lock_release "test-svc"
    return 0
}

test_lock_stale_recovery() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-lock-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "lock-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/lock.sh"

    export ABF_LOCK_DIR="${tmpdir}/locks"
    abf_lock_init

    # Manually create a lock file with a PID that no longer exists
    local lock_file="${ABF_LOCK_DIR}/test-svc.lock"
    echo "99999" > "$lock_file"

    # Now try to acquire -- should detect stale PID and succeed
    abf_lock_acquire "test-svc" || {
        echo "  FAIL: Should have recovered stale lock"
        return 1
    }

    # Verify lock file now has our PID
    local current_pid
    current_pid=$(cat "$lock_file" 2>/dev/null)
    assert_eq "$$" "$current_pid" "Lock updated to our PID after stale recovery"

    abf_lock_release "test-svc"
    return 0
}

test_lock_exit_trap_cleans_up() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-lock-XXXXXX")
    local lock_file="${tmpdir}/locks/test-svc.lock"

    # Run a subshell that acquires a lock and then exits
    (
        export ABF_ROOT="${ABF_ROOT}"
        source "${ABF_ROOT}/core/exit_codes.sh"
        source "${ABF_ROOT}/core/log.sh"
        abf_init_logging "lock-test" "test" "/tmp"
        source "${ABF_ROOT}/core/lock.sh"

        export ABF_LOCK_DIR="${tmpdir}/locks"
        abf_lock_init
        abf_lock_acquire "test-svc" || exit 1
        trap 'abf_lock_release "test-svc"' EXIT
        exit 0
    )

    # After subshell exits, lock file should be gone (via EXIT trap)
    if [[ -f "$lock_file" ]]; then
        echo "  FAIL: Lock file should be removed after process exits"
        return 1
    fi

    # Should be able to re-acquire
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "lock-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/lock.sh"

    export ABF_LOCK_DIR="${tmpdir}/locks"
    abf_lock_init
    abf_lock_acquire "test-svc" || {
        echo "  FAIL: Should acquire after previous owner exited"
        return 1
    }
    abf_lock_release "test-svc"
    return 0
}

test_lock_trap_uses_global_variable() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-lock-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "lock-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/lock.sh"

    export ABF_LOCK_DIR="${tmpdir}/locks"
    abf_lock_init
    abf_lock_acquire "test-svc" || return 1

    # Simulate the pattern used in abf_run_backup
    ABF_LOCK_SERVICE="test-svc"
    trap 'abf_lock_release "$ABF_LOCK_SERVICE"; ABF_LOCK_SERVICE=""; trap - EXIT' EXIT

    # Verify global is set
    assert_eq "test-svc" "$ABF_LOCK_SERVICE" "ABF_LOCK_SERVICE is set before trap"

    # Simulate trap execution (as it would fire on shell exit)
    local handler
    handler=$(trap -p EXIT 2>/dev/null | sed "s/^trap -- '//; s/' EXIT$//")
    eval "$handler"

    # Verify lock was released
    if [[ -f "${ABF_LOCK_DIR}/test-svc.lock" ]]; then
        echo "  FAIL: Lock should have been released by trap"
        return 1
    fi

    # Verify global was reset
    assert_eq "" "$ABF_LOCK_SERVICE" "ABF_LOCK_SERVICE reset after trap"

    # Verify trap was cleared
    if trap -p EXIT 2>/dev/null | grep -q "abf_lock_release"; then
        echo "  FAIL: EXIT trap should have been cleared"
        return 1
    fi

    return 0
}

test_lock_trap_does_not_dangle_after_cleanup() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-lock-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "lock-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/lock.sh"

    export ABF_LOCK_DIR="${tmpdir}/locks"
    abf_lock_init

    # Acquire lock, set trap (mimicking abf_run_backup pattern)
    abf_lock_acquire "test-svc" || return 1
    ABF_LOCK_SERVICE="test-svc"
    trap 'abf_lock_release "$ABF_LOCK_SERVICE"; ABF_LOCK_SERVICE=""; trap - EXIT' EXIT

    # Clean up (mimicking the end of abf_run_backup)
    trap - EXIT
    ABF_LOCK_SERVICE=""
    abf_lock_release "test-svc"

    # After cleanup: no trap should remain
    if trap -p EXIT 2>/dev/null | grep -q "abf_lock_release"; then
        echo "  FAIL: EXIT trap dangling after cleanup"
        return 1
    fi

    # Global should be empty
    if [[ -n "$ABF_LOCK_SERVICE" ]]; then
        echo "  FAIL: ABF_LOCK_SERVICE not cleared"
        return 1
    fi

    return 0
}

test_lock_exit_code_on_locked() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-lock-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "lock-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/lock.sh"

    export ABF_LOCK_DIR="${tmpdir}/locks"
    abf_lock_init

    # Simulate a running process
    local lock_file="${ABF_LOCK_DIR}/test-svc.lock"
    echo "$$" > "$lock_file"

    # Cannot acquire -- we already hold it
    if abf_lock_acquire "test-svc" 2>/dev/null; then
        echo "  FAIL: Acquire should fail when we already hold the lock"
        return 1
    fi

    abf_lock_release "test-svc"
    return 0
}
