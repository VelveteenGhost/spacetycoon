"""Turn bake_sky.py's cube faces into Roblox skybox faces.

Orientation: the bake names its faces by world direction (Ft -Z, Bk +Z, Lf -X, Rt +X; Up with image-up -Z, Dn with
image-up +Z). Roblox shows SkyboxLf at +X and SkyboxRt at -X, turns Up 90 degrees anticlockwise and Dn 90 degrees
clockwise (checked in Studio with the debug set, Nov 9), so this swaps and pre-turns them.

Colour: Roblox multiplies the skybox by a tint that follows the sun. With the sun high it's a flat 1.095; at sunrise
it darkens about 4x and turns olive overhead and purple at the horizon; at blue hour it darkens about 40x and all
but removes blue. It depends only on the view's elevation (measured toward and across the sun, Nov 9). Roblox then
applies the scene's exposure, which the bake already contains. So each texel is scaled by K / (tint(el) * 2^E),
leaving the sky on screen at K times the bake. K is set per sun by matching the reference frames on the mount shot
(Nov 9): 0.6 at sunrise, 0.85 in the morning, 1.3 at blue hour (with the Atmosphere off, see Look). The faces are
stored darker than the bake, so a triangular dither of one 8-bit step keeps dark gradients from banding; it's
per texel, so it doesn't seam.

Usage: python -I tools/sky_faces.py art/sky/<look>_<weather> [...]   -> writes <dir>/roblox/{Ft,Bk,Lf,Rt,Up,Dn}.png
art/sky/debug is only reoriented. The roblox/ folders are build output (git-ignored); the dither is seeded per face,
so reruns match each other. The faces uploaded on Nov 9 predate that seed (sunrise and morning have no dither), so a
rerun differs from them by dither noise only.
"""
import math, os, sys, zlib
import numpy as np
from PIL import Image

# Roblox face <- (bake face, clockwise turn in degrees)
MAP = {'Ft': ('Ft', 0), 'Bk': ('Bk', 0), 'Lf': ('Rt', 0), 'Rt': ('Lf', 0), 'Up': ('Up', 90), 'Dn': ('Dn', -90)}
K = {'sunrise': 0.6, 'morning': 0.85, 'blue': 1.3}

# Roblox's sky tint (linear RGB) by view elevation, read off a uniform-grey skybox at each preset's ClockTime
TINT_EL = [-10, 0, 10, 20, 30, 40, 50, 60]
TINT = {
    'sunrise': [(.301, .226, .282), (.306, .231, .267), (.307, .236, .236), (.307, .242, .220),
                (.304, .250, .193), (.304, .256, .171), (.306, .269, .158), (.307, .270, .158)],
    'morning': [(1.095, 1.095, 1.095)] * 8,
    # At -4 degrees Roblox's tint is about 40x darker and all but blue-free (R .041-.063, G .022, B .004-.030), past
    # what a texture can make up. The sun casts no light then anyway, so Look parks Roblox's sun at the morning
    # angle for blue hour, where the tint is neutral.
    'blue': [(1.095, 1.095, 1.095)] * 8,
}
ELEV = {'blue': -4, 'sunrise': 3, 'morning': 12}
WX_SUN = {'clear': 1, 'broken': 0.92, 'marine': 0.55}
EXPOSURE_BIAS = 1


def smooth(a, b, x):
    t = min(1, max(0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def exposure(e, wx):
    """Look.setExposure with no engine dip, in stops."""
    base = lerp(lerp(1.15, 0.7, smooth(-6, 3, e)), 0.48, smooth(3, 18, e)) * (1 + (1 - WX_SUN[wx]) * 0.7)
    return EXPOSURE_BIAS + math.log2(base / 0.7)


def to_lin(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def to_srgb(a):
    a = np.clip(a, 0, 1)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)


def elevation(face, n):
    """View elevation in degrees of each texel of a Roblox face (unchanged by the face's turn about the view axis)."""
    s = (np.arange(n) + 0.5) / n * 2 - 1
    sx, sy = np.meshgrid(s, -s)  # sy: +1 at the top row
    if face == 'Up':
        return np.degrees(np.arctan2(1, np.hypot(sx, sy)))
    if face == 'Dn':
        return -np.degrees(np.arctan2(1, np.hypot(sx, sy)))
    return np.degrees(np.arctan2(sy, np.sqrt(1 + sx * sx)))


def gain(face, n, sun, wx):
    el = elevation(face, n)
    e2 = 2 ** exposure(ELEV[sun], wx)
    tint = np.stack([np.interp(el, TINT_EL, [t[c] for t in TINT[sun]]) for c in range(3)], axis=-1)
    return K[sun] / (tint * e2)


for d in sys.argv[1:]:
    look = os.path.basename(os.path.normpath(d))
    sun, wx = look.split('_') if '_' in look else (None, None)
    out = os.path.join(d, 'roblox')
    os.makedirs(out, exist_ok=True)
    for face, (src, cw) in MAP.items():
        im = Image.open(os.path.join(d, src + '.png')).convert('RGB')  # the bake's alpha is all opaque
        if cw:
            im = im.rotate(-cw, expand=False)  # PIL turns anticlockwise for positive angles
        if sun:
            a = to_lin(np.asarray(im, dtype=np.float64) / 255)
            a = a * gain(face, im.size[0], sun, wx)
            rng = np.random.default_rng(zlib.crc32(f'{look}/{face}'.encode()))
            dither = rng.random(a.shape) - rng.random(a.shape)
            im = Image.fromarray(np.clip(np.round(to_srgb(a) * 255 + dither), 0, 255).astype(np.uint8))
        im.save(os.path.join(out, face + '.png'), optimize=True)
    if sun:
        g = gain('Ft', 64, sun, wx)
        print(f"{out}: E {exposure(ELEV[sun], wx):+.2f} stops; gain at horizon {np.round(g[31, 32], 2)}, "
              f"overhead {np.round(gain('Up', 64, sun, wx)[32, 32], 2)}")
    else:
        print(out)
