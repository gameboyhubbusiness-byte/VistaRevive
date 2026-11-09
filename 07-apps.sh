#!/usr/bin/env bash
# VistaRevive - Phase 7: everyday apps, tuned for low RAM
# Target: Debian 13 "trixie". Run after 06-boot-login.sh.
#
# Usage:
#   sudo bash 07-apps.sh                      install apps; BOTH office suites for benchmarking
#   sudo bash 07-apps.sh --with-falkon        also install Falkon to compare browsers
#   sudo bash 07-apps.sh --keep-office libreoffice   after benchmarking: remove AbiWord/Gnumeric
#   sudo bash 07-apps.sh --keep-office lite          after benchmarking: remove LibreOffice
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
log()  { echo -e "\e[1;34m[VistaRevive]\e[0m $*"; }
warn() { echo -e "\e[1;33m[warning]\e[0m $*"; }
available() { for p in "$@"; do
  if apt-cache show "$p" >/dev/null 2>&1; then echo "$p"; else warn "Package $p not found, skipping" >&2; fi
done; }
apt_install() { DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"; }

WITH_FALKON=0; KEEP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-falkon) WITH_FALKON=1 ;;
    --keep-office) KEEP="${2:-}"; shift ;;
    *) echo "Unknown option $1"; exit 1 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# After benchmarking: keep one office suite
# ---------------------------------------------------------------------------
if [[ -n "$KEEP" ]]; then
  case "$KEEP" in
    libreoffice) log "Removing AbiWord + Gnumeric"; apt-get purge -y abiword gnumeric || true ;;
    lite)
      log "Removing LibreOffice"; apt-get purge -y 'libreoffice*' || true
      W=$(basename "$(ls /usr/share/applications/*[Aa]bi[Ww]ord*.desktop 2>/dev/null | head -n1)" 2>/dev/null || true)
      C=$(basename "$(ls /usr/share/applications/*[Gg]numeric*.desktop 2>/dev/null | head -n1)" 2>/dev/null || true)
      if [[ -n "$W" && -n "$C" ]]; then
        sed -i "s/libreoffice-writer.desktop/$W/g; s/libreoffice-calc.desktop/$C/g" /etc/xdg/mimeapps.list
        for rc in /etc/xdg/xfce4/panel/whiskermenu-1.rc /home/*/.config/xfce4/panel/whiskermenu-1.rc; do
          [[ -f "$rc" ]] && sed -i "s/libreoffice-writer.desktop/$W/" "$rc"
        done
      fi ;;
    *) echo "--keep-office takes 'libreoffice' or 'lite'"; exit 1 ;;
  esac
  apt-get autoremove -y
  log "Done."; exit 0
fi

# ---------------------------------------------------------------------------
# 1. Packages
# ---------------------------------------------------------------------------
LANG_CODE="$(. /etc/default/locale 2>/dev/null; echo "${LANG:-en_US}" | cut -d_ -f1)"
mapfile -t PKGS < <(available \
  firefox-esr webext-ublock-origin-firefox \
  libreoffice-writer libreoffice-calc libreoffice-gtk3 \
  abiword gnumeric \
  fonts-liberation2 fonts-crosextra-carlito fonts-crosextra-caladea \
  "hunspell-$LANG_CODE" \
  atril mpv yt-dlp xclip xdotool \
  ristretto xarchiver 7zip unzip zip \
  mousepad galculator synaptic exo-utils xdg-utils \
  cups system-config-printer printer-driver-gutenprint printer-driver-hpcups)
(( WITH_FALKON )) && mapfile -t -O "${#PKGS[@]}" PKGS < <(available falkon)

log "Installing ${#PKGS[@]} packages (long download; LibreOffice is the big one)"
apt_install "${PKGS[@]}"

# ---------------------------------------------------------------------------
# 2. Firefox ESR: low-RAM defaults (users can still change them)
# ---------------------------------------------------------------------------
FFDIR=/usr/lib/firefox-esr
if [[ -d "$FFDIR" ]]; then
  log "Tuning Firefox ESR for low RAM"
  mkdir -p "$FFDIR/defaults/pref" "$FFDIR/distribution"
  cat > "$FFDIR/defaults/pref/vistarevive-lowram.js" <<'EOF'
// VistaRevive: Firefox ESR defaults for 1-2 GB RAM and a Core 2 Duo.
// Fewer processes. Trade-off: less site isolation than stock Firefox.
pref("dom.ipc.processCount", 2);
pref("dom.ipc.processCount.webIsolated", 1);
pref("fission.autostart", false);
// Unload background tabs when memory runs low; drop old session data.
pref("browser.tabs.unloadOnLowMemory", true);
pref("browser.sessionstore.interval", 60000);
pref("browser.sessionstore.max_tabs_undo", 5);
pref("browser.sessionhistory.max_entries", 20);
// Smaller caches (RAM and HDD).
pref("browser.cache.memory.capacity", 32768);
pref("browser.cache.disk.smart_size.enabled", false);
pref("browser.cache.disk.capacity", 262144);
// No speculative connections or prefetching.
pref("network.prefetch-next", false);
pref("network.dns.disablePrefetch", true);
pref("network.http.speculative-parallel-limit", 0);
pref("browser.urlbar.speculativeConnect.enabled", false);
// Video: this GPU cannot decode VP9/AV1, so ask sites (YouTube) for H.264,
// which the CPU decodes far more cheaply. Revert these two if a site breaks.
pref("media.av1.enabled", false);
pref("media.mediasource.vp9.enabled", false);
// Less animation and background work.
pref("toolkit.cosmeticAnimations.enabled", false);
pref("ui.prefersReducedMotion", 1);
pref("extensions.pocket.enabled", false);
pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
pref("browser.newtabpage.activity-stream.showSponsored", false);
pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
EOF
  # Policies: no telemetry/studies; uBlock Origin from AMO if Debian lacks the package
  UBLOCK=""
  if ! dpkg -l webext-ublock-origin-firefox 2>/dev/null | grep -q '^ii'; then
    UBLOCK=',
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
      }
    }'
  fi
  cat > "$FFDIR/distribution/policies.json" <<EOF
{
  "policies": {
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "DontCheckDefaultBrowser": true,
    "OverrideFirstRunPage": "",
    "UserMessaging": { "MoreFromMozilla": false, "SkipOnboarding": true, "FeatureRecommendations": false }$UBLOCK
  }
}
EOF
fi

# ---------------------------------------------------------------------------
# 3. LibreOffice: lighter defaults (system-wide registry layer)
# ---------------------------------------------------------------------------
if [[ -d /etc/libreoffice/registry ]]; then
  log "Tuning LibreOffice"
  cat > /etc/libreoffice/registry/vistarevive.xcd <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<oor:data xmlns:xs="http://www.w3.org/2001/XMLSchema"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xmlns:oor="http://openoffice.org/2001/registry">
  <dependency file="main"/>
  <oor:component-data oor:package="org.openoffice.Office" oor:name="Common">
    <node oor:name="Undo"><prop oor:name="Steps" oor:op="fuse"><value>30</value></prop></node>
    <node oor:name="Misc"><prop oor:name="UseOpenCL" oor:op="fuse"><value>false</value></prop></node>
  </oor:component-data>
</oor:data>
EOF
fi

# ---------------------------------------------------------------------------
# 4. mpv: tuned for software decoding; YouTube links via yt-dlp
# ---------------------------------------------------------------------------
log "Configuring mpv"
mkdir -p /etc/mpv
cat > /etc/mpv/mpv.conf <<'EOF'
# VistaRevive: Core 2 Duo + old GPU
profile=fast
hwdec=auto-safe
vo=gpu,xv,x11
keep-open=yes
cache=yes
demuxer-max-bytes=40MiB
demuxer-max-back-bytes=10MiB
# Prefer H.264 at 720p for online video (decodes in software without dropping frames)
ytdl-format=bestvideo[height<=?720][vcodec^=avc1]+bestaudio/best[height<=?720]
screenshot-directory=~~desktop/
EOF

# "Play video link" helper: plays the URL on the clipboard in mpv.
# Watching YouTube this way uses far less CPU and RAM than the browser.
cat > /usr/local/bin/vistarevive-play-url <<'EOF'
#!/usr/bin/env bash
url="${1:-$(xclip -selection clipboard -o 2>/dev/null)}"
if [[ "$url" != http* ]]; then
  notify-send "Play video link" "Copy a video link first (Ctrl+C), then try again." 2>/dev/null || true
  exit 1
fi
notify-send "Play video link" "Opening $url" 2>/dev/null || true
exec mpv --force-window=immediate "$url"
EOF
chmod 755 /usr/local/bin/vistarevive-play-url
cat > /usr/share/applications/vistarevive-play-url.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Play Video Link
Comment=Play a copied YouTube (or other) link in the lightweight video player
Exec=vistarevive-play-url
Icon=mpv
Categories=AudioVideo;Video;Player;
EOF

# yt-dlp updater: YouTube changes often and Debian stable's yt-dlp can lag.
# Installs the official release to /usr/local/bin, which takes precedence.
cat > /usr/local/bin/vistarevive-update-ytdlp <<'EOF'
#!/usr/bin/env bash
# Usage: sudo vistarevive-update-ytdlp
set -e
[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
tmp=$(mktemp)
curl -fL --max-time 120 -o "$tmp" https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp
install -m 755 "$tmp" /usr/local/bin/yt-dlp && rm -f "$tmp"
/usr/local/bin/yt-dlp --version
EOF
chmod 755 /usr/local/bin/vistarevive-update-ytdlp

# ---------------------------------------------------------------------------
# 5. Default applications
# ---------------------------------------------------------------------------
log "Setting default applications"
OFFICE_W=libreoffice-writer.desktop; OFFICE_C=libreoffice-calc.desktop
cat > /etc/xdg/mimeapps.list <<EOF
[Default Applications]
x-scheme-handler/http=firefox-esr.desktop
x-scheme-handler/https=firefox-esr.desktop
text/html=firefox-esr.desktop
application/pdf=atril.desktop
text/plain=org.xfce.mousepad.desktop
image/png=org.xfce.ristretto.desktop
image/jpeg=org.xfce.ristretto.desktop
image/gif=org.xfce.ristretto.desktop
image/webp=org.xfce.ristretto.desktop
video/mp4=mpv.desktop
video/x-matroska=mpv.desktop
video/webm=mpv.desktop
video/x-msvideo=mpv.desktop
audio/mpeg=mpv.desktop
audio/ogg=mpv.desktop
audio/flac=mpv.desktop
application/zip=xarchiver.desktop
application/x-7z-compressed=xarchiver.desktop
application/x-compressed-tar=xarchiver.desktop
application/vnd.openxmlformats-officedocument.wordprocessingml.document=$OFFICE_W
application/msword=$OFFICE_W
application/vnd.oasis.opendocument.text=$OFFICE_W
application/vnd.openxmlformats-officedocument.spreadsheetml.sheet=$OFFICE_C
application/vnd.ms-excel=$OFFICE_C
application/vnd.oasis.opendocument.spreadsheet=$OFFICE_C
text/csv=$OFFICE_C
EOF

# XFCE "Web Browser" helper -> Firefox ESR
mkdir -p /usr/share/xfce4/helpers
cat > /usr/share/xfce4/helpers/firefox-esr.desktop <<'EOF'
[Desktop Entry]
NoDisplay=true
Version=1.0
Type=X-XFCE-Helper
X-XFCE-Category=WebBrowser
X-XFCE-Commands=firefox-esr
X-XFCE-CommandsWithParameter=firefox-esr "%s"
Icon=firefox-esr
Name=Firefox ESR
EOF
printf 'WebBrowser=firefox-esr\nFileManager=thunar\nTerminalEmulator=xfce4-terminal\n' > /etc/xdg/xfce4/helpers.rc

# Start-menu favourites: real apps instead of generic helpers
FAV="favorites=firefox-esr.desktop,thunar.desktop,libreoffice-writer.desktop,atril.desktop,vistarevive-play-url.desktop,xfce-settings-manager.desktop"
for rc in /etc/xdg/xfce4/panel/whiskermenu-1.rc /home/*/.config/xfce4/panel/whiskermenu-1.rc; do
  [[ -f "$rc" ]] && sed -i "s|^favorites=.*|$FAV|" "$rc"
done

# ---------------------------------------------------------------------------
# 6. Printing: CUPS starts only when something prints (saves RAM at idle)
# ---------------------------------------------------------------------------
if systemctl list-unit-files cups.socket >/dev/null 2>&1; then
  systemctl disable --now cups.service >/dev/null 2>&1 || true
  systemctl enable --now cups.socket cups.path >/dev/null 2>&1 || true
fi
for u in /home/*; do
  name=$(basename "$u")
  id "$name" >/dev/null 2>&1 && usermod -aG lpadmin "$name" 2>/dev/null || true
done

# earlyoom: also prefer killing Falkon/LibreOffice workers over the desktop
if [[ -f /etc/default/earlyoom ]]; then
  sed -i 's/chromium)\$/chromium|QtWebEngineProc|falkon)$/' /etc/default/earlyoom
  systemctl restart earlyoom || true
fi

cat <<'EOF'

Phase 7 installed. Log out and back in.

TEST LIST:
 1. Firefox: YouTube video plays at 480p/720p without stutter? Gmail loads?
    about:addons shows uBlock Origin?
 2. Copy a YouTube link, start menu -> "Play Video Link": plays in mpv?
    (If mpv says the video is unavailable: sudo vistarevive-update-ytdlp)
 3. Double-click a PDF, a .docx, a photo, a video, a .zip: right app opens?
 4. Printer: Start menu -> Print Settings -> Add (if you have a printer).
 5. Run the benchmarks (as your user, inside the desktop, close other apps):
      bash 07-benchmark.sh idle
      bash 07-benchmark.sh browser firefox-esr
      bash 07-benchmark.sh office
    and send me ~/vistarevive-benchmarks.md
EOF
