# Restore

## List Available Backups

```bash
abf list vaultwarden
```

Output:

```
vaultwarden      20260710-120000  /var/backups/abf/vaultwarden/vaultwarden-20260710-120000.tar.gz (42.3M)
vaultwarden      20260709-120000  /var/backups/abf/vaultwarden/vaultwarden-20260709-120000.tar.gz (41.8M)
```

## Dry Run

Preview what would be restored without modifying any files:

```bash
abf restore vaultwarden --dry-run
```

## Full Restore

```bash
abf restore vaultwarden
```

This restores the most recent snapshot. The framework will:

1. Auto-select the latest snapshot (or specify with `--snapshot`)
2. Extract the archive to a temporary directory
3. Show the contents
4. Wait 5 seconds for you to cancel (Ctrl+C)
5. **You must stop the Vaultwarden service** before proceeding (not automated)
6. Copy all components back to the data directory
7. Notify you to restart the service

## Restore a Specific Snapshot

```bash
abf restore vaultwarden --snapshot /var/backups/abf/vaultwarden/vaultwarden-20260709-120000.tar.gz
```

## Safety

- Restore **never automatically stops or starts** services
- Restore provides a 5-second confirmation window
- Use `--dry-run` to preview before making changes
- Archives are immutable once created
