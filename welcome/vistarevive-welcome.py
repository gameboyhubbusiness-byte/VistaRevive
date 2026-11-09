#!/usr/bin/env python3
"""
VistaRevive Welcome Center - original, Vista-inspired "get started" window.

Shows a summary of the computer and big task tiles for the things people
need first: Wi-Fi, updates, software, printers, display, sound, appearance.

Usage:
  vistarevive-welcome              open the window
  vistarevive-welcome --autostart  open only if "Show at startup" is ticked
  vistarevive-welcome --info       print the system summary and exit (no GUI)

Needs: python3-gi, gir1.2-gtk-3.0 (GTK3 so it follows the VistaRevive theme)
"""
import configparser
import os
import shutil
import subprocess
import sys
import time

APP_NAME = "Welcome Center"
CONF_DIR = os.path.expanduser("~/.config/vistarevive")
CONF_FILE = os.path.join(CONF_DIR, "welcome.conf")
WEATHER_CONF = os.path.join(CONF_DIR, "weather.conf")
WEATHER_CACHE = os.path.expanduser("~/.cache/vistarevive/weather.txt")
ORB = "/usr/share/vistarevive/orb-256.png"


# ---------------------------------------------------------------------------
# System information (no GUI needed; testable with --info)
# ---------------------------------------------------------------------------
def read(path, default=""):
    try:
        with open(path) as fh:
            return fh.read()
    except OSError:
        return default


def os_name():
    for line in read("/etc/os-release").splitlines():
        if line.startswith("PRETTY_NAME="):
            return "VistaRevive on " + line.split("=", 1)[1].strip('"')
    return "VistaRevive"


def cpu_name():
    for line in read("/proc/cpuinfo").splitlines():
        if line.startswith("model name"):
            name = line.split(":", 1)[1].strip()
            for junk in ("(R)", "(TM)", "CPU ", "  "):
                name = name.replace(junk, " " if junk == "  " else "")
            return " ".join(name.split())
    return "Unknown processor"


def cpu_count():
    return os.cpu_count() or 1


def ram_text():
    info = {}
    for line in read("/proc/meminfo").splitlines():
        k, _, v = line.partition(":")
        info[k] = int(v.split()[0]) if v.split() else 0
    total = info.get("MemTotal", 0) / 1024
    avail = info.get("MemAvailable", 0) / 1024
    # Report installed size the way people know it (1 GB, 2 GB, 4 GB)
    # (shared graphics memory makes 1 GB show up as ~870-990 MB)
    nice = f"{round(total / 1024 * 2) / 2:g} GB" if total > 700 else f"{total:.0f} MB"
    return f"{nice} ({avail:.0f} MB free now)", total


def gpu_name():
    conf = read("/etc/vistarevive/hardware.conf")
    known = {"intel-x3100": "Intel GMA X3100", "ati-x1350": "ATI Mobility Radeon X1350"}
    for line in conf.splitlines():
        if line.startswith("GPU="):
            gpu = line.split("=", 1)[1].strip()
            if gpu in known:
                return known[gpu]
    try:
        out = subprocess.run(["lspci"], capture_output=True, text=True, timeout=3).stdout
        for line in out.splitlines():
            if "VGA" in line or "Display" in line:
                return line.split(":", 2)[-1].strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return "Unknown graphics"


def disk_text():
    try:
        du = shutil.disk_usage("/")
        return f"{du.free / 1e9:.0f} GB free of {du.total / 1e9:.0f} GB"
    except OSError:
        return "Unknown"


def disk_type():
    # rotational=1 -> hard disk, 0 -> SSD
    try:
        out = subprocess.run(["findmnt", "-no", "SOURCE", "/"], capture_output=True,
                             text=True, timeout=3).stdout.strip()
        dev = os.path.basename(out).rstrip("0123456789")
        rot = read(f"/sys/block/{dev}/queue/rotational").strip()
        return {"1": "hard disk", "0": "SSD"}.get(rot, "")
    except (OSError, subprocess.SubprocessError):
        return ""


def updates_text():
    auto = 'Unattended-Upgrade "1"' in read("/etc/apt/apt.conf.d/20auto-upgrades")
    stamp = "/var/lib/apt/periodic/upgrade-stamp"
    if os.path.exists(stamp):
        days = (time.time() - os.path.getmtime(stamp)) / 86400
        last = "today" if days < 1 else f"{days:.0f} day{'s' if days >= 2 else ''} ago"
    else:
        last = "not yet"
    return f"Automatic security updates {'on' if auto else 'off'} · last run {last}"


def aero_on():
    return not os.path.exists(os.path.join(CONF_DIR, "aero-off"))


def summary():
    ram, _ = ram_text()
    dtype = disk_type()
    return [
        ("System", os_name()),
        ("Processor", f"{cpu_name()} ({cpu_count()} cores)"),
        ("Memory", ram),
        ("Graphics", gpu_name()),
        ("Disk", disk_text() + (f" ({dtype})" if dtype else "")),
        ("Updates", updates_text()),
    ]


def show_at_startup():
    cp = configparser.ConfigParser()
    cp.read(CONF_FILE)
    return cp.getboolean("welcome", "show_at_startup", fallback=True)


def set_show_at_startup(value):
    os.makedirs(CONF_DIR, exist_ok=True)
    cp = configparser.ConfigParser()
    cp.read(CONF_FILE)
    if not cp.has_section("welcome"):
        cp.add_section("welcome")
    cp.set("welcome", "show_at_startup", "true" if value else "false")
    with open(CONF_FILE, "w") as fh:
        cp.write(fh)


def weather_location():
    for line in read(WEATHER_CONF).splitlines():
        if line.startswith("LOCATION="):
            return line.split("=", 1)[1].strip().strip('"')
    return ""


def set_weather_location(city):
    os.makedirs(CONF_DIR, exist_ok=True)
    safe = city.replace('"', "").replace("$", "").replace("`", "").replace("\\", "").strip()
    with open(WEATHER_CONF, "w") as fh:
        fh.write(f'LOCATION="{safe}"\n')
    try:
        os.remove(WEATHER_CACHE)  # sidebar fetches the new city on its next refresh
    except OSError:
        pass


def have(cmd):
    return shutil.which(cmd) is not None


# Task tiles: (title, subtitle, icon names to try, command list or callable name)
TERM_UPDATE = ["xfce4-terminal", "--title=Check for updates", "--hold", "-x", "sh", "-c",
               "echo 'Checking for updates...'; sudo apt update && sudo apt full-upgrade; "
               "echo; echo 'Done. You can close this window.'"]
TASKS = [
    ("Connect to a network", "Wi-Fi and wired connections",
     ["network-wireless", "preferences-system-network"], ["nm-connection-editor"]),
    ("Check for updates", "Install the latest fixes now",
     ["system-software-update", "software-update-available"], TERM_UPDATE),
    ("Add or remove programs", "Browse and install software",
     ["system-software-install", "synaptic"], ["synaptic-pkexec"]),
    ("Printers", "Add and manage printers",
     ["printer", "preferences-devices-printer"], ["system-config-printer"]),
    ("Display", "Resolution and external screens",
     ["preferences-desktop-display", "video-display"], ["xfce4-display-settings"]),
    ("Sound", "Volume, speakers and microphone",
     ["audio-volume-high", "multimedia-volume-control"], ["pavucontrol"]),
    ("Power and battery", "Sleep, lid and brightness",
     ["xfce4-power-manager-settings", "battery", "preferences-system-power"],
     ["xfce4-power-manager-settings"]),
    ("Personalize", "Themes, icons and fonts",
     ["preferences-desktop-theme", "preferences-desktop-appearance"], ["xfce4-appearance-settings"]),
    ("Weather gadget", "Choose your city for the sidebar",
     ["weather-few-clouds", "weather-clear"], "weather"),
    ("All settings", "Everything else",
     ["preferences-system", "xfce-settings-manager"], ["xfce4-settings-manager"]),
]


# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------
CSS = b"""
#vr-banner {
  background-image: linear-gradient(to bottom, #1c4f78 0%, #0f3150 55%, #0a2238 100%);
  border-bottom: 1px solid #071624;
  padding: 18px 22px;
}
#vr-banner label { color: #ffffff; text-shadow: 0 1px 2px rgba(0,0,0,0.8); }
#vr-title { font-size: 20px; font-weight: 300; }
#vr-info-key { color: #9cc8ec; }
#vr-section { font-weight: bold; color: #1d4f7a; margin-top: 6px; }
.vr-tile {
  background-image: none; background-color: transparent;
  border: 1px solid transparent; border-radius: 4px; box-shadow: none; padding: 6px;
}
.vr-tile:hover {
  background-image: linear-gradient(to bottom, #f3f9fe, #dcecfa);
  border-color: #a8d3ee;
}
.vr-tile-title { font-weight: bold; color: #1a3a58; }
.vr-tile-sub { color: #5b6876; font-size: 90%; }
#vr-footer { border-top: 1px solid #d0d7df; padding: 8px 16px; background-color: #f0f3f6; }
"""


def run_gui(autostart=False):
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gdk, GdkPixbuf, Gtk

    if autostart and not show_at_startup():
        return 0

    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    theme = Gtk.IconTheme.get_default()

    def icon(names, size=40):
        for n in names:
            if theme.has_icon(n):
                return Gtk.Image.new_from_icon_name(n, Gtk.IconSize.DIALOG) if size >= 40 \
                    else Gtk.Image.new_from_icon_name(n, Gtk.IconSize.LARGE_TOOLBAR)
        return Gtk.Image.new_from_icon_name("applications-system", Gtk.IconSize.DIALOG)

    win = Gtk.Window(title=APP_NAME)
    win.set_default_size(720, 560)
    win.set_position(Gtk.WindowPosition.CENTER)
    if os.path.exists("/usr/share/icons/hicolor/48x48/apps/vistarevive-start.png"):
        win.set_icon_name("vistarevive-start")
    win.connect("destroy", Gtk.main_quit)

    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    win.add(root)

    # --- banner: orb + title + computer summary ---------------------------
    banner = Gtk.Box(spacing=18)
    banner.set_name("vr-banner")
    if os.path.exists(ORB):
        pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(ORB, 96, 96, True)
        banner.pack_start(Gtk.Image.new_from_pixbuf(pb), False, False, 0)
    right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    title = Gtk.Label(label="Welcome to VistaRevive", xalign=0)
    title.set_name("vr-title")
    right.pack_start(title, False, False, 0)
    grid = Gtk.Grid(column_spacing=14, row_spacing=2)
    for row, (k, v) in enumerate(summary()):
        kl = Gtk.Label(label=k, xalign=0)
        kl.set_name("vr-info-key")
        vl = Gtk.Label(label=v, xalign=0)
        vl.set_ellipsize(3)  # Pango.EllipsizeMode.END
        vl.set_selectable(True)
        grid.attach(kl, 0, row, 1, 1)
        grid.attach(vl, 1, row, 1, 1)
    right.pack_start(grid, False, False, 0)
    banner.pack_start(right, True, True, 0)
    root.pack_start(banner, False, False, 0)

    # --- task tiles -------------------------------------------------------
    body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    body.set_border_width(14)
    sect = Gtk.Label(label="Get started with your computer", xalign=0)
    sect.set_name("vr-section")
    body.pack_start(sect, False, False, 0)

    flow = Gtk.FlowBox()
    flow.set_selection_mode(Gtk.SelectionMode.NONE)
    flow.set_max_children_per_line(2)
    flow.set_min_children_per_line(2)
    flow.set_column_spacing(8)
    flow.set_row_spacing(4)
    flow.set_homogeneous(True)

    def launch(_btn, action):
        if action == "weather":
            weather_dialog()
            return
        if not have(action[0]):
            msg = Gtk.MessageDialog(transient_for=win, modal=True,
                                    message_type=Gtk.MessageType.INFO,
                                    buttons=Gtk.ButtonsType.OK,
                                    text=f"'{action[0]}' is not installed.")
            msg.run()
            msg.destroy()
            return
        subprocess.Popen(action, start_new_session=True)

    def weather_dialog():
        dlg = Gtk.Dialog(title="Weather gadget", transient_for=win, modal=True)
        dlg.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Save", Gtk.ResponseType.OK)
        box = dlg.get_content_area()
        box.set_spacing(8)
        box.set_border_width(12)
        box.add(Gtk.Label(label="City for the sidebar weather (leave empty to detect "
                                "automatically from your internet address):", xalign=0,
                          wrap=True, max_width_chars=48))
        entry = Gtk.Entry(text=weather_location(), placeholder_text="e.g. Paris")
        entry.set_activates_default(True)
        box.add(entry)
        dlg.set_default_response(Gtk.ResponseType.OK)
        dlg.show_all()
        if dlg.run() == Gtk.ResponseType.OK:
            set_weather_location(entry.get_text())
        dlg.destroy()

    for t, sub, icons, action in TASKS:
        btn = Gtk.Button()
        btn.get_style_context().add_class("vr-tile")
        btn.set_relief(Gtk.ReliefStyle.NONE)
        hb = Gtk.Box(spacing=12)
        hb.pack_start(icon(icons), False, False, 0)
        tb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        tl = Gtk.Label(label=t, xalign=0)
        tl.get_style_context().add_class("vr-tile-title")
        sl = Gtk.Label(label=sub, xalign=0)
        sl.get_style_context().add_class("vr-tile-sub")
        tb.pack_start(tl, False, False, 0)
        tb.pack_start(sl, False, False, 0)
        hb.pack_start(tb, True, True, 0)
        btn.add(hb)
        btn.connect("clicked", launch, action)
        flow.add(btn)

    scroll = Gtk.ScrolledWindow()
    scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    scroll.add(flow)
    body.pack_start(scroll, True, True, 0)
    root.pack_start(body, True, True, 0)

    # --- footer: Aero switch + show at startup -----------------------------
    footer = Gtk.Box(spacing=10)
    footer.set_name("vr-footer")
    footer.pack_start(Gtk.Label(label="Aero glass effects"), False, False, 0)
    sw = Gtk.Switch(active=aero_on(), valign=Gtk.Align.CENTER)

    def on_aero(switch, _param):
        if have("vistarevive-aero"):
            subprocess.Popen(["vistarevive-aero", "on" if switch.get_active() else "off"])
    sw.connect("notify::active", on_aero)
    footer.pack_start(sw, False, False, 0)
    chk = Gtk.CheckButton(label="Show this window at startup", active=show_at_startup())
    chk.connect("toggled", lambda c: set_show_at_startup(c.get_active()))
    footer.pack_end(chk, False, False, 0)
    root.pack_start(footer, False, False, 0)

    win.show_all()
    Gtk.main()
    return 0


def main(argv):
    if "--info" in argv:
        for k, v in summary():
            print(f"{k:10} {v}")
        print(f"{'Startup':10} {'show' if show_at_startup() else 'hidden'}")
        print(f"{'Weather':10} {weather_location() or '(auto)'}")
        return 0
    return run_gui(autostart="--autostart" in argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
