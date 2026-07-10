#!/usr/bin/env bash
#
# install.sh  --  Backup Framework installer
#
# Follows the spec's shell-script coding standard.
set -Eeuo pipefail

ABF_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DST="/etc/abf"
BIN_DST="/usr/local/bin"

echo "==> Installing Backup Framework"

# 1. Create directories
echo "==> Setting up directories..."
install -d -m 0755 "${CONFIG_DST}/services"
install -d -m 0755 /var/log/abf
install -d -m 0755 /var/cache/abf

# 2. Copy default config files (do not overwrite existing)
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
copy_default "${ABF_ROOT}/config/abf.conf"           "${CONFIG_DST}/abf.conf"
copy_default "${ABF_ROOT}/config/storage.conf"        "${CONFIG_DST}/storage.conf"
copy_default "${ABF_ROOT}/config/services/vaultwarden.conf" \
             "${CONFIG_DST}/services/vaultwarden.conf"

# 3. Install the abf command
echo "==> Installing abf command..."
if [[ -d "$BIN_DST" ]]; then
    cp "${ABF_ROOT}/abf" "${BIN_DST}/abf"
    chmod 0755 "${BIN_DST}/abf"
    echo "    Installed ${BIN_DST}/abf"
else
    echo "    WARNING: ${BIN_DST} not found -- install abf manually"
fi

# 4. Verify installation
echo "==> Verifying installation..."
if command -v abf &>/dev/null; then
    echo "    abf command is available"
    abf --version
else
    echo "    WARNING: abf command not found in PATH"
fi

echo "==> Installation complete"
echo ""
echo "Next steps:"
echo "  1. Edit ${CONFIG_DST}/services/vaultwarden.conf"
echo "     to set your Vaultwarden data directory"
echo "  2. Run: abf config check"
echo "  3. Run: abf backup vaultwarden"
