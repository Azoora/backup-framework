# ---------------------------------------------------------------------------
# Tests for the email notification module
# ---------------------------------------------------------------------------

test_notify_disabled_by_default() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "notify-test" "test" "/tmp"
    source "${ABF_ROOT}/core/notify.sh"

    # SMTP_ENABLED defaults to false, so notify should return OK without sending
    SMTP_ENABLED="false"
    abf_notify_send "SUCCESS" "test-svc" "test details"
    assert_eq "$ABF_EXIT_OK" "$?" "Notify should succeed when disabled"
}

test_email_body_format() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "notify-test" "test" "/tmp"
    source "${ABF_ROOT}/core/notify.sh"

    local body
    body=$(_abf_build_email_body "SUCCESS" "test-svc" "custom details")

    assert_contains "$body" "SUCCESS" "Body contains status"
    assert_contains "$body" "test-svc" "Body contains service name"
    assert_contains "$body" "custom details" "Body contains custom details"
    assert_contains "$body" "Backup Framework" "Body contains project name"
}

test_smtp_config_defaults() {
    assert_eq "false" "${SMTP_ENABLED:-false}" "SMTP disabled by default"
    assert_eq "" "${SMTP_HOST:-}" "SMTP host empty by default"
}

test_notify_status_mapping_success() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "notify-test" "test" "/tmp"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/notify.sh"

    SMTP_ENABLED="false"

    # Capture notify_send calls via mock
    local captured=""
    abf_notify_send() {
        captured="status=$1 service=$2"
    }

    _abf_notify_result "$ABF_EXIT_OK" "test-svc"
    assert_contains "$captured" "status=SUCCESS" "OK maps to SUCCESS"
    assert_contains "$captured" "service=test-svc" "Service name passed through"
}

test_notify_status_mapping_warning() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "notify-test" "test" "/tmp"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/notify.sh"

    SMTP_ENABLED="false"

    local captured=""
    abf_notify_send() {
        captured="status=$1 service=$2"
    }

    _abf_notify_result "$ABF_EXIT_VERIFICATION_FAILED" "test-svc"
    assert_contains "$captured" "status=WARNING" "VERIFICATION_FAILED maps to WARNING"
}

test_notify_status_mapping_failed() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "notify-test" "test" "/tmp"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/notify.sh"

    SMTP_ENABLED="false"

    local captured=""
    abf_notify_send() {
        captured="status=$1 service=$2"
    }

    _abf_notify_result "$ABF_EXIT_BACKUP_FAILED" "test-svc"
    assert_contains "$captured" "status=FAILED" "BACKUP_FAILED maps to FAILED"
}
