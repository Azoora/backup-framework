# ---------------------------------------------------------------------------
# config.sh  --  Configuration loader
#
# Loads KEY=VALUE configuration files by sourcing them.
# Config is loaded in this order (later files override earlier ones):
#   1. config/abf.conf              -- Framework defaults
#   2. config/storage.conf          -- Storage defaults
#   3. services/<name>/service.conf -- Service module defaults
#   4. config/services/<name>.conf  -- User overrides
#
# No hardcoded paths.  All variables are prefixed for safety.
# ---------------------------------------------------------------------------

ABF_CONFIG_DIR=""
ABF_SERVICE_NAME=""

# ------------------------------------------------------------------
# Framework-level config loading
# ------------------------------------------------------------------

abf_load_config() {
    local config_dir="${1:-}"

    if [[ -z "$config_dir" ]]; then
        config_dir=$(_abf_discover_config_dir)
    fi

    if [[ ! -d "$config_dir" ]]; then
        echo "ERROR: Config directory not found: ${config_dir}" >&2
        return 1
    fi

    ABF_CONFIG_DIR="$config_dir"

    _abf_source_if_exists "${config_dir}/abf.conf"
    _abf_source_if_exists "${config_dir}/storage.conf"
    _abf_source_if_exists "${config_dir}/smtp.conf"

    return 0
}

_abf_discover_config_dir() {
    for dir in "/etc/abf" "${HOME}/.config/abf" "${ABF_ROOT}/config"; do
        if [[ -d "$dir" ]]; then
            echo "$dir"
            return 0
        fi
    done
    echo "${ABF_ROOT}/config"
}

# ------------------------------------------------------------------
# Service-level config loading
# ------------------------------------------------------------------

abf_load_service_config() {
    local service_name="$1"
    ABF_SERVICE_NAME="$service_name"

    _abf_source_if_exists "${ABF_ROOT}/services/${service_name}/service.conf"
    _abf_source_if_exists "${ABF_CONFIG_DIR}/services/${service_name}.conf"
}

# ------------------------------------------------------------------
# Storage-level config loading
# ------------------------------------------------------------------

abf_load_storage_config() {
    local storage_name="$1"
    _abf_source_if_exists "${ABF_ROOT}/storage/${storage_name}/storage.conf"
    _abf_source_if_exists "${ABF_CONFIG_DIR}/storage/${storage_name}.conf"
}

abf_load_destination_config() {
    local destination_name="$1"
    _abf_source_if_exists "${ABF_ROOT}/destinations/${destination_name}/destination.conf"
    _abf_source_if_exists "${ABF_CONFIG_DIR}/destinations/${destination_name}.conf"
}

# ------------------------------------------------------------------
# Utility
# ------------------------------------------------------------------

_abf_source_if_exists() {
    local path="$1"
    if [[ -f "$path" ]]; then
        # shellcheck source=/dev/null
        source "$path"
    fi
}
