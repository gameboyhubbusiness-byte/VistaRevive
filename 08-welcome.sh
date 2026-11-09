#!/usr/bin/env bash
# VistaRevive - Phase 8: Welcome Center
# Target: Debian 13 "trixie". Run after 07-apps.sh.
# Usage: sudo bash 08-welcome.sh      (needs welcome/vistarevive-welcome.py next to it)
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
log()  { echo -e "\e[1;34m[VistaRevive]\e[0m $*"; }
warn() { echo -e "\e[1;33m[warning]\e[0m $*"; }
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/welcome/vistarevive-welcome.py"
[[ -f "$SRC" ]] || { echo "Missing $SRC"; exit 1; }
available() { for p in "$@"; do
  if apt-cache show "$p" >/dev/null 2>&1; then echo "$p"; else warn "Package $p not found, skipping" >&2; fi
done; }

# ---------------------------------------------------------------------------
# 1. Packages: GTK3 for Python, a password prompt for admin tasks, the
#    network editor the "Connect to a network" tile opens.
# ---------------------------------------------------------------------------
# A polkit agent shows the password box when Synaptic or the printer tool
# needs admin rights. Without one, those apps fail silently. lxpolkit is the
# smallest; mate-polkit is the fallback.
AGENT_PKG=""
for p in lxpolkit mate-polkit; do
  if apt-cache show "$p" >/dev/null 2>&1; then AGENT_PKG=$p; break; fi
done
mapfile -t PKGS < <(available python3-gi gir1.2-gtk-3.0 nm-connection-editor $AGENT_PKG)
log "Installing: ${PKGS[*]}"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PKGS[@]}"

# Start the password agent in XFCE sessions
AGENT_BIN=""
for b in /usr/bin/lxpolkit /usr/libexec/polkit-mate-authentication-agent-1 \
         /usr/lib/mate-polkit/polkit-mate-authentication-agent-1; do
  [[ -x "$b" ]] && { AGENT_BIN=$b; break; }
done
if [[ -n "$AGENT_BIN" ]]; then
  cat > /etc/xdg/autostart/vistarevive-polkit.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Authentication agent
Exec=$AGENT_BIN
OnlyShowIn=XFCE;
NoDisplay=true
EOF
  log "Password agent: $AGENT_BIN"
else
  warn "No polkit agent found; Synaptic may not open from the Welcome Center."
fi

# ---------------------------------------------------------------------------
# 2. The app, its menu entry and autostart
# ---------------------------------------------------------------------------
install -m 755 "$SRC" /usr/local/bin/vistarevive-welcome

cat > /usr/share/applications/vistarevive-welcome.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Welcome Center
Comment=Get started: Wi-Fi, updates, programs, printers and more
Exec=vistarevive-welcome
Icon=vistarevive-start
Categories=Settings;System;
EOF

cat > /etc/xdg/autostart/vistarevive-welcome.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Welcome Center
Exec=sh -c "sleep 8; exec vistarevive-welcome --autostart"
OnlyShowIn=XFCE;
NoDisplay=true
EOF

# Pin it in the start menu's favourites (after Firefox)
for rc in /etc/xdg/xfce4/panel/whiskermenu-1.rc /home/*/.config/xfce4/panel/whiskermenu-1.rc; do
  if [[ -f "$rc" ]] && ! grep -q 'vistarevive-welcome.desktop' "$rc"; then
    sed -i 's|^favorites=|favorites=vistarevive-welcome.desktop,|' "$rc"
  fi
done

log "System summary as the Welcome Center will show it:"
sudo -u "${SUDO_USER:-root}" /usr/local/bin/vistarevive-welcome --info || true

cat <<'EOF'

Phase 8 installed. Log out and back in: the Welcome Center opens by itself.
(Start menu -> Welcome Center opens it any time.)

TEST LIST:
 1. Top banner: orb, "Welcome to VistaRevive", correct CPU / RAM / GPU / disk?
 2. Click every tile. Each should open its tool:
    network editor, update terminal (asks your password), Synaptic
    (password box), printers, display, sound, power, appearance,
    weather city box, all settings.
 3. Aero switch at the bottom toggles glass on/off?
 4. Untick "Show this window at startup": stays closed at next login?
 5. If a tile does nothing, run  vistarevive-welcome  from a terminal and
    send me what it prints.
EOF
