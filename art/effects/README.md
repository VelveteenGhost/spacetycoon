# Effect textures

Particle and beam textures for the launch-pad port, ported from the three.js scene's canvas recipes. Regenerate with:

```
python tools/make_effect_textures.py --out art/effects            # seed 1977 by default; --seed N for variants
```

All files are 8-bit RGBA PNG with straight (non-premultiplied) alpha, white or grayscale so `Color` tints them.
White masks keep RGB 255 everywhere. Shaded ones put a neutral grey in fully transparent texels, never black.
Beam textures run along the beam on X (U) and across it on Y (V).

| File | Size | What it's for | Suggested Roblox use |
| --- | --- | --- | --- |
| `billow_a.png` | 256² | Lit cauliflower billow, `litBillow(46, .78)`: ground cloud and contrail puffs | ParticleEmitter, LightEmission 0, LightInfluence 1, Orientation FacingCameraWorldUp (keeps the lit top up), Rotation −15..15 |
| `billow_b.png` | 256² | Same, `litBillow(30, .9)`: fewer, bigger lumps | As above; use a second emitter for variety |
| `billow_c.png` | 256² | Same, `litBillow(60, .7)`: many small lumps, flatter | As above |
| `billow_soft.png` | 256² | `billowTex2`: soft-edged lumps with a shaded underside, for the ground cloud's outer puffs | ParticleEmitter, LightEmission 0, LightInfluence 1, FacingCameraWorldUp |
| `puff.png` | 128² | `puffTex`: soft steam puff (white mask). Vents, frost vapour, separation gas, fire puffs | ParticleEmitter, Rotation 0..360, small RotSpeed. LightEmission 0 for steam, 1 for the fire puffs |
| `glow.png` | 128² | `glowTex`: soft radial halo (white). Flame halo, lamp glows, beacons | ParticleEmitter or BillboardGui ImageLabel; LightEmission 1, FacingCamera |
| `flame.png` | 256² | Flame tongue: round white-hot end at the **top** of the image, tapering **down**. Narrow opaque core in a streaky sheath | ParticleEmitter, LightEmission 1, Brightness 2–5, Orientation FacingCameraWorldUp so it hangs below a downward nozzle (Rotation 180 for an upward flame), short Lifetime |
| `plume_streak.png` | 256×64 | `plumeTex` turned for a Beam: opaque at the left (nozzle), streaky, clear at the right | Beam, Attachment0 at the nozzle, TextureMode Stretch, TextureLength 1, FaceCamera, LightEmission 1 |
| `contrail.png` | 256×64 | Smoke band: lumpy soft top and bottom edges, mottled, tiles along X | Beam, TextureMode Wrap (TextureLength ≈ 4× Width), FaceCamera, LightEmission 0, LightInfluence 1, optional slow TextureSpeed |
| `ice_shards.png` | 512² | 2×2 flipbook of jagged, flat ice sheets (white to pale ice-blue). Frames go left to right, then top to bottom | ParticleEmitter, FlipbookLayout Grid2x2, FlipbookStartRandom on, low FlipbookFramerate, Orientation VelocityPerpendicular or FacingCamera, RotSpeed and an animated Squash for the flutter |
| `foam.png` | 256² | `foamTex`: broken surf crest lines, tiles in both directions (white). Crests run along X | Beam along the shoreline (TextureMode Wrap, slow TextureSpeed), or a Texture on a transparent part; LightInfluence 1 |

Notes:

- `flame.png` is square, not 128×256: Roblox particles are square, so a tall image would be squashed. Use `Squash` to stretch it.
- The scene's particle shader blends billow undersides into a sky-ambient colour, so they're never black. Roblox only
  multiplies the texture by `Color`, so the billows bake that mix in. Stored grey = sRGB(0.22 + 0.78 × lit), so
  the darkest undersides sit near 143/255 rather than 17/255 (`BILLOW_SHADOW` in the script). Their transparent texels hold the
  same mix applied to litBillow's neutral 0.62 (218/255). `billow_soft` uses 0.62 × 255 = 158.
- The billows only look right while the image's top faces the sun. The scene turns each puff toward the sun on screen;
  in Roblox, FacingCameraWorldUp is the nearest match (sun from above).
- `plume_streak.png` fades to 0 at its top and bottom edges, because a Beam is a flat ribbon, not the scene's open
  cylinder. The scene scrolls the streaks around the cylinder; a Beam can only scroll along U, which would move the hot
  end. Animate it with Brightness and Width flicker, or two overlapping beams.
- `foam.png` has its crests along X, turned 90° from the scene (which ran them along V on a strip lying across the
  shore), so a Beam laid along the coast shows them parallel to it.
