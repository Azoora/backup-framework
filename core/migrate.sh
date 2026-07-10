# ---------------------------------------------------------------------------
# migrate.sh  --  Configuration migration engine
#
# Detects obsolete default values in config files and updates them to the
# current defaults.  Never overwrites user-customized values (a value is
# considered "customized" when it differs from the old default).
#
# Before any modification a timestamped backup is created under:
#   ${ABF_CONFIG_DIR}/backup/YYYYMMDD-HHMMSS/
# ---------------------------------------------------------------------------

# ------------------------------------------------------------------
# Migration rule definitions
#
# Format (whitespace-delimited, one rule per line):
#   REL_PATH  VAR_NAME  OLD_DEFAULT  NEW_DEFAULT
#
# REL_PATH   -- relative to ABF_CONFIG_DIR (e.g. abf.conf)
# VAR_NAME   -- config variable name (e.g. ABF_LOG_DIR)
# OLD_DEFAULT-- value shipped by previous framework version
# NEW_DEFAULT-- value shipped by current framework version
# ------------------------------------------------------------------

_abf_migration_rules() {
    cat <<'MIGRATIONS'
abf.conf              ABF_LOG_DIR               /var/log/abf              /tmp/abf/logs
abf.conf              ABF_CACHE_DIR             /var/cache/abf            /tmp/abf/cache
services/vaultwarden.conf SERVICE_VAULTWARDEN_BACKUP_DIR /var/backups/abf/vaultwarden /tmp/abf/vaultwarden
MIGRATIONS
}

# ------------------------------------------------------------------
# abf_config_migrate  --  Apply all pending migrations
#
# Returns 0 when all migrations succeeded (or none were needed).
# Returns 1 when any migration rule encountered an error.
# ------------------------------------------------------------------

abf_config_migrate() {
    local config_dir="${ABF_CONFIG_DIR:-/etc/abf}"
    local backup_base="${config_dir}/backup"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_dir="${backup_base}/${timestamp}"
    local -a applied
    local changed=0
    local errors=0

    if [[ ! -d "$config_dir" ]]; then
        echo "ERROR: Config directory not found: ${config_dir}" >&2
        return 1
    fi

    while IFS=' ' read -r rel_path var_name old_val new_val; do
        # Skip comments and blank lines
        [[ "$rel_path" =~ ^#.*$ || -z "$rel_path" ]] && continue

        local full_path="${config_dir}/${rel_path}"

        if [[ ! -f "$full_path" ]]; then
            continue
        fi

        # Check if an active (uncommented) line still carries the old default
        if grep -qE "^[[:space:]]*${var_name}=[\"']?${old_val}[\"']?" "$full_path" 2>/dev/null; then

            # Create backup on first change
            if [[ $changed -eq 0 && ! -d "$backup_dir" ]]; then
                local backup_tmp
                backup_tmp=$(mktemp -d -t "abf-migrate-XXXXXX") || {
                    echo "ERROR: Cannot create temporary directory for backup" >&2
                    return 1
                }
                cp -r "${config_dir}/." "${backup_tmp}/" 2>/dev/null || {
                    rm -rf "$backup_tmp"
                    echo "ERROR: Failed to copy config to backup" >&2
                    return 1
                }
                mkdir -p "$backup_base" 2>/dev/null || {
                    rm -rf "$backup_tmp"
                    echo "ERROR: Cannot create backup directory: ${backup_base}" >&2
                    return 1
                }
                mv "$backup_tmp" "$backup_dir" 2>/dev/null || {
                    rm -rf "$backup_tmp"
                    echo "ERROR: Failed to finalize backup at ${backup_dir}" >&2
                    return 1
                }
                echo "Backup created: ${backup_dir}"
            fi

            # Escape old/new values for sed (| delimiter)
            local old_escaped new_escaped
            old_escaped=$(sed 's/[|&\]/\\&/g' <<< "$old_val")
            new_escaped=$(sed 's/[|&\]/\\&/g' <<< "$new_val")

            # Replace old default with new default, keeping the line active
            if sed -i "s|^\([[:space:]]*${var_name}=\)[\"']*${old_escaped}[\"']*|\1\"${new_escaped}\"|" "$full_path"; then
                applied+=("  ${rel_path}  ${var_name}  \"${old_val}\" -> \"${new_val}\"")
                changed=$((changed + 1))
            else
                echo "ERROR: Failed to apply migration for ${var_name} in ${full_path}" >&2
                errors=$((errors + 1))
            fi
        fi
    done < <(_abf_migration_rules)

    # Summary
    if [[ $changed -gt 0 ]]; then
        echo "Migrated ${changed} value(s):"
        printf "%s\n" "${applied[@]}"
    else
        echo "No migrations needed."
    fi

    return $(( errors > 0 ? 1 : 0 ))
}
