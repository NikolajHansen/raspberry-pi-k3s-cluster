# Persistent Storage

Application data is stored on `atlas.example.com` (ZFS pool: `greenlake`) and exported via NFS to the k3s subnet.

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
zfs set sharenfs="-alldirs -maproot=root -network 10.0.0.0/24" greenlake/k3s

# Music library (read-only, set via sharenfs on dataset)
zfs set sharenfs="-mapall=media:media -network 10.0.0.0/24" greenlake/media
```

Verify with:
```bash
showmount -e localhost
```

## SQLite on NFS

LMS uses SQLite with WAL (Write-Ahead Logging) by default. WAL requires shared memory files (`.db-wal`, `.db-shm`) which do not work reliably over NFS. The NFS PV for `/config` uses `nolock` mount option, and an init container converts all databases to `DELETE` journal mode before LMS starts.

## NFS mount options

| Volume | Options |
|---|---|
| `/config` (lyrion-config-pv) | `nolock`, `fsc` |
| `/media` (lyrion-media-pv) | `vers=3`, `noatime`, `nodiratime`, `rsize=131072`, `wsize=131072` |

## Setup

Run once as root on `atlas.example.com` to create datasets and configure NFS exports:

```bash
sudo sh scripts/atlas-k3s-storage-setup.sh
```

The script is idempotent — existing datasets and sharenfs properties are skipped.

To add a new application, append it to the `apps` list in the script and re-run.

## Adding storage for a new application

1. Add the app name to `apps` in `scripts/atlas-k3s-storage-setup.sh`
2. Re-run the script on atlas
3. Add a PV/PVC to the app's Kubernetes manifest pointing to `/greenlake/k3s/<appname>`
