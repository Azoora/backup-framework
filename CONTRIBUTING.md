# Contributing

Thanks for your interest in the Backup Framework.  
This project follows a conservative, test-first approach.

---

## Quick Start

```bash
git clone <repo>
cd backup-framework
bash scripts/test.sh
```

All tests must pass before any contribution is accepted.

---

## Code Standards

1. **Bash** — All scripts must begin with `set -Eeuo pipefail`.
2. **Functions** — Framework functions are prefixed `abf_`; internal helpers are prefixed `_abf_`.
3. **Exit codes** — Use the standardized codes from `core/exit_codes.sh`. Never use bare numeric exit codes.
4. **Naming** — `snake_case` for variables and functions.
5. **No hardcoded paths** — Everything must be configurable via environment or `.conf` files.

---

## How to Add a Service

1. Add the service name to `services/manifest.conf`.
2. Create `services/<name>/module.sh` implementing all lifecycle hooks:
   - `service_pre_backup` / `service_backup` / `service_verify_backup` / `service_post_backup`
   - `service_pre_restore` / `service_restore` / `service_verify_restore` / `service_post_restore`
3. Create `config/services/<name>.conf` with user-settable defaults.
4. Create `tests/test_<name>.sh` with tests for all hook functions.
5. Run `bash scripts/test.sh` and verify all tests pass.

## How to Add a Storage Backend

1. Add the backend name to `storage/manifest.conf`.
2. Create `storage/<name>/module.sh` defining `storage_get_repo_url()`.
3. Create `config/storage/<name>.conf` with backend-specific settings.
4. Run the full test suite.

## How to Add a Destination

1. Add the destination name to `destinations/manifest.conf`.
2. Create `destinations/<name>/module.sh` defining:
   - `destination_sync <repo_path>` — syncs the repository to the destination. Return 0 on success, non-zero on failure.
   - `destination_name` (optional) — returns a human-readable display name for the summary output.
3. Add configuration defaults to `destinations/<name>/destination.conf`.
4. Create `tests/test_destination_<name>.sh` with tests for all functions.
5. Run `bash scripts/test.sh` and verify all tests pass.

---

## Testing

```bash
# Run all tests
bash scripts/test.sh

# Run specific test files
bash scripts/test.sh test_vaultwarden test_restic

# Run with debug output
ABF_VERBOSE=true bash scripts/test.sh test_config
```

All contributions must include tests for new functionality.

---

## Commit Messages

Use Conventional Commits:

```
feat(scope): description

fix(scope): description

docs(scope): description
```

---

## Pull Request Process

1. Ensure all tests pass.
2. Update documentation if adding or changing features.
3. Update `CHANGELOG.md` under the `## Unreleased` section.
4. Open a pull request with a clear description of the change.
