# ---------------------------------------------------------------------------
# scheduler.sh  --  Schedule management (cron / systemd timers)
#
# Automatically detects the available scheduling system and manages
# recurring backup jobs.
# ---------------------------------------------------------------------------

ABF_SCHEDULER_BACKEND=""

# ------------------------------------------------------------------
# Detection
# ------------------------------------------------------------------

_abf_scheduler_detect() {
    if [[ -n "$ABF_SCHEDULER_BACKEND" ]]; then
        echo "$ABF_SCHEDULER_BACKEND"
        return 0
    fi

    if systemctl --version &>/dev/null 2>&1; then
        echo "systemd"
    elif command -v crontab &>/dev/null; then
        echo "cron"
    else
        echo "none"
    fi
}

# ------------------------------------------------------------------
# Human-readable schedule description
# ------------------------------------------------------------------

_abf_describe_schedule() {
    local frequency="$1"
    local time="$2"
    local day="$3"

    case "$frequency" in
        daily)
            echo "Daily at ${time}"
            ;;
        weekly)
            local day_name
            day_name=$(_abf_day_name "$day")
            echo "Every ${day_name} at ${time}"
            ;;
        monthly)
            echo "Day ${day} of every month at ${time}"
            ;;
        custom)
            echo "Custom schedule: ${time}"
            ;;
        *)
            echo "Unknown frequency: ${frequency}"
            ;;
    esac
}

_abf_day_name() {
    case "${1:-0}" in
        0|7|Sun|sun) echo "Sunday" ;;
        1|Mon|mon)   echo "Monday" ;;
        2|Tue|tue)   echo "Tuesday" ;;
        3|Wed|wed)   echo "Wednesday" ;;
        4|Thu|thu)   echo "Thursday" ;;
        5|Fri|fri)   echo "Friday" ;;
        6|Sat|sat)   echo "Saturday" ;;
        *)           echo "Day ${1}" ;;
    esac
}

_abf_day_abbrev() {
    case "${1:-0}" in
        0|7|Sun|sun) echo "Sun" ;;
        1|Mon|mon)   echo "Mon" ;;
        2|Tue|tue)   echo "Tue" ;;
        3|Wed|wed)   echo "Wed" ;;
        4|Thu|thu)   echo "Thu" ;;
        5|Fri|fri)   echo "Fri" ;;
        6|Sat|sat)   echo "Sat" ;;
        *)           echo "$1" ;;
    esac
}

# ------------------------------------------------------------------
# Build the abf command line for a scheduled job
# ------------------------------------------------------------------

_abf_build_schedule_cmd() {
    local service_name="$1"
    local config_dir="${ABF_CONFIG_DIR:-}"

    local cmd="${ABF_ROOT}/abf backup ${service_name}"
    if [[ -n "$config_dir" ]]; then
        cmd="${cmd} --config ${config_dir}"
    fi
    echo "$cmd"
}

_abf_build_cron_expr() {
    local frequency="$1"
    local time="$2"
    local day="$3"

    local hour minute
    hour=$((10#$(echo "$time" | cut -d: -f1)))
    minute=$((10#$(echo "$time" | cut -d: -f2)))

    case "$frequency" in
        daily)
            echo "${minute} ${hour} * * *"
            ;;
        weekly)
            echo "${minute} ${hour} * * ${day}"
            ;;
        monthly)
            echo "${minute} ${hour} ${day} * *"
            ;;
        custom)
            echo "$time"
            ;;
    esac
}

_abf_build_systemd_calendar() {
    local frequency="$1"
    local time="$2"
    local day="$3"

    case "$frequency" in
        daily)
            echo "*-*-* ${time}:00"
            ;;
        weekly)
            local abbrev
            abbrev=$(_abf_day_abbrev "$day")
            echo "${abbrev} *-*-* ${time}:00"
            ;;
        monthly)
            echo "*-*-${day} ${time}:00"
            ;;
        custom)
            echo "$time"
            ;;
    esac
}

# ------------------------------------------------------------------
# Cron backend
# ------------------------------------------------------------------

_abf_schedule_cron_install() {
    local service_name="$1"
    local cron_expr="$2"
    local description="$3"
    local force="$4"

    local abf_cmd
    abf_cmd=$(_abf_build_schedule_cmd "$service_name")
    local cron_line="${cron_expr} ${abf_cmd} # abf-schedule:${service_name}"

    local current
    current=$(crontab -l 2>/dev/null || true)

    if echo "$current" | grep -qF "abf-schedule:${service_name}"; then
        if [[ "$force" != "true" ]]; then
            echo "A schedule already exists for '${service_name}'."
            echo "Use --force to overwrite it, or 'abf schedule remove ${service_name}' first."
            return "$ABF_EXIT_CONFIG_ERROR"
        fi
        current=$(echo "$current" | grep -vF "abf-schedule:${service_name}" || true)
    fi

    printf '%s\n%s\n' "$current" "$cron_line" | crontab -
    echo "Installed cron schedule: ${description}"
    return "$ABF_EXIT_OK"
}

_abf_schedule_cron_remove() {
    local service_name="$1"

    local current
    current=$(crontab -l 2>/dev/null || true)

    if ! echo "$current" | grep -qF "abf-schedule:${service_name}"; then
        echo "No schedule found for '${service_name}'."
        return "$ABF_EXIT_OK"
    fi

    current=$(echo "$current" | grep -vF "abf-schedule:${service_name}" || true)
    printf '%s\n' "$current" | crontab -
    echo "Removed schedule for '${service_name}'."
    return "$ABF_EXIT_OK"
}

_abf_schedule_cron_status() {
    local service_name="$1"

    local current
    current=$(crontab -l 2>/dev/null || true)
    local line
    line=$(echo "$current" | grep "abf-schedule:${service_name}" || true)

    if [[ -z "$line" ]]; then
        echo "No schedule for '${service_name}'."
        return "$ABF_EXIT_OK"
    fi

    local cron_expr
    cron_expr=$(echo "$line" | awk '{print $1, $2, $3, $4, $5}')
    echo "Schedule active: ${cron_expr}"
    return "$ABF_EXIT_OK"
}

_abf_schedule_cron_list() {
    local current
    current=$(crontab -l 2>/dev/null || true)
    local entries
    entries=$(echo "$current" | grep "abf-schedule:" || true)

    if [[ -z "$entries" ]]; then
        echo "No scheduled backups."
        return "$ABF_EXIT_OK"
    fi

    echo "Scheduled backups:"
    echo "$entries" | while IFS= read -r line; do
        local service
        # shellcheck disable=SC2016
        service=$(echo "$line" | sed 's/.*abf-schedule://' | awk '{print $1}')
        local cron_expr
        cron_expr=$(echo "$line" | awk '{print $1, $2, $3, $4, $5}')
        echo "  ${service}  [${cron_expr}]"
    done
}

# ------------------------------------------------------------------
# Systemd backend
# ------------------------------------------------------------------

_abf_schedule_systemd_install() {
    local service_name="$1"
    local calendar="$2"
    local description="$3"
    local force="$4"

    local unit_name="abf-backup-${service_name}"
    local service_file="/etc/systemd/system/${unit_name}.service"
    local timer_file="/etc/systemd/system/${unit_name}.timer"

    local abf_cmd
    abf_cmd=$(_abf_build_schedule_cmd "$service_name")

    if [[ -f "$timer_file" ]]; then
        if [[ "$force" != "true" ]]; then
            echo "A systemd timer already exists for '${service_name}'."
            echo "Use --force to overwrite it, or 'abf schedule remove ${service_name}' first."
            return "$ABF_EXIT_CONFIG_ERROR"
        fi
        systemctl stop "${unit_name}.timer" 2>/dev/null || true
    fi

    _abf_systemd_write_unit "$service_file" \
        "[Unit]" \
        "Description=Backup Framework - ${service_name} backup" \
        "After=network-online.target" \
        "" \
        "[Service]" \
        "Type=oneshot" \
        "ExecStart=${abf_cmd}" \
        "User=root" \
        "StandardOutput=journal" \
        "StandardError=journal"

    _abf_systemd_write_unit "$timer_file" \
        "[Unit]" \
        "Description=Backup Framework - ${description}" \
        "Requires=${unit_name}.service" \
        "" \
        "[Timer]" \
        "OnCalendar=${calendar}" \
        "Persistent=true" \
        "RandomizedDelaySec=1800" \
        "" \
        "[Install]" \
        "WantedBy=timers.target"

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable "${unit_name}.timer" 2>/dev/null || true
    systemctl start "${unit_name}.timer" 2>/dev/null || true

    echo "Installed systemd timer: ${description}"
    return "$ABF_EXIT_OK"
}

_abf_systemd_write_unit() {
    local file="$1"
    shift

    > "$file"
    for line in "$@"; do
        echo "$line" >> "$file"
    done
}

_abf_schedule_systemd_remove() {
    local service_name="$1"
    local unit_name="abf-backup-${service_name}"

    if [[ ! -f "/etc/systemd/system/${unit_name}.timer" ]] \
        && [[ ! -f "/etc/systemd/system/${unit_name}.service" ]]; then
        echo "No systemd timer found for '${service_name}'."
        return "$ABF_EXIT_OK"
    fi

    systemctl stop "${unit_name}.timer" 2>/dev/null || true
    systemctl disable "${unit_name}.timer" 2>/dev/null || true
    rm -f "/etc/systemd/system/${unit_name}.timer" \
          "/etc/systemd/system/${unit_name}.service"
    systemctl daemon-reload 2>/dev/null || true

    echo "Removed systemd timer for '${service_name}'."
    return "$ABF_EXIT_OK"
}

_abf_schedule_systemd_status() {
    local service_name="$1"
    local unit_name="abf-backup-${service_name}"
    local timer_file="/etc/systemd/system/${unit_name}.timer"

    if [[ ! -f "$timer_file" ]]; then
        echo "No systemd timer for '${service_name}'."
        return "$ABF_EXIT_OK"
    fi

    local active
    active=$(systemctl is-active "${unit_name}.timer" 2>/dev/null || echo "unknown")
    local enabled
    enabled=$(systemctl is-enabled "${unit_name}.timer" 2>/dev/null || echo "unknown")
    local calendar
    calendar=$(systemctl show -p OnCalendar "${unit_name}.timer" 2>/dev/null \
        | sed 's/OnCalendar=//' || echo "unknown")

    echo "Schedule active: ${calendar}"
    echo "  State: ${active}, enabled: ${enabled}"
    return "$ABF_EXIT_OK"
}

_abf_schedule_systemd_list() {
    local timers
    timers=$(systemctl list-units --type=timer --all --no-legend 2>/dev/null \
        | grep 'abf-backup-' || true)

    if [[ -z "$timers" ]]; then
        echo "No scheduled backups."
        return "$ABF_EXIT_OK"
    fi

    echo "Scheduled backups:"
    echo "$timers" | while IFS= read -r line; do
        local unit
        unit=$(echo "$line" | awk '{print $1}')
        local name="${unit#abf-backup-}"
        name="${name%.timer}"
        local calendar
        calendar=$(systemctl show -p OnCalendar "${unit}" 2>/dev/null \
            | sed 's/OnCalendar=//' || echo "unknown")
        echo "  ${name}  [${calendar}]"
    done
}

# ------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------

abf_schedule_install() {
    local service_name="$1"
    local frequency="${2:-daily}"
    local time="${3:-03:00}"
    local day="${4:-0}"
    local force="${5:-false}"

    local backend
    backend=$(_abf_scheduler_detect)
    if [[ "$backend" == "none" ]]; then
        echo "ERROR: No scheduling system detected (cron or systemd required)."
        return "$ABF_EXIT_CONFIG_ERROR"
    fi

    local description
    description=$(_abf_describe_schedule "$frequency" "$time" "$day")

    echo "Scheduling backup for '${service_name}'..."
    echo "  Schedule: ${description}"
    echo "  Backend:  ${backend}"
    echo ""

    case "$backend" in
        cron)
            local cron_expr
            cron_expr=$(_abf_build_cron_expr "$frequency" "$time" "$day")
            _abf_schedule_cron_install "$service_name" "$cron_expr" "$description" "$force"
            ;;
        systemd)
            local calendar
            calendar=$(_abf_build_systemd_calendar "$frequency" "$time" "$day")
            _abf_schedule_systemd_install "$service_name" "$calendar" "$description" "$force"
            ;;
    esac
}

abf_schedule_remove() {
    local service_name="$1"

    local backend
    backend=$(_abf_scheduler_detect)
    if [[ "$backend" == "none" ]]; then
        echo "ERROR: No scheduling system detected."
        return "$ABF_EXIT_CONFIG_ERROR"
    fi

    case "$backend" in
        cron)   _abf_schedule_cron_remove "$service_name" ;;
        systemd) _abf_schedule_systemd_remove "$service_name" ;;
    esac
}

abf_schedule_status() {
    local service_name="$1"

    local backend
    backend=$(_abf_scheduler_detect)
    if [[ "$backend" == "none" ]]; then
        echo "No scheduling system available."
        return "$ABF_EXIT_OK"
    fi

    case "$backend" in
        cron)   _abf_schedule_cron_status "$service_name" ;;
        systemd) _abf_schedule_systemd_status "$service_name" ;;
    esac
}

abf_schedule_list() {
    local backend
    backend=$(_abf_scheduler_detect)
    if [[ "$backend" == "none" ]]; then
        echo "No scheduling system available."
        return "$ABF_EXIT_OK"
    fi

    case "$backend" in
        cron)   _abf_schedule_cron_list ;;
        systemd) _abf_schedule_systemd_list ;;
    esac
}

# ------------------------------------------------------------------
# Global schedule (runs backup for every service in the manifest)
# Uses a single systemd timer: abf-backup.timer / abf-backup.service
# ------------------------------------------------------------------

_abf_schedule_global_config_file() {
    echo "${ABF_CONFIG_DIR}/schedule.conf"
}

_abf_schedule_global_load_config() {
    local config_file
    config_file=$(_abf_schedule_global_config_file)
    if [[ -f "$config_file" ]]; then
        source "$config_file" 2>/dev/null || true
    fi
    SCHEDULE_ENABLED="${SCHEDULE_ENABLED:-false}"
    SCHEDULE_FREQUENCY="${SCHEDULE_FREQUENCY:-daily}"
    SCHEDULE_TIME="${SCHEDULE_TIME:-03:00}"
}

_abf_schedule_global_save_config() {
    local config_file
    config_file=$(_abf_schedule_global_config_file)
    local config_dir
    config_dir=$(dirname "$config_file")
    mkdir -p "$config_dir" 2>/dev/null || true
    cat > "$config_file" <<EOF
# Backup Framework schedule configuration
# Generated by abf schedule
SCHEDULE_ENABLED=${SCHEDULE_ENABLED:-false}
SCHEDULE_FREQUENCY=${SCHEDULE_FREQUENCY:-daily}
SCHEDULE_TIME=${SCHEDULE_TIME:-03:00}
EOF
}

_abf_schedule_global_build_services_exec() {
    local abf_path="$1"
    local config_arg="${2:-}"
    while IFS= read -r svc; do
        echo "ExecStart=${abf_path} backup ${svc}${config_arg}"
    done < <(_abf_manifest_lines)
}

abf_schedule_global_enable() {
    local frequency="${1:-daily}"
    local time="${2:-03:00}"

    local backend
    backend=$(_abf_scheduler_detect)
    if [[ "$backend" != "systemd" ]]; then
        echo "ERROR: Global schedule requires systemd. Detected: ${backend}" >&2
        return "$ABF_EXIT_CONFIG_ERROR"
    fi

    if [[ ! -d "$ABF_CONFIG_DIR" ]]; then
        echo "ERROR: Config directory not found: ${ABF_CONFIG_DIR}" >&2
        return "$ABF_EXIT_CONFIG_ERROR"
    fi

    SCHEDULE_ENABLED="true"
    SCHEDULE_FREQUENCY="$frequency"
    SCHEDULE_TIME="$time"
    _abf_schedule_global_save_config

    local unit_name="abf-backup"
    local service_file="/etc/systemd/system/${unit_name}.service"
    local timer_file="/etc/systemd/system/${unit_name}.timer"
    local abf_path="${ABF_ROOT}/abf"
    local config_arg=""
    [[ -n "$ABF_CONFIG_DIR" ]] && config_arg=" --config ${ABF_CONFIG_DIR}"

    systemctl stop "${unit_name}.timer" 2>/dev/null || true
    systemctl disable "${unit_name}.timer" 2>/dev/null || true

    local exec_lines
    exec_lines=$(_abf_schedule_global_build_services_exec "${abf_path}" "${config_arg}")
    if [[ -z "$exec_lines" ]]; then
        echo "ERROR: No services found in manifest -- nothing to schedule." >&2
        return "$ABF_EXIT_CONFIG_ERROR"
    fi

    printf "%s\n" "[Unit]" \
        "Description=Backup Framework - All services" \
        "After=network-online.target" \
        "" \
        "[Service]" \
        "Type=oneshot" > "$service_file"
    echo "$exec_lines" >> "$service_file"
    printf "%s\n" "User=root" \
        "StandardOutput=journal" \
        "StandardError=journal" >> "$service_file"

    local calendar
    calendar=$(_abf_build_systemd_calendar "$frequency" "$time" "0")

    _abf_systemd_write_unit "$timer_file" \
        "[Unit]" \
        "Description=Backup Framework - ${frequency} backup at ${time}" \
        "Requires=${unit_name}.service" \
        "" \
        "[Timer]" \
        "OnCalendar=${calendar}" \
        "Persistent=true" \
        "" \
        "[Install]" \
        "WantedBy=timers.target"

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable "${unit_name}.timer" 2>/dev/null || true
    systemctl start "${unit_name}.timer" 2>/dev/null || true

    local description
    description=$(_abf_describe_schedule "$frequency" "$time" "0")
    echo "Backup schedule updated."
    echo ""
    echo "Enabled : Yes"
    echo "Time    : ${description}"

    local next_str
    next_str=$(systemctl show -p NextElapseUSecRealtime "${unit_name}.timer" 2>/dev/null \
        | sed 's/NextElapseUSecRealtime=//' || true)
    if [[ -n "$next_str" ]] && [[ "$next_str" != "n/a" ]]; then
        echo "Next Run: ${next_str}"
    fi

    return "$ABF_EXIT_OK"
}

abf_schedule_global_disable() {
    local backend
    backend=$(_abf_scheduler_detect)
    if [[ "$backend" != "systemd" ]]; then
        echo "No scheduling system available."
        return "$ABF_EXIT_OK"
    fi

    local unit_name="abf-backup"

    systemctl stop "${unit_name}.timer" 2>/dev/null || true
    systemctl disable "${unit_name}.timer" 2>/dev/null || true
    rm -f "/etc/systemd/system/${unit_name}.timer" \
          "/etc/systemd/system/${unit_name}.service"
    systemctl daemon-reload 2>/dev/null || true

    SCHEDULE_ENABLED="false"
    _abf_schedule_global_save_config

    echo "Backup schedule removed."
    return "$ABF_EXIT_OK"
}

abf_schedule_global_status() {
    local unit_name="abf-backup"
    local timer_file="/etc/systemd/system/${unit_name}.timer"

    _abf_schedule_global_load_config

    if [[ ! -f "$timer_file" ]]; then
        echo "No backup schedule configured."
        echo "Use 'abf schedule daily HH:MM' or 'abf schedule enable' to create one."
        return "$ABF_EXIT_OK"
    fi

    local enabled_status
    enabled_status=$(systemctl is-enabled "${unit_name}.timer" 2>/dev/null || echo "disabled")
    local active_status
    active_status=$(systemctl is-active "${unit_name}.timer" 2>/dev/null || echo "inactive")
    local calendar
    calendar=$(systemctl show -p OnCalendar "${unit_name}.timer" 2>/dev/null \
        | sed 's/OnCalendar=//' || echo "unknown")

    local description
    local time_part="00:00"
    if [[ "$calendar" =~ ^\*-\*-\*\ ([0-9]{2}):([0-9]{2}):00$ ]]; then
        time_part="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
        description="Daily at ${time_part}"
    elif [[ "$calendar" =~ ^[A-Z][a-z]+\ \*-\*-\*\ ([0-9]{2}):([0-9]{2}):00$ ]]; then
        time_part="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
        description="Weekly at ${time_part}"
    fi

    # Fall back to saved config when systemctl parsing failed
    if [[ -z "$description" ]]; then
        description=$(_abf_describe_schedule "$SCHEDULE_FREQUENCY" "$SCHEDULE_TIME" "0")
    fi

    local is_on="No"
    if [[ "$enabled_status" == "enabled" ]] || [[ "$active_status" == "active" ]]; then
        is_on="Yes"
    fi
    echo "Enabled : ${is_on}"
    echo "Time    : ${description}"

    local next_str
    next_str=$(systemctl show -p NextElapseUSecRealtime "${unit_name}.timer" 2>/dev/null \
        | sed 's/NextElapseUSecRealtime=//' || true)
    if [[ -n "$next_str" ]] && [[ "$next_str" != "n/a" ]]; then
        echo "Next Run: ${next_str}"
    fi

    local last_str
    last_str=$(systemctl show -p LastTriggerUSec "${unit_name}.timer" 2>/dev/null \
        | sed 's/LastTriggerUSec=//' || true)
    if [[ -n "$last_str" ]] && [[ "$last_str" != "n/a" ]]; then
        echo "Last Run: ${last_str}"
    fi

    return "$ABF_EXIT_OK"
}

abf_schedule_global_is_enabled() {
    local unit_name="abf-backup"
    local timer_file="/etc/systemd/system/${unit_name}.timer"

    if [[ ! -f "$timer_file" ]]; then
        return 1
    fi

    local enabled_status
    enabled_status=$(systemctl is-enabled "${unit_name}.timer" 2>/dev/null || echo "disabled")
    if [[ "$enabled_status" == "enabled" ]]; then
        return 0
    fi

    local active_status
    active_status=$(systemctl is-active "${unit_name}.timer" 2>/dev/null || echo "inactive")
    if [[ "$active_status" == "active" ]]; then
        return 0
    fi

    return 1
}
