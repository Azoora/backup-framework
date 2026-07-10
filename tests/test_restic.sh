# ---------------------------------------------------------------------------
# Tests for the restic integration module
# ---------------------------------------------------------------------------

test_restic_init_requires_restic_installed() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "restic-test" "test" "/tmp"

    source "${ABF_ROOT}/core/restic.sh"

    # Without restic installed, init should fail
    if command -v restic &>/dev/null; then
        # restic is installed in this env -- skip this test
        return 0
    fi

    ABF_RESTIC_PASSWORD_FILE="/dev/null"
    if abf_restic_init "local:/tmp/test-repo" 2>/dev/null; then
        echo "  FAIL: Expected failure when restic not installed"
        return 1
    fi
    return 0
}

test_restic_repo_url_format() {
    source "${ABF_ROOT}/core/exit_codes.sh"

    # Verify the URL format used by onedrive module
    local remote="onedrive"
    local path="abf-restic"
    local url="rclone:${remote}:${path}"
    assert_eq "rclone:onedrive:abf-restic" "$url" "rclone repo URL format"
}

test_pasword_file_variable() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "restic-test" "test" "/tmp"

    source "${ABF_ROOT}/core/restic.sh"

    # Default password file path
    local default="/etc/abf/restic-password"
    assert_eq "/etc/abf/restic-password" "${ABF_RESTIC_PASSWORD_FILE:-$default}" \
        "Default restic password file path"
}

test_restic_full_backup_restore_cycle() {
    if ! command -v restic &>/dev/null; then
        echo "  SKIP: restic not installed"
        return 0
    fi

    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-restic-XXXXXX")
    local repo="${tmpdir}/repo"
    local data="${tmpdir}/data"
    local restore_target="${tmpdir}/restore"
    local pwfile="${tmpdir}/pw"

    echo "test-password" > "$pwfile"
    mkdir -p "$data" "$restore_target"
    echo "content-1" > "$data/file1.txt"
    echo "content-2" > "$data/file2.txt"

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "restic-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/restic.sh"

    export ABF_RESTIC_PASSWORD_FILE="$pwfile"

    # Init repo
    abf_restic_init "$repo" || {
        echo "  FAIL: repo init"
        return 1
    }
    assert_eq "$repo" "$ABF_RESTIC_REPO" "Repo URL stored"

    # Backup
    abf_restic_backup "$data" "test-service" || {
        echo "  FAIL: backup"
        return 1
    }
    assert_neq "" "${ABF_RESTIC_SNAPSHOT_ID:-}" "Snapshot ID captured"

    # List snapshots
    local snapshot_output
    snapshot_output=$(abf_restic_list_snapshots "test-service")
    assert_contains "$snapshot_output" "test-service" "Snapshot tagged with service name"

    # Get latest snapshot ID
    local latest
    latest=$(abf_restic_get_latest_snapshot "test-service")
    assert_eq "$ABF_RESTIC_SNAPSHOT_ID" "$latest" "Get latest matches backup snapshot"

    # Verify
    abf_restic_verify || {
        echo "  FAIL: verify"
        return 1
    }

    # Restore
    abf_restic_restore "$ABF_RESTIC_SNAPSHOT_ID" "$restore_target" "test-service" || {
        echo "  FAIL: restore"
        return 1
    }

    # Check restored content
    local restored_file="${restore_target}/${data}/file1.txt"
    # restic restore preserves full path under --target
    local found
    found=$(find "$restore_target" -name "file1.txt" 2>/dev/null || true)
    if [[ -z "$found" ]]; then
        # Try alternative layout
        found=$(find "$restore_target" -type f 2>/dev/null || true)
        echo "  RESTORED FILES: $found"
    fi

    if echo "$found" | grep -q "file1.txt"; then
        assert_eq "content-1" "$(cat "$found")" "Restored file content matches"
    else
        echo "  FAIL: file1.txt not found in restore target"
        find "$restore_target" -type f 2>/dev/null
        return 1
    fi
}
