#!/bin/sh
# Lyrion ZFS snapshot backup/restore on the NAS server.
#
# ZFS snapshots are instant, atomic, and space-efficient (copy-on-write).
# Snapshots live in greenlake/k3s/lyrion@<name> and can be listed, rolled
# back, or cloned without touching the live data.
#
# Usage (run on atlas as root):
#   Snapshot: sh scripts/lyrion-backup.sh snapshot
#   List:     sh scripts/lyrion-backup.sh list
#   Rollback: sh scripts/lyrion-backup.sh rollback [snapshot]
#
# Or run remotely:
#   ssh atlas 'sudo sh /path/to/lyrion-backup.sh snapshot'

set -e

DATASET="greenlake/k3s/lyrion"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
KEEP=10

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run as root"
  exit 1
fi

case "${1:-snapshot}" in

  snapshot)
    SNAP="${DATASET}@lyrion-${TIMESTAMP}"
    echo "==> Creating ZFS snapshot: ${SNAP}"
    zfs snapshot "${SNAP}"
    echo "==> Done."

    # Prune old snapshots, keep most recent $KEEP
    OLD=$(zfs list -t snapshot -H -o name -s creation -r "${DATASET}" \
          | grep "@lyrion-" | head -n -${KEEP})
    if [ -n "$OLD" ]; then
      echo "==> Pruning old snapshots:"
      echo "$OLD" | while read -r snap; do
        echo "    Destroying: $snap"
        zfs destroy "$snap"
      done
    fi

    echo "==> Current snapshots:"
    zfs list -t snapshot -H -o name,used,creation -r "${DATASET}" | grep "@lyrion-"
    ;;

  list)
    echo "==> Snapshots for ${DATASET}:"
    zfs list -t snapshot -o name,used,creation -r "${DATASET}" | grep "@lyrion-" || echo "    (none)"
    ;;

  rollback)
    SNAP="${2:-$(zfs list -t snapshot -H -o name -s creation -r "${DATASET}" | grep "@lyrion-" | tail -1)}"
    if [ -z "$SNAP" ]; then
      echo "ERROR: No snapshot found. Run 'snapshot' first."
      exit 1
    fi
    echo "==> Rolling back to: ${SNAP}"
    echo "    WARNING: All changes since this snapshot will be lost!"
    echo "    Make sure Lyrion is scaled to 0 first:"
    echo "    kubectl -n lyrion scale deployment/lyrion --replicas=0"
    printf "    Continue? [y/N] "
    read -r answer
    [ "$answer" = "y" ] || [ "$answer" = "Y" ] || { echo "Aborted."; exit 0; }
    zfs rollback -r "${SNAP}"
    echo "==> Rollback complete. Scale Lyrion back up:"
    echo "    kubectl -n lyrion scale deployment/lyrion --replicas=1"
    ;;

  *)
    echo "Usage: $0 {snapshot|list|rollback [snapshot]}"
    exit 1
    ;;
esac
