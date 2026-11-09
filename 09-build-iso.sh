#!/usr/bin/env bash
# VistaRevive - Phase 9: build an installable VistaRevive ISO with live-build
#
# Run on any Debian 13 "trixie" machine (the 6710b works, just slowly; a faster
# PC or a VM is nicer). Needs ~12 GB free disk and internet. Takes 30-90 min.
#
#   sudo apt install live-build
#   sudo bash 09-build-iso.sh                       build ./iso-build/vistarevive-<date>-amd64.iso
#   sudo bash 09-build-iso.sh --office lite         ship AbiWord + Gnumeric instead of LibreOffice
#   sudo bash 09-build-iso.sh --office both         ship both suites
#   sudo bash 09-build-iso.sh --config-only         prepare ./iso-build/config without building
#   sudo bash 09-build-iso.sh --dir /path/to/build  use another build folder
#
# The ISO boots a live VistaRevive desktop (user "user", password "live") and
# offers "Install" in the boot menu (Debian's installer, copies the live system).
# Everything comes from the phase scripts in this folder, so the ISO always
# matches what the scripts do on an installed system.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
log()  { echo -e "\e[1;34m[VistaRevive]\e[0m $*"; }
warn() { echo -e "\e[1;33m[warning]\e[0m $*"; }
HERE="$(cd "$(dirname "$0")" && pwd)"

OFFICE=libreoffice; CONFIG_ONLY=0; BUILD="$HERE/iso-build"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --office) OFFICE="${2:-}"; shift ;;
    --config-only) CONFIG_ONLY=1 ;;
    --dir) BUILD="$(realpath -m "${2:-}")"; shift ;;
    *) echo "Unknown option $1"; exit 1 ;;
  esac
  shift
done
[[ "$OFFICE" =~ ^(libreoffice|lite|both)$ ]] || { echo "--office takes libreoffice, lite or both"; exit 1; }

# ---------------------------------------------------------------------------
# 0. Checks
# ---------------------------------------------------------------------------
command -v lb >/dev/null || { echo "live-build missing:  sudo apt install live-build"; exit 1; }
. /etc/os-release
[[ "${VERSION_CODENAME:-}" == "trixie" ]] || warn "Build host is '${VERSION_CODENAME:-unknown}', not trixie. Building on Debian 13 is safest."
for f in 03-performance.sh 04-desktop.sh 05-theme.sh 06-boot-login.sh 07-apps.sh 08-welcome.sh \
         vistarevive-art.tar.gz welcome/vistarevive-welcome.py; do
  [[ -e "$HERE/$f" ]] || { echo "Missing project file: $f"; exit 1; }
done
free_gb=$(df -BG --output=avail "$(dirname "$BUILD")" | tail -n1 | tr -dc 0-9)
(( free_gb >= 12 )) || warn "Only ${free_gb} GB free; the build needs about 12 GB."

mkdir -p "$BUILD"
cd "$BUILD"
if [[ -d config ]]; then
  log "Cleaning previous build"
  lb clean --purge >/dev/null 2>&1 || true
  rm -rf config
fi

# ---------------------------------------------------------------------------
# 1. live-build configuration
# ---------------------------------------------------------------------------
log "Configuring live-build"
lb config \
  --distribution trixie \
  --architectures amd64 \
  --linux-flavours amd64 \
  --archive-areas "main contrib non-free non-free-firmware" \
  --security true \
  --updates true \
  --apt-recommends false \
  --firmware-chroot true \
  --firmware-binary true \
  --debian-installer live \
  --debian-installer-gui true \
  --binary-image iso-hybrid \
  --memtest none \
  --chroot-squashfs-compression-type zstd \
  --chroot-squashfs-compression-level 19 \
  --bootappend-live "boot=live components quiet splash hostname=vistarevive username=user" \
  --iso-application "VistaRevive" \
  --iso-volume "VistaRevive" \
  --iso-publisher "VistaRevive project" \
  --cache true

# ---------------------------------------------------------------------------
# 2. Base packages: drivers and firmware for EVERY 6710b variant
#    (the ISO can't know if it'll meet an X3100 or an X1350, Intel or Broadcom)
# ---------------------------------------------------------------------------
mkdir -p config/package-lists
cat > config/package-lists/vistarevive-base.list.chroot <<'EOF'
# Firmware and drivers for all HP Compaq 6710b variants
firmware-misc-nonfree
firmware-iwlwifi
firmware-amd-graphics
intel-microcode
libgl1-mesa-dri
mesa-utils
xserver-xorg-video-radeon
# Basics the phase scripts expect
network-manager
alsa-utils
pciutils
usbutils
acpi
acpid
bluez
sudo
curl
ca-certificates
locales
console-setup
keyboard-configuration
EOF

# ---------------------------------------------------------------------------
# 3. Files baked into the image
# ---------------------------------------------------------------------------
INC=config/includes.chroot
mkdir -p "$INC/usr/share/vistarevive/source/welcome" "$INC/usr/share/vistarevive/source/art" \
         "$INC/usr/local/sbin" "$INC/etc/systemd/system" "$INC/etc/default/grub.d"

log "Copying project files into the image"
for f in "$HERE"/0*.sh "$HERE"/0*.md "$HERE"/README.md "$HERE"/vistarevive-art.tar.gz; do
  [[ -f "$f" ]] && cp "$f" "$INC/usr/share/vistarevive/source/"
done
cp "$HERE/welcome/vistarevive-welcome.py" "$INC/usr/share/vistarevive/source/welcome/"
[[ -f "$HERE/art/make-art.py" ]] && cp "$HERE/art/make-art.py" "$INC/usr/share/vistarevive/source/art/"

# Boot options for the INSTALLED system (the installer writes /etc/default/grub;
# Debian's GRUB also reads /etc/default/grub.d/*.cfg)
cat > "$INC/etc/default/grub.d/vistarevive.cfg" <<'EOF'
# VistaRevive: short menu, splash screen, quiet boot
GRUB_TIMEOUT=1
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 vt.global_cursor_default=0"
GRUB_DISTRIBUTOR="VistaRevive"
EOF

# Hardware detection at every boot (one image, any 6710b variant)
cat > "$INC/usr/local/sbin/vistarevive-detect-hw" <<'EOF'
#!/usr/bin/env bash
# Writes /etc/vistarevive/hardware.conf from PCI IDs (same rules as 02-drivers.sh)
PCI="$(lspci -nn 2>/dev/null)"
GPU=unknown; WIFI=none
if   grep -qiE '\[8086:2a0[23]\]' <<<"$PCI"; then GPU=intel-x3100
elif grep -qiE 'VGA.*\[1002:'     <<<"$PCI"; then GPU=ati-x1350; fi
if   grep -qiE '\[8086:(4222|4227|4229|4230)\]' <<<"$PCI"; then WIFI=intel
elif grep -qiE '\[14e4:(4311|4312|4315)\]'      <<<"$PCI"; then WIFI=broadcom
elif grep -qi  'Network controller'             <<<"$PCI"; then WIFI=other; fi
mkdir -p /etc/vistarevive
printf '# Written by vistarevive-detect-hw on %s\nGPU=%s\nWIFI=%s\n' "$(date -I)" "$GPU" "$WIFI" \
  > /etc/vistarevive/hardware.conf
EOF

# Disk swap on the installed system (never in the live session)
cat > "$INC/usr/local/sbin/vistarevive-swap-setup" <<'EOF'
#!/usr/bin/env bash
# Creates a backup swapfile once, if the system has no disk swap yet.
[[ -d /run/live ]] && exit 0                                     # live session: RAM only
swapon --show=NAME --noheadings 2>/dev/null | grep -qv zram && exit 0   # disk swap active
grep -qE '^[^#].*\sswap\s' /etc/fstab && exit 0                  # configured, not yet active
[[ -f /swapfile ]] && exit 0
case "$(findmnt -no FSTYPE /)" in ext4|xfs) ;; *) exit 0 ;; esac
ram_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
size=$(( ram_mb < 2048 ? 2048 : 1024 ))
fallocate -l "${size}M" /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null || exit 0
echo '/swapfile none swap sw,pri=10 0 0' >> /etc/fstab
swapon -p 10 /swapfile
EOF

cat > "$INC/etc/systemd/system/vistarevive-firstboot.service" <<'EOF'
[Unit]
Description=VistaRevive hardware detection and swap setup
After=local-fs.target
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vistarevive-detect-hw
ExecStart=/usr/local/sbin/vistarevive-swap-setup

[Install]
WantedBy=multi-user.target
EOF

# ---------------------------------------------------------------------------
# 4. The hook: run phases 3-8 inside the image
# ---------------------------------------------------------------------------
mkdir -p config/hooks/normal
cat > config/hooks/normal/0500-vistarevive.hook.chroot <<EOF
#!/bin/bash
# VistaRevive: apply phases 3-8 inside the live-build chroot
set -e
export VISTAREVIVE_BUILD=1 DEBIAN_FRONTEND=noninteractive
SRC=/usr/share/vistarevive/source
OFFICE=$OFFICE

# Shims: a chroot shares the BUILD HOST's kernel. Never let the phase scripts
# change the host's sysctls, load modules on it, retrigger its udev or touch
# running services. 'systemctl enable/disable/set-default' still work offline.
SHIM=/tmp/vr-shim
mkdir -p "\$SHIM"
cat > "\$SHIM/systemctl" <<'SH'
#!/bin/bash
args=()
for a in "\$@"; do [[ "\$a" == --now ]] || args+=("\$a"); done
for a in "\${args[@]}"; do
  case "\$a" in
    start|stop|restart|reload|try-restart|reload-or-restart|daemon-reload|is-active|status|kill) exit 0 ;;
    enable|disable|mask|unmask|set-default|list-unit-files|is-enabled|preset) break ;;
  esac
done
exec /usr/bin/systemctl "\${args[@]}"
SH
for t in sysctl modprobe udevadm update-grub swapon swapoff; do
  printf '#!/bin/sh\nexit 0\n' > "\$SHIM/\$t"
done
chmod 755 "\$SHIM"/*
export PATH="\$SHIM:\$PATH"

apt-get update

# Broadcom b43 firmware is downloaded by its installer package; don't fail
# the whole build if Broadcom's server is unreachable.
apt-get install -y --no-install-recommends firmware-b43-installer \
  || echo "WARNING: b43 firmware download failed (Broadcom Wi-Fi only)."

for s in 03-performance.sh 04-desktop.sh 05-theme.sh 06-boot-login.sh 07-apps.sh 08-welcome.sh; do
  echo "================ VistaRevive: \$s ================"
  bash "\$SRC/\$s"
done

case "\$OFFICE" in
  libreoffice|lite) bash "\$SRC/07-apps.sh" --keep-office "\$OFFICE" ;;
esac

systemctl enable vistarevive-firstboot.service
chmod 755 /usr/local/sbin/vistarevive-detect-hw /usr/local/sbin/vistarevive-swap-setup

# Don't ship build leftovers
rm -rf "\$SHIM" /etc/vistarevive/hardware.conf
apt-get clean
EOF
chmod 755 config/hooks/normal/0500-vistarevive.hook.chroot

# ---------------------------------------------------------------------------
# 5. Installer answers: only safe defaults, partitioning stays interactive
# ---------------------------------------------------------------------------
mkdir -p config/includes.installer
cat > config/includes.installer/preseed.cfg <<'EOF'
# VistaRevive installer defaults. Disk partitioning is still asked, so the
# installer never wipes a disk without you choosing it.
d-i passwd/root-login boolean false
d-i passwd/user-default-groups string audio cdrom dip floppy video plugdev netdev bluetooth lpadmin scanner
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
popularity-contest popularity-contest/participate boolean false
EOF

if (( CONFIG_ONLY )); then
  log "Config ready in $BUILD/config (not built: --config-only)"
  exit 0
fi

# ---------------------------------------------------------------------------
# 6. Build
# ---------------------------------------------------------------------------
log "Building the ISO (30-90 minutes). Full log: $BUILD/build.log"
lb build 2>&1 | tee build.log
ISO=$(ls -1 ./*.iso 2>/dev/null | head -n1 || true)
[[ -n "$ISO" ]] || { echo "Build failed: no ISO produced. See $BUILD/build.log"; exit 1; }
NAME="vistarevive-$(date +%Y%m%d)-amd64.iso"
mv "$ISO" "$NAME"
sha256sum "$NAME" > "$NAME.sha256"
log "Done: $BUILD/$NAME ($(du -h "$NAME" | cut -f1))"

cat <<EOF

NEXT STEPS:
 1. Write it to a USB stick (4 GB+):
      sudo dd if=$BUILD/$NAME of=/dev/sdX bs=4M status=progress oflag=sync
    (replace sdX with the stick; check with lsblk first, dd overwrites it)
 2. On the 6710b: F9 at power-on, pick the USB.
    - "Live" boots the desktop to try it (user: user, password: live)
    - "Install" installs VistaRevive to the disk
 3. After installing: the first boot detects GPU/Wi-Fi and creates swap.
    Broadcom Wi-Fi without signal? Plug in Ethernet once and run:
      sudo apt install --reinstall firmware-b43-installer
EOF
