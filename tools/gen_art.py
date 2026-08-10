#!/usr/bin/env python3
"""Generate every sprite, tile and background layer the game loads.

Run from the project root:  python3 tools/gen_art.py

The palette is sampled from the Kenney "Platformer Art Complete Pack" (CC0)
sources in assets/kenney/, and Kenney's clouds/bush art is reused directly for
the parallax layers. Everything else is drawn here so the terrain art lines up
exactly with the collision geometry the level builder generates.
"""

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pngio
from canvas import Canvas, sheet

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KENNEY = os.path.join(ROOT, "assets", "kenney")

FRAME_W, FRAME_H = 40, 44
ORIGIN = (20, 22)  # player position inside a frame; feet sit at y = 22 + 19


# --------------------------------------------------------------------------- #
# palette
# --------------------------------------------------------------------------- #
def sample_palette():
    """Pull base hues out of the Kenney CC0 tiles so the art harmonises.

    Kenney's grassMid tile is a green lip over a brown body, so grass and dirt
    both come from it; dirtMid supplies the grey stone used for hardware.
    """
    grass_tile = pngio.read(os.path.join(KENNEY, "grassMid.png"))
    stone_tile = pngio.read(os.path.join(KENNEY, "dirtMid.png"))
    cloud = pngio.read(os.path.join(KENNEY, "cloud1.png"))

    def dominant(img, y0, y1, x0=4, x1=66):
        block = img[y0:y1, x0:x1].reshape(-1, 4)
        block = block[block[:, 3] > 128]
        colours, counts = np.unique(block[:, :3], axis=0, return_counts=True)
        return tuple(int(v) for v in colours[np.argmax(counts)])

    grass = dominant(grass_tile, 2, 9)
    dirt = dominant(grass_tile, 30, 64)
    stone = dominant(stone_tile, 0, 70)
    haze = dominant(cloud, 20, 50, 20, 100)
    return {
        "grass": grass,
        "grass_light": shift(grass, 22),
        "grass_dark": mix(grass, (0, 0, 0), 0.34),
        "dirt": dirt,
        "dirt_dark": mix(dirt, (0, 0, 0), 0.26),
        "stone": stone,
        # GHZ-style sky: a saturated blue up top fading into Kenney's haze
        "sky_top": (48, 108, 216),
        "sky_bottom": haze,
    }


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shift(c, amount):
    return tuple(int(max(0, min(255, v + amount))) for v in c)


PAL = sample_palette()
GRASS = PAL["grass"]
GRASS_D = PAL["grass_dark"]
GRASS_L = PAL["grass_light"]
DIRT = PAL["dirt"]
DIRT_D = PAL["dirt_dark"]
DIRT_L = shift(DIRT, 26)
SKY_TOP = PAL["sky_top"]
SKY_BOT = PAL["sky_bottom"]

# fixed object colours
RED = (222, 48, 44)
RED_D = (148, 24, 30)

# Mascot colours. These are module globals rather than parameters because every
# pose function reads them; use_palette() swaps the whole roster's look at once.
CHARACTERS = {
    "dash": {
        "body": (36, 92, 216), "body_d": (22, 56, 150), "body_l": (86, 148, 244),
        "skin": (247, 202, 148), "skin_d": (208, 152, 98),
        "shoe": (222, 48, 44), "shoe_d": (148, 24, 30),
        "quills": 2, "tuft": False,
    },
    "pip": {
        "body": (246, 166, 46), "body_d": (186, 112, 20), "body_l": (255, 206, 116),
        "skin": (255, 235, 200), "skin_d": (224, 190, 146),
        "shoe": (232, 76, 60), "shoe_d": (150, 34, 32),
        "quills": 3, "tuft": False,
    },
    "brawn": {
        "body": (206, 52, 52), "body_d": (140, 26, 30), "body_l": (240, 108, 96),
        "skin": (247, 202, 148), "skin_d": (208, 152, 98),
        "shoe": (74, 176, 96), "shoe_d": (34, 108, 56),
        "quills": 2, "tuft": False,
    },
    "volt": {
        "body": (58, 58, 74), "body_d": (28, 28, 40), "body_l": (208, 62, 62),
        "skin": (247, 202, 148), "skin_d": (208, 152, 98),
        "shoe": (222, 48, 44), "shoe_d": (148, 24, 30),
        "quills": 3, "tuft": False,
    },
    "rosa": {
        "body": (238, 120, 178), "body_d": (172, 62, 118), "body_l": (255, 178, 214),
        "skin": (247, 202, 148), "skin_d": (208, 152, 98),
        "shoe": (216, 60, 92), "shoe_d": (140, 28, 52),
        "quills": 2, "tuft": True,
    },
}

MBODY = MBODY_D = MBODY_L = MSKIN = MSKIN_D = MSHOE = MSHOE_D = (0, 0, 0)
MQUILLS = 2
MTUFT = False


def use_palette(slug):
    """Point the mascot drawing globals at one character's colours."""
    global MBODY, MBODY_D, MBODY_L, MSKIN, MSKIN_D, MSHOE, MSHOE_D, MQUILLS, MTUFT
    pal = CHARACTERS[slug]
    MBODY, MBODY_D, MBODY_L = pal["body"], pal["body_d"], pal["body_l"]
    MSKIN, MSKIN_D = pal["skin"], pal["skin_d"]
    MSHOE, MSHOE_D = pal["shoe"], pal["shoe_d"]
    MQUILLS, MTUFT = pal["quills"], pal["tuft"]
WHITE = (255, 255, 255)
EYE = (30, 30, 66)
INK = (14, 22, 56)
GOLD = (255, 206, 56)
GOLD_D = (206, 140, 20)
GOLD_L = (255, 240, 168)
STEEL = PAL["stone"]
STEEL_D = mix(STEEL, (0, 0, 0), 0.42)


# --------------------------------------------------------------------------- #
# mascot
# --------------------------------------------------------------------------- #
def rot(x, y, cx, cy, deg):
    a = math.radians(deg)
    dx, dy = x - cx, y - cy
    return cx + dx * math.cos(a) - dy * math.sin(a), cy + dx * math.sin(a) + dy * math.cos(a)


def shoe(c, x, y, deg=0.0, flat=False, colour=None):
    """Sneaker with a white cuff, drawn centred on the ankle joint."""
    colour = colour or MSHOE
    w, h = (11, 6) if not flat else (12, 5)
    pts = [(-w / 2, -h / 2), (w / 2 - 1, -h / 2), (w / 2 + 1, h / 2), (-w / 2 - 1, h / 2)]
    pts = [rot(x + px, y + py, x, y, deg) for px, py in pts]
    c.poly(pts, colour)
    cuff = [(-w / 2 - 1, -h / 2 - 2), (-w / 2 + 3, -h / 2 - 2), (-w / 2 + 3, -h / 2 + 1), (-w / 2 - 1, -h / 2 + 1)]
    c.poly([rot(x + px, y + py, x, y, deg) for px, py in cuff], WHITE)
    sole = [(-w / 2 - 1, h / 2 - 1), (w / 2 + 1, h / 2 - 1), (w / 2 + 1, h / 2), (-w / 2 - 1, h / 2)]
    c.poly([rot(x + px, y + py, x, y, deg) for px, py in sole], WHITE)


def quills(c, hx, hy, spread=0.0):
    """Swept-back quills, drawn before the head so they sit behind it."""
    c.poly([(hx - 7, hy - 5), (hx - 19 - spread, hy - 10), (hx - 8, hy + 2)], MBODY)
    c.poly([(hx - 7, hy + 2), (hx - 20 - spread, hy + 6), (hx - 7, hy + 9)], MBODY)
    if MQUILLS >= 3:
        c.poly([(hx - 6, hy - 8), (hx - 15 - spread, hy - 16), (hx - 8, hy - 5)], MBODY)
    c.poly([(hx - 8, hy - 4), (hx - 15 - spread, hy - 7), (hx - 9, hy)], MBODY_D)
    if MTUFT:
        c.poly([(hx - 2, hy - 9), (hx - 6, hy - 17), (hx + 4, hy - 10)], MBODY_L)


def head(c, hx, hy, eyes="open", squint=0.0, face=(0.0, 0.0)):
    quills(c, hx, hy)
    c.poly([(hx - 3, hy - 8), (hx - 1, hy - 13), (hx + 3, hy - 7)], MBODY)  # ear
    c.disc(hx, hy, 9.5, MBODY)
    c.ring(hx, hy, 9.5, 7.5, MBODY_D, a0=30, a1=150)  # underside shading
    face_dx, face_dy = face
    mx, my = hx + 7 + face_dx, hy + 3 + face_dy
    c.disc(mx, my, 5.5, MSKIN)  # muzzle
    c.disc(mx + 3, my - 3, 2, INK)  # nose
    c.ellipse(mx - 2, my + 3, 3, 1.6, MSKIN_D)  # mouth line

    # one merged eye shape (classic Genesis look) keeps the outline pass clean
    ex, ey = hx + 3 + face_dx, hy - 2 + face_dy
    if eyes == "shut":
        c.rect(ex - 6, ey, ex + 4, ey + 1, EYE)
    else:
        c.ellipse(ex, ey, 4.2, 5.2 - squint * 2.6, WHITE)
        c.ellipse(ex - 5, ey, 3.6, 4.6 - squint * 2.4, WHITE)
        if eyes == "open":
            c.ellipse(ex + 1.6, ey + 0.6, 1.9, 2.6 - squint, EYE)
            c.ellipse(ex - 4.2, ey + 0.6, 1.6, 2.4 - squint, EYE)
        elif eyes == "dead":
            for ox in (1.6, -4.2):
                c.line(ex + ox - 2, ey - 2, ex + ox + 2, ey + 2, EYE)
                c.line(ex + ox + 2, ey - 2, ex + ox - 2, ey + 2, EYE)


def torso(c, x, y, rx=8.5, ry=7.5):
    c.ellipse(x, y, rx, ry, MBODY)
    c.ring(x, y, rx, rx - 2, MBODY_D, a0=20, a1=160)  # underside
    c.ellipse(x + 4, y + 1, rx - 4.0, ry - 3.0, MSKIN)  # chest/belly patch


def arm(c, sx, sy, hx, hy):
    c.capsule(sx, sy, hx, hy, 2.0, MSKIN_D)
    c.disc(hx, hy, 2.6, WHITE)  # glove


def leg(c, hx, hy, ax, ay):
    c.capsule(hx, hy, ax, ay, 2.2, MSKIN_D)


def standing(eyes="open", walk=None, lean=0.0, arms="down", squint=0.0, face=(0.0, 0.0)):
    """Upright pose. `walk` is a phase in [0,1) driving the leg cycle."""
    c = Canvas(FRAME_W, FRAME_H)
    ox, oy = ORIGIN
    hip_x, hip_y = ox - 1 + lean * 2, oy + 11
    hx, hy = ox + 1 + lean * 3, oy - 10

    if walk is None:
        back, front = (hip_x - 4, oy + 16), (hip_x + 4, oy + 16)
        back_rot = front_rot = 0.0
    else:
        # ankles travel an ellipse below the hips; half a cycle apart
        def ankle(phase):
            a = phase * math.tau
            return hip_x + math.cos(a) * 6.5, oy + 15 + math.sin(a) * 2.5

        back = ankle(walk + 0.5)
        front = ankle(walk)
        back_rot = math.cos((walk + 0.5) * math.tau) * -12
        front_rot = math.cos(walk * math.tau) * -12

    leg(c, hip_x, hip_y, *back)
    shoe(c, back[0], back[1] + 3, back_rot)
    torso(c, hip_x, oy + 6)
    head(c, hx, hy, eyes, squint, face)
    if arms == "down":
        arm(c, hip_x + 4, oy + 4, hip_x + 7, oy + 9)
    elif arms == "back":
        arm(c, hip_x + 2, oy + 3, hip_x - 6, oy + 7)
    elif arms == "up":
        arm(c, hip_x + 3, oy + 3, hip_x + 5, oy - 4)
        arm(c, hip_x - 3, oy + 3, hip_x - 8, oy - 2)
    elif arms == "push":
        arm(c, hip_x + 4, oy + 3, hip_x + 12, oy + 5)
    leg(c, hip_x, hip_y, *front)
    shoe(c, front[0], front[1] + 3, front_rot)
    return c


def running(phase):
    """Legs blur into the classic figure-of-eight."""
    c = Canvas(FRAME_W, FRAME_H)
    ox, oy = ORIGIN
    cy = oy + 13
    c.ring(ox, cy, 7.5, 4.5, MSKIN, a0=0, a1=360)
    c.ring(ox, cy, 7.5, 5.5, MSKIN_D, a0=40 + phase * 90, a1=200 + phase * 90)
    torso(c, ox - 1, oy + 5)
    head(c, ox + 2, oy - 11, "open", squint=0.45)
    c.capsule(ox + 1, oy + 2, ox - 6 + (phase % 2) * 3, oy + 4, 2.0, MSKIN_D)
    for i in range(2):
        sx, sy = rot(ox + 7.5, cy, ox, cy, phase * 90 + i * 180)
        shoe(c, sx, sy, 0, flat=True)
    return c


def rolling(phase):
    """Spin-ball: quills fan out of a blue ball, shoes streak round the rim."""
    c = Canvas(FRAME_W, FRAME_H)
    ox, oy = ORIGIN
    base = phase * 90
    for i in range(6):
        a = base + i * 60
        tip = rot(ox + 15, oy, ox, oy, a)
        l = rot(ox + 8, oy - 4, ox, oy, a)
        r = rot(ox + 8, oy + 4, ox, oy, a)
        c.poly([tip, l, r], MBODY_D)
    c.disc(ox, oy, 12, MBODY)
    c.ring(ox, oy, 12, 8, MBODY_L, a0=base + 200, a1=base + 320)
    for i in range(2):
        a = base * 2 + i * 180
        sx, sy = rot(ox + 8, oy, ox, oy, a)
        c.disc(sx, sy, 3.4, RED)
        c.disc(*rot(ox + 4, oy, ox, oy, a), 2.4, MSKIN)
    c.disc(ox - 2, oy - 3, 2, WHITE)  # glint
    return c


def crouching():
    """Duck / spindash charge: same footprint, head tucked down."""
    c = Canvas(FRAME_W, FRAME_H)
    ox, oy = ORIGIN
    shoe(c, ox - 6, oy + 19, 0)
    shoe(c, ox + 5, oy + 19, 0)
    c.ellipse(ox, oy + 13, 9, 5.5, MBODY)
    c.ellipse(ox + 4, oy + 14, 4.5, 3, MSKIN)
    head(c, ox + 3, oy + 4, "shut", face=(0.0, 1.0))
    arm(c, ox + 4, oy + 12, ox + 9, oy + 16)
    return c


def looking_up():
    c = Canvas(FRAME_W, FRAME_H)
    ox, oy = ORIGIN
    leg(c, ox - 1, oy + 11, ox - 5, oy + 16)
    shoe(c, ox - 5, oy + 19, 0)
    torso(c, ox - 1, oy + 6)
    head(c, ox, oy - 11, "open", face=(-4.0, -4.5))
    arm(c, ox + 3, oy + 4, ox + 8, oy + 8)
    leg(c, ox - 1, oy + 11, ox + 4, oy + 16)
    shoe(c, ox + 4, oy + 19, 0)
    return c


def skidding():
    """Braking: torso leans back, front foot planted forward."""
    c = Canvas(FRAME_W, FRAME_H)
    ox, oy = ORIGIN
    leg(c, ox - 3, oy + 11, ox - 8, oy + 16)
    shoe(c, ox - 8, oy + 19, -14)
    torso(c, ox - 3, oy + 6)
    head(c, ox - 4, oy - 10, "shut")
    arm(c, ox - 1, oy + 3, ox + 8, oy - 1)
    leg(c, ox - 3, oy + 12, ox + 7, oy + 15)
    shoe(c, ox + 7, oy + 18, 16)
    return c


def hurt(dead=False):
    """Knocked back: arms and legs thrown outward."""
    c = Canvas(FRAME_W, FRAME_H)
    ox, oy = ORIGIN
    leg(c, ox - 1, oy + 10, ox - 8, oy + 15)
    shoe(c, ox - 8, oy + 17, -32)
    leg(c, ox - 1, oy + 10, ox + 8, oy + 16)
    shoe(c, ox + 8, oy + 18, 32)
    torso(c, ox, oy + 5)
    head(c, ox, oy - 10, "dead" if dead else "shut")
    arm(c, ox + 2, oy + 1, ox + 8, oy - 6)
    arm(c, ox - 2, oy + 1, ox - 9, oy - 5)
    return c


def springing():
    """Stretched vertical pose used while a spring is launching the player."""
    c = Canvas(FRAME_W, FRAME_H)
    ox, oy = ORIGIN
    leg(c, ox, oy + 12, ox - 2, oy + 17)
    shoe(c, ox - 3, oy + 19, 0)
    leg(c, ox, oy + 12, ox + 3, oy + 17)
    shoe(c, ox + 4, oy + 19, 0)
    c.ellipse(ox, oy + 6, 6, 9, MBODY)
    c.ellipse(ox + 3, oy + 6, 3, 5, MSKIN)
    head(c, ox, oy - 8, "shut")
    arm(c, ox + 3, oy + 1, ox + 6, oy - 6)
    arm(c, ox - 3, oy + 1, ox - 7, oy - 5)
    return c


def flying(phase):
    """Hovering with a spinning rotor above the head."""
    c = Canvas(FRAME_W, FRAME_H)
    ox, oy = ORIGIN
    span = 15 if phase % 2 == 0 else 7
    c.ellipse(ox, oy - 20, span, 2.0, MSKIN_D)
    c.ellipse(ox, oy - 20, span * 0.5, 1.4, MSKIN)
    leg(c, ox - 1, oy + 11, ox - 4, oy + 16)
    shoe(c, ox - 4, oy + 18, 0)
    leg(c, ox - 1, oy + 11, ox + 5, oy + 16)
    shoe(c, ox + 5, oy + 18, 0)
    torso(c, ox - 1, oy + 6)
    head(c, ox + 1, oy - 9, "open", squint=0.2)
    arm(c, ox + 3, oy + 3, ox + 9, oy + 1)
    arm(c, ox - 3, oy + 3, ox - 9, oy + 2)
    return c


def gliding():
    """Arms spread wide, body pitched forward into the dive."""
    c = Canvas(FRAME_W, FRAME_H)
    ox, oy = ORIGIN
    leg(c, ox - 2, oy + 8, ox - 9, oy + 13)
    shoe(c, ox - 10, oy + 14, -24)
    leg(c, ox - 2, oy + 8, ox + 4, oy + 14)
    shoe(c, ox + 5, oy + 15, 18)
    c.ellipse(ox - 1, oy + 3, 9.0, 6.5, MBODY)
    c.ring(ox - 1, oy + 3, 9.0, 7.0, MBODY_D, a0=20, a1=160)
    c.ellipse(ox + 3, oy + 4, 4.5, 3.5, MSKIN)
    head(c, ox + 2, oy - 9, "open", squint=0.5)
    # outstretched arms read as the glide silhouette
    c.capsule(ox + 2, oy, ox + 15, oy - 4, 2.2, MSKIN_D)
    c.disc(ox + 15, oy - 4, 2.6, WHITE)
    c.capsule(ox - 3, oy + 1, ox - 15, oy - 3, 2.2, MSKIN_D)
    c.disc(ox - 15, oy - 3, 2.6, WHITE)
    return c


def climbing(phase):
    """Clinging to a wall on the right, one hand higher than the other."""
    c = Canvas(FRAME_W, FRAME_H)
    ox, oy = ORIGIN
    lift = 3 if phase % 2 == 0 else -3
    leg(c, ox - 1, oy + 11, ox + 4, oy + 15 - lift)
    shoe(c, ox + 5, oy + 17 - lift, 8)
    leg(c, ox - 1, oy + 11, ox + 3, oy + 17 + lift)
    shoe(c, ox + 4, oy + 19 + lift, 8)
    torso(c, ox - 2, oy + 6)
    head(c, ox, oy - 9, "open", squint=0.3)
    arm(c, ox + 2, oy + 1, ox + 8, oy - 8 + lift)
    arm(c, ox + 1, oy + 3, ox + 7, oy + 2 - lift)
    return c


def hammering(phase):
    """Mallet swing: overhead on the first frame, down and forward on the second."""
    c = Canvas(FRAME_W, FRAME_H)
    ox, oy = ORIGIN
    leg(c, ox - 1, oy + 11, ox - 5, oy + 16)
    shoe(c, ox - 5, oy + 18, 0)
    leg(c, ox - 1, oy + 11, ox + 4, oy + 16)
    shoe(c, ox + 4, oy + 18, 0)
    torso(c, ox - 1, oy + 6)
    head(c, ox + 1, oy - 9, "open", squint=0.4)
    if phase == 0:
        handle_end = (ox + 6, oy - 18)
        head_pos = (ox + 8, oy - 21)
    else:
        handle_end = (ox + 16, oy + 2)
        head_pos = (ox + 18, oy + 5)
    c.capsule(ox + 3, oy + 2, handle_end[0], handle_end[1], 1.6, MSKIN_D)
    c.ellipse(head_pos[0], head_pos[1], 6.0, 5.0, STEEL)
    c.ring(head_pos[0], head_pos[1], 6.0, 4.0, STEEL_D, a0=0, a1=360)
    c.disc(head_pos[0] - 2, head_pos[1] - 2, 1.4, WHITE)
    arm(c, ox + 2, oy + 2, ox + 5, oy + 1)
    return c


def build_player_sheet(slug):
    """One character's sheet: 11 columns, frame indices as used by player.gd."""
    use_palette(slug)
    frames = [standing()]                                     # 0 idle
    frames += [standing(walk=i / 4.0) for i in range(4)]       # 1-4 walk
    frames += [running(i) for i in range(4)]                   # 5-8 run
    frames += [rolling(i) for i in range(4)]                   # 9-12 roll
    frames += [skidding()]                                     # 13
    frames += [crouching()]                                    # 14
    frames += [looking_up()]                                   # 15
    frames += [standing(eyes="shut", arms="push", lean=1.0),    # 16-17 push
               standing(eyes="shut", arms="push", lean=1.6, walk=0.5)]
    frames += [hurt()]                                         # 18
    frames += [hurt(dead=True)]                                # 19
    frames += [springing()]                                    # 20
    frames += [standing(eyes="shut", arms="up")]                # 21 balance/idle alt
    frames += [flying(0), flying(1)]                            # 22-23 fly
    frames += [gliding()]                                       # 24 glide
    frames += [climbing(0), climbing(1)]                        # 25-26 climb
    frames += [hammering(0), hammering(1)]                      # 27-28 hammer
    for f in frames:
        f.outline(INK)
    return sheet(frames, columns=11)


# --------------------------------------------------------------------------- #
# objects
# --------------------------------------------------------------------------- #
def build_rings():
    frames = []
    for i in range(4):
        c = Canvas(16, 16)
        squash = [1.0, 0.62, 0.3, 0.62][i]
        rx = 6 * squash
        c.ellipse(8, 8, rx + 1, 7, GOLD_D)
        c.ellipse(8, 8, rx, 6, GOLD)
        if squash > 0.5:
            c.ellipse(8, 8, rx - 2.2, 3.4, (0, 0, 0, 0))
        c.ellipse(8 - rx * 0.35, 6, max(1.0, rx * 0.35), 2, GOLD_L)
        frames.append(c)
    return sheet(frames)


def build_shot():
    """Buzzer projectile."""
    frames = []
    for i in range(2):
        c = Canvas(8, 12)
        c.poly([(4, 0), (7, 8), (1, 8)], STEEL_D if i == 0 else STEEL)
        c.disc(4, 8, 3, STEEL)
        c.disc(3, 7, 1, WHITE)
        c.outline(INK)
        frames.append(c)
    return sheet(frames)


def build_ring_sparkle():
    frames = []
    for i in range(4):
        c = Canvas(16, 16)
        r = 2 + i * 2.5
        for a in range(0, 360, 45):
            x, y = rot(8 + r, 8, 8, 8, a)
            c.disc(x, y, max(0.8, 2.5 - i * 0.5), GOLD_L if i < 2 else GOLD)
        if i < 2:
            c.disc(8, 8, 3 - i, WHITE)
        frames.append(c)
    return sheet(frames)


def build_spring():
    frames = []
    for extended in (False, True):
        c = Canvas(32, 32)
        top = 12 if not extended else 2
        for y in range(top + 6, 30, 3):  # coil
            c.rect(8, y, 23, y + 1, STEEL)
            c.rect(8, y + 1, 23, y + 2, STEEL_D)
        c.rect(4, top, 27, top + 5, RED)
        c.rect(4, top + 4, 27, top + 5, RED_D)
        c.rect(8, top + 1, 23, top + 2, (255, 120, 110))
        c.rect(2, 28, 29, 31, STEEL_D)
        c.outline(INK)
        frames.append(c)
    return sheet(frames)


def build_monitor():
    icons = ["ring", "shoes", "shield", "life", "broken"]
    frames = []
    for kind in icons:
        c = Canvas(32, 32)
        if kind == "broken":
            c.rect(4, 22, 27, 29, STEEL_D)
            c.poly([(4, 22), (10, 14), (16, 22)], STEEL)
            c.poly([(16, 22), (22, 12), (28, 22)], STEEL)
            c.outline(INK)
            frames.append(c)
            continue
        c.rect(2, 2, 29, 27, STEEL_D)
        c.rect(4, 4, 27, 23, (44, 52, 92))
        c.rect(10, 27, 21, 31, STEEL_D)
        if kind == "ring":
            c.ellipse(16, 13, 6, 7, GOLD)
            c.ellipse(16, 13, 3.2, 4, (44, 52, 92))
        elif kind == "shoes":
            shoe(c, 16, 14, 0, flat=True, colour=RED)
            c.rect(9, 17, 23, 18, WHITE)
        elif kind == "shield":
            c.poly([(16, 5), (25, 10), (16, 22), (7, 10)], (90, 190, 255))
            c.poly([(16, 9), (21, 12), (16, 18), (11, 12)], WHITE)
        elif kind == "life":
            c.disc(16, 12, 6, MBODY)
            c.disc(19, 14, 3, MSKIN)
            c.disc(20, 11, 1.2, EYE)
        c.rect(4, 4, 27, 5, (120, 140, 200))
        c.outline(INK)
        frames.append(c)
    return sheet(frames)


def build_spikes():
    c = Canvas(32, 16)
    c.rect(0, 11, 31, 15, STEEL_D)
    for i in range(4):
        x = i * 8 + 4
        c.poly([(x - 4, 12), (x, 0), (x + 4, 12)], STEEL)
        c.poly([(x, 0), (x + 4, 12), (x + 1, 12)], STEEL_D)
    c.outline(INK)
    return c.a


def build_motobug():
    frames = []
    for i in range(2):
        c = Canvas(32, 24)
        c.ellipse(15, 12, 11, 8, (196, 44, 60))
        c.ellipse(15, 10, 9, 5, (240, 90, 100))
        c.disc(24, 11, 4, STEEL)  # head
        c.disc(26, 10, 1.6, (255, 240, 90))  # eye
        c.rect(4, 6, 12, 8, STEEL_D)  # exhaust
        for wx in (9, 21):
            c.disc(wx, 19, 4, INK)
            c.disc(wx, 19, 2, STEEL if i == 0 else STEEL_D)
        c.outline(INK)
        frames.append(c)
    return sheet(frames)


def build_buzzer():
    frames = []
    for i in range(2):
        c = Canvas(40, 24)
        c.ellipse(20, 13, 10, 6, (250, 208, 48))
        c.rect(14, 9, 24, 17, (40, 44, 70))
        c.disc(29, 12, 5, (250, 208, 48))
        c.disc(31, 11, 1.6, (255, 60, 60))
        c.poly([(8, 13), (2, 9), (4, 17)], STEEL_D)  # stinger
        wing_y = 5 if i == 0 else 8
        c.ellipse(18, wing_y, 9, 2.5, (200, 230, 255, 200))
        c.ellipse(24, wing_y + 1, 7, 2, (200, 230, 255, 160))
        c.outline(INK)
        frames.append(c)
    return sheet(frames)


def build_explosion():
    frames = []
    for i in range(4):
        c = Canvas(32, 32)
        r = 4 + i * 5
        for a in range(0, 360, 45):
            x, y = rot(16 + r * 0.7, 16, 16, 16, a + i * 12)
            c.disc(x, y, max(1.5, 7 - i * 1.4), (255, 236, 150) if i < 2 else (255, 170, 60))
        c.disc(16, 16, max(1, 9 - i * 2.5), WHITE)
        frames.append(c)
    return sheet(frames)


def build_dust():
    frames = []
    for i in range(4):
        c = Canvas(24, 24)
        alpha = 255 - i * 55
        for j in range(3):
            x = 6 + j * 5 + i * 1.5
            y = 16 - j * 2 - i
            c.disc(x, y, max(1.0, 5 - i * 1.1 - j * 0.5), (*mix(WHITE, DIRT_L, 0.35), alpha))
        frames.append(c)
    return sheet(frames)


def build_checkpoint():
    frames = []
    for lit in (False, True):
        c = Canvas(24, 48)
        c.rect(10, 8, 13, 46, STEEL_D)
        c.rect(11, 8, 12, 46, STEEL)
        c.disc(12, 6, 5, (220, 60, 60) if not lit else (80, 210, 120))
        if lit:
            c.rect(13, 10, 22, 18, (240, 240, 120))
            c.rect(13, 10, 22, 11, WHITE)
        c.rect(6, 44, 17, 47, DIRT_D)
        c.outline(INK)
        frames.append(c)
    return sheet(frames)


def build_goal():
    frames = []
    for i in range(4):
        c = Canvas(48, 64)
        c.rect(22, 10, 25, 62, STEEL_D)
        c.rect(23, 10, 24, 62, STEEL)
        w = [18, 11, 3, 11][i]
        c.ellipse(24, 24, w, 15, (240, 240, 250) if i != 2 else STEEL_D)
        if w > 8:
            c.ellipse(24, 24, w - 2, 13, (60, 120, 220))
            c.disc(24, 20, min(w - 4, 6), MBODY)
            c.disc(26, 22, 3, MSKIN)
            c.disc(27, 20, 1.2, EYE)
            c.rect(24 - w + 3, 30, 24 + w - 3, 33, WHITE)
        c.rect(14, 60, 33, 63, DIRT_D)
        c.outline(INK)
        frames.append(c)
    return sheet(frames)


def build_platform():
    c = Canvas(64, 20)
    c.rect(0, 0, 63, 5, GRASS)
    c.rect(0, 4, 63, 6, GRASS_D)
    c.rect(0, 6, 63, 17, DIRT)
    for x in range(0, 64, 16):
        c.rect(x, 8, x + 7, 15, DIRT_D)
    c.rect(0, 17, 63, 19, DIRT_D)
    c.outline(INK)
    return c.a


# --------------------------------------------------------------------------- #
# terrain textures
# --------------------------------------------------------------------------- #
def build_ground_strip():
    """Repeating top-of-terrain strip: grass lip over checkered dirt."""
    c = Canvas(64, 48)
    c.rect(0, 0, 63, 5, GRASS)
    c.rect(0, 0, 63, 1, GRASS_L)
    c.rect(0, 5, 63, 8, GRASS_D)
    for x in range(0, 64, 8):  # grass fringe
        c.poly([(x, 8), (x + 4, 13), (x + 8, 8)], GRASS_D)
    c.rect(0, 9, 63, 47, DIRT)
    for gy in range(0, 3):
        for gx in range(0, 4):
            if (gx + gy) % 2 == 0:
                y0 = 12 + gy * 12
                c.rect(gx * 16, y0, gx * 16 + 15, y0 + 11, DIRT_D)
    for i in range(0, 64, 4):  # speckle
        c.px(i + (i // 4 % 3), 20 + (i % 9), DIRT_L)
    return c.a


def build_dirt_fill():
    c = Canvas(32, 32)
    c.rect(0, 0, 31, 31, DIRT_D)
    for gy in range(2):
        for gx in range(2):
            if (gx + gy) % 2 == 0:
                c.rect(gx * 16, gy * 16, gx * 16 + 15, gy * 16 + 15, mix(DIRT, DIRT_D, 0.5))
    for i in range(0, 32, 5):
        c.px(i, (i * 7) % 32, DIRT)
    return c.a


def build_loop_track():
    """Repeating tile for the loop's annulus fill."""
    c = Canvas(16, 16)
    c.rect(0, 0, 15, 15, mix(DIRT, (90, 90, 110), 0.35))
    c.rect(0, 0, 15, 2, GRASS_D)
    c.rect(0, 13, 15, 15, shift(DIRT_D, -14))
    for i in range(0, 16, 4):
        c.rect(i, 5, i + 1, 10, DIRT_L)
    return c.a


# --------------------------------------------------------------------------- #
# background layers (Kenney art, downscaled 4x)
# --------------------------------------------------------------------------- #
def build_sky(width=512, height=256):
    c = Canvas(width, height)
    for y in range(height):
        t = (y / (height - 1)) ** 0.85
        colour = mix(SKY_TOP, SKY_BOT, t)
        c.rect(0, y, width - 1, y, colour)
    return c.a


def build_clouds(width=512, height=96):
    c = Canvas(width, height)
    clouds = [pngio.box_downscale(pngio.read(os.path.join(KENNEY, f"cloud{i}.png")), 4)
              for i in (1, 2, 3)]
    spots = [(6, 30, 0), (120, 12, 1), (232, 40, 2), (330, 18, 0), (430, 34, 1)]
    for x, y, idx in spots:
        c.blit(clouds[idx], x, y)
    return c.a


def build_hills(width=512, height=160, near=True):
    c = Canvas(width, height)
    base = height - 1
    green = mix(GRASS, SKY_BOT, 0.15 if near else 0.42)
    green_d = mix(GRASS_D, SKY_BOT, 0.1 if near else 0.38)
    amp = 46 if near else 30
    period = 190 if near else 130
    for x in range(width):
        h = amp * (0.55 + 0.45 * math.sin(x / period * math.tau)) \
            + amp * 0.25 * math.sin(x / (period * 0.37) * math.tau + 1.1)
        top = int(base - h)
        c.rect(x, top, x, base, green)
        c.rect(x, top, x, top + 2, mix(green, WHITE, 0.18))
        c.rect(x, top + 3, x, top + 5, green_d)
    if near:
        bush = pngio.box_downscale(pngio.read(os.path.join(KENNEY, "bush.png")), 4)
        for x in range(20, width - 20, 96):
            col = c.a[:, x, 3]
            solid = np.nonzero(col > 0)[0]
            if len(solid):
                c.blit(bush, x, int(solid[0]) - bush.shape[0] + 3)
    return c.a


def build_bush():
    return pngio.box_downscale(pngio.read(os.path.join(KENNEY, "bush.png")), 3)


# --------------------------------------------------------------------------- #
def main():
    sprites = os.path.join(ROOT, "assets", "sprites")
    tiles = os.path.join(ROOT, "assets", "tiles")
    bg = os.path.join(ROOT, "assets", "bg")
    for d in (sprites, tiles, bg):
        os.makedirs(d, exist_ok=True)

    print("palette sampled from Kenney CC0 tiles:")
    for k, v in PAL.items():
        print(f"  {k:12s} {v}")

    outputs = {}
    for slug in CHARACTERS:
        outputs[os.path.join(sprites, "player_%s.png" % slug)] = build_player_sheet(slug)
    use_palette("dash")  # object art should not depend on who was generated last
    outputs |= {
        os.path.join(sprites, "ring.png"): build_rings(),
        os.path.join(sprites, "ring_sparkle.png"): build_ring_sparkle(),
        os.path.join(sprites, "shot.png"): build_shot(),
        os.path.join(sprites, "spring.png"): build_spring(),
        os.path.join(sprites, "monitor.png"): build_monitor(),
        os.path.join(sprites, "spikes.png"): build_spikes(),
        os.path.join(sprites, "motobug.png"): build_motobug(),
        os.path.join(sprites, "buzzer.png"): build_buzzer(),
        os.path.join(sprites, "explosion.png"): build_explosion(),
        os.path.join(sprites, "dust.png"): build_dust(),
        os.path.join(sprites, "checkpoint.png"): build_checkpoint(),
        os.path.join(sprites, "goal.png"): build_goal(),
        os.path.join(sprites, "platform.png"): build_platform(),
        os.path.join(tiles, "ground_strip.png"): build_ground_strip(),
        os.path.join(tiles, "dirt_fill.png"): build_dirt_fill(),
        os.path.join(tiles, "loop_track.png"): build_loop_track(),
        os.path.join(bg, "sky.png"): build_sky(),
        os.path.join(bg, "clouds.png"): build_clouds(),
        os.path.join(bg, "hills_far.png"): build_hills(near=False),
        os.path.join(bg, "hills_near.png"): build_hills(near=True),
        os.path.join(bg, "bush.png"): build_bush(),
    }
    for path, arr in outputs.items():
        pngio.write(path, arr)
        h, w = arr.shape[:2]
        print(f"  wrote {os.path.relpath(path, ROOT)} ({w}x{h})")


if __name__ == "__main__":
    main()
