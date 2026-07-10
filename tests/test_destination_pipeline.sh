# ---------------------------------------------------------------------------
# Tests for the destination pipeline integration in core.sh
# ---------------------------------------------------------------------------

test_destination_manifest_exists() {
    if [[ ! -f "${ABF_ROOT}/destinations/manifest.conf" ]]; then
        echo "  FAIL: Destination manifest not found"
        return 1
    fi
    return 0
}

test_destination_module_loader_valid() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-dest-pipe-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "dest-pipe-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/core.sh"

    if ! abf_load_destination_module "local"; then
        echo "  FAIL: Should load local destination module"
        return 1
    fi
    return 0
}

test_destination_module_loader_invalid() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-dest-pipe-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "dest-pipe-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/core.sh"

    if abf_load_destination_module "nonexistent" 2>/dev/null; then
        echo "  FAIL: Should not load nonexistent module"
        return 1
    fi
    return 0
}

test_destination_exists_checks_manifest() {
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/core.sh"

    if ! abf_destination_exists "local"; then
        echo "  FAIL: local should exist in manifest"
        return 1
    fi

    if abf_destination_exists "nonexistent" 2>/dev/null; then
        echo "  FAIL: nonexistent should not exist in manifest"
        return 1
    fi
    return 0
}

test_abf_print_summary_backup_success() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/core/core.sh"

    local output
    output=$(_abf_print_summary "test-svc" "$ABF_EXIT_OK" "$ABF_EXIT_OK" "Local:SUCCESS" 2>&1)

    assert_contains "$output" "SUCCESS" "Summary contains SUCCESS"
    assert_contains "$output" "Backup:" "Summary contains Backup"
    assert_contains "$output" "Repository Verify:" "Summary contains Repository Verify"
    assert_contains "$output" "Local:" "Summary contains Local"

    return 0
}

test_abf_print_summary_backup_failed() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/core/core.sh"

    local output
    output=$(_abf_print_summary "test-svc" "$ABF_EXIT_BACKUP_FAILED" "$ABF_EXIT_OK" "OneDrive:FAILED" 2>&1)

    assert_contains "$output" "FAILED" "Summary contains FAILED"
    assert_contains "$output" "Backup:" "Summary contains Backup"
    assert_contains "$output" "OneDrive:" "Summary contains OneDrive"

    return 0
}

test_abf_print_summary_multiple_destinations() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    source "${ABF_ROOT}/core/core.sh"

    local output
    output=$(_abf_print_summary "test-svc" "$ABF_EXIT_OK" "$ABF_EXIT_OK" \
        "Local:SUCCESS" "OneDrive:FAILED" 2>&1)

    assert_contains "$output" "Local:" "Local destination in summary"
    assert_contains "$output" "OneDrive:" "OneDrive destination in summary"
    assert_contains "$output" "FAILED" "OneDrive shows FAILED"

    return 0
}

test_destination_config_validation() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-dest-pipe-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "dest-pipe-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/core.sh"

    BACKUP_DESTINATIONS="local"
    export BACKUP_DESTINATIONS

    # Mock ABF_RESTIC_PASSWORD_FILE and ABF_LOG_DIR to avoid unrelated errors
    echo "test-pw" > "${tmpdir}/pwfile"
    ABF_RESTIC_PASSWORD_FILE="${tmpdir}/pwfile"
    ABF_LOG_DIR="${tmpdir}/logs"
    export ABF_RESTIC_PASSWORD_FILE ABF_LOG_DIR

    local output
    output=$(abf_validate_config 2>&1 || true)

    assert_contains "$output" "0 error" "Config should have 0 errors with local destination"

    return 0
}

test_destination_config_validation_invalid() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-dest-pipe-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "dest-pipe-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/core.sh"

    BACKUP_DESTINATIONS="nonexistent"
    export BACKUP_DESTINATIONS

    echo "test-pw" > "${tmpdir}/pwfile"
    ABF_RESTIC_PASSWORD_FILE="${tmpdir}/pwfile"
    ABF_LOG_DIR="${tmpdir}/logs"
    export ABF_RESTIC_PASSWORD_FILE ABF_LOG_DIR

    local output
    output=$(abf_validate_config 2>&1 || true)

    assert_contains "$output" "ERROR" "Config should have errors with invalid destination"
    assert_contains "$output" "nonexistent" "Error message should reference the invalid destination"

    return 0
}
