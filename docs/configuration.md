# Configuration

All configuration lives in `/etc/abf/` (or `~/.config/abf/`, or `./config/`).

Files use simple `KEY=VALUE` format and are sourced directly by the framework.

## File: `abf.conf`

```bash
# Directory for log output
ABF_LOG_DIR="/var/log/abf"

# Directory for cached data
ABF_CACHE_DIR="/var/cache/abf"

# Directory for temporary files
ABF_TEMP_DIR="/tmp/abf"
```

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

# Where backup archives are stored
SERVICE_VAULTWARDEN_BACKUP_DIR="/var/backups/abf/vaultwarden"

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
