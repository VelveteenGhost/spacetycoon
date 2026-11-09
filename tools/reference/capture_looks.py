"""Render mood-study reference frames for the other looks: sun elevation and weather, at a fixed launch time.

capture.py covers the default look (sun +3, clear) across the sequence. This one holds the sequence at one T-time
and steps through the lighting presets the deck offers, for the cameras that decide the look.

Usage: venv/bin/python -I capture_looks.py <page_url> <out_dir>
Writes look_<sun>_<wx>_<cam>.png (sun as blue, sunrise or morning).
"""
import os, sys
from playwright.sync_api import sync_playwright

URL, OUT = sys.argv[1], sys.argv[2]
T = -28
SUNS = {'blue': -4, 'sunrise': 3, 'morning': 12}
LOOKS = [('blue', 'clear'), ('morning', 'clear'), ('sunrise', 'broken'), ('sunrise', 'marine'), ('blue', 'marine')]
CAMS = ['mount', 'pad', 'onboard', 'drone', 'press', 'wide']


def wait_frames(pg, n):
    fc0 = pg.evaluate('window.__frameCount')
    pg.wait_for_function('n => window.__frameCount >= n', arg=fc0 + n, timeout=60000, polling='raf')


os.makedirs(OUT, exist_ok=True)
with sync_playwright() as p:
    browser = p.chromium.launch(channel='chrome', headless=True)
    pg = browser.new_page(viewport={'width': 1600, 'height': 900}, device_scale_factor=1)
    pg.goto(URL, wait_until='load')
    pg.wait_for_function('window.__cap && (window.__frameCount || 0) > 10', timeout=60000)
    pg.evaluate('window.__noGov = true; window.__fixedDt = 1/30; window.__paused = true;')
    if pg.get_attribute('#tMotion', 'aria-pressed') != 'false':
        pg.click('#tMotion')
    pg.evaluate("document.querySelector('#deck').style.display = 'none'; document.querySelector('#showBtn').hidden = true;"
                "document.querySelectorAll('[data-ov]').forEach(el => { el.style.visibility = 'hidden'; });")
    pg.evaluate('c => window.__cap.setCam(c)', 'drone')
    pg.evaluate('m => window.__cap.startSeq(m)', 'launch')
    wait_frames(pg, 1)
    pg.evaluate('t => { window.__untilT = t; window.__paused = false; }', T)
    pg.wait_for_function('t => window.__cap.state().tRel === t', arg=T, timeout=600000, polling='raf')
    pg.evaluate('window.__paused = true;')
    for sun, wx in LOOKS:
        pg.evaluate('w => document.querySelector(`[data-wx="${w}"]`).click()', wx)  # the deck is hidden
        pg.evaluate("v => { const s = document.querySelector('#sun'); s.value = v; "
                    "s.dispatchEvent(new Event('input')); s.dispatchEvent(new Event('change')); }", str(SUNS[sun]))
        for cam in CAMS:
            pg.evaluate('c => window.__cap.setCam(c)', cam)
            wait_frames(pg, 4)
            pg.screenshot(path=os.path.join(OUT, f'look_{sun}_{wx}_{cam}.png'))
    browser.close()
print(f'{len(LOOKS) * len(CAMS)} frames written')
