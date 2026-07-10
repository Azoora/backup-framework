# ---------------------------------------------------------------------------
# Tests for the local filesystem storage module
# ---------------------------------------------------------------------------

test_local_storage_module_exists() {
    if [[ ! -f "${ABF_ROOT}/storage/local/module.sh" ]]; then
        echo "  FAIL: Local storage module not found"
        return 1
    fi
    return 0
}

test_local_storage_registered_in_manifest() {
    if ! grep -q "^local$" "${ABF_ROOT}/storage/manifest.conf"; then
        echo "  FAIL: Local storage not registered in manifest"
        return 1
    fi
    return 0
}

test_local_storage_get_repo_url_default() {
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/storage/local/module.sh"

    local url
    url=$(storage_get_repo_url)
    assert_eq "/var/backups/abf/restic" "$url" "Default repo path"
}

test_local_storage_get_repo_url_custom() {
    source "${ABF_ROOT}/core/log.sh"
    export STORAGE_LOCAL_REPO_PATH="/custom/repo/path"
    source "${ABF_ROOT}/storage/local/module.sh"

    local url
    url=$(storage_get_repo_url)
    assert_eq "/custom/repo/path" "$url" "Custom repo path"
}

test_local_storage_pre_upload_creates_parent() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-local-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "local-test" "test" "${tmpdir}/logs"

    export STORAGE_LOCAL_REPO_PATH="${tmpdir}/repos/abf/restic"
    source "${ABF_ROOT}/storage/local/module.sh"

    if ! storage_pre_upload; then
        echo "  FAIL: storage_pre_upload should create parent directory"
        return 1
    fi

    if [[ ! -d "${tmpdir}/repos/abf" ]]; then
        echo "  FAIL: Parent directory was not created"
        return 1
    fi
    return 0
}

test_local_storage_pre_upload_fails_on_readonly() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-local-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "local-test" "test" "${tmpdir}/logs"

    # Create parent with no write permission
    local parent="${tmpdir}/readonly"
    mkdir -p "$parent"
    chmod 0444 "$parent"

    export STORAGE_LOCAL_REPO_PATH="${parent}/restic"
    source "${ABF_ROOT}/storage/local/module.sh"

    if storage_pre_upload 2>/dev/null; then
        echo "  FAIL: storage_pre_upload should fail on read-only parent"
        return 1
    fi
    return 0
}

test_local_storage_cleanup_noop() {
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/storage/local/module.sh"

    if ! storage_cleanup "test"; then
        echo "  FAIL: storage_cleanup should succeed"
        return 1
    fi
    return 0
}

test_local_storage_loadable_by_framework() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-local-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "local-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/core.sh"

    # Should load successfully and return a URL
    ABF_STORAGE_BACKEND="local"
    export STORAGE_LOCAL_REPO_PATH="${tmpdir}/restic"
    mkdir -p "${tmpdir}"

    local repo
    repo=$(_abf_get_storage_repo 2>/dev/null) || {
        echo "  FAIL: _abf_get_storage_repo should succeed for local backend"
        return 1
    }

    assert_eq "${tmpdir}/restic" "$repo" "Repo URL from framework loader"
    return 0
}
