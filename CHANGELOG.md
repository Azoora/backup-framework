# Changelog

## 0.1.1-beta (2026-07-10)

### Milestone 3 — Local Storage Backend, Installation & Diagnostics Improvements

- New `local` storage backend: stores Restic repositories on the local filesystem
  - Configurable via `STORAGE_LOCAL_REPO_PATH` (default: `/tmp/abf/restic`)
  - Supports init, backup, restore, snapshot listing, verification
- `ABF_STORAGE_BACKEND=local` now works as a proper storage backend (was a no-op pseudo-backend)

- `install.sh`: dependency detection (restic, rclone, sqlite3) with auto-install on Debian/Ubuntu
- `abf config check`: batch error reporting — all errors reported together with summary
- `abf doctor`: new checks (sqlite3, rclone configuration), improved [PASS]/[WARN]/[FAIL] output format
- 6 new automated tests (62 total)

### Bug Fixes (Production Deployment)

- **Bug 1 — Hardcoded log path**: Removed all `/var/log/abf` fallback defaults from `core/log.sh:23` and
  `abf:86,109`. Log path is now sourced exclusively from `ABF_LOG_DIR` config variable. If unset,
  `abf_init_logging` falls back to empty string. Config validation catches missing `ABF_LOG_DIR`.
- **Bug 2 — Hardcoded backup path**: Changed `services/vaultwarden/service.conf:8` default from
  `/var/backups/abf/vaultwarden` to `/tmp/abf/vaultwarden`. Added `|| true` guard on `mkdir -p`
  in `service_pre_backup` so `set -u` does not crash on failure.
- **Bug 3 — Unbound variable + lock leak**: The EXIT trap already used the global `$ABF_LOCK_SERVICE`
  instead of the local `$service_name`, but `abf_run_backup` never explicitly released the lock on
  success or early-return paths — only the EXIT trap released it. Added explicit `abf_lock_release`
  to every `return` path (both error and success), with the EXIT trap retained as a safety net.
- **Test suite gap**: Added `test_integration.sh` with 5 end-to-end tests that run `./abf backup
  vaultwarden` via the real CLI against a temp config/environment. Tests verify no `unbound variable`
  crashes and that lock files are cleaned up post-backup.
- 24 new automated tests (86 total)

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
