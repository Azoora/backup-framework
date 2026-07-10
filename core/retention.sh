# ---------------------------------------------------------------------------
# retention.sh  --  Backup retention policy enforcement
#
# Uses restic forget to remove old snapshots based on the configured
# retention policy.  Policy is set in abf.conf:
#   ABF_RETENTION_KEEP_DAILY
#   ABF_RETENTION_KEEP_WEEKLY
#   ABF_RETENTION_KEEP_MONTHLY
#   ABF_RETENTION_KEEP_YEARLY
# ---------------------------------------------------------------------------

abf_apply_retention() {
    local service_name="$1"
    abf_restic_forget "$service_name"
}
