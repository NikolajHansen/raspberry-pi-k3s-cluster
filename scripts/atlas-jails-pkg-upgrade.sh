#!/bin/sh
# Run `pkg upgrade` in every jail found in a directory (FreeBSD).
#
# Each subdirectory is treated as a jail root. Layouts supported:
#   <dir>/<jail>/etc/...        (root directly in the jail folder)
#   <dir>/<jail>/root/etc/...   (Bastille-style)
# pkg runs with `-c <root>` (chroot), so it works for running and stopped jails.
#
# Usage (run on atlas as root):
#   sh scripts/atlas-jails-pkg-upgrade.sh [-n] [-r] [-j name] [directory]
#     -n         dry run (pkg upgrade -n), no changes
#     -r         restart each jail that had packages upgraded
#     -j name    only this jail (subdirectory name)
#     directory  folder containing the jails (default: /usr/local/jails/containers)
#
# Or run remotely:
#   ssh atlas 'sudo sh /path/to/atlas-jails-pkg-upgrade.sh -n'

set -u

DIR="/usr/local/jails/containers"
DRY=0
RESTART=0
ONLY=""

while getopts "nrj:" opt; do
  case "$opt" in
    n) DRY=1 ;;
    r) RESTART=1 ;;
    j) ONLY="$OPTARG" ;;
    *) echo "Usage: $0 [-n] [-r] [-j name] [directory]"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] && DIR="$1"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run as root"
  exit 1
fi

if [ ! -d "$DIR" ]; then
  echo "ERROR: Directory not found: $DIR"
  exit 1
fi

OK=""
FAILED=""
SKIPPED=""

for d in "$DIR"/*/; do
  name=$(basename "$d")
  [ -n "$ONLY" ] && [ "$name" != "$ONLY" ] && continue

  if [ -d "${d}root/etc" ]; then
    root="${d}root"
  elif [ -d "${d}etc" ]; then
    root="${d%/}"
  else
    SKIPPED="$SKIPPED $name"
    continue
  fi

  if [ ! -x "$root/usr/sbin/pkg" ] && [ ! -x "$root/usr/local/sbin/pkg" ]; then
    echo "==> [$name] pkg not bootstrapped, skipping"
    SKIPPED="$SKIPPED $name"
    continue
  fi

  echo "==> [$name] pkg update + upgrade ($root)"
  if [ "$DRY" -eq 1 ]; then
    pkg -c "$root" update -q && pkg -c "$root" upgrade -n
    rc=$?
  else
    pkg -c "$root" update -q && pkg -c "$root" upgrade -y
    rc=$?
  fi

  if [ "$rc" -ne 0 ]; then
    echo "!!  [$name] FAILED (exit $rc)"
    FAILED="$FAILED $name"
    continue
  fi
  OK="$OK $name"

  if [ "$RESTART" -eq 1 ] && [ "$DRY" -eq 0 ] && jls -j "$name" >/dev/null 2>&1; then
    echo "==> [$name] restarting jail"
    service jail restart "$name" || FAILED="$FAILED $name(restart)"
  fi
done

echo
echo "==> Summary"
echo "    ok:      ${OK:- none}"
echo "    skipped: ${SKIPPED:- none}"
echo "    failed:  ${FAILED:- none}"

[ -z "$FAILED" ]
