# Lyrion Music Server

[Lyrion Music Server](https://lyrion.org) (formerly Logitech Media Server) streams music to Squeezebox hardware players and software clients.

## Endpoints

| Service | Address |
|---|---|
| Web UI | http://lyrion.example.com:9000 |
| Squeezebox protocol | TCP/UDP 3483 |

## Storage

| Mount | Source | Access |
|---|---|---|
| `/media` | `atlas.example.com:/greenlake/media` | Read-only, NFSv3 |
| `/config` | `atlas.example.com:/greenlake/k3s/lyrion` | Read-write, NFS |

The `/config` mount persists across pod restarts and rescheduling:
- Lyrion SQLite database (`squeezebox.db`)
- Downloaded album artwork and inlays
- Plugin data and preferences

> **Note**: Lyrion 9+ supports SQLite only. MySQL/MariaDB support was dropped in LMS 9.0.

## Networking

- **VIP**: `10.0.0.60` via MetalLB — stable across pod rescheduling
- **hostNetwork**: enabled — required for Squeezebox UDP broadcast discovery on the LAN

## Deployment

The manifest is generated from a Jinja2 template using site-specific variables:

```bash
k3s-ansible lyrion.yml
```

Or render and apply manually:

```bash
ansible -i ansible/inventory/inventory.yml localhost \
  -m template -a "src=k8s/lyrion.yaml.j2 dest=/tmp/lyrion.yaml" \
  -e @~/k3s-site.yml
kubectl apply -f /tmp/lyrion.yaml
```

## Screensaver (SB2/physical players)

To show a clock on the display when a player is off:

**Settings → Player → [player] → Basic Settings → Screensaver when off → Date and Time**

If "Date and Time" is not available, install the `DateTime` plugin via **Settings → Plugins**.
