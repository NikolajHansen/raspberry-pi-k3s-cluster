# Centralized Logging

## Architecture overview

```
Pi nodes (all 10)
  ├── journald  ──►  /run/log/journal  (RAM only — Storage=volatile)
  │                       │
  └── rsyslog              │
        ├── imjournal ─────┘  node/system logs  ──────────────┐
        └── imfile (/var/log/pods/*/*/*log)  pod logs (local6) ┤  TCP/514
                                                               │
                                        atlas.example.com:514 ◄┘
                                        (FreeBSD jail: syslog-receiver)
                                              └── syslog-ng
                                                    ├── /mnt/logs/nodes/<host>/YYYY-MM-DD.log
                                                    └── /mnt/logs/pods/<host>/YYYY-MM-DD.log
                                        (ZFS: greenlake/logs/k3s-cluster, rotated 30 days)
```

All cluster nodes are **stateless by design** — journald runs in volatile
(RAM-only) mode; no log data is persisted to SD cards.  Logs are forwarded
in real-time over TCP to atlas and only stored there.

## What is forwarded

| Source | Mechanism | syslog facility | Forwarded |
|--------|-----------|-----------------|-----------|
| k3s server / agent | `imjournal` | default | ✓ |
| containerd / container runtime | `imjournal` | default | ✓ |
| kernel / boot messages | `kern.*` | kernel | ✓ |
| auth / sudo | `auth.*` | auth | ✓ |
| All warnings and above | `*.warn` | various | ✓ |
| Kubernetes pod stdout/stderr | `imfile` (pod log files) | `local6` | ✓ |
| Debug / cron below warning | — | — | ✗ (noise reduction) |

Pod logs use syslog facility **local6** so syslog-ng on atlas routes them to
a separate `/mnt/logs/pods/` tree, distinct from node/system logs.

## SD card protection — volatile journald

Node SD cards are protected from log write wear by setting:

```ini
# /etc/systemd/journald.conf.d/volatile.conf  (deployed by remote-logging.yml)
[Journal]
Storage=volatile
```

This makes journald store its ring buffer in `/run/log/journal` (tmpfs, RAM
only).  rsyslog's `imjournal` still reads from it in real-time and forwards
everything to atlas.  If a node reboots, journal entries since the last rsyslog
flush are lost, but all forwarded entries are safe on atlas.

## Cluster-side configuration (Ansible-managed)

The playbook `ansible/playbooks/remote-logging.yml` installs rsyslog and
deploys a drop-in forwarding config to `/etc/rsyslog.d/90-remote.conf` on
every node.  The template lives at `ansible/templates/rsyslog-remote.conf.j2`.

The `syslog_server` variable defaults to `syslog.example.com` and must be
set in `~/k3s-site.yml`:

```yaml
# ~/k3s-site.yml (site-specific, not committed)
syslog_server: syslog.example.com   # FreeBSD host running the syslog receiver
```

Key design decisions:
- **TCP** (not UDP) — reliable delivery; messages are not silently dropped if
  atlas is briefly unreachable (rsyslog queues in memory).
- `imjournal` — reads from the systemd journal directly, so k3s and container
  logs that go to the journal (not syslog) are captured correctly.
- `imfile` glob on `/var/log/pods/*/*/*log` — captures structured pod stdout/stderr
  with syslog facility `local6` for separate routing on atlas.
- **No on-disk queue** — rsyslog configured `queue.saveOnShutdown="off"` to
  avoid any SD card writes.
- Drop-in file under `rsyslog.d/` — avoids touching the OS-default
  `/etc/rsyslog.conf`, making the role idempotent and upgrade-safe.

## Atlas-side configuration (Ansible-managed)

Atlas is a FreeBSD host with a dedicated `syslog-receiver` jail.  It is
managed via `ansible/playbooks/atlas-syslog-config.yml` which deploys
`ansible/templates/syslog-ng.conf.j2` into the jail.

Atlas must be added to inventory under the `nas` group (see
`k3s-inventory.yml.example`) and to `~/k3s-inventory.yml`.

```yaml
# ~/k3s-inventory.yml excerpt
nas:
  hosts:
    atlas.example.com:
      ansible_user: nikolaj
      ansible_python_interpreter: /usr/local/bin/python3
```

To apply config changes to atlas:

```sh
k3s-ansible atlas-syslog-config.yml
```

### First-time jail setup

A fully automated setup script is provided at `scripts/atlas-syslog-jail-setup.sh`.
Copy it to atlas and run it as root once:

```sh
scp scripts/atlas-syslog-jail-setup.sh atlas.example.com:~/
ssh atlas.example.com
sudo sh ~/setup-syslog-jail.sh
```

The script creates the ZFS dataset, nullfs-based jail, installs syslog-ng,
and configures initial routing.  All subsequent config changes go through
the Ansible playbook.

#### Gotchas discovered during setup

- `jail -c <name>` does not read `/etc/jail.conf.d/` — use `service jail start <name>`.
- `master.passwd` in the jail must be populated and `pwd_mkdb` run or the
  jail fails with `initgroups root: Operation not permitted`.
- Do not pre-assign the jail IP to the host NIC — let `service jail start` do it.
- `mount.procfs` in `jail.conf` and a `proc` `fstab` entry are mutually exclusive;
  use only one.

### syslog-ng routing on atlas

| Filter | Destination |
|--------|------------|
| `facility(local6)` — pod logs | `/mnt/logs/pods/<host>/YYYY-MM-DD.log` |
| Everything else — node/system logs | `/mnt/logs/nodes/<host>/YYYY-MM-DD.log` |

Logs are rotated daily, 30 days retained, via `newsyslog.conf.d/` on atlas.

The ZFS path is `/greenlake/logs/k3s-cluster/` (bind-mounted into the jail
at `/mnt/logs/`).
