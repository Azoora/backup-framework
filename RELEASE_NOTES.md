# Release Notes — v0.1.0-beta

**Release date:** 2026-07-10

---

## Overview

Backup Framework is a production-grade, modular backup platform for self-hosted infrastructure. It provides encrypted, scheduled, off-site backups with a bash-first design that requires no language runtimes beyond bash itself.

---

## Major Features

### Core Engine
- Flat CLI with 9 commands (`backup`, `restore`, `list`, `config`, `doctor`, `schedule install/remove/status/list`)
- Service plugin architecture with standardized lifecycle hooks
- Storage plugin architecture with extensible backends
- Dual-output logging (human-readable `.log` + JSON Lines `.jsonl`)
- KEY=VALUE configuration with layered loading (defaults → overrides)
- Standardized exit codes (`core/exit_codes.sh`)

### Encryption & Storage (Restic)
- AES-256-GCM encrypted backups via restic
- Automated repository initialization
- Integrity verification (`restic check --read-data-subset=5%`)
- Snapshot listing and tagged by service name
- Retention policy with `restic forget` (daily/weekly/monthly pruning)

### OneDrive Support
- Rclone-backed OneDrive storage via restic rclone backend
- No separate upload step — restic handles encryption and transport

### Notifications
- SMTP email with four delivery backends (`mail`, `sendmail`, `msmtp`, bash TCP)
- Configurable from address and recipient
- Disabled by default

### Concurrency Safety
- PID-based lock files prevent concurrent backup jobs
- Stale lock detection (crashed process cleanup)
- EXIT trap guarantees lock release

### Scheduling
- Auto-detects systemd (preferred) or cron
- Supports daily, weekly, monthly, and custom cron expressions
- Human-readable schedule descriptions
- `--force` to overwrite existing schedules

### Diagnostics
- `abf doctor` — 13 comprehensive health checks
- `--json` mode for monitoring integration
- Nagios-compatible exit codes (0=OK, 1=WARNING, 2=ERROR)

### Vaultwarden Service Module
- SQLite database backup (with `sqlite3 .backup` or fallback `cp`)
- Attachments, icon cache, RSA keys, `config.json`
- Per-component enable/disable flags
- Safe restore with dry-run preview and 5-second abort window

---

## Supported Services

| Service | Components | Status |
|---|---|---|
| Vaultwarden | SQLite DB, attachments, icon cache, RSA keys, config.json | Mature |

---

## Supported Storage Backends

| Backend | Mechanism | Status |
|---|---|---|
| Local | File-level staging + verify | Mature |
| OneDrive | Restic over rclone | Mature |
| Umbrel | — | Stub |

---

## Known Limitations

1. **Single service module**: Only Vaultwarden is currently implemented. The plugin architecture supports additional services but none have been built yet.
2. **Umbrel storage**: The Umbrel storage module is a stub with no functional implementation.
3. **No automatic restic install**: The framework detects restic but does not install it. Users must install restic separately.
4. **SMTP TLS**: TLS is only supported in the bash TCP fallback path. The `mail`, `sendmail`, and `msmtp` backends handle TLS externally.
5. **restic `--time`**: The `--time` flag is not passed to restic (incompatible date format). Restic uses the current system time.
6. **No web dashboard**: Monitoring and management are CLI-only.
7. **Debug logging**: `abf_log_debug` calls exist but are sparsely used in the pipeline. Most operational logging is at INFO level.

---

## Upgrade Notes

**From Milestone 1 (0.0.x):**
- The version number jumps directly to `0.1.0-beta` as this is the first tagged release.
- No upgrade path exists from pre-tagged versions.

**Fresh install:**
```bash
git clone <repo> /opt/abf
cd /opt/abf
sudo ./scripts/install.sh
echo "your-password" | sudo tee /etc/abf/restic-password
sudo chmod 600 /etc/abf/restic-password
# Edit /etc/abf/services/vaultwarden.conf
abf config check
abf backup vaultwarden
```

---

## Future Roadmap

| Area | Status |
|---|---|
| Additional service modules (PostgreSQL, Nextcloud, Gitea) | Planned |
| Umbrel storage backend | Planned |
| Umbrel app store packaging | Planned |
| Retention module refactoring | Deferred |
| Naming consistency (prefixed vs unprefixed config vars) | Deferred |
| Docker-based service module support | Future |
| Web dashboard | Out of scope |
| Monitoring / metrics | Out of scope |

---

## Testing

54 automated tests across 9 test files:

| Test file | Tests | Area |
|---|---|---|
| `test_config.sh` | 9 | Config loading, validation |
| `test_log.sh` | 4 | Dual-output logging |
| `test_notify.sh` | 6 | SMTP notifications, status mapping |
| `test_lock.sh` | 5 | Concurrency locks, stale detection |
| `test_restic.sh` | 4 | Restic init, backup, restore, verify |
| `test_retention.sh` | 3 | Retention policy |
| `test_scheduler.sh` | 11 | Schedule descriptions, cron/systemd, install/remove |
| `test_diagnostics.sh` | 6 | Doctor output, exit codes |
| `test_vaultwarden.sh` | 6 | Backup, verify, restore, healthcheck, cleanup |

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the complete history.
