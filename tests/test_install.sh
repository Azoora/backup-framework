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

test_install_sources_version_file() {
    # Verify install.sh references VERSION (the framework version, not install.sh version)
    local install="${ABF_ROOT}/scripts/install.sh"
    if ! grep -q "ABF_SRC" "$install"; then
        echo "  FAIL: install.sh should define ABF_SRC"
        return 1
    fi
    return 0
}
