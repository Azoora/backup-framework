# Backup Framework

A production-grade, modular backup platform designed to protect self-hosted infrastructure.

## Status

Milestone 1 -- Core engine with Vaultwarden support.

## Features

- Modular Bash-first architecture with standardized lifecycle hooks
- Plugin-based services via explicit manifest
- Consistent backup pipeline (pre-backup, backup, verify, post-backup)
- Dual-output logging (human-readable + JSON Lines)
- Vaultwarden backup (SQLite, attachments, icons, RSA keys, config)
- Safe restore with dry-run support and 5-second abort window
- Configuration-driven (no hardcoded paths)
- All scripts follow `set -Eeuo pipefail` coding standard

## Quick Start

```bash
# Create config directory
sudo mkdir -p /etc/abf/services
sudo cp config/abf.conf /etc/abf/
sudo cp config/storage.conf /etc/abf/
sudo cp config/services/vaultwarden.conf /etc/abf/services/

# Install the abf command
sudo cp abf /usr/local/bin/abf
sudo chmod +x /usr/local/bin/abf

# Validate configuration
abf config check

# Create a backup
abf backup vaultwarden

# List backups
abf list vaultwarden

# Restore (dry-run first)
abf restore vaultwarden --dry-run
```

## Project Structure

```
abf               CLI entry point
lib/              Core engine libraries (config, logging, pipeline)
services/         Service plugin modules (manifest.conf + <name>/module.sh)
config/           Default configuration files
docs/             Documentation
scripts/          Helper scripts (install, test)
tests/            Test suite
storage/          Reserved for storage plugins (Milestone 2+)
```

## Documentation

- [Installation](docs/installation.md)
- [Configuration](docs/configuration.md)
- [Backup](docs/backup.md)
- [Restore](docs/restore.md)
- [Troubleshooting](docs/troubleshooting.md)

## License

MIT
