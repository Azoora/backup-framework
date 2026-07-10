# ---------------------------------------------------------------------------
# Tests for the OneDrive (Rclone) destination module
# ---------------------------------------------------------------------------

test_onedrive_destination_module_exists() {
    if [[ ! -f "${ABF_ROOT}/destinations/onedrive/module.sh" ]]; then
        echo "  FAIL: OneDrive destination module not found"
        return 1
    fi
    return 0
}

test_onedrive_destination_registered_in_manifest() {
    if ! grep -q "^onedrive$" "${ABF_ROOT}/destinations/manifest.conf"; then
        echo "  FAIL: OneDrive destination not registered in manifest"
        return 1
    fi
    return 0
}

test_onedrive_destination_name() {
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/destinations/onedrive/module.sh"

    local name
    name=$(destination_name)
    assert_eq "OneDrive" "$name" "Destination display name"
}

test_onedrive_destination_defaults() {
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/destinations/onedrive/module.sh"

    assert_eq "OneDrive" "$ONEDRIVE_REMOTE" "Default remote name"
    assert_eq "Backups/BackupFramework" "$ONEDRIVE_PATH" "Default remote path"

    return 0
}

test_onedrive_destination_check_fails_without_rclone() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-dest-onedrive-XXXXXX")

    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/destinations/onedrive/module.sh"

    local real_path="$PATH"
    export PATH="/dev/null"

    if destination_check 2>/dev/null; then
        export PATH="$real_path"
        echo "  FAIL: destination_check should fail without rclone"
        return 1
    fi
    export PATH="$real_path"
    return 0
}

test_onedrive_destination_fails_without_rclone() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-dest-onedrive-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "onedrive-dest-test" "test" "${tmpdir}/logs"

    source "${ABF_ROOT}/destinations/onedrive/module.sh"

    local real_path="$PATH"
    export PATH="/dev/null"

    if destination_sync "/tmp/repo" 2>/dev/null; then
        export PATH="$real_path"
        echo "  FAIL: destination_sync should fail without rclone"
        return 1
    fi
    export PATH="$real_path"
    return 0
}

test_onedrive_destination_config_is_customizable() {
    source "${ABF_ROOT}/core/log.sh"

    export ONEDRIVE_REMOTE="myremote"
    export ONEDRIVE_PATH="my/custom/path"
    source "${ABF_ROOT}/destinations/onedrive/module.sh"

    assert_eq "myremote" "$ONEDRIVE_REMOTE" "Custom remote name"
    assert_eq "my/custom/path" "$ONEDRIVE_PATH" "Custom remote path"

    return 0
}

test_onedrive_destination_skips_on_unknown_repo() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-dest-onedrive-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "onedrive-dest-test" "test" "${tmpdir}/logs"

    source "${ABF_ROOT}/destinations/onedrive/module.sh"

    if destination_sync "s3:some-bucket/repo" 2>/dev/null; then
        echo "  FAIL: destination_sync should fail on unsupported repo type"
        return 1
    fi
    return 0
}
