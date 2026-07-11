# ---------------------------------------------------------------------------
# Tests for the status module
# ---------------------------------------------------------------------------

test_status_format_time_today() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-status-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/status.sh"

    local now_iso
    now_iso=$(date +"%Y-%m-%dT%H:%M:%S%z")
    local time_only
    time_only=$(date -d "$now_iso" +"%H:%M" 2>/dev/null || date +"%H:%M")
    local result
    result=$(_abf_status_format_time "$now_iso")
    assert_contains "$result" "Today" "Shows Today for recent time"
    assert_contains "$result" "$time_only" "Shows time for today"

    rm -rf "$tmpdir"
}

test_status_format_time_yesterday() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/status.sh"

    local yesterday_iso
    yesterday_iso=$(date -d "yesterday" +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null) || {
        echo "  SKIP: date -d yesterday not supported"
        return 0
    }
    local time_only
    time_only=$(date -d "yesterday" +"%H:%M" 2>/dev/null || echo "??:??")
    local result
    result=$(_abf_status_format_time "$yesterday_iso")
    assert_contains "$result" "Yesterday" "Shows Yesterday for yesterday"
    assert_contains "$result" "$time_only" "Shows time for yesterday"
}

test_status_format_time_never() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/status.sh"

    local result
    result=$(_abf_status_format_time "")
    assert_eq "Never" "$result" "Empty time shows Never"
}

test_status_format_time_older() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/status.sh"

    local old_date="2024-01-15T03:00:00+0000"
    local time_only
    time_only=$(date -d "$old_date" +"%H:%M" 2>/dev/null || echo "03:00")
    local result
    result=$(_abf_status_format_time "$old_date")
    assert_contains "$result" "Jan 15" "Shows month/day for older date"
    assert_contains "$result" "$time_only" "Shows time for older date"
}

test_status_notification_disabled() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-status-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/status.sh"

    SMTP_ENABLED="false"
    SMTP_HOST=""
    local result
    result=$(_abf_status_notification_status)
    assert_eq "Disabled" "$result" "Notifications disabled"

    rm -rf "$tmpdir"
}

test_status_notification_enabled_configured() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-status-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/status.sh"

    SMTP_ENABLED="true"
    SMTP_HOST="mail.example.com"
    local result
    result=$(_abf_status_notification_status)
    assert_eq "OK" "$result" "Notifications configured OK"

    rm -rf "$tmpdir"
}

test_status_notification_enabled_not_configured() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-status-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/status.sh"

    SMTP_ENABLED="true"
    SMTP_HOST=""
    local result
    result=$(_abf_status_notification_status)
    assert_eq "Not configured" "$result" "Notifications not configured"

    rm -rf "$tmpdir"
}

test_status_storage_configured_local() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-status-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "status-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/status.sh"
    source "${ABF_ROOT}/core/core.sh"

    ABF_CONFIG_DIR="$tmpdir"
    ABF_STORAGE_BACKEND="local"
    local result
    result=$(_abf_status_storage_status)
    # Local storage returns OK even without restic (falls through to "OK" when restic is unavailable)
    assert_eq "OK" "$result" "Local storage returns OK when configured"

    rm -rf "$tmpdir"
}

test_status_human_output_format() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-status-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/status.sh"

    local version="0.1.1-beta"
    local svc_data="vaultwarden|Today 03:00|SUCCESS|Healthy|onedrive:Connected|Delivered"
    local sched_enabled="Yes"
    local sched_next="Tomorrow 03:00"
    local sched_time="Daily at 03:00"
    local storage_status="OK"
    local notif_status="OK"
    local overall="HEALTHY"

    local output
    output=$(_abf_status_output_human \
        "$version" "$svc_data" \
        "$sched_enabled" "$sched_next" "$sched_time" \
        "$storage_status" "$notif_status" "$overall")

    assert_contains "$output" "Backup Framework v0.1.1-beta" "Human output shows version"
    assert_contains "$output" "Overall Health" "Human output has health section"
    assert_contains "$output" "HEALTHY" "Human output shows healthy"
    assert_contains "$output" "Vaultwarden" "Human output shows service name"
    assert_contains "$output" "Today 03:00" "Human output shows last backup"
    assert_contains "$output" "Scheduler" "Human output has scheduler section"
    assert_contains "$output" "Enabled" "Human output shows enabled"
    assert_contains "$output" "Tomorrow 03:00" "Human output shows next run"
    assert_contains "$output" "Storage" "Human output has storage section"
    assert_contains "$output" "Notifications" "Human output has notifications section"

    rm -rf "$tmpdir"
}

test_status_human_output_disabled_service() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-status-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/status.sh"

    local version="0.1.1-beta"
    local svc_data="immich||Disabled|||"
    local sched_enabled="No"
    local sched_next=""
    local sched_time=""
    local storage_status="OK"
    local notif_status="Disabled"
    local overall="WARNING"

    local output
    output=$(_abf_status_output_human \
        "$version" "$svc_data" \
        "$sched_enabled" "$sched_next" "$sched_time" \
        "$storage_status" "$notif_status" "$overall")

    assert_contains "$output" "Immich" "Human output shows disabled service"
    assert_contains "$output" "Disabled" "Human output shows Disabled status"

    rm -rf "$tmpdir"
}

test_status_short_output() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-status-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/status.sh"

    local version="0.1.1-beta"
    local svc_data="vaultwarden|Today 03:00|SUCCESS|Healthy|onedrive:Connected|Delivered"
    local sched_enabled="Yes"
    local sched_next="Tomorrow 03:00"
    local sched_time="Daily at 03:00"
    local storage_status="OK"
    local notif_status="OK"
    local overall="HEALTHY"

    local output
    output=$(_abf_status_output_short \
        "$version" "$svc_data" \
        "$sched_enabled" "$sched_next" "$sched_time" \
        "$storage_status" "$notif_status" "$overall")

    assert_contains "$output" "All systems healthy" "Short output shows healthy"
    assert_contains "$output" "Vaultwarden" "Short output mentions service"
    assert_contains "$output" "Today 03:00" "Short output shows time"
    assert_contains "$output" "Next backup" "Short output shows next backup"

    rm -rf "$tmpdir"
}

test_status_short_output_warning() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/status.sh"

    local output
    output=$(_abf_status_output_short \
        "0.1.1-beta" "immich||Disabled|||" \
        "No" "" "" \
        "OK" "Disabled" "WARNING")

    assert_contains "$output" "Some systems need attention" "Short output shows warning"
}

test_status_short_output_unhealthy() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/status.sh"

    local output
    output=$(_abf_status_output_short \
        "0.1.1-beta" "vaultwarden||FAILED|||" \
        "No" "" "" \
        "Unreachable" "Disabled" "UNHEALTHY")

    assert_contains "$output" "System issues detected" "Short output shows unhealthy"
}

test_status_json_output() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-status-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/status.sh"

    local version="0.1.1-beta"
    local svc_data="vaultwarden|Today 03:00|SUCCESS|Healthy|onedrive:Connected|Delivered"
    local sched_enabled="Yes"
    local sched_next="Tomorrow 03:00"
    local sched_time="Daily at 03:00"
    local storage_status="OK"
    local notif_status="OK"
    local overall="HEALTHY"

    local output
    output=$(_abf_status_output_json \
        "$version" "$svc_data" \
        "$sched_enabled" "$sched_next" "$sched_time" \
        "$storage_status" "$notif_status" "$overall")

    assert_contains "$output" '"version": "0.1.1-beta"' "JSON has version"
    assert_contains "$output" '"overall_health": "HEALTHY"' "JSON has overall health"
    assert_contains "$output" '"vaultwarden"' "JSON has service name"
    assert_contains "$output" '"status": "SUCCESS"' "JSON has service status"
    assert_contains "$output" '"enabled": true' "JSON has scheduler enabled"
    assert_contains "$output" '"smtp": "OK"' "JSON has smtp status"
    assert_contains "$output" '"local": "OK"' "JSON has local storage"

    rm -rf "$tmpdir"
}

test_status_json_output_disabled_service() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/status.sh"

    local output
    output=$(_abf_status_output_json \
        "0.1.1-beta" "immich||Disabled|||" \
        "No" "" "" \
        "OK" "Disabled" "WARNING")

    assert_contains "$output" '"status": "Disabled"' "JSON has disabled status"
    assert_contains "$output" '"enabled": false' "JSON has scheduler disabled"
}

test_status_json_output_multiple_services() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/status.sh"

    local svc_data
    svc_data=$(printf "vaultwarden|Today 03:00|SUCCESS|Healthy|onedrive:Connected|Delivered\nimmich||Disabled|||")
    local output
    output=$(_abf_status_output_json \
        "0.1.1-beta" "$svc_data" \
        "Yes" "Tomorrow 03:00" "Daily at 03:00" \
        "OK" "OK" "HEALTHY")

    assert_contains "$output" '"vaultwarden"' "JSON has vaultwarden"
    assert_contains "$output" '"immich"' "JSON has immich"
    assert_contains "$output" '"services"' "JSON has services block"

    # Validate it's valid JSON by checking structure
    assert_contains "$output" '"version"' "JSON starts with version"
    assert_contains "$output" '"timestamp"' "JSON has timestamp"
    assert_contains "$output" '"scheduler"' "JSON has scheduler"
    assert_contains "$output" '"storage"' "JSON has storage"
    assert_contains "$output" '"notifications"' "JSON has notifications"
}

# Regression: Bug 2 — _abf_status_get_snapshot_time must return 0 when repo is empty
# to avoid triggering set -Eeuo pipefail in the CLI
test_status_get_snapshot_time_returns_zero_on_empty_repo() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/status.sh"

    local result
    local rc=0
    result=$(_abf_status_get_snapshot_time "test-svc" "") || rc=$?
    assert_eq "0" "$rc" "Exit code must be 0 when repo is empty"
    assert_eq "" "$result" "Output must be empty when repo is empty"
}

# Regression: Bug 2 — _abf_status_get_snapshot_time must return 0 when restic is missing
test_status_get_snapshot_time_returns_zero_without_restic() {
    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/core.sh"
    source "${ABF_ROOT}/core/status.sh"

    local result
    local rc=0
    # Provide a non-empty repo path but restic unavailable
    result=$(_abf_status_get_snapshot_time "test-svc" "/tmp/fake-repo") || rc=$?
    assert_eq "0" "$rc" "Exit code must be 0 when restic is not available"
    assert_eq "" "$result" "Output must be empty when restic is not available"
}
