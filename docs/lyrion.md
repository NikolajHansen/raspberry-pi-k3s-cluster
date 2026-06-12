# Lyrion Music Server

[Lyrion Music Server](https://lyrion.org) (formerly Logitech Media Server) streams music to Squeezebox hardware players and software clients.

## Endpoints

| Service | Address |
|---|---|
| Web UI (Material Skin) | http://lyrion.example.com:9000/material |
| Squeezebox protocol | TCP/UDP 3483 |

## Storage

| Mount | Source | Access |
|---|---|---|
| `/media` | `atlas.example.com:/greenlake/media` | Read-only, NFSv3, rsize/wsize=128K |
| `/config` | `atlas.example.com:/greenlake/k3s/lyrion` | Read-write, NFS, nolock |

The `/config` mount persists all state across pod restarts and rescheduling:
- `prefs/` — server and plugin settings
- `prefs/persist.db` — main SQLite database (settings, player state)
- `cache/library.db` — music library index
- `cache/artwork.db` — album art cache
- `cache/InstalledPlugins/` — downloaded plugins (Material Skin, Spotty, Qobuz etc.)
- `logs/` — server logs
- `playlists/` — saved playlists

> **Note**: Lyrion 9+ supports SQLite only. MySQL/MariaDB support was dropped in LMS 9.0.

### SQLite WAL mode on NFS

SQLite uses WAL (Write-Ahead Logging) by default, which relies on shared memory files (`.db-wal`, `.db-shm`) that do not work reliably over NFS — even with `nolock`. An init container runs before LMS starts and:

1. Validates each `.db` file is a valid SQLite database
2. Deletes stale `-wal` and `-shm` files
3. Switches journal mode to `DELETE` (safe for single-writer NFS use)

## Networking

- **VIP**: `10.0.0.60` via MetalLB — stable across pod rescheduling
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
| MusicArtistInfo | Artist biographies and info |
| RadioNowPlaying | Radio station metadata |

### Spotify (Spotty) setup

1. Create a Spotify Developer app at https://developer.spotify.com/dashboard
2. Add redirect URI: `https://api.lms-community.org/auth/callback`
3. In LMS → Settings → Advanced → Spotty → enter Client ID and Secret
4. Authenticate via the plugin settings page

> **Important**: Open LMS via the VIP (`http://10.0.0.60:9000`) when authenticating — Spotty uses the host address to build the OAuth callback URL. With `hostNetwork: true` this will be the node IP (routable from browser).

## Deployment

```bash
k3s-ansible lyrion.yml
```

## Screensaver (SB2/physical players)

To show a clock on the display when a player is off:

**Settings → Player → [player] → Basic Settings → Screensaver when off → Date and Time**

If "Date and Time" is not available, install the `DateTime` plugin via **Settings → Plugins**.
