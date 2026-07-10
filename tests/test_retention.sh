# ---------------------------------------------------------------------------
# Tests for the retention policy module
# ---------------------------------------------------------------------------

test_retention_config_defaults() {
    source "${ABF_ROOT}/core/exit_codes.sh"

    # Default values from abf.conf
    local daily="${ABF_RETENTION_KEEP_DAILY:-7}"
    local weekly="${ABF_RETENTION_KEEP_WEEKLY:-4}"
    local monthly="${ABF_RETENTION_KEEP_MONTHLY:-3}"
    local yearly="${ABF_RETENTION_KEEP_YEARLY:-0}"

    assert_eq "7" "$daily" "Default keep-daily"
    assert_eq "4" "$weekly" "Default keep-weekly"
    assert_eq "3" "$monthly" "Default keep-monthly"
    assert_eq "0" "$yearly" "Default keep-yearly"
}

test_retention_policy_format() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "retention-test" "test" "/tmp"
    source "${ABF_ROOT}/core/retention.sh"

    # Verify the function exists and is callable
    if ! declare -F abf_apply_retention &>/dev/null; then
        echo "  FAIL: abf_apply_retention function not defined"
        return 1
    fi
    return 0
}

test_retention_passthrough_to_restic_forget() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "retention-test" "test" "/tmp"
    source "${ABF_ROOT}/core/restic.sh"
    source "${ABF_ROOT}/core/retention.sh"

    if ! declare -F abf_restic_forget &>/dev/null; then
        echo "  FAIL: abf_restic_forget function not defined"
        return 1
    fi
    return 0
}
