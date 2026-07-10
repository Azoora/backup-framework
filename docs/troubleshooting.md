# Troubleshooting

## Configuration Errors

```bash
abf config check
```

This validates all configuration files and reports any issues.

## Common Issues

### "Config directory not found"

The framework cannot find a configuration directory. Use `--config` to specify the path explicitly:

```bash
abf --config /etc/abf backup vaultwarden
```

### "Vaultwarden data directory does not exist"

The `SERVICE_VAULTWARDEN_DATA_DIR` path does not point to a valid directory.

Verify the path:

```bash
ls -la /var/lib/vaultwarden
```

### "Failed to create archive"

Possible causes:

- Permission denied on the backup directory
- Disk full
- Temporary directory creation failed

Check the log file for detailed error messages.

### "No snapshots found"

The backup directory is empty or does not exist. Verify the path in the configuration:

```bash
abf list vaultwarden
```

### "sqlite3 not found — copied database without consistency guarantee"

The `sqlite3` command-line tool is not installed. The database is copied directly, which may result in an inconsistent snapshot if the database is in use during backup.

Install sqlite3:

```bash
sudo apt install sqlite3    # Debian/Ubuntu
sudo dnf install sqlite3    # Fedora
```

## Logs

Log files are stored in the directory specified by `ABF_LOG_DIR` in `abf.conf`.

Each operation generates two files:

- `*.log` -- Human-readable
- `*.jsonl` -- Machine-readable (JSON Lines)

## Getting Help

Check the log files first. If the issue persists, file a bug report with:

1. The command you ran
2. The full output
3. The relevant log files
4. Your configuration (with secrets redacted)
