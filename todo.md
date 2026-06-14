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

## Other

- [ ] Rename Botkube Slack app from "Demo App" to "Botkube" (delete and recreate in Slack app portal — username cannot be changed after creation)
