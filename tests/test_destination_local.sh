# ---------------------------------------------------------------------------
# Tests for the local filesystem destination module
# ---------------------------------------------------------------------------

test_local_destination_module_exists() {
    if [[ ! -f "${ABF_ROOT}/destinations/local/module.sh" ]]; then
        echo "  FAIL: Local destination module not found"
        return 1
    fi
    return 0
}

test_local_destination_registered_in_manifest() {
    if ! grep -q "^local$" "${ABF_ROOT}/destinations/manifest.conf"; then
        echo "  FAIL: Local destination not registered in manifest"
        return 1
    fi
    return 0
}

test_local_destination_name() {
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/destinations/local/module.sh"

    local name
    name=$(destination_name)
    assert_eq "Local" "$name" "Destination display name"
}

test_local_destination_sync_creates_dest_dir() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-dest-local-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "local-dest-test" "test" "${tmpdir}/logs"

    local src_repo="${tmpdir}/source-repo"
    mkdir -p "$src_repo"
    echo "test-config" > "${src_repo}/config"
    mkdir -p "${src_repo}/index" "${src_repo}/snapshots" "${src_repo}/data"
    echo "test-data" > "${src_repo}/index/test"

    export DESTINATION_LOCAL_PATH="${tmpdir}/dest-repo/restic"
    source "${ABF_ROOT}/destinations/local/module.sh"

    if ! destination_sync "$src_repo"; then
        echo "  FAIL: destination_sync should succeed"
        return 1
    fi

    if [[ ! -d "${tmpdir}/dest-repo/restic" ]]; then
        echo "  FAIL: Destination directory was not created"
        return 1
    fi

    if [[ ! -f "${tmpdir}/dest-repo/restic/config" ]]; then
        echo "  FAIL: config file not present at destination"
        return 1
    fi

    return 0
}

test_local_destination_sync_fails_on_missing_source() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-dest-local-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "local-dest-test" "test" "${tmpdir}/logs"

    export DESTINATION_LOCAL_PATH="${tmpdir}/dest-repo"
    source "${ABF_ROOT}/destinations/local/module.sh"

    if destination_sync "/nonexistent/path" 2>/dev/null; then
        echo "  FAIL: destination_sync should fail on missing source"
        return 1
    fi
    return 0
}

test_local_destination_sync_fails_on_readonly_dest() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-dest-local-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "local-dest-test" "test" "${tmpdir}/logs"

    local src_repo="${tmpdir}/source-repo"
    mkdir -p "$src_repo"
    echo "test-config" > "${src_repo}/config"

    local dest_parent="${tmpdir}/readonly"
    mkdir -p "$dest_parent"
    chmod 0444 "$dest_parent"

    export DESTINATION_LOCAL_PATH="${dest_parent}/restic"
    source "${ABF_ROOT}/destinations/local/module.sh"

    if destination_sync "$src_repo" 2>/dev/null; then
        echo "  FAIL: destination_sync should fail on read-only parent"
        return 1
    fi
    return 0
}

test_local_destination_skips_remote_source() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-dest-local-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "local-dest-test" "test" "${tmpdir}/logs"

    export DESTINATION_LOCAL_PATH="${tmpdir}/dest-repo"
    source "${ABF_ROOT}/destinations/local/module.sh"

    if destination_sync "rclone:remote:path" 2>/dev/null; then
        echo "  FAIL: destination_sync should fail on rclone source"
        return 1
    fi
    return 0
}

test_local_destination_default_path_is_umbrel_mount() {
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/destinations/local/module.sh"

    local default_path="$DESTINATION_LOCAL_PATH"
    assert_contains "$default_path" "/mnt/umbrel" "Default path targets Umbrel mount"

    return 0
}

test_local_destination_sync_preserves_files() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-dest-local-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "local-dest-test" "test" "${tmpdir}/logs"

    local src_repo="${tmpdir}/source-repo"
    mkdir -p "$src_repo"
    echo "config-content" > "${src_repo}/config"
    mkdir -p "${src_repo}/index"
    echo "index-data" > "${src_repo}/index/test"

    export DESTINATION_LOCAL_PATH="${tmpdir}/dest-repo"
    source "${ABF_ROOT}/destinations/local/module.sh"

    destination_sync "$src_repo" || {
        echo "  FAIL: destination_sync failed"
        return 1
    }

    local dest_content
    dest_content=$(cat "${tmpdir}/dest-repo/config")
    assert_eq "config-content" "$dest_content" "Config file content preserved"

    return 0
}
