# Security Policy

## Supported Versions

| Version | Supported |
|---|---|
| 0.1.x (beta) | Security fixes are accepted but no active backporting |

## Reporting a Vulnerability

The Backup Framework handles access to encrypted backup repositories and
may process sensitive data (database files, configuration secrets, TLS keys).

If you discover a security vulnerability:

1. **Do not** open a public GitHub issue.
2. Email the maintainers or open a draft security advisory on GitHub.
3. Include a description of the issue, steps to reproduce, and affected versions.

You should receive a response within 72 hours.

## Security Best Practices

### Restic Password

The restic repository password is stored in a file referenced by
`ABF_RESTIC_PASSWORD_FILE` (default: `/etc/abf/restic-password`).

```bash
chmod 600 /etc/abf/restic-password
```

Do not check this file into version control.

### Lock Files

Lock files are stored in `ABF_LOCK_DIR` (default: `/tmp/abf/locks`).
They contain only the PID of the running backup process and are
automatically cleaned up via EXIT traps. Stale lock files (from
crashed processes) are detected and removed when the next backup runs.

### Log Files

Log files may contain service names and operation metadata but do
**not** contain passwords or encryption keys. Restrict access:

```bash
chmod 640 /var/log/abf/*.log
```

### SMTP Credentials

SMTP credentials (`SMTP_USER`, `SMTP_PASS`) are stored in
`/etc/abf/smtp.conf`. Restrict access:

```bash
chmod 600 /etc/abf/smtp.conf
```

### Network

- The backup framework does not listen on any network port.
- SMTP notifications connect outbound to the configured SMTP server.
- Restic communicates with storage backends (OneDrive via rclone, etc.).
