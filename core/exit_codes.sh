# ---------------------------------------------------------------------------
# exit_codes.sh  --  Standardized framework exit codes
#
# Every module must use these codes instead of inventing new ones.
# Source this file in any script that returns exit codes.
# ---------------------------------------------------------------------------

ABF_EXIT_OK=0
ABF_EXIT_CONFIG_ERROR=1
ABF_EXIT_SERVICE_NOT_FOUND=2
ABF_EXIT_BACKUP_FAILED=3
ABF_EXIT_RESTORE_FAILED=4
ABF_EXIT_VERIFICATION_FAILED=5
ABF_EXIT_STORAGE_ERROR=6
ABF_EXIT_NOTIFICATION_ERROR=7
ABF_EXIT_INTERNAL_ERROR=99
