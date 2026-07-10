# ---------------------------------------------------------------------------
# Tests for the restore safety foundation (Phase 1)
#
# Tests cover:
#   - Confirmation prompt (TTY detection, --yes, dry-run)
#   - Restore privilege checks
#   - Restore lock integration
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
