# Backup Framework

A production-grade, modular backup platform for self-hosted infrastructure.  
Designed for operators who need encrypted, scheduled, off-site backups without heavy dependencies.

```text
abf backup vaultwarden    →  staged → restic encrypted → OneDrive
                            verified → notified → retained
```

---

## Features

- **Bash-first** — Zero language runtime dependencies (`set -Eeuo pipefail`)
- **Encrypted storage** — Restic-backed with AES-256-GCM, configurable password
- **Off-site support** — OneDrive via rclone restic backend (S3, SFTP, B2 also possible)
- **Plugin architecture** — Services via `services/<name>/module.sh`, storage via `storage/<name>/module.sh`, destinations via `destinations/<name>/module.sh`
- **Lifecycle hooks** — `pre_backup`, `backup`, `verify_backup`, `post_backup` (and restore equivalents)
- **Concurrency safety** — PID-based lock files with stale detection and EXIT trap cleanup
- **Scheduling** — Auto-detects systemd timers or cron, generates human-readable descriptions
- **Notifications** — SMTP email with four delivery fallbacks (mail, sendmail, msmtp, bash TCP). Subject includes status (SUCCESS/WARNING/FAILED), service name, snapshot ID, start/end time, duration, repo verification result, destination results, and attaches the backup log (up to configurable size limit).
- **Retention** — Policy-driven snapshot pruning via `restic forget` (daily/weekly/monthly)
- **Diagnostics** — `abf doctor` with 13 health checks, JSON mode for monitoring
- **System Status** — `abf status` with human, short, and JSON output modes
- **Dual-output logging** — Human-readable `.log` + machine-readable `.jsonl`
- **Safe restore** — Dry-run mode, 5-second abort window, staging directory isolation

---

## Architecture

```
abf                    CLI entry point
├── core/              Engine modules
│   ├── config.sh      KEY=VALUE config loader (abf.conf → storage.conf → smtp.conf)
│   ├── log.sh         Dual-output logging (human + JSON Lines)
│   ├── core.sh        Backup/restore pipeline orchestrator
│   ├── exit_codes.sh  Standardized exit codes (8 values)
│   ├── restic.sh      Restic backup, restore, verify, forget
│   ├── notify.sh      SMTP notifications (4 delivery backends)
│   ├── retention.sh   Retention policy passthrough
│   ├── lock.sh        PID-based concurrency lock
│   ├── scheduler.sh   Cron/systemd schedule management (global + per-service)
│   ├── diagnostics.sh Health check subsystem (abf doctor)
│   └── status.sh      System health overview (abf status)
├── services/          Service plugin modules
│   ├── manifest.conf  Explicit service registry
│   └── vaultwarden/   Vaultwarden lifecycle hooks
├── storage/           Storage backend plugins
│   ├── manifest.conf  Explicit storage registry
│   ├── onedrive/      Rclone-backed OneDrive
│   └── umbrel/        (future)
├── destinations/      Destination sync plugins
│   ├── manifest.conf  Explicit destination registry
│   ├── local/         Local filesystem (Umbrel)
│   └── onedrive/      OneDrive via rclone
├── config/            Default configuration files
│   ├── abf.conf       Framework settings
│   ├── storage.conf   Storage defaults
│   ├── smtp.conf      SMTP notification settings (host, port, TLS, auth, from name/email, recipients, log attach)
│   └── services/      Per-service overrides
├── tests/             Automated test suite (220+ tests)
├── scripts/           install.sh, test.sh
├── examples/          cron + systemd timer examples
├── cache/             Runtime cache
├── logs/              Runtime logs
├── temp/              Temporary files
├── VERSION            Current version
├── CHANGELOG.md       Release history
├── CONTRIBUTING.md    Contribution guidelines
├── SECURITY.md        Security policy
├── LICENSE            MIT license
└── docs/              Documentation
```

### Backup Pipeline

```
service_pre_backup     →  Validate environment, create staging directory
service_backup         →  Populate staging dir with raw files
abf_restic_backup      →  Encrypt and store snapshot in repository
service_verify_backup  →  Verify staging dir content
abf_restic_verify      →  Check repository integrity (5% data subset)
abf_apply_retention    →  Prune old snapshots per policy
destination_sync       →  Sync repo to configured destinations (local, onedrive)
service_post_backup    →  Clean up staging directory
abf_print_summary      →  Print backup + verify + destination results
abf_notify_send        →  Send email notification (if configured)
```

### Restore Pipeline

```
service_pre_restore    →  Validate environment, prepare staging
abf_restic_restore     →  Decrypt and restore snapshot to staging
service_restore        →  Copy files from staging to service location
service_verify_restore →  Verify restored files
service_post_restore   →  Clean up staging
```

---

## Quick Start

```bash
# Install (copies framework to /opt/abf, creates /usr/local/bin/abf wrapper)
sudo ./scripts/install.sh

# Validate
sudo abf config check

# Run a backup
sudo abf backup vaultwarden

# List snapshots
sudo abf list vaultwarden

# Dry-run restore
sudo abf restore vaultwarden --dry-run

# Health check
sudo abf doctor
```

**Two modes:** `./abf` works from a git checkout (development).  
After `install.sh`, the `abf` command works system-wide (production).  
Both modes use the same code — only the install layout differs.

---

## Installation

### Requirements

| Dependency | Required | Notes |
|---|---|---|
| bash ≥ 4.0 | yes | `set -Eeuo pipefail` |
| restic | for encryption | Install from [restic.net](https://restic.net) |
| rclone | for OneDrive | `apt install rclone` or [rclone.org](https://rclone.org) |
| crontab or systemd | for scheduling | Auto-detected |

### Automated Install

```bash
git clone https://github.com/your-org/backup-framework.git /opt/abf
cd /opt/abf
sudo ./scripts/install.sh
```

The installer:
<br>- Copies the full framework to `/opt/abf/`
<br>- Creates a lightweight wrapper at `/usr/local/bin/abf` that execs `/opt/abf/abf`
<br>- Copies default configuration to `/etc/abf/` (without overwriting existing files)
</br>
```bash
# Source layout (development)
git checkout/
├── abf              # full launcher
├── core/            # engine modules
├── services/        # service plugins
└── storage/         # storage plugins

# Installed layout (production)
/opt/abf/
├── abf              # full launcher
├── core/
├── services/
├── storage/
└── ...

/usr/local/bin/abf   # lightweight wrapper → exec /opt/abf/abf
```

### Manual Install

```bash
# Deploy framework
sudo mkdir -p /opt/abf
sudo cp -r abf core services storage scripts tests docs examples \
         VERSION CHANGELOG.md LICENSE README.md /opt/abf/
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
```

### Uninstall

```bash
sudo bash /opt/abf/scripts/uninstall.sh
```

---

## Configuration

Configuration is key=value, loaded in this order (later overrides earlier):

1. `config/abf.conf` — Framework defaults
2. `config/storage.conf` — Storage backend defaults
3. `services/<name>/service.conf` — Service module defaults
4. `config/services/<name>.conf` — User overrides

### Essential Settings (`/etc/abf/abf.conf`)

```ini
ABF_LOG_DIR="/var/log/abf"
ABF_STORAGE_BACKEND="onedrive"
ABF_RESTIC_PASSWORD_FILE="/etc/abf/restic-password"
ABF_RETENTION_KEEP_DAILY=7
ABF_RETENTION_KEEP_WEEKLY=4
ABF_RETENTION_KEEP_MONTHLY=3
```

Create a restic password:

```bash
echo "your-strong-password" | sudo tee /etc/abf/restic-password
sudo chmod 600 /etc/abf/restic-password
```

---

## Usage

### Backup

```bash
abf backup vaultwarden
```

### Restore

```bash
abf restore vaultwarden --dry-run         # preview without modifying files
abf restore vaultwarden                    # restore latest snapshot
abf restore vaultwarden --snapshot a1b2c3  # restore specific snapshot
```

### Global Schedule

```bash
abf schedule enable               # enable with saved/default schedule
abf schedule disable              # disable the global schedule
abf schedule daily 03:00          # configure and enable daily backup at 03:00
abf schedule status               # show global schedule status
```

### Per-Service Schedule

```bash
abf schedule install vaultwarden \
  --frequency daily \
  --at 03:00

abf schedule install vaultwarden \
  --frequency weekly \
  --at 02:00 \
  --on-day 0

abf schedule status vaultwarden   # status for a specific service
abf schedule list                 # list all scheduled backups
abf schedule remove vaultwarden
```

### System Status

```bash
abf status              # comprehensive health overview (human-readable)
abf status --short      # concise summary (for voice assistants / Apple Shortcuts)
abf status --json       # structured JSON (for Home Assistant, n8n, dashboards)
```

### Diagnostics

```bash
abf doctor          # human-readable health report
abf doctor --json   # machine-readable for monitoring (Nagios-compatible exit codes)
```

### List Snapshots

```bash
abf list                # all snapshots
abf list vaultwarden    # snapshots for a specific service
```

### Destination Validation

```bash
abf destination check   # validate all configured destinations
```

### SMTP Configuration Wizard

```bash
sudo abf config smtp
```

Interactive wizard for configuring SMTP notifications. Prompts for host, port, TLS, credentials, sender info, and recipients. Saves to `/etc/abf/smtp.conf` without overwriting existing values unless confirmed. Optionally sends a test email after configuration.

### Test Notification

```bash
abf notify test
```

Sends a test email using the current SMTP configuration. Reports success or failure immediately. Requires `SMTP_ENABLED="true"` in `smtp.conf`.

### Config Validation

```bash
abf config check
```

---

## Supported Services

| Service | Status | Components |
|---|---|---|
| Vaultwarden | Mature | SQLite, attachments, icon cache, RSA keys, `config.json` |

---

## Supported Storage Backends

| Backend | Status | Mechanism |
|---|---|---|
| Local | Mature | File-level staging + verify |
| OneDrive | Mature | Restic over rclone |
| Umbrel | Stub | — |

## Supported Destinations

After each backup, the repository can be synced to one or more destinations for redundancy.

| Destination | Status | Mechanism |
|---|---|---|
| Local | Mature | rsync to local path (e.g. Umbrel SSD) |
| OneDrive | Mature | rclone sync to Microsoft OneDrive |

Configure via `BACKUP_DESTINATIONS="local,onedrive"` in `abf.conf`. Each destination is independent — if one fails, the others continue. The backup itself is considered successful as long as the Restic snapshot was created.

---

## Scheduling

The framework provides two scheduling modes:

### Global Schedule (Recommended)

A single systemd timer (`abf-backup.timer`) runs backups for **all services** in the manifest.  
Configured via:

```bash
abf schedule daily 03:00    # set daily backup at 3 AM
abf schedule status         # view schedule, next/last run
abf schedule disable        # stop scheduled backups
```

The timer is persisted across reboots. Re-running `abf schedule daily HH:MM` updates the existing schedule.  
The schedule configuration is saved to `$ABF_CONFIG_DIR/schedule.conf`.

### Per-Service Schedule (Legacy)

The framework also auto-detects the available scheduling system (systemd preferred, cron fallback) for individual services.

**systemd timer** — Units named `abf-backup-<service>.service` and `.timer` are created in `/etc/systemd/system/`.

**cron** — A line is added to the user's crontab with `# abf-schedule:<service>` annotation.

Both backends support `--frequency daily|weekly|monthly|<cron-expr>`.

---

## System Status

The `abf status` command provides a complete health overview of the backup appliance:

```
Backup Framework v0.1.1-beta

Overall Health
--------------
HEALTHY

Services
--------
Vaultwarden
  Last Backup : Today 03:00
  Status      : SUCCESS
  Repository  : Healthy

Immich
  Status      : Disabled

Scheduler
---------
Enabled   : Yes
Next Run  : Tomorrow 03:00

Storage
-------
Local Repository : OK

Notifications
-------------
SMTP       : OK
Last Email : Delivered
```

Three output formats:
- **Default**: Formatted table view with sections for health, services, scheduler, storage, and notifications
- `--short`: Concise one-liners for voice assistants and Apple Shortcuts
- `--json`: Structured JSON for Home Assistant, n8n, and dashboards

---

## Project Structure

```
abf                        CLI entry point
VERSION                    Current version
core/                      Engine modules
  config.sh                Configuration loader
  log.sh                   Dual-output logging
  core.sh                  Pipeline orchestrator
  exit_codes.sh            Standardized exit codes
  restic.sh                Restic integration
  notify.sh                SMTP notifications
  retention.sh             Retention policy
  lock.sh                  Backup locking
  scheduler.sh             Schedule management (global + per-service)
  diagnostics.sh           Health diagnostics
  status.sh                System health overview
services/                  Service plugin modules
  manifest.conf            Service registry
  vaultwarden/             Vaultwarden lifecycle hooks
storage/                   Storage backend plugins
  manifest.conf            Storage registry
  onedrive/                OneDrive via rclone
destinations/              Destination sync plugins
  manifest.conf            Destination registry
  local/                   Local filesystem (Umbrel)
  onedrive/                OneDrive via rclone
config/                    Default configuration
  abf.conf                 Framework settings
  storage.conf             Storage defaults
  smtp.conf                SMTP settings
  services/                Service overrides
tests/                     Test suite (220+ tests)
scripts/                   install.sh, test.sh
cache/                     Runtime cache
logs/                      Runtime logs
temp/                      Temporary files
docs/                      Documentation
examples/                  cron + systemd timer examples
VERSION                    Current version
CHANGELOG.md               Release history
CONTRIBUTING.md            Contribution guidelines
SECURITY.md                Security policy
LICENSE                    MIT license
```

---

## Development

```bash
# Run tests
bash scripts/test.sh

# Run a specific test file
bash scripts/test.sh test_vaultwarden test_restic

# Run in verbose mode
ABF_VERBOSE=true bash scripts/test.sh
```

### Adding a Service

1. Add service name to `services/manifest.conf`
2. Create `services/<name>/module.sh` with all lifecycle hooks
3. Create `config/services/<name>.conf` with user-configurable overrides

### Adding a Storage Backend

1. Add backend name to `storage/manifest.conf`
2. Create `storage/<name>/module.sh` defining `storage_get_repo_url()`

### Adding a Destination

1. Add destination name to `destinations/manifest.conf`
2. Create `destinations/<name>/module.sh` defining `destination_sync()` and optionally `destination_name()`

---

## Documentation

- [Installation](docs/installation.md)
- [Configuration](docs/configuration.md)
- [Backup](docs/backup.md)
- [Restore](docs/restore.md)
- [Troubleshooting](docs/troubleshooting.md)

---

## License

MIT — see [LICENSE](LICENSE).
