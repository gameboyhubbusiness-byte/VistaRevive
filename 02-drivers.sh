#!/usr/bin/env bash
# VistaRevive - Phase 2b: drivers and firmware for the HP Compaq 6710b
# Target: Debian 13 "trixie", amd64, fresh minimal install.
# Usage: sudo bash 02-drivers.sh
# Safe to run more than once. Detects GPU / Wi-Fi by PCI ID; never guesses.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }

log()  { echo -e "\e[1;34m[VistaRevive]\e[0m $*"; }
warn() { echo -e "\e[1;33m[warning]\e[0m $*"; }

. /etc/os-release
CODENAME="${VERSION_CODENAME:-trixie}"
log "Debian $VERSION_ID ($CODENAME) detected"

# ---------------------------------------------------------------------------
# 1. Enable contrib, non-free and non-free-firmware
# ---------------------------------------------------------------------------
if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
  log "Updating deb822 sources (debian.sources)"
  cp -n /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/debian.sources.bak || true
  sed -i -E 's/^Components:.*/Components: main contrib non-free non-free-firmware/' \
    /etc/apt/sources.list.d/debian.sources
else
  log "Rewriting /etc/apt/sources.list (backup: sources.list.bak)"
  [[ -f /etc/apt/sources.list ]] && cp -n /etc/apt/sources.list /etc/apt/sources.list.bak || true
  cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian ${CODENAME} main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${CODENAME}-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${CODENAME}-security main contrib non-free non-free-firmware
EOF
fi
apt-get update

PCI="$(lspci -nn)"
has_pci() { grep -qiE "$1" <<<"$PCI"; }

# Base packages for every 6710b variant
PKGS=(
  firmware-misc-nonfree   # misc firmware incl. Broadcom tg3 Ethernet
  intel-microcode         # CPU microcode updates for the Core 2 Duo
  network-manager         # nmcli now, tray applet later
  alsa-utils              # aplay, speaker-test, alsamixer
  pciutils usbutils       # lspci / lsusb
  acpi acpid              # battery info, lid/power button events
)

# ---------------------------------------------------------------------------
# 2. GPU
# ---------------------------------------------------------------------------
# Intel GM965 / GMA X3100: 8086:2a02 (and 8086:2a03 second function)
# ATI Mobility Radeon X1350 is an RV515 (R500 family): vendor 1002
if has_pci '\[8086:2a0[23]\]'; then
  GPU="intel-x3100"
  log "GPU: Intel GMA X3100 -> kernel i915 + Mesa 'crocus' via the modesetting driver"
  # No xserver-xorg-video-intel: the built-in modesetting driver is the
  # maintained path for this generation and supports compositing better.
  PKGS+=(libgl1-mesa-dri mesa-utils)
elif has_pci 'VGA.*\[1002:'; then
  GPU="ati-x1350"
  log "GPU: ATI Radeon (R500 family) -> kernel radeon + Mesa r300"
  PKGS+=(firmware-amd-graphics libgl1-mesa-dri mesa-utils xserver-xorg-video-radeon)
else
  GPU="unknown"
  warn "GPU not recognised. Send me: lspci -nn | grep -Ei 'vga|display'"
fi

# ---------------------------------------------------------------------------
# 3. Wi-Fi
# ---------------------------------------------------------------------------
# Intel PRO/Wireless 3945ABG: 8086:4222 / 8086:4227
# Intel Wireless 4965AGN:     8086:4229 / 8086:4230
# Broadcom BCM4311: 14e4:4311 / 14e4:4312   BCM4312: 14e4:4315
WIFI="none"
if has_pci '\[8086:(4222|4227|4229|4230)\]'; then
  WIFI="intel"
  log "Wi-Fi: Intel 3945/4965 -> firmware-iwlwifi"
  PKGS+=(firmware-iwlwifi)
elif has_pci '\[14e4:(4311|4312|4315)\]'; then
  WIFI="broadcom"
  log "Wi-Fi: Broadcom BCM4311/4312 -> open b43 driver + extracted firmware"
  # firmware-b43-installer downloads the firmware at install time, so this
  # step needs a working (Ethernet) connection. Alternative if b43 misbehaves:
  #   apt install linux-headers-amd64 broadcom-sta-dkms   (proprietary 'wl')
  PKGS+=(firmware-b43-installer)
elif has_pci 'Network controller'; then
  WIFI="other"
  warn "Unrecognised Wi-Fi chip. Send me: lspci -nn | grep -i network"
fi

# ---------------------------------------------------------------------------
# 4. Bluetooth (only if a Bluetooth USB device is present)
# ---------------------------------------------------------------------------
if lsusb | grep -qi bluetooth; then
  log "Bluetooth adapter found -> bluez"
  PKGS+=(bluez)
fi

# ---------------------------------------------------------------------------
# 5. Install
# ---------------------------------------------------------------------------
log "Installing: ${PKGS[*]}"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PKGS[@]}"

# Let NetworkManager manage interfaces that the installer put in
# /etc/network/interfaces (keep only loopback there), otherwise nmcli ignores them.
if [[ -f /etc/network/interfaces ]] && grep -qE '^(allow-hotplug|auto) +(e|w)' /etc/network/interfaces; then
  log "Handing network interfaces over to NetworkManager (backup: interfaces.bak)"
  cp -n /etc/network/interfaces /etc/network/interfaces.bak
  cat > /etc/network/interfaces <<'EOF'
# Managed by NetworkManager (VistaRevive). Original saved as interfaces.bak
source /etc/network/interfaces.d/*
auto lo
iface lo inet loopback
EOF
fi
systemctl enable NetworkManager >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 6. Record what we found (used by later phases and the ISO build)
# ---------------------------------------------------------------------------
mkdir -p /etc/vistarevive
cat > /etc/vistarevive/hardware.conf <<EOF
# Written by 02-drivers.sh on $(date -I)
GPU=$GPU
WIFI=$WIFI
EOF
log "Saved detection results to /etc/vistarevive/hardware.conf"
cat /etc/vistarevive/hardware.conf

log "Done. Reboot now: sudo reboot"
log "Then run the tests listed in 02-install-guide.md, section 5."
