# Raspberry Pi K3s Cluster

A 10-node Kubernetes cluster running on Raspberry Pi hardware, provisioned with Ansible and managed via Rancher.

| Role | Hostname | IP | Count |
|---|---|---|---|
| Control Plane | master01 | 10.0.0.50 | 1 |
| Worker | node01–node09 | 10.0.0.51–59 | 9 |

## Documentation

- [Architecture](docs/architecture.md) — hardware, software stack, network and Kubernetes diagrams
- [Provisioning](docs/provisioning.md) — how to bootstrap and manage the cluster with Ansible
- [Persistent Storage](docs/storage.md) — NFS/ZFS storage on atlas.example.com
- [Lyrion Music Server](docs/lyrion.md) — Squeezebox streaming server deployment

## Repository Structure

```
.
├── ansible/
│   ├── inventory/
│   │   ├── inventory.yml            # Hosts, groups, Bitwarden lookup for become_password
│   │   └── credentials.yml.example # Credentials template (never commit the real file)
│   ├── playbooks/
│   │   ├── k3s-cluster.yml          # Full cluster bootstrap
│   │   ├── static-ips.yml           # Assign static IPs via NetworkManager
│   │   ├── lyrion.yml               # Deploy Lyrion Music Server
│   │   ├── botkube.yml              # Deploy Botkube Slack monitoring
│   │   └── helm-apps.yml            # Deploy additional Helm chart applications
│   └── templates/
│       ├── unbound.yaml.j2          # Unbound DNS Kubernetes manifest
│       └── coredns-custom.yaml.j2   # CoreDNS custom ConfigMap
├── docs/
│   ├── architecture.md              # Hardware, software stack, network diagrams
│   ├── provisioning.md              # Ansible usage and cluster bootstrap
│   ├── storage.md                   # NFS/ZFS persistent storage
│   └── lyrion.md                    # Lyrion Music Server details
├── k8s/
│   └── lyrion.yaml.j2               # Lyrion manifest template
├── scripts/
│   ├── atlas-k3s-storage-setup.sh  # NFS storage setup on atlas.example.com (run as root)
│   └── lyrion-backup.sh            # ZFS snapshot backup/restore for Lyrion
└── README.md
```

## Quick Start

```bash
# 1. Setup NFS storage on atlas (run as root on atlas.example.com)
su -
sh scripts/atlas-k3s-storage-setup.sh

# 2. Bootstrap the cluster
k3s-ansible k3s-cluster.yml

# 3. Deploy Lyrion
k3s-ansible lyrion.yml

# 4. Deploy Botkube monitoring (requires botkube_slack_bot_token + botkube_slack_app_token in site vars)
k3s-ansible botkube.yml
```

## Roadmap

- [ ] Dedicated cluster VLAN with pfSense routing
- [ ] Move cluster to isolated `10.1.10.x` network
- [x] Persistent storage for Lyrion config (NFSv4 on atlas)
- [x] ZFS snapshot backup/restore for Lyrion
- [x] Botkube Slack monitoring for pod crashes/restarts
