# Changelog

## 0.1.0 (Milestone 1)

- Project structure and architecture
- Bash-first CLI entry point (`abf`) with flat command structure
- Configuration loader (KEY=VALUE `.conf` files, environment-aware)
- Dual-output logging system (human + JSON Lines)
- Core backup engine with standardized lifecycle hooks
- Service manifest (`services/manifest.conf`)
- Vaultwarden service module with full lifecycle implementation
- Backup pipeline: pre-backup, backup, verify, post-backup
- Restore pipeline: pre-restore, restore, verify-restore, post-restore
- Dry-run restore with 5-second abort window
- Snapshot listing
- Config validation
- Documentation: installation, configuration, backup, restore, troubleshooting
- Test suite with 13 tests
