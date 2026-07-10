# Configuration

All configuration lives in `/etc/abf/` (or `~/.config/abf/`, or `./config/`).

Files use simple `KEY=VALUE` format and are sourced directly by the framework.

## File: `abf.conf`

```bash
# Directory for log output
ABF_LOG_DIR="/tmp/abf/logs"

# Directory for cached data
ABF_CACHE_DIR="/tmp/abf/cache"

# Directory for temporary files
ABF_TEMP_DIR="/tmp/abf"

# Comma-separated list of destinations to sync after each backup
# Supported values: local, onedrive
# Local syncs to DESTINATION_LOCAL_PATH (default: /mnt/umbrel/backups/restic)
# OneDrive syncs to DESTINATION_ONEDRIVE_REMOTE:DESTINATION_ONEDRIVE_PATH
BACKUP_DESTINATIONS=""
```

> **Note:** If upgrading from a previous version, your config may still contain
> the old defaults (`/var/log/abf`, `/var/cache/abf`).  Run `abf config migrate`
> or re-run `install.sh` to upgrade them automatically.

## File: `storage.conf`

```bash
# Default storage backend (Milestone 2+)
STORAGE_DEFAULT="local"

# Retention policy (Milestone 2+)
RETENTION_KEEP_DAILY=7
RETENTION_KEEP_WEEKLY=4
RETENTION_KEEP_MONTHLY=3
```

## File: `services/vaultwarden.conf`

```bash
# Path to the Vaultwarden data directory
SERVICE_VAULTWARDEN_DATA_DIR="/var/lib/vaultwarden"

# Directory for staging backup files before encryption
SERVICE_VAULTWARDEN_BACKUP_DIR="/tmp/abf/vaultwarden"

# Toggle individual backup components on or off
SERVICE_VAULTWARDEN_BACKUP_DATABASE=true
SERVICE_VAULTWARDEN_BACKUP_ATTACHMENTS=true
SERVICE_VAULTWARDEN_BACKUP_ICON_CACHE=true
SERVICE_VAULTWARDEN_BACKUP_RSA_KEYS=true
SERVICE_VAULTWARDEN_BACKUP_CONFIG=true
SERVICE_VAULTWARDEN_BACKUP_TEMP_FILES=false
```

## Configuration Discovery

The framework searches for the config directory in this order:

1. `/etc/abf/`
2. `~/.config/abf/`
3. `./config/` (relative to the working directory)

Use `--config DIR` to specify a custom path.

## Validation

```bash
abf config check
```

## Migration (Upgrade)

When upgrading the framework, config values that still match a known old
default are automatically updated.  A timestamped backup of your full config
directory is created first:

```bash
# Automatic: re-run install.sh
sudo ./scripts/install.sh

# Manual: run at any time
abf config migrate
```

### How It Works

1. The migration engine reads a list of known old-default → new-default mappings
2. For each config file, it checks if any value still matches an old default
3. If matched, the value is updated to the new default
4. **Customized values are never touched** — only values that exactly match
   the old default are updated
5. Before the first change, a full backup is created at
   `/etc/abf/backup/YYYYMMDD-HHMMSS/`

### Current Migration Rules

| Config File | Variable | Old Default | New Default |
|---|---|---|---|
| `abf.conf` | `ABF_LOG_DIR` | `/var/log/abf` | `/tmp/abf/logs` |
| `abf.conf` | `ABF_CACHE_DIR` | `/var/cache/abf` | `/tmp/abf/cache` |
| `services/vaultwarden.conf` | `SERVICE_VAULTWARDEN_BACKUP_DIR` | `/var/backups/abf/vaultwarden` | `/tmp/abf/vaultwarden` |

### Idempotent

Running migration multiple times is safe.  Once a value has been updated,
subsequent runs detect no pending changes and produce no additional backups.
