"""Render reference frames from the three.js mood study (capture copy) for camera-by-camera comparison.

Usage: venv/bin/python -I capture.py <page_url> <out_dir>
"""
import json, os, sys, time
from playwright.sync_api import sync_playwright

URL, OUT = sys.argv[1], sys.argv[2]
CAMS = ['onboard', 'mount', 'pad', 'drone', 'long', 'press', 'coast', 'wide', 'tracker']
LAUNCH_T = [-28, -10, 0, 4, 10, 20]
STATIC_T = [3]
SETTLE_FRAMES = 4
HUD_SHOT = ('launch', -10, 'mount')

records = []
log = []


def tlabel(t):
    return f"T-{abs(t):g}" if t < 0 else f"T+{t:g}"


def wait_frames(pg, n):
    fc0 = pg.evaluate('window.__frameCount')
    pg.wait_for_function('n => window.__frameCount >= n', arg=fc0 + n, timeout=60000, polling='raf')


def set_overlay(pg, visible):
    pg.evaluate("v => document.querySelectorAll('[data-ov]').forEach(el => { el.style.visibility = v ? '' : 'hidden'; })", visible)


def open_page(browser):
    pg = browser.new_page(viewport={'width': 1600, 'height': 900}, device_scale_factor=1)
    errs = []
    pg.on('pageerror', lambda e: errs.append(str(e)))
    pg.goto(URL, wait_until='load')
    pg.wait_for_function('window.__cap && (window.__frameCount || 0) > 10', timeout=60000)
    pg.evaluate('document.fonts.ready.then(() => true)')
    # freeze the governor and time stepping first, then the UI settings
    pg.evaluate('window.__noGov = true; window.__fixedDt = 1/30; window.__paused = true;')
    if pg.get_attribute('#tMotion', 'aria-pressed') != 'false':
        pg.click('#tMotion')
    assert pg.get_attribute('#tMotion', 'aria-pressed') == 'false', 'motion still on'
    env = pg.evaluate("({ sun: document.querySelector('#sun').value, sunOut: document.querySelector('#sunOut').value, "
                      "wx: document.querySelector('[data-wx][aria-pressed=true]').dataset.wx, dpr: devicePixelRatio, w: innerWidth, h: innerHeight })")
    assert env['sun'] == '3' and env['wx'] == 'clear', env
    pg.evaluate("document.querySelector('#deck').style.display = 'none'; document.querySelector('#showBtn').hidden = true;")
    set_overlay(pg, False)
    log.append(f'page env {env}; startup page errors: {sorted(set(errs))}')
    errs.clear()
    return pg, errs


def advance_to(pg, target):
    t0 = time.time()
    pg.evaluate('t => { window.__untilT = t; window.__paused = false; }', target)
    pg.wait_for_function('t => window.__cap.state().tRel === t', arg=target, timeout=600000, polling='raf')
    pg.evaluate('window.__paused = true;')
    wait_frames(pg, 2)
    st = pg.evaluate('window.__cap.state()')
    assert st['tRel'] == target, st
    log.append(f'reached tRel={target} in {time.time() - t0:.1f}s wall')


def shoot(pg, seq, target, cam, overlay=False):
    pg.evaluate('c => window.__cap.setCam(c)', cam)
    if overlay:
        set_overlay(pg, True)
    wait_frames(pg, SETTLE_FRAMES)
    if overlay:
        pg.evaluate('window.__cap.updateHUD()')      # HUD text refreshes on sim time, which is paused: refresh it for this camera
        wait_frames(pg, 2)
    st = pg.evaluate('window.__cap.state()')
    assert st['cam'] == cam and st['tRel'] == target, st
    name = f"{'hud_' if overlay else ''}{seq}_{tlabel(target)}_{cam}.png"
    pg.screenshot(path=os.path.join(OUT, name))
    st2 = pg.evaluate('window.__cap.state()')
    assert st2['pos'] == st['pos'] and st2['aim'] == st['aim'] and st2['tRel'] == st['tRel'], (st, st2)
    if overlay:
        set_overlay(pg, False)
    records.append({'file': name, 'seq': seq, 'tRel': st['tRel'], 'cam': cam, 'label': st['label'],
                    'pos': st['pos'], 'aim': st['aim'], 'fov': st['fov'], 'aspect': st['aspect'],
                    'alt': st['alt'], 'posX': st['posX'], 'pitch': st['pitch'],
                    'quat': st['quat'], 'near': st['near'], 'far': st['far'], 'thrust': st['thrust'],
                    'overlay': overlay})


def run_seq(browser, seq, targets):
    pg, errs = open_page(browser)
    pg.evaluate('c => window.__cap.setCam(c)', 'drone')   # manual camera from here on (autoCam off)
    pg.evaluate('m => window.__cap.startSeq(m)', seq)
    wait_frames(pg, 1)
    st = pg.evaluate('window.__cap.state()')
    assert st['seqMode'] == seq and st['tRel'] == -30, st
    for target in targets:
        advance_to(pg, target)
        for cam in CAMS:
            shoot(pg, seq, target, cam)
        if (seq, target) == HUD_SHOT[:2]:
            shoot(pg, seq, target, HUD_SHOT[2], overlay=True)
        pg.evaluate('window.__paused = false;')
    if errs:
        log.append(f'{seq}: page errors during capture: {sorted(set(errs))}')
    pg.close()


os.makedirs(OUT, exist_ok=True)
with sync_playwright() as p:
    browser = p.chromium.launch(channel='chrome', headless=True)
    try:
        run_seq(browser, 'launch', LAUNCH_T)
        run_seq(browser, 'static', STATIC_T)
    finally:
        browser.close()
        with open(os.path.join(OUT, 'frames.json'), 'w') as f:
            json.dump(records, f, indent=1)
        print('\n'.join(log))
        print(f'{len(records)} frames written')
