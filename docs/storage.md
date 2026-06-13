# Persistent Storage

Application data is stored on `atlas.example.com` (ZFS pool: `greenlake`) and exported via NFSv4 to the k3s subnet.

Data follows the **pod, not the node** — pods can be rescheduled freely between nodes without data loss.

## ZFS layout

```
greenlake/
├── media/          # Music library (read-only, shared with Lyrion)
└── k3s/
    └── lyrion/     # Lyrion config, SQLite databases, plugins, artwork cache
```

Each application under `greenlake/k3s/` gets its own ZFS dataset, enabling:
- Independent snapshots and rollbacks per application
- Per-application quotas
- Targeted backups

## NFS export

Exports are configured via the ZFS `sharenfs` property — **not** `/etc/exports`. Mixing the two methods causes exports to be silently ignored on FreeBSD.

```bash
# k3s app storage (read-write, all cluster nodes)
zfs set sharenfs="-alldirs -maproot=root -network 192.168.1.0/24" greenlake/k3s

# Music library (read-only)
zfs set sharenfs="-mapall=media:media -network 192.168.1.0/24" greenlake/media
```

Verify with:
```bash
showmount -e localhost
```

## NFSv4 and UID mapping

All mounts use NFSv4 with `sec=sys` — UIDs are passed numerically. For correct ownership inside containers, the container's UID must exist on all k3s nodes.

- `squeezeboxserver` (uid=499) is created on all nodes by `k3s-cluster.yml`
- `/greenlake/k3s/lyrion` must be owned by uid=499 on atlas:

```bash
ssh atlas 'sudo chown -R 499:100 /greenlake/k3s/lyrion'
```

## NFS mount options

| Volume | Options |
|---|---|
| `/config` (lyrion-config-pv) | `vers=4`, `hard`, `retrans=3`, `noatime`, `nodiratime`, `rsize=131072`, `wsize=131072` |
| `/media` (lyrion-media-pv) | `vers=4`, `hard`, `retrans=3`, `noatime`, `nodiratime`, `rsize=131072`, `wsize=131072` |

`hard` mount mode means the kernel retries NFS operations indefinitely if the server is unreachable — preventing silent data loss. NFSv4 is required for correct SQLite WAL locking.

## SQLite on NFS

Lyrion uses SQLite with WAL (Write-Ahead Log) mode. NFSv4 supports the mandatory locking required for WAL to work correctly.

A `fix-sqlite-wal` init container checkpoints all WALs with `PRAGMA wal_checkpoint(TRUNCATE)` before Lyrion starts, ensuring a clean state after any unclean shutdown.

> **Never delete WAL files manually** — they contain uncommitted data. Let the init container checkpoint them.

## Snapshots

ZFS snapshots provide instant, space-efficient backups. Use `scripts/lyrion-backup.sh` on atlas:

```bash
# Take a snapshot (after scanner.pl has exited)
ssh atlas 'sudo sh scripts/lyrion-backup.sh snapshot'

# List snapshots
ssh atlas 'sudo sh scripts/lyrion-backup.sh list'

# Rollback (scale pod to 0 first)
kubectl -n lyrion scale deployment/lyrion --replicas=0
ssh atlas 'sudo sh scripts/lyrion-backup.sh rollback'
kubectl -n lyrion scale deployment/lyrion --replicas=1
```

## Setup

Run once as root on `atlas.example.com` to create datasets and configure NFS exports:

```bash
sudo sh scripts/atlas-k3s-storage-setup.sh
```

The script is idempotent — existing datasets and sharenfs properties are skipped.

## Adding storage for a new application

1. Add the app name to `apps` in `scripts/atlas-k3s-storage-setup.sh`
2. Re-run the script on atlas
3. Add a PV/PVC to the app's Kubernetes manifest pointing to `/k3s/<appname>` (NFSv4 path, relative to V4 root `/greenlake`)
