# VistaRevive

A lightweight, Vista-inspired Debian 13 "Trixie" system for the HP Compaq 6710b.
Keep every file in `~/vistarevive/` and run scripts in number order, rebooting
between phases.

| File | Phase | Run where | What it does |
|---|---|---|---|
| `01-hw-report.sh` | 1 | Debian live USB | Collects GPU, Wi-Fi, disk, BIOS info into `hw-report.txt` |
| `02-install-guide.md` | 2 | — | Step-by-step minimal netinstall choices |
| `02-drivers.sh` | 2 | Installed system | Enables non-free repos, installs GPU/Wi-Fi/firmware by PCI ID |
| `03-performance.sh` | 3 | Installed system | zram, disk swap, earlyoom, BFQ, journal cap, boot trims, auto security updates |
| `04-desktop.sh` | 4 | Installed system | XFCE, Vista-order taskbar, Whisker start menu, Win-key shortcuts |
| `05-theme.sh` | 5 | Installed system | Glass/Basic window frames, glossy GTK theme, orb, wallpaper, icons, cursor, sounds |
| `06-boot-login.sh` | 6 | Installed system | Login screen, Plymouth boot splash, Conky sidebar (clock, CPU, RAM, weather, battery) |
| `07-apps.sh` | 7 | Installed system | Firefox ESR (low-RAM tuned, uBlock), office suites, PDF/video/image/archive apps, printing, default apps |
| `07-benchmark.sh` | 7 | Inside the desktop | Measures idle RAM, browser 1/5 tabs, LibreOffice vs AbiWord/Gnumeric |
| `08-welcome.sh` | 8 | Installed system | Installs the Welcome Center, password agent, network editor |
| `welcome/vistarevive-welcome.py` | 8 | (used by 08) | Welcome Center app (Python + GTK3) |
| `09-build-iso.sh` | 9 | Any Debian 13 PC | Builds the installable VistaRevive ISO with live-build (runs phases 3–8 inside the image) |
| `vistarevive-art.tar.gz` | 5–6 | (used by 05) | Prebuilt original artwork |
| `art/make-art.py` | 5–6 | Any Linux | Regenerates all artwork from code (python3-pil, python3-numpy) |
| `vistarevive-preview.png` | — | — | What Phases 5–6 should look like |

## Commands installed for you
- `vistarevive-aero on|off|status` – glass "Aero" look vs. fast opaque "Basic" look
- `vistarevive-firstlogin --force` – re-apply all VistaRevive desktop settings for your user
- `vistarevive-welcome` – Welcome Center (`--info` prints the system summary)
- `vistarevive-play-url` – plays the copied video link in mpv (menu: "Play Video Link")
- `sudo vistarevive-update-ytdlp` – fetch the latest yt-dlp when YouTube playback in mpv breaks
- `vistarevive-weather` – sidebar weather (set `LOCATION="City"` in
  `~/.config/vistarevive/weather.conf`; without it wttr.in guesses from your IP address)

## Two ways to install
1. **Scripts on a fresh Debian 13** (what the phases describe): follow `02-install-guide.md`,
   then run `02` … `08` in order.
2. **The ISO** (after Phase 9): `sudo apt install live-build && sudo bash 09-build-iso.sh`,
   write the ISO to USB, boot, choose *Install*. One image fits every 6710b variant:
   GPU/Wi-Fi are detected at each boot (`vistarevive-firstboot.service`), and the
   installed system creates its swapfile on first boot.

## Artwork
All artwork (wallpapers, start orb, window frames, boot splash, user tile, sounds)
is generated from `art/make-art.py`. No Microsoft logos, wallpapers, sounds or names.
Icons: Oxygen (LGPL, from Debian). Cursor: DMZ-White (from Debian).

## App choices (Phase 7)
| Need | Pick | Why |
|---|---|---|
| Browser | Firefox ESR, 2 content processes, site isolation off | Lowest RAM of the engines that fully run Gmail, Docs and YouTube; security updates for a year at a time |
| Video | mpv | Software H.264 decode; "Play Video Link" plays YouTube with a fraction of the browser's RAM and CPU |
| Documents | LibreOffice **or** AbiWord + Gnumeric | Decided by `07-benchmark.sh office` on this laptop |
| PDF | Atril | GTK3, light, simple toolbar |
| Images / archives / text | Ristretto / Xarchiver / Mousepad | XFCE-native, tiny |
| Printing | CUPS (on demand) + system-config-printer | Daemon starts only when you print |

## Progress
- [~] Phase 1 – Hardware identification (script ready, waiting for `hw-report.txt`)
- [~] Phase 2 – Minimal install + drivers (ready, untested; handles X3100/X1350, Intel/Broadcom)
- [~] Phase 3 – Performance base (ready, untested)
- [~] Phase 4 – Desktop, panel, start menu (ready, untested)
- [~] Phase 5 – Vista-inspired theme (ready, untested)
- [~] Phase 6 – Login screen, boot splash, gadgets (ready, untested)
- [~] Phase 7 – Apps + low-RAM tuning + benchmarks (ready, untested; office pick waits for benchmark)
- [~] Phase 8 – Welcome Center (ready; logic tested, GUI untested)
- [~] Phase 9 – Reproducible ISO build (config generation tested; full build untested)
- [ ] Phase 10 – Testing and polish

## Hardware (fill in from hw-report.txt)
- GPU: ?
- Wi-Fi: ?
- Disk: ?
- BIOS version: ?
