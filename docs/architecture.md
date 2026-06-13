# Architecture

## Hardware

| Role | Hostname | IP | Count |
|---|---|---|---|
| Control Plane | master01 | 10.0.0.50 | 1 |
| Worker | node01–node09 | 10.0.0.51–59 | 9 |

All nodes run **Raspberry Pi OS Lite** (Debian 12 Bookworm, 64-bit, headless).

## Software Stack

| Tool | Purpose |
|---|---|
| [K3s](https://k3s.io) | Lightweight Kubernetes distribution |
| [Ansible](https://www.ansible.com) | Cluster provisioning and configuration |
| [Helm](https://helm.sh) | Kubernetes package manager |
| [Rancher](https://rancher.com) | Kubernetes management UI |
| [cert-manager](https://cert-manager.io) | TLS certificate management |
| [MetalLB](https://metallb.universe.tf) | Bare-metal load balancer (L2 mode) |
| [Unbound](https://nlnetlabs.nl/projects/unbound/) | Internal DNS resolver (deployed in-cluster) |
| [CoreDNS](https://coredns.io) | Kubernetes cluster DNS (k3s default, customised) |
| [NetworkManager](https://networkmanager.dev) | Static IP management on nodes |
| [Botkube](https://botkube.io) | Kubernetes event monitoring with Slack alerts |
| [Lyrion Music Server](https://lyrion.org) | Music streaming server (Squeezebox compatible) |
| [Bitwarden CLI](https://bitwarden.com/help/cli/) | Secrets management for Ansible |

## Network

```mermaid
graph TD
    internet((Internet))
    pfsense[pfSense Router\n10.0.0.1]
    switch[Network Switch]
    dns[DNS Server\n10.0.0.21]
    atlas[atlas.example.com\nNFS + ZFS storage]

    master[master01\n10.0.0.50\nControl Plane]
    node1[node01\n10.0.0.51]
    node2[node02\n10.0.0.52]
    node3[node03-09\n10.0.0.53–59]

    metallb[MetalLB VIP pool\n10.0.0.60–70]

    internet --> pfsense
    pfsense --> switch
    dns --> switch
    atlas --> switch
    switch --> master
    switch --> node1
    switch --> node2
    switch --> node3
    master -->|L2 ARP| metallb
```

## Kubernetes

```mermaid
graph TD
    rancher[Rancher UI\nrancher.example.com]
    master[master01\nK3s Server\nControl Plane + etcd]
    certmgr[cert-manager\ncattle-system]
    metallb[MetalLB\nmetallb-system]
    unbound[Unbound DNS\nkube-system]
    coredns[CoreDNS\nkube-system]
    botkube[Botkube\nbotkube namespace\nSlack alerts]
    lyrion[Lyrion Music Server\nlyrion namespace\nVIP: 10.0.0.61]
    workers[Worker Nodes\nnode01–node09\nK3s Agents]

    rancher --> master
    certmgr --> master
    metallb --> master
    unbound --> master
    coredns --> master
    botkube --> master
    lyrion --> workers
    master -->|schedules workloads| workers
    coredns -->|forwards internal DNS| unbound
    metallb -->|assigns VIPs| lyrion
```

## MetalLB

MetalLB runs in L2 mode with IP pool `10.0.0.60–10.0.0.70`. It provides stable VIPs for `LoadBalancer` services.

> **Important**: k3s ships with a built-in load balancer (klipper/servicelb) that conflicts with MetalLB.
> It is disabled via `--disable servicelb` in the k3s server args.

| Service | VIP |
|---|---|
| Rancher | 10.0.0.60 |
| Lyrion Music Server | 10.0.0.61 |
