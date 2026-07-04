#!/bin/sh
# Setup the syslog receiver jail on atlas (FreeBSD/ZFS).
# Run as root. Idempotent — safe to re-run.
#
# What this does:
#   1. Creates ZFS dataset greenlake/k3s/logs
#   2. Creates jail directory/symlink structure at /area51/jails/syslog.example.com
#   3. Populates /etc from basejail and rebuilds passwd db
#   4. Creates /etc/jail.conf.d/syslog.conf  (IP 10.0.0.25)
#   5. Adds 'syslog' to jail_list in /etc/rc.conf (jail framework owns the IP)
#   6. Clears any stuck IP aliases from prior failed attempts
#   7. Starts the jail via `service jail start`
#   8. Bootstraps pkg, installs and configures syslog-ng
#
# After this script succeeds, run the Ansible playbook on the k3s cluster:
#   k3s-ansible remote-logging.yml
#
# Cluster nodes forward logs to 10.0.0.25:514 (TCP).
# Node logs : /greenlake/k3s/logs/nodes/<hostname>/YYYY-MM-DD.log
# Pod logs  : /greenlake/k3s/logs/pods/<namespace>/<podname>/YYYY-MM-DD.log

set -e

JAIL_NAME="syslog"
JAIL_HOST="syslog.example.com"
JAIL_IP="10.0.0.26"
JAIL_LO="127.0.0.9"
JAIL_ROOT="/area51/jails/${JAIL_HOST}"
BASEJAIL="/area51/jails/basejail"
ZFS_DATASET="greenlake/k3s/logs"
LOG_MOUNT="/greenlake/k3s/logs"
LOG_MOUNT_IN_JAIL="/mnt/logs"

echo "==> Checking prerequisites..."
[ "$(id -u)" -eq 0 ] || { echo "ERROR: Must be run as root."; exit 1; }
[ -d "$BASEJAIL" ] || { echo "ERROR: Basejail not found at $BASEJAIL"; exit 1; }

# ---------------------------------------------------------------------------
echo "==> Step 1: ZFS dataset ${ZFS_DATASET}..."
if zfs list "${ZFS_DATASET}" >/dev/null 2>&1; then
  echo "    Already exists."
else
  zfs create -p "${ZFS_DATASET}"
  echo "    Created, mounted at ${LOG_MOUNT}"
fi

# ---------------------------------------------------------------------------
echo "==> Step 2: Jail directory structure at ${JAIL_ROOT}..."
if [ ! -d "${JAIL_ROOT}" ]; then
  mkdir -p "${JAIL_ROOT}"
  for d in basejail dev etc home mnt proc root tmp var \
            var/cache var/db var/log var/run var/tmp var/spool \
            usr/local usr/games usr/obj; do
    mkdir -p "${JAIL_ROOT}/${d}"
  done
  for link in bin include lib lib32 libdata libexec ports sbin share src; do
    ln -sf "/basejail/usr/${link}" "${JAIL_ROOT}/usr/${link}"
  done
  for link in bin lib lib32 libexec rescue sbin; do
    ln -sf "/basejail/${link}" "${JAIL_ROOT}/${link}"
  done
  mkdir -p "${JAIL_ROOT}${LOG_MOUNT_IN_JAIL}"
  chmod 1777 "${JAIL_ROOT}/tmp"
  chmod 0700 "${JAIL_ROOT}/root"
  echo "    Directory structure created."
else
  echo "    Already exists."
fi

# ---------------------------------------------------------------------------
echo "==> Step 3: /etc from basejail + passwd db..."
if [ ! -f "${JAIL_ROOT}/etc/master.passwd" ]; then
  echo "    Copying /etc from basejail..."
  cp -Rp "${BASEJAIL}/etc/." "${JAIL_ROOT}/etc/"
fi
# Always rebuild passwd db — required or jail fails with "initgroups root: Operation not permitted"
pwd_mkdb -p -d "${JAIL_ROOT}/etc" "${JAIL_ROOT}/etc/master.passwd"
echo "    passwd db OK (root: $(grep -c '^root' ${JAIL_ROOT}/etc/master.passwd) entry)"

cat > "${JAIL_ROOT}/etc/rc.conf" << EOF
hostname="${JAIL_HOST}"
defaultrouter="10.0.0.1"
sendmail_enable="NO"
sendmail_submit_enable="NO"
sendmail_outbound_enable="NO"
sendmail_msp_queue_enable="NO"
syslogd_flags="-ss"
cron_flags="\$cron_flags -J 15"
rpcbind_enable="NO"
syslog_ng_enable="YES"
EOF

cat > "${JAIL_ROOT}/etc/resolv.conf" << EOF
nameserver 10.0.0.1
search example.com
EOF

# ---------------------------------------------------------------------------
echo "==> Step 4: fstab (no proc — jail.conf handles procfs)..."
cat > "${JAIL_ROOT}/etc/fstab" << EOF
${BASEJAIL} ${JAIL_ROOT}/basejail nullfs ro 0 0
${LOG_MOUNT} ${JAIL_ROOT}${LOG_MOUNT_IN_JAIL} nullfs rw 0 0
EOF
echo "    Done."

# ---------------------------------------------------------------------------
echo "==> Step 5: /etc/jail.conf.d/${JAIL_NAME}.conf..."
JAILCONF="/etc/jail.conf.d/${JAIL_NAME}.conf"
cat > "${JAILCONF}" << EOF
${JAIL_NAME} {
    host.hostname = "${JAIL_HOST}";
    path = "${JAIL_ROOT}";
    ip4.addr = "bge0|${JAIL_IP}/32";
    ip4.addr += "lo1|${JAIL_LO}/32";
    mount.fstab = "${JAIL_ROOT}/etc/fstab";
    mount.devfs;
    mount.fdescfs;
    mount.procfs;
    exec.start = "/bin/sh /etc/rc";
    exec.stop = "/bin/sh /etc/rc.shutdown";
    exec.clean;
    exec.system_user = "root";
    exec.jail_user = "root";
    exec.consolelog = "/var/log/jail_${JAIL_NAME}_console.log";
    allow.raw_sockets = 1;
    allow.socket_af = 1;
    allow.mount;
    allow.set_hostname = 0;
    devfs_ruleset = "4";
}
EOF
echo "    Written."

# ---------------------------------------------------------------------------
echo "==> Step 6: jail_list in /etc/rc.conf..."
# Remove any ifconfig_bge0_alias for JAIL_IP — the jail framework owns the IP
sed -i '' "/ifconfig_bge0_alias.*${JAIL_IP}/d" /etc/rc.conf
if grep -q "jail_list=.*${JAIL_NAME}" /etc/rc.conf; then
  echo "    '${JAIL_NAME}' already in jail_list."
else
  sed -i '' "s/^jail_list=\"\(.*\)\"/jail_list=\"\1 ${JAIL_NAME}\"/" /etc/rc.conf
  echo "    Added. jail_list: $(grep '^jail_list' /etc/rc.conf)"
fi

# ---------------------------------------------------------------------------
echo "==> Step 7: Clearing any stuck IP aliases from prior failed attempts..."
ifconfig bge0 inet "${JAIL_IP}" delete 2>/dev/null && echo "    Removed stuck bge0 ${JAIL_IP} alias." || true
ifconfig lo1 inet "${JAIL_LO}" delete 2>/dev/null && echo "    Removed stuck lo1 ${JAIL_LO} alias." || true

# ---------------------------------------------------------------------------
echo "==> Step 8: Starting jail..."
if jls -j "${JAIL_NAME}" >/dev/null 2>&1; then
  echo "    Jail '${JAIL_NAME}' is already running (JID $(jls -j ${JAIL_NAME} -h jid | tail -1))."
else
  service jail start "${JAIL_NAME}"
  sleep 2
  jls -j "${JAIL_NAME}" >/dev/null 2>&1 || { echo "ERROR: Jail failed to start. Check /var/log/jail_${JAIL_NAME}_console.log"; exit 1; }
  echo "    Jail started (JID $(jls -j ${JAIL_NAME} -h jid | tail -1))."
fi

# ---------------------------------------------------------------------------
echo "==> Step 9: Bootstrap pkg..."
if jexec "${JAIL_NAME}" test -f /usr/local/sbin/pkg 2>/dev/null; then
  echo "    pkg already bootstrapped."
else
  jexec "${JAIL_NAME}" env ASSUME_ALWAYS_YES=yes pkg bootstrap
fi

# ---------------------------------------------------------------------------
echo "==> Step 10: Install syslog-ng..."
jexec "${JAIL_NAME}" pkg update -q
if jexec "${JAIL_NAME}" pkg info syslog-ng >/dev/null 2>&1; then
  echo "    syslog-ng already installed."
else
  jexec "${JAIL_NAME}" pkg install -y syslog-ng
fi

# ---------------------------------------------------------------------------
echo "==> Step 11: Configure syslog-ng..."
SYSLOGNG_CONF="${JAIL_ROOT}/usr/local/etc/syslog-ng.conf"
mkdir -p "${JAIL_ROOT}/usr/local/etc"
cat > "${SYSLOGNG_CONF}" << 'EOF'
@version: 4.8
@include "scl.conf"

options {
    flush_lines(0);
    time_reopen(10);
    log_fifo_size(1000);
    chain_hostnames(no);
    use_dns(no);
    use_fqdn(no);
    keep_hostname(yes);
    create_dirs(yes);
    dir_perm(0755);
    perm(0640);
};

source s_tcp {
    network(
        ip("0.0.0.0")
        port(514)
        transport("tcp")
        max_connections(50)
        so_keepalive(yes)
    );
};

# Parse [namespace/podname] prefix embedded by rsyslog from pod log messages.
parser p_k8s_pod {
    regexp-parser(
        regexp("^\[(?P<ns>[^/\]]+)/(?P<pod>[^\]]+)\] ?")
        template("${MSG}")
        prefix(".pod.")
        flags(store-matches)
    );
};

# Node journal logs — one file per host
destination d_nodes {
    file(
        "/mnt/logs/nodes/$HOST/$YEAR-$MONTH-$DAY.log"
        create_dirs(yes)
        template("${ISODATE} ${HOST} ${MSGHDR}${MSG}\n")
    );
};

# Pod logs — one file per namespace/podname
destination d_pods {
    file(
        "/mnt/logs/pods/${.pod.ns}/${.pod.pod}/$YEAR-$MONTH-$DAY.log"
        create_dirs(yes)
        template("${ISODATE} ${HOST} ${MSG}\n")
    );
};

# Fallback for pod messages that failed [ns/pod] parsing
destination d_pods_unknown {
    file(
        "/mnt/logs/pods/_unparsed/$HOST/$YEAR-$MONTH-$DAY.log"
        create_dirs(yes)
        template("${ISODATE} ${HOST} ${MSGHDR}${MSG}\n")
    );
};

# Pod logs arrive tagged "k8s-pod" on facility local6
filter f_k8s { facility(local6); };
filter f_k8s_parsed { match("." value(".pod.ns")); };

# Route pod logs per namespace/pod; fallback for unparseable
log {
    source(s_tcp);
    filter(f_k8s);
    parser(p_k8s_pod);
    if (filter(f_k8s_parsed)) {
        destination(d_pods);
    } else {
        destination(d_pods_unknown);
    };
    flags(final);
};

# Node/system logs
log {
    source(s_tcp);
    destination(d_nodes);
};
EOF
echo "    syslog-ng.conf written."

# Ensure log dir structure exists
mkdir -p "${LOG_MOUNT}/nodes" "${LOG_MOUNT}/pods"

# ---------------------------------------------------------------------------
echo "==> Step 12: Start/restart syslog-ng inside jail..."
jexec "${JAIL_NAME}" service syslog-ng restart 2>/dev/null || jexec "${JAIL_NAME}" service syslog-ng start
sleep 1
jexec "${JAIL_NAME}" sockstat -l -4 | grep 514 && echo "    TCP 514 is listening." || echo "    WARNING: port 514 not open yet."

# ---------------------------------------------------------------------------
echo "==> Step 13: Configure log rotation (newsyslog on host, outside jail)..."
NEWSYSLOG_CONF="/etc/newsyslog.conf.d/k3s-cluster.conf"
mkdir -p /etc/newsyslog.conf.d
if [ -f "${NEWSYSLOG_CONF}" ]; then
  echo "    ${NEWSYSLOG_CONF} already exists."
else
  cat > "${NEWSYSLOG_CONF}" << EOF
# Rotate k3s cluster syslog files daily, keep 30 days compressed.
# Paths are on the host (ZFS dataset); syslog-ng writes them inside the jail
# via the nullfs mount at ${JAIL_ROOT}${LOG_MOUNT_IN_JAIL}.
${LOG_MOUNT}/nodes/*/*.log           644  30  *  @T00  JC
${LOG_MOUNT}/pods/*/*/*.log          644  30  *  @T00  JC
EOF
  echo "    Written. Logs rotate daily, 30-day retention."
fi

# ---------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo "  Syslog jail is up!"
echo "  Jail IP  : ${JAIL_IP}"
echo "  Node logs: ${LOG_MOUNT}/nodes/<host>/YYYY-MM-DD.log"
echo "  Pod logs : ${LOG_MOUNT}/pods/<namespace>/<pod>/YYYY-MM-DD.log"
echo ""
echo "  Next steps:"
echo "    1. Add DNS entry: syslog.${JAIL_HOST#*.} → ${JAIL_IP} (in pfSense/Unbound/hosts)"
echo "    2. Add to ~/k3s-site.yml: syslog_server: syslog.${JAIL_HOST#*.}"
echo "    3. Run: k3s-ansible remote-logging.yml"
echo "    4. Node logs : tail -f ${LOG_MOUNT}/nodes/<host>/\$(date +%Y-%m-%d).log"
echo "    5. Pod logs  : tail -f ${LOG_MOUNT}/pods/<namespace>/<pod>/\$(date +%Y-%m-%d).log"
echo "=================================================================="
