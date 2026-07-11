# Installation

## Requirements

- Bash 4.0 or later
- `restic` (recommended for encrypted backups; install from [restic.net](https://restic.net))
- `rclone` (required for OneDrive storage; `apt install rclone` or [rclone.org](https://rclone.org))
- `sqlite3` (recommended for consistent SQLite backups; falls back to `cp`)
- `crontab` or `systemd` (for scheduling; auto-detected)

## Automated Install

```bash
git clone <repository-url> /opt/abf
cd /opt/abf
sudo ./scripts/install.sh
```

The installer:

1. Checks for required dependencies (restic) and recommended dependencies (rclone, sqlite3)
2. On Debian/Ubuntu, offers to install missing recommended packages automatically via `apt`
3. Copies the full framework to `/opt/abf/`
4. Creates a lightweight wrapper at `/usr/local/bin/abf` that execs `/opt/abf/abf`
5. Copies default configuration to `/etc/abf/` (never overwrites existing files)
6. Creates runtime directories (`/var/log/abf`, `/var/cache/abf`)

## Manual Install

```bash
# Deploy framework
sudo mkdir -p /opt/abf
sudo cp -r abf core services storage scripts tests docs examples VERSION \
         CHANGELOG.md LICENSE README.md /opt/abf/
sudo chmod +x /opt/abf/abf

# Create wrapper
printf '#!/usr/bin/env bash\nexec /opt/abf/abf "$@"\n' \
  | sudo tee /usr/local/bin/abf >/dev/null
sudo chmod +x /usr/local/bin/abf

# Configuration
sudo mkdir -p /etc/abf/services /var/log/abf /var/cache/abf
sudo cp config/abf.conf /etc/abf/
sudo cp config/storage.conf /etc/abf/
sudo cp config/smtp.conf /etc/abf/
sudo cp config/services/vaultwarden.conf /etc/abf/services/

# Verify
abf config check
```

## Install Layout

```
# Development mode (git checkout)
checkout/
├── abf              # full launcher (ABF_ROOT = checkout/)
├── core/
├── services/
├── storage/
└── ...

# Installed mode (production)
/opt/abf/
├── abf              # full launcher (ABF_ROOT = /opt/abf/)
├── core/
├── services/
├── storage/
└── ...

/usr/local/bin/abf   # lightweight wrapper (2 lines, no framework logic)
```

Both modes use identical code. `ABF_ROOT` is computed from the launcher's own location, so it resolves correctly in either layout.

## Configuration

Edit the configuration files in `/etc/abf/`:

- `abf.conf` — Framework settings (log directory, storage backend, retention)
- `storage.conf` — Storage backend defaults
- `smtp.conf` — SMTP notification settings (host, port, TLS, auth, from name/email, recipients, log attach)
- `services/vaultwarden.conf` — Vaultwarden paths and component selection

See the [Configuration Guide](configuration.md) for details.

## Upgrading

Re-run the installer to upgrade:

```bash
sudo ./scripts/install.sh
```

The installer:

1. Replaces all framework files in `/opt/abf/`
2. Preserves your existing configuration (never overwrites modified files)
3. Runs **config migration** to upgrade any stale default values
4. Existing customized values are never touched

### Config Migration

When upgrading from a previous version, the installer automatically detects
config values that still carry old defaults and updates them to the current
standard.  Before making any changes, it creates a timestamped backup:

```
/etc/abf/backup/20260710-020000/
├── abf.conf
├── storage.conf
├── smtp.conf
└── services/
    └── vaultwarden.conf
```

You can also run migration manually at any time:

```bash
abf config migrate
```

Migration only touches values that exactly match a known old default.
If you have customized a value, it is left unchanged.

### Migration Examples

| Variable | Old Default | New Default |
|---|---|---|
| `ABF_LOG_DIR` | `/var/log/abf` | `/tmp/abf/logs` |
| `ABF_CACHE_DIR` | `/var/cache/abf` | `/tmp/abf/cache` |
| `SERVICE_VAULTWARDEN_BACKUP_DIR` | `/var/backups/abf/vaultwarden` | `/tmp/abf/vaultwarden` |

## Privilege Requirements

Backup and restore operations require read access to:

- The **restic password file** (`/etc/abf/restic-password`)
- The **service data directory** (e.g. `/var/lib/vaultwarden`)

Both are typically owned by `root`.  Before starting a backup or restore,
the framework checks that the current user can read these paths.  If not,
it fails immediately with a clear message:

```
ERROR: Cannot read restic password file: /etc/abf/restic-password
ERROR: Backup requires elevated privileges.

  Run: sudo abf backup vaultwarden
```

Run all backup and restore commands with `sudo`:

```bash
sudo abf backup vaultwarden
sudo abf restore vaultwarden
```

## Uninstall

```bash
sudo bash /opt/abf/scripts/uninstall.sh
```

The uninstaller:
1. Removes `/usr/local/bin/abf` (only if it matches the known wrapper)
2. Removes `/opt/abf/`
3. Removes `/var/log/abf` and `/var/cache/abf`
4. Prompts before removing `/etc/abf/` (preserves custom configuration)
