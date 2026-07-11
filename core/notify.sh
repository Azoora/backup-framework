# ---------------------------------------------------------------------------
# notify.sh  --  Email notification system
#
# Sends SMTP email notifications on backup success/failure.
# Uses the `mail` command (mailutils) if available, otherwise falls back
# to a bash-native SMTP client via /dev/tcp.
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
    local message=""

    message+="From: ${from}\r\n"
    message+="To: ${recipients}\r\n"
    message+="Subject: ${subject}\r\n"
    message+="MIME-Version: 1.0\r\n"

    if [[ -n "$log_content" ]]; then
        message+="Content-Type: multipart/mixed; boundary=\"${boundary}\"\r\n"
        message+="\r\n"
        message+="--${boundary}\r\n"
        message+="Content-Type: text/plain; charset=UTF-8\r\n"
        message+="Content-Transfer-Encoding: 7bit\r\n"
        message+="\r\n"
        message+="${body}\r\n"
        message+="\r\n"
        message+="--${boundary}\r\n"
        message+="Content-Type: text/plain; charset=UTF-8\r\n"
        message+="Content-Disposition: attachment; filename=\"${service}_backup.log\"\r\n"
        message+="Content-Transfer-Encoding: base64\r\n"
        message+="\r\n"
        message+="$(echo "$log_content" | base64)\r\n"
        message+="\r\n"
        message+="--${boundary}--\r\n"
    else
        message+="Content-Type: text/plain; charset=UTF-8\r\n"
        message+="\r\n"
        message+="${body}\r\n"
    fi

    echo -e "$message"
}

# ------------------------------------------------------------------
# Internal: send email
# ------------------------------------------------------------------

_abf_sendmail() {
    local subject="$1"
    local body="$2"
    local service="$3"

    local from
    from=$(_abf_format_from)

    if command -v mail &>/dev/null; then
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

        if [[ -n "$first_rcpt" ]]; then
            local cc_arg=""
            if [[ ${#cc_rcpts[@]} -gt 0 ]]; then
                cc_arg=$(IFS=,; echo "${cc_rcpts[*]}")
            fi

            local log_attach=""
            log_attach=$(_abf_read_log_for_attachment) || true

            if [[ -n "$log_attach" ]]; then
                (echo "$body") | mail -s "$subject" -a "From: ${from}" -a "Content-Type: text/plain; charset=UTF-8" ${cc_arg:+-c "$cc_arg"} "$first_rcpt" 2>/dev/null && return 0
            else
                (echo "$body") | mail -s "$subject" -a "From: ${from}" ${cc_arg:+-c "$cc_arg"} "$first_rcpt" 2>/dev/null && return 0
            fi
        fi
    fi

    if command -v sendmail &>/dev/null; then
        local msg
        msg=$(_abf_build_mime_message "$subject" "$body" "$service")
        echo -e "$msg" | /usr/sbin/sendmail -t 2>/dev/null && return 0
    fi

    if command -v msmtp &>/dev/null; then
        local msg
        msg=$(_abf_build_mime_message "$subject" "$body" "$service")
        local rcpt_args=()
        while IFS= read -r addr; do
            [[ -n "$addr" ]] && rcpt_args+=("$addr")
        done < <(_abf_split_recipients)
        if [[ ${#rcpt_args[@]} -gt 0 ]]; then
            echo -e "$msg" | msmtp --from="${SMTP_FROM}" "${rcpt_args[@]}" 2>/dev/null && return 0
        fi
    fi

    _abf_sendmail_tcp "$subject" "$body" "$service" && return 0

    abf_log_warning "No email delivery method available"
    return 1
}

# ------------------------------------------------------------------
# TCP SMTP (bash built-in /dev/tcp) with full auth and multiple recipients
# ------------------------------------------------------------------

_abf_sendmail_tcp() {
    local subject="$1"
    local body="$2"
    local service="$3"

    if [[ -z "${SMTP_HOST:-}" ]]; then
        return 1
    fi

    local port="${SMTP_PORT:-25}"
    local from="${SMTP_FROM:-}"
    local from_header
    from_header=$(_abf_format_from)

    exec 9<>"/dev/tcp/${SMTP_HOST}/${port}" 2>/dev/null || return 1

    _abf_smtp_cmd 9 "EHLO localhost"
    if [[ "${SMTP_TLS:-false}" == "true" ]] && [[ "$port" == "587" ]]; then
        _abf_smtp_cmd 9 "STARTTLS"
    fi
    if [[ -n "${SMTP_USER:-}" ]]; then
        _abf_smtp_cmd 9 "AUTH LOGIN"
        _abf_smtp_cmd 9 "$(printf '%s' "${SMTP_USER}" | base64)"
        _abf_smtp_cmd 9 "$(printf '%s' "${SMTP_PASS}" | base64)"
    fi

    _abf_smtp_cmd 9 "MAIL FROM:<${from}>"

    local rcpt_count=0
    while IFS= read -r addr; do
        [[ -z "$addr" ]] && continue
        _abf_smtp_cmd 9 "RCPT TO:<${addr}>"
        ((rcpt_count++))
    done < <(_abf_split_recipients)

    if [[ $rcpt_count -eq 0 ]]; then
        abf_log_warning "SMTP TCP: no recipients configured"
        exec 9>&-
        return 1
    fi

    _abf_smtp_cmd 9 "DATA"

    local log_content
    log_content=$(_abf_read_log_for_attachment) || true

    {
        echo "From: ${from_header}"
        echo "To: $(paste -sd, <(_abf_split_recipients))"
        echo "Subject: ${subject}"
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
