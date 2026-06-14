# Lyrion Music Server

[Lyrion Music Server](https://lyrion.org) (formerly Logitech Media Server) streams music to Squeezebox hardware players and software clients.

## Endpoints

| Service | Address |
|---|---|
| Web UI (Material Skin) | http://lyrion.barnabas.dk/material |
| Squeezebox protocol | TCP/UDP 3483 |

## Storage

| Mount | Source | Access |
|---|---|---|
| `/media` | `atlas.example.com:/media` | Read-only, NFSv4, hard, rsize/wsize=128K |
| `/config` | `atlas.example.com:/k3s/lyrion` | Read-write, NFSv4, hard, rsize/wsize=128K |

NFSv4 is required — NFSv3 cannot handle concurrent file access needed by SQLite WAL mode.

The `/config` mount persists all state across pod restarts and rescheduling:
- `prefs/` — server and plugin settings
- `prefs/persist.db` — main SQLite database (settings, player state)
- `prefs/plugin/` — per-plugin preferences (spotty.prefs, qobuz.prefs, material-skin.prefs etc.)
- `prefs/playlists/` — saved playlists
- `cache/library.db` — music library index (local + Spotty + Qobuz)
- `cache/artwork.db` — album art cache
- `cache/InstalledPlugins/` — downloaded plugins (Material Skin, Spotty, Qobuz etc.)
- `logs/` — server logs

> **Note**: Lyrion 9+ supports SQLite only. MySQL/MariaDB support was dropped in LMS 9.0.

### File ownership on NFS

Files must be owned by UID 499 (`squeezeboxserver` inside the container). NFSv4 maps UIDs numerically (`sec=sys`) — the `squeezeboxserver` user (uid=499) is created on all k3s nodes by `k3s-cluster.yml`. If ownership is wrong on atlas:

```bash
ssh atlas 'sudo chown -R 499:100 /greenlake/k3s/lyrion'
```

### SQLite WAL mode

SQLite WAL mode creates `.db-wal` and `.db-shm` files alongside each database. A `fix-sqlite-wal` init container checkpoints all WALs using `PRAGMA wal_checkpoint(TRUNCATE)` before Lyrion starts.

> **Never delete WAL files manually** — checkpoint first or let Lyrion recover them on startup.

If a database is corrupt (not valid SQLite), the init container removes it and Lyrion rebuilds from scratch.

### ZFS snapshots (backup/restore)

Use `scripts/lyrion-backup.sh` on atlas after a full successful scan (wait for `scanner.pl` to exit):

```bash
# Take a snapshot
ssh atlas 'sudo sh scripts/lyrion-backup.sh snapshot'

# List snapshots
ssh atlas 'sudo sh scripts/lyrion-backup.sh list'

# Restore (scale pod to 0 first)
kubectl -n lyrion scale deployment/lyrion --replicas=0
ssh atlas 'sudo sh scripts/lyrion-backup.sh rollback'
kubectl -n lyrion scale deployment/lyrion --replicas=1
```

## Networking

- **VIP**: `192.168.1.61` via MetalLB — stable across pod rescheduling
- **Web UI**: port 80 on VIP (MetalLB maps 80 → pod port 9000)
- **hostNetwork**: enabled — required for:
  - Squeezebox UDP broadcast discovery on the LAN
  - Spotty (Spotify) OAuth callback URL resolves to node IP (routable from browser)

## Plugins

Installed plugins (persisted in `/config/cache/InstalledPlugins/`):

| Plugin | Purpose |
|---|---|
| Material Skin | Modern web UI |
| Spotty | Spotify integration |
| Qobuz | Qobuz streaming |
| MusicArtistInfo | Artist biographies and photos |
| RadioNowPlaying | Radio station metadata |

### Spotify (Spotty) setup

1. Create a Spotify Developer app at https://developer.spotify.com/dashboard
2. Add redirect URI: `https://api.lms-community.org/auth/callback`
3. In LMS → Settings → Advanced → Spotty → enter Client ID and Secret
4. Authenticate via the plugin settings page

> **Important**: Open LMS via the node IP (`http://192.168.1.5x:9000`, e.g. 192.168.1.56) when authenticating — Spotty uses the host address to build the OAuth callback URL. With `hostNetwork: true` this will be the node IP (routable from browser).

### Qobuz setup

1. In LMS → Settings → Advanced → Qobuz → enter username and password
2. A full library scan will import your Qobuz favourites and albums

## Media scan

A full scan runs automatically on startup and can be triggered manually via Settings → Advanced → Rescan. Approximate durations observed:

| Phase | Duration |
|---|---|
| Local music (343 tracks) | ~5 sec |
| Spotify (Spotty) library | ~350 sec |
| Qobuz library | ~278 sec |
| MusicArtistInfo (1501 artists) | ~55 sec |
| Artwork precache (544 albums) | ~225 sec |

## Init containers

The pod runs two init containers before Lyrion starts:

| Container | Purpose |
|---|---|
| `check-mounts` | Verifies `/config` is writable and `/media/music` is readable (retries 60s) |
| `fix-sqlite-wal` | Checkpoints all SQLite WALs; removes corrupt non-SQLite files |

## Resource limits

| | Request | Limit |
|---|---|---|
| CPU | 250m | 2000m |
| Memory | 512Mi | 1500Mi |

## Graceful shutdown

A `preStop` hook sends `stopserver` to the Lyrion CLI port (9090) via `bash /dev/tcp`, waits for the perl process to exit (up to 30s), then runs `sync`. `terminationGracePeriodSeconds` is 60.

## Deployment

```bash
k3s-ansible lyrion.yml
```

Or directly with Helm (from a machine with kubeconfig and the chart):

```bash
helm upgrade --install lyrion charts/lyrion \
  --set nfsServer=atlas.example.com \
  --set vip=10.0.0.61 \
  --set hostname=lyrion.example.com
```

## Screensaver (SB2/physical players)

To show a clock on the display when a player is off:

**Settings → Player → [player] → Basic Settings → Screensaver when off → Date and Time**

If "Date and Time" is not available, install the `DateTime` plugin via **Settings → Plugins**.
