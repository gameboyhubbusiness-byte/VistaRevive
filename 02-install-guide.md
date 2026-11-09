# VistaRevive – Phase 2a: Minimal Debian 13 "Trixie" install

Goal: a bare, console-only Debian 13 (amd64) with no desktop. Every graphical
piece gets added later on purpose, so nothing heavy sneaks in.

## 1. Get the installer
- Download the **Debian 13 netinst ISO, amd64** (debian.org → "Download" → small
  installation image). Since Debian 12 the official images already include
  non-free firmware, so Intel Wi-Fi usually works during the install.
- Write it to USB (Etcher / Rufus in DD mode / `dd`).
- **Easiest path: plug in an Ethernet cable for the install.** Broadcom Wi-Fi
  (b43) cannot get its firmware during installation; Ethernet avoids that problem.

## 2. Installer choices
Boot with **F9**, pick the USB, choose **Install** (the text installer is lighter
than the graphical one on 1 GB).

| Screen | Choose |
|---|---|
| Language / location / keyboard | Your choice (e.g. English, Croatia, Croatian or US keyboard) |
| Hostname | `vistarevive` |
| Domain | leave empty |
| Root password | **leave empty** → your user gets `sudo` automatically |
| User | your name / username / password |
| Partitioning | **Guided – use entire disk** → **All files in one partition** |
| Mirror | a nearby one (e.g. `deb.debian.org`) |
| Popularity contest | No |
| **Software selection** | **untick everything except "standard system utilities"** |
| GRUB | Yes, install to the disk (`/dev/sda`) |

### Partitioning detail
Accept the guided layout as proposed, including the small swap partition it
creates. Phase 3 puts **zram** (compressed RAM) in front of it as the fast first
tier. If the installer's swap partition exists, the Phase 3 script uses it as
the backup tier. If not, the script creates a swapfile instead.

Filesystem: **ext4** (default). Do not pick btrfs; it costs RAM and swapfiles on
it need special handling.

## 3. First boot
You'll land at a text login. Log in, then:

```bash
sudo apt update && sudo apt full-upgrade -y
mkdir -p ~/vistarevive
```

Copy the project files into `~/vistarevive/` (USB stick: `lsblk` to find it,
then `sudo mount /dev/sdb1 /mnt && cp /mnt/vistarevive/* ~/vistarevive/`).

## 4. Run the driver script
```bash
cd ~/vistarevive
sudo bash 02-drivers.sh
sudo reboot
```

## 5. Test after reboot (send me the answers)
```bash
ip -br link                 # is there a wlan0 / wlp* interface?
nmcli dev wifi list         # do networks appear?
aplay -l                    # sound card listed?
speaker-test -c2 -t wav -l1 # do you hear "front left / front right"?
cat /sys/class/backlight/*/max_brightness   # which backlight devices exist?
free -m                     # RAM in use at the console
systemd-analyze             # boot time
```
Also try: **Fn + brightness keys**, and `systemctl suspend` (press power to wake;
does the screen and Wi-Fi come back?).

Wi-Fi connect from the console:
```bash
nmcli dev wifi connect "YourNetwork" --ask
```
