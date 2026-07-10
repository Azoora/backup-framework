# ---------------------------------------------------------------------------
# Tests for the Vaultwarden service module
# ---------------------------------------------------------------------------

_setup_vw_test_env() {
    local data_dir="$1"
    local backup_dir="$2"

    mkdir -p "$data_dir" "$backup_dir"
    touch "$data_dir/db.sqlite3"
    mkdir -p "$data_dir/attachments" && echo "attach" > "$data_dir/attachments/file.txt"
    mkdir -p "$data_dir/icon_cache" && echo "icon" > "$data_dir/icon_cache/icon.png"
    echo "private-key" > "$data_dir/rsa_key.pem"
    echo '{"domain":"test"}' > "$data_dir/config.json"

    export SERVICE_VAULTWARDEN_DATA_DIR="$data_dir"
    export SERVICE_VAULTWARDEN_BACKUP_DIR="$backup_dir"
    export SERVICE_VAULTWARDEN_BACKUP_DATABASE=true
    export SERVICE_VAULTWARDEN_BACKUP_ATTACHMENTS=true
    export SERVICE_VAULTWARDEN_BACKUP_ICON_CACHE=true
    export SERVICE_VAULTWARDEN_BACKUP_RSA_KEYS=true
    export SERVICE_VAULTWARDEN_BACKUP_CONFIG=true
    export SERVICE_VAULTWARDEN_BACKUP_TEMP_FILES=false
}

test_backup_creates_staging_dir() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-vw-XXXXXX")
    local data_dir="${tmpdir}/data"
    local backup_dir="${tmpdir}/backups"

    _setup_vw_test_env "$data_dir" "$backup_dir"

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "vaultwarden" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/services/vaultwarden/module.sh"

    service_pre_backup || return 1
    service_backup || return 1
    service_verify_backup || return 1

    # Verify staging directory has expected files
    local staging="$ABF_SERVICE_STAGING_DIR"
    if [[ ! -d "$staging" ]]; then
        echo "  FAIL: Staging directory not created"
        return 1
    fi

    local contents
    contents=$(find "$staging" -type f | sort)
    assert_contains "$contents" "db.sqlite3" "Stage contains database"
    assert_contains "$contents" "config.json" "Stage contains config"
    assert_contains "$contents" "attachments/file.txt" "Stage contains attachments"
    assert_contains "$contents" "icon_cache/icon.png" "Stage contains icon cache"
    assert_contains "$contents" "rsa_key.pem" "Stage contains RSA keys"

    service_post_backup
}

test_backup_respects_disabled_components() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-vw-XXXXXX")
    local data_dir="${tmpdir}/data"
    local backup_dir="${tmpdir}/backups"

    _setup_vw_test_env "$data_dir" "$backup_dir"
    export SERVICE_VAULTWARDEN_BACKUP_DATABASE=false

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "vaultwarden" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/services/vaultwarden/module.sh"

    service_pre_backup || return 1
    service_backup || return 1

    local staging="$ABF_SERVICE_STAGING_DIR"
    if [[ -f "$staging/db.sqlite3" ]]; then
        echo "  FAIL: Stage should not contain db.sqlite3 (disabled)"
        service_post_backup
        return 1
    fi
    assert_eq "YES" "$([ -f "$staging/config.json" ] && echo YES || echo NO)" "config.json should be staged"
    service_post_backup
}

test_restore_dry_run_does_not_modify() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-vw-XXXXXX")
    local data_dir="${tmpdir}/data"
    local backup_dir="${tmpdir}/backups"

    _setup_vw_test_env "$data_dir" "$backup_dir"

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "vaultwarden" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/services/vaultwarden/module.sh"

    service_pre_backup || return 1
    service_backup || return 1
    service_verify_backup || return 1

    # Save staging path before cleanup
    local staging="${ABF_SERVICE_STAGING_DIR:-}"
    if [[ ! -d "$staging" ]]; then
        echo "  FAIL: Staging dir not created"
        service_post_backup
        return 1
    fi

    # Remove config.json from data dir
    rm -f "$data_dir/config.json"
    assert_eq "NO" "$([ -f "$data_dir/config.json" ] && echo YES || echo NO)" "config.json removed"

    # Dry-run restore from the staging dir (simulates restic restore into staging)
    ABF_RESTORE_STAGING="$staging"
    service_pre_restore "" || return 1
    service_restore "" "true" || return 1
    service_verify_restore || return 1

    # Verify config.json was NOT restored (dry-run)
    assert_eq "NO" "$([ -f "$data_dir/config.json" ] && echo YES || echo NO)" "config.json should not exist after dry-run"

    service_post_restore
    service_post_backup
}

test_healthcheck_detects_missing_data_dir() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-vw-XXXXXX")

    export SERVICE_VAULTWARDEN_DATA_DIR="${tmpdir}/nonexistent"
    export SERVICE_VAULTWARDEN_BACKUP_DIR="${tmpdir}/backups"

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "vaultwarden" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/services/vaultwarden/module.sh"

    if service_healthcheck "test"; then
        echo "  FAIL: Healthcheck should fail when data dir missing"
        return 1
    fi
    return 0
}

test_cleanup_removes_stale_temp_dir() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-vw-XXXXXX")
    export ABF_SERVICE_STAGING_DIR="${tmpdir}/stale"
    mkdir -p "$ABF_SERVICE_STAGING_DIR"

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "vaultwarden" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/services/vaultwarden/module.sh"

    service_cleanup "test"
    if [[ -d "$tmpdir/stale" ]]; then
        echo "  FAIL: Cleanup should remove stale temp dir"
        return 1
    fi
    return 0
}

test_verify_fails_on_empty_staging() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-vw-XXXXXX")

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "vaultwarden" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/services/vaultwarden/module.sh"

    ABF_SERVICE_STAGING_DIR="${tmpdir}/empty"
    mkdir -p "$ABF_SERVICE_STAGING_DIR"

    if service_verify_backup; then
        echo "  FAIL: Verify should fail for empty staging dir"
        return 1
    fi
    return 0
}
