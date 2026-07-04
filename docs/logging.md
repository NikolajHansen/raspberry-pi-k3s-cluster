# Centralized Logging

## Architecture overview

```
Pi nodes (all 10)
  └── rsyslog (imjournal)
        │  TCP/514
        └──► atlas.barnabas.dk  (FreeBSD jail: syslog-receiver)
                └── ZFS dataset: tank/logs/k3s-cluster
                      └── flat log files, rotated by newsyslog(8)
```

All cluster nodes are **stateless by design** — no log data is kept on the
nodes themselves. Journal data is forwarded in real-time over TCP to atlas.

## What is forwarded

| Source | Mechanism | Forwarded |
|--------|-----------|-----------|
| k3s (server) | `imjournal` (_SYSTEMD_UNIT=k3s.service) | yes |
| k3s-agent | `imjournal` (_SYSTEMD_UNIT=k3s-agent.service) | yes |
| containerd / container runtime | `imjournal` | yes |
| kernel / boot messages | `kern.*` syslog facility | yes |
| auth / sudo | `auth.*` | yes |
| All warnings and above | `*.warn` | yes |

Low-priority noise (debug, cron chatter below warning) is **not** forwarded to
keep atlas storage modest.

## Cluster-side configuration (Ansible-managed)

The playbook `ansible/playbooks/remote-logging.yml` installs rsyslog and
deploys a drop-in forwarding config to `/etc/rsyslog.d/90-remote.conf` on
every node.  The template lives at `ansible/templates/rsyslog-remote.conf.j2`.

The `syslog_server` variable defaults to `atlas.barnabas.dk` and can be
overridden in `~/k3s-site.yml`:

```yaml
# ~/k3s-site.yml (site-specific, not committed)
syslog_server: atlas.barnabas.dk   # FreeBSD host running the syslog receiver
```

Key design decisions:
- **TCP** (not UDP) — reliable delivery; messages are not silently dropped if
  atlas is briefly unreachable (rsyslog queues in memory).
- `imjournal` — reads from the systemd journal directly, so k3s and container
  logs that go to the journal (not syslog) are captured correctly.
- Drop-in file under `rsyslog.d/` — avoids touching the OS-default
  `/etc/rsyslog.conf`, making the role idempotent and upgrade-safe.

## Atlas-side configuration (out of scope for this repo)

Atlas is a FreeBSD host managed separately from these Ansible playbooks.
A fully automated setup script is provided at `scripts/atlas-syslog-jail-setup.sh`.
Copy it to atlas and run it as root:

```sh
scp scripts/atlas-syslog-jail-setup.sh atlas.example.com:~/
ssh atlas.example.com
sudo sh ~/setup-syslog-jail.sh
```

The script performs all steps below automatically. The manual breakdown is
provided for reference.

### 1. Create ZFS dataset

```sh
zfs create greenlake/logs/k3s-cluster
# Mounts at /greenlake/logs/k3s-cluster
```

### 2. Create a jail for the syslog receiver

The script creates a nullfs-based jail at `/area51/jails/syslog.example.com`
using the shared basejail pattern, assigns IP `10.0.0.25`, and writes
`/etc/jail.conf.d/syslog.conf`.

### 3. Configure syslog-ng inside the jail

Installs syslog-ng from pkg inside the jail and configures it as a receiver
on TCP 514:

```conf
# /usr/local/etc/rsyslog.conf (inside syslog-receiver jail)
module(load="imtcp")
input(type="imtcp" port="514")

# Write all forwarded messages to per-host files
template(name="PerHostFile" type="string"
  string="/var/log/k3s-cluster/%HOSTNAME%/%$YEAR%-%$MONTH%-%$DAY%.log")

*.* ?PerHostFile
```

### 4. Expose TCP 514 from atlas to the cluster network

If the receiver runs inside a jail with a private jail IP, configure a PF NAT
redirect or assign the jail a routable IP reachable from all Pi nodes.

### 5. Log rotation

Add a `newsyslog.conf` entry for `/var/log/k3s-cluster/` to rotate daily,
keeping 30 days of compressed logs.

```conf
# /etc/newsyslog.conf.d/k3s-cluster.conf (on atlas, outside jail)
/var/log/k3s-cluster/*/*.log  644  30  *  @T00  JC
```

## Phase 2 — pod/container log aggregation (Loki)

Phase 1 covers **node-level** logs (journal → rsyslog → atlas).  Container
stdout/stderr forwarded to the journal is included, but structured pod-level
log aggregation is deferred to Phase 2.

Phase 2 plan:
- Run a **Loki** instance on atlas (inside a jail or as a standalone binary)
  backed by the same ZFS dataset.
- Deploy **Vector** or **Promtail** as a DaemonSet on the cluster, configured
  to tail `/var/log/pods/**/*.log` and forward to atlas Loki.
- Add a Loki datasource to the Rancher Monitoring Grafana instance so logs are
  searchable alongside metrics.

Phase 2 is out of scope until the cluster VLAN migration (see `todo.md`) is
complete, as network topology changes will affect routing between pods and atlas.

## Stateless-node constraint

Cluster nodes must remain stateless — no persistent disk writes, no
node-local services that accumulate state.  rsyslog in forwarding-only mode
satisfies this: it reads from the journal (kernel-managed ring buffer) and
forwards over TCP.  If atlas is temporarily unreachable, rsyslog buffers in
memory (configurable, default ~10 MB per node) and retries; **no on-disk
queue file is written to the node**.
