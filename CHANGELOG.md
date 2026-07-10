# Changelog

## 0.1.0-beta (2026-07-10)

### Milestone 2 — Restic, Notifications, Retention, Scheduling

- Restic integration: encrypted backup/restore/verify/forget
- OneDrive storage backend via rclone restic
- SMTP notifications with 4 delivery backends (mail, sendmail, msmtp, bash TCP)
- Retention policy engine (daily/weekly/monthly pruning via `restic forget`)
- Backup locking: PID-based concurrency safety with stale detection
- Schedule management: cron + systemd timers (auto-detect, human-readable descriptions)
- Diagnostics: `abf doctor` with 13 health checks, JSON output, Nagios-compatible exit codes
- `--verbose` / `-v` flag with debug log gating
- Standardized exit codes (`core/exit_codes.sh`)
- Storage plugin architecture (`storage/manifest.conf`, OneDrive module)
- Optional lifecycle hooks (healthcheck, cleanup)
- `VERSION` file and `--version` flag
- 54 automated tests (up from 13)

### Milestone 1 — Core Engine

- Bash-first CLI entry point (`abf`) with flat command structure
- Configuration loader (KEY=VALUE `.conf` files, environment-aware)
- Dual-output logging system (human-readable + JSON Lines)
- Core backup engine with standardized lifecycle hooks
- Service manifest (`services/manifest.conf`)
- Vaultwarden service module with full lifecycle implementation
- Backup pipeline: pre-backup, backup, verify, post-backup
- Restore pipeline: pre-restore, restore, verify-restore, post-restore
- Dry-run restore with 5-second abort window
- Snapshot listing
- Config validation (`abf config check`)
- Installation script (`scripts/install.sh`)
- Documentation: installation, configuration, backup, restore, troubleshooting
- Test suite with 13 tests
