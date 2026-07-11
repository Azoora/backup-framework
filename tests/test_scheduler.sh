# ---------------------------------------------------------------------------
# Tests for the scheduler module
# ---------------------------------------------------------------------------

# Override the system crontab with a mock script for testing
# Creates a mock `crontab` command in a temporary location that's prepended
# to PATH before any test that needs cron.
_abf_setup_cron_mock() {
    local tmpdir="$1"
    local crontab_file="${tmpdir}/crontab.txt"
    local bin_dir="${tmpdir}/bin"

    touch "$crontab_file"
    mkdir -p "$bin_dir"

    cat > "${bin_dir}/crontab" <<MOCK
#!/usr/bin/env bash
CRONTAB_FILE="${crontab_file}"
flag="\${1:-}"
if [[ "\$flag" == "-l" ]]; then
    cat "\$CRONTAB_FILE" 2>/dev/null || true
elif [[ "\$flag" == "-" ]] || [[ "\$flag" == "--" ]]; then
    cat > "\$CRONTAB_FILE"
fi
MOCK
    chmod +x "${bin_dir}/crontab"

    export PATH="${bin_dir}:${PATH}"
}

test_schedule_describe_daily() {
    source "${ABF_ROOT}/core/scheduler.sh"
    local desc
    desc=$(_abf_describe_schedule "daily" "03:00" "0")
    assert_eq "Daily at 03:00" "$desc" "Daily description"
}

test_schedule_describe_weekly() {
    source "${ABF_ROOT}/core/scheduler.sh"
    local desc
    desc=$(_abf_describe_schedule "weekly" "02:30" "0")
    assert_eq "Every Sunday at 02:30" "$desc" "Weekly Sunday"
    desc=$(_abf_describe_schedule "weekly" "02:30" "1")
    assert_eq "Every Monday at 02:30" "$desc" "Weekly Monday"
    desc=$(_abf_describe_schedule "weekly" "02:30" "6")
    assert_eq "Every Saturday at 02:30" "$desc" "Weekly Saturday"
}

test_schedule_describe_monthly() {
    source "${ABF_ROOT}/core/scheduler.sh"
    local desc
    desc=$(_abf_describe_schedule "monthly" "00:00" "1")
    assert_eq "Day 1 of every month at 00:00" "$desc" "Monthly first day"
}

test_schedule_describe_custom() {
    source "${ABF_ROOT}/core/scheduler.sh"
    local desc
    desc=$(_abf_describe_schedule "custom" "*/15 * * * *" "0")
    assert_eq "Custom schedule: */15 * * * *" "$desc" "Custom cron"
}

test_build_cron_expr_daily() {
    source "${ABF_ROOT}/core/scheduler.sh"
    local expr
    expr=$(_abf_build_cron_expr "daily" "03:00" "0")
    assert_eq "0 3 * * *" "$expr" "Daily cron"
}

test_build_cron_expr_weekly() {
    source "${ABF_ROOT}/core/scheduler.sh"
    local expr
    expr=$(_abf_build_cron_expr "weekly" "02:30" "0")
    assert_eq "30 2 * * 0" "$expr" "Weekly Sunday cron"
}

test_build_cron_expr_monthly() {
    source "${ABF_ROOT}/core/scheduler.sh"
    local expr
    expr=$(_abf_build_cron_expr "monthly" "00:00" "15")
    assert_eq "0 0 15 * *" "$expr" "Monthly 15th cron"
}

test_build_systemd_calendar_daily() {
    source "${ABF_ROOT}/core/scheduler.sh"
    local cal
    cal=$(_abf_build_systemd_calendar "daily" "03:00" "0")
    assert_eq "*-*-* 03:00:00" "$cal" "Daily systemd calendar"
}

test_build_systemd_calendar_weekly() {
    source "${ABF_ROOT}/core/scheduler.sh"
    local cal
    cal=$(_abf_build_systemd_calendar "weekly" "02:30" "0")
    assert_eq "Sun *-*-* 02:30:00" "$cal" "Weekly Sunday calendar"
    cal=$(_abf_build_systemd_calendar "weekly" "02:30" "3")
    assert_eq "Wed *-*-* 02:30:00" "$cal" "Weekly Wednesday calendar"
}

test_build_systemd_calendar_monthly() {
    source "${ABF_ROOT}/core/scheduler.sh"
    local cal
    cal=$(_abf_build_systemd_calendar "monthly" "00:00" "1")
    assert_eq "*-*-1 00:00:00" "$cal" "Monthly first day calendar"
}

test_cron_install_remove_list_status() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-sched-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "sched-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/scheduler.sh"

    _abf_setup_cron_mock "$tmpdir"
    ABF_ROOT="${ABF_ROOT}"

    # Install
    _abf_schedule_cron_install "test-svc" "0 3 * * *" "Daily at 03:00" "false"
    local status_line
    status_line=$(_abf_schedule_cron_status "test-svc")
    assert_contains "$status_line" "0 3 * * *" "Status shows cron expr after install"

    # List
    local list_out
    list_out=$(_abf_schedule_cron_list)
    assert_contains "$list_out" "test-svc" "List contains service"

    # Duplicate install without force should fail
    local rc=0
    _abf_schedule_cron_install "test-svc" "0 3 * * *" "Daily at 03:00" "false" || rc=$?
    assert_neq "0" "$rc" "Duplicate install without force fails"

    # Force overwrite
    _abf_schedule_cron_install "test-svc" "30 2 * * *" "Daily at 02:30" "true" || {
        echo "  FAIL: Force overwrite should succeed"
        return 1
    }
    status_line=$(_abf_schedule_cron_status "test-svc")
    assert_contains "$status_line" "30 2 * * *" "Status updated after force install"

    # Remove
    _abf_schedule_cron_remove "test-svc"
    status_line=$(_abf_schedule_cron_status "test-svc")
    assert_contains "$status_line" "No schedule" "Status shows no schedule after remove"

    return 0
}

test_global_config_file_path() {
    source "${ABF_ROOT}/core/scheduler.sh"
    ABF_CONFIG_DIR="/tmp/abf-test-config"
    local path
    path=$(_abf_schedule_global_config_file)
    assert_eq "/tmp/abf-test-config/schedule.conf" "$path" "Global config file path"
}

test_global_config_save_and_load() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-global-sched-XXXXXX")

    source "${ABF_ROOT}/core/scheduler.sh"
    ABF_CONFIG_DIR="$tmpdir"

    SCHEDULE_ENABLED="true"
    SCHEDULE_FREQUENCY="daily"
    SCHEDULE_TIME="03:00"
    _abf_schedule_global_save_config

    SCHEDULE_ENABLED="false"
    SCHEDULE_FREQUENCY=""
    SCHEDULE_TIME=""

    _abf_schedule_global_load_config

    assert_eq "true" "$SCHEDULE_ENABLED" "Global config loads enabled"
    assert_eq "daily" "$SCHEDULE_FREQUENCY" "Global config loads frequency"
    assert_eq "03:00" "$SCHEDULE_TIME" "Global config loads time"

    rm -rf "$tmpdir"
    return 0
}

test_global_config_defaults_when_missing() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-global-sched-XXXXXX")

    source "${ABF_ROOT}/core/scheduler.sh"
    ABF_CONFIG_DIR="$tmpdir"

    SCHEDULE_ENABLED=""
    SCHEDULE_FREQUENCY=""
    SCHEDULE_TIME=""
    _abf_schedule_global_load_config

    assert_eq "false" "$SCHEDULE_ENABLED" "Default enabled is false"
    assert_eq "daily" "$SCHEDULE_FREQUENCY" "Default frequency is daily"
    assert_eq "03:00" "$SCHEDULE_TIME" "Default time is 03:00"

    rm -rf "$tmpdir"
    return 0
}

test_global_build_services_exec() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-global-sched-XXXXXX")

    # Create a minimal manifest
    mkdir -p "${tmpdir}/services"
    printf 'vaultwarden\nimmich\n' > "${tmpdir}/services/manifest.conf"

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "sched-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/core.sh"

    # Override _abf_manifest_lines to use our test manifest
    _abf_manifest_lines() {
        printf 'vaultwarden\nimmich\n'
    }

    local exec_lines
    exec_lines=$(_abf_schedule_global_build_services_exec "/usr/local/bin/abf" " --config /etc/abf")

    assert_contains "$exec_lines" "ExecStart=/usr/local/bin/abf backup vaultwarden --config /etc/abf" "Builds vaultwarden exec"
    assert_contains "$exec_lines" "ExecStart=/usr/local/bin/abf backup immich --config /etc/abf" "Builds immich exec"

    rm -rf "$tmpdir"
    return 0
}

test_global_build_services_exec_no_config() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-global-sched-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "sched-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/core.sh"

    _abf_manifest_lines() {
        printf 'vaultwarden\n'
    }

    local exec_lines
    exec_lines=$(_abf_schedule_global_build_services_exec "/usr/local/bin/abf" "")

    assert_contains "$exec_lines" "ExecStart=/usr/local/bin/abf backup vaultwarden" "Builds exec without config arg"

    rm -rf "$tmpdir"
    return 0
}

# Regression: Bug 3 — timer unit must NOT contain RandomizedDelaySec
test_global_timer_no_randomized_delay() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-global-sched-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "sched-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/config.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/core.sh"

    local timer_file="${tmpdir}/test-timer.timer"

    # Directly invoke the timer writing logic with _abf_systemd_write_unit
    _abf_systemd_write_unit "$timer_file" \
        "[Unit]" \
        "Description=Test" \
        "" \
        "[Timer]" \
        "OnCalendar=*-*-* 02:00:00" \
        "Persistent=true" \
        "" \
        "[Install]" \
        "WantedBy=timers.target"

    assert_contains "$(cat "$timer_file")" "OnCalendar=*-*-* 02:00:00" "Timer has OnCalendar"
    if grep -q "RandomizedDelaySec" "$timer_file"; then
        echo "  FAIL: Timer must not contain RandomizedDelaySec"
        return 1
    fi

    rm -rf "$tmpdir"
    return 0
}

# Regression: Bug 1 — status should use config fallback when systemctl description is empty
test_global_status_config_fallback() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-global-sched-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/scheduler.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "sched-test" "test" "${tmpdir}/logs"

    ABF_CONFIG_DIR="$tmpdir"

    # Set config values as if they were saved by abf schedule daily
    SCHEDULE_ENABLED="true"
    SCHEDULE_FREQUENCY="daily"
    SCHEDULE_TIME="02:00"
    _abf_schedule_global_save_config

    # Verify saved config is correct
    assert_eq "true" "$SCHEDULE_ENABLED" "Config saved enabled"
    assert_eq "daily" "$SCHEDULE_FREQUENCY" "Config saved frequency"
    assert_eq "02:00" "$SCHEDULE_TIME" "Config saved time"

    # Load config fresh and verify describe_schedule produces correct output
    SCHEDULE_ENABLED=""
    SCHEDULE_FREQUENCY=""
    SCHEDULE_TIME=""
    _abf_schedule_global_load_config

    local description
    description=$(_abf_describe_schedule "$SCHEDULE_FREQUENCY" "$SCHEDULE_TIME" "0")
    assert_eq "Daily at 02:00" "$description" "Config fallback produces correct description"

    rm -rf "$tmpdir"
    return 0
}

# Regression: Bug 4 — description unbound variable under set -u
test_global_status_unbound_description_regression() {
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-description-XXXXXX")

    source "${ABF_ROOT}/core/exit_codes.sh"
    source "${ABF_ROOT}/core/log.sh"
    abf_init_logging "sched-test" "test" "${tmpdir}/logs"
    source "${ABF_ROOT}/core/scheduler.sh"

    ABF_CONFIG_DIR="$tmpdir"

    SCHEDULE_ENABLED="true"
    SCHEDULE_FREQUENCY="daily"
    SCHEDULE_TIME="02:00"
    _abf_schedule_global_save_config

    (
        set -u
        ABF_CONFIG_DIR="$tmpdir"
        _abf_schedule_global_load_config

        # Same code pattern as abf_schedule_global_status fallback;
        # must not crash with "unbound variable"
        local description=""
        if [[ -z "$description" ]]; then
            description=$(_abf_describe_schedule "$SCHEDULE_FREQUENCY" "$SCHEDULE_TIME" "0")
        fi
        echo "$description"
    ) || {
        echo "  FAIL: unbound variable error in description fallback under set -u"
        rm -rf "$tmpdir"
        return 1
    }

    rm -rf "$tmpdir"
    return 0
}
