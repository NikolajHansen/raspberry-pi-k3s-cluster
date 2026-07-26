# Copilot Instructions for `raspberry-pi-k3s-cluster`

## Build, test, and lint commands

This repository is infrastructure-as-code (Ansible + Helm). There is no repo-defined unit test suite or lint script (no Makefile/package test targets).

Primary execution entrypoint is the local wrapper `~/bin/k3s-ansible` described in `README.md` and `docs/provisioning.md`:

```bash
# Full cluster bootstrap
k3s-ansible k3s-cluster.yml

# Single-playbook run (smallest normal execution unit)
k3s-ansible lyrion.yml

# Other targeted runs
k3s-ansible static-ips.yml
k3s-ansible rancher-monitoring.yml
k3s-ansible rpi-sensors.yml
k3s-ansible helm-apps.yml
k3s-ansible botkube.yml
```

Per-playbook syntax check (closest equivalent to a single-test run in this repo):

```bash
ansible-playbook \
  -i ansible/inventory/groups.yml \
  -i ~/k3s-inventory.yml \
  -e @~/k3s-site.yml \
  ansible/playbooks/lyrion.yml \
  --syntax-check
```

Direct Helm deployment path for Lyrion (from `docs/lyrion.md`):

```bash
helm upgrade --install lyrion charts/lyrion \
  --set nfsServer=atlas.example.com \
  --set vip=10.0.0.61 \
  --set hostname=lyrion.example.com
```

## High-level architecture

The repo has two main layers:

1. **Cluster provisioning (`ansible/playbooks`)**  
   - `k3s-cluster.yml` is the end-to-end bootstrap flow across four plays:
     - all nodes: cgroups + `squeezeboxserver` UID 499 user
     - master: install k3s server, patch CoreDNS behavior
     - workers: join k3s cluster
     - master: install Helm, cert-manager, Rancher
   - `static-ips.yml` sets node static IPs via NetworkManager (`nmcli`).
   - `helm-apps.yml` deploys optional apps from `site_helm_apps`.

2. **Application deployment (`charts/lyrion` + playbooks)**  
   - `ansible/playbooks/lyrion.yml` copies and installs the local Helm chart.
   - `charts/lyrion/templates/lyrion.yaml` defines:
     - static NFS-backed PV/PVCs for `/media` and `/config`
     - Lyrion Deployment with `hostNetwork: true`
     - init containers for mount checks and SQLite WAL checkpointing
     - MetalLB-backed `LoadBalancer` Service + Ingress

External dependencies wired into this flow:
- Site-specific variables come from `~/k3s-site.yml` and `~/k3s-inventory.yml`.
- Secrets are fetched from Bitwarden lookups in Ansible.
- Persistent data is stored on NAS ZFS datasets and exported over NFSv4.

3. **Observability deployment (`ansible/playbooks/rancher-monitoring.yml` + `rpi-sensors.yml`)**
   - `rancher-monitoring.yml` installs Rancher Monitoring (CRDs + stack) in `cattle-monitoring-system`.
   - `rpi-sensors.yml` deploys a DaemonSet and PodMonitor exposing Raspberry Pi temperature and firmware throttling metrics to Prometheus.

## Weekend baseline (2026-06-13 to 2026-06-14)

Treat these as the current intended state unless the user explicitly asks to change them:

- Lyrion deployment was migrated from `k8s/lyrion.yaml.j2` to Helm chart `charts/lyrion/*`.
- Site examples were moved to repo root: `k3s-site.yml.example` and `k3s-inventory.yml.example`.
- CoreDNS now forwards directly to pfSense; Unbound was removed from playbooks/docs.
- Botkube Slack monitoring was added via `ansible/playbooks/botkube.yml`.
- `helm-apps.yml` now guards missing `values` keys before `dict2items`.
- `todo.md` is used for the planned VLAN migration work and includes the rule that NFS must remain reachable from both LAN and cluster VLAN subnets.

## Key repository conventions

- **Never commit site-specific config**: copy examples to `~/k3s-site.yml` and `~/k3s-inventory.yml`; playbooks assume these external files.
- **Lyrion storage must stay on NFSv4**: chart mount options pin `vers=4`; docs explicitly require v4 for SQLite WAL locking.
- **On FreeBSD NAS, exports are managed via ZFS `sharenfs`** (not `/etc/exports`), matching `scripts/atlas-k3s-storage-setup.sh`.
- **UID mapping is intentional**: playbooks create `squeezeboxserver` UID 499 on every node so NFSv4 numeric UID mapping matches container ownership.
- **Secrets handling pattern**: keep secrets out of Helm `--set` when possible; Botkube uses a temporary `0600` values file and deletes it after install.
- **Documentation sanitization**: keep public docs/examples anonymized (`example.com`, `10.0.0.x`) rather than real domain/IP values.
