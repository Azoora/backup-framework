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

echo "==> Installing Backup Framework"

# ------------------------------------------------------------------
# 1. Create directories
# ------------------------------------------------------------------
echo "==> Setting up directories..."
install -d -m 0755 "${ABF_DST}"
install -d -m 0755 "${ABF_DST}/cache"
install -d -m 0755 "${ABF_DST}/logs"
install -d -m 0755 "${ABF_DST}/temp"
install -d -m 0755 "${CONFIG_DST}/services"
install -d -m 0755 /var/log/abf
install -d -m 0755 /var/cache/abf

# ------------------------------------------------------------------
# 2. Copy framework (preserve relative paths)
# ------------------------------------------------------------------
echo "==> Installing framework to ${ABF_DST}..."
cp -r "${ABF_SRC}/abf"           "${ABF_DST}/abf"
cp -r "${ABF_SRC}/VERSION"       "${ABF_DST}/VERSION"
cp -r "${ABF_SRC}/core"          "${ABF_DST}/core"
cp -r "${ABF_SRC}/services"      "${ABF_DST}/services"
cp -r "${ABF_SRC}/storage"       "${ABF_DST}/storage"
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
copy_default "${ABF_SRC}/config/abf.conf"           "${CONFIG_DST}/abf.conf"
copy_default "${ABF_SRC}/config/storage.conf"        "${CONFIG_DST}/storage.conf"
copy_default "${ABF_SRC}/config/smtp.conf"           "${CONFIG_DST}/smtp.conf"
copy_default "${ABF_SRC}/config/services/vaultwarden.conf" \
             "${CONFIG_DST}/services/vaultwarden.conf"

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
echo "  2. Run: abf config check"
echo "  3. Run: abf backup vaultwarden"
echo ""
echo "To uninstall: sudo bash ${ABF_DST}/scripts/uninstall.sh"
