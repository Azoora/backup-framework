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

test_mime_message_has_date_header() {
    _abf_notify_setup

    local msg
    msg=$(_abf_build_mime_message "Test Subject" "Test Body" "test-svc")
    assert_contains "$msg" "Date:" "MIME message contains Date header"
}

test_mime_message_has_crlf() {
    _abf_notify_setup

    local msg
    msg=$(_abf_build_mime_message "Test" "Body" "svc")
    # The MIME message uses literal \r\n (4 chars) which printf converts to CRLF
    assert_contains "$msg" '\r\n' "MIME message uses CRLF line endings"
}

test_mime_message_has_mime_version() {
    _abf_notify_setup

    local msg
    msg=$(_abf_build_mime_message "Test" "Body" "svc")
    assert_contains "$msg" "MIME-Version: 1.0" "MIME message has MIME-Version header"
}

test_mime_message_has_from() {
    _abf_notify_setup

    SMTP_FROM_NAME="Test Sender"
    SMTP_FROM="test@example.com"

    local msg
    msg=$(_abf_build_mime_message "Test" "Body" "svc")
    assert_contains "$msg" "From: Test Sender <test@example.com>" "MIME message has From header"
}

test_mime_message_has_to() {
    _abf_notify_setup

    SMTP_TO="admin@example.com"
    local msg
    msg=$(_abf_build_mime_message "Test" "Body" "svc")
    assert_contains "$msg" "To: admin@example.com" "MIME message has To header"
}

test_mime_message_has_subject() {
    _abf_notify_setup

    local msg
    msg=$(_abf_build_mime_message "Test Subject Line" "Body" "svc")
    assert_contains "$msg" "Subject: Test Subject Line" "MIME message has Subject header"
}

test_mime_message_multipart_with_log() {
    _abf_notify_setup

    local tmpfile
    tmpfile=$(mktemp -t "abf-test-log-XXXXXX")
    echo "log content" > "$tmpfile"
    ABF_LOG_FILE="$tmpfile"
    SMTP_LOG_ATTACH_MAX_KB="64"

    local msg
    msg=$(_abf_build_mime_message "Test" "Body" "svc")

    assert_contains "$msg" "multipart/mixed" "MIME is multipart with log"
    assert_contains "$msg" "Content-Disposition: attachment" "MIME has attachment header"
    assert_contains "$msg" "$(printf '%s' "log content" | base64 -w0)" "MIME includes base64 log"

    rm -f "$tmpfile"
}

# ------------------------------------------------------------------
# SMTP response parser tests
# ------------------------------------------------------------------

test_smtp_response_accepts_250() {
    _abf_notify_setup

    local response="220 smtp.example.com ESMTP
250-localhost
250-AUTH LOGIN PLAIN
250 OK
334 VXNlcm5hbWU6
334 UGFzc3dvcmQ6
235 Authentication successful
250 Sender OK
250 Recipient OK
354 Enter message, ending with \".\" on a line by itself
250 OK: Message accepted
221 Bye"

    _abf_smtp_response_has_code "$response" "250" "after data"
    assert_eq "0" "$?" "Response parser accepts 250 after data"
}

test_smtp_response_rejects_550() {
    _abf_notify_setup

    local response="220 smtp.example.com ESMTP
250-localhost
250-AUTH LOGIN PLAIN
250 OK
334 VXNlcm5hbWU6
334 UGFzc3dvcmQ6
235 Authentication successful
250 Sender OK
250 Recipient OK
354 Enter message
550 5.1.1 Recipient rejected
221 Bye"

    local rc=0
    _abf_smtp_response_has_code "$response" "250" "after data" || rc=$?
    assert_eq "1" "$rc" "Response parser rejects 550 after data"
}

test_smtp_response_no_data_line() {
    _abf_notify_setup

    local response="220 smtp.example.com ESMTP
250-localhost
250 OK
221 Bye"

    local rc=0
    _abf_smtp_response_has_code "$response" "250" "after data" || rc=$?
    assert_eq "1" "$rc" "Response parser returns 1 when no DATA sent"
}

test_smtp_response_handles_openssl_noise() {
    _abf_notify_setup

    local response="depth=0 C=US, O=Example
verify error:num=20
DONE
250-localhost
250-AUTH LOGIN PLAIN
250 OK
354 Enter message
250 OK: Message accepted
221 Bye"

    _abf_smtp_response_has_code "$response" "250" "after data"
    assert_eq "0" "$?" "Response parser handles openssl noise lines"
}

# ------------------------------------------------------------------
# TCP backend tests
# ------------------------------------------------------------------

test_tcp_skips_when_tls_enabled() {
    _abf_notify_setup

    SMTP_HOST="smtp.example.com"
    SMTP_PORT="587"
    SMTP_TLS="true"

    local rc=0
    _abf_sendmail_tcp "subject" "body" "service" || rc=$?
    assert_eq "1" "$rc" "TCP backend returns 1 when TLS is enabled"
}

test_tcp_skips_when_tls_on_port_465() {
    _abf_notify_setup

    SMTP_HOST="smtp.example.com"
    SMTP_PORT="465"
    SMTP_TLS="true"

    local rc=0
    _abf_sendmail_tcp "subject" "body" "service" || rc=$?
    assert_eq "1" "$rc" "TCP backend returns 1 on port 465 with TLS"
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

# ------------------------------------------------------------------
# Verbose mode tests
# ------------------------------------------------------------------

# Set up a mock PATH so we can intercept backend executables
_abf_verbose_setup() {
    _abf_notify_setup
    export ABF_SMTP_VERBOSE="true"
    export SMTP_HOST="smtp.test.com"
    export SMTP_PORT="587"
    export SMTP_USER="user@test.com"
    export SMTP_PASS="secret"
    export SMTP_FROM_NAME="Tester"
    export SMTP_FROM="tester@test.com"
    export SMTP_TO="admin@test.com"
    export SMTP_TLS="false"
    SMTP_ENABLED="true"

    # Build a mock PATH at the front that we control
    MOCK_BINDIR=$(mktemp -d -t "abf-mock-bin-XXXXXX")
    PATH="${MOCK_BINDIR}:${PATH}"
}

_abf_verbose_teardown() {
    rm -rf "${MOCK_BINDIR:-/dev/null}"
}

test_verbose_dispatch_prints_backend_names() {
    _abf_verbose_setup

    # Mock all backends to fail so we see all names.
    # For the openssl backend (now FIFO-based), the mock must exit
    # immediately so the FIFO reader gets EOF.
    cat > "${MOCK_BINDIR}/msmtp" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
    # Openssl mock: exit immediately — FIFO writer closes, reader gets EOF
    cat > "${MOCK_BINDIR}/openssl" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
    cat > "${MOCK_BINDIR}/sendmail" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
    cat > "${MOCK_BINDIR}/mail" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
    chmod +x "${MOCK_BINDIR}/msmtp" "${MOCK_BINDIR}/openssl" "${MOCK_BINDIR}/sendmail" "${MOCK_BINDIR}/mail"

    local output
    output=$(_abf_sendmail "Test Subj" "Test Body" "test-svc" 2>&1 || true)

    assert_contains "$output" "backend[1] msmtp" "Dispatch prints msmtp backend"
    assert_contains "$output" "backend[2] openssl" "Dispatch prints openssl backend"
    assert_contains "$output" "backend[3] sendmail" "Dispatch prints sendmail backend"
    assert_contains "$output" "backend[4] mail" "Dispatch prints mail backend"
    assert_contains "$output" "backend[5] tcp" "Dispatch prints tcp backend"
    assert_contains "$output" "No delivery method succeeded" "Dispatch prints failure summary"

    _abf_verbose_teardown
}

test_verbose_msmtp_shows_command_and_stderr() {
    _abf_verbose_setup

    cat > "${MOCK_BINDIR}/msmtp" <<'SCRIPT'
#!/bin/bash
echo "msmtp: connection refused" >&2
exit 1
SCRIPT
    chmod +x "${MOCK_BINDIR}/msmtp"

    local output
    output=$(_abf_sendmail_msmtp "Test" "Body" "svc" 2>&1 || true)

    assert_contains "$output" "command: msmtp" "msmtp verbose shows command"
    assert_contains "$output" "stderr: msmtp: connection refused" "msmtp verbose shows stderr"
    assert_contains "$output" "exit code: 1" "msmtp verbose shows exit code"
    assert_contains "$output" "delivery failed" "msmtp verbose shows failure"

    _abf_verbose_teardown
}

test_verbose_msmtp_shows_accepted() {
    _abf_verbose_setup

    cat > "${MOCK_BINDIR}/msmtp" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
    chmod +x "${MOCK_BINDIR}/msmtp"

    local output
    output=$(_abf_sendmail_msmtp "Test" "Body" "svc" 2>&1 || true)

    assert_contains "$output" "delivery accepted" "msmtp verbose shows accepted"

    _abf_verbose_teardown
}

test_verbose_openssl_shows_conversation_and_response() {
    _abf_verbose_setup

    # Interactive openssl mock: reads commands, responds like real SMTP server
    cat > "${MOCK_BINDIR}/openssl" <<'SCRIPT'
#!/bin/bash
echo "220 mock.smtp ESMTP ready"
in_data=false
auth_step=0
while IFS= read -r line; do
    line="${line%%$'\r'}"
    if $in_data; then
        if [ "$line" = "." ]; then
            echo "250 OK: Message accepted"
            in_data=false
        fi
    else
        case "$line" in
            "EHLO"*) echo "250-localhost" ; echo "250 AUTH LOGIN PLAIN" ;;
            "AUTH LOGIN") echo "334 VXNlcm5hbWU6" ; auth_step=1 ;;
            "QUIT") echo "221 Bye" ; exit 0 ;;
            "DATA") echo "354 End data with <CRLF>.<CRLF>" ; in_data=true ;;
            "MAIL FROM"*) echo "250 Sender OK" ;;
            "RCPT TO"*) echo "250 Recipient OK" ;;
            *)
                if [[ "$line" =~ ^[A-Za-z0-9+/=]{2,}$ ]]; then
                    if [[ $auth_step -eq 1 ]]; then
                        echo "334 UGFzc3dvcmQ6"
                        auth_step=2
                    else
                        echo "235 Authentication successful"
                        auth_step=0
                    fi
                fi
                ;;
        esac
    fi
done
SCRIPT
    chmod +x "${MOCK_BINDIR}/openssl"

    local output
    output=$(_abf_sendmail_openssl "Test" "Body" "svc" 2>&1 || true)

    assert_contains "$output" ">> EHLO localhost" "openssl verbose shows >> EHLO"
    assert_contains "$output" ">> AUTH LOGIN" "openssl verbose shows >> AUTH LOGIN"
    assert_contains "$output" ">> MAIL FROM" "openssl verbose shows >> MAIL FROM"
    assert_contains "$output" ">> RCPT TO" "openssl verbose shows >> RCPT TO"
    assert_contains "$output" "<< 220" "openssl verbose shows greeting"
    assert_contains "$output" "<< 250-localhost" "openssl verbose shows EHLO response"
    assert_contains "$output" "message accepted (250)" "openssl verbose shows acceptance"

    _abf_verbose_teardown
}

test_verbose_openssl_masks_password() {
    _abf_verbose_setup

    # Interactive mock that verifies the password line sent by the client
    # is NOT printed raw in the verbose output
    cat > "${MOCK_BINDIR}/openssl" <<'SCRIPT'
#!/bin/bash
echo "220 mock.smtp ESMTP ready"
in_data=false
auth_step=0
while IFS= read -r line; do
    line="${line%%$'\r'}"
    if $in_data; then
        if [ "$line" = "." ]; then
            echo "250 OK: Message accepted"
            in_data=false
        fi
    else
        case "$line" in
            "EHLO"*) echo "250-localhost" ; echo "250 AUTH LOGIN PLAIN" ;;
            "AUTH LOGIN") echo "334 VXNlcm5hbWU6" ; auth_step=1 ;;
            "QUIT") echo "221 Bye" ; exit 0 ;;
            "DATA") echo "354 End data" ; in_data=true ;;
            "MAIL FROM"*) echo "250 Sender OK" ;;
            "RCPT TO"*) echo "250 Recipient OK" ;;
            *)
                if [[ "$line" =~ ^[A-Za-z0-9+/=]{2,}$ ]]; then
                    if [[ $auth_step -eq 1 ]]; then
                        echo "334 UGFzc3dvcmQ6"
                        auth_step=2
                    else
                        echo "235 Authentication successful"
                        auth_step=0
                    fi
                fi
                ;;
        esac
    fi
done
SCRIPT
    chmod +x "${MOCK_BINDIR}/openssl"

    local output
    output=$(_abf_sendmail_openssl "Test" "Body" "svc" 2>&1 || true)

    # The password line is now shown as >> [base64 password masked]
    # because the conversation display uses AUTH LOGIN state tracking
    assert_contains "$output" "password masked" "openssl verbose masks password"

    _abf_verbose_teardown
}

test_verbose_openssl_shows_connection_error() {
    _abf_verbose_setup

    # Mock exits immediately (no greeting) — FIFO reader gets EOF
    cat > "${MOCK_BINDIR}/openssl" <<'SCRIPT'
#!/bin/bash
echo "connect: Connection refused" >&2
exit 1
SCRIPT
    chmod +x "${MOCK_BINDIR}/openssl"

    local output
    output=$(_abf_sendmail_openssl "Test" "Body" "svc" 2>&1 || true)

    assert_contains "$output" "no SMTP greeting" "openssl verbose shows no greeting"
    assert_contains "$output" "Connection refused" "openssl verbose shows stderr error"

    _abf_verbose_teardown
}

test_verbose_openssl_shows_smtp_rejection() {
    _abf_verbose_setup

    # Interactive mock that rejects password
    cat > "${MOCK_BINDIR}/openssl" <<'SCRIPT'
#!/bin/bash
echo "220 mock.smtp ESMTP ready"
auth_step=0
while IFS= read -r line; do
    line="${line%%$'\r'}"
    case "$line" in
        "EHLO"*) echo "250-localhost" ; echo "250 AUTH LOGIN PLAIN" ;;
        "AUTH LOGIN") echo "334 VXNlcm5hbWU6" ; auth_step=1 ;;
        "QUIT") echo "221 Bye" ; exit 0 ;;
        *)
            if [[ "$line" =~ ^[A-Za-z0-9+/=]{2,}$ ]]; then
                if [[ $auth_step -eq 1 ]]; then
                    echo "334 UGFzc3dvcmQ6"
                    auth_step=2
                else
                    echo "535 5.7.8 Authentication credentials invalid"
                fi
            fi
            ;;
    esac
done
SCRIPT
    chmod +x "${MOCK_BINDIR}/openssl"

    local output
    output=$(_abf_sendmail_openssl "Test" "Body" "svc" 2>&1 || true)

    assert_contains "$output" "password rejected" "openssl verbose shows password rejection"
    assert_contains "$output" "535" "openssl verbose includes error code"

    _abf_verbose_teardown
}

test_verbose_tcp_skips_when_tls_enabled() {
    _abf_verbose_setup

    SMTP_TLS="true"
    SMTP_PORT="587"

    local output
    output=$(_abf_sendmail_tcp "Test" "Body" "svc" 2>&1 || true)

    assert_contains "$output" "cannot do TLS" "tcp verbose explains TLS skip"

    _abf_verbose_teardown
}

test_verbose_tcp_shows_commands() {
    _abf_verbose_setup

    # Verify _abf_smtp_tcp_cmd prints the >> command prefix
    # Use a connected pipe pair to simulate socket behavior
    local tmpf
    tmpf=$(mktemp -t "abf-tcp-test-XXXXXX")
    # Write a response first, then open fd for both rw
    printf '250 OK\r\n' > "$tmpf"
    exec 9<>"$tmpf"

    local output
    output=$(_abf_smtp_tcp_cmd 9 "EHLO localhost" "250" 2>&1 || true)
    assert_contains "$output" ">> EHLO localhost" "tcp_cmd verbose shows sent command"

    exec 9>&-
    rm -f "$tmpf"

    _abf_verbose_teardown
}

test_verbose_disabled_produces_no_output() {
    _abf_notify_setup

    export ABF_SMTP_VERBOSE="false"
    export SMTP_HOST="smtp.test.com"
    export SMTP_PORT="587"
    export SMTP_FROM="tester@test.com"
    export SMTP_TO="admin@test.com"
    SMTP_ENABLED="true"

    # Mock msmtp to succeed
    MOCK_BINDIR=$(mktemp -d -t "abf-mock-bin-XXXXXX")
    cat > "${MOCK_BINDIR}/msmtp" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
    chmod +x "${MOCK_BINDIR}/msmtp"
    PATH="${MOCK_BINDIR}:${PATH}"

    local output
    output=$(_abf_sendmail "Subj" "Body" "svc" 2>&1 || true)
    assert_eq "" "$output" "No verbose output when ABF_SMTP_VERBOSE=false"

    rm -rf "${MOCK_BINDIR}"
}

test_verbose_disabled_suppresses_backend_details() {
    _abf_notify_setup

    export ABF_SMTP_VERBOSE="false"
    export SMTP_HOST="smtp.test.com"
    export SMTP_PORT="587"
    export SMTP_FROM="tester@test.com"
    export SMTP_TO="admin@test.com"
    SMTP_ENABLED="true"

    MOCK_BINDIR=$(mktemp -d -t "abf-mock-bin-XXXXXX")
    cat > "${MOCK_BINDIR}/msmtp" <<'SCRIPT'
#!/bin/bash
echo "internal error" >&2
exit 1
SCRIPT
    chmod +x "${MOCK_BINDIR}/msmtp"
    PATH="${MOCK_BINDIR}:${PATH}"

    local output
    output=$(_abf_sendmail_msmtp "Subj" "Body" "svc" 2>&1 || true)
    assert_eq "" "$output" "No verbose msmtp output when ABF_SMTP_VERBOSE=false"

    rm -rf "${MOCK_BINDIR}"
}
