#!/usr/bin/env bash
# VistaRevive - Phase 3: performance base for low RAM and slow disks
# Target: Debian 13 "trixie". Run after 02-drivers.sh and a reboot.
# Usage: sudo bash 03-performance.sh
# Safe to run more than once. Every file it writes is listed at the end.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
log()  { echo -e "\e[1;34m[VistaRevive]\e[0m $*"; }
warn() { echo -e "\e[1;33m[warning]\e[0m $*"; }

RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
log "Detected ${RAM_MB} MB RAM"

DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  systemd-zram-generator earlyoom

# ---------------------------------------------------------------------------
# 1. zram: compressed swap in RAM (first tier)
# ---------------------------------------------------------------------------
# zstd compresses roughly 3:1 on desktop data, so a zram device the size of
# physical RAM costs about a third of that when full. Scales with RAM upgrades.
log "Configuring zram (size = RAM, zstd, high priority)"
cat > /etc/systemd/zram-generator.conf <<'EOF'
# VistaRevive zram config
[zram0]
zram-size = ram
compression-algorithm = zstd
swap-priority = 100
EOF

# zram-tools would also create a zram device; make sure only one tool runs.
if dpkg -l zram-tools 2>/dev/null | grep -q '^ii'; then
  warn "Removing zram-tools to avoid two competing zram setups"
  apt-get purge -y zram-tools
fi

# ---------------------------------------------------------------------------
# 2. Disk swap (second tier): installer partition if present, else a swapfile
# ---------------------------------------------------------------------------
# (Skipped inside an ISO build: the installed system creates its swap at first
#  boot via vistarevive-firstboot.service, see 09-build-iso.sh.)
if [[ -n "${VISTAREVIVE_BUILD:-}" ]]; then
  log "ISO build: disk swap will be set up at first boot"
elif grep -qE '^[^#].*\sswap\s' /etc/fstab 2>/dev/null; then
  log "Swap partition found in /etc/fstab -> using it as backup tier"
  # Give it low priority so zram is always used first.
  sed -i -E '/^[^#].*\sswap\s/ s/\bsw\b/sw,pri=10/; /^[^#].*\sswap\s/ s/pri=10,pri=10/pri=10/' /etc/fstab
elif [[ ! -f /swapfile ]]; then
  SWAP_MB=$(( RAM_MB < 2048 ? 2048 : 1024 ))
  log "Creating ${SWAP_MB} MB /swapfile (backup tier)"
  fallocate -l "${SWAP_MB}M" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  echo '/swapfile none swap sw,pri=10 0 0' >> /etc/fstab
else
  log "/swapfile already exists, leaving it as is"
fi

# ---------------------------------------------------------------------------
# 3. Memory tuning (sysctl)
# ---------------------------------------------------------------------------
log "Writing memory sysctl settings"
cat > /etc/sysctl.d/90-vistarevive.conf <<'EOF'
# VistaRevive memory tuning for zram
# Swap to zram eagerly: compressing pages is far cheaper than dropping
# file cache and re-reading it from a slow HDD.
vm.swappiness = 150
# zram has no seek cost, so read single pages instead of clusters.
vm.page-cluster = 0
# Keep directory/inode caches a little longer (helps file manager on HDD).
vm.vfs_cache_pressure = 50
# Start background writeback earlier so the desktop doesn't stall on big copies.
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
EOF
sysctl --system >/dev/null

# ---------------------------------------------------------------------------
# 4. earlyoom: kill the biggest offender before the system locks up
# ---------------------------------------------------------------------------
log "Configuring earlyoom"
cat > /etc/default/earlyoom <<'EOF'
# VistaRevive: act when free RAM < 5% AND free swap < 10%.
# Prefer killing browser tabs; never pick the display server or session.
# No quotes or spaces inside the regexes: systemd splits this variable on
# whitespace and passes quote characters through literally ('.' matches the space).
EARLYOOM_ARGS="-m 5 -s 10 -r 3600 --prefer (^|/)(firefox-esr|firefox|Isolated.Web.Co|Web.Content|chromium)$ --avoid (^|/)(Xorg|lightdm|xfce4-session|xfwm4|xfce4-panel|lxqt-session|openbox|systemd|sshd)$"
EOF
systemctl enable --now earlyoom >/dev/null
systemctl restart earlyoom

# ---------------------------------------------------------------------------
# 5. I/O scheduler: BFQ on spinning disks (better responsiveness under load),
#    mq-deadline on SSDs.
# ---------------------------------------------------------------------------
log "Setting I/O scheduler rule"
cat > /etc/udev/rules.d/60-vistarevive-iosched.rules <<'EOF'
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
EOF
modprobe bfq 2>/dev/null || true
echo bfq > /etc/modules-load.d/bfq.conf
udevadm control --reload
udevadm trigger --subsystem-match=block --action=change

# Weekly TRIM if an SSD is fitted later (harmless on HDD).
systemctl enable fstrim.timer >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 6. Journal size: cap logs so they don't grow on a small disk
# ---------------------------------------------------------------------------
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/90-vistarevive.conf <<'EOF'
[Journal]
SystemMaxUse=50M
EOF
systemctl restart systemd-journald

# ---------------------------------------------------------------------------
# 7. Boot speed
# ---------------------------------------------------------------------------
log "Trimming boot delays"
# Waiting for the network blocks boot by seconds and nothing here needs it.
systemctl disable --now NetworkManager-wait-online.service >/dev/null 2>&1 || true
# ModemManager probes serial ports at boot; the 6710b has no built-in modem we use.
if systemctl list-unit-files ModemManager.service >/dev/null 2>&1; then
  systemctl disable --now ModemManager.service >/dev/null 2>&1 || true
fi

# GRUB menu: 1 second instead of 5.
if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
  update-grub >/dev/null 2>&1
fi

# ---------------------------------------------------------------------------
# 8. Automatic security updates (project goal)
# ---------------------------------------------------------------------------
log "Enabling automatic security updates"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
cat <<EOF

Files written:
  /etc/systemd/zram-generator.conf
  /etc/sysctl.d/90-vistarevive.conf
  /etc/default/earlyoom
  /etc/udev/rules.d/60-vistarevive-iosched.rules
  /etc/modules-load.d/bfq.conf
  /etc/systemd/journald.conf.d/90-vistarevive.conf
  /etc/apt/apt.conf.d/20auto-upgrades
  /etc/fstab (swap priority / swapfile line)
  /etc/default/grub (GRUB_TIMEOUT=1)

Reboot now (sudo reboot), then send me the output of:
  swapon --show
  zramctl
  free -m
  cat /sys/block/sda/queue/scheduler
  systemd-analyze
  systemd-analyze blame | head -n 15
  systemctl --type=service --state=running --no-pager
EOF
