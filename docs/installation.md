# Installation

## Requirements

- Bash 4.0 or later
- `tar` (for archive creation)
- `sqlite3` (recommended for consistent SQLite backups; falls back to `cp`)

## Quick Install

```bash
git clone <repository-url> /opt/abf
cd /opt/abf
./scripts/install.sh
```

## Manual Install

```bash
# Create directories
sudo mkdir -p /etc/abf/services
sudo mkdir -p /var/log/abf
sudo mkdir -p /var/backups

# Copy configuration
sudo cp config/abf.conf /etc/abf/
sudo cp config/storage.conf /etc/abf/
sudo cp config/services/vaultwarden.conf /etc/abf/services/

# Install the abf command
sudo cp abf /usr/local/bin/abf
sudo chmod +x /usr/local/bin/abf

# Verify
abf config check
```

## Configuration

Edit the configuration files in `/etc/abf/`:

- `abf.conf` -- Framework settings (log directory, temp directory)
- `services/vaultwarden.conf` -- Vaultwarden paths and component selection

See the [Configuration Guide](configuration.md) for details.

## Uninstall

```bash
sudo rm /usr/local/bin/abf
sudo rm -rf /etc/abf
sudo rm -rf /var/log/abf
```
