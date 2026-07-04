# Raspberry Pi K3s Cluster

A 10-node Kubernetes cluster running on Raspberry Pi hardware, provisioned with Ansible and managed via Rancher.

| Role | Hostname | IP | Count |
|---|---|---|---|
| Control Plane | master01 | *(site-specific)* | 1 |
| Worker | node01–node09 | *(site-specific)* | 9 |

## Documentation

- [Architecture](docs/architecture.md) — hardware, software stack, network and Kubernetes diagrams
- [Provisioning](docs/provisioning.md) — how to bootstrap and manage the cluster with Ansible
- [Persistent Storage](docs/storage.md) — NFS/ZFS storage
- [Lyrion Music Server](docs/lyrion.md) — Squeezebox streaming server deployment

## Repository Structure

```
.
├── k3s-site.yml.example             # Copy to ~/k3s-site.yml — site-specific vars (IPs, domains, versions)
├── k3s-inventory.yml.example        # Copy to ~/k3s-inventory.yml — per-host IPs (never committed)
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── groups.yml               # Group structure and shared vars (no IPs)
│   │   └── credentials.yml.example  # Vault credentials template
│   ├── playbooks/
│   │   ├── k3s-cluster.yml          # Full cluster bootstrap
│   │   ├── static-ips.yml           # Assign static IPs via NetworkManager
│   │   ├── rancher-monitoring.yml   # Deploy Rancher Monitoring (Prometheus/Grafana)
│   │   ├── rpi-sensors.yml          # Deploy Raspberry Pi temp/throttling exporter
│   │   ├── lyrion.yml               # Deploy Lyrion Music Server
│   │   ├── botkube.yml              # Deploy Botkube Slack monitoring
│   │   └── helm-apps.yml            # Deploy additional Helm chart applications
│   └── templates/
│       ├── coredns-custom.yaml.j2   # CoreDNS custom ConfigMap template
│       └── rpi-sensor-exporter.yaml.j2
├── docs/
│   ├── architecture.md
│   ├── provisioning.md
│   ├── storage.md
│   └── lyrion.md
├── charts/
│   └── lyrion/                      # Lyrion Helm chart
│       ├── Chart.yaml
│       ├── values.yaml              # Default values (override via ~/k3s-site.yml)
│       └── templates/
│           └── lyrion.yaml
└── scripts/
    ├── atlas-k3s-storage-setup.sh   # NFS/ZFS storage setup on the NAS (run as root)
    └── lyrion-backup.sh             # ZFS snapshot backup/restore for Lyrion
```

## Quick Start

```bash
# 1. Copy site files and fill in your values
cp k3s-site.yml.example ~/k3s-site.yml
cp k3s-inventory.yml.example ~/k3s-inventory.yml

# 2. Setup NFS storage on your NAS (run as root)
sh scripts/atlas-k3s-storage-setup.sh

# 3. Bootstrap the cluster
k3s-ansible k3s-cluster.yml

# 4. Deploy Lyrion
k3s-ansible lyrion.yml

# 5. (Optional) Deploy Rancher Monitoring + Raspberry Pi sensors
k3s-ansible rancher-monitoring.yml
k3s-ansible rpi-sensors.yml

# 6. (Optional) Deploy Botkube Slack monitoring
k3s-ansible botkube.yml
```

## Roadmap

- [ ] Dedicated cluster VLAN with pfSense routing
- [x] Persistent storage for Lyrion config (NFSv4)
- [x] ZFS snapshot backup/restore for Lyrion
- [x] Botkube Slack monitoring for pod crashes/restarts
- [x] Helm chart for Lyrion (replaced Jinja template)
- [x] Rancher monitoring + Raspberry Pi hardware sensors
