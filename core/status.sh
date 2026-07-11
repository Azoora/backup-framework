# ---------------------------------------------------------------------------
# status.sh  --  System status overview (abf status)
#
# Provides three output formats:
#   human  --  formatted table view (default)
#   short  --  one-line summary (for Apple Shortcuts / voice assistants)
#   json   --  structured JSON (for Home Assistant / n8n / dashboards)
# ---------------------------------------------------------------------------

# ------------------------------------------------------------------
# Core status check: get latest snapshot info for a service
# ------------------------------------------------------------------

_abf_status_get_snapshot_time() {
    local service_name="$1"
    local repo="${2:-}"

    if [[ -z "$repo" ]]; then
        echo ""
        return 1
    fi

    if ! command -v restic &>/dev/null; then
        echo ""
        return 1
    fi

    if [[ -z "${ABF_RESTIC_PASSWORD_FILE:-}" ]] || [[ ! -r "${ABF_RESTIC_PASSWORD_FILE:-}" ]]; then
        echo ""
        return 1
    fi

    local time_str
    time_str=$(restic -r "$repo" --password-file "$ABF_RESTIC_PASSWORD_FILE" \
        snapshots --json --tag "$service_name" 2>/dev/null \
        | grep -oP '"time"\s*:\s*"\K[^"]+' | sort | tail -1) || true

    if [[ -z "$time_str" ]]; then
        echo ""
        return 1
    fi

    echo "$time_str"
    return 0
}

_abf_status_format_time() {
    local iso_time="$1"
    if [[ -z "$iso_time" ]]; then
        echo "Never"
        return
    fi

    local ts
    ts=$(date -d "$iso_time" +%s 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    local diff_hours=$(( (now - ts) / 3600 ))
    local time_only
    time_only=$(date -d "$iso_time" +%H:%M 2>/dev/null || echo "??:??")

    if [[ $diff_hours -lt 24 ]]; then
        echo "Today ${time_only}"
    elif [[ $diff_hours -lt 48 ]]; then
        echo "Yesterday ${time_only}"
    else
        date -d "$iso_time" "+%b %d ${time_only}" 2>/dev/null || echo "$iso_time"
    fi
}

_abf_status_repo_healthy() {
    local repo="$1"
    if [[ -z "$repo" ]] || ! command -v restic &>/dev/null; then
        echo "Unknown"
        return
    fi
    if [[ -z "${ABF_RESTIC_PASSWORD_FILE:-}" ]] || [[ ! -r "${ABF_RESTIC_PASSWORD_FILE:-}" ]]; then
        echo "Unknown"
        return
    fi
    if restic -r "$repo" --password-file "$ABF_RESTIC_PASSWORD_FILE" \
        snapshots --json --quiet &>/dev/null 2>&1; then
        echo "Healthy"
    else
        echo "Unhealthy"
    fi
}

_abf_status_destination_status() {
    local dest="$1"
    if ! abf_destination_exists "$dest" 2>/dev/null; then
        echo "Unknown"
        return
    fi
    abf_load_destination_module "$dest" 2>/dev/null || {
        echo "Unknown"
        return
    }
    abf_load_destination_config "$dest" 2>/dev/null
    if declare -F "destination_check" &>/dev/null; then
        if destination_check &>/dev/null; then
            echo "Connected"
        else
            echo "Disconnected"
        fi
    else
        echo "Configured"
    fi
}

_abf_status_storage_status() {
    local backend="${ABF_STORAGE_BACKEND:-local}"
    local repo
    repo=$(_abf_get_storage_repo 2>/dev/null) || {
        echo "Not configured"
        return
    }
    if command -v restic &>/dev/null \
        && [[ -n "${ABF_RESTIC_PASSWORD_FILE:-}" ]] \
        && [[ -r "${ABF_RESTIC_PASSWORD_FILE:-}" ]]; then
        if restic -r "$repo" --password-file "$ABF_RESTIC_PASSWORD_FILE" \
            snapshots --json --quiet &>/dev/null 2>&1; then
            echo "OK"
        else
            echo "Unreachable"
        fi
    else
        echo "OK"
    fi
}

_abf_status_notification_status() {
    if [[ "${SMTP_ENABLED:-false}" != "true" ]]; then
        echo "Disabled"
        return
    fi
    if [[ -n "${SMTP_HOST:-}" ]]; then
        echo "OK"
    else
        echo "Not configured"
    fi
}

# ------------------------------------------------------------------
# Human-readable output
# ------------------------------------------------------------------

_abf_status_output_human() {
    local version="$1"
    local service_data="$2"
    local scheduler_enabled="$3"
    local scheduler_next="$4"
    local scheduler_time="$5"
    local storage_status="$6"
    local notification_status="$7"
    local overall="$8"

    echo "Backup Framework v${version}"
    echo ""
    echo "Overall Health"
    echo "--------------"
    echo "${overall}"
    echo ""

    echo "Services"
    echo "--------"
    local svc_name last_bk svc_st repo_st dests email_st
    while IFS= read -r line; do
        svc_name=$(echo "$line" | cut -d'|' -f1)
        last_bk=$(echo "$line" | cut -d'|' -f2)
        svc_st=$(echo "$line" | cut -d'|' -f3)
        repo_st=$(echo "$line" | cut -d'|' -f4)
        dests=$(echo "$line" | cut -d'|' -f5)
        email_st=$(echo "$line" | cut -d'|' -f6)

        local display
        display=$(_abf_service_display_name "$svc_name")
        echo "${display}"
        if [[ "$svc_st" == "Disabled" ]]; then
            printf "  %-12s %s\n" "Status" ": Disabled"
        else
            printf "  %-12s %s\n" "Last Backup" ": ${last_bk}"
            printf "  %-12s %s\n" "Status" ": ${svc_st}"
            printf "  %-12s %s\n" "Repository" ": ${repo_st}"
            if [[ -n "$dests" ]]; then
                IFS=',' read -ra dest_list <<< "$dests"
                for d in "${dest_list[@]}"; do
                    local d_name="${d%%:*}"
                    local d_status="${d#*:}"
                    printf "  %-12s %s\n" "${d_name}" ": ${d_status}"
                done
            fi
            if [[ "$notification_status" != "Disabled" ]]; then
                printf "  %-12s %s\n" "Email" ": ${email_st}"
            fi
        fi
        echo ""
    done <<< "$service_data"

    echo "Scheduler"
    echo "---------"
    printf "  %-12s %s\n" "Enabled" ": ${scheduler_enabled}"
    if [[ -n "$scheduler_time" ]]; then
        printf "  %-12s %s\n" "Time" ": ${scheduler_time}"
    fi
    if [[ -n "$scheduler_next" ]]; then
        printf "  %-12s %s\n" "Next Run" ": ${scheduler_next}"
    fi
    echo ""

    echo "Storage"
    echo "-------"
    printf "  %-20s %s\n" "Local Repository" ": ${storage_status}"
    local dests_config="${BACKUP_DESTINATIONS:-}"
    if [[ -n "$dests_config" ]]; then
        IFS=',' read -ra dest_list <<< "$dests_config"
        for dest in "${dest_list[@]}"; do
            dest=$(echo "$dest" | xargs)
            local d_status
            d_status=$(_abf_status_destination_status "$dest")
            printf "  %-20s %s\n" "${dest^}" ": ${d_status}"
        done
    fi
    echo ""

    echo "Notifications"
    echo "-------------"
    printf "  %-12s %s\n" "SMTP" ": ${notification_status}"
    echo ""
}

# ------------------------------------------------------------------
# Short output (one-liners for Apple Shortcuts / voice assistants)
# ------------------------------------------------------------------

_abf_status_output_short() {
    local version="$1"
    local service_data="$2"
    local scheduler_enabled="$3"
    local scheduler_next="$4"
    local scheduler_time="$5"
    local storage_status="$6"
    local notification_status="$7"
    local overall="$8"

    local healthy_count=0
    local total_count=0
    local latest_svc=""
    local latest_time=""

    while IFS= read -r line; do
        local svc_name last_bk svc_st
        svc_name=$(echo "$line" | cut -d'|' -f1)
        last_bk=$(echo "$line" | cut -d'|' -f2)
        svc_st=$(echo "$line" | cut -d'|' -f3)

        total_count=$((total_count + 1))
        if [[ "$svc_st" == "SUCCESS" ]]; then
            healthy_count=$((healthy_count + 1))
            if [[ -z "$latest_time" ]] || [[ "$last_bk" > "$latest_time" ]]; then
                latest_time="$last_bk"
                latest_svc="$svc_name"
            fi
        fi
    done <<< "$service_data"

    if [[ "$overall" == "HEALTHY" ]]; then
        echo "All systems healthy."
    elif [[ "$overall" == "WARNING" ]]; then
        echo "Some systems need attention."
    else
        echo "System issues detected."
    fi

    if [[ -n "$latest_svc" ]] && [[ -n "$latest_time" ]]; then
        local display
        display=$(_abf_service_display_name "$latest_svc")
        echo "${display} backed up successfully ${latest_time}."
    fi

    if [[ "$scheduler_enabled" == "Yes" ]] && [[ -n "$scheduler_next" ]]; then
        echo "Next backup: ${scheduler_next}."
    fi
}

# ------------------------------------------------------------------
# JSON output
# ------------------------------------------------------------------

_abf_status_output_json() {
    local version="$1"
    local service_data="$2"
    local scheduler_enabled="$3"
    local scheduler_next="$4"
    local scheduler_time="$5"
    local storage_status="$6"
    local notification_status="$7"
    local overall="$8"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S%z")

    local json_services="{"
    local first_svc=true
    while IFS= read -r line; do
        $first_svc || json_services+=","
        first_svc=false
        local svc_name last_bk svc_st repo_st dests email_st
        svc_name=$(echo "$line" | cut -d'|' -f1)
        last_bk=$(echo "$line" | cut -d'|' -f2)
        svc_st=$(echo "$line" | cut -d'|' -f3)
        repo_st=$(echo "$line" | cut -d'|' -f4)
        dests=$(echo "$line" | cut -d'|' -f5)
        email_st=$(echo "$line" | cut -d'|' -f6)

        json_services+="\"${svc_name}\": {"
        json_services+="\"status\": \"${svc_st}\""
        if [[ "$svc_st" != "Disabled" ]]; then
            json_services+=", \"last_backup\": \"${last_bk}\""
            json_services+=", \"repository\": \"${repo_st}\""
            if [[ -n "$dests" ]]; then
                json_services+=", \"destinations\": {"
                local first_dest=true
                IFS=',' read -ra dest_list <<< "$dests"
                for d in "${dest_list[@]}"; do
                    $first_dest || json_services+=","
                    first_dest=false
                    local d_name="${d%%:*}"
                    local d_status="${d#*:}"
                    json_services+=" \"${d_name}\": \"${d_status}\""
                done
                json_services+=" }"
            fi
            if [[ "$notification_status" != "Disabled" ]]; then
                json_services+=", \"email\": \"${email_st}\""
            fi
        fi
        json_services+=" }"
    done <<< "$service_data"
    json_services+=" }"

    local json_scheduler="{ "
    json_scheduler+="\"enabled\": $( [ "$scheduler_enabled" = "Yes" ] && echo "true" || echo "false")"
    if [[ -n "$scheduler_next" ]]; then
        json_scheduler+=", \"next_run\": \"${scheduler_next}\""
    fi
    if [[ -n "$scheduler_time" ]]; then
        json_scheduler+=", \"time\": \"${scheduler_time}\""
    fi
    json_scheduler+=" }"

    local json_storage="{ "
    json_storage+="\"local\": \"${storage_status}\""
    local dests_config="${BACKUP_DESTINATIONS:-}"
    if [[ -n "$dests_config" ]]; then
        IFS=',' read -ra dest_list <<< "$dests_config"
        for dest in "${dest_list[@]}"; do
            dest=$(echo "$dest" | xargs)
            local d_status
            d_status=$(_abf_status_destination_status "$dest")
            json_storage+=", \"${dest}\": \"${d_status}\""
        done
    fi
    json_storage+=" }"

    local json_notifications="{ "
    json_notifications+="\"smtp\": \"${notification_status}\""
    json_notifications+=" }"

    cat <<EOF
{
  "version": "${version}",
  "timestamp": "${timestamp}",
  "overall_health": "${overall}",
  "services": ${json_services},
  "scheduler": ${json_scheduler},
  "storage": ${json_storage},
  "notifications": ${json_notifications}
}
EOF
}

# ------------------------------------------------------------------
# Main status orchestration
# ------------------------------------------------------------------

abf_status_run() {
    local output_format="${1:-human}"

    local version
    version=$(cat "${ABF_ROOT}/VERSION" 2>/dev/null || echo "unknown")
    local overall="HEALTHY"
    local has_warnings=false
    local has_errors=false

    # Gather service data
    local service_data=""
    local svc_repo=""

    # Try to get the storage repo once
    svc_repo=$(_abf_get_storage_repo 2>/dev/null) || svc_repo=""

    while IFS= read -r svc; do
        local display
        display=$(_abf_service_display_name "$svc")
        abf_load_service_config "$svc" 2>/dev/null || true

        local last_bk=""
        last_bk=$(_abf_status_get_snapshot_time "$svc" "$svc_repo")

        local formatted_time=""
        formatted_time=$(_abf_status_format_time "$last_bk")

        local svc_status=""
        local repo_status=""
        local dest_statuses=""
        local email_status=""

        if [[ -z "$last_bk" ]]; then
            svc_status="Disabled"
        else
            svc_status="SUCCESS"
            repo_status=$(_abf_status_repo_healthy "$svc_repo")

            if [[ "$repo_status" == "Unhealthy" ]]; then
                has_errors=true
            fi

            local dests_config="${BACKUP_DESTINATIONS:-}"
            if [[ -n "$dests_config" ]]; then
                local first=true
                IFS=',' read -ra dest_list <<< "$dests_config"
                for dest in "${dest_list[@]}"; do
                    dest=$(echo "$dest" | xargs)
                    $first || dest_statuses+=","
                    first=false
                    local d_status
                    d_status=$(_abf_status_destination_status "$dest")
                    dest_statuses+="${dest}:${d_status}"
                done
            fi

            local notif_status
            notif_status=$(_abf_status_notification_status)
            if [[ "$notif_status" == "OK" ]]; then
                email_status="Delivered"
            elif [[ "$notif_status" == "Disabled" ]]; then
                email_status="Disabled"
            else
                email_status="Not configured"
                has_warnings=true
            fi

            if [[ "$repo_status" == "Healthy" ]] && [[ "$notif_status" != "Not configured" ]]; then
                : # all good
            fi
        fi

        service_data+="${svc}|${formatted_time}|${svc_status}|${repo_status}|${dest_statuses}|${email_status}"$'\n'

        if [[ "$svc_status" == "Disabled" ]]; then
            has_warnings=true
        fi
    done < <(_abf_manifest_lines)

    # Scheduler
    local scheduler_enabled="No"
    local scheduler_next=""
    local scheduler_time=""

    if systemctl --version &>/dev/null 2>&1; then
        if abf_schedule_global_is_enabled 2>/dev/null; then
            scheduler_enabled="Yes"

            local unit_name="abf-backup"
            local calendar
            calendar=$(systemctl show -p OnCalendar "${unit_name}.timer" 2>/dev/null \
                | sed 's/OnCalendar=//' || true)

            if [[ "$calendar" =~ ^\*-\*-\*\ ([0-9]{2}):([0-9]{2}):00$ ]]; then
                scheduler_time="Daily at ${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
            elif [[ -n "$calendar" ]]; then
                scheduler_time="$calendar"
            fi

            local next_str
            next_str=$(systemctl show -p NextElapseUSecRealtime "${unit_name}.timer" 2>/dev/null \
                | sed 's/NextElapseUSecRealtime=//' || true)
            if [[ -n "$next_str" ]] && [[ "$next_str" != "n/a" ]]; then
                scheduler_next="$next_str"
            fi
        else
            scheduler_enabled="No"
        fi
    fi

    # Storage
    local storage_status
    storage_status=$(_abf_status_storage_status)
    if [[ "$storage_status" == "Unreachable" ]]; then
        has_errors=true
    elif [[ "$storage_status" == "Not configured" ]]; then
        has_warnings=true
    fi

    # Notifications
    local notification_status
    notification_status=$(_abf_status_notification_status)

    # Overall health
    if $has_errors; then
        overall="UNHEALTHY"
    elif $has_warnings; then
        overall="WARNING"
    else
        overall="HEALTHY"
    fi

    # Trim trailing newline
    service_data="${service_data%%$'\n'}"

    case "$output_format" in
        json)
            _abf_status_output_json \
                "$version" "$service_data" \
                "$scheduler_enabled" "$scheduler_next" "$scheduler_time" \
                "$storage_status" "$notification_status" "$overall"
            ;;
        short)
            _abf_status_output_short \
                "$version" "$service_data" \
                "$scheduler_enabled" "$scheduler_next" "$scheduler_time" \
                "$storage_status" "$notification_status" "$overall"
            ;;
        *)
            _abf_status_output_human \
                "$version" "$service_data" \
                "$scheduler_enabled" "$scheduler_next" "$scheduler_time" \
                "$storage_status" "$notification_status" "$overall"
            ;;
    esac
}
