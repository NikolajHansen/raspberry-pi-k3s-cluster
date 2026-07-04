# Cluster Monitoring

Monitoring is provided by **Rancher Monitoring** (kube-prometheus-stack) deployed
via `ansible/playbooks/rancher-monitoring.yml`, plus a custom **rpi-sensor-exporter**
DaemonSet for Raspberry Pi-specific hardware metrics.

## Rancher Monitoring

Rancher Monitoring installs the full kube-prometheus-stack into
`cattle-monitoring-system`:

- **Prometheus** — scrapes all PodMonitors and ServiceMonitors
- **Alertmanager** — routes alerts (Slack via Botkube, or directly)
- **Grafana** — dashboards; accessible via the Rancher UI

Deploy or upgrade:

```sh
k3s-ansible rancher-monitoring.yml
```

## Raspberry Pi sensor exporter

A custom Python exporter DaemonSet (`rpi-sensor-exporter`) runs on every node
and exposes Pi-specific hardware metrics on port **9101**.

### Metrics exposed

| Metric | Description |
|--------|-------------|
| `rpi_cpu_temperature_celsius` | SoC temperature from `/sys/class/thermal/thermal_zone0/temp` |
| `rpi_firmware_throttled_status` | Raw `get_throttled` bitmask (0 = healthy) |
| `rpi_firmware_throttled_current` | Current throttling flags (bits 0–3) |
| `rpi_firmware_throttled_occurred` | Historical throttling flags (bits 16–19) |

Throttling flag bits:
| Bit | Meaning |
|-----|---------|
| 0 | Under-voltage detected |
| 1 | Arm frequency capped |
| 2 | Currently throttled |
| 3 | Soft temperature limit active |
| 16–19 | Same, but "since last boot" |

A value of `0x0` means the node is healthy.  Non-zero values indicate power
or thermal problems that affect cluster reliability.

### How throttling is read — vcgencmd vs sysfs

On **Raspberry Pi 4** the `get_throttled` status is only accessible via the
VideoCore firmware mailbox, through the `vcgencmd` utility.

The sysfs path (`/sys/class/firmware/raspberrypi/vcio` or
`/sys/bus/platform/drivers/raspberrypi-firmware/*/get_throttled`) does **not**
exist on Pi 4 with current Raspberry Pi OS kernels.  Only Pi 5 / newer kernels
may expose it.

The exporter therefore uses this priority order:

1. **`vcgencmd get_throttled`** — primary method (Pi 4 + Pi 5)
2. **sysfs glob** — fallback for future kernels that expose it directly

### Container image — why `python:3.12-slim` (not Alpine)

`vcgencmd` is a **glibc** binary.  Alpine Linux uses **musl libc**.
A glibc binary cannot run in a musl container because:

- The dynamic linker is at `/lib/ld-linux-aarch64.so.1` (glibc) — absent in Alpine.
- Symbol resolution fails (`__printf_chk`, `__fprintf_chk`, etc.) — musl does
  not export glibc-internal symbols.

The image therefore uses `python:3.12-slim` (Debian Bookworm, glibc) so
the host `vcgencmd` binary runs correctly via the `/host-usr` volume mount.

### Volume mounts

The DaemonSet mounts two host paths:

| Mount | Host path | Container path | Purpose |
|-------|-----------|----------------|---------|
| `vcio` | `/dev/vcio` | `/dev/vcio` | VideoCore mailbox character device — required by `vcgencmd` |
| `host-usr` | `/usr` | `/host-usr` | Provides `vcgencmd` binary and its shared libraries (`libvchiq_arm.so`, etc.) |

The `vcio` device is mounted as type `CharDevice` with `hostNetwork: true`
not required — the DaemonSet does not use host networking.

### Deploy / update

```sh
k3s-ansible rpi-sensors.yml
```

To verify metrics are being collected from a node:

```sh
# From a shell on the cluster, or via kubectl exec
kubectl exec -n cattle-monitoring-system daemonset/rpi-sensor-exporter \
  -- wget -qO- http://0.0.0.0:9101/metrics | grep rpi_

# Or from a Pi node directly
curl -s http://localhost:9101/metrics | grep rpi_
```

Expected healthy output:
```
rpi_cpu_temperature_celsius 52.3
rpi_firmware_throttled_status 0
rpi_firmware_throttled_current 0
rpi_firmware_throttled_occurred 0
```

### Prometheus alerts

Seven PrometheusRule alerts are defined in the DaemonSet manifest:

| Alert | Condition |
|-------|-----------|
| `RpiUnderVoltage` | Under-voltage flag set for > 1m |
| `RpiArmFreqCapped` | Arm frequency cap flag set for > 1m |
| `RpiThrottled` | Currently throttled for > 1m |
| `RpiSoftTempLimit` | Soft temperature limit active for > 1m |
| `RpiHighTemperature` | CPU temp > 80 °C for > 5m |
| `RpiVeryHighTemperature` | CPU temp > 85 °C for > 2m |
| `RpiAnyHistoricalThrottling` | Any historical throttle event since last boot |

## Botkube

Botkube monitors the Kubernetes API and forwards events to Slack.  Deployed
via `ansible/playbooks/botkube.yml`.  See `todo.md` for the Slack app rename
backlog item.
