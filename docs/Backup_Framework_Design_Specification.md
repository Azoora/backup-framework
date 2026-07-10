# Backup Framework Design Specification

**Version:** 0.1.0 (Draft)

**Status:** Active

**Last Updated:** July 2026

---

# 1. Vision

Backup Framework is a production-grade, modular backup platform designed to reliably protect self-hosted infrastructure.

It is **not** a collection of backup scripts.

It is a reusable backup engine capable of protecting any application, database, filesystem, or Docker service with minimal configuration.

The framework should be simple to operate while remaining highly reliable, secure, and extensible.

---

# 2. Design Principles

The framework must always prioritize:

- Reliability over speed
- Safety over convenience
- Simplicity over cleverness
- Recoverability over backup creation
- Automation over manual work
- Configuration over hardcoded logic
- Reusability over application-specific code

Every design decision should follow these principles.

---

# 3. Goals

The framework should provide:

- Production-grade reliability
- Secure encrypted backups
- Easy restoration
- Modular architecture
- Plugin-based services
- Plugin-based storage
- Automatic verification
- Automatic notifications
- Detailed logging
- Easy maintenance

The framework should support both manual and scheduled execution.

---

# 4. Non-Goals

The framework should NOT:

- Invent custom encryption algorithms
- Invent custom archive formats
- Reimplement existing mature backup software
- Depend on GUI applications
- Require application-specific code inside the core engine
- Require editing scripts to add a new application

---

# 5. Supported Services

Initially

- Vaultwarden

Future

- Immich
- Jellyfin
- Audiobookshelf
- Navidrome
- Linkwarden
- Karakeep
- PostgreSQL
- MariaDB
- Redis
- SQLite
- Custom Docker containers
- Arbitrary folders

Adding a new service should require only a configuration file or service plugin.

---

# 6. Supported Storage

Primary

- OneDrive (Rclone)

Secondary

- Umbrel Home Server

Future

- S3
- Backblaze B2
- Wasabi
- Google Drive
- Dropbox
- Local USB
- External NAS
- SSH Servers
- Additional VPS

Storage implementations must be modular.

---

# 7. Architecture

```
               Backup Framework

                    CLI

                     │

              Core Engine

     ┌────────┼────────┐

Configuration  Logging  Notifications

     │                    │

Service Plugins     Storage Plugins

     │                    │

Vaultwarden       OneDrive

Immich            Umbrel

Jellyfin          S3

etc               etc
```

The Core Engine must never contain application-specific logic.

---

# 8. Directory Structure

```
backup-framework/

docs/
config/
services/
storage/
scripts/
logs/
cache/
temp/
tests/
examples/

README.md
CHANGELOG.md
LICENSE
```

---

# 9. Core Engine Responsibilities

The core engine is responsible for:

- Reading configuration
- Loading plugins
- Running backup jobs
- Running restore jobs
- Logging
- Notifications
- Verification
- Scheduling integration
- Cleanup
- Error handling

It should never know how Vaultwarden or Immich works internally.

---

# 10. Backup Pipeline

Every backup should follow exactly the same lifecycle.

```
Pre-flight checks

↓

Validate configuration

↓

Verify storage

↓

Verify free disk

↓

Verify service

↓

Prepare backup

↓

Create backup

↓

Compress (if applicable)

↓

Encrypt

↓

Upload

↓

Verify

↓

Cleanup

↓

Notifications

↓

Logging
```

No step should silently fail.

---

# 11. Restore Pipeline

Restore should always support:

- Snapshot listing
- Dry run
- Full restore
- Selective restore
- Integrity verification
- Rollback protection

Restoring data should never overwrite existing data without confirmation.

---

# 12. Encryption

Encryption is mandatory.

The framework should use:

- Restic

Do not implement custom encryption.

Repository passwords should never be hardcoded.

Passwords should be stored securely.

---

# 13. Notifications

Support SMTP.

Notification levels:

- Success
- Warning
- Failed

Emails should include:

- Timestamp
- Hostname
- Duration
- Service
- Backup size
- Repository
- Snapshot ID
- Upload destination
- Verification result
- Errors (if any)

---

# 14. Logging

Every run must generate:

Human readable log

Machine readable log

Exit code

Logs should be timestamped.

Errors should contain meaningful diagnostics.

---

# 15. Configuration

Configuration should be separated into:

```
config/

abf.conf

storage.conf

smtp.conf

services/

vaultwarden.conf

immich.conf

etc
```

Nothing should be hardcoded.

---

# 16. Vaultwarden Module

The first implementation should support:

Backup:

- SQLite database
- Attachments
- Icon cache
- RSA keys
- Configuration
- Temporary files (optional)

Restore:

Restore every component safely.

---

# 17. Command Line Interface

Future CLI:

```
backup backup vaultwarden

backup backup all

backup restore vaultwarden

backup verify

backup doctor

backup status

backup list

backup config check
```

CLI output should be clean and readable.

---

# 18. Scheduling

The framework itself should NOT install cron jobs automatically.

It should provide examples for:

- Cron
- Systemd Timers

Scheduling should remain optional.

---

# 19. Documentation

Every feature must be documented.

Minimum documentation:

- Installation
- Configuration
- Backup
- Restore
- Troubleshooting
- Storage
- Notifications
- Adding Services

---

# 20. Coding Standards

All shell scripts should begin with:

```bash
set -Eeuo pipefail
```

Requirements:

- Defensive programming
- No duplicated logic
- Meaningful variable names
- Proper error handling
- Consistent logging
- Modular functions
- Small reusable scripts
- Extensive comments where needed

---

# 21. Milestones

## Milestone 1

- Project structure
- CLI
- Configuration loader
- Logging
- Vaultwarden backup
- Vaultwarden restore
- Documentation

---

## Milestone 2

- Restic integration
- OneDrive support
- Email notifications
- Verification
- Retention

---

## Milestone 3

- Umbrel replication
- Status
- Doctor
- Health checks
- Cleanup

---

## Milestone 4

- Plugin system
- Additional services
- Integration testing

---

# 22. Future Roadmap

Potential future enhancements:

- Web dashboard
- Metrics
- Prometheus exporter
- Grafana dashboard
- Webhooks
- Discord notifications
- Telegram notifications
- Slack notifications
- Multi-node backup
- Snapshot browser
- Automatic restore testing
- Deduplicated cloud replication

---

# 23. Success Criteria

The project will be considered production-ready when:

- A backup can be created with one command.
- A restore can be completed with one command.
- Every backup is encrypted.
- Every backup is verified.
- Every failure generates an alert.
- Every operation is logged.
- New services can be added without modifying the Core Engine.

---

# 24. Development Workflow

The AI coding assistant should:

1. Read this specification before making changes.
2. Implement only one milestone at a time.
3. Explain all design decisions.
4. Wait for approval before proceeding.
5. Never violate this specification without explicitly proposing a revision.

This document is the project's single source of truth.