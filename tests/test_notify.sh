# ---------------------------------------------------------------------------
# Tests for the email notification module
# ---------------------------------------------------------------------------

_abf_notify_setup() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "notify-test" "test" "/tmp"
    source "${ABF_ROOT}/core/notify.sh"
}

test_notify_disabled_by_default() {
    _abf_notify_setup

    SMTP_ENABLED="false"
    abf_notify_send "SUCCESS" "test-svc" "test details"
    assert_eq "$ABF_EXIT_OK" "$?" "Notify should succeed when disabled"
}

test_email_body_format() {
    _abf_notify_setup

    local body
    body=$(_abf_build_email_body "SUCCESS" "test-svc" "custom details")

    assert_contains "$body" "SUCCESS" "Body contains status"
    assert_contains "$body" "test-svc" "Body contains service name"
    assert_contains "$body" "custom details" "Body contains custom details"
    assert_contains "$body" "Backup Framework" "Body contains project name"
}

test_email_body_includes_snapshot() {
    _abf_notify_setup

    ABF_SNAPSHOT_ID="abc123"
    local body
    body=$(_abf_build_email_body "SUCCESS" "test-svc" "")
    assert_contains "$body" "abc123" "Body contains snapshot ID"
}

test_email_body_includes_timing() {
    _abf_notify_setup

    ABF_BACKUP_START_TIME="2025-01-01T00:00:00+0000"
    ABF_BACKUP_END_TIME="2025-01-01T01:30:00+0000"
    ABF_BACKUP_DURATION="01:30:00"
    local body
    body=$(_abf_build_email_body "SUCCESS" "test-svc" "")
    assert_contains "$body" "2025-01-01T00:00:00" "Body contains start time"
    assert_contains "$body" "2025-01-01T01:30:00" "Body contains end time"
    assert_contains "$body" "01:30:00" "Body contains duration"
}

test_email_body_includes_verify_and_dest() {
    _abf_notify_setup

    ABF_BACKUP_REPO_VERIFY_STATUS="SUCCESS"
    ABF_BACKUP_DEST_RESULTS="local:SUCCESS, onedrive:SUCCESS"
    local body
    body=$(_abf_build_email_body "SUCCESS" "test-svc" "")
    assert_contains "$body" "Repo Verify" "Body contains repo verify"
    assert_contains "$body" "Destinations" "Body contains destinations"
    assert_contains "$body" "local:SUCCESS" "Body contains dest results"
}

test_split_recipients_single() {
    _abf_notify_setup

    SMTP_TO="admin@example.com"
    local addrs=()
    while IFS= read -r addr; do
        [[ -n "$addr" ]] && addrs+=("$addr")
    done < <(_abf_split_recipients)
    assert_eq "1" "${#addrs[@]}" "Single recipient count"
    assert_eq "admin@example.com" "${addrs[0]-}" "Single recipient parsed"
}

test_split_recipients_multiple() {
    _abf_notify_setup

    SMTP_TO="a@x.com, b@y.com, c@z.com"
    local addrs=()
    while IFS= read -r addr; do
        [[ -n "$addr" ]] && addrs+=("$addr")
    done < <(_abf_split_recipients)
    assert_eq "3" "${#addrs[@]}" "Three recipients parsed"
    assert_eq "a@x.com" "${addrs[0]}" "First recipient"
    assert_eq "b@y.com" "${addrs[1]}" "Second recipient trimmed"
    assert_eq "c@z.com" "${addrs[2]}" "Third recipient trimmed"
}

test_split_recipients_empty() {
    _abf_notify_setup

    SMTP_TO=""
    local result
    result=$(_abf_split_recipients)
    assert_eq "" "$result" "Empty recipients returns empty"
}

test_format_from_with_name() {
    _abf_notify_setup

    SMTP_FROM_NAME="Test Sender"
    SMTP_FROM="test@example.com"
    local result
    result=$(_abf_format_from)
    assert_eq "Test Sender <test@example.com>" "$result" "From header with name"
}

test_format_from_without_name() {
    _abf_notify_setup

    SMTP_FROM_NAME=""
    SMTP_FROM="noreply@example.com"
    local result
    result=$(_abf_format_from)
    assert_eq "noreply@example.com" "$result" "From header without name"
}

test_format_from_empty_email() {
    _abf_notify_setup

    SMTP_FROM_NAME="Anything"
    SMTP_FROM=""
    local result
    result=$(_abf_format_from)
    assert_eq "" "$result" "Empty email returns empty"
}

test_generate_smtp_config_output() {
    _abf_notify_setup

    SMTP_HOST="mail.example.com"
    SMTP_PORT="465"
    SMTP_TLS="true"
    SMTP_USER="user@x.com"
    SMTP_PASS="secret123"
    SMTP_FROM_NAME="My App"
    SMTP_FROM="app@x.com"
    SMTP_TO="admin@x.com"
    SMTP_ENABLED="true"

    local cfg
    cfg=$(_abf_generate_smtp_config)
    assert_contains "$cfg" "SMTP_HOST=\"mail.example.com\"" "Config contains host"
    assert_contains "$cfg" "SMTP_PORT=\"465\"" "Config contains port"
    assert_contains "$cfg" "SMTP_TLS=\"true\"" "Config contains TLS"
    assert_contains "$cfg" "SMTP_USER=\"user@x.com\"" "Config contains user"
    assert_contains "$cfg" "SMTP_PASS=\"secret123\"" "Config contains pass"
    assert_contains "$cfg" "SMTP_FROM_NAME=\"My App\"" "Config contains from name"
    assert_contains "$cfg" "SMTP_FROM=\"app@x.com\"" "Config contains from email"
    assert_contains "$cfg" "SMTP_TO=\"admin@x.com\"" "Config contains to"
    assert_contains "$cfg" "SMTP_ENABLED=\"true\"" "Config contains enabled"
    assert_contains "$cfg" "SMTP_LOG_ATTACH_MAX_KB" "Config contains attach max"
}

test_generate_smtp_config_defaults() {
    _abf_notify_setup

    SMTP_HOST=""
    SMTP_PORT=""
    SMTP_TLS=""
    SMTP_USER=""
    SMTP_PASS=""
    SMTP_FROM_NAME=""
    SMTP_FROM=""
    SMTP_TO=""
    SMTP_ENABLED=""

    local cfg
    cfg=$(_abf_generate_smtp_config)
    assert_contains "$cfg" "SMTP_PORT=\"587\"" "Config defaults port to 587"
    assert_contains "$cfg" "SMTP_FROM_NAME=\"Backup Framework\"" "Config defaults from name"
    assert_contains "$cfg" "SMTP_LOG_ATTACH_MAX_KB=\"64\"" "Config defaults attach max"
}

test_log_attachment_small_file() {
    _abf_notify_setup

    local tmpfile
    tmpfile=$(mktemp -t "abf-test-log-XXXXXX")
    echo "test log content" > "$tmpfile"
    ABF_LOG_FILE="$tmpfile"
    SMTP_LOG_ATTACH_MAX_KB="64"

    local content
    content=$(_abf_read_log_for_attachment) || true
    assert_eq "test log content" "$content" "Small log file attached"

    rm -f "$tmpfile"
}

test_log_attachment_large_file() {
    _abf_notify_setup

    local tmpfile
    tmpfile=$(mktemp -t "abf-test-log-XXXXXX")
    dd if=/dev/zero bs=1024 count=128 of="$tmpfile" 2>/dev/null
    ABF_LOG_FILE="$tmpfile"
    SMTP_LOG_ATTACH_MAX_KB="64"

    local content
    content=$(_abf_read_log_for_attachment) || true
    assert_eq "" "$content" "Large log file not attached"

    rm -f "$tmpfile"
}

test_log_attachment_missing_file() {
    _abf_notify_setup

    ABF_LOG_FILE="/nonexistent/path.log"
    SMTP_LOG_ATTACH_MAX_KB="64"

    local rc=0
    local content
    content=$(_abf_read_log_for_attachment) || rc=$?
    assert_eq "" "$content" "Missing log file returns empty"
    assert_eq "1" "$rc" "Missing log file returns 1"
}

test_notify_status_mapping_success() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "notify-test" "test" "/tmp"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/notify.sh"

    SMTP_ENABLED="false"

    local captured=""
    abf_notify_send() {
        captured="status=$1 service=$2 details=$3"
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

test_wizard_sets_smtp_enabled_true() {
    _abf_notify_setup

    # Simulate what the wizard does: set SMTP_ENABLED before generating config
    SMTP_ENABLED="true"
    SMTP_HOST="mail.example.com"
    SMTP_FROM="app@x.com"
    SMTP_TO="admin@x.com"

    local cfg
    cfg=$(_abf_generate_smtp_config)
    assert_contains "$cfg" "SMTP_ENABLED=\"true\"" "Wizard generates SMTP_ENABLED=true"
}

test_test_email_success_output() {
    _abf_notify_setup

    _abf_sendmail() { return 0; }

    SMTP_HOST="smtp.test.com"
    SMTP_PORT="587"
    SMTP_USER="user"
    SMTP_PASS="pass"
    SMTP_FROM_NAME="Tester"
    SMTP_FROM="tester@test.com"
    SMTP_TO="admin@test.com"
    SMTP_TLS="true"
    SMTP_ENABLED="true"

    local output
    output=$(abf_notify_send_test 2>&1 || true)
    assert_contains "$output" "✓" "Success output shows checkmark"
    assert_contains "$output" "sent successfully" "Success message"
}

test_test_email_failure_output() {
    _abf_notify_setup

    _abf_sendmail() { return 1; }

    SMTP_HOST="smtp.test.com"
    SMTP_FROM="tester@test.com"
    SMTP_TO="admin@test.com"
    SMTP_ENABLED="true"

    local output
    output=$(abf_notify_send_test 2>&1 || true)
    assert_contains "$output" "✗" "Failure output shows X mark"
    assert_contains "$output" "failed" "Failure message"
}

test_test_email_no_host_reason() {
    _abf_notify_setup

    _abf_sendmail() { return 1; }

    SMTP_HOST=""
    SMTP_FROM="tester@test.com"
    SMTP_TO="admin@test.com"
    SMTP_ENABLED="true"

    local output
    output=$(abf_notify_send_test 2>&1 || true)
    assert_contains "$output" "host is not configured" "Shows host reason"
}

test_test_email_no_from_reason() {
    _abf_notify_setup

    _abf_sendmail() { return 1; }

    SMTP_HOST="smtp.test.com"
    SMTP_FROM=""
    SMTP_TO="admin@test.com"
    SMTP_ENABLED="true"

    local output
    output=$(abf_notify_send_test 2>&1 || true)
    assert_contains "$output" "From email" "Shows from reason"
}

test_test_email_no_to_reason() {
    _abf_notify_setup

    _abf_sendmail() { return 1; }

    SMTP_HOST="smtp.test.com"
    SMTP_FROM="tester@test.com"
    SMTP_TO=""
    SMTP_ENABLED="true"

    local output
    output=$(abf_notify_send_test 2>&1 || true)
    assert_contains "$output" "Recipient email" "Shows recipient reason"
}

test_notify_send_test_email_structure() {
    _abf_notify_setup

    local captured=""
    _abf_sendmail() {
        captured="subject=$1 body_preview=${2:0:80} service=$3"
    }

    SMTP_HOST="smtp.test.com"
    SMTP_PORT="587"
    SMTP_USER="user"
    SMTP_PASS="pass"
    SMTP_FROM_NAME="Tester"
    SMTP_FROM="tester@test.com"
    SMTP_TO="admin@test.com"
    SMTP_TLS="true"
    SMTP_ENABLED="true"

    abf_notify_send_test
    assert_contains "$captured" "TEST" "Test email subject contains TEST"
    assert_contains "$captured" "notification-test" "Test email service name"
}
