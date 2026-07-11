# ---------------------------------------------------------------------------
# notify.sh  --  Email notification system
#
# Sends SMTP email notifications on backup success/failure.
# Delivery backends (tried in order):
#   1. msmtp  -- proper SMTP client with TLS (best)
#   2. openssl s_client -- direct SMTP with TLS via openssl
#   3. sendmail  -- local MTA
#   4. mail  -- local MTA
#   5. bash /dev/tcp -- plain SMTP only (no TLS, port 25 only)
# ---------------------------------------------------------------------------

# ------------------------------------------------------------------
# Global state set by core.sh for email enrichment
# ------------------------------------------------------------------

ABF_BACKUP_START_TIME=""
ABF_BACKUP_END_TIME=""
ABF_BACKUP_DURATION=""
ABF_BACKUP_REPO_VERIFY_STATUS=""
ABF_BACKUP_DEST_RESULTS=""

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

_abf_split_recipients() {
    local to="${SMTP_TO:-}"
    if [[ -z "$to" ]]; then
        echo ""
        return
    fi
    local IFS=,
    for addr in $to; do
        addr="$(echo "$addr" | xargs)"
        [[ -n "$addr" ]] && echo "$addr"
    done
}

_abf_format_from() {
    local name="${SMTP_FROM_NAME:-}"
    local email="${SMTP_FROM:-}"
    if [[ -z "$email" ]]; then
        echo ""
        return
    fi
    if [[ -n "$name" ]]; then
        echo "${name} <${email}>"
    else
        echo "${email}"
    fi
}

# ------------------------------------------------------------------
# Main notification dispatch
# ------------------------------------------------------------------

abf_notify_send() {
    local status="$1"
    local service="$2"
    local extra_details="${3:-}"

    if [[ "${SMTP_ENABLED:-false}" != "true" ]]; then
        return "$ABF_EXIT_OK"
    fi

    local subject body
    subject="[Backup Framework] ${status} - ${service} backup - $(hostname)"
    body=$( _abf_build_email_body "$status" "$service" "$extra_details" )

    _abf_sendmail "$subject" "$body" "$service"
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        abf_log_warning "Failed to send email notification"
    fi
    return $rc
}

# ------------------------------------------------------------------
# Test email
# ------------------------------------------------------------------

abf_notify_send_test() {
    local status="TEST"
    local service="notification-test"
    local hostname
    hostname=$(hostname)
    local body
    body=$(cat <<EOF
This is a test email from Backup Framework.

Configuration:
  SMTP Host:       ${SMTP_HOST:-<not set>}
  SMTP Port:       ${SMTP_PORT:-25}
  SMTP TLS:        ${SMTP_TLS:-false}
  SMTP User:       ${SMTP_USER:-<not set>}
  SMTP From Name:  ${SMTP_FROM_NAME:-Backup Framework}
  SMTP From:       ${SMTP_FROM:-<not set>}
  SMTP To:         ${SMTP_TO:-<not set>}

If you receive this, SMTP is configured correctly.

---
Backup Framework v$(cat "${ABF_ROOT}/VERSION" 2>/dev/null || echo "unknown")
EOF
)

    local subject="[Backup Framework] TEST - SMTP configuration test - ${hostname}"
    if _abf_sendmail "$subject" "$body" "$service"; then
        echo "  ✓ Test email sent successfully"
        return 0
    else
        local reason=""
        if [[ -z "${SMTP_HOST:-}" ]]; then
            reason="SMTP host is not configured"
        elif [[ -z "${SMTP_FROM:-}" ]]; then
            reason="From email is not configured"
        elif [[ -z "${SMTP_TO:-}" ]]; then
            reason="Recipient email is not configured"
        else
            reason="Check SMTP settings or network connectivity"
        fi
        echo "  ✗ Test email failed" >&2
        echo "    ${reason}" >&2
        return 1
    fi
}

# ------------------------------------------------------------------
# Internal: build email body
# ------------------------------------------------------------------

_abf_build_email_body() {
    local status="$1"
    local service="$2"
    local extra_details="${3:-}"

    local hostname
    hostname=$(hostname)
    local version
    version=$(cat "${ABF_ROOT}/VERSION" 2>/dev/null || echo "unknown")

    cat <<EOF
Backup Framework - Backup Report
=================================
Status:               ${status}
Service:              ${service}
Hostname:             ${hostname}
Timestamp:            $(date -u +"%Y-%m-%dT%H:%M:%S%z")
EOF

    if [[ -n "${ABF_SNAPSHOT_ID:-}" ]]; then
        echo "Snapshot ID:         ${ABF_SNAPSHOT_ID}"
    fi

    if [[ -n "${ABF_BACKUP_START_TIME:-}" ]]; then
        echo "Start Time:          ${ABF_BACKUP_START_TIME}"
    fi

    if [[ -n "${ABF_BACKUP_END_TIME:-}" ]]; then
        echo "End Time:            ${ABF_BACKUP_END_TIME}"
    fi

    if [[ -n "${ABF_BACKUP_DURATION:-}" ]]; then
        echo "Duration:            ${ABF_BACKUP_DURATION}"
    fi

    if [[ -n "${ABF_BACKUP_REPO_VERIFY_STATUS:-}" ]]; then
        echo "Repo Verify:         ${ABF_BACKUP_REPO_VERIFY_STATUS}"
    fi

    if [[ -n "${ABF_BACKUP_DEST_RESULTS:-}" ]]; then
        echo "Destinations:        ${ABF_BACKUP_DEST_RESULTS}"
    fi

    echo ""

    if [[ -n "$extra_details" ]]; then
        echo "${extra_details}"
        echo ""
    fi

    echo "---"
    echo "Backup Framework v${version}"
}

_abf_read_log_for_attachment() {
    local log_file="${ABF_LOG_FILE:-}"
    local max_kb="${SMTP_LOG_ATTACH_MAX_KB:-64}"

    if [[ -z "$log_file" ]] || [[ ! -f "$log_file" ]]; then
        return 1
    fi

    local size_bytes
    size_bytes=$(stat -c%s "$log_file" 2>/dev/null || stat -f%z "$log_file" 2>/dev/null || echo "0")
    local max_bytes=$((max_kb * 1024))

    if [[ "$size_bytes" -gt "$max_bytes" ]]; then
        abf_log_debug "Log file too large for attachment: ${size_bytes} > ${max_bytes} bytes"
        return 1
    fi

    cat "$log_file"
}

# ------------------------------------------------------------------
# Build RFC-compliant MIME message (with CRLF)
# ------------------------------------------------------------------

_abf_build_mime_message() {
    local subject="$1"
    local body="$2"
    local service="$3"
    local log_content

    local from
    from=$(_abf_format_from)
    local recipients
    recipients=$(paste -sd, <(_abf_split_recipients))

    log_content=$(_abf_read_log_for_attachment) || true

    local boundary="abf-boundary-$(date +%s)-$$"
    local date_header
    date_header=$(date -R 2>/dev/null || date +"%a, %d %b %Y %H:%M:%S %z")

    local msg=""

    _abf_mime_append "From: ${from}"
    _abf_mime_append "To: ${recipients}"
    _abf_mime_append "Subject: ${subject}"
    _abf_mime_append "Date: ${date_header}"
    _abf_mime_append "MIME-Version: 1.0"

    if [[ -n "$log_content" ]]; then
        _abf_mime_append "Content-Type: multipart/mixed; boundary=\"${boundary}\""
        _abf_mime_append ""
        _abf_mime_append "--${boundary}"
        _abf_mime_append "Content-Type: text/plain; charset=UTF-8"
        _abf_mime_append "Content-Transfer-Encoding: 7bit"
        _abf_mime_append ""
        _abf_mime_append "$body"
        _abf_mime_append ""
        _abf_mime_append "--${boundary}"
        _abf_mime_append "Content-Type: text/plain; charset=UTF-8"
        _abf_mime_append "Content-Disposition: attachment; filename=\"${service}_backup.log\""
        _abf_mime_append "Content-Transfer-Encoding: base64"
        _abf_mime_append ""
        _abf_mime_append "$(printf '%s' "$log_content" | base64)"
        _abf_mime_append ""
        _abf_mime_append "--${boundary}--"
    else
        _abf_mime_append "Content-Type: text/plain; charset=UTF-8"
        _abf_mime_append ""
        _abf_mime_append "${body}"
    fi

    printf '%s' "$msg"
}

_abf_mime_append() {
    msg="${msg}${1}\r\n"
}

# ==================================================================
# SMTP Delivery Backends
# ==================================================================

# ------------------------------------------------------------------
# _abf_sendmail  --  Main dispatch, tries backends in order
# ------------------------------------------------------------------

_abf_sendmail() {
    local subject="$1"
    local body="$2"
    local service="$3"

    local v; v() { [[ "${ABF_SMTP_VERBOSE:-}" == "true" ]] && echo "$*" >&2; }

    # 1) msmtp with full SMTP config (best: handles TLS natively)
    v "  backend[1] msmtp: $(command -v msmtp || echo 'not found')"
    if command -v msmtp &>/dev/null; then
        _abf_sendmail_msmtp "$subject" "$body" "$service" && return 0
    fi

    # 2) openssl s_client (direct SMTP with TLS)
    v "  backend[2] openssl: $(command -v openssl || echo 'not found')"
    if command -v openssl &>/dev/null; then
        _abf_sendmail_openssl "$subject" "$body" "$service" && return 0
    fi

    # 3) sendmail (local MTA)
    v "  backend[3] sendmail: $(command -v sendmail || echo 'not found')"
    if command -v sendmail &>/dev/null; then
        _abf_sendmail_sendmail "$subject" "$body" "$service" && return 0
    fi

    # 4) mail (local MTA)
    v "  backend[4] mail: $(command -v mail || echo 'not found')"
    if command -v mail &>/dev/null; then
        _abf_sendmail_mail "$subject" "$body" "$service" && return 0
    fi

    # 5) bash /dev/tcp (plain SMTP, no TLS)
    v "  backend[5] tcp: /dev/tcp"
    _abf_sendmail_tcp "$subject" "$body" "$service" && return 0

    v "  SMTP: No delivery method succeeded"
    return 1
}

# ------------------------------------------------------------------
# Backend: msmtp with inline SMTP config
# ------------------------------------------------------------------

_abf_sendmail_msmtp() {
    local subject="$1"
    local body="$2"
    local service="$3"

    local v; v() { [[ "${ABF_SMTP_VERBOSE:-}" == "true" ]] && echo "  msmtp: $*" >&2; }

    if [[ -z "${SMTP_HOST:-}" ]]; then
        v "SMTP_HOST not set, skipping"
        return 1
    fi

    local msg
    msg=$(_abf_build_mime_message "$subject" "$body" "$service")

    local rcpt_args=()
    while IFS= read -r addr; do
        [[ -n "$addr" ]] && rcpt_args+=("$addr")
    done < <(_abf_split_recipients)

    if [[ ${#rcpt_args[@]} -eq 0 ]]; then
        v "no recipients"
        return 1
    fi

    local msmtp_args=(
        "--host=${SMTP_HOST}"
        "--port=${SMTP_PORT:-587}"
        "--from=${SMTP_FROM:-}"
    )

    if [[ "${SMTP_TLS:-false}" == "true" ]]; then
        msmtp_args+=("--tls=on")
        if [[ "${SMTP_PORT:-587}" == "587" ]]; then
            msmtp_args+=("--tls-starttls=on")
        fi
    else
        msmtp_args+=("--tls=off")
    fi

    if [[ -n "${SMTP_USER:-}" ]]; then
        msmtp_args+=("--auth=login" "--user=${SMTP_USER}")
        if [[ -n "${SMTP_PASS:-}" ]]; then
            local pw_file
            pw_file=$(mktemp -t "abf-msmtp-pw-XXXXXX")
            printf '%s' "${SMTP_PASS}" > "$pw_file"
            chmod 600 "$pw_file"
            msmtp_args+=("--passwordeval=cat ${pw_file}")
        fi
    fi

    local masked_args=()
    local a
    for a in "${msmtp_args[@]}"; do
        if [[ "$a" == --passwordeval=cat* ]]; then
            masked_args+=("--passwordeval=cat <password>")
        else
            masked_args+=("$a")
        fi
    done
    v "command: msmtp ${masked_args[*]} ${rcpt_args[*]}"

    local msmtp_stderr
    msmtp_stderr=$(mktemp -t "abf-msmtp-err-XXXXXX")
    printf '%s\r\n' "$msg" | msmtp "${msmtp_args[@]}" "${rcpt_args[@]}" 2>"$msmtp_stderr"
    local rc=$?

    if [[ -n "${pw_file:-}" ]]; then
        rm -f "${pw_file:-}"
    fi

    if [[ -s "$msmtp_stderr" ]]; then
        v "stderr: $(cat "$msmtp_stderr")"
    fi
    rm -f "$msmtp_stderr"

    v "exit code: $rc"

    if [[ $rc -eq 0 ]]; then
        v "delivery accepted"
        return 0
    fi

    v "delivery failed"
    return 1
}

# ------------------------------------------------------------------
# Backend: openssl s_client (TLS-capable direct SMTP)
# ------------------------------------------------------------------

_abf_sendmail_openssl() {
    local subject="$1"
    local body="$2"
    local service="$3"

    local v; v() { [[ "${ABF_SMTP_VERBOSE:-}" == "true" ]] && echo "  openssl: $*" >&2; }

    if [[ -z "${SMTP_HOST:-}" ]]; then
        v "SMTP_HOST not set, skipping"
        return 1
    fi

    local port="${SMTP_PORT:-587}"
    local from="${SMTP_FROM:-}"
    local from_header
    from_header=$(_abf_format_from)
    local recipients
    recipients=$(paste -sd, <(_abf_split_recipients))

    # Build the SMTP conversation (CRLF line endings)
    local conv=""
    _abf_smtp_append_conv "EHLO localhost"

    if [[ -n "${SMTP_USER:-}" ]]; then
        _abf_smtp_append_conv "AUTH LOGIN"
        _abf_smtp_append_conv "$(printf '%s' "${SMTP_USER}" | base64 -w0)"
        _abf_smtp_append_conv "$(printf '%s' "${SMTP_PASS}" | base64 -w0)"
    fi

    _abf_smtp_append_conv "MAIL FROM:<${from}>"

    while IFS= read -r addr; do
        [[ -n "$addr" ]] && _abf_smtp_append_conv "RCPT TO:<${addr}>"
    done < <(_abf_split_recipients)

    local date_header
    date_header=$(date -R 2>/dev/null || date +"%a, %d %b %Y %H:%M:%S %z")

    _abf_smtp_append_conv "DATA"
    _abf_smtp_append_conv "From: ${from_header}"
    _abf_smtp_append_conv "To: ${recipients}"
    _abf_smtp_append_conv "Subject: ${subject}"
    _abf_smtp_append_conv "Date: ${date_header}"
    _abf_smtp_append_conv "MIME-Version: 1.0"
    _abf_smtp_append_conv "Content-Type: text/plain; charset=UTF-8"
    _abf_smtp_append_conv ""
    _abf_smtp_append_conv "${body}"
    _abf_smtp_append_conv "."
    _abf_smtp_append_conv "QUIT"

    # Verbose: show the SMTP conversation (mask base64 password)
    if [[ "${ABF_SMTP_VERBOSE:-}" == "true" ]]; then
        echo "  openssl: SMTP conversation to send ---" >&2
        local auth_pending=0
        # $conv uses literal \r\n strings — convert to newlines for display
        while IFS= read -r line; do
            if echo "$line" | grep -qE '^AUTH LOGIN$'; then
                auth_pending=1
                echo "  AUTH LOGIN" >&2
            elif [[ $auth_pending -eq 1 ]]; then
                # First base64 line after AUTH LOGIN = username
                echo "  [base64 username]" >&2
                auth_pending=2
            elif [[ $auth_pending -eq 2 ]]; then
                # Second base64 line = password — mask it
                echo "  [base64 password masked]" >&2
                auth_pending=0
            else
                echo "  ${line}" >&2
            fi
        done < <(echo "$conv" | sed 's/\\r\\n/\n/g')
        echo "  ---" >&2
    fi

    local openssl_args=(
        "-connect" "${SMTP_HOST}:${port}"
        "-crlf"
        "-quiet"
        "-no_ign_eof"
    )

    # STARTTLS for port 587 with TLS enabled
    if [[ "${SMTP_TLS:-false}" == "true" ]] && [[ "$port" == "587" ]]; then
        v "using STARTTLS (port 587)"
        openssl_args+=("-starttls" "smtp")
    elif [[ "${SMTP_TLS:-false}" == "true" ]]; then
        v "using implicit TLS (port ${port})"
    else
        v "plain text (no TLS)"
    fi

    v "connecting to ${SMTP_HOST}:${port}..."

    local openssl_stderr
    openssl_stderr=$(mktemp -t "abf-openssl-err-XXXXXX")

    # Send conversation and capture response (preserve stderr for diagnostics)
    local response
    response=$(printf '%s' "$conv" | openssl s_client "${openssl_args[@]}" 2>"$openssl_stderr")
    local rc=$?

    local err_output=""
    if [[ -s "$openssl_stderr" ]]; then
        err_output=$(cat "$openssl_stderr")
    fi
    rm -f "$openssl_stderr"

    if [[ $rc -ne 0 ]]; then
        v "connection failed (exit $rc)"
        if [[ -n "$err_output" ]]; then
            if [[ "${ABF_SMTP_VERBOSE:-}" == "true" ]]; then
                echo "  openssl: stderr ---" >&2
                echo "$err_output" | sed 's/^/  /' >&2
                echo "  ---" >&2
            fi
            # Extract the most relevant error line
            local err_line
            err_line=$(echo "$err_output" | grep -iE 'error|failed|refused|timeout|connect|certificate' | head -1)
            if [[ -n "$err_line" ]]; then
                v "error: ${err_line}"
            fi
        fi
        return 1
    fi

    if [[ -z "$response" ]]; then
        v "empty response from server"
        if [[ -n "$err_output" ]]; then
            if [[ "${ABF_SMTP_VERBOSE:-}" == "true" ]]; then
                echo "  openssl: stderr ---" >&2
                echo "$err_output" | sed 's/^/  /' >&2
                echo "  ---" >&2
            fi
        fi
        return 1
    fi

    if [[ "${ABF_SMTP_VERBOSE:-}" == "true" ]]; then
        echo "  openssl: response ---" >&2
        echo "$response" | sed 's/^/  /' >&2
        echo "  ---" >&2
    fi

    # Check for final success after DATA terminator
    # After ".", server returns "250" if message was accepted
    if _abf_smtp_response_has_code "$response" "250" "after data"; then
        v "message accepted (250)"
        return 0
    fi

    # Extract the SMTP error for diagnostics
    local err_message=""
    err_message=$(echo "$response" | grep -oE '[0-9]{3} .*' | tail -1)
    if [[ -n "$err_message" ]]; then
        v "SMTP rejected: ${err_message}"
    else
        v "SMTP rejected (no recognizable error code)"
    fi

    return 1
}

_abf_smtp_append_conv() {
    conv="${conv}${1}\r\n"
}

# ------------------------------------------------------------------
# SMTP response parser: check that the last response before QUIT is 2xx
# This is the critical check: after DATA + ".", the server must return 250.
# ------------------------------------------------------------------

_abf_smtp_response_has_code() {
    local response="$1"
    local target_code="$2"
    local context="${3:-}"

    # Find the response after "DATA" and the message terminator "."
    # This is the response that indicates whether the server accepted the email.
    # It will be a line like "250 OK" or "550 Rejected"

    # Strategy: find the last "354" (DATA accepted) and check the next 2xx/3xx line
    local data_line_found=false
    local after_data_code=""

    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//')
        [[ -z "$line" ]] && continue

        local code="${line:0:3}"
        # Skip openssl noise lines (depth=, verify, etc.)
        if echo "$line" | grep -qE '^(depth=|verify |DONE|---)'; then
            continue
        fi
        # Skip base64 auth blobs
        if echo "$line" | grep -qE '^[A-Za-z0-9+/=]{20,}$'; then
            continue
        fi

        if [[ "$code" == "354" ]]; then
            data_line_found=true
            after_data_code=""
        elif $data_line_found && [[ "$code" =~ ^[0-9]{3}$ ]]; then
            after_data_code="$code"
            if [[ "$code" == "$target_code" ]]; then
                return 0
            fi
        fi
    done < <(echo "$response")

    return 1
}

# ------------------------------------------------------------------
# Backend: sendmail (local MTA)
# ------------------------------------------------------------------

_abf_sendmail_sendmail() {
    local subject="$1"
    local body="$2"
    local service="$3"

    local v; v() { [[ "${ABF_SMTP_VERBOSE:-}" == "true" ]] && echo "  sendmail: $*" >&2; }

    local msg
    msg=$(_abf_build_mime_message "$subject" "$body" "$service")

    v "command: /usr/sbin/sendmail -t"

    local stmp
    stmp=$(mktemp -t "abf-sendmail-err-XXXXXX")
    printf '%s\r\n' "$msg" | /usr/sbin/sendmail -t 2>"$stmp"
    local rc=$?

    if [[ -s "$stmp" ]]; then
        v "stderr: $(cat "$stmp")"
    fi
    rm -f "$stmp"

    v "exit code: $rc"

    if [[ $rc -eq 0 ]]; then
        v "delivery accepted"
        return 0
    fi

    v "delivery failed"
    return 1
}

# ------------------------------------------------------------------
# Backend: mail (local MTA)
# ------------------------------------------------------------------

_abf_sendmail_mail() {
    local subject="$1"
    local body="$2"
    local service="$3"

    local v; v() { [[ "${ABF_SMTP_VERBOSE:-}" == "true" ]] && echo "  mail: $*" >&2; }

    local from
    from=$(_abf_format_from)

    local first_rcpt=""
    local cc_rcpts=()
    local first=true
    while IFS= read -r addr; do
        [[ -z "$addr" ]] && continue
        if $first; then
            first_rcpt="$addr"
            first=false
        else
            cc_rcpts+=("$addr")
        fi
    done < <(_abf_split_recipients)

    if [[ -z "$first_rcpt" ]]; then
        v "no recipients"
        return 1
    fi

    local cc_arg=""
    if [[ ${#cc_rcpts[@]} -gt 0 ]]; then
        cc_arg=$(IFS=,; echo "${cc_rcpts[*]}")
    fi

    local mail_cmd=("mail" "-s" "$subject" "-a" "From: ${from}")
    [[ -n "$cc_arg" ]] && mail_cmd+=("-c" "$cc_arg")
    mail_cmd+=("$first_rcpt")

    v "command: ${mail_cmd[*]}"
    v "body: piped via stdin"

    local mtmp
    mtmp=$(mktemp -t "abf-mail-err-XXXXXX")
    printf '%s\n' "$body" | "${mail_cmd[@]}" 2>"$mtmp"
    local rc=$?

    if [[ -s "$mtmp" ]]; then
        v "stderr: $(cat "$mtmp")"
    fi
    rm -f "$mtmp"

    v "exit code: $rc"

    if [[ $rc -eq 0 ]]; then
        v "delivery accepted"
        return 0
    fi

    v "delivery failed"
    return 1
}

# ------------------------------------------------------------------
# Backend: bash /dev/tcp (plain SMTP only, no TLS)
# Only works for non-TLS connections (port 25). TLS is impossible
# with bash's built-in TCP device.
# ------------------------------------------------------------------

_abf_sendmail_tcp() {
    local subject="$1"
    local body="$2"
    local service="$3"

    local v; v() { [[ "${ABF_SMTP_VERBOSE:-}" == "true" ]] && echo "  tcp: $*" >&2; }

    if [[ -z "${SMTP_HOST:-}" ]]; then
        v "SMTP_HOST not set, skipping"
        return 1
    fi

    local port="${SMTP_PORT:-25}"
    local from="${SMTP_FROM:-}"
    local from_header
    from_header=$(_abf_format_from)

    # TLS is not possible with bash /dev/tcp — refuse so higher
    # backends (openssl, msmtp) get a chance instead.
    if [[ "${SMTP_TLS:-false}" == "true" ]]; then
        v "TLS enabled — /dev/tcp cannot do TLS, skipping"
        return 1
    fi

    v "connecting to ${SMTP_HOST}:${port}..."

    exec 9<>"/dev/tcp/${SMTP_HOST}/${port}" 2>/dev/null
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        v "connection failed (exit $rc)"
        return 1
    fi

    local ok=true

    _abf_smtp_tcp_cmd 9 "EHLO localhost" "250" || ok=false
    if [[ -n "${SMTP_USER:-}" ]]; then
        _abf_smtp_tcp_cmd 9 "AUTH LOGIN" "334" || ok=false
        _abf_smtp_tcp_cmd 9 "$(printf '%s' "${SMTP_USER}" | base64 -w0)" "334" || ok=false
        _abf_smtp_tcp_cmd 9 "$(printf '%s' "${SMTP_PASS}" | base64 -w0)" "235" || ok=false
    fi

    _abf_smtp_tcp_cmd 9 "MAIL FROM:<${from}>" "250" || ok=false

    local rcpt_count=0
    while IFS= read -r addr; do
        [[ -z "$addr" ]] && continue
        _abf_smtp_tcp_cmd 9 "RCPT TO:<${addr}>" "250" || ok=false
        ((rcpt_count++))
    done < <(_abf_split_recipients)

    if [[ $rcpt_count -eq 0 ]]; then
        v "no recipients"
        exec 9>&-
        return 1
    fi

    _abf_smtp_tcp_cmd 9 "DATA" "354" || ok=false

    if $ok; then
        local date_header
        date_header=$(date -R 2>/dev/null || date +"%a, %d %b %Y %H:%M:%S %z")

        local log_content
        log_content=$(_abf_read_log_for_attachment) || true

        {
            echo "From: ${from_header}"
            echo "To: $(paste -sd, <(_abf_split_recipients))"
            echo "Subject: ${subject}"
            echo "Date: ${date_header}"
            echo "MIME-Version: 1.0"
            echo "Content-Type: text/plain; charset=UTF-8"
            echo ""
            echo "$body"
            if [[ -n "$log_content" ]]; then
                echo ""
                echo "--- Backup Log ---"
                echo "$log_content"
            fi
            echo "."
        } >&9

        # Read the response(s) after the data terminator
        # The server returns "250 OK" if accepted
        local data_response=""
        local line
        while IFS= read -r line <&9; do
            line=$(echo "$line" | tr -d '\r')
            data_response="$line"
            # Multi-line responses end with "code SP message" (no hyphen)
            if [[ "$line" =~ ^[0-9]{3}\  ]]; then
                break
            fi
        done 2>/dev/null || true

        v "data response: ${data_response}"

        local data_code="${data_response:0:3}"
        if [[ "$data_code" != "250" ]]; then
            v "message rejected (${data_response})"
            ok=false
        fi
    fi

    _abf_smtp_tcp_cmd 9 "QUIT" "221" || true

    exec 9>&-

    $ok && return 0
    return 1
}

# ------------------------------------------------------------------
# TCP SMTP command: send command, check response code
# ------------------------------------------------------------------

_abf_smtp_tcp_cmd() {
    local fd="$1"
    local cmd="$2"
    local expected_code="${3:-}"

    [[ "${ABF_SMTP_VERBOSE:-}" == "true" ]] && echo "  tcp >> ${cmd}" >&2

    # Skip empty commands
    if [[ -z "$cmd" ]]; then
        return 0
    fi

    echo "$cmd" >&"$fd"

    # Read multi-line response (lines ending with - continue, space terminates)
    local response=""
    local line=""
    while IFS= read -r line <&"$fd"; do
        line=$(echo "$line" | tr -d '\r')
        response="$line"
        # Last line of multi-line response is "code SP message" (no hyphen after code)
        if [[ "$line" =~ ^[0-9]{3}\  ]]; then
            break
        fi
    done 2>/dev/null || true

    [[ "${ABF_SMTP_VERBOSE:-}" == "true" ]] && echo "  tcp << ${response}" >&2

    if [[ -z "$expected_code" ]]; then
        return 0
    fi

    local code="${response:0:3}"
    if [[ "$code" == "$expected_code" ]]; then
        return 0
    fi

    [[ "${ABF_SMTP_VERBOSE:-}" == "true" ]] && echo "  tcp: expected ${expected_code}, got ${code}" >&2
    return 1
}

# ------------------------------------------------------------------
# Interactive SMTP configuration wizard
# ------------------------------------------------------------------

abf_config_wizard_smtp() {
    local config_dir="${1:-}"
    local config_file=""

    if [[ -z "$config_dir" ]]; then
        config_dir=$(_abf_discover_config_dir)
    fi

    config_file="${config_dir}/smtp.conf"

    if [[ ! -f "$config_file" ]]; then
        echo "Creating new SMTP configuration at: ${config_file}"
        mkdir -p "$(dirname "$config_file")" 2>/dev/null || true
    else
        echo "Existing SMTP configuration found at: ${config_file}"
        # shellcheck source=/dev/null
        source "$config_file"
    fi

    echo ""
    echo "=== SMTP Configuration Wizard ==="
    echo "Press Enter to keep the current value shown in brackets."
    echo ""

    _abf_wizard_prompt "SMTP host" "SMTP_HOST" "${SMTP_HOST:-}"
    _abf_wizard_prompt "SMTP port" "SMTP_PORT" "${SMTP_PORT:-587}"
    _abf_wizard_prompt "Use SSL/TLS (true/false)" "SMTP_TLS" "${SMTP_TLS:-true}"
    _abf_wizard_prompt "SMTP username" "SMTP_USER" "${SMTP_USER:-}"

    local current_pass="${SMTP_PASS:-}"
    local new_pass
    echo -n "  SMTP password${current_pass:+ [<hidden>]} : "
    read -rs new_pass
    echo ""
    if [[ -n "$new_pass" ]]; then
        SMTP_PASS="$new_pass"
    elif [[ -z "$current_pass" ]]; then
        SMTP_PASS=""
    fi

    _abf_wizard_prompt "From name" "SMTP_FROM_NAME" "${SMTP_FROM_NAME:-Backup Framework}"
    _abf_wizard_prompt "From email" "SMTP_FROM" "${SMTP_FROM:-}"
    _abf_wizard_prompt "Recipient email(s) (comma-separated)" "SMTP_TO" "${SMTP_TO:-}"

    echo ""
    echo "=== Configuration Summary ==="
    echo "  SMTP host:           ${SMTP_HOST}"
    echo "  SMTP port:           ${SMTP_PORT}"
    echo "  SMTP TLS:            ${SMTP_TLS}"
    echo "  SMTP username:       ${SMTP_USER}"
    echo "  SMTP password:       ${SMTP_PASS:+<set>}"
    echo "  SMTP from name:      ${SMTP_FROM_NAME}"
    echo "  SMTP from email:     ${SMTP_FROM}"
    echo "  SMTP to:             ${SMTP_TO}"
    echo ""

    # Enable notifications since the user completed the wizard
    SMTP_ENABLED="true"

    local existing_values=""
    if [[ -f "$config_file" ]]; then
        existing_values=$(cat "$config_file")
    fi
    local new_values
    new_values=$(_abf_generate_smtp_config)

    if [[ -n "$existing_values" ]] && [[ "$existing_values" != "$new_values" ]]; then
        echo "Existing configuration differs from new values."
        echo -n "Overwrite ${config_file}? [y/N] "
        local confirm
        read -r confirm
        if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
            echo "Configuration not saved."
            return 1
        fi
    fi

    echo "$new_values" > "$config_file"
    chmod 600 "$config_file" 2>/dev/null || true
    echo ""
    echo "SMTP configuration saved to: ${config_file}"

    echo ""
    echo -n "Send a test email now? [y/N] "
    local send_test
    read -r send_test
    if [[ "$send_test" == "y" ]] || [[ "$send_test" == "Y" ]]; then
        abf_notify_send_test
    fi

    return 0
}

_abf_wizard_prompt() {
    local label="$1"
    local var_name="$2"
    local current_val="$3"

    local prompt_label="  ${label}${current_val:+ [${current_val}]} : "
    echo -n "$prompt_label"
    local input
    read -r input

    if [[ -n "$input" ]]; then
        printf -v "$var_name" "%s" "$input"
    elif [[ -z "$current_val" ]]; then
        printf -v "$var_name" "%s" ""
    fi
}

_abf_generate_smtp_config() {
    cat <<EOF
# ---------------------------------------------------------------------------
# smtp.conf  --  SMTP notification configuration
#
# Set SMTP_ENABLED to "true" to enable email notifications.
# ---------------------------------------------------------------------------

SMTP_ENABLED="${SMTP_ENABLED:-false}"
SMTP_HOST="${SMTP_HOST:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASS="${SMTP_PASS:-}"
SMTP_FROM_NAME="${SMTP_FROM_NAME:-Backup Framework}"
SMTP_FROM="${SMTP_FROM:-}"
SMTP_TO="${SMTP_TO:-}"
SMTP_TLS="${SMTP_TLS:-true}"
SMTP_LOG_ATTACH_MAX_KB="${SMTP_LOG_ATTACH_MAX_KB:-64}"
EOF
}
