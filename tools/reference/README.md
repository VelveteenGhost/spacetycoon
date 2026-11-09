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
`window.__cap` (`startSeq`, `setCam`, `updateHUD`, `state()`).
