# ---------------------------------------------------------------------------
# Tests for the Immich service module
# ---------------------------------------------------------------------------

_setup_im_test_env() {
    local data_dir="$1"
    local backup_dir="$2"

    mkdir -p "$data_dir" "$backup_dir" \
        "$data_dir/uploads/library" \
        "$data_dir/uploads/upload" \
        "$data_dir/uploads/profile" \
        "$data_dir/thumbnails" \
        "$data_dir/encoding"

    touch "$data_dir/uploads/library/photo1.jpg"
    touch "$data_dir/uploads/upload/video1.mp4"
    touch "$data_dir/uploads/profile/avatar.png"
    touch "$data_dir/thumbnails/thumb1.webp"
    touch "$data_dir/encoding/profile1.json"
    echo "DB_HOST=localhost" > "$data_dir/.env"
    echo "DB_NAME=immich"   >> "$data_dir/.env"

    export SERVICE_IMMICH_DATA_DIR="$data_dir"
    export SERVICE_IMMICH_BACKUP_DIR="$backup_dir"
    export SERVICE_IMMICH_BACKUP_DATABASE=true
    export SERVICE_IMMICH_BACKUP_UPLOADS=true
    export SERVICE_IMMICH_BACKUP_THUMBNAILS=true
    export SERVICE_IMMICH_BACKUP_ENCODING=true
    export SERVICE_IMMICH_BACKUP_CONFIG=true
}

test_immich_backup_creates_staging_dir() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-im-XXXXXX")
    local data_dir="${tmpdir}/data"
    local backup_dir="${tmpdir}/backups"

    _setup_im_test_env "$data_dir" "$backup_dir"

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "immich" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/services/immich/module.sh"

    service_pre_backup || return 1
    service_backup || return 1
    service_verify_backup || return 1

    local staging="$ABF_SERVICE_STAGING_DIR"
    if [[ ! -d "$staging" ]]; then
        echo "  FAIL: Staging directory not created"
        return 1
    fi

    local contents
    contents=$(find "$staging" -type f | sort)
    assert_contains "$contents" "uploads" "Stage contains uploads"
    assert_contains "$contents" "thumbnails" "Stage contains thumbnails"
    assert_contains "$contents" "encoding" "Stage contains encoding profiles"
    assert_contains "$contents" "config" "Stage contains config"

    service_post_backup
}

test_immich_backup_respects_disabled_components() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-im-XXXXXX")
    local data_dir="${tmpdir}/data"
    local backup_dir="${tmpdir}/backups"

    _setup_im_test_env "$data_dir" "$backup_dir"
    export SERVICE_IMMICH_BACKUP_UPLOADS=false
    export SERVICE_IMMICH_BACKUP_THUMBNAILS=false

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "immich" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/services/immich/module.sh"

    service_pre_backup || return 1
    service_backup || return 1

    local staging="$ABF_SERVICE_STAGING_DIR"
    if [[ -d "$staging/uploads" ]]; then
        echo "  FAIL: Stage should not contain uploads (disabled)"
        service_post_backup
        return 1
    fi
    if [[ -d "$staging/thumbnails" ]]; then
        echo "  FAIL: Stage should not contain thumbnails (disabled)"
        service_post_backup
        return 1
    fi
    assert_eq "YES" "$([ -f "$staging/config" ] && echo YES || echo NO)" "config should be staged"
    service_post_backup
}

test_immich_healthcheck_detects_missing_data_dir() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-im-XXXXXX")

    export SERVICE_IMMICH_DATA_DIR="${tmpdir}/nonexistent"
    export SERVICE_IMMICH_BACKUP_DIR="${tmpdir}/backups"

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "immich" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/services/immich/module.sh"

    if service_healthcheck "test"; then
        echo "  FAIL: Healthcheck should fail when data dir missing"
        return 1
    fi
    return 0
}

test_immich_cleanup_removes_stale_temp_dir() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-im-XXXXXX")
    export ABF_SERVICE_STAGING_DIR="${tmpdir}/stale"
    mkdir -p "$ABF_SERVICE_STAGING_DIR"

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "immich" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/services/immich/module.sh"

    service_cleanup "test"
    if [[ -d "$tmpdir/stale" ]]; then
        echo "  FAIL: Cleanup should remove stale temp dir"
        return 1
    fi
    return 0
}

test_immich_verify_fails_on_empty_staging() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-im-XXXXXX")

    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "immich" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/services/immich/module.sh"

    ABF_SERVICE_STAGING_DIR="${tmpdir}/empty"
    mkdir -p "$ABF_SERVICE_STAGING_DIR"

    if service_verify_backup; then
        echo "  FAIL: Verify should fail for empty staging dir"
        return 1
    fi
    return 0
}

test_immich_resolve_components() {
    source "${ABF_ROOT}/services/immich/module.sh"

    local default
    default=$(service_resolve_components "")
    assert_eq "database,uploads,thumbnails,encoding,config" "$default" "Default components"

    local short_names
    short_names=$(service_resolve_components "db,config")
    assert_eq "database,config" "$short_names" "Short name 'db' resolves to 'database'"

    local passthrough
    passthrough=$(service_resolve_components "custom_dir")
    assert_eq "custom_dir" "$passthrough" "Unknown name passed through unchanged"
}
