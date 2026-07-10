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
