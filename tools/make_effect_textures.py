#!/usr/bin/env python3
"""Particle and beam textures for the Roblox port of the three.js launch-pad scene.

Ports the scene's canvas recipes (puffTex, billowTex2, litBillow, plumeTex, foamTex, glowTex, the flame glows and the
ice-shard outlines) to numpy, then adapts them for Roblox:

  * Particle textures are tinted by ParticleEmitter.Color, so they are white or grayscale with straight
    (non-premultiplied) alpha. The lit billows keep their baked top-lit shading in RGB.
  * White masks keep RGB = 255 everywhere, so filtering can never shift their colour. Shaded textures put a
    neutral grey (0.62 * 255, as litBillow does) in fully transparent texels, never black.
  * Beam textures run along the beam on the image's X axis (U) and across it on Y (V).
  * Power-of-two sizes, at most 512 px, 8-bit RGBA PNG.

Usage:
    python tools/make_effect_textures.py --out art/effects [--seed 1977]

Needs Pillow and numpy. The output is deterministic for a given seed; each texture draws from its own
random stream, so changing one recipe does not reshuffle the others.
"""
import argparse
import math
import os

import numpy as np
from PIL import Image, ImageDraw

NEUTRAL = round(.62 * 255)          # 158: what litBillow writes into transparent texels
TAU = math.tau
# The scene's particle shader never shows litBillow's red channel directly: it mixes from shadowCol (sky ambient
# * .58) to the sunlit colour by that value, so a billow's underside is grey-blue, never black. Roblox only
# multiplies the texture by Color, so that mix is baked in: stored = sRGB(BILLOW_SHADOW + (1 - BILLOW_SHADOW) * v),
# in linear light. .22 is about the shadow/sun ratio the scene reaches in daylight.
BILLOW_SHADOW = .22


# ---------------------------------------------------------------- helpers

def smoothstep(e0, e1, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def grid(w, h):
    """Pixel-centre coordinates, canvas style (y runs down)."""
    return np.meshgrid(np.arange(w) + .5, np.arange(h) + .5)


def interp_stops(t, stops):
    """Canvas gradient: piecewise-linear stops [(pos, value)], padded at both ends."""
    pos = [s[0] for s in stops]
    val = [s[1] for s in stops]
    return np.interp(t, pos, val)


def conic_t(X, Y, x0, y0, r0, x1, y1, r1):
    """Gradient parameter of canvas createRadialGradient(x0,y0,r0, x1,y1,r1): the largest t whose circle
    passes through the point. t < 0 inside the start circle (padded to the first stop)."""
    dcx, dcy, dr = x1 - x0, y1 - y0, r1 - r0
    px, py = X - x0, Y - y0
    a = dcx * dcx + dcy * dcy - dr * dr
    b = px * dcx + py * dcy + r0 * dr
    c = px * px + py * py - r0 * r0
    if abs(a) < 1e-9:
        return c / (2 * b + 1e-12)
    d = np.sqrt(np.maximum(b * b - a * c, 0))
    t1, t2 = (b + d) / a, (b - d) / a
    t = np.maximum(t1, t2)
    return np.where(r0 + t * dr >= 0, t, np.minimum(t1, t2))


def blur(a, sigma, wrap=False):
    """Gaussian blur via FFT. wrap=True keeps a tileable image tileable; otherwise the outside is zero."""
    if sigma <= 0:
        return a
    pad = 0 if wrap else int(3 * sigma) + 2
    if pad:
        a = np.pad(a, pad)
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2 * math.pi ** 2 * sigma ** 2 * (fx * fx + fy * fy))
    out = np.real(np.fft.ifft2(np.fft.fft2(a) * g))
    return out[pad:-pad, pad:-pad] if pad else out


def periodic_noise(rng, h, w, beta=3.0, sx=1.0, sy=1.0, kmin=0.0):
    """Tileable fractal noise (spectral synthesis), normalised to roughly [0, 1].
    sx < 1 stretches features along X, sy < 1 along Y."""
    F = np.fft.fft2(rng.standard_normal((h, w)))
    kx = np.fft.fftfreq(w)[None, :] * sx
    ky = np.fft.fftfreq(h)[:, None] * sy
    k = np.sqrt(kx * kx + ky * ky)
    k[0, 0] = np.inf
    amp = np.where(k > kmin, k ** (-beta / 2), 0)
    n = np.real(np.fft.ifft2(F * amp))
    lo, hi = np.percentile(n, 1), np.percentile(n, 99)
    return np.clip((n - lo) / (hi - lo), 0, 1)


def periodic_noise_1d(rng, n, harmonics=10, falloff=1.3):
    """Smooth loop of n samples in [-1, 1] built from a few low harmonics."""
    x = np.arange(n) / n
    out = np.zeros(n)
    for k in range(1, harmonics + 1):
        out += k ** -falloff * np.sin(TAU * k * x + rng.uniform(0, TAU))
    return out / np.abs(out).max()


def cover1d(a0, a1, n, wrap=False):
    """How much of each pixel [i, i+1) the interval [a0, a1) covers (canvas-style antialiased rect edges)."""
    i = np.arange(n)
    c = np.zeros(n)
    for s in ((-n, 0, n) if wrap else (0,)):
        c += np.clip(np.minimum(a1 + s, i + 1) - np.maximum(a0 + s, i), 0, 1)
    return np.clip(c, 0, 1)


def edge_window(w, h, margin):
    """1 inside, easing to 0 at the image border, so non-tiling sprites never clip."""
    X, Y = grid(w, h)
    d = np.minimum(np.minimum(X, w - X), np.minimum(Y, h - Y))
    return smoothstep(0, margin, d)


def srgb_encode(x):
    x = np.clip(x, 0, 1)
    return np.where(x <= .0031308, x * 12.92, 1.055 * x ** (1 / 2.4) - .055)


def bake_shadow_floor(v):
    """litBillow's light-facing term -> stored grey, with the scene's shadow-to-sun mix baked in."""
    return srgb_encode(BILLOW_SHADOW + (1 - BILLOW_SHADOW) * v)


def downsample(a, f):
    h, w = a.shape[:2]
    return a.reshape(h // f, f, w // f, f, *a.shape[2:]).mean(axis=(1, 3))


def save(path, rgb, alpha, empty_rgb=None):
    """rgb: float 0..1, (H,W) grey or (H,W,3). alpha: float 0..1. Straight alpha.
    empty_rgb: colour written into texels whose 8-bit alpha is 0."""
    a8 = np.clip(np.round(alpha * 255), 0, 255).astype(np.uint8)
    rgb = np.asarray(rgb, dtype=np.float64)
    if rgb.ndim == 0:
        rgb = np.full(alpha.shape, float(rgb))
    if rgb.ndim == 2:
        rgb = np.repeat(rgb[..., None], 3, axis=2)
    c8 = np.clip(np.round(rgb * 255), 0, 255).astype(np.uint8)
    if empty_rgb is not None:
        c8[a8 == 0] = empty_rgb
    Image.fromarray(np.dstack([c8, a8])).save(path, optimize=True)
    return path


# ---------------------------------------------------------------- recipes

def lit_billow(rng, n_lumps, flat, N=256, ss=2):
    """litBillow(nLumps, flat): a union of hemispheres as a height field, shaded per pixel with light from the
    top of the image. Built at ss x resolution and box-filtered (premultiplied) so the firm edges are antialiased."""
    M = N * ss
    hgt = np.zeros((M, M))
    for _ in range(n_lumps):
        a = rng.random() * 6.283
        rr = rng.random() ** .7 * M * .25
        r = M * (.075 + rng.random() * .1) * (1.15 - rr / (M * .36))
        cx, cy = M / 2 + math.cos(a) * rr, M / 2 + math.sin(a) * rr * flat - M * .03
        x0, x1 = max(0, int(cx - r)), min(M - 1, int(math.ceil(cx + r)))
        y0, y1 = max(0, int(cy - r)), min(M - 1, int(math.ceil(cy + r)))
        X, Y = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        d2 = ((X - cx) ** 2 + (Y - cy) ** 2) / (r * r)
        hh = np.where(d2 < 1, r * np.sqrt(np.maximum(0, 1 - d2)), 0)
        sub = hgt[y0:y1 + 1, x0:x1 + 1]
        np.maximum(sub, hh, out=sub)                                   # union of spheres

    L = np.array([0, .9, .44]); L /= np.linalg.norm(L)                # from the top, a little toward the viewer
    xp = np.concatenate([hgt[:, 1:], hgt[:, -1:]], axis=1)
    xm = np.concatenate([hgt[:, :1], hgt[:, :-1]], axis=1)
    yp = np.concatenate([hgt[1:], hgt[-1:]], axis=0)
    ym = np.concatenate([hgt[:1], hgt[:-1]], axis=0)
    hx, hy = (xp - xm) * .5, (yp - ym) * .5
    nx, ny, nz = -hx, hy, 1.0                                         # image y runs down; +ny is the top
    nl = np.sqrt(nx * nx + ny * ny + nz * nz)
    diff = np.maximum(0, (nx * L[0] + ny * L[1] + nz * L[2]) / nl)
    wrap = (diff + .08) / 1.08
    thick = np.minimum(1, hgt / (M * .05))                            # thin rims let a little light through
    v = np.minimum(1, wrap * .92 + (1 - thick) * .12)
    a = np.where(hgt > 0, np.minimum(1, hgt / (M * .022)), 0)        # firm edge: opaque a few pixels in
    A = downsample(a, ss)
    V = downsample(v * a, ss) / np.maximum(A, 1e-9)
    return V, A


def billow_soft(rng, N=256):
    """billowTex2: many tight radial-gradient lumps, highlight offset up-left, then a dark underside laid
    source-atop. Composited premultiplied, like the canvas. Shadow made neutral grey so Color tints it."""
    X, Y = grid(N, N)
    P = np.zeros((N, N))      # premultiplied grey
    A = np.zeros((N, N))
    stops_a = [(0, .8), (.6, .5), (1, 0)]
    stops_c = [(0, 255 / 255), (.6, 236 / 255), (1, 214 / 255)]
    for _ in range(70):
        a = rng.random() * 6.283
        rr = math.sqrt(rng.random()) * N * .27
        x, y = N / 2 + math.cos(a) * rr, N / 2 + math.sin(a) * rr * .8 - N * .03
        r = N * (.05 + rng.random() * .09)
        t = np.clip(conic_t(X, Y, x - r * .3, y - r * .35, r * .05, x, y, r), 0, 1)
        sa = interp_stops(t, stops_a)
        sp = interp_stops(t, [(p, c * aa) for (p, c), (_, aa) in zip(stops_c, stops_a)])
        P = sp + P * (1 - sa)
        A = sa + A * (1 - sa)
    C = P / np.maximum(A, 1e-9)
    sh = interp_stops(Y / N, [(.25, 0), (.85, .7)])                    # linear gradient, padded
    C = sh * (106 / 255) + (1 - sh) * C                                # source-atop: alpha unchanged
    return C, A


def puff(rng, N=128):
    """puffTex: 16 overlapping soft radial gradients on a black mask. Pulled in 8% from the centre so no
    lump reaches the image border."""
    X, Y = grid(N, N)
    v = np.zeros((N, N))
    k = .92
    for _ in range(16):
        x = N / 2 + (rng.random() - .5) * N * .34 * k
        y = N / 2 + (rng.random() - .5) * N * .34 * k
        r = N * (.16 + rng.random() * .2) * k
        t = np.sqrt((X - x) ** 2 + (Y - y) ** 2) / r
        a = np.where(t <= 1, interp_stops(t, [(0, .5), (.6, .18), (1, 0)]), 0)
        v = a + v * (1 - a)
    return v


def glow(N=128):
    """glowTex: radial gradient 1 / .65 / .16 / 0 at 0 / .16 / .42 / 1."""
    X, Y = grid(N, N)
    t = np.sqrt((X - N / 2) ** 2 + (Y - N / 2) ** 2) / (N / 2)
    return interp_stops(t, [(0, 1), (.16, .65), (.42, .16), (1, 0)])


def teardrop(W, H, cx, v0, v1, halfw, ss=4):
    """Antialiased teardrop: round end at v0 (top), tapering to a point at v1. halfw is the widest half-width."""
    X, Y = grid(W * ss, H * ss)
    u, v = X / (W * ss), Y / (H * ss)
    s = (v - v0) / (v1 - v0)
    sc = np.clip(s, 0, 1)
    smax = (.5 / 1.75) ** .5 * (1.25 / 1.75) ** 1.25
    hw = halfw * np.sqrt(sc) * (1 - sc) ** 1.25 / smax
    inside = (s > 0) & (s < 1) & (np.abs(u - cx) < hw)
    return downsample(inside.astype(np.float64), ss)


def flame(rng, N=256):
    """A flame tongue for camera-facing particles: round white-hot end at the top of the image (the nozzle end),
    tapering downward. A narrow opaque core inside a wider, streaky sheath, as the scene's flameIn/flameOut glow
    chains build it. RGB is a little greyer in the sheath so the core clips to white first under Brightness."""
    X, Y = grid(N, N)
    v = Y / N
    sheath_hard = teardrop(N, N, .5, .05, .96, .2)
    mid_hard = teardrop(N, N, .5, .08, .84, .125)
    core_hard = teardrop(N, N, .5, .11, .66, .07)
    sheath = blur(sheath_hard, N * .04)
    mid = blur(mid_hard, N * .03)
    core = blur(core_hard, N * .022)
    outer = blur(sheath_hard, N * .09)
    streaks = periodic_noise(rng, N, N, beta=2.6, sx=1.0, sy=.18)        # features stretched down the tongue
    s = np.clip((v - .05) / .91, 0, 1)
    core_a = np.clip(core * 1.25, 0, 1) * (1 - .35 * smoothstep(.2, .66, v))
    mid_a = mid * (.7 + .3 * streaks) * (1 - .3 * s)
    sheath_a = sheath * (.45 + .55 * streaks) * (1 - .55 * s)
    alpha = 1 - (1 - core_a) * (1 - .75 * mid_a) * (1 - .55 * sheath_a) * (1 - .18 * outer)
    alpha *= edge_window(N, N, 10)
    grey = .72 + .28 * np.clip(core * 1.3 + mid * .25, 0, 1)
    return grey, alpha


def plume_streak(rng, W=256, H=64):
    """plumeTex turned 90 degrees for a Beam: hot at U=0 (left, the nozzle), fading to 0 at U=1, with the same
    long dark streaks thinning the mask. Across the beam (V) it eases to 0 at both edges, since a Roblox Beam is a
    flat ribbon rather than the scene's open cylinder."""
    X, Y = grid(W, H)
    along = interp_stops(X / W, [(0, 1), (.22, .78), (.65, .26), (1, 0)])
    m = np.ones((H, W))
    for _ in range(70):
        a = .12 + rng.random() * .34
        y0 = rng.random() * H
        th = 1 + rng.random() * 3
        x0 = rng.random() * W * .25
        ln = W * (.3 + rng.random() * .7)
        cov = np.outer(cover1d(y0, y0 + th, H), cover1d(x0, x0 + ln, W))
        m *= 1 - a * cov
    t = (Y - .5) / (H - 1) * 2 - 1                                    # first and last rows land on 0
    across = np.clip(1 - t * t, 0, 1) ** 1.2
    return along * m * across


def contrail(rng, W=256, H=64):
    """Smoke band for a Beam: lumpy soft top and bottom edges, mottled density, tileable along X."""
    X, Y = grid(W, H)
    xi = np.arange(W)
    yc = H / 2 + 1.8 * periodic_noise_1d(rng, W, 6)[None, :]
    top = (19 + 6.5 * periodic_noise_1d(rng, W, 12))[None, :]       # half-thickness above the centre line
    bot = (19 + 6.5 * periodic_noise_1d(rng, W, 12))[None, :]       # and below it (max 25.5 + 1.8 < 31)
    dy = Y - yc
    q = np.where(dy < 0, -dy / top, dy / bot)
    mottle = periodic_noise(rng, H, W, beta=3.2, sx=.45, sy=1.0)       # stretched along the trail
    fine = periodic_noise(rng, H, W, beta=2.2, sx=.6, sy=1.0)
    q = q * (1 + .28 * (mottle - .5) + .1 * (fine - .5))               # ragged, billowy outline
    profile = 1 - smoothstep(.3, 1.0, q)
    # a row of wrapped soft lumps so the band reads as puffs rather than a smooth tube
    lumps = np.zeros((H, W))
    for _ in range(16):
        x, y = rng.random() * W, H / 2 + (rng.random() - .5) * 18
        r = 7 + rng.random() * 9
        for s in (-W, 0, W):
            lumps = np.maximum(lumps, np.exp(-(((X - x - s) ** 2) + (Y - y) ** 2) / (2 * r * r)))
    density = profile * (.42 + .38 * mottle + .14 * fine + .22 * lumps)
    alpha = np.clip(density, 0, 1) ** 1.1 * .92
    alpha *= smoothstep(0, 2.5, np.minimum(Y, H - Y))                  # guarantee clear top and bottom rows
    grey = .86 + .1 * mottle + .04 * lumps                             # faint volume, never dark
    return np.clip(grey, 0, 1), alpha


def foam(rng, N=256):
    """foamTex: five broken crest lines of small white dashes. The scene runs them along V (parallel to the shore
    on a strip whose V runs along the coast); here they run along X so a Beam laid along the shoreline shows them
    parallel to it. Every dash wraps, so the tile is seamless in both directions."""
    one_minus = np.ones((N, N))
    for k in range(5):
        y0 = (k + .2 + rng.random() * .5) * N / 5
        gaps = smoothstep(-.45, -.05, periodic_noise_1d(rng, N, 12, .6))         # where this crest breaks (wraps in X)
        for _ in range(300):
            x = rng.random() * N
            y = y0 + math.sin(x / N * TAU * 2 + k) * 5 + (rng.random() - .5) * 9
            a = (.22 + rng.random() * .5) * gaps[int(x) % N]
            th = 1.5 + rng.random() * 4.5
            ln = 4 + rng.random() * 24
            cov = np.outer(cover1d(y, y + th, N, wrap=True), cover1d(x, x + ln, N, wrap=True))
            one_minus *= 1 - a * cov
    return 1 - one_minus


def shard_outline(rng):
    """The scene's shard polygon (5-8 points, uneven radii, an occasional deep notch, squashed in y), with extra
    jagged points on every edge so it reads as broken sheet ice."""
    n = 5 + int(rng.random() * 4)
    pts = []
    for k in range(n):
        a = (k + rng.random() * .6) / n * TAU
        r = .3 + rng.random() * .25 - (.12 if rng.random() < .25 else 0)
        pts.append((math.cos(a) * r, math.sin(a) * r * (.7 + rng.random() * .5)))
    pts = np.array(pts)
    out = []
    for i in range(n):
        p, q = pts[i], pts[(i + 1) % n]
        e = q - p
        L = np.linalg.norm(e)
        nrm = np.array([e[1], -e[0]]) / L
        out.append(p)
        m = int(rng.integers(1, 4))
        sign = 1 if rng.random() < .5 else -1
        for j, t in enumerate(sorted(rng.uniform(.12, .88, m))):
            out.append(p + e * t + nrm * L * rng.uniform(.025, .08) * sign * (1 if j % 2 == 0 else -1))
    P = np.array(out)
    P[:, 1] *= rng.uniform(1.0, 1.6)                                   # sheets are longer than wide (sy > sx)
    th = rng.uniform(0, TAU)
    c, s = math.cos(th), math.sin(th)
    return P @ np.array([[c, s], [-s, c]])


def ice_shards(rng, size=512):
    """2x2 flipbook (frames left-to-right, top-to-bottom) of flat, jagged ice sheets: pale ice-blue faces with a
    soft glint band, frost mottling, bright white broken rims and a few white fracture lines."""
    cell, ss = size // 2, 4
    C = cell * ss
    rgb = np.zeros((size, size, 3))
    alpha = np.zeros((size, size))
    blue, white = np.array([.78, .88, .96]), np.array([.97, .985, 1.0])
    X, Y = grid(cell, cell)
    for f in range(4):
        P = shard_outline(rng)
        P -= (P.max(0) + P.min(0)) / 2
        P *= (1 - 2 * .1) / (P.max(0) - P.min(0)).max()                  # 10% margin so mips never bleed frames
        pix = [tuple(p) for p in (P + .5) * C]
        m_img = Image.new('L', (C, C), 0)
        ImageDraw.Draw(m_img).polygon(pix, fill=255)
        c_img = Image.new('L', (C, C), 0)
        dr = ImageDraw.Draw(c_img)
        centre = P.mean(0)
        for _ in range(int(rng.integers(2, 5))):                          # fractures running in from the edge
            p = P[int(rng.integers(len(P)))].copy()
            reach = rng.uniform(.35, .75)
            pts = [p.copy()]
            for _ in range(int(rng.integers(3, 6))):
                step = (centre - p) * reach / 3 + rng.normal(0, .035, 2)
                p = p + step
                pts.append(p.copy())
            dr.line([tuple(q) for q in (np.array(pts) + .5) * C], fill=255, width=max(1, int(ss * 1.1)), joint='curve')
        cov = downsample(np.asarray(m_img, dtype=np.float64) / 255, ss)
        crack = downsample(np.asarray(c_img, dtype=np.float64) / 255, ss) * cov
        b = blur(cov, cell * .022)
        rim = np.clip((1 - b) * 2.2, 0, 1) * cov
        ang = rng.uniform(0, TAU)
        t = ((X / cell - .5) * math.cos(ang) + (Y / cell - .5) * math.sin(ang)) / .8 + .5
        frost = periodic_noise(rng, cell, cell, beta=2.0)
        g0 = rng.uniform(.3, .7)
        glint = np.exp(-((t - g0) / .07) ** 2) * .55
        col = blue + (white - blue) * smoothstep(0, 1, t)[..., None]
        col = col * (.95 + .08 * frost)[..., None]
        k = np.maximum.reduce([glint, rim * .9, crack])[..., None]
        col = col + (white - col) * k
        a = cov * np.clip(.72 + .14 * frost + .3 * rim + .2 * glint + .3 * crack, 0, 1)
        oy, ox = (f // 2) * cell, (f % 2) * cell
        rgb[oy:oy + cell, ox:ox + cell] = col
        alpha[oy:oy + cell, ox:ox + cell] = a
    fill = rgb[alpha > .5].mean(0)
    return np.clip(rgb, 0, 1), alpha, tuple(int(round(v * 255)) for v in fill)


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--out', default='art/effects', help='output folder (created if missing)')
    ap.add_argument('--seed', type=int, default=1977, help='random seed (default 1977, the scene\'s own)')
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    rng = lambda k: np.random.default_rng([args.seed, k])
    out = lambda name: os.path.join(args.out, name)
    written = []

    for k, (name, n, flat) in enumerate([('billow_a.png', 46, .78), ('billow_b.png', 30, .9), ('billow_c.png', 60, .7)]):
        V, A = lit_billow(rng(10 + k), n, flat)
        neutral = int(round(float(bake_shadow_floor(NEUTRAL / 255)) * 255))
        written.append(save(out(name), bake_shadow_floor(V), A, empty_rgb=(neutral,) * 3))
    C, A = billow_soft(rng(20))
    written.append(save(out('billow_soft.png'), C, A, empty_rgb=(NEUTRAL,) * 3))
    written.append(save(out('puff.png'), 1.0, puff(rng(30))))
    written.append(save(out('glow.png'), 1.0, glow()))
    g, a = flame(rng(40))
    written.append(save(out('flame.png'), g, a))
    written.append(save(out('plume_streak.png'), 1.0, plume_streak(rng(50))))
    g, a = contrail(rng(60))
    written.append(save(out('contrail.png'), g, a))
    rgb, a, fill = ice_shards(rng(70))
    written.append(save(out('ice_shards.png'), rgb, a, empty_rgb=fill))
    written.append(save(out('foam.png'), 1.0, foam(rng(80))))

    for p in written:
        with Image.open(p) as im:
            print(f'{p}  {im.size[0]}x{im.size[1]}  {im.mode}')


if __name__ == '__main__':
    main()
