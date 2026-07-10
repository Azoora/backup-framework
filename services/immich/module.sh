# ---------------------------------------------------------------------------
# Immich service module
#
# Standard lifecycle hooks called by the core engine.
# All service-specific logic (PostgreSQL backup, file copying)
# lives here -- the core engine never knows how Immich works.
#
# Immich data layout:
#   UPLOAD_LOCATION/  -- original photos and videos
#   thumbnails/       -- generated thumbnail images
#   encoding/         -- video encoding profiles
#   database          -- PostgreSQL (backed up via pg_dump)
#   .env              -- configuration variables
# ---------------------------------------------------------------------------

ABF_SERVICE_STAGING_DIR="${ABF_SERVICE_STAGING_DIR:-}"

# ------------------------------------------------------------------
# Backup lifecycle
# ------------------------------------------------------------------

service_pre_backup() {
    if [[ ! -d "${SERVICE_IMMICH_DATA_DIR}" ]]; then
        abf_log_error "Immich data directory not found: ${SERVICE_IMMICH_DATA_DIR}"
        return 1
    fi

    mkdir -p "${SERVICE_IMMICH_BACKUP_DIR:-}" 2>/dev/null || true

    ABF_SERVICE_STAGING_DIR=$(mktemp -d -t "abf-immich-backup-XXXXXX")
    abf_log_info "Created staging directory: ${ABF_SERVICE_STAGING_DIR}"
    return 0
}

service_backup() {
    _im_backup_database     || abf_log_warning "Database backup had issues"
    _im_backup_uploads      || abf_log_warning "Uploads backup had issues"
    _im_backup_thumbnails   || abf_log_warning "Thumbnails backup had issues"
    _im_backup_encoding     || abf_log_warning "Encoding profiles backup had issues"
    _im_backup_config       || abf_log_warning "Config backup had issues"

    local file_count
    file_count=$(find "$ABF_SERVICE_STAGING_DIR" -type f 2>/dev/null | wc -l)
    abf_log_success "${file_count} file(s) staged for backup in ${ABF_SERVICE_STAGING_DIR}"
    return 0
}

service_verify_backup() {
    if [[ ! -d "${ABF_SERVICE_STAGING_DIR:-}" ]]; then
        abf_log_error "Staging directory missing"
        return 1
    fi

    local file_count
    file_count=$(find "$ABF_SERVICE_STAGING_DIR" -type f 2>/dev/null | wc -l)
    if [[ "$file_count" -eq 0 ]]; then
        abf_log_warning "Staging directory is empty -- nothing to back up"
        return 1
    fi

    abf_log_success "Staging directory verified -- ${file_count} file(s)"
    return 0
}

service_post_backup() {
    if [[ -n "${ABF_SERVICE_STAGING_DIR:-}" ]] && [[ -d "$ABF_SERVICE_STAGING_DIR" ]]; then
        rm -rf "$ABF_SERVICE_STAGING_DIR"
        abf_log_info "Cleaned up staging directory"
    fi
}

# ------------------------------------------------------------------
# Restore lifecycle
# ------------------------------------------------------------------

service_pre_restore() {
    local snapshot="$1"
    local target="${ABF_RESTORE_TARGET:-}"

    local data_dir="${target:-${SERVICE_IMMICH_DATA_DIR}}"

    if [[ ! -d "$data_dir" ]]; then
        abf_log_info "Creating target directory: ${data_dir}"
        mkdir -p "$data_dir" || {
            abf_log_error "Cannot create target directory: ${data_dir}"
            return 1
        }
    fi

    if [[ ! -w "$data_dir" ]]; then
        abf_log_error "Target directory not writable: ${data_dir}"
        return 1
    fi

    if [[ -n "$target" ]]; then
        abf_log_info "Restore target: ${target}"
    fi

    local staging="${ABF_RESTORE_STAGING:-}"
    if [[ -n "$staging" ]] && [[ -d "$staging" ]]; then
        abf_log_info "Restore staging directory: ${staging}"
        return 0
    fi

    if [[ -f "$snapshot" ]]; then
        ABF_SERVICE_STAGING_DIR=$(mktemp -d -t "abf-immich-restore-XXXXXX")
        abf_log_info "Extracting archive to: ${ABF_SERVICE_STAGING_DIR}"
        tar -xzf "$snapshot" -C "$ABF_SERVICE_STAGING_DIR"
        ABF_RESTORE_STAGING="$ABF_SERVICE_STAGING_DIR"
    fi

    return 0
}

service_restore() {
    local snapshot="$1"
    local dry_run="$2"
    local staging="${ABF_RESTORE_STAGING:-}"
    local data_dir="${ABF_RESTORE_TARGET:-${SERVICE_IMMICH_DATA_DIR}}"

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
    _im_restore_all "$staging" "$data_dir"
    return 0
}

service_resolve_components() {
    local raw="$1"
    if [[ -z "$raw" ]]; then
        echo "database,uploads,thumbnails,encoding,config"
        return
    fi
    local result=()
    IFS=',' read -ra parts <<< "$raw"
    for part in "${parts[@]}"; do
        case "$part" in
            db|database)    result+=("database") ;;
            uploads)        result+=("uploads") ;;
            thumbnails)     result+=("thumbnails") ;;
            encoding)       result+=("encoding") ;;
            config)         result+=("config") ;;
            *)              result+=("$part") ;;
        esac
    done
    local IFS=','
    echo "${result[*]}"
}

service_verify_restore() {
    local data_dir="${ABF_RESTORE_TARGET:-${SERVICE_IMMICH_DATA_DIR}}"

    if [[ ! -d "$data_dir" ]]; then
        abf_log_error "Verification failed: data directory missing after restore"
        return 1
    fi

    local file_count
    file_count=$(find "$data_dir" -type f 2>/dev/null | wc -l)
    abf_log_success "Verification passed: ${file_count} file(s) in data directory"
    return 0
}

service_post_restore() {
    if [[ -n "${ABF_SERVICE_STAGING_DIR:-}" ]] && [[ -d "$ABF_SERVICE_STAGING_DIR" ]]; then
        rm -rf "$ABF_SERVICE_STAGING_DIR"
        ABF_SERVICE_STAGING_DIR=""
        abf_log_info "Cleaned up working directory"
    fi
}

# ------------------------------------------------------------------
# Optional hooks
# ------------------------------------------------------------------

service_healthcheck() {
    local context="${1:-}"
    local data_dir="${ABF_RESTORE_TARGET:-${SERVICE_IMMICH_DATA_DIR:-}}"

    if [[ ! -d "$data_dir" ]]; then
        abf_log_warning "Healthcheck: data directory not found (context: ${context})"
        return 1
    fi

    abf_log_info "Healthcheck passed (context: ${context})"
    return 0
}

service_cleanup() {
    local context="${1:-}"
    if [[ -n "${ABF_SERVICE_STAGING_DIR:-}" ]] && [[ -d "$ABF_SERVICE_STAGING_DIR" ]]; then
        rm -rf "$ABF_SERVICE_STAGING_DIR"
        ABF_SERVICE_STAGING_DIR=""
        abf_log_info "Cleanup removed stale staging dir (context: ${context})"
    fi
}

# ------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------

_im_backup_database() {
    local enabled
    enabled="${SERVICE_IMMICH_BACKUP_DATABASE:-true}"
    [[ "$enabled" == "true" ]] || { abf_log_info "Skipping database (disabled)"; return 0; }

    if command -v pg_dump &>/dev/null && [[ -n "${IMMICH_DB_HOST:-}" ]]; then
        abf_log_info "Backing up PostgreSQL database"
        PGPASSWORD="${IMMICH_DB_PASSWORD:-}" pg_dump -h "$IMMICH_DB_HOST" \
            -p "${IMMICH_DB_PORT:-5432}" \
            -U "${IMMICH_DB_USER:-postgres}" \
            -d "${IMMICH_DB_NAME:-immich}" \
            -F c \
            -f "${ABF_SERVICE_STAGING_DIR}/database.dump" || {
            abf_log_warning "pg_dump failed — database backup incomplete"
            rm -f "${ABF_SERVICE_STAGING_DIR}/database.dump"
            return 0
        }
        abf_log_success "Database backup completed (pg_dump)"
    else
        abf_log_warning "pg_dump not available or IMMICH_DB_HOST not set — skipping database backup"
        abf_log_warning "Set IMMICH_DB_HOST in config to enable PostgreSQL backup"
    fi
    return 0
}

_im_backup_uploads() {
    local enabled
    enabled="${SERVICE_IMMICH_BACKUP_UPLOADS:-true}"
    [[ "$enabled" == "true" ]] || { abf_log_info "Skipping uploads (disabled)"; return 0; }

    local src="${SERVICE_IMMICH_DATA_DIR}/uploads"
    if [[ ! -d "$src" ]]; then
        abf_log_info "Uploads directory not found -- skipping"
        return 0
    fi

    abf_log_info "Backing up uploads"
    cp -r "$src" "${ABF_SERVICE_STAGING_DIR}/uploads"
    abf_log_success "Uploads backup completed"
}

_im_backup_thumbnails() {
    local enabled
    enabled="${SERVICE_IMMICH_BACKUP_THUMBNAILS:-true}"
    [[ "$enabled" == "true" ]] || { abf_log_info "Skipping thumbnails (disabled)"; return 0; }

    local src="${SERVICE_IMMICH_DATA_DIR}/thumbnails"
    if [[ ! -d "$src" ]]; then
        abf_log_info "Thumbnails directory not found -- skipping"
        return 0
    fi

    abf_log_info "Backing up thumbnails"
    cp -r "$src" "${ABF_SERVICE_STAGING_DIR}/thumbnails"
    abf_log_success "Thumbnails backup completed"
}

_im_backup_encoding() {
    local enabled
    enabled="${SERVICE_IMMICH_BACKUP_ENCODING:-true}"
    [[ "$enabled" == "true" ]] || { abf_log_info "Skipping encoding profiles (disabled)"; return 0; }

    local src="${SERVICE_IMMICH_DATA_DIR}/encoding"
    if [[ ! -d "$src" ]]; then
        abf_log_info "Encoding profiles directory not found -- skipping"
        return 0
    fi

    abf_log_info "Backing up encoding profiles"
    cp -r "$src" "${ABF_SERVICE_STAGING_DIR}/encoding"
    abf_log_success "Encoding profiles backup completed"
}

_im_backup_config() {
    local enabled
    enabled="${SERVICE_IMMICH_BACKUP_CONFIG:-true}"
    [[ "$enabled" == "true" ]] || { abf_log_info "Skipping config (disabled)"; return 0; }

    local src="${SERVICE_IMMICH_DATA_DIR}/.env"
    if [[ ! -f "$src" ]]; then
        abf_log_info ".env not found in data directory -- skipping"
        return 0
    fi

    cp "$src" "${ABF_SERVICE_STAGING_DIR}/config"
    abf_log_success "Config backup completed"
}

_im_component_enabled() {
    local name="$1"
    local components="${ABF_RESTORE_COMPONENTS:-}"
    [[ -z "$components" ]] && return 0
    [[ ",${components}," == *",${name},"* ]] && return 0
    return 1
}

_im_restore_all() {
    local staging="$1"
    local data_dir="$2"

    if _im_component_enabled "database"; then
        _im_restore_item "$staging" "database.dump" "$data_dir" "database" || true
    fi
    if _im_component_enabled "uploads"; then
        _im_restore_dir "$staging" "uploads" "$data_dir" || true
    fi
    if _im_component_enabled "thumbnails"; then
        _im_restore_dir "$staging" "thumbnails" "$data_dir" || true
    fi
    if _im_component_enabled "encoding"; then
        _im_restore_dir "$staging" "encoding" "$data_dir" || true
    fi
    if _im_component_enabled "config"; then
        _im_restore_item "$staging" "config" "$data_dir" "config" || true
    fi
    return 0
}

_im_restore_item() {
    local staging="$1"
    local name="$2"
    local data_dir="$3"
    local label="$4"
    local src="${staging}/${name}"
    local dst="${data_dir}/${name}"

    if [[ ! -f "$src" ]]; then
        abf_log_info "  ${label} not in archive -- skipping"
        return
    fi

    if ! command -v rsync &>/dev/null; then
        abf_log_error "rsync is required for restore operations. Install rsync and try again."
        return 1
    fi

    abf_log_info "  Restoring ${label}..."
    mkdir -p "$(dirname "$dst")"
    rsync -a "$src" "$dst"
    abf_log_success "  Restored: ${name}"
}

_im_restore_dir() {
    local staging="$1"
    local name="$2"
    local data_dir="$3"
    local src="${staging}/${name}"
    local dst="${data_dir}/${name}"

    if [[ ! -d "$src" ]]; then
        abf_log_info "  ${name} not in archive -- skipping"
        return
    fi

    if ! command -v rsync &>/dev/null; then
        abf_log_error "rsync is required for restore operations. Install rsync and try again."
        return 1
    fi

    mkdir -p "$(dirname "$dst")"

    if [[ "${ABF_RESTORE_REPLACE_ALL:-false}" == "true" ]]; then
        abf_log_info "  Restoring ${name} (replace-all)..."
        rsync -a --delete "$src/" "$dst/"
    else
        if [[ -d "$dst" ]]; then
            abf_log_info "  Merging ${name}..."
        else
            abf_log_info "  Restoring ${name}..."
        fi
        rsync -a "$src/" "$dst/"
    fi
    abf_log_success "  Restored: ${name}/"
}
