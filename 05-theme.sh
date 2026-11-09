#!/usr/bin/env bash
# VistaRevive - Phase 5: Vista-inspired look (original artwork only)
# Target: Debian 13 "trixie". Run after 04-desktop.sh.
# Usage: sudo bash 05-theme.sh
#
# Needs ONE of these next to this script:
#   vistarevive-art.tar.gz   (prebuilt artwork, recommended)
#   art/make-art.py          (regenerates the artwork; installs python3-pil/numpy)
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
log()  { echo -e "\e[1;34m[VistaRevive]\e[0m $*"; }
warn() { echo -e "\e[1;33m[warning]\e[0m $*"; }
HERE="$(cd "$(dirname "$0")" && pwd)"

# Install only the packages that exist in this Debian release
available() { for p in "$@"; do
  if apt-cache show "$p" >/dev/null 2>&1; then echo "$p"; else warn "Package $p not found, skipping" >&2; fi
done; }

# ---------------------------------------------------------------------------
# 1. Packages: icons, cursor, GTK2 fallback, event sounds, font, Qt matching
# ---------------------------------------------------------------------------
mapfile -t PKGS < <(available \
  oxygen-icon-theme dmz-cursor-theme \
  gnome-themes-extra gtk2-engines-pixbuf \
  libcanberra-gtk3-module libcanberra-pulse \
  fonts-open-sans \
  qt5-gtk-platformtheme qt6-gtk-platformtheme \
  gtk-update-icon-cache)
log "Installing: ${PKGS[*]}"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PKGS[@]}"

# ---------------------------------------------------------------------------
# 2. Artwork: prebuilt tarball, or generate it here
# ---------------------------------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if [[ -f "$HERE/vistarevive-art.tar.gz" ]]; then
  log "Using prebuilt artwork"
  tar -xzf "$HERE/vistarevive-art.tar.gz" -C "$WORK"
elif [[ -f "$HERE/art/make-art.py" ]]; then
  log "Generating artwork (installs python3-pil and python3-numpy)"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3-pil python3-numpy
  python3 "$HERE/art/make-art.py" "$WORK/art-out"
else
  echo "Missing vistarevive-art.tar.gz or art/make-art.py next to this script."; exit 1
fi
ART="$WORK/art-out"

log "Installing themes, icons, sounds, wallpapers"
cp -r "$ART/themes/." /usr/share/themes/
cp -r "$ART/icons/hicolor/." /usr/share/icons/hicolor/
mkdir -p /usr/share/sounds /usr/share/backgrounds/vistarevive /usr/share/vistarevive
cp -r "$ART/sounds/VistaRevive" /usr/share/sounds/
cp "$ART/backgrounds/"*.png /usr/share/backgrounds/vistarevive/
cp -r "$ART/vistarevive/." /usr/share/vistarevive/
cp -r "$ART/plymouth" /usr/share/vistarevive/        # installed by Phase 6
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qf /usr/share/icons/hicolor || true

# Cursor for the whole system (also the login screen)
if [[ -f /usr/share/icons/DMZ-White/cursor.theme ]]; then
  update-alternatives --set x-cursor-theme /usr/share/icons/DMZ-White/cursor.theme >/dev/null 2>&1 || true
fi

# Our round orb as the start button
sed -i 's|^button-icon=.*|button-icon=vistarevive-start|' /etc/xdg/xfce4/panel/whiskermenu-1.rc

# Qt apps follow the GTK theme
if dpkg -l qt5-gtk-platformtheme qt6-gtk-platformtheme 2>/dev/null | grep -q '^ii'; then
  echo 'export QT_QPA_PLATFORMTHEME=gtk3' > /etc/X11/Xsession.d/90vistarevive-qt
fi

# Login chime
cat > /etc/xdg/autostart/vistarevive-login-sound.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=VistaRevive login sound
Exec=sh -c "sleep 2; pw-play /usr/share/sounds/VistaRevive/stereo/desktop-login.wav"
OnlyShowIn=XFCE;
NoDisplay=true
EOF

# ---------------------------------------------------------------------------
# 3. Aero switch v2: compositing + matching window theme (+ sidebar, Phase 6)
# ---------------------------------------------------------------------------
log "Updating vistarevive-aero"
cat > /usr/local/bin/vistarevive-aero <<'EOF'
#!/usr/bin/env bash
# Usage: vistarevive-aero on|off|status   (run as your normal user, inside the desktop)
# on  = compositing, glass window frames, translucent taskbar/menu/sidebar
# off = "Basic": no compositor, opaque frames (faster on weak GPUs)
set -e
FLAG="$HOME/.config/vistarevive/aero-off"
setp() { xfconf-query -c "$1" -p "$2" -n -t "$3" -s "$4" 2>/dev/null || xfconf-query -c "$1" -p "$2" -s "$4"; }
restart_sidebar() {
  if pgrep -u "$USER" -x conky >/dev/null; then
    pkill -u "$USER" -x conky; sleep 1
    conky -q -d -c /usr/share/vistarevive/conky/sidebar.lua >/dev/null 2>&1 || true
  fi
}
mkdir -p "$(dirname "$FLAG")"
case "${1:-status}" in
  on)
    rm -f "$FLAG"
    setp xfwm4 /general/use_compositing bool true
    setp xfwm4 /general/vblank_mode string glx
    setp xfwm4 /general/cycle_preview bool true
    setp xfwm4 /general/show_dock_shadow bool false
    [[ -d /usr/share/themes/VistaRevive/xfwm4 ]] && setp xfwm4 /general/theme string VistaRevive
    restart_sidebar; echo "Aero: ON" ;;
  off)
    touch "$FLAG"
    setp xfwm4 /general/use_compositing bool false
    [[ -d /usr/share/themes/VistaRevive-Basic/xfwm4 ]] && setp xfwm4 /general/theme string VistaRevive-Basic
    restart_sidebar; echo "Aero: OFF (Basic)" ;;
  status)
    [[ -f "$FLAG" ]] && echo "Aero: OFF (Basic)" || echo "Aero: ON" ;;
  *) echo "Usage: vistarevive-aero on|off|status"; exit 1 ;;
esac
EOF
chmod 755 /usr/local/bin/vistarevive-aero

# ---------------------------------------------------------------------------
# 4. Per-user setup v2 (replaces the Phase 4 version; re-runs automatically
#    for users who already ran v1). Contains ALL per-user settings so far.
# ---------------------------------------------------------------------------
log "Updating per-user setup (version 2)"
cat > /usr/local/bin/vistarevive-firstlogin <<EOF
#!/usr/bin/env bash
# VistaRevive per-user setup. Runs at login when its version is newer than
# the stamp. Force a re-run with:  vistarevive-firstlogin --force
VERSION=2
STAMP="\$HOME/.config/vistarevive/firstlogin.done"
done_ver=0
[[ -f "\$STAMP" ]] && done_ver=\$(cat "\$STAMP" 2>/dev/null || echo 1)
[[ -z "\$done_ver" ]] && done_ver=1
[[ "\${1:-}" != "--force" && "\$done_ver" -ge "\$VERSION" ]] && exit 0
[[ "\${1:-}" != "--force" ]] && sleep 3   # let xfconfd and the window manager start

setp() { xfconf-query -c "\$1" -p "\$2" -n -t "\$3" -s "\$4" 2>/dev/null || xfconf-query -c "\$1" -p "\$2" -s "\$4"; }
key()  { setp xfce4-keyboard-shortcuts "\$1" string "\$2"; }

# --- Phase 4: Vista-style shortcuts ---
key '/commands/custom/Super_L'                 'xfce4-popup-whiskermenu'
key '/commands/custom/<Super>e'                'thunar'
key '/commands/custom/<Super>r'                'xfce4-appfinder --collapsed'
key '/commands/custom/<Super>l'                'xflock4'
key '/commands/custom/<Primary><Shift>Escape'  'xfce4-taskmanager'
key '/commands/custom/Print'                   'xfce4-screenshooter -f'
key '/xfwm4/custom/<Super>d'                   'show_desktop_key'
key '/xfwm4/custom/<Super>Up'                  'maximize_window_key'
key '/xfwm4/custom/<Super>Down'                'hide_window_key'
setp xfwm4 /general/workspace_count int 1

# --- Phase 5: look and sound ---
FONT="DejaVu Sans 9"
fc-list | grep -qi "Open Sans" && FONT="Open Sans 9"
ICONS="Adwaita"
[[ -d /usr/share/icons/oxygen ]] && ICONS="oxygen"

setp xsettings /Net/ThemeName              string VistaRevive
setp xsettings /Net/IconThemeName          string "\$ICONS"
setp xsettings /Gtk/CursorThemeName        string DMZ-White
setp xsettings /Gtk/CursorThemeSize        int    24
setp xsettings /Gtk/FontName               string "\$FONT"
setp xsettings /Xft/Antialias              int    1
setp xsettings /Xft/HintStyle              string hintslight
setp xsettings /Xft/RGBA                   string rgb
setp xsettings /Net/SoundThemeName         string VistaRevive
setp xsettings /Net/EnableEventSounds      bool   true
setp xsettings /Net/EnableInputFeedbackSounds bool false
setp xfwm4     /general/title_font         string "\$FONT"
setp xfwm4     /general/frame_opacity      int    100

# Wallpaper sized to the screen (1680x1050 panel option, else 1280x800)
WP=/usr/share/backgrounds/vistarevive/vistarevive-1280x800.png
width=\$(xrandr 2>/dev/null | awk '/\*/ {split(\$1,a,"x"); print a[1]; exit}')
[[ "\${width:-0}" -ge 1600 ]] && WP=/usr/share/backgrounds/vistarevive/vistarevive-1680x1050.png
for mon in \$(xrandr --listmonitors 2>/dev/null | awk 'NR>1 {print \$NF}'); do
  base="/backdrop/screen0/monitor\$mon/workspace0"
  setp xfce4-desktop "\$base/last-image"  string "\$WP"
  setp xfce4-desktop "\$base/image-style" int    5
done

# Aero on when the GPU was recognised on THIS machine, otherwise Basic
GPU=unknown
[[ -f /etc/vistarevive/hardware.conf ]] && . /etc/vistarevive/hardware.conf
if [[ "\$GPU" == "unknown" ]]; then
  /usr/local/bin/vistarevive-aero off >/dev/null
else
  /usr/local/bin/vistarevive-aero on >/dev/null
fi

mkdir -p "\$(dirname "\$STAMP")" && echo "\$VERSION" > "\$STAMP"
EOF
chmod 755 /usr/local/bin/vistarevive-firstlogin

cat <<'EOF'

Phase 5 installed. Log out and back in (or run: vistarevive-firstlogin --force).

TEST LIST:
 1. Start button is the blue "V" orb? Taskbar dark and glossy?
 2. Window frames: blue glass with Aero on; light blue opaque after
    "vistarevive-aero off". Buttons light up on hover?
 3. Wallpaper fills the screen without stretching?
 4. Icons (Oxygen) and cursor (white) changed? Text readable?
 5. Login chime plays? Plugging in a USB stick makes a sound?
 6. Any app that looks broken or unreadable: tell me which one.
 7. Send me:  free -m   (theme cost should be a few MB at most)
EOF
