# ---------------------------------------------------------------------------
# notify.sh  --  Email notification system
#
# Sends SMTP email notifications on backup success/failure.
# Uses the `mail` command (mailutils) if available, otherwise falls back
# to a bash-native SMTP client via /dev/tcp.
# ---------------------------------------------------------------------------

# ------------------------------------------------------------------
# Main notification dispatch
# ------------------------------------------------------------------

abf_notify_send() {
    local status="$1"      # SUCCESS, WARNING, or FAILED
    local service="$2"
    local details="$3"

    if [[ "${SMTP_ENABLED:-false}" != "true" ]]; then
        return "$ABF_EXIT_OK"
    fi

    local subject body
    subject="[Backup Framework] ${status} - ${service} backup - $(hostname)"
    body=$( _abf_build_email_body "$status" "$service" "$details" )

    _abf_sendmail "$subject" "$body"
}

# ------------------------------------------------------------------
# Internal: build email body
# ------------------------------------------------------------------

_abf_build_email_body() {
    local status="$1"
    local service="$2"
    local details="$3"

    cat <<EOF
Backup Framework - Backup Report
=================================
Status:      ${status}
Service:     ${service}
Hostname:    $(hostname)
Timestamp:   $(date -u +"%Y-%m-%dT%H:%M:%S%z")

${details}

---
Backup Framework v$(cat "${ABF_ROOT}/VERSION" 2>/dev/null || echo "unknown")
EOF
}

# ------------------------------------------------------------------
# Internal: send email
# ------------------------------------------------------------------

_abf_sendmail() {
    local subject="$1"
    local body="$2"

    if command -v mail &>/dev/null; then
        # mailutils / mailx
        echo "$body" | mail -s "$subject" -a "From: ${SMTP_FROM}" "${SMTP_TO}" 2>/dev/null && return 0
    fi

    if command -v sendmail &>/dev/null; then
        # sendmail (postfix, exim, etc.)
        _abf_sendmail_sendmail "$subject" "$body" && return 0
    fi

    if command -v msmtp &>/dev/null; then
        # msmtp (lightweight SMTP client)
        _abf_sendmail_msmtp "$subject" "$body" && return 0
    fi

    # Fallback: bash TCP
    _abf_sendmail_tcp "$subject" "$body" && return 0

    abf_log_warning "No email delivery method available"
    return 1
}

_abf_sendmail_sendmail() {
    local subject="$1"
    local body="$2"

    {
        echo "From: ${SMTP_FROM}"
        echo "To: ${SMTP_TO}"
        echo "Subject: $subject"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        echo "$body"
    } | /usr/sbin/sendmail -t 2>/dev/null
}

_abf_sendmail_msmtp() {
    local subject="$1"
    local body="$2"

    {
        echo "From: ${SMTP_FROM}"
        echo "To: ${SMTP_TO}"
        echo "Subject: $subject"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        echo "$body"
    } | msmtp --from="${SMTP_FROM}" "${SMTP_TO}" 2>/dev/null
}

# Fallback: direct SMTP via /dev/tcp (bash built-in)
_abf_sendmail_tcp() {
    local subject="$1"
    local body="$2"

    if [[ -z "${SMTP_HOST:-}" ]]; then
        return 1
    fi

    local port="${SMTP_PORT:-25}"

    exec 9<>"/dev/tcp/${SMTP_HOST}/${port}" 2>/dev/null || return 1

    _abf_smtp_cmd 9 "EHLO localhost"
    if [[ "${SMTP_TLS:-false}" == "true" ]] && [[ "$port" == "587" ]]; then
        _abf_smtp_cmd 9 "STARTTLS"
    fi
    _abf_smtp_cmd 9 "AUTH LOGIN"
    _abf_smtp_cmd 9 "$(printf '%s' "${SMTP_USER}" | base64)"
    _abf_smtp_cmd 9 "$(printf '%s' "${SMTP_PASS}" | base64)"
    _abf_smtp_cmd 9 "MAIL FROM:<${SMTP_FROM}>"
    _abf_smtp_cmd 9 "RCPT TO:<${SMTP_TO}>"
    _abf_smtp_cmd 9 "DATA"
    echo -e "From: ${SMTP_FROM}\nTo: ${SMTP_TO}\nSubject: ${subject}\n\n${body}\n." >&9
    _abf_smtp_cmd 9 "QUIT"

    exec 9>&-
    return 0
}

_abf_smtp_cmd() {
    local fd="$1"
    local cmd="$2"
    echo "$cmd" >&"$fd"
    read -r response <&"$fd" 2>/dev/null || true
}
