#!/usr/bin/env bash
#
# install.sh  --  Backup Framework installer
#
# Deploys the framework to /opt/abf/ and creates a lightweight
# wrapper at /usr/local/bin/abf.
set -Eeuo pipefail

ABF_SRC="$(cd "$(dirname "$0")/.." && pwd)"
ABF_DST="/opt/abf"
BIN_DST="/usr/local/bin"
CONFIG_DST="/etc/abf"

# ------------------------------------------------------------------
# Dependency definitions
# ------------------------------------------------------------------

ABF_DEPS=(
    "restic:restic:Restic (encrypted backups):required"
    "rclone:rclone:Rclone (remote storage backends):recommended"
    "rsync:rsync:rsync (file transfer for restore operations):required"
    "sqlite3:sqlite3:sqlite3 (consistent SQLite database snapshots):recommended"
)

_abf_dep_name()    { echo "${1%%:*}"; }
_abf_dep_cmd()     { local x="${1#*:}"; echo "${x%%:*}"; }
_abf_dep_desc()    { local x="${1#*:}"; x="${x#*:}"; echo "${x%%:*}"; }
_abf_dep_required(){ echo "${1##*:}"; }

_abf_check_deps() {
    local missing_req=0
    local missing_rec=0
    local missing_names=""
    local installable=""

    echo ""
    echo "==> Checking dependencies..."

    for dep in "${ABF_DEPS[@]}"; do
        local name; name=$(_abf_dep_name "$dep")
        local cmd;  cmd=$(_abf_dep_cmd "$dep")
        local desc; desc=$(_abf_dep_desc "$dep")
        local required; required=$(_abf_dep_required "$dep")

        if command -v "$cmd" &>/dev/null; then
            local ver
            ver=$("$cmd" --version 2>/dev/null | head -1 || echo "installed")
            echo "    [FOUND] ${name} — ${ver}"
        else
            if [[ "$required" == "required" ]]; then
                echo "    [MISS]  ${name} — ${desc} (REQUIRED)"
                missing_req=$((missing_req + 1))
                missing_names="${missing_names} ${name}"
                installable="${installable} ${cmd}"
            else
                echo "    [MISS]  ${name} — ${desc} (recommended)"
                missing_rec=$((missing_rec + 1))
                missing_names="${missing_names} ${name}"
                installable="${installable} ${cmd}"
            fi
        fi
    done

    if [[ "$missing_req" -gt 0 ]]; then
        echo ""
        echo "    ERROR: ${missing_req} required dependenc(ies) missing."
        echo "    Install missing packages and re-run this installer."
    fi

    if [[ "$missing_rec" -gt 0 ]] && [[ "$missing_req" -eq 0 ]]; then
        # Offer auto-install on Debian/Ubuntu
        if [[ -f /etc/os-release ]]; then
            # shellcheck disable=SC1091
            source /etc/os-release
            if [[ "${ID:-}" == "debian" || "${ID:-}" == "ubuntu" || "${ID:-}" == "neon" || "${ID:-}" == "pop" || "${ID:-}" == "linuxmint" || "${ID:-}" == "elementary" ]]; then
                _abf_install_deps_debian "$installable"
            fi
        fi
    fi

    return "$missing_req"
}

_abf_install_deps_debian() {
    local packages="$1"
    local apt_packages=""

    for pkg in $packages; do
        case "$pkg" in
            restic) apt_packages="$apt_packages restic" ;;
            rclone) apt_packages="$apt_packages rclone" ;;
            rsync)  apt_packages="$apt_packages rsync" ;;
            sqlite3) apt_packages="$apt_packages sqlite3" ;;
        esac
    done

    if [[ -z "$apt_packages" ]]; then
        return 0
    fi

    echo ""
    echo "==> Detected Debian/Ubuntu-based system."
    echo "    The following recommended packages can be installed automatically:"
    echo "    ${apt_packages}"
    echo ""
    echo -n "    Install now? [Y/n] "
    local answer
    read -r answer
    if [[ -z "$answer" || "$answer" =~ ^[Yy] ]]; then
        echo "    Installing: ${apt_packages}"
        if sudo apt-get update -qq && sudo apt-get install -y -qq $apt_packages; then
            echo "    Installation complete."
        else
            echo "    WARNING: Package installation failed."
            echo "    Install manually: sudo apt-get install${apt_packages}"
        fi
    else
        echo "    Skipped. Install manually: sudo apt-get install${apt_packages}"
    fi
}

echo "==> Installing Backup Framework"

# ------------------------------------------------------------------
# 0. Check dependencies
# ------------------------------------------------------------------
_abf_check_deps || exit 1

# ------------------------------------------------------------------
# 1. Create directories
# ------------------------------------------------------------------
echo "==> Setting up directories..."
install -d -m 0755 "${ABF_DST}"
install -d -m 0755 "${ABF_DST}/cache"
install -d -m 0755 "${ABF_DST}/logs"
install -d -m 0755 "${ABF_DST}/temp"
install -d -m 0755 "${CONFIG_DST}/services"
install -d -m 0755 "${CONFIG_DST}/destinations"
install -d -m 0755 /var/log/abf
install -d -m 0755 /var/cache/abf

# ------------------------------------------------------------------
# 2. Copy framework (preserve relative paths)
# ------------------------------------------------------------------
echo "==> Installing framework to ${ABF_DST}..."

# Remove stale framework files before copy to prevent nested directory
# duplication (cp -r src/ dst/ creates dst/src/ when dst/ already exists)
rm -rf "${ABF_DST}/abf" \
       "${ABF_DST}/core" \
       "${ABF_DST}/services" \
       "${ABF_DST}/storage" \
       "${ABF_DST}/destinations" \
       "${ABF_DST}/scripts" \
       "${ABF_DST}/docs" \
       "${ABF_DST}/examples" \
       "${ABF_DST}/tests" \
       "${ABF_DST}/VERSION" \
       "${ABF_DST}/CHANGELOG.md" \
       "${ABF_DST}/CONTRIBUTING.md" \
       "${ABF_DST}/LICENSE" \
       "${ABF_DST}/README.md" \
       "${ABF_DST}/RELEASE_NOTES.md" \
       "${ABF_DST}/SECURITY.md"

cp -r "${ABF_SRC}/abf"           "${ABF_DST}/abf"
cp -r "${ABF_SRC}/VERSION"       "${ABF_DST}/VERSION"
cp -r "${ABF_SRC}/core"          "${ABF_DST}/core"
cp -r "${ABF_SRC}/services"      "${ABF_DST}/services"
cp -r "${ABF_SRC}/storage"       "${ABF_DST}/storage"
cp -r "${ABF_SRC}/destinations"  "${ABF_DST}/destinations"
cp -r "${ABF_SRC}/scripts"       "${ABF_DST}/scripts"
cp -r "${ABF_SRC}/docs"          "${ABF_DST}/docs"
cp -r "${ABF_SRC}/examples"      "${ABF_DST}/examples"
cp -r "${ABF_SRC}/tests"         "${ABF_DST}/tests"
cp -r "${ABF_SRC}/CHANGELOG.md"  "${ABF_DST}/CHANGELOG.md"
cp -r "${ABF_SRC}/CONTRIBUTING.md" "${ABF_DST}/CONTRIBUTING.md"
cp -r "${ABF_SRC}/LICENSE"       "${ABF_DST}/LICENSE"
cp -r "${ABF_SRC}/README.md"     "${ABF_DST}/README.md"
cp -r "${ABF_SRC}/RELEASE_NOTES.md" "${ABF_DST}/RELEASE_NOTES.md"
cp -r "${ABF_SRC}/SECURITY.md"   "${ABF_DST}/SECURITY.md"
chmod 0755 "${ABF_DST}/abf"

# ------------------------------------------------------------------
# 3. Create lightweight wrapper at /usr/local/bin/abf
# ------------------------------------------------------------------
echo "==> Installing abf wrapper..."
if [[ -d "$BIN_DST" ]]; then
    cat > "${BIN_DST}/abf" <<'WRAPPER'
#!/usr/bin/env bash
exec /opt/abf/abf "$@"
WRAPPER
    chmod 0755 "${BIN_DST}/abf"
    echo "    Created ${BIN_DST}/abf -> /opt/abf/abf"
else
    echo "    WARNING: ${BIN_DST} not found -- create symlink manually:"
    echo "    ln -s /opt/abf/abf /usr/local/bin/abf"
fi

# ------------------------------------------------------------------
# 4. Copy default config files (do not overwrite existing)
# ------------------------------------------------------------------
copy_default() {
    local src="$1"
    local dst="$2"
    if [[ -f "$dst" ]]; then
        echo "    Skipping $dst (already exists)"
    else
        cp "$src" "$dst"
        echo "    Created $dst"
    fi
}

echo "==> Installing configuration..."
mkdir -p "${CONFIG_DST}/services"
mkdir -p "${CONFIG_DST}/destinations"
copy_default "${ABF_SRC}/config/abf.conf"           "${CONFIG_DST}/abf.conf"
copy_default "${ABF_SRC}/config/storage.conf"        "${CONFIG_DST}/storage.conf"
copy_default "${ABF_SRC}/config/smtp.conf"           "${CONFIG_DST}/smtp.conf"
copy_default "${ABF_SRC}/config/services/vaultwarden.conf" \
             "${CONFIG_DST}/services/vaultwarden.conf"
copy_default "${ABF_SRC}/config/services/immich.conf" \
             "${CONFIG_DST}/services/immich.conf"
copy_default "${ABF_SRC}/config/destinations/local.conf" \
             "${CONFIG_DST}/destinations/local.conf"
copy_default "${ABF_SRC}/config/destinations/onedrive.conf" \
             "${CONFIG_DST}/destinations/onedrive.conf"

# Run config migration to upgrade any stale default values
# (e.g. /var/log/abf -> /tmp/abf/logs) left by previous installs.
# Only touches values that still match the old defaults.
if source "${ABF_SRC}/core/migrate.sh" 2>/dev/null; then
    echo ""
    echo "==> Checking for stale config defaults..."
    ABF_CONFIG_DIR="${CONFIG_DST}" abf_config_migrate || true
fi

# ------------------------------------------------------------------
# 5. Verify installation
# ------------------------------------------------------------------
echo "==> Verifying installation..."
if [[ -x "${ABF_DST}/abf" ]]; then
    echo "    Framework installed: ${ABF_DST}/abf"
fi
if command -v abf &>/dev/null; then
    echo "    abf command available: $(which abf)"
    abf --version
else
    echo "    WARNING: abf not found in PATH"
fi

echo "==> Installation complete"
echo ""
echo "Next steps:"
echo "  1. Edit ${CONFIG_DST}/services/vaultwarden.conf to set"
echo "     your Vaultwarden data directory"
echo "  2. Edit ${CONFIG_DST}/services/immich.conf to set"
echo "     your Immich data directory"
echo "  3. Run: abf config check"
echo "  4. Run: abf backup vaultwarden or abf backup immich"
echo ""
echo "To uninstall: sudo bash ${ABF_DST}/scripts/uninstall.sh"
