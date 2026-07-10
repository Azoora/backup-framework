# ---------------------------------------------------------------------------
# Tests for the restore safety foundation (Phase 1) and Phase 2 features
#
# Phase 1 tests cover:
#   - Confirmation prompt (TTY detection, --yes, dry-run)
#   - Restore privilege checks
#   - Restore lock integration
#
# Phase 2 tests cover:
#   - Pre-restore backup (skip with --target, creates dir structure)
#   - Component name resolution via service module
#   - Component filtering during restore
#   - rsync dependency required for restore operations
# ---------------------------------------------------------------------------

test_restore_dry_run_skips_confirmation() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-res-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test" "restore" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/restore.sh"

    # dry_run=true should return OK regardless of TTY
    _abf_require_confirmation "true" "false" || {
        echo "  FAIL: dry_run=true should skip confirmation"
        rm -rf "$tmpdir"
        return 1
    }

    rm -rf "$tmpdir"
    return 0
}

test_restore_yes_flag_skips_confirmation() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-res-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test" "restore" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/restore.sh"

    # yes=true should return OK regardless of TTY
    _abf_require_confirmation "false" "true" || {
        echo "  FAIL: yes=true should skip confirmation"
        rm -rf "$tmpdir"
        return 1
    }

    rm -rf "$tmpdir"
    return 0
}

test_restore_non_tty_rejected_without_yes() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-res-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test" "restore" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/restore.sh"

    # Non-TTY (test default) without --yes should abort
    if _abf_require_confirmation "false" "false"; then
        echo "  FAIL: non-TTY without --yes should abort"
        rm -rf "$tmpdir"
        return 1
    fi

    rm -rf "$tmpdir"
    return 0
}

test_restore_interactive_accepted() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-res-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test" "restore" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/restore.sh"

    # Override interactive check to simulate terminal
    _abf_is_interactive() { return 0; }

    # Pipe 'y' into confirmation prompt
    _abf_require_confirmation "false" "false" <<< "y" || {
        echo "  FAIL: 'y' response should proceed"
        rm -rf "$tmpdir"
        return 1
    }

    rm -rf "$tmpdir"
    return 0
}

test_restore_interactive_rejected() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-res-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test" "restore" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/restore.sh"

    # Override interactive check to simulate terminal
    _abf_is_interactive() { return 0; }

    # Pipe 'n' into confirmation prompt
    if _abf_require_confirmation "false" "false" <<< "n"; then
        echo "  FAIL: 'n' response should abort"
        rm -rf "$tmpdir"
        return 1
    fi

    rm -rf "$tmpdir"
    return 0
}

test_restore_privilege_check_fails_on_missing_dir() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-res-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test" "restore" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/restore.sh"

    # Point data dir at a non-existent path
    export SERVICE_VAULTWARDEN_DATA_DIR="${tmpdir}/nonexistent"

    if _abf_check_restore_privileges "vaultwarden"; then
        echo "  FAIL: privilege check should fail on missing data dir"
        rm -rf "$tmpdir"
        return 1
    fi

    rm -rf "$tmpdir"
    return 0
}

# ==================================================================
# Phase 2: Pre-restore backup
# ==================================================================

test_restore_pre_backup_creates_backup() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-res-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test" "restore" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/restore.sh"

    local data_dir="${tmpdir}/data"
    mkdir -p "$data_dir"
    echo "original db" > "$data_dir/db.sqlite3"
    mkdir -p "$data_dir/attachments" && echo "data" > "$data_dir/attachments/file.txt"

    export ABF_TEMP_DIR="${tmpdir}/abf"
    export ABF_RESTORE_COMPONENTS="db.sqlite3,attachments"

    _abf_create_pre_restore_backup "test-svc" "$data_dir" || {
        echo "  FAIL: pre-restore backup should succeed"
        rm -rf "$tmpdir"
        return 1
    }

    local pre_dir="${ABF_TEMP_DIR}/pre_restore/test-svc"
    if [[ ! -d "$pre_dir" ]]; then
        echo "  FAIL: pre-restore dir not created"
        rm -rf "$tmpdir"
        return 1
    fi

    local dir_count
    dir_count=$(find "$pre_dir" -mindepth 1 -maxdepth 1 -type d | wc -l)
    if [[ "$dir_count" -ne 1 ]]; then
        echo "  FAIL: expected 1 timestamped backup dir, found ${dir_count}"
        rm -rf "$tmpdir"
        return 1
    fi

    local backup_dir
    backup_dir=$(find "$pre_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
    local backed_up_files
    backed_up_files=$(find "$backup_dir" -type f | sort)

    assert_contains "$backed_up_files" "db.sqlite3" "Backup contains db.sqlite3"
    assert_contains "$backed_up_files" "attachments/file.txt" "Backup contains attachments/file.txt"
    assert_contains "$backed_up_files" ".metadata" "Backup contains metadata file"

    rm -rf "$tmpdir"
    return 0
}

test_restore_pre_backup_with_custom_components() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-res-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test" "restore" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/restore.sh"

    local data_dir="${tmpdir}/data"
    mkdir -p "$data_dir"
    echo "only db" > "$data_dir/db.sqlite3"
    mkdir -p "$data_dir/attachments" && echo "data" > "$data_dir/attachments/file.txt"

    export ABF_TEMP_DIR="${tmpdir}/abf"
    export ABF_RESTORE_COMPONENTS="db.sqlite3"

    _abf_create_pre_restore_backup "test-svc" "$data_dir" || {
        echo "  FAIL: pre-restore backup should succeed"
        rm -rf "$tmpdir"
        return 1
    }

    local pre_dir="${ABF_TEMP_DIR}/pre_restore/test-svc"
    local backup_dir
    backup_dir=$(find "$pre_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
    local backed_up_files
    backed_up_files=$(find "$backup_dir" -type f | sort)

    assert_contains "$backed_up_files" "db.sqlite3" "Backup contains db.sqlite3"
    if echo "$backed_up_files" | grep -q "attachments"; then
        echo "  FAIL: attachments should not be in selective backup"
        rm -rf "$tmpdir"
        return 1
    fi

    rm -rf "$tmpdir"
    return 0
}

# ==================================================================
# Phase 2: Component name resolution
# ==================================================================

test_restore_resolve_components_fallback() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-res-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test" "restore" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/restore.sh"

    local result
    result=$(_abf_resolve_components "")
    assert_eq "" "$result" "Empty input returns empty"

    result=$(_abf_resolve_components "custom,paths")
    assert_eq "custom,paths" "$result" "No service module returns raw string"

    rm -rf "$tmpdir"
    return 0
}

test_restore_resolve_components_vaultwarden() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-res-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "test" "restore" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/restore.sh"
    source "${ABF_ROOT}/services/vaultwarden/module.sh"

    local result
    result=$(_abf_resolve_components "db,config")
    assert_eq "db.sqlite3,config.json" "$result" "Short names resolved"

    result=$(_abf_resolve_components "attachments,rsa_keys")
    assert_eq "attachments,rsa_keys" "$result" "Known component names pass through"

    result=$(_abf_resolve_components "icon_cache")
    assert_eq "icon_cache" "$result" "icon_cache resolved"

    rm -rf "$tmpdir"
    return 0
}

# ==================================================================
# Phase 2: Vaultwarden component filtering during restore
# ==================================================================

test_restore_vaultwarden_component_filter() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-res-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "vaultwarden" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/services/vaultwarden/module.sh"

    local data_dir="${tmpdir}/data"
    local staging="${tmpdir}/staging"
    mkdir -p "$data_dir" "$staging"
    echo "db" > "$staging/db.sqlite3"
    echo "config" > "$staging/config.json"
    mkdir -p "$staging/attachments" && echo "attach" > "$staging/attachments/file.txt"
    mkdir -p "$staging/rsa_keys" && echo "key" > "$staging/rsa_keys/key.pem"

    export ABF_RESTORE_COMPONENTS="db.sqlite3,config.json"
    export ABF_RESTORE_REPLACE_ALL="false"

    _vw_restore_all "$staging" "$data_dir"

    assert_eq "YES" "$([ -f "$data_dir/db.sqlite3" ] && echo YES || echo NO)" "db.sqlite3 restored"
    assert_eq "YES" "$([ -f "$data_dir/config.json" ] && echo YES || echo NO)" "config.json restored"
    assert_eq "NO" "$([ -d "$data_dir/attachments" ] && echo YES || echo NO)" "attachments not restored"

    rm -rf "$tmpdir"
    return 0
}

test_restore_vaultwarden_replace_all() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-res-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "vaultwarden" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/services/vaultwarden/module.sh"

    local data_dir="${tmpdir}/data"
    local staging="${tmpdir}/staging"
    mkdir -p "$data_dir/stale_dir"
    echo "old" > "$data_dir/stale_dir/old.txt"
    mkdir -p "$staging/attachments" && echo "new" > "$staging/attachments/new.txt"

    export ABF_RESTORE_COMPONENTS="attachments"
    export ABF_RESTORE_REPLACE_ALL="true"

    _vw_restore_dir "$staging" "attachments" "$data_dir"

    assert_eq "YES" "$([ -f "$data_dir/attachments/new.txt" ] && echo YES || echo NO)" "attachments/new.txt restored"
    assert_eq "YES" "$([ -d "$data_dir/stale_dir" ] && echo YES || echo NO)" "stale_dir preserved (replace-all only affects attachments dir)"

    rm -rf "$tmpdir"
    return 0
}
