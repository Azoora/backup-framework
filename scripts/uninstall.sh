#!/usr/bin/env bash
#
# uninstall.sh  --  Backup Framework uninstaller
#
# Removes the installed framework and optionally the configuration.
set -Eeuo pipefail

ABF_DST="/opt/abf"
BIN_DST="/usr/local/bin"
CONFIG_DST="/etc/abf"

echo "==> Uninstalling Backup Framework"

# ------------------------------------------------------------------
# 1. Remove wrapper
# ------------------------------------------------------------------
if [[ -f "${BIN_DST}/abf" ]]; then
    if head -1 "${BIN_DST}/abf" | grep -q "#!/usr/bin/env bash" \
        && grep -q "exec /opt/abf/abf" "${BIN_DST}/abf"; then
        rm -f "${BIN_DST}/abf"
        echo "    Removed ${BIN_DST}/abf"
    else
        echo "    WARNING: ${BIN_DST}/abf does not appear to be the Backup Framework wrapper"
        echo "    Skipping (remove manually if desired)"
    fi
fi

# ------------------------------------------------------------------
# 2. Remove framework
# ------------------------------------------------------------------
if [[ -d "$ABF_DST" ]]; then
    rm -rf "$ABF_DST"
    echo "    Removed ${ABF_DST}/"
else
    echo "    ${ABF_DST}/ not found"
fi

# ------------------------------------------------------------------
# 3. Remove runtime directories
# ------------------------------------------------------------------
rm -rf /var/log/abf /var/cache/abf 2>/dev/null || true
echo "    Removed /var/log/abf, /var/cache/abf"

# ------------------------------------------------------------------
# 4. Configuration removal (with confirmation)
# ------------------------------------------------------------------
echo ""
echo "==> Configuration"
if [[ -d "$CONFIG_DST" ]]; then
    echo "    Configuration directory exists: ${CONFIG_DST}"
    echo "    This directory may contain custom settings and the restic password file."
    echo -n "    Remove configuration? [y/N] "
    read -r answer
    if [[ "${answer:-}" =~ ^[yY] ]]; then
        rm -rf "$CONFIG_DST"
        echo "    Removed ${CONFIG_DST}/"
    else
        echo "    Skipped ${CONFIG_DST}"
    fi
fi

echo ""
echo "==> Uninstall complete"
