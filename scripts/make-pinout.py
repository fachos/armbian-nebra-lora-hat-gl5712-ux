#!/usr/bin/env python3
"""Render docs/assets/pinout-40pin.png — 40-pin map + signal flow (dark theme)."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1680, 980
BG = (14, 17, 22)
PANEL = (22, 27, 34)
PANEL2 = (26, 32, 40)
EDGE = (48, 54, 61)
INK = (230, 237, 243)
DIM = (139, 148, 158)
CYAN = (47, 129, 247)
ORANGE = (240, 136, 62)
VIOLET = (163, 113, 247)

FDIR = "/usr/share/fonts/truetype/dejavu/"


def font(name, size):
    try:
        return ImageFont.truetype(FDIR + name, size)
    except OSError:
        return ImageFont.load_default()


f_title, f_h = font("DejaVuSans-Bold.ttf", 32), font("DejaVuSans-Bold.ttf", 20)
f_t, f_s = font("DejaVuSans.ttf", 17), font("DejaVuSans.ttf", 15)
f_xs, f_pin = font("DejaVuSans.ttf", 13), font("DejaVuSans.ttf", 12)

img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)

d.text((48, 30), "Nebra LoRa HAT  ·  GL5712-UX  ·  Rock Pi 4B+  —  40-pin map & signal flow",
       font=f_title, fill=INK)
d.line([(48, 78), (W - 48, 78)], fill=EDGE, width=2)

# ---------------- header ----------------
HX, HY, BW, BH, GAP = 60, 132, 200, 26, 4
ROW = BH + GAP
labels = {
    1: "3V3", 2: "5V", 4: "5V", 17: "3V3",
    6: "GND", 9: "GND", 14: "GND", 20: "GND",
    25: "GND", 30: "GND", 34: "GND", 39: "GND",
    11: "NC", 12: "POWER_EN · GPIO4_A3",
    19: "SPI1 MOSI", 21: "SPI1 MISO", 23: "SPI1 SCLK", 24: "SPI1 CS0",
    33: "band jumper · GPIO2_B4",
}
strong = {12: ORANGE, 19: CYAN, 21: CYAN, 23: CYAN, 24: CYAN, 33: VIOLET}

d.text((HX, HY - 32), "40-pin header (top view, pin 1 top-left)", font=f_h, fill=INK)

for i in range(20):
    y = HY + i * ROW
    for col, base in ((0, 1), (1, 2)):
        pin = base + i * 2
        x = HX + col * (BW + 60)
        lab = labels.get(pin, "")
        if pin in strong:
            fill, tc, edge = strong[pin], BG, strong[pin]
        elif pin in (1, 2, 4, 17):
            fill, tc, edge = PANEL2, CYAN, EDGE
        else:
            fill, tc, edge = PANEL, DIM, EDGE
        d.rectangle([x, y, x + BW, y + BH], fill=fill, outline=edge)
        d.text((x + 7, y + 7), f"{pin:>2}", font=f_pin, fill=tc)
        if lab:
            d.text((x + 32, y + 7), lab, font=f_pin, fill=tc)

ly = HY + 20 * ROW + 22
lx = HX
for c, t in [(ORANGE, "control GPIO"), (CYAN, "SPI1 @ 2 MHz"), (VIOLET, "band jumper (read-only)")]:
    d.rectangle([lx, ly, lx + 14, ly + 14], fill=c)
    d.text((lx + 22, ly - 1), t, font=f_xs, fill=INK)
    lx += 22 + d.textlength(t, font=f_xs) + 46

# ---------------- signal flow ----------------
RX = 760
d.text((RX, HY - 32), "Signal flow", font=f_h, fill=INK)


def box(x, y, w, h, title, sub="", fill=PANEL, outline=EDGE):
    d.rounded_rectangle([x, y, x + w, y + h], 10, fill=fill, outline=outline, width=2)
    d.text((x + 14, y + 11), title, font=f_t, fill=INK)
    for j, line in enumerate(sub.split("\n")):
        d.text((x + 14, y + 38 + j * 19), line, font=f_xs, fill=DIM)


def arrow(x1, y1, x2, y2, label="", col=INK):
    d.line([(x1, y1), (x2, y2)], fill=col, width=3)
    if x2 >= x1:
        d.polygon([(x2, y2), (x2 - 10, y2 - 6), (x2 - 10, y2 + 6)], fill=col)
    else:
        d.polygon([(x2, y2), (x2 + 10, y2 - 6), (x2 + 10, y2 + 6)], fill=col)
    if label:
        tw = d.textlength(label, font=f_xs)
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        d.rectangle([mx - tw / 2 - 6, my - 19, mx + tw / 2 + 6, my - 1], fill=BG)
        d.text((mx - tw / 2, my - 18), label, font=f_xs, fill=col)


box(RX, HY + 12, 300, 92, "Radxa ROCK Pi 4B+",
    "RK3399 · 2 GB · Armbian trixie\nspidev1.0 · gpiochip4")
box(RX + 420, HY + 12, 300, 92, "GL5712-UX (SX1301)",
    "concentrator · 8 IF chains\nAGC firmware · calibration", PANEL2)
box(RX + 420, HY + 176, 300, 92, "SX1257 radio A / B",
    "863–928 MHz front end\n32 MHz TCXO from radio B", PANEL2)
box(RX + 420, HY + 340, 300, 84, "Antenna",
    "u.FL → 915 MHz model tested\nnever transmit without it", PANEL2)
box(RX, HY + 176, 300, 132, "Control lines",
    "POWER_EN  gpiochip4:3   HIGH, held\n"
    "reset     = cycle POWER_EN (line 3)\n"
    "LED       gpiochip4:28  lit = up\n"
    "sysfs 131 / 156 · lines 21/22 unused", (33, 26, 18), (74, 52, 30))

arrow(RX + 300, HY + 58, RX + 418, HY + 58, "SPI1 2 MHz", CYAN)
arrow(RX + 570, HY + 104, RX + 570, HY + 174, "IF / clock", DIM)
arrow(RX + 570, HY + 268, RX + 570, HY + 338, "RF", DIM)

cx0, cy0 = RX + 300, HY + 214
mid = RX + 360
d.line([(cx0, cy0), (mid, cy0)], fill=ORANGE, width=3)
d.line([(mid, cy0), (mid, HY + 78)], fill=ORANGE, width=3)
arrow(mid, HY + 78, RX + 418, HY + 78, "", ORANGE)

# ---------------- notes ----------------
ny = HY + 452
notes = [
    ("Why 2 MHz SPI", "The HAT keeps a stub trace from a removed SPI NOR flash; above ~4 MHz registers read back corrupted."),
    ("Why reads need a dummy byte", "Read as [address, 0x00] — 2 bytes, value in byte 1. A 1-byte read gives 0x66; the 3-byte mux form gives 0x67 everywhere."),
    ("Why reset is the power rail", "Not a GPIO: driving the lines sources call NRESET (21/22) during power-up changed nothing. Cycle POWER_EN: LOW 500 ms, HIGH, wait 2 s."),
    ("Why one owner on POWER_EN", "gpioset one-shots exit and release the line, the TCXO rail drops mid-init. A long-running service holds it."),
]
for i, (t, s) in enumerate(notes):
    y = ny + i * 68
    d.rectangle([RX - 10, y + 2, RX - 4, y + 54], fill=CYAN)
    d.text((RX + 6, y), t, font=f_t, fill=INK)
    d.text((RX + 6, y + 24), s, font=f_xs, fill=DIM)

out = Path(__file__).resolve().parent.parent / "docs/assets/pinout-40pin.png"
img.save(out, "PNG")
print("written", out, img.size)
