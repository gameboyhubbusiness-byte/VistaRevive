#!/usr/bin/env python3
"""
VistaRevive - original artwork generator (Phases 5 and 6)

Everything here is drawn from code: wallpapers, the round start orb, the
glass window frames, the boot splash, the login user tile and the sound
theme. No third-party or Microsoft artwork is used.

Requires: python3, python3-pil, python3-numpy  (Debian package names)
Usage:    python3 make-art.py [OUTPUT_DIR]      (default: ./art-out)
Output layout (installed by 05-theme.sh / 06-boot-login.sh):
  themes/VistaRevive/        GTK3 + GTK2 theme, xfwm4 "Aero" glass frames
  themes/VistaRevive-Basic/  xfwm4 opaque "Basic" frames
  icons/hicolor/*/apps/vistarevive-start.png
  sounds/VistaRevive/        freedesktop sound theme (WAV)
  backgrounds/               wallpapers + login background
  plymouth/vistarevive/      boot splash theme
  vistarevive/               user tile, orb, wordmark (shared assets)
"""
import math
import os
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "art-out"
RNG = np.random.default_rng(6710)  # fixed seed: same art on every build


def mkdir(*parts):
    p = os.path.join(OUT, *parts)
    os.makedirs(p, exist_ok=True)
    return p


def find_font(bold=False):
    names = (["DejaVuSans-Bold.ttf"] if bold else ["DejaVuSans.ttf"])
    dirs = ["/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/TTF",
            "/usr/share/fonts/dejavu"]
    for d in dirs:
        for n in names:
            p = os.path.join(d, n)
            if os.path.exists(p):
                return p
    return None


def font(size, bold=False):
    p = find_font(bold)
    return ImageFont.truetype(p, size) if p else ImageFont.load_default()


def to_img(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


# ---------------------------------------------------------------------------
# 1. Wallpaper: "Revive" - light ribbons over deep blue, drawn procedurally
# ---------------------------------------------------------------------------
def wallpaper(w, h, darken=0.0):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = x / w, y / h
    top = np.array([3, 10, 28], np.float32)
    bot = np.array([6, 44, 74], np.float32)
    img = top * (1 - v[..., None]) + bot * v[..., None]
    glow = np.exp(-(((u - 0.32) / 0.5) ** 2 + ((v - 0.78) / 0.38) ** 2))
    img += glow[..., None] * np.array([14, 70, 105], np.float32)

    # (base height, amplitude, frequency, phase, softness, colour)
    ribbons = [
        (0.52, 0.09, 0.85, 0.4, 0.075, (40, 200, 190)),
        (0.58, 0.07, 1.10, 2.1, 0.060, (70, 150, 235)),
        (0.47, 0.11, 0.70, 4.0, 0.090, (120, 110, 230)),
        (0.63, 0.05, 1.45, 1.2, 0.045, (90, 230, 210)),
        (0.55, 0.08, 0.95, 5.3, 0.050, (180, 220, 255)),
    ]
    for base, amp, freq, phase, soft, col in ribbons:
        yc = (base + amp * np.sin(2 * np.pi * u * freq + phase)
              + 0.025 * np.sin(2 * np.pi * u * freq * 2.6 + phase * 1.7))
        d = v - yc
        # sharp upper edge, long curtain-like fade downwards
        body = np.where(d < 0, np.exp(-(d / (soft * 0.3)) ** 2),
                        np.exp(-(d / soft) ** 2))
        core = np.exp(-(d / 0.0035) ** 2) * 0.7
        edge_fade = np.clip(np.sin(np.pi * u) * 1.25, 0, 1) ** 0.8
        shimmer = 0.75 + 0.25 * np.sin(2 * np.pi * u * 9 + phase * 3)
        inten = (body * 0.5 * shimmer + core) * edge_fade
        img += inten[..., None] * np.array(col, np.float32)

    # soft-knee tone map so bright overlaps glow instead of clipping
    img = 255 * (1 - np.exp(-img / 165.0))
    img = to_img(img)

    # out-of-focus light dots
    bokeh = Image.new("RGB", (w, h), (0, 0, 0))
    bd = ImageDraw.Draw(bokeh)
    for _ in range(int(w * h / 26000)):
        cx, cy = RNG.uniform(0, w), RNG.uniform(h * 0.25, h * 0.9)
        r = RNG.uniform(h * 0.004, h * 0.018)
        c = int(RNG.uniform(25, 70))
        bd.ellipse([cx - r, cy - r, cx + r, cy + r],
                   fill=(c // 2, c, int(c * 1.2)))
    bokeh = bokeh.filter(ImageFilter.GaussianBlur(h * 0.004))
    arr = np.asarray(img, np.float32) + np.asarray(bokeh, np.float32)

    if darken:
        arr *= (1 - darken)
    arr += RNG.normal(0, 1.2, arr.shape)  # dither: no banding on 6-bit LCDs
    return to_img(arr)


# ---------------------------------------------------------------------------
# 2. Start orb: glass sphere with an original "V" chevron emblem
# ---------------------------------------------------------------------------
def orb(size, glow_boost=1.0):
    S = size * 4
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    c = (S - 1) / 2
    r = S * 0.46
    dx, dy = (x - c) / r, (y - c) / r
    d = np.sqrt(dx ** 2 + dy ** 2)

    t = np.clip((dy + 1) / 2, 0, 1)[..., None]
    col = np.array([8, 30, 58], np.float32) * (1 - t) + \
        np.array([16, 105, 160], np.float32) * t
    bottom = np.exp(-((dx / 0.62) ** 2 + ((dy - 0.62) / 0.28) ** 2))
    col += bottom[..., None] * np.array([60, 190, 230], np.float32) * glow_boost
    rim = np.clip((d - 0.78) / 0.22, 0, 1)[..., None]
    col *= (1 - 0.55 * rim)
    alpha = np.clip((1 - d) * r, 0, 1)

    base = Image.fromarray(np.dstack([np.clip(col, 0, 255),
                                      alpha * 255]).astype(np.uint8), "RGBA")

    # emblem: rounded chevron
    em = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ed = ImageDraw.Draw(em)
    wdt = int(S * 0.085)
    pts = [(c - S * 0.19, c - S * 0.12), (c, c + S * 0.15),
           (c + S * 0.19, c - S * 0.12)]
    ed.line(pts, fill=(255, 255, 255, 255), width=wdt, joint="curve")
    for p in (pts[0], pts[2]):
        ed.ellipse([p[0] - wdt / 2, p[1] - wdt / 2, p[0] + wdt / 2,
                    p[1] + wdt / 2], fill=(255, 255, 255, 255))
    glow = em.filter(ImageFilter.GaussianBlur(S * 0.03))
    gl = np.asarray(glow, np.float32)
    gl[..., :3] = [140, 230, 255]
    gl[..., 3] *= 0.9 * glow_boost
    base = Image.alpha_composite(base, Image.fromarray(np.clip(gl, 0, 255).astype(np.uint8)))
    base = Image.alpha_composite(base, em)

    # glossy highlight on the upper half
    hl = np.clip(1 - ((dx / 0.74) ** 2 + ((dy + 0.47) / 0.42) ** 2), 0, 1) ** 0.6
    hl *= np.clip(1 - (dy + 0.47) / 0.6, 0, 1)
    hla = (hl * 0.62 * alpha * 255)
    hlimg = Image.fromarray(np.dstack([np.full_like(hla, 255)] * 3 + [hla]).astype(np.uint8), "RGBA")
    base = Image.alpha_composite(base, hlimg)

    # thin dark outline
    ring = np.clip(1 - np.abs(d - 0.985) * r / 2.2, 0, 1) * 200
    ringimg = Image.fromarray(np.dstack([np.zeros_like(ring)] * 3 + [ring]).astype(np.uint8), "RGBA")
    base = Image.alpha_composite(base, ringimg)
    return base.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------------------
# 3. xfwm4 window frames: "Aero" glass (alpha) and "Basic" (opaque)
# ---------------------------------------------------------------------------
TH = 30      # title bar height
B = 6        # side / bottom border
P = 28       # tile period (diagonal sheen repeats every 28 px)
W = H = 140  # size of the reference frame we slice tiles from


def frame(style, active):
    """Render a whole reference window frame, then slice tiles from it."""
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    rgba = np.zeros((H, W, 4), np.float32)

    if style == "aero":
        if active:
            top_c, bot_c, a_top, a_bot = (96, 150, 190), (48, 104, 146), 150, 175
        else:
            top_c, bot_c, a_top, a_bot = (150, 170, 188), (120, 145, 168), 95, 115
    else:  # basic
        if active:
            top_c, bot_c, a_top, a_bot = (200, 218, 238), (164, 190, 222), 255, 255
        else:
            top_c, bot_c, a_top, a_bot = (220, 227, 236), (198, 208, 222), 255, 255

    t = np.clip(y / TH, 0, 1)[..., None]
    col = np.array(top_c, np.float32) * (1 - t) + np.array(bot_c, np.float32) * t
    alpha = a_top * (1 - t[..., 0]) + a_bot * t[..., 0]

    # gloss band on the upper half of the title bar
    gloss = np.where(y < TH * 0.5, 0.32 - 0.22 * (y / (TH * 0.5)), 0.0)
    if style == "aero":
        # faint diagonal sheen, periodic in both directions
        s = ((x + y) % P) / P
        gloss += 0.07 * np.exp(-((s - 0.35) / 0.08) ** 2)
    gloss = gloss[..., None]
    col = col * (1 - gloss) + 255 * gloss
    alpha = np.clip(alpha + gloss[..., 0] * 120, 0, 255)

    rgba[..., :3], rgba[..., 3] = col, alpha

    # client area is not part of the frame
    client = (x >= B) & (x < W - B) & (y >= TH) & (y < H - B)
    rgba[client] = 0

    # rounded outer corners (7 px top, 3 px bottom)
    def corner_mask(cx, cy, rad, region):
        dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
        m = np.clip(rad - dist + 0.5, 0, 1)
        return np.where(region, m, 1.0)
    m = np.ones((H, W), np.float32)
    m *= corner_mask(7, 7, 7, (x < 7) & (y < 7))
    m *= corner_mask(W - 8, 7, 7, (x > W - 8) & (y < 7))
    m *= corner_mask(3, H - 4, 3, (x < 3) & (y > H - 4))
    m *= corner_mask(W - 4, H - 4, 3, (x > W - 4) & (y > H - 4))

    # outer dark line + inner light line, following the rounded shape
    edge = np.minimum.reduce([x, W - 1 - x, y, H - 1 - y])
    dark = (64, 76, 92) if style == "basic" else (8, 18, 30)
    for e_val, c_val, a_val in ((0, dark, 230), (1, (255, 255, 255), 90)):
        sel = (edge == e_val) & ~client
        rgba[sel, :3] = c_val
        rgba[sel, 3] = np.maximum(rgba[sel, 3], a_val) if e_val == 1 else a_val
    # line round the client area
    ring = (~client) & (x >= B - 1) & (x <= W - B) & (y >= TH - 1) & (y <= H - B)
    rgba[ring, :3] = (40, 60, 80) if style == "basic" else (0, 0, 0)
    rgba[ring, 3] = 150

    rgba[..., 3] *= m
    return rgba


def slice_save(rgba, box, path):
    x0, y0, x1, y1 = box
    to_img_rgba(rgba[y0:y1, x0:x1]).save(path)


def to_img_rgba(a):
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def button(kind, state, style, active):
    """kind: close|maximize|maximize-toggled|hide. Drawn at 4x, downscaled."""
    bw = 44 if kind == "close" else 27
    bh = 19
    k = 4
    img = Image.new("RGBA", (bw * k, TH * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if kind == "close":
        pal = {"normal": ((214, 104, 90), (170, 44, 32)),
               "prelight": ((244, 136, 112), (214, 58, 36)),
               "pressed": ((150, 52, 40), (110, 22, 14))}
        if not active and state == "normal":
            pal["normal"] = ((200, 200, 205), (160, 166, 176)) if style == "basic" \
                else ((150, 168, 186), (110, 130, 150))
    else:
        if style == "basic":
            pal = {"normal": ((246, 249, 252), (206, 218, 232)),
                   "prelight": ((232, 246, 255), (150, 206, 244)),
                   "pressed": ((176, 214, 240), (92, 160, 210))}
        else:
            pal = {"normal": ((150, 186, 214), (70, 112, 146)),
                   "prelight": ((150, 214, 255), (40, 140, 214)),
                   "pressed": ((60, 110, 160), (20, 60, 100))}
        if not active and state == "normal":
            pal["normal"] = ((210, 216, 224), (184, 194, 206)) if style == "basic" \
                else ((150, 166, 182), (120, 138, 156))
    top_c, bot_c = pal[state]

    x0, y0, x1, y1 = 0, 0, bw * k - 1, bh * k
    grad = Image.new("RGBA", (bw * k, bh * k))
    gd = ImageDraw.Draw(grad)
    for yy in range(bh * k):
        tt = yy / (bh * k)
        c = tuple(int(top_c[i] * (1 - tt) + bot_c[i] * tt) for i in range(3))
        if tt < 0.5:  # glass highlight on the top half
            c = tuple(int(ci + (255 - ci) * 0.25) for ci in c)
        gd.line([(0, yy), (bw * k, yy)], fill=c + (255,))
    mask = Image.new("L", (bw * k, bh * k), 0)
    ImageDraw.Draw(mask).rounded_rectangle([x0, -4 * k, x1, y1 - 1], radius=4 * k, fill=255)
    img.paste(grad, (0, 0), mask)
    d.rounded_rectangle([x0, -4 * k, x1, y1 - 1], radius=4 * k,
                        outline=(10, 20, 30, 210), width=k)

    # glyph
    gc = (255, 255, 255, 255)
    oc = (20, 30, 40, 200)
    cx, cy = bw * k / 2, bh * k / 2
    s = 4.5 * k
    lw = int(1.8 * k)

    def stroke(draw_fn):
        draw_fn(oc, lw + 2 * k)
        draw_fn(gc, lw)

    if style == "basic" and kind != "close":
        gc, oc = (30, 44, 60, 255), (255, 255, 255, 160)

    if kind == "close":
        stroke(lambda c, w_: (d.line([(cx - s, cy - s), (cx + s, cy + s)], fill=c, width=w_),
                              d.line([(cx - s, cy + s), (cx + s, cy - s)], fill=c, width=w_)))
    elif kind == "maximize":
        stroke(lambda c, w_: d.rectangle([cx - s, cy - s * 0.8, cx + s, cy + s * 0.8],
                                         outline=c, width=w_))
    elif kind == "maximize-toggled":
        stroke(lambda c, w_: (d.rectangle([cx - s + 2 * k, cy - s * 0.8 - 1 * k, cx + s, cy + s * 0.4],
                                          outline=c, width=w_),
                              d.rectangle([cx - s, cy - s * 0.4 + 2 * k, cx + s - 2 * k, cy + s * 0.8 + 1 * k],
                                          outline=c, width=w_)))
    elif kind == "hide":
        stroke(lambda c, w_: d.line([(cx - s, cy + s * 0.6), (cx + s, cy + s * 0.6)],
                                    fill=c, width=w_))
    return img.resize((bw, TH), Image.LANCZOS)


def write_xfwm4(theme_dir, style):
    xd = mkdir(theme_dir, "xfwm4")
    for active in (True, False):
        sfx = "active" if active else "inactive"
        f = frame(style, active)
        slice_save(f, (0, 0, 10, TH), f"{xd}/top-left-{sfx}.png")
        slice_save(f, (W - 10, 0, W, TH), f"{xd}/top-right-{sfx}.png")
        for n in range(1, 6):
            slice_save(f, (P, 0, 2 * P, TH), f"{xd}/title-{n}-{sfx}.png")
        slice_save(f, (0, 2 * P, B, 3 * P), f"{xd}/left-{sfx}.png")
        slice_save(f, (W - B, 2 * P, W, 3 * P), f"{xd}/right-{sfx}.png")
        slice_save(f, (P, H - B, 2 * P, H), f"{xd}/bottom-{sfx}.png")
        slice_save(f, (0, H - B, 10, H), f"{xd}/bottom-left-{sfx}.png")
        slice_save(f, (W - 10, H - B, W, H), f"{xd}/bottom-right-{sfx}.png")
        for kind in ("close", "maximize", "maximize-toggled", "hide"):
            for state in ("normal", "prelight", "pressed"):
                name = f"{kind}-{sfx}.png" if state == "normal" else f"{kind}-{state}.png"
                if state != "normal" and not active:
                    continue  # prelight/pressed images are shared
                button(kind, state, style, active).save(f"{xd}/{name}")

    text_a, text_i = ("#ffffff", "#e2ebf3") if style == "aero" else ("#16212e", "#5a6676")
    with open(f"{xd}/themerc", "w") as fh:
        fh.write(f"""# VistaRevive xfwm4 theme ({style}) - original artwork
button_layout=|HMC
button_offset=6
button_spacing=0
title_alignment=left
full_width_title=true
title_horizontal_offset=8
title_vertical_offset_active=0
title_vertical_offset_inactive=0
title_shadow_active={'true' if style == 'aero' else 'false'}
title_shadow_inactive=false
active_text_color={text_a}
inactive_text_color={text_i}
active_text_shadow_color=#000000
inactive_text_shadow_color=#000000
maximized_offset=0
shadow_delta_height=2
shadow_delta_width=0
shadow_delta_x=0
shadow_delta_y=-2
""")


# ---------------------------------------------------------------------------
# 4. GTK theme: Adwaita base + Vista-inspired overrides (pure CSS)
# ---------------------------------------------------------------------------
GTK3_CSS = r"""/* VistaRevive GTK3 theme - Adwaita base with original Vista-inspired styling */
@import url("resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained.css");

/* ---------- selection & focus ---------- */
*:selected, selection,
treeview.view:selected, iconview:selected, row:selected,
flowboxchild:selected, label:selected {
  background-color: #3a8ee0; color: #ffffff;
}
row:selected:hover, treeview.view:selected:hover { background-color: #2f7fd0; }

/* ---------- glossy buttons ---------- */
button {
  background-image: linear-gradient(to bottom, #fcfdfe 0%, #eef2f5 48%, #dfe5ec 52%, #d2dae4 100%);
  border: 1px solid #8995a4; border-radius: 3px;
  box-shadow: inset 0 1px rgba(255,255,255,0.85);
  color: #1a1a1a; text-shadow: none;
}
button:hover {
  background-image: linear-gradient(to bottom, #ecf7fe 0%, #dcf1fd 48%, #c1e6fb 52%, #a9d8f4 100%);
  border-color: #3f82b5;
}
button:active, button:checked {
  background-image: linear-gradient(to bottom, #e3f2fb 0%, #c3e2f4 48%, #9acdeb 52%, #6fb2d9 100%);
  border-color: #2d628a; box-shadow: inset 0 1px 2px rgba(0,0,0,0.25);
}
button:disabled { background-image: linear-gradient(#f4f4f4, #e9e9e9); border-color: #b8bcc2; color: #8d9399; }
button.flat { background-image: none; border-color: transparent; box-shadow: none; }
button.flat:hover { background-image: linear-gradient(to bottom, #f3f9fe, #dcedfa); border-color: #9fcdec; }
button.suggested-action { background-image: linear-gradient(to bottom, #8ec9f4 0%, #5aa9e6 48%, #3b8fd6 52%, #2f7fc8 100%); border-color: #1f5f99; color: #fff; }

/* ---------- entries ---------- */
entry { border: 1px solid #a9adb5; border-radius: 2px; box-shadow: inset 0 1px rgba(0,0,0,0.06); }
entry:focus { border-color: #3c7db1; box-shadow: 0 0 0 1px rgba(60,125,177,0.35); }

/* ---------- menus & tooltips ---------- */
menu, .menu, .context-menu { background-color: #f5f6f8; border: 1px solid #9a9a9a; padding: 2px; }
menuitem { padding: 4px 18px 4px 10px; border: 1px solid transparent; }
menuitem:hover {
  background-image: linear-gradient(to bottom, #f1f8fe, #d9ebfa); color: #000;
  border: 1px solid #a7d3ee; border-radius: 3px;
}
tooltip, tooltip.background {
  background-image: linear-gradient(to bottom, #ffffff, #e6e8f1);
  border: 1px solid #7a7a7a; border-radius: 3px; color: #4a4a4a;
}
tooltip * { color: #4a4a4a; }

/* ---------- taskbar (xfce4-panel): dark glass ---------- */
.xfce4-panel.background {
  background-color: transparent;
  background-image: linear-gradient(to bottom,
      rgba(78, 90, 104, 0.90) 0%, rgba(30, 36, 44, 0.90) 46%,
      rgba(6, 9, 13, 0.93) 52%, rgba(18, 24, 32, 0.93) 100%);
  border-top: 1px solid rgba(255, 255, 255, 0.28);
  color: #ffffff;
}
.xfce4-panel.background label { color: #ffffff; text-shadow: 0 1px 2px rgba(0,0,0,0.9); }
.xfce4-panel.background button {
  background-image: none; background-color: transparent; color: #ffffff;
  border: 1px solid transparent; border-radius: 3px; box-shadow: none; padding: 2px 6px;
}
.xfce4-panel.background button:hover {
  background-image: linear-gradient(to bottom, rgba(255,255,255,0.30), rgba(255,255,255,0.10) 50%,
                                    rgba(255,255,255,0.03) 51%, rgba(255,255,255,0.14));
  border-color: rgba(255,255,255,0.38);
}
.xfce4-panel.background button:checked, .xfce4-panel.background button:active {
  background-image: linear-gradient(to bottom, rgba(150,205,255,0.40), rgba(80,150,220,0.22) 50%,
                                    rgba(40,100,170,0.26) 51%, rgba(100,170,235,0.38));
  border-color: rgba(170,215,255,0.55);
}
#whiskermenu-button, #whiskermenu-button:hover, #whiskermenu-button:checked {
  background-image: none; border-color: transparent; padding: 0 6px;
}

/* ---------- start menu (Whisker) ---------- */
#whiskermenu-window {
  background-color: transparent;
  background-image: linear-gradient(to bottom, rgba(44, 78, 108, 0.96), rgba(14, 30, 46, 0.97));
  border: 1px solid rgba(0, 0, 0, 0.7); border-radius: 6px; color: #ffffff;
}
#whiskermenu-window label { color: #ffffff; }
#whiskermenu-window treeview.view, #whiskermenu-window iconview,
#whiskermenu-window scrolledwindow viewport, #whiskermenu-window scrolledwindow {
  background-color: #ffffff; color: #1a1a1a; border-radius: 4px;
}
#whiskermenu-window treeview.view label, #whiskermenu-window iconview label { color: #1a1a1a; }
#whiskermenu-window treeview.view:hover { background-image: linear-gradient(#f1f8fe, #d9ebfa); }
#whiskermenu-window entry {
  background-color: #ffffff; color: #1a1a1a; border-radius: 12px; padding: 3px 10px;
  border: 1px solid rgba(0,0,0,0.5);
}
#whiskermenu-window button {
  background-image: none; background-color: transparent; color: #ffffff;
  border: 1px solid transparent; box-shadow: none;
}
#whiskermenu-window button:hover, #whiskermenu-window button:checked {
  background-image: linear-gradient(to bottom, rgba(255,255,255,0.28), rgba(255,255,255,0.08));
  border-color: rgba(255,255,255,0.35);
}

/* ---------- login screen (LightDM GTK greeter) ---------- */
#panel_window {
  background-image: linear-gradient(to bottom, rgba(40,48,58,0.85), rgba(6,10,14,0.85));
  color: #ffffff; border-bottom: 1px solid rgba(255,255,255,0.15);
}
#panel_window label, #panel_window menubar > menuitem { color: #ffffff; }
#login_window {
  background-color: rgba(10, 30, 50, 0.55);
  border: 1px solid rgba(255,255,255,0.25); border-radius: 8px;
  box-shadow: 0 6px 24px rgba(0,0,0,0.6); padding: 18px;
}
#login_window label { color: #ffffff; text-shadow: 0 1px 2px rgba(0,0,0,0.8); }
#login_window entry { border-radius: 3px; }
#login_window #user_image { border: 2px solid rgba(255,255,255,0.7); border-radius: 6px; }
"""

GTK2_RC = """# VistaRevive GTK2 fallback: reuse Adwaita's GTK2 engine with blue selection
gtk-color-scheme = "selected_bg_color:#3a8ee0\\nselected_fg_color:#ffffff"
include "/usr/share/themes/Adwaita/gtk-2.0/gtkrc"
"""


def write_gtk_theme(theme_dir):
    mkdir(theme_dir, "gtk-3.0")
    mkdir(theme_dir, "gtk-2.0")
    with open(os.path.join(OUT, theme_dir, "gtk-3.0", "gtk.css"), "w") as fh:
        fh.write(GTK3_CSS)
    with open(os.path.join(OUT, theme_dir, "gtk-2.0", "gtkrc"), "w") as fh:
        fh.write(GTK2_RC)
    with open(os.path.join(OUT, theme_dir, "index.theme"), "w") as fh:
        fh.write("""[Desktop Entry]
Type=X-GNOME-Metatheme
Name=VistaRevive
Comment=Original Vista-inspired theme for VistaRevive
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=VistaRevive
MetacityTheme=VistaRevive
IconTheme=oxygen
CursorTheme=DMZ-White
""")


# ---------------------------------------------------------------------------
# 5. Login user tile + boot splash pieces
# ---------------------------------------------------------------------------
def user_tile(size=96):
    k = 4
    S = size * k
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for yy in range(S):
        t = yy / S
        c = (int(70 + 60 * t), int(140 + 50 * t), int(200 + 30 * t), 255)
        d.line([(0, yy), (S, yy)], fill=c)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=10 * k, fill=255)
    tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    tile.paste(img, (0, 0), mask)
    d = ImageDraw.Draw(tile)
    fg = (255, 255, 255, 230)
    d.ellipse([S * 0.36, S * 0.2, S * 0.64, S * 0.48], fill=fg)           # head
    d.pieslice([S * 0.2, S * 0.52, S * 0.8, S * 1.12], 180, 360, fill=fg)  # shoulders
    gl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(gl).ellipse([-S * 0.3, -S * 0.75, S * 1.3, S * 0.45], fill=(255, 255, 255, 60))
    tile = Image.alpha_composite(tile, Image.composite(gl, Image.new("RGBA", (S, S)), mask))
    return tile.resize((size, size), Image.LANCZOS)


def wordmark(text, size):
    f = font(size)
    tmp = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    l, t, r, b = tmp.textbbox((0, 0), text, font=f)
    w, h = r - l + 20, b - t + 20
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((10 - l, 10 - t), text, font=f, fill=(225, 238, 248, 255))
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((10 - l, 12 - t), text, font=f, fill=(0, 0, 0, 160))
    shadow = shadow.filter(ImageFilter.GaussianBlur(2))
    return Image.alpha_composite(shadow, img)


def glow_ring(size):
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2
    d = np.sqrt((x - c) ** 2 + (y - c) ** 2) / (size / 2)
    a = np.exp(-((d - 0.55) / 0.22) ** 2) * 200
    rgba = np.dstack([np.full_like(a, 90), np.full_like(a, 200), np.full_like(a, 255), a])
    return to_img_rgba(rgba)


def bar_track(w=220, h=8):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle([0, 0, w - 1, h - 1], radius=h // 2,
                                          fill=(255, 255, 255, 34), outline=(255, 255, 255, 70))
    return img


def bar_segment(w=56, h=8):
    x = np.linspace(-1, 1, w)
    a = np.clip(1 - x ** 2, 0, 1) ** 0.7
    rows = []
    for yy in range(h):
        g = 1.0 if yy < h / 2 else 0.8
        rows.append(np.stack([90 * g + 0 * a, 220 * g + 0 * a, 200 * g + 0 * a, a * 255], -1))
    return to_img_rgba(np.array(rows))


PLY_SCRIPT = r"""# VistaRevive boot splash - original artwork, Plymouth script module
Window.SetBackgroundTopColor(0.012, 0.04, 0.11);
Window.SetBackgroundBottomColor(0.024, 0.17, 0.29);

sw = Window.GetWidth();
sh = Window.GetHeight();

orb_img   = Image("orb.png");
glow_img  = Image("glow.png");
word_img  = Image("wordmark.png");
track_img = Image("track.png");
seg_img   = Image("segment.png");

cx = sw / 2;
cy = sh * 0.42;

glow  = Sprite(glow_img);
orb   = Sprite(orb_img);
word  = Sprite(word_img);
track = Sprite(track_img);
seg   = Sprite(seg_img);

glow.SetPosition(cx - glow_img.GetWidth() / 2, cy - glow_img.GetHeight() / 2, 1);
orb.SetPosition(cx - orb_img.GetWidth() / 2, cy - orb_img.GetHeight() / 2, 2);
wy = cy + orb_img.GetHeight() / 2 + 20;
word.SetPosition(cx - word_img.GetWidth() / 2, wy, 2);
tx = cx - track_img.GetWidth() / 2;
ty = wy + word_img.GetHeight() + 24;
track.SetPosition(tx, ty, 2);
seg.SetPosition(tx, ty, 3);

t = 0;
fun refresh_callback ()
{
  t++;
  glow.SetOpacity(0.55 + 0.45 * Math.Sin(t / 22));
  span = track_img.GetWidth() - seg_img.GetWidth();
  p = (t % 140) / 140;
  seg.SetX(tx + span * p);
  seg.SetOpacity(Math.Sin(p * 3.14159));
}
Plymouth.SetRefreshFunction(refresh_callback);

# Minimal message / password support (needed only for encrypted disks)
msg = Sprite();
fun message_callback (text)
{
  msg.SetImage(Image.Text(text, 0.85, 0.92, 0.97));
  msg.SetPosition(cx - msg.GetImage().GetWidth() / 2, ty + 40, 4);
}
Plymouth.SetMessageFunction(message_callback);

prompt = Sprite();
fun password_callback (prompt_text, bullets)
{
  s = prompt_text + "  ";
  for (i = 0; i < bullets; i++) s = s + "*";
  prompt.SetImage(Image.Text(s, 1, 1, 1));
  prompt.SetPosition(cx - prompt.GetImage().GetWidth() / 2, ty + 40, 4);
  prompt.SetOpacity(1);
}
Plymouth.SetDisplayPasswordFunction(password_callback);
fun normal_callback () { prompt.SetOpacity(0); }
Plymouth.SetDisplayNormalFunction(normal_callback);
"""

PLY_THEME = """[Plymouth Theme]
Name=VistaRevive
Description=VistaRevive boot splash (original artwork)
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/vistarevive
ScriptFile=/usr/share/plymouth/themes/vistarevive/vistarevive.script
"""


# ---------------------------------------------------------------------------
# 6. Sound theme: synthesised from scratch
# ---------------------------------------------------------------------------
SR = 44100


def note(freq, dur, amp=0.3, attack=0.01, release=None, harmonics=(1, 0.35, 0.12, 0.05)):
    n = int(SR * dur)
    t = np.arange(n) / SR
    sig = sum(h * np.sin(2 * np.pi * freq * (i + 1) * t) for i, h in enumerate(harmonics))
    env = np.minimum(1, t / max(attack, 1e-4))
    rel = release if release else dur
    env *= np.exp(-t / (rel / 4))
    return amp * sig * env


def place(buf, sig, at):
    i = int(at * SR)
    end = min(len(buf), i + len(sig))
    buf[i:end] += sig[:end - i]


def reverb(sig, mix=0.3):
    out = sig.copy()
    for delay, g in ((0.031, 0.5), (0.047, 0.42), (0.071, 0.33), (0.113, 0.25)):
        d = int(delay * SR)
        tmp = np.zeros_like(sig)
        for k in range(1, 6):
            if d * k < len(sig):
                tmp[d * k:] += sig[:-d * k] * (g ** k)
        out += tmp * mix
    return out


def hz(name):
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    n = names[name[0]] + (1 if "#" in name else 0)
    octave = int(name[-1])
    return 440 * 2 ** ((n + (octave - 4) * 12) / 12)


def render(events, length, rev=0.35, pad=None):
    buf = np.zeros(int(SR * length))
    for at, nm, dur, amp in events:
        place(buf, note(hz(nm), dur, amp), at)
    if pad:
        for nm in pad:
            place(buf, note(hz(nm), length * 0.9, 0.06, attack=0.6, release=length,
                            harmonics=(1, 0.2)), 0.05)
    buf = reverb(buf, rev)
    fade = np.ones_like(buf)
    fl = int(SR * 0.05)
    fade[-fl:] = np.linspace(1, 0, fl)
    buf *= fade
    peak = np.max(np.abs(buf)) or 1
    return buf / peak * 0.7


def save_wav(path, mono):
    left = mono
    right = np.concatenate([np.zeros(int(SR * 0.008)), mono[:-int(SR * 0.008)]])  # subtle width
    stereo = np.stack([left, right], -1)
    data = (np.clip(stereo, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


SOUNDS = {
    # freedesktop event name: (events [(time, note, dur, amp)], length, pad notes)
    "desktop-login": ([(0.00, "D4", 1.8, 0.30), (0.18, "A4", 1.7, 0.26), (0.36, "E5", 1.6, 0.24),
                       (0.54, "F#5", 1.6, 0.22), (0.80, "A5", 2.0, 0.24), (1.10, "D6", 2.2, 0.16)],
                      3.4, ("D3", "A3", "E4")),
    "desktop-logout": ([(0.00, "A5", 1.0, 0.25), (0.20, "E5", 1.0, 0.25), (0.40, "C#5", 1.0, 0.25),
                        (0.62, "A4", 1.4, 0.28)], 2.2, ("A3",)),
    "dialog-error": ([(0.00, "E4", 0.35, 0.35), (0.14, "C4", 0.6, 0.35)], 0.9, None),
    "dialog-warning": ([(0.00, "G4", 0.5, 0.33), (0.0, "D5", 0.5, 0.12)], 0.8, None),
    "dialog-information": ([(0.00, "E5", 0.5, 0.28), (0.12, "B5", 0.7, 0.24)], 0.9, None),
    "message-new-instant": ([(0.00, "G5", 0.4, 0.26), (0.10, "D6", 0.6, 0.22)], 0.8, None),
    "device-added": ([(0.00, "C5", 0.3, 0.3), (0.12, "G5", 0.5, 0.28)], 0.7, None),
    "device-removed": ([(0.00, "G5", 0.3, 0.3), (0.12, "C5", 0.5, 0.28)], 0.7, None),
    "complete": ([(0.00, "C5", 0.3, 0.26), (0.09, "E5", 0.3, 0.26), (0.18, "G5", 0.6, 0.26)], 0.9, None),
    "bell": ([(0.00, "A5", 0.25, 0.3)], 0.4, None),
    "trash-empty": ([(0.00, "D5", 0.15, 0.2), (0.05, "A4", 0.2, 0.2), (0.1, "F4", 0.3, 0.2)], 0.6, None),
}


def write_sounds():
    base = mkdir("sounds", "VistaRevive")
    st = mkdir("sounds", "VistaRevive", "stereo")
    with open(os.path.join(base, "index.theme"), "w") as fh:
        fh.write("""[Sound Theme]
Name=VistaRevive
Comment=Original VistaRevive sound theme
Inherits=freedesktop
Directories=stereo

[stereo]
OutputProfile=stereo
""")
    for name, (events, length, pad) in SOUNDS.items():
        save_wav(os.path.join(st, f"{name}.wav"), render(events, length, pad=pad))


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main():
    print("Wallpapers...")
    bg = mkdir("backgrounds")
    for w, h in ((1280, 800), (1680, 1050)):
        wallpaper(w, h).save(f"{bg}/vistarevive-{w}x{h}.png", optimize=True)
    login = wallpaper(1680, 1050, darken=0.35).filter(ImageFilter.GaussianBlur(6))
    login.save(f"{bg}/vistarevive-login.png", optimize=True)

    print("Start orb...")
    for s in (16, 22, 24, 32, 48, 64, 128):
        d = mkdir("icons", "hicolor", f"{s}x{s}", "apps")
        orb(s).save(f"{d}/vistarevive-start.png")
    shared = mkdir("vistarevive")
    orb(256).save(f"{shared}/orb-256.png")
    orb(48, glow_boost=1.6).save(f"{shared}/orb-48-hover.png")

    print("Window frames...")
    write_xfwm4("themes/VistaRevive", "aero")
    write_xfwm4("themes/VistaRevive-Basic", "basic")
    write_gtk_theme("themes/VistaRevive")

    print("Login tile and boot splash...")
    user_tile(96).save(f"{shared}/user-tile.png")
    wm = wordmark("VistaRevive", 30)
    wm.save(f"{shared}/wordmark.png")
    ply = mkdir("plymouth", "vistarevive")
    orb(128).save(f"{ply}/orb.png")
    glow_ring(260).save(f"{ply}/glow.png")
    wm.save(f"{ply}/wordmark.png")
    bar_track().save(f"{ply}/track.png")
    bar_segment().save(f"{ply}/segment.png")
    with open(f"{ply}/vistarevive.script", "w") as fh:
        fh.write(PLY_SCRIPT)
    with open(f"{ply}/vistarevive.plymouth", "w") as fh:
        fh.write(PLY_THEME)

    print("Sounds...")
    write_sounds()
    print(f"Done -> {os.path.abspath(OUT)}")


if __name__ == "__main__":
    main()
