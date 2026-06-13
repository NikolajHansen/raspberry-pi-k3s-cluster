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
| `/media` | `atlas.barnabas.dk:/greenlake/media` | Read-only, NFSv3, rsize/wsize=128K |
| `/config` | `atlas.barnabas.dk:/greenlake/k3s/lyrion` | Read-write, NFSv3, nolock |

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

Files must be owned by UID 499 (squeezeboxserver inside the container). The NFS root directory needs the correct ownership:

```bash
# On atlas — run once if ownership is wrong
sudo chown 499:100 /greenlake/k3s/lyrion
```

### SQLite WAL mode on NFS

SQLite WAL mode creates `.db-wal` and `.db-shm` shared memory files that do not work reliably over NFS. An init container runs before LMS starts and removes stale `-wal` and `-shm` files. If LMS crashes or is force-killed, stale WAL files may remain — remove them manually on atlas:

```bash
sudo rm -f /greenlake/k3s/lyrion/cache/*.db-wal /greenlake/k3s/lyrion/cache/*.db-shm
sudo rm -f /greenlake/k3s/lyrion/prefs/*.db-wal /greenlake/k3s/lyrion/prefs/*.db-shm
```

Then restart the pod.

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

## Deployment

```bash
k3s-ansible lyrion.yml
```

## Screensaver (SB2/physical players)

To show a clock on the display when a player is off:

**Settings → Player → [player] → Basic Settings → Screensaver when off → Date and Time**

If "Date and Time" is not available, install the `DateTime` plugin via **Settings → Plugins**.
