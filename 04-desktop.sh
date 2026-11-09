#!/usr/bin/env bash
# VistaRevive - Phase 4: desktop, taskbar, start menu, shortcuts
# Target: Debian 13 "trixie". Run after 03-performance.sh and a reboot.
# Usage: sudo bash 04-desktop.sh
#
# Design: everything is written as SYSTEM-WIDE defaults (/etc/xdg, /usr/local),
# so any new user - and the future ISO - gets the same desktop. Per-user tweaks
# that XFCE only accepts at runtime are applied once at first login.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
log()  { echo -e "\e[1;34m[VistaRevive]\e[0m $*"; }
warn() { echo -e "\e[1;33m[warning]\e[0m $*"; }

GPU="unknown"
[[ -f /etc/vistarevive/hardware.conf ]] && . /etc/vistarevive/hardware.conf
log "GPU from Phase 2: $GPU"

# ---------------------------------------------------------------------------
# 1. Packages (no recommends: every package is here on purpose)
# ---------------------------------------------------------------------------
PKGS=(
  # X server
  xserver-xorg-core xserver-xorg-input-libinput x11-xserver-utils xinit
  # XFCE core
  xfce4-session xfwm4 xfce4-panel xfdesktop4 xfce4-settings xfconf
  xfce4-whiskermenu-plugin   # searchable start menu
  xfce4-appfinder            # Win+R "Run" dialog
  xfce4-notifyd              # notification bubbles
  xfce4-power-manager xfce4-power-manager-plugins  # battery, brightness keys, lid
  xfce4-pulseaudio-plugin pavucontrol              # volume icon + mixer
  xfce4-terminal xfce4-taskmanager xfce4-screenshooter
  # Files, USB drives, trash
  thunar thunar-volman gvfs udisks2 tumbler
  # Audio (PipeWire: Debian 13 default, also handles Bluetooth audio)
  pipewire pipewire-pulse wireplumber
  # Network tray icon
  network-manager-applet
  # Login screen
  lightdm lightdm-gtk-greeter
  # Basic look until Phase 5 replaces it
  fonts-dejavu-core adwaita-icon-theme librsvg2-common
  # Session plumbing
  dbus-x11 at-spi2-core
)
if lsusb | grep -qi bluetooth; then PKGS+=(blueman); fi

log "Installing desktop packages (this takes a while on an HDD)"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PKGS[@]}"

XDG=/etc/xdg/xfce4
mkdir -p "$XDG/xfconf/xfce-perchannel-xml" "$XDG/panel"

# ---------------------------------------------------------------------------
# 2. Taskbar: one 40 px panel at the bottom, Vista order
#    [Start] [open windows .......] [tray] [volume] [battery] [clock] [show desktop]
# ---------------------------------------------------------------------------
log "Writing default taskbar layout"
cat > "$XDG/xfconf/xfce-perchannel-xml/xfce4-panel.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!-- VistaRevive default taskbar -->
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="40"/>
      <property name="icon-size" type="uint" value="24"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu"/>
    <property name="plugin-2" type="string" value="tasklist">
      <property name="grouping" type="uint" value="0"/>
      <property name="show-labels" type="bool" value="true"/>
      <property name="flat-buttons" type="bool" value="false"/>
      <property name="include-all-workspaces" type="bool" value="false"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="systray">
      <property name="square-icons" type="bool" value="true"/>
    </property>
    <property name="plugin-5" type="string" value="pulseaudio">
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
    </property>
    <property name="plugin-6" type="string" value="power-manager-plugin"/>
    <property name="plugin-7" type="string" value="clock">
      <property name="mode" type="uint" value="2"/>
      <property name="digital-layout" type="uint" value="3"/>
      <property name="digital-time-format" type="string" value="%H:%M"/>
      <property name="tooltip-format" type="string" value="%A, %d %B %Y"/>
    </property>
    <property name="plugin-8" type="string" value="showdesktop"/>
  </property>
</channel>
EOF

# Start menu: search box at the bottom and power buttons, like Vista.
# The button icon is a placeholder; Phase 5 swaps in our own round orb.
cat > "$XDG/panel/whiskermenu-1.rc" <<'EOF'
favorites=xfce4-web-browser.desktop,thunar.desktop,xfce4-terminal.desktop,xfce-settings-manager.desktop
button-icon=start-here
show-button-title=false
show-button-icon=true
launcher-show-name=true
launcher-show-description=true
position-search-alternate=true
position-commands-alternate=true
position-categories-alternate=false
menu-width=420
menu-height=520
menu-opacity=100
command-settings=xfce4-settings-manager
show-command-settings=true
command-lockscreen=xflock4
show-command-lockscreen=true
command-logoutuser=xfce4-session-logout
show-command-logoutuser=true
command-switchuser=dm-tool switch-to-greeter
show-command-switchuser=false
command-restart=xfce4-session-logout --reboot --fast
show-command-restart=true
command-shutdown=xfce4-session-logout --halt --fast
show-command-shutdown=true
command-suspend=xfce4-session-logout --suspend
show-command-suspend=true
command-menueditor=
show-command-menueditor=false
EOF

# ---------------------------------------------------------------------------
# 3. "Aero" switch: compositing on (translucency, Alt+Tab previews, shadows)
#    or off ("Basic"). Phase 5 will also swap the window theme here.
# ---------------------------------------------------------------------------
log "Installing vistarevive-aero switch"
cat > /usr/local/bin/vistarevive-aero <<'EOF'
#!/usr/bin/env bash
# Usage: vistarevive-aero on|off|status   (run as your normal user, inside the desktop)
set -e
case "${1:-status}" in
  on)
    xfconf-query -c xfwm4 -p /general/use_compositing -s true
    xfconf-query -c xfwm4 -p /general/vblank_mode -n -t string -s glx 2>/dev/null \
      || xfconf-query -c xfwm4 -p /general/vblank_mode -s glx
    xfconf-query -c xfwm4 -p /general/cycle_preview -n -t bool -s true 2>/dev/null \
      || xfconf-query -c xfwm4 -p /general/cycle_preview -s true
    xfconf-query -c xfwm4 -p /general/show_dock_shadow -n -t bool -s false 2>/dev/null \
      || xfconf-query -c xfwm4 -p /general/show_dock_shadow -s false
    echo "Aero: ON"
    ;;
  off)
    xfconf-query -c xfwm4 -p /general/use_compositing -s false
    echo "Aero: OFF (Basic)"
    ;;
  status)
    v=$(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null || echo false)
    [[ "$v" == "true" ]] && echo "Aero: ON" || echo "Aero: OFF (Basic)"
    ;;
  *) echo "Usage: vistarevive-aero on|off|status"; exit 1 ;;
esac
EOF
chmod 755 /usr/local/bin/vistarevive-aero

# ---------------------------------------------------------------------------
# 4. First-login setup (runs once per user): shortcuts + Aero default
# ---------------------------------------------------------------------------
log "Installing first-login setup"
if [[ "$GPU" == "unknown" ]]; then AERO_DEFAULT=off; else AERO_DEFAULT=on; fi

cat > /usr/local/bin/vistarevive-firstlogin <<EOF
#!/usr/bin/env bash
# VistaRevive first-login setup. Delete ~/.config/vistarevive/firstlogin.done to re-run.
STAMP="\$HOME/.config/vistarevive/firstlogin.done"
[[ -f "\$STAMP" ]] && exit 0
sleep 3   # let xfconfd and the window manager start

set_key() {  # set_key CHANNEL PROPERTY VALUE
  xfconf-query -c "\$1" -p "\$2" -n -t string -s "\$3" 2>/dev/null \\
    || xfconf-query -c "\$1" -p "\$2" -s "\$3"
}

# Vista-style shortcuts
set_key xfce4-keyboard-shortcuts '/commands/custom/Super_L'            'xfce4-popup-whiskermenu'
set_key xfce4-keyboard-shortcuts '/commands/custom/<Super>e'           'thunar'
set_key xfce4-keyboard-shortcuts '/commands/custom/<Super>r'           'xfce4-appfinder --collapsed'
set_key xfce4-keyboard-shortcuts '/commands/custom/<Super>l'           'xflock4'
set_key xfce4-keyboard-shortcuts '/commands/custom/<Primary><Shift>Escape' 'xfce4-taskmanager'
set_key xfce4-keyboard-shortcuts '/commands/custom/Print'              'xfce4-screenshooter -f'
set_key xfce4-keyboard-shortcuts '/xfwm4/custom/<Super>d'              'show_desktop_key'
set_key xfce4-keyboard-shortcuts '/xfwm4/custom/<Super>Up'             'maximize_window_key'
set_key xfce4-keyboard-shortcuts '/xfwm4/custom/<Super>Down'           'hide_window_key'
# Alt+Tab is already xfwm4's default.

# One workspace, like Vista
xfconf-query -c xfwm4 -p /general/workspace_count -s 1 2>/dev/null || true

/usr/local/bin/vistarevive-aero $AERO_DEFAULT

mkdir -p "\$(dirname "\$STAMP")" && touch "\$STAMP"
EOF
chmod 755 /usr/local/bin/vistarevive-firstlogin

cat > /etc/xdg/autostart/vistarevive-firstlogin.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=VistaRevive first-login setup
Exec=/usr/local/bin/vistarevive-firstlogin
OnlyShowIn=XFCE;
NoDisplay=true
EOF

# ---------------------------------------------------------------------------
# 5. Trim session autostarts that cost RAM and are not needed here
# ---------------------------------------------------------------------------
for f in /etc/xdg/autostart/{xscreensaver,print-applet,org.gnome.SettingsDaemon.*,tracker-*}.desktop; do
  if [[ -f "$f" ]] && ! grep -q '^Hidden=true' "$f"; then
    log "Disabling autostart: $(basename "$f")"
    echo "Hidden=true" >> "$f"
  fi
done

# ---------------------------------------------------------------------------
# 6. Login screen (themed properly in Phase 6)
# ---------------------------------------------------------------------------
systemctl enable lightdm >/dev/null
systemctl set-default graphical.target >/dev/null

cat <<'EOF'

Phase 4 installed. Reboot now: sudo reboot
You should get a login screen, then the desktop.

TEST LIST (send me the answers):
 1. Taskbar at the bottom: start button, window buttons, tray, volume,
    battery, clock, show-desktop?
 2. Win key alone opens the start menu; typing searches apps?
 3. Win+E opens Thunar, Win+R the Run box, Win+D shows the desktop,
    Ctrl+Shift+Esc opens Task Manager, Alt+Tab shows window previews?
 4. Plug in a USB stick: does it appear in Thunar and open?
 5. Wi-Fi icon in the tray connects to your network?
 6. Volume keys / brightness keys work?
 7. Aero smoothness: drag a window around quickly, open/close menus.
    Smooth = keep it. Laggy or tearing:  vistarevive-aero off
 8. Open a terminal (Win+R -> xfce4-terminal) and paste me the output of:
      vistarevive-aero status
      glxinfo -B | grep -E "renderer|version"
      free -m
      ps -eo rss,comm --sort=-rss | head -n 15
EOF
