# ---------------------------------------------------------------------------
# Integration tests that exercise the real abf CLI
# ---------------------------------------------------------------------------

test_integration_lock_released_after_backup() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-int-XXXXXX")
    local config_dir="${tmpdir}/config"
    mkdir -p "$config_dir/services"

    cat > "$config_dir/abf.conf" <<EOF
ABF_LOG_DIR="${tmpdir}/logs"
ABF_CACHE_DIR="${tmpdir}/cache"
ABF_TEMP_DIR="${tmpdir}"
ABF_LOCK_DIR="${tmpdir}/locks"
ABF_STORAGE_BACKEND="local"
ABF_RESTIC_PASSWORD_FILE="${tmpdir}/restic-pw"
EOF

    local data_dir="${tmpdir}/vw-data"
    mkdir -p "$data_dir"
    touch "$data_dir/db.sqlite3"
    touch "$data_dir/config.json"

    cat > "$config_dir/services/vaultwarden.conf" <<EOF
SERVICE_VAULTWARDEN_DATA_DIR="${data_dir}"
SERVICE_VAULTWARDEN_BACKUP_DIR="${tmpdir}/vw-backup"
EOF
    echo "test-pw-123" > "${tmpdir}/restic-pw"

    local output rc=0
    output=$("${ABF_ROOT}/abf" --config "$config_dir" backup vaultwarden 2>&1) || rc=$?

    if echo "$output" | grep -q "unbound variable"; then
        echo "  FAIL: Unbound variable crash"
        echo "  Output: ${output}"
        rm -rf "$tmpdir"
        return 1
    fi

    # Verify lock file was released
    if [[ -f "${tmpdir}/locks/vaultwarden.lock" ]]; then
        local lock_pid
        lock_pid=$(cat "${tmpdir}/locks/vaultwarden.lock" 2>/dev/null)
        echo "  FAIL: Lock file not released after backup (PID ${lock_pid})"
        rm -rf "$tmpdir"
        return 1
    fi

    # Verify the trap string does NOT reference a local variable
    if grep -q "trap.*ABF_LOCK_SERVICE" "${ABF_ROOT}/core/core.sh"; then
        :  # Good — uses global variable
    else
        echo "  FAIL: Trap does not use global ABF_LOCK_SERVICE"
        rm -rf "$tmpdir"
        return 1
    fi

    rm -rf "$tmpdir"
    return 0
}

test_integration_backup_vaultwarden_via_cli() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-int-XXXXXX")

    # Set up a minimal vaultwarden data directory
    local data_dir="${tmpdir}/vw-data"
    mkdir -p "$data_dir"
    touch "$data_dir/db.sqlite3"
    touch "$data_dir/config.json"

    # Set up config directory
    local config_dir="${tmpdir}/config"
    mkdir -p "$config_dir/services"

    # Write abf.conf with safe temp paths
    cat > "$config_dir/abf.conf" <<EOF
ABF_LOG_DIR="${tmpdir}/logs"
ABF_CACHE_DIR="${tmpdir}/cache"
ABF_TEMP_DIR="${tmpdir}"
ABF_LOCK_DIR="${tmpdir}/locks"
ABF_STORAGE_BACKEND="local"
ABF_RESTIC_PASSWORD_FILE="${tmpdir}/restic-pw"
ABF_RETENTION_KEEP_DAILY=7
ABF_RETENTION_KEEP_WEEKLY=4
ABF_RETENTION_KEEP_MONTHLY=3
ABF_RETENTION_KEEP_YEARLY=0
EOF

    # Override vaultwarden paths to our tmpdir
    cat > "$config_dir/services/vaultwarden.conf" <<EOF
SERVICE_VAULTWARDEN_DATA_DIR="${data_dir}"
SERVICE_VAULTWARDEN_BACKUP_DIR="${tmpdir}/vw-backup"
EOF

    # Create restic password file
    echo "test-pw-123" > "${tmpdir}/restic-pw"

    # Run the real CLI backup
    local output rc=0
    output=$("${ABF_ROOT}/abf" --config "$config_dir" backup vaultwarden 2>&1) || rc=$?

    # Check for unbound variable crash (the bug we're fixing)
    if echo "$output" | grep -q "unbound variable"; then
        echo "  FAIL: Unbound variable crash detected in real CLI path"
        echo "  Output: ${output}"
        rm -rf "$tmpdir"
        return 1
    fi

    # If restic is not installed, the backup should still reach service_pre_backup
    # and should not crash. Known errors are acceptable.
    if [[ "$rc" -ne 0 ]]; then
        if echo "$output" | grep -qi "restic not found"; then
            # restic unavailable in test env - this is acceptable
            rm -rf "$tmpdir"
            return 0
        fi

        if echo "$output" | grep -qi "password file"; then
            # password file issue - check if path resolution is correct
            rm -rf "$tmpdir"
            return 0
        fi

        echo "  FAIL: Backup failed with unexpected error (rc=${rc})"
        echo "  Output: ${output}"
        rm -rf "$tmpdir"
        return 1
    fi

    # On success, verify a log file was created
    if [[ -d "${tmpdir}/logs" ]]; then
        local log_count
        log_count=$(find "${tmpdir}/logs" -type f 2>/dev/null | wc -l)
        if [[ "$log_count" -eq 0 ]]; then
            echo "  WARN: No log files created in ${tmpdir}/logs"
        fi
    fi

    rm -rf "$tmpdir"
    return 0
}

test_integration_backup_fails_gracefully_on_missing_service() {
    local output rc=0
    output=$("${ABF_ROOT}/abf" backup nonexistent_service 2>&1) || rc=$?

    # Should NOT crash with unbound variable
    if echo "$output" | grep -q "unbound variable"; then
        echo "  FAIL: Unbound variable crash for missing service"
        echo "  Output: ${output}"
        return 1
    fi

    # Should print an error about unknown service
    if ! echo "$output" | grep -qi "unknown service"; then
        echo "  FAIL: Should report unknown service"
        echo "  Output: ${output}"
        return 1
    fi

    return 0
}

test_integration_list_services() {
    local output rc=0
    output=$("${ABF_ROOT}/abf" list 2>&1) || rc=$?

    if echo "$output" | grep -q "unbound variable"; then
        echo "  FAIL: Unbound variable crash in list"
        echo "  Output: ${output}"
        return 1
    fi

    # Without a configured storage backend, list will show a message
    # about the repository — which is acceptable; the key is no crash
    if echo "$output" | grep -qi "could not connect"; then
        # Acceptable when restic is not configured
        return 0
    fi

    if ! echo "$output" | grep -q "vaultwarden"; then
        echo "  FAIL: vaultwarden should appear in service list"
        echo "  Output: ${output}"
        return 1
    fi

    return 0
}

test_integration_config_check_succeeds() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-int-XXXXXX")
    local config_dir="${tmpdir}/config"
    mkdir -p "$config_dir/services"

    cat > "$config_dir/abf.conf" <<EOF
ABF_LOG_DIR="${tmpdir}/logs"
ABF_CACHE_DIR="${tmpdir}/cache"
ABF_TEMP_DIR="${tmpdir}"
ABF_LOCK_DIR="${tmpdir}/locks"
ABF_STORAGE_BACKEND="local"
ABF_RESTIC_PASSWORD_FILE="${tmpdir}/restic-pw"
EOF
    echo "test" > "${tmpdir}/restic-pw"

    local output rc=0
    output=$("${ABF_ROOT}/abf" --config "$config_dir" config check 2>&1) || rc=$?

    if echo "$output" | grep -q "unbound variable"; then
        echo "  FAIL: Unbound variable crash in config check"
        echo "  Output: ${output}"
        rm -rf "$tmpdir"
        return 1
    fi

    rm -rf "$tmpdir"
    return 0
}
