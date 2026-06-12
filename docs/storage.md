# Persistent Storage

Application data is stored on `atlas.example.com` (ZFS pool: `greenlake`) and exported via NFS to the k3s subnet.

Data follows the **pod, not the node** — pods can be rescheduled freely between nodes without data loss.

## ZFS layout

```
greenlake/
├── media/          # Music library (read-only, shared with Lyrion)
└── k3s/
    └── lyrion/     # Lyrion config, SQLite database, artwork cache
```

Each application under `greenlake/k3s/` gets its own ZFS dataset, enabling:
- Independent snapshots and rollbacks per application
- Per-application quotas
- Targeted backups

## NFS export

A single export covers the entire k3s application tree, accessible to all cluster nodes:

```
/greenlake/k3s   -alldirs -maproot=root   10.0.0.0/24
```

The music library is exported separately (read-only):

```
/greenlake/media   -maproot=root   10.0.0.0/24
```

## Setup

Run once as root on `atlas.example.com` to create datasets and configure NFS exports:

```bash
su -
sh scripts/atlas-k3s-storage-setup.sh
```

The script is idempotent — existing datasets and export entries are skipped.

To add a new application, append it to the `apps` list in the script and re-run.

## Adding storage for a new application

1. Add the app name to `apps` in `scripts/atlas-k3s-storage-setup.sh`
2. Re-run the script on atlas
3. Add a PV/PVC to the app's Kubernetes manifest pointing to `/greenlake/k3s/<appname>`
