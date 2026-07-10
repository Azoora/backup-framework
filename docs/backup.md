# Backup

## Create a Backup

```bash
abf backup vaultwarden
```

The framework follows a standardized pipeline:

1. **Pre-backup** -- Validate paths, create working directory
2. **Backup** -- Create consistent snapshot of each component:
   - SQLite database (via `sqlite3 .backup`, or `cp` if sqlite3 unavailable)
   - Attachments directory
   - Icon cache directory
   - RSA keys
   - Configuration file
3. **Restic backup** -- Encrypt and store snapshot in repository
4. **Verify** -- Verify staged content and repository integrity
5. **Retention** -- Prune old snapshots per policy
6. **Destination sync** -- Sync repository to configured destinations (if `BACKUP_DESTINATIONS` is set)
7. **Post-backup** -- Clean up temporary files
8. **Summary** -- Print backup, verify, and per-destination results

## Output

```
[2026-07-10T12:00:00+0000] [INFO   ] Vaultwarden backup started
[2026-07-10T12:00:00+0000] [INFO   ] Created working directory: /tmp/abf-vw-backup-XXXXXX
[2026-07-10T12:00:00+0000] [INFO   ] Backing up SQLite database
[2026-07-10T12:00:01+0000] [SUCCESS] Database backup completed
[2026-07-10T12:00:01+0000] [INFO   ] Backing up attachments
[2026-07-10T12:00:02+0000] [SUCCESS] Attachments backup completed
...
[2026-07-10T12:00:05+0000] [SUCCESS] Archive created (42.3M): /var/backups/abf/vaultwarden/vaultwarden-20260710-120000.tar.gz
[2026-07-10T12:00:05+0000] [SUCCESS] Archive verified — 42 file(s)
[2026-07-10T12:00:05+0000] [INFO   ] Restic: verifying repository integrity
[2026-07-10T12:00:06+0000] [SUCCESS] Restic: repository integrity check passed
[2026-07-10T12:00:06+0000] [INFO   ] Destination 'local': syncing repository
[2026-07-10T12:00:07+0000] [SUCCESS] Local destination: sync completed and verified
[2026-07-10T12:00:07+0000] [INFO   ] Destination 'onedrive': syncing repository
[2026-07-10T12:00:09+0000] [SUCCESS] OneDrive destination: sync completed and verified

========================================
  Backup Summary — vaultwarden
========================================
  Backup:                SUCCESS
  Repository Verify:     SUCCESS
  Local:                 SUCCESS
  OneDrive:              SUCCESS
========================================

[2026-07-10T12:00:09+0000] [SUCCESS] Backup completed for service: vaultwarden
```

## Backup Location

Archives are stored in the directory specified by `SERVICE_VAULTWARDEN_BACKUP_DIR` in the service configuration. Default: `/var/backups/abf/vaultwarden/`.

## Component Toggles

Each component can be enabled or disabled in the service configuration:

| Variable | Default | Description |
|---|---|---|
| `SERVICE_VAULTWARDEN_BACKUP_DATABASE` | `true` | SQLite database |
| `SERVICE_VAULTWARDEN_BACKUP_ATTACHMENTS` | `true` | File uploads |
| `SERVICE_VAULTWARDEN_BACKUP_ICON_CACHE` | `true` | Website icons |
| `SERVICE_VAULTWARDEN_BACKUP_RSA_KEYS` | `true` | Encryption keys |
| `SERVICE_VAULTWARDEN_BACKUP_CONFIG` | `true` | config.json |
| `SERVICE_VAULTWARDEN_BACKUP_TEMP_FILES` | `false` | Temporary data |

Set any to `false` to exclude from backup.

## Logs

Every backup generates two log files in the configured log directory:

- `vaultwarden_backup_<timestamp>.log` -- Human-readable
- `vaultwarden_backup_<timestamp>.jsonl` -- Machine-readable (JSON Lines)

## Scheduling

The framework does not install cron jobs automatically. Use your system's scheduler:

### Cron (daily at 2 AM)

```cron
0 2 * * * /usr/local/bin/abf backup vaultwarden
```

### Systemd Timer

See `examples/` for a systemd timer unit.
