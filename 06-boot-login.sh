#!/usr/bin/env bash
# VistaRevive - Phase 6: login screen, boot splash, sidebar gadgets
# Target: Debian 13 "trixie". Run after 05-theme.sh.
# Usage: sudo bash 06-boot-login.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
log()  { echo -e "\e[1;34m[VistaRevive]\e[0m $*"; }
warn() { echo -e "\e[1;33m[warning]\e[0m $*"; }

[[ -d /usr/share/vistarevive/plymouth/vistarevive ]] || { echo "Run 05-theme.sh first."; exit 1; }

FONT="DejaVu Sans"
fc-list | grep -qi "Open Sans" && FONT="Open Sans"
ICONS="Adwaita"
[[ -d /usr/share/icons/oxygen ]] && ICONS="oxygen"

# ---------------------------------------------------------------------------
# 1. Login screen (LightDM GTK greeter)
# ---------------------------------------------------------------------------
log "Theming the login screen"
[[ -f /etc/lightdm/lightdm-gtk-greeter.conf ]] && \
  cp -n /etc/lightdm/lightdm-gtk-greeter.conf /etc/lightdm/lightdm-gtk-greeter.conf.bak
cat > /etc/lightdm/lightdm-gtk-greeter.conf <<EOF
# VistaRevive login screen
[greeter]
background=/usr/share/backgrounds/vistarevive/vistarevive-login.png
user-background=false
theme-name=VistaRevive
icon-theme-name=$ICONS
cursor-theme-name=DMZ-White
cursor-theme-size=24
font-name=$FONT 10
xft-antialias=true
xft-hintstyle=hintslight
xft-rgba=rgb
default-user-image=/usr/share/vistarevive/user-tile.png
indicators=~host;~spacer;~clock;~spacer;~a11y;~power
clock-format=%A, %d %B   %H:%M
position=50%,center 50%,center
screensaver-timeout=60
EOF

# Show the user list (like Vista's user tiles) instead of an empty name box
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-vistarevive.conf <<'EOF'
[Seat:*]
greeter-hide-users=false
EOF

# ---------------------------------------------------------------------------
# 2. Boot splash (Plymouth)
# ---------------------------------------------------------------------------
log "Installing the boot splash (rebuilds the initramfs, takes a minute)"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends plymouth
rm -rf /usr/share/plymouth/themes/vistarevive
cp -r /usr/share/vistarevive/plymouth/vistarevive /usr/share/plymouth/themes/
mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf <<'EOF'
[Daemon]
Theme=vistarevive
ShowDelay=0
DeviceTimeout=8
EOF
plymouth-set-default-theme -R vistarevive

# "quiet splash" on the kernel command line, fewer messages on screen
if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub 2>/dev/null; then
  cmd=$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/\1/p' /etc/default/grub)
  for opt in quiet splash loglevel=3 vt.global_cursor_default=0; do
    [[ " $cmd " == *" $opt "* ]] || cmd="$cmd $opt"
  done
  cmd="$(echo "$cmd" | xargs)"
  sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$cmd\"|" /etc/default/grub
  update-grub >/dev/null 2>&1
  log "Kernel options: $cmd"
fi

# ---------------------------------------------------------------------------
# 3. Sidebar gadgets (Conky): clock, CPU meter, memory, weather, battery
# ---------------------------------------------------------------------------
log "Installing sidebar gadgets"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends conky-std curl

mkdir -p /usr/share/vistarevive/conky
cat > /usr/share/vistarevive/conky/sidebar.lua <<EOF
-- VistaRevive sidebar (Conky). Translucent with Aero, solid in Basic mode.
local home = os.getenv('HOME') or ''
local f = io.open(home .. '/.config/vistarevive/aero-off', 'r')
local aero = (f == nil)
if f then f:close() end

conky.config = {
  own_window = true,
  own_window_type = 'normal',
  own_window_class = 'Conky',
  own_window_title = 'VistaRevive Sidebar',
  own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
  own_window_argb_visual = aero,
  own_window_argb_value = aero and 140 or 255,
  own_window_transparent = false,
  own_window_colour = '0e1c2a',
  double_buffer = true,
  alignment = 'top_right',
  gap_x = 12, gap_y = 12,
  minimum_width = 190, maximum_width = 190,
  border_inner_margin = 10,
  update_interval = 2,
  cpu_avg_samples = 2,
  no_buffers = true,
  use_xft = true,
  font = '$FONT:size=9',
  override_utf8_locale = true,
  default_color = 'e8f1f8',
  color1 = '8cc4f2',
  color2 = '5fd3c8',
  draw_shades = true, default_shade_color = '000000',
  draw_outline = false, draw_borders = false, draw_graph_borders = false,
  text_buffer_size = 1024,
}

conky.text = [[
\${alignc}\${font $FONT:light:size=32}\${time %H:%M}\${font}
\${alignc}\${time %A, %d %B}
\${voffset 8}\${color1}\${font $FONT:bold:size=9}CPU\${font}\${color}\${alignr}\${cpu cpu0}%
\${color2}\${cpugraph cpu0 30,170 1f6fa8 5fd3c8}\${color}
Core 1\${alignr}\${cpubar cpu1 6,120}
Core 2\${alignr}\${cpubar cpu2 6,120}
\${voffset 8}\${color1}\${font $FONT:bold:size=9}Memory\${font}\${color}\${alignr}\${mem} / \${memmax}
\${color2}\${membar 6,170}\${color}
Swap\${alignr}\${swap} / \${swapmax}
\${voffset 8}\${color1}\${font $FONT:bold:size=9}Weather\${font}\${color}
\${execpi 600 /usr/local/bin/vistarevive-weather}
\${if_existing /sys/class/power_supply/BAT0}\${voffset 8}\${color1}\${font $FONT:bold:size=9}Battery\${font}\${color}\${alignr}\${battery_percent BAT0}%
\${color2}\${battery_bar 6,170 BAT0}\${color}\${endif}
]]
EOF

cat > /usr/local/bin/vistarevive-weather <<'EOF'
#!/usr/bin/env bash
# Weather for the VistaRevive sidebar, from wttr.in, cached for 30 minutes.
# Set your city in ~/.config/vistarevive/weather.conf, e.g.:  LOCATION="Zagreb"
# With no LOCATION, wttr.in guesses the location from your IP address.
CONF="$HOME/.config/vistarevive/weather.conf"
CACHE="$HOME/.cache/vistarevive/weather.txt"
LOCATION=""
[[ -f "$CONF" ]] && . "$CONF"
mkdir -p "$(dirname "$CACHE")"

age=99999
[[ -s "$CACHE" ]] && age=$(( $(date +%s) - $(stat -c %Y "$CACHE") ))
if (( age > 1800 )); then
  loc="${LOCATION// /+}"
  if out=$(curl -fsS --max-time 8 "https://wttr.in/${loc}?m&format=%l%7C%t+%C%7C%h%7C%w" 2>/dev/null) \
     && [[ "$out" == *"|"* ]]; then
    IFS='|' read -r l t h w <<<"$out"
    printf '%s\n%s\nHumidity %s   Wind %s\n' "$l" "$t" "$h" "$w" > "$CACHE"
  fi
fi
if [[ -s "$CACHE" ]]; then cat "$CACHE"; else echo "Weather unavailable"; fi
EOF
chmod 755 /usr/local/bin/vistarevive-weather

cat > /etc/xdg/autostart/vistarevive-sidebar.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=VistaRevive Sidebar
Comment=Clock, CPU, memory, weather and battery gadgets
Exec=sh -c "sleep 6; exec conky -q -c /usr/share/vistarevive/conky/sidebar.lua"
OnlyShowIn=XFCE;
EOF

cat <<'EOF'

Phase 6 installed. Reboot now: sudo reboot

TEST LIST:
 1. Boot: dark blue screen with the glowing orb and a moving bar, no text
    scrolling? (If the screen stays black or flickers, tell me which GPU.)
 2. Login screen: blurred wallpaper, your user in a glass box, clock on top?
 3. Desktop: sidebar top-right with clock, CPU, memory, weather, battery?
    - Weather wrong city? Create ~/.config/vistarevive/weather.conf with
      LOCATION="YourCity"   (then:  rm ~/.cache/vistarevive/weather.txt)
    - Don't want the sidebar? Settings > Session and Startup > untick it.
 4. "vistarevive-aero off" turns the sidebar solid; "on" makes it see-through?
 5. Send me:  systemd-analyze   and   free -m
EOF
