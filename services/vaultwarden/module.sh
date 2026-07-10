# ---------------------------------------------------------------------------
# Vaultwarden service module
#
# Standard lifecycle hooks called by the core engine.
# All service-specific logic (SQLite backup, file copying)
# lives here -- the core engine never knows how Vaultwarden works.
#
# In Milestone 2 the backup hook populates a staging directory.
# Archiving and encryption are handled by the engine via restic.
# ---------------------------------------------------------------------------

ABF_VW_TEMP_DIR="${ABF_VW_TEMP_DIR:-}"

# ------------------------------------------------------------------
# Backup lifecycle
# ------------------------------------------------------------------

service_pre_backup() {
    if [[ ! -d "${SERVICE_VAULTWARDEN_DATA_DIR}" ]]; then
        abf_log_error "Vaultwarden data directory not found: ${SERVICE_VAULTWARDEN_DATA_DIR}"
        return 1
    fi

    mkdir -p "${SERVICE_VAULTWARDEN_BACKUP_DIR:-}" 2>/dev/null || true

    ABF_VW_TEMP_DIR=$(mktemp -d -t "abf-vw-backup-XXXXXX")
    abf_log_info "Created staging directory: ${ABF_VW_TEMP_DIR}"
    return 0
}

service_backup() {
    _vw_backup_database     || abf_log_warning "Database backup had issues"
    _vw_backup_attachments  || abf_log_warning "Attachments backup had issues"
    _vw_backup_icon_cache   || abf_log_warning "Icon cache backup had issues"
    _vw_backup_rsa_keys     || abf_log_warning "RSA keys backup had issues"
    _vw_backup_config       || abf_log_warning "Config backup had issues"

    local file_count
    file_count=$(find "$ABF_VW_TEMP_DIR" -type f 2>/dev/null | wc -l)
    abf_log_success "${file_count} file(s) staged for backup in ${ABF_VW_TEMP_DIR}"
    return 0
}

service_verify_backup() {
    if [[ ! -d "${ABF_VW_TEMP_DIR:-}" ]]; then
        abf_log_error "Staging directory missing"
        return 1
    fi

    local file_count
    file_count=$(find "$ABF_VW_TEMP_DIR" -type f 2>/dev/null | wc -l)
    if [[ "$file_count" -eq 0 ]]; then
        abf_log_warning "Staging directory is empty -- nothing to back up"
        return 1
    fi

    abf_log_success "Staging directory verified -- ${file_count} file(s)"
    return 0
}

service_post_backup() {
    if [[ -n "${ABF_VW_TEMP_DIR:-}" ]] && [[ -d "$ABF_VW_TEMP_DIR" ]]; then
        rm -rf "$ABF_VW_TEMP_DIR"
        abf_log_info "Cleaned up staging directory"
    fi
}

# ------------------------------------------------------------------
# Restore lifecycle
# ------------------------------------------------------------------

service_pre_restore() {
    local snapshot="$1"

    if [[ ! -d "${SERVICE_VAULTWARDEN_DATA_DIR}" ]]; then
        abf_log_error "Vaultwarden data directory does not exist: ${SERVICE_VAULTWARDEN_DATA_DIR}"
        return 1
    fi

    local staging="${ABF_RESTORE_STAGING:-}"
    if [[ -n "$staging" ]] && [[ -d "$staging" ]]; then
        abf_log_info "Restore staging directory: ${staging}"
        return 0
    fi

    if [[ -f "$snapshot" ]]; then
        ABF_VW_TEMP_DIR=$(mktemp -d -t "abf-vw-restore-XXXXXX")
        abf_log_info "Extracting archive to: ${ABF_VW_TEMP_DIR}"
        tar -xzf "$snapshot" -C "$ABF_VW_TEMP_DIR"
        ABF_RESTORE_STAGING="$ABF_VW_TEMP_DIR"
    fi

    return 0
}

service_restore() {
    local snapshot="$1"
    local dry_run="$2"
    local staging="${ABF_RESTORE_STAGING:-}"
    local data_dir="${SERVICE_VAULTWARDEN_DATA_DIR}"

    if [[ -z "$staging" ]] || [[ ! -d "$staging" ]]; then
        abf_log_error "Restore staging directory not available"
        return 1
    fi

    local extracted
    extracted=$(find "$staging" -mindepth 1 2>/dev/null | wc -l)
    abf_log_info "Restore staging contains ${extracted} item(s)"

    if [[ "$dry_run" == "true" ]]; then
        abf_log_info "Dry-run mode -- no files will be modified"
        abf_log_info "Would restore: $(ls "$staging" 2>/dev/null | tr '\n' ' ')"
        return 0
    fi

    abf_log_info "Restoring files to ${data_dir}..."
    _vw_restore_all "$staging" "$data_dir"
    return 0
}

service_verify_restore() {
    if [[ ! -d "${SERVICE_VAULTWARDEN_DATA_DIR}" ]]; then
        abf_log_error "Verification failed: data directory missing after restore"
        return 1
    fi

    local file_count
    file_count=$(find "${SERVICE_VAULTWARDEN_DATA_DIR}" -type f 2>/dev/null | wc -l)
    abf_log_success "Verification passed: ${file_count} file(s) in data directory"
    return 0
}

service_post_restore() {
    if [[ -n "${ABF_VW_TEMP_DIR:-}" ]] && [[ -d "$ABF_VW_TEMP_DIR" ]]; then
        rm -rf "$ABF_VW_TEMP_DIR"
        ABF_VW_TEMP_DIR=""
        abf_log_info "Cleaned up working directory"
    fi
}

# ------------------------------------------------------------------
# Optional hooks
# ------------------------------------------------------------------

service_healthcheck() {
    local context="${1:-}"

    if [[ ! -d "${SERVICE_VAULTWARDEN_DATA_DIR:-}" ]]; then
        abf_log_warning "Healthcheck: data directory not found (context: ${context})"
        return 1
    fi

    if [[ ! -f "${SERVICE_VAULTWARDEN_DATA_DIR}/db.sqlite3" ]]; then
        abf_log_warning "Healthcheck: database file not found (context: ${context})"
        return 1
    fi

    abf_log_info "Healthcheck passed (context: ${context})"
    return 0
}

service_cleanup() {
    local context="${1:-}"
    if [[ -n "${ABF_VW_TEMP_DIR:-}" ]] && [[ -d "$ABF_VW_TEMP_DIR" ]]; then
        rm -rf "$ABF_VW_TEMP_DIR"
        ABF_VW_TEMP_DIR=""
        abf_log_info "Cleanup removed stale staging dir (context: ${context})"
    fi
}

# ------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------

_vw_backup_database() {
    local enabled
    enabled="${SERVICE_VAULTWARDEN_BACKUP_DATABASE:-true}"
    [[ "$enabled" == "true" ]] || { abf_log_info "Skipping database (disabled)"; return 0; }

    local src="${SERVICE_VAULTWARDEN_DATA_DIR}/db.sqlite3"
    if [[ ! -f "$src" ]]; then
        abf_log_warning "Database file not found: ${src}"
        return 0
    fi

    abf_log_info "Backing up SQLite database"
    if command -v sqlite3 &>/dev/null; then
        sqlite3 "$src" ".backup ${ABF_VW_TEMP_DIR}/db.sqlite3"
    else
        cp "$src" "${ABF_VW_TEMP_DIR}/db.sqlite3"
        abf_log_warning "sqlite3 not found -- copied database without consistency guarantee"
    fi
    abf_log_success "Database backup completed"
}

_vw_backup_attachments() {
    local enabled
    enabled="${SERVICE_VAULTWARDEN_BACKUP_ATTACHMENTS:-true}"
    [[ "$enabled" == "true" ]] || { abf_log_info "Skipping attachments (disabled)"; return 0; }

    local src="${SERVICE_VAULTWARDEN_DATA_DIR}/attachments"
    if [[ ! -d "$src" ]]; then
        abf_log_info "Attachments directory not found -- skipping"
        return 0
    fi

    abf_log_info "Backing up attachments"
    cp -r "$src" "${ABF_VW_TEMP_DIR}/attachments"
    abf_log_success "Attachments backup completed"
}

_vw_backup_icon_cache() {
    local enabled
    enabled="${SERVICE_VAULTWARDEN_BACKUP_ICON_CACHE:-true}"
    [[ "$enabled" == "true" ]] || { abf_log_info "Skipping icon cache (disabled)"; return 0; }

    local src="${SERVICE_VAULTWARDEN_DATA_DIR}/icon_cache"
    if [[ ! -d "$src" ]]; then
        abf_log_info "Icon cache directory not found -- skipping"
        return 0
    fi

    abf_log_info "Backing up icon cache"
    cp -r "$src" "${ABF_VW_TEMP_DIR}/icon_cache"
    abf_log_success "Icon cache backup completed"
}

_vw_backup_rsa_keys() {
    local enabled
    enabled="${SERVICE_VAULTWARDEN_BACKUP_RSA_KEYS:-true}"
    [[ "$enabled" == "true" ]] || { abf_log_info "Skipping RSA keys (disabled)"; return 0; }

    local found=false
    local dst="${ABF_VW_TEMP_DIR}/rsa_keys"
    mkdir -p "$dst"

    for pattern in "rsa_key*" "rsa_key.pub" "rsa_key.der"; do
        for path in "${SERVICE_VAULTWARDEN_DATA_DIR}"/$pattern; do
            if [[ -f "$path" ]]; then
                cp "$path" "$dst/"
                found=true
            fi
        done
    done

    if $found; then
        abf_log_success "RSA keys backup completed"
    else
        abf_log_info "No RSA key files found -- skipping"
        rm -rf "$dst"
    fi
}

_vw_backup_config() {
    local enabled
    enabled="${SERVICE_VAULTWARDEN_BACKUP_CONFIG:-true}"
    [[ "$enabled" == "true" ]] || { abf_log_info "Skipping config (disabled)"; return 0; }

    local src="${SERVICE_VAULTWARDEN_DATA_DIR}/config.json"
    if [[ ! -f "$src" ]]; then
        abf_log_info "config.json not found -- skipping"
        return 0
    fi

    cp "$src" "${ABF_VW_TEMP_DIR}/config.json"
    abf_log_success "Config backup completed"
}

_vw_restore_all() {
    local staging="$1"
    local data_dir="$2"

    _vw_restore_item "$staging" "db.sqlite3"  "$data_dir" "database"
    _vw_restore_item "$staging" "config.json" "$data_dir" "config"
    _vw_restore_dir  "$staging" "attachments" "$data_dir"
    _vw_restore_dir  "$staging" "icon_cache"  "$data_dir"

    local rsa_src="${staging}/rsa_keys"
    if [[ -d "$rsa_src" ]]; then
        abf_log_info "  Restoring RSA keys..."
        for key_file in "$rsa_src"/*; do
            if [[ -f "$key_file" ]]; then
                cp "$key_file" "$data_dir/"
            fi
        done
        abf_log_success "  Restored: RSA keys"
    fi
}

_vw_restore_item() {
    local staging="$1"
    local name="$2"
    local data_dir="$3"
    local label="$4"
    local src="${staging}/${name}"

    if [[ ! -f "$src" ]]; then
        abf_log_info "  ${label} not in archive -- skipping"
        return
    fi

    abf_log_info "  Restoring ${label}..."
    cp "$src" "${data_dir}/${name}"
    abf_log_success "  Restored: ${name}"
}

_vw_restore_dir() {
    local staging="$1"
    local name="$2"
    local data_dir="$3"
    local src="${staging}/${name}"
    local dst="${data_dir}/${name}"

    if [[ ! -d "$src" ]]; then
        abf_log_info "  ${name} not in archive -- skipping"
        return
    fi

    if [[ -d "$dst" ]]; then
        abf_log_info "  Merging ${name}..."
        rm -rf "$dst"
    else
        abf_log_info "  Restoring ${name}..."
    fi
    cp -r "$src" "$dst"
    abf_log_success "  Restored: ${name}/"
}
