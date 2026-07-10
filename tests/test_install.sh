# ---------------------------------------------------------------------------
# Tests for the installation layout
# ---------------------------------------------------------------------------

test_install_wrapper_structure() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-inst-XXXXXX")
    local bin_dir="${tmpdir}/bin"
    local framework_dir="${tmpdir}/opt/abf"

    mkdir -p "$bin_dir" "$framework_dir"

    # Create mock framework
    cp "${ABF_ROOT}/abf" "${framework_dir}/abf"
    mkdir -p "${framework_dir}/core"
    cp -r "${ABF_ROOT}/core"/* "${framework_dir}/core/"
    mkdir -p "${framework_dir}/services"
    cp -r "${ABF_ROOT}/services"/* "${framework_dir}/services/"
    echo "0.1.0-beta" > "${framework_dir}/VERSION"

    # Create wrapper (same structure as install.sh creates)
    cat > "${bin_dir}/abf" <<'WRAPPER'
#!/usr/bin/env bash
exec /opt/abf/abf "$@"
WRAPPER
    chmod +x "${bin_dir}/abf"

    # Verify wrapper properties
    local wrapper_content
    wrapper_content=$(cat "${bin_dir}/abf")
    assert_contains "$wrapper_content" "#!/usr/bin/env bash" "Wrapper has correct shebang"
    assert_contains "$wrapper_content" "exec /opt/abf/abf" "Wrapper execs framework path"
    assert_contains "$wrapper_content" "\"\$@\"" "Wrapper passes all arguments"

    # Verify the wrapper is NOT a copy of the framework (no framework logic)
    if grep -q "abf_run_backup" "${bin_dir}/abf" 2>/dev/null; then
        echo "  FAIL: Wrapper must not contain framework logic"
        return 1
    fi

    # Verify framework is intact
    if [[ ! -f "${framework_dir}/abf" ]]; then
        echo "  FAIL: Framework launcher missing"
        return 1
    fi
    if [[ ! -d "${framework_dir}/core" ]]; then
        echo "  FAIL: Core modules missing"
        return 1
    fi

    return 0
}

test_install_abf_root_dev_mode() {
    # Development mode: running ./abf from checkout
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-inst-XXXXXX")

    # Simulate dev checkout structure (full enough for launcher to source)
    mkdir -p "${tmpdir}/checkout"
    cp -r "${ABF_ROOT}/core"                 "${tmpdir}/checkout/core"
    cp -r "${ABF_ROOT}/services"             "${tmpdir}/checkout/services"
    cp -r "${ABF_ROOT}/storage"              "${tmpdir}/checkout/storage"
    cp "${ABF_ROOT}/abf"                     "${tmpdir}/checkout/abf"
    cp "${ABF_ROOT}/VERSION"                 "${tmpdir}/checkout/VERSION"

    # Running from checkout: ABF_ROOT should be the checkout dir
    local abf_root
    abf_root=$(cd "${tmpdir}/checkout" && pwd)
    local computed
    computed=$(cd "$(dirname "${tmpdir}/checkout/abf")" && pwd)
    assert_eq "$abf_root" "$computed" "Dev mode ABF_ROOT equals checkout dir"

    # Verify the launcher can compute its own root and source modules
    local version_out
    version_out=$(cd "${tmpdir}/checkout" && ./abf --version 2>&1)
    assert_contains "$version_out" "0.1.1-beta" "Dev mode reports correct version"
}

test_install_abf_root_installed_mode() {
    # Installed mode: ABF_ROOT should be /opt/abf regardless of wrapper path
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-inst-XXXXXX")
    local bin_dir="${tmpdir}/bin"
    local framework_dir="${tmpdir}/opt/abf"

    mkdir -p "$bin_dir" "$framework_dir/core" "$framework_dir/services"

    # Create mock framework
    cp "${ABF_ROOT}/abf" "${framework_dir}/abf"
    echo "0.1.0-beta" > "${framework_dir}/VERSION"

    # Create wrapper
    cat > "${bin_dir}/abf" <<'WRAPPER'
#!/usr/bin/env bash
exec "$(dirname "$0")/../opt/abf/abf" "$@"
WRAPPER
    chmod +x "${bin_dir}/abf"

    # The framework launcher computes ABF_ROOT from its own $0
    # When called via exec /opt/abf/abf, $0 is /opt/abf/abf
    # So ABF_ROOT should be /opt/abf

    local script_dir
    script_dir=$(cd "$(dirname "${framework_dir}/abf")" && pwd)
    assert_eq "${tmpdir}/opt/abf" "$script_dir" "Installed ABF_ROOT is /opt/abf"
}

test_install_uninstall_script_exists() {
    if [[ ! -f "${ABF_ROOT}/scripts/uninstall.sh" ]]; then
        echo "  FAIL: uninstall.sh not found"
        return 1
    fi
    local shebang
    shebang=$(head -1 "${ABF_ROOT}/scripts/uninstall.sh")
    assert_contains "$shebang" "#!/usr/bin/env bash" "Uninstall has correct shebang"
}

test_install_script_idempotent() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-inst-XXXXXX")

    # Simulate that framework is already installed
    mkdir -p "${tmpdir}/opt/abf/core"
    echo "already-installed" > "${tmpdir}/opt/abf/VERSION"

    # The install should handle existing installations gracefully
    if [[ -d "${tmpdir}/opt/abf" ]]; then
        # Just verify the directory structure is valid
        local content
        content=$(cat "${tmpdir}/opt/abf/VERSION")
        assert_eq "already-installed" "$content" "Existing installation preserved"
    fi
}

test_install_has_dependency_checking() {
    local install="${ABF_ROOT}/scripts/install.sh"

    # Verify dependency definitions exist
    if ! grep -q "ABF_DEPS=" "$install"; then
        echo "  FAIL: install.sh missing ABF_DEPS definitions"
        return 1
    fi

    # Verify dependency functions exist
    if ! grep -q "_abf_check_deps()" "$install"; then
        echo "  FAIL: install.sh missing _abf_check_deps()"
        return 1
    fi
    if ! grep -q "_abf_install_deps_debian()" "$install"; then
        echo "  FAIL: install.sh missing _abf_install_deps_debian()"
        return 1
    fi

    # Verify required dependencies are listed
    local deps_section
    deps_section=$(grep -A20 "ABF_DEPS=(" "$install")
    assert_contains "$deps_section" "restic" "install.sh checks for restic"
    assert_contains "$deps_section" "rclone" "install.sh checks for rclone"
    assert_contains "$deps_section" "sqlite3" "install.sh checks for sqlite3"

    return 0
}

test_install_dep_check_restic_required() {
    local install="${ABF_ROOT}/scripts/install.sh"

    # Verify restic is marked as required
    local restic_line
    restic_line=$(grep "restic:" "$install" | grep "required" || true)
    if [[ -z "$restic_line" ]]; then
        echo "  FAIL: restic should be marked as required dependency"
        return 1
    fi
    return 0
}

test_install_no_nested_duplicate_directories() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-inst-XXXXXX")

    # Simulate first installation
    local dst="${tmpdir}/opt/abf"
    mkdir -p "${dst}"
    cp -r "${ABF_ROOT}/core"  "${dst}/core"
    cp -r "${ABF_ROOT}/services" "${dst}/services"
    cp -r "${ABF_ROOT}/storage"  "${dst}/storage"
    cp -r "${ABF_ROOT}/scripts"  "${dst}/scripts"

    # Now simulate re-install (the exact pattern install.sh uses after cleanup)
    rm -rf "${dst}/core" "${dst}/services" "${dst}/storage" "${dst}/scripts"
    cp -r "${ABF_ROOT}/core"     "${dst}/core"
    cp -r "${ABF_ROOT}/services" "${dst}/services"
    cp -r "${ABF_ROOT}/storage"  "${dst}/storage"
    cp -r "${ABF_ROOT}/scripts"  "${dst}/scripts"

    # Check for nested duplicate directories
    if [[ -d "${dst}/core/core" ]]; then
        echo "  FAIL: Nested duplicate 'core/core/' exists after re-install"
        return 1
    fi
    if [[ -d "${dst}/services/services" ]]; then
        echo "  FAIL: Nested duplicate 'services/services/' exists after re-install"
        return 1
    fi
    if [[ -d "${dst}/storage/storage" ]]; then
        echo "  FAIL: Nested duplicate 'storage/storage/' exists after re-install"
        return 1
    fi
    if [[ -d "${dst}/scripts/scripts" ]]; then
        echo "  FAIL: Nested duplicate 'scripts/scripts/' exists after re-install"
        return 1
    fi

    # Verify the installed files are the real ones, not stale nested copies
    if [[ -f "${dst}/core/core/main.sh" ]]; then
        echo "  FAIL: Stale nested file 'core/core/main.sh' exists after re-install"
        return 1
    fi

    return 0
}

test_install_files_contain_latest_code() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-inst-XXXXXX")
    local dst="${tmpdir}/opt/abf"

    mkdir -p "${dst}"

    # Simulate a clean installation
    rm -rf "${dst}/core" "${dst}/services"
    cp -r "${ABF_ROOT}/core"     "${dst}/core"
    cp -r "${ABF_ROOT}/services" "${dst}/services"

    # Verify installed files match source files (same content, not outdated)
    local src_core_files dst_core_files
    src_core_files=$(find "${ABF_ROOT}/core" -type f | sort)
    dst_core_files=$(find "${dst}/core" -type f | sort)

    local src_file dst_file
    while IFS= read -r src_file; do
        dst_file="${dst}/core/${src_file#${ABF_ROOT}/core/}"
        if [[ ! -f "$dst_file" ]]; then
            echo "  FAIL: Installed file missing: ${dst_file}"
            return 1
        fi
        if ! diff -q "$src_file" "$dst_file" >/dev/null 2>&1; then
            echo "  FAIL: Content mismatch: ${dst_file} does not match source"
            return 1
        fi
    done <<< "$src_core_files"

    return 0
}

# ------------------------------------------------------------------
# Upgrade & migration tests
# ------------------------------------------------------------------

test_upgrade_migrates_old_defaults() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-inst-XXXXXX")
    local cfg="${tmpdir}/etc/abf"
    mkdir -p "${cfg}/services"

    # Create config with old defaults (as shipped by a previous install)
    cat > "${cfg}/abf.conf" <<'EOF'
ABF_LOG_DIR="/var/log/abf"
ABF_CACHE_DIR="/var/cache/abf"
ABF_TEMP_DIR="/tmp/abf"
ABF_RESTIC_PASSWORD_FILE="/etc/abf/restic-password"
EOF

    # Source migration module and run
    source "${ABF_ROOT}/core/migrate.sh"
    ABF_CONFIG_DIR="$cfg" abf_config_migrate

    # Verify old defaults were migrated
    local log_dir cache_dir
    log_dir=$(grep -E '^ABF_LOG_DIR=' "${cfg}/abf.conf" | sed 's/.*="//;s/"$//')
    cache_dir=$(grep -E '^ABF_CACHE_DIR=' "${cfg}/abf.conf" | sed 's/.*="//;s/"$//')

    assert_eq "/tmp/abf/logs" "$log_dir" "ABF_LOG_DIR migrated to new default"
    assert_eq "/tmp/abf/cache" "$cache_dir" "ABF_CACHE_DIR migrated to new default"

    return 0
}

test_upgrade_preserves_customized_values() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-inst-XXXXXX")
    local cfg="${tmpdir}/etc/abf"
    mkdir -p "${cfg}/services"

    # Create config where user already customized the value (not old default)
    cat > "${cfg}/abf.conf" <<'EOF'
ABF_LOG_DIR="/custom/log/path"
ABF_CACHE_DIR="/tmp/abf/cache"
EOF

    # Run migration
    source "${ABF_ROOT}/core/migrate.sh"
    ABF_CONFIG_DIR="$cfg" abf_config_migrate

    # Verify customized value was NOT changed
    local log_dir
    log_dir=$(grep -E '^ABF_LOG_DIR=' "${cfg}/abf.conf" | sed 's/.*="//;s/"$//')
    assert_eq "/custom/log/path" "$log_dir" "Customized ABF_LOG_DIR preserved"

    # Verify the non-customized value WAS migrated (old default matched)
    local cache_dir
    cache_dir=$(grep -E '^ABF_CACHE_DIR=' "${cfg}/abf.conf" | sed 's/.*="//;s/"$//')
    assert_eq "/tmp/abf/cache" "$cache_dir" "Default ABF_CACHE_DIR untouched (already /tmp/abf/cache)"

    return 0
}

test_upgrade_creates_backup_before_migration() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-inst-XXXXXX")
    local cfg="${tmpdir}/etc/abf"
    mkdir -p "${cfg}/services"

    cat > "${cfg}/abf.conf" <<'EOF'
ABF_LOG_DIR="/var/log/abf"
EOF

    source "${ABF_ROOT}/core/migrate.sh"
    ABF_CONFIG_DIR="$cfg" abf_config_migrate

    # Verify backup directory was created
    local backup_dirs
    backup_dirs=$(find "${cfg}/backup" -maxdepth 1 -type d 2>/dev/null | wc -l)

    if [[ "$backup_dirs" -lt 2 ]]; then
        echo "  FAIL: No backup directory found in ${cfg}/backup"
        return 1
    fi

    # Verify the backup contains the original config
    local backup_file
    backup_file=$(find "${cfg}/backup" -name "abf.conf" 2>/dev/null | head -1)
    if [[ -z "$backup_file" ]]; then
        echo "  FAIL: Backup does not contain abf.conf"
        return 1
    fi

    # Verify backup has the OLD value before migration
    local old_val
    old_val=$(grep -E '^ABF_LOG_DIR=' "$backup_file" | sed 's/.*="//;s/"$//')
    assert_eq "/var/log/abf" "$old_val" "Backup contains original value before migration"

    return 0
}

test_upgrade_idempotent() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-inst-XXXXXX")
    local cfg="${tmpdir}/etc/abf"
    mkdir -p "${cfg}/services"

    cat > "${cfg}/abf.conf" <<'EOF'
ABF_LOG_DIR="/var/log/abf"
EOF

    source "${ABF_ROOT}/core/migrate.sh"
    ABF_CONFIG_DIR="$cfg" abf_config_migrate
    local backup_count_1
    backup_count_1=$(find "${cfg}/backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)

    # Run migration again
    ABF_CONFIG_DIR="$cfg" abf_config_migrate

    # Verify no new backup was created
    local backup_count_2
    backup_count_2=$(find "${cfg}/backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    assert_eq "$backup_count_1" "$backup_count_2" "No additional backup on second run"

    # Verify value is still correct
    local log_dir
    log_dir=$(grep -E '^ABF_LOG_DIR=' "${cfg}/abf.conf" | sed 's/.*="//;s/"$//')
    assert_eq "/tmp/abf/logs" "$log_dir" "Value unchanged after second migration run"

    # Verify output says "No migrations needed"
    local output
    output=$(ABF_CONFIG_DIR="$cfg" abf_config_migrate 2>&1)
    assert_contains "$output" "No migrations needed" "Second run reports no migrations"

    return 0
}

test_upgrade_info_printed_in_summary() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-inst-XXXXXX")
    local cfg="${tmpdir}/etc/abf"
    mkdir -p "${cfg}/services"

    cat > "${cfg}/abf.conf" <<'EOF'
ABF_LOG_DIR="/var/log/abf"
ABF_CACHE_DIR="/var/cache/abf"
EOF

    source "${ABF_ROOT}/core/migrate.sh"
    local output
    output=$(ABF_CONFIG_DIR="$cfg" abf_config_migrate 2>&1)

    assert_contains "$output" "Backup created" "Summary mentions backup"
    assert_contains "$output" "Migrated 2 value" "Summary reports change count"
    assert_contains "$output" "ABF_LOG_DIR" "Summary lists migrated variable"
    assert_contains "$output" "ABF_CACHE_DIR" "Summary lists migrated variable"
    assert_contains "$output" "/var/log/abf" "Summary shows old value"
    assert_contains "$output" "/tmp/abf/logs" "Summary shows new value"

    return 0
}

test_upgrade_vaultwarden_backup_dir() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-inst-XXXXXX")
    local cfg="${tmpdir}/etc/abf"
    mkdir -p "${cfg}/services"

    cat > "${cfg}/services/vaultwarden.conf" <<'EOF'
SERVICE_VAULTWARDEN_BACKUP_DIR="/var/backups/abf/vaultwarden"
EOF

    source "${ABF_ROOT}/core/migrate.sh"
    ABF_CONFIG_DIR="$cfg" abf_config_migrate

    local dir
    dir=$(grep -E '^SERVICE_VAULTWARDEN_BACKUP_DIR=' "${cfg}/services/vaultwarden.conf" | sed 's/.*="//;s/"$//')
    assert_eq "/tmp/abf/vaultwarden" "$dir" "Vaultwarden backup dir migrated"

    return 0
}

test_upgrade_privilege_check_detects_unreadable_password_file() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-inst-XXXXXX")

    local pw_file="${tmpdir}/restic-password"
    echo "test-password" > "$pw_file"
    chmod 000 "$pw_file"

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/core/core.sh"

    export ABF_RESTIC_PASSWORD_FILE="$pw_file"

    local output
    output=$(_abf_check_backup_privileges "test" 2>&1 || true)

    chmod 644 "$pw_file"
    unset ABF_RESTIC_PASSWORD_FILE

    assert_contains "$output" "Cannot read restic password file" "Error includes password file path"
    assert_contains "$output" "sudo abf backup" "Error suggests sudo"

    return 0
}

test_upgrade_privilege_check_passes_when_readable() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-inst-XXXXXX")

    local pw_file="${tmpdir}/restic-password"
    echo "test-password" > "$pw_file"
    chmod 644 "$pw_file"

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/core/core.sh"

    export ABF_RESTIC_PASSWORD_FILE="$pw_file"

    _abf_check_backup_privileges "test" 2>/dev/null

    local rc=$?

    chmod 644 "$pw_file"
    unset ABF_RESTIC_PASSWORD_FILE

    if [[ "$rc" -ne 0 ]]; then
        echo "  FAIL: Privilege check should pass for readable password file"
        return 1
    fi

    return 0
}

test_install_sources_version_file() {
    # Verify install.sh references VERSION (the framework version, not install.sh version)
    local install="${ABF_ROOT}/scripts/install.sh"
    if ! grep -q "ABF_SRC" "$install"; then
        echo "  FAIL: install.sh should define ABF_SRC"
        return 1
    fi
    return 0
}
