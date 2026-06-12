#!/bin/sh
# Setup app-oriented NFS storage for k3s cluster on atlas.barnabas.dk
#
# Creates a ZFS dataset per application under greenlake/k3s/ with a
# single NFS export for the entire k3s subnet (192.168.1.0/24).
#
# Data follows the pod, not the node — pods can move freely between
# nodes and still access their persistent data.
#
# To add a new application, add it to the `apps` list below and re-run.
# The script is idempotent — existing datasets and exports are skipped.
#
# Usage (run as root on atlas.barnabas.dk):
#   su -
#   sh scripts/atlas-k3s-storage-setup.sh
#
# Or with sudo:
#   sudo sh scripts/atlas-k3s-storage-setup.sh

set -e

POOL="greenlake"
K3S_SUBNET="192.168.1.0/24"

# Applications to create datasets for.
# Add new apps here as needed — one per line.
apps="
lyrion
"

# Verify running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root (su - or sudo)"
  exit 1
fi

# Create parent dataset if it doesn't exist
if ! zfs list ${POOL}/k3s > /dev/null 2>&1; then
  echo "==> Creating ${POOL}/k3s"
  zfs create ${POOL}/k3s
else
  echo "==> ${POOL}/k3s already exists, skipping"
fi

# Create per-app datasets
for app in $apps; do
  dataset="${POOL}/k3s/${app}"
  if ! zfs list ${dataset} > /dev/null 2>&1; then
    echo "==> Creating ${dataset}"
    zfs create ${dataset}
  else
    echo "==> ${dataset} already exists, skipping"
  fi
done

# Add NFS export for entire k3s tree (only if not already present)
if ! grep -q "k3s app storage" /etc/exports; then
  echo "" >> /etc/exports
  echo "# k3s app storage - generated $(date +%Y-%m-%d)" >> /etc/exports
  printf "/%s/k3s\t-alldirs -maproot=root\t%s\n" "${POOL}" "${K3S_SUBNET}" >> /etc/exports
  echo "==> /etc/exports updated"
else
  echo "==> /etc/exports already contains k3s entry, skipping"
fi

echo ""
echo "==> Current /etc/exports:"
cat /etc/exports

echo ""
echo "==> Reloading NFS exports"
service nfsd restart

echo ""
echo "==> Done. Verify with:"
echo "    showmount -e localhost"
echo "    zfs list -r ${POOL}/k3s"
