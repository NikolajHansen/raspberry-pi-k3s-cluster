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

# NFSv4 requires uid/gid to exist on the server for correct ID mapping.
# squeezeboxserver uid=499 gid=100 matches the Lyrion container user.
LYRION_UID=499
LYRION_GID=100
LYRION_USER=squeezeboxserver
LYRION_GROUP=users

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

# Create group and user for NFSv4 ID mapping (Lyrion container user)
if pw groupshow ${LYRION_GROUP} > /dev/null 2>&1; then
  echo "==> Group '${LYRION_GROUP}' (gid ${LYRION_GID}) already exists"
else
  echo "==> Creating group '${LYRION_GROUP}' (gid ${LYRION_GID})"
  pw groupadd -n ${LYRION_GROUP} -g ${LYRION_GID}
fi

if pw usershow ${LYRION_USER} > /dev/null 2>&1; then
  echo "==> User '${LYRION_USER}' (uid ${LYRION_UID}) already exists"
else
  echo "==> Creating user '${LYRION_USER}' (uid ${LYRION_UID})"
  pw useradd -n ${LYRION_USER} -u ${LYRION_UID} -g ${LYRION_GID} -d /nonexistent -s /usr/sbin/nologin
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

# Enable NFS export via ZFS sharenfs property (same approach as greenlake/media)
# This is the correct method on FreeBSD — do not mix with /etc/exports
current_sharenfs=$(zfs get -H -o value sharenfs ${POOL}/k3s)
if [ "$current_sharenfs" = "off" ]; then
  echo "==> Setting sharenfs on ${POOL}/k3s"
  zfs set sharenfs="-alldirs -maproot=root -network ${K3S_SUBNET}" ${POOL}/k3s
else
  echo "==> sharenfs already set on ${POOL}/k3s, skipping"
fi

echo ""
echo "==> Done. Verify with:"
echo "    showmount -e localhost"
echo "    zfs list -r ${POOL}/k3s"
