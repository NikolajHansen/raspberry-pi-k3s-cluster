# Todo / Roadmap

## VLAN Isolation — Cluster Network Segmentation

Move the k3s cluster nodes from the main LAN to a dedicated cluster VLAN, with atlas providing NFS directly on the cluster VLAN interface.

### Prerequisites

- [ ] Plug `em0` (or `em1`–`em3`) on atlas into the cluster VLAN switch port — NICs are present, just no carrier
- [ ] Configure managed switch: cluster VLAN (e.g. 10.1.10.x), trunk port to pfSense, access ports for Pi nodes
- [ ] Add pfSense VLAN interface and firewall rules (LAN → cluster VLAN: SSH port 22, Rancher port 443, MetalLB VIP ports)

### atlas

- [ ] Reconfigure the chosen NIC from current LAN alias (e.g. `192.168.1.30`) to cluster VLAN IP (e.g. `10.1.10.200`) in `/etc/rc.conf`
- [ ] NFS must remain accessible from **both** subnets (LAN clients + k3s nodes) — update ZFS `sharenfs` to include both networks:
  ```sh
  zfs set sharenfs="-alldirs -maproot=root -network 192.168.1.0/24 -network 10.1.10.0/24" greenlake/k3s
  zfs set sharenfs="-alldirs -maproot=root -network 192.168.1.0/24 -network 10.1.10.0/24" greenlake/media
  ```
- [ ] Update `scripts/atlas-k3s-storage-setup.sh` — add `K3S_LAN_SUBNET` var alongside `K3S_SUBNET` and export to both
- [ ] Decision: run `udpbroadcastrelay` on atlas for Squeezebox port 3483 if static server IP on Squeezeboxes is not viable

### Squeezeboxes

- [ ] Try static server IP first: configure each Squeezebox with the Lyrion MetalLB VIP (Settings → Advanced → Server address)
- [ ] If static IP not sufficient: install `udpbroadcastrelay` on atlas to relay port 3483 between LAN and cluster VLAN

### Ansible / cluster

- [ ] Update `~/k3s-site.yml`: new node IPs, `lan_subnet`, MetalLB pool, VIPs, NFS server address on cluster VLAN
- [ ] Update `~/k3s-inventory.yml`: new IPs for all 10 nodes
- [ ] Run `k3s-ansible static-ips.yml` to reconfigure NetworkManager on all nodes
- [ ] Verify cluster comes back up with new IPs
- [ ] Redeploy Lyrion Helm chart (`k3s-ansible lyrion.yml`) with updated NFS server and VIP

### Verification

- [ ] NFS mounts healthy inside Lyrion pod — no chown errors, writable
- [ ] MetalLB VIP reachable from LAN via pfSense routing
- [ ] Rancher UI reachable from LAN
- [ ] Lyrion web UI reachable from LAN
- [ ] Squeezebox devices connect to Lyrion (broadcast or static IP)
- [ ] Botkube Slack alerts still firing

---

## Centralized Logging — Atlas syslog receiver (Phase 1)

The Ansible playbook `ansible/playbooks/remote-logging.yml` configures rsyslog
forwarding on all cluster nodes. Run with:
```
k3s-ansible remote-logging.yml
```
Set `syslog_server: 192.168.1.26` in `~/k3s-site.yml` (the syslog jail IP on atlas).

**Atlas-side receiver is complete** — set up via `scripts/atlas-syslog-jail-setup.sh`.

- [x] Create ZFS dataset on atlas: `zfs create greenlake/logs/k3s-cluster` (at `/greenlake/logs/k3s-cluster`)
- [x] Create FreeBSD jail on atlas for the syslog receiver (`syslog.barnabas.dk`, IP `192.168.1.26`)
- [x] Install syslog-ng inside the jail (pkg install syslog-ng)
- [x] Configure syslog-ng receiver on TCP 514 writing per-host daily log files
      to `/greenlake/logs/k3s-cluster/<hostname>/YYYY-MM-DD.log`
- [ ] Add `newsyslog.conf` entry on atlas to rotate logs daily, retain 30 days compressed
- [ ] Add DNS entry for `syslog.example.com` → jail IP (so nodes can resolve it)
- [ ] Add `syslog_server: syslog.barnabas.dk` to `~/k3s-site.yml`
- [ ] Run `k3s-ansible remote-logging.yml` and verify journal entries appear in
      `/greenlake/logs/k3s-cluster/` on atlas

### Phase 2 — pod log aggregation (Loki) — deferred until post-VLAN migration

- [ ] Install Loki on atlas (jail or standalone binary) backed by `tank/logs/k3s-cluster`
- [ ] Deploy Vector or Promtail DaemonSet on the cluster forwarding pod logs to atlas Loki
- [ ] Add Loki datasource to Rancher Monitoring Grafana

---

## Other

- [ ] Rename Botkube Slack app from "Demo App" to "Botkube" (delete and recreate in Slack app portal — username cannot be changed after creation)
