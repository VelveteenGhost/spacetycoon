# Mood-study reference frames

`capture.py` renders the mood study (`moodstudy_capture.html`, a copy with a small capture hook) in headless
Chrome and writes PNGs for every broadcast camera at fixed T-times, plus `frames.json` with each frame's exact
camera state (position and aim in metres, vertical FOV in degrees). The PNGs go to `previews/reference/`, which
git ignores; `frames.json` is kept here so camera checks can run without re-rendering.

```
python3 -m venv /tmp/refvenv && /tmp/refvenv/bin/pip install playwright
python3 -m http.server 18731 --bind 127.0.0.1 --directory tools/reference &
/tmp/refvenv/bin/python -I tools/reference/capture.py http://127.0.0.1:18731/moodstudy_capture.html previews/reference
```

It drives the installed Google Chrome (`channel="chrome"`), so no browser download is needed. About 76 s.
The hook in the copy: `window.__fixedDt`, `__paused`, `__noGov`, `__untilT`, `__frameCount` and
`window.__cap` (`startSeq`, `setCam`, `updateHUD`, `state()`, plus `setLook` and `bakeSky` for the sky bake below).

## Sky cube maps

`bake_sky.py` bakes the page's sky into Roblox skybox faces. It covers six looks: sun at −4° (`blue`), +3° (`sunrise`)
and +12° (`morning`), each in `clear` and `marine` weather. Each look gets 1024×1024 `Ft Bk Lf Rt Up Dn.png` in
`art/sky/<look>_<weather>/`, plus a 1600×400 `strip.png` (Lf Ft Rt Bk, for checking the horizon across the seams).
It also writes `art/sky/debug/`, grey faces with a label and an image-up arrow, for checking how Roblox orients each face.

```
/tmp/refvenv/bin/python -I tools/reference/bake_sky.py            # optional arg: another output folder
```

It serves this folder itself on a free local port, so the `http.server` step above isn't needed. It takes about 5 s.
- Camera: at (0, 2, 0) with a 90° FOV. `Ft` looks −Z, `Bk` +Z, `Lf` −X and `Rt` +X, with image-up +Y. `Up` looks +Y
  with image-up −Z, and `Dn` looks −Y with image-up +Z.
- What's drawn: only the sky mesh, with fog and bloom off. It goes through a copy of the grade pass at the look's
  `baseExposure`, with the page's contrast, saturation, tint and lift. Vignette, grain and sun glare are 0, because
  they're screen-space and would seam.
- Log: each look's sky and grade parameters, a seam check over all 24 cube edges, and where the sun lands. At bearing
  98° it should be in `Rt`, a little left of centre.
- Page errors on the first frame or two: the page throws them itself at load, and the script reports them apart from
  the bake.
