#!/bin/sh
# Setup per-node NFS storage for k3s cluster on atlas.barnabas.dk
#
# Creates a ZFS dataset per node under greenlake/k3s/ with individual
# NFS exports restricted to each node's IP.
#
# Usage (run as root on atlas.barnabas.dk):
#   su -
#   sh scripts/atlas-k3s-storage-setup.sh
#
# Or with sudo:
#   sudo sh scripts/atlas-k3s-storage-setup.sh

set -e

POOL="greenlake"
QUOTA="50G"

# Verify running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root (su - or sudo)"
  exit 1
fi

# Node name -> IP mapping (master01=.50, node01-09=.51-.59)
nodes="master01:192.168.1.50
node01:192.168.1.51
node02:192.168.1.52
node03:192.168.1.53
node04:192.168.1.54
node05:192.168.1.55
node06:192.168.1.56
node07:192.168.1.57
node08:192.168.1.58
node09:192.168.1.59"

# Create parent dataset if it doesn't exist
if ! zfs list ${POOL}/k3s > /dev/null 2>&1; then
  echo "==> Creating ${POOL}/k3s"
  zfs create ${POOL}/k3s
else
  echo "==> ${POOL}/k3s already exists, skipping"
fi

# Create per-node datasets
for entry in $nodes; do
  node=$(echo "$entry" | cut -d: -f1)
  ip=$(echo "$entry" | cut -d: -f2)
  dataset="${POOL}/k3s/${node}"

  if ! zfs list ${dataset} > /dev/null 2>&1; then
    echo "==> Creating ${dataset} (quota: ${QUOTA}, export to ${ip})"
    zfs create ${dataset}
    zfs set quota=${QUOTA} ${dataset}
  else
    echo "==> ${dataset} already exists, skipping"
  fi
done

# Add exports to /etc/exports (only if not already present)
if ! grep -q "k3s node storage" /etc/exports; then
  echo "" >> /etc/exports
  echo "# k3s node storage - generated $(date +%Y-%m-%d)" >> /etc/exports
  for entry in $nodes; do
    node=$(echo "$entry" | cut -d: -f1)
    ip=$(echo "$entry" | cut -d: -f2)
    printf "/%s/k3s/%s\t-maproot=root\t%s\n" "${POOL}" "${node}" "${ip}" >> /etc/exports
  done
  echo "==> /etc/exports updated"
else
  echo "==> /etc/exports already contains k3s entries, skipping"
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
