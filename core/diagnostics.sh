# ---------------------------------------------------------------------------
# diagnostics.sh  --  Framework health diagnostics (abf doctor)
#
# Runs a comprehensive set of checks covering every component.
# Exit codes: 0 = healthy, 1 = warning, 2 = error (Nagios-compatible).
# ---------------------------------------------------------------------------

ABF_DIAG_RESULTS=()
ABF_DIAG_OVERALL="OK"

# ------------------------------------------------------------------
# Result accumulator
# ------------------------------------------------------------------

_abf_diag_result() {
    local status="$1"   # OK, WARNING, ERROR
    local name="$2"
    local message="$3"
    ABF_DIAG_RESULTS+=("${status}|${name}|${message}")
}

_abf_diag_overall() {
    local worst="OK"
    for entry in "${ABF_DIAG_RESULTS[@]}"; do
        local s="${entry%%|*}"
        case "$s" in
            ERROR)   worst="ERROR" ;;
            WARNING) [[ "$worst" != "ERROR" ]] && worst="WARNING" ;;
        esac
    done
    ABF_DIAG_OVERALL="$worst"
}

# ------------------------------------------------------------------
# Individual checks
# ------------------------------------------------------------------

_abf_diag_check_sqlite3() {
    if command -v sqlite3 &>/dev/null; then
        _abf_diag_result "OK" "sqlite3_installed" "sqlite3 is installed"
    else
        _abf_diag_result "WARNING" "sqlite3_installed" "sqlite3 not installed (recommended for consistent SQLite backups)"
    fi
}

_abf_diag_check_rsync() {
    if command -v rsync &>/dev/null; then
        _abf_diag_result "OK" "rsync_installed" "rsync is installed"
    else
        _abf_diag_result "ERROR" "rsync_installed" "rsync not installed (required for restore operations)"
    fi
}

_abf_diag_check_rclone_config() {
    if ! command -v rclone &>/dev/null; then
        local backend="${ABF_STORAGE_BACKEND:-local}"
        if [[ "$backend" != "local" ]]; then
            _abf_diag_result "ERROR" "rclone_config" "Rclone not installed (required by storage backend: ${backend})"
        else
            _abf_diag_result "WARNING" "rclone_config" "Rclone not installed (needed for remote storage backends)"
        fi
        return 0
    fi

    if rclone lsd "${STORAGE_ONEDRIVE_REMOTE:-}:" &>/dev/null 2>&1; then
        _abf_diag_result "OK" "rclone_config" "Rclone configured and remote reachable"
    else
        local backend="${ABF_STORAGE_BACKEND:-local}"
        if [[ "$backend" != "local" ]]; then
            _abf_diag_result "ERROR" "rclone_config" "Rclone remote not reachable (required by storage backend: ${backend})"
        else
            _abf_diag_result "WARNING" "rclone_config" "Rclone not configured (run: rclone config)"
        fi
    fi
}

_abf_diag_check_version() {
    local ver
    ver=$(cat "${ABF_ROOT}/VERSION" 2>/dev/null || echo "unknown")
    _abf_diag_result "OK" "framework_version" "Backup Framework v${ver}"
}

_abf_diag_check_config() {
    if abf_validate_config 2>/dev/null 1>&2; then
        _abf_diag_result "OK" "config_valid" "Configuration is valid"
    else
        _abf_diag_result "ERROR" "config_valid" "Configuration validation failed"
    fi
}

_abf_diag_check_restic() {
    if command -v restic &>/dev/null; then
        local ver
        ver=$(restic version 2>/dev/null | head -1 || echo "installed")
        _abf_diag_result "OK" "restic_installed" "Restic ${ver}"
    else
        _abf_diag_result "ERROR" "restic_installed" "Restic is not installed"
    fi
}

_abf_diag_check_rclone() {
    if command -v rclone &>/dev/null; then
        _abf_diag_result "OK" "rclone_installed" "Rclone is installed"
    else
        _abf_diag_result "WARNING" "rclone_installed" "Rclone is not installed (needed for OneDrive)"
    fi
}

_abf_diag_check_repository() {
    local repo
    repo=$(_abf_get_storage_repo 2>/dev/null) || {
        _abf_diag_result "OK" "repository" "No storage backend configured"
        return 0
    }

    if [[ -z "${ABF_RESTIC_PASSWORD_FILE:-}" ]] \
        || [[ ! -f "${ABF_RESTIC_PASSWORD_FILE:-}" ]]; then
        _abf_diag_result "ERROR" "repository" "Repository password file missing: ${ABF_RESTIC_PASSWORD_FILE:-/etc/abf/restic-password}"
        return 1
    fi

    if command -v restic &>/dev/null; then
        if restic -r "$repo" --password-file "$ABF_RESTIC_PASSWORD_FILE" \
            snapshots --json --quiet &>/dev/null 2>&1; then
            _abf_diag_result "OK" "repository" "Repository reachable: ${repo}"
        else
            _abf_diag_result "ERROR" "repository" "Repository unreachable: ${repo}"
        fi
    fi
}

_abf_diag_check_storage_backend() {
    local backend="${ABF_STORAGE_BACKEND:-local}"

    if abf_load_storage_module "$backend" 2>/dev/null \
        && abf_load_storage_config "$backend" 2>/dev/null; then
        _abf_diag_result "OK" "storage_backend" "Storage backend: ${backend}"
    else
        _abf_diag_result "ERROR" "storage_backend" "Storage module not found: ${backend}"
    fi
}

_abf_diag_check_smtp() {
    if [[ "${SMTP_ENABLED:-false}" != "true" ]]; then
        _abf_diag_result "OK" "smtp_config" "SMTP notifications disabled"
        return 0
    fi

    if [[ -n "${SMTP_HOST:-}" ]]; then
        _abf_diag_result "OK" "smtp_config" "SMTP configured (${SMTP_HOST}:${SMTP_PORT:-25})"
    else
        _abf_diag_result "WARNING" "smtp_config" "SMTP enabled but SMTP_HOST not set"
    fi
}

_abf_diag_check_smtp_connect() {
    if [[ "${SMTP_ENABLED:-false}" != "true" ]] || [[ -z "${SMTP_HOST:-}" ]]; then
        return 0
    fi

    local port="${SMTP_PORT:-25}"
    if timeout 5 bash -c "echo > /dev/tcp/${SMTP_HOST}/${port}" 2>/dev/null; then
        _abf_diag_result "OK" "smtp_connect" "SMTP reachable (${SMTP_HOST}:${port})"
    else
        _abf_diag_result "WARNING" "smtp_connect" "Cannot connect to SMTP (${SMTP_HOST}:${port})"
    fi
}

_abf_diag_check_scheduler() {
    local backend
    backend=$(_abf_scheduler_detect)
    if [[ "$backend" == "none" ]]; then
        _abf_diag_result "WARNING" "scheduler" "No scheduling system available"
        return 0
    fi

    local list_output
    list_output=$(abf_schedule_list 2>/dev/null)
    if echo "$list_output" | grep -q "Scheduled backups:"; then
        _abf_diag_result "OK" "scheduler" "Scheduler active (${backend}) with schedule(s)"
    else
        _abf_diag_result "OK" "scheduler" "Scheduler available (${backend}), no schedules configured"
    fi
}

_abf_diag_check_lock_dir() {
    local lock_dir="${ABF_LOCK_DIR:-${ABF_TEMP_DIR:-/tmp/abf}/locks}"
    if mkdir -p "$lock_dir" 2>/dev/null && [[ -w "$lock_dir" ]]; then
        _abf_diag_result "OK" "lock_dir" "Lock directory writable: ${lock_dir}"
    else
        _abf_diag_result "ERROR" "lock_dir" "Lock directory not writable: ${lock_dir}"
    fi
}

_abf_diag_check_backup_dirs() {
    local issues=0
    while IFS= read -r svc; do
        local prefix
        prefix=$(_abf_svc_var_prefix "$svc")
        local dir_var="${prefix}_BACKUP_DIR"
        local dir="${!dir_var:-}"
        if [[ -n "$dir" ]] && [[ ! -d "$dir" ]]; then
            issues=1
        fi
    done < <(_abf_manifest_lines)

    if [[ "$issues" -eq 0 ]]; then
        _abf_diag_result "OK" "backup_dirs" "Backup directories accessible"
    else
        _abf_diag_result "WARNING" "backup_dirs" "Some backup directories do not exist"
    fi
}

_abf_diag_check_service_config() {
    local issues=0
    while IFS= read -r svc; do
        local module="${ABF_ROOT}/services/${svc}/module.sh"
        if [[ ! -f "$module" ]]; then
            _abf_diag_result "ERROR" "service_${svc}" "Service module missing: ${module}"
            issues=1
            continue
        fi
        local hooks_ok=true
        local required=(service_pre_backup service_backup service_verify_backup service_post_backup)

        # shellcheck disable=SC1090
        source "$module" 2>/dev/null || hooks_ok=false
        for func in "${required[@]}"; do
            if ! declare -F "$func" &>/dev/null; then
                hooks_ok=false
                break
            fi
        done

        if $hooks_ok; then
            _abf_diag_result "OK" "service_${svc}" "Service '${svc}' module loaded (all hooks present)"
        else
            _abf_diag_result "ERROR" "service_${svc}" "Service '${svc}' module missing required hooks"
            issues=1
        fi
    done < <(_abf_manifest_lines)

    if [[ "$issues" -eq 0 ]]; then
        : # individual results already added
    fi
}

_abf_diag_check_backup_age() {
    local repo
    repo=$(_abf_get_storage_repo 2>/dev/null) || {
        _abf_diag_result "OK" "backup_age" "No storage backend — age check skipped"
        return 0
    }

    if ! command -v restic &>/dev/null; then
        _abf_diag_result "WARNING" "backup_age" "Cannot check backup age (restic not installed)"
        return 0
    fi

    if [[ -z "${ABF_RESTIC_PASSWORD_FILE:-}" ]] \
        || [[ ! -f "${ABF_RESTIC_PASSWORD_FILE:-}" ]]; then
        return 0
    fi

    local latest
    latest=$(restic -r "$repo" --password-file "$ABF_RESTIC_PASSWORD_FILE" \
        snapshots --json 2>/dev/null \
        | grep -oP '"time"\s*:\s*"\K[^"]+' | sort | tail -1) || true

    if [[ -z "$latest" ]]; then
        _abf_diag_result "WARNING" "backup_age" "No snapshots found in repository"
        return 0
    fi

    local latest_epoch now_epoch diff_days
    latest_epoch=$(date -d "$latest" +%s 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    diff_days=$(( (now_epoch - latest_epoch) / 86400 ))

    if [[ "$diff_days" -le 1 ]]; then
        _abf_diag_result "OK" "backup_age" "Latest backup: ${diff_days} day(s) ago"
    elif [[ "$diff_days" -le 7 ]]; then
        _abf_diag_result "WARNING" "backup_age" "Latest backup is ${diff_days} day(s) old"
    else
        _abf_diag_result "ERROR" "backup_age" "Latest backup is ${diff_days} day(s) old (threshold: 7)"
    fi
}

# ------------------------------------------------------------------
# Output helpers
# ------------------------------------------------------------------

_abf_diag_output_human() {
    local header="Diagnostics — Backup Framework v$(cat "${ABF_ROOT}/VERSION" 2>/dev/null || echo "?")"
    local sep
    sep=$(printf '%*s' "${#header}" '' | tr ' ' '=')

    echo ""
    echo "${header}"
    echo "${sep}"
    echo ""

    local errors=0 warnings=0 passes=0
    for entry in "${ABF_DIAG_RESULTS[@]}"; do
        local status="${entry%%|*}"
        local rest="${entry#*|}"
        local name="${rest%%|*}"
        local message="${rest#*|}"

        case "$status" in
            OK)
                printf "  [PASS] %s  — %s\n" "$name" "$message"
                passes=$((passes + 1))
                ;;
            WARNING)
                printf "  [WARN] %s  — %s\n" "$name" "$message"
                warnings=$((warnings + 1))
                ;;
            ERROR)
                printf "  [FAIL] %s  — %s\n" "$name" "$message"
                errors=$((errors + 1))
                ;;
        esac
    done

    echo ""
    echo "${sep}"
    echo "  Overall: ${ABF_DIAG_OVERALL}  (${passes} passed, ${warnings} warnings, ${errors} errors)"
    echo "${sep}"
    echo ""
}

_abf_diag_output_json() {
    local first=true
    cat <<EOF
{
  "version": "$(cat "${ABF_ROOT}/VERSION" 2>/dev/null || echo "unknown")",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%S%z")",
  "overall": "${ABF_DIAG_OVERALL}",
  "checks": [
EOF

    for entry in "${ABF_DIAG_RESULTS[@]}"; do
        $first || echo ","
        first=false
        local status="${entry%%|*}"
        local rest="${entry#*|}"
        local name="${rest%%|*}"
        local message="${rest#*|}"

        printf '    {"name":"%s","status":"%s","message":"%s"}' \
            "$name" "$status" "$message"
    done

    echo ""
    cat <<EOF
  ]
}
EOF
}

# ------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------

abf_doctor_run() {
    local json_mode="${1:-false}"

    ABF_DIAG_RESULTS=()
    ABF_DIAG_OVERALL="OK"

    local checks=(
        _abf_diag_check_version
        _abf_diag_check_config
        _abf_diag_check_restic
        _abf_diag_check_rclone
        _abf_diag_check_rsync
        _abf_diag_check_sqlite3
        _abf_diag_check_rclone_config
        _abf_diag_check_repository
        _abf_diag_check_storage_backend
        _abf_diag_check_smtp
        _abf_diag_check_smtp_connect
        _abf_diag_check_scheduler
        _abf_diag_check_lock_dir
        _abf_diag_check_backup_dirs
        _abf_diag_check_service_config
        _abf_diag_check_backup_age
    )

    for check in "${checks[@]}"; do
        "$check" 2>/dev/null || true
    done

    _abf_diag_overall

    if [[ "$json_mode" == "true" ]]; then
        _abf_diag_output_json
    else
        _abf_diag_output_human
    fi

    case "$ABF_DIAG_OVERALL" in
        OK)      return 0 ;;
        WARNING) return 1 ;;
        ERROR)   return 2 ;;
    esac
}
