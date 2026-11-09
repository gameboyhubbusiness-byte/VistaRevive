#!/usr/bin/env bash
# VistaRevive - Phase 1: hardware report
# Run from a Debian live USB (or any Linux) on the HP Compaq 6710b:
#   bash 01-hw-report.sh
# Writes hw-report.txt in the current folder. Paste its contents back to Claude.

OUT="hw-report.txt"
: > "$OUT"

section() {
  echo -e "\n===== $1 =====" >> "$OUT"
  shift
  ( "$@" ) >> "$OUT" 2>&1 || echo "(command failed or not available)" >> "$OUT"
}

section "SYSTEM / BIOS"   sh -c 'for f in sys_vendor product_name product_version bios_version bios_date; do printf "%-16s %s\n" "$f:" "$(cat /sys/class/dmi/id/$f 2>/dev/null)"; done'
section "CPU"             sh -c 'lscpu | grep -E "Model name|Architecture|CPU\(s\)|Thread|MHz|Flags" | sed "s/Flags:.*\(vmx\).*/Flags: vmx present (VT-x supported)/"'
section "VT-x FLAG"       sh -c 'grep -qw vmx /proc/cpuinfo && echo "vmx: YES" || echo "vmx: NO (or disabled in BIOS)"'
section "MEMORY"          free -h
section "PCI DEVICES (GPU, Wi-Fi, audio, storage)" lspci -nn
section "GPU DETAIL"      sh -c 'lspci -k | grep -A3 -Ei "vga|display"'
section "NETWORK DETAIL"  sh -c 'lspci -k | grep -A3 -Ei "network|wireless|ethernet"'
section "USB DEVICES (Bluetooth, webcam, card reader)" lsusb
section "STORAGE"         lsblk -o NAME,SIZE,ROTA,TYPE,MODEL,TRAN
section "SATA MODE (AHCI or IDE)" sh -c 'lspci -k | grep -A3 -Ei "sata|ide"'
section "AUDIO"           sh -c 'cat /proc/asound/cards 2>/dev/null; lspci | grep -i audio'
section "MISSING FIRMWARE (dmesg)" sh -c 'dmesg 2>/dev/null | grep -iE "firmware|fw" | tail -n 30 || echo "run with sudo for dmesg"'
section "BATTERY"         sh -c 'cat /sys/class/power_supply/BAT*/uevent 2>/dev/null || echo "no battery info"'
section "KERNEL"          uname -a

echo "Done. Report saved to $(pwd)/$OUT"
