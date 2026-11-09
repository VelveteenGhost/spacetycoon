"""Bake the mood study's sky (THREE.Sky, Preetham, plus the page's grade) into cube-map faces for Roblox skyboxes.

Usage: venv/bin/python -I tools/reference/bake_sky.py [out_dir]      (default out_dir: <repo>/art/sky)

Serves this folder on a local port, opens moodstudy_capture.html in headless Chrome and, for each look (sun elevation x
weather), renders the sky alone from (0, 2, 0) into six 1024x1024 faces with a 90 deg camera:
    Ft look -Z, Bk +Z, Lf -X, Rt +X (image up +Y);  Up look +Y (image up -Z);  Dn look -Y (image up +Z).
Writes <out_dir>/<look>_<weather>/<Face>.png, a 1600x400 strip.png (Lf Ft Rt Bk, for checking the horizon across the
seams) and <out_dir>/debug/<Face>.png (grey faces with a label and an image-up arrow, for checking Roblox's orientation).
Prints each look's sky parameters, a seam check over all 24 cube edges and where the sun lands.
"""
import base64, functools, http.server, os, sys, threading
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(REPO, 'art', 'sky')
SIZE = 1024
LOOKS = [('blue', -4), ('sunrise', 3), ('morning', 12)]
WEATHERS = ['clear', 'marine']
FACES = ['Ft', 'Bk', 'Lf', 'Rt', 'Up', 'Dn']
STRIP = (['Lf', 'Ft', 'Rt', 'Bk'], 400)
DEBUG_CAPTION = {'Ft': 'look -Z · up +Y', 'Bk': 'look +Z · up +Y', 'Lf': 'look -X · up +Y',
                 'Rt': 'look +X · up +Y', 'Up': 'look +Y · up -Z', 'Dn': 'look -Y · up +Z'}

# Checks on the faces left in window.__skyBake. Seams: for every border pixel, the pixel just across the cube edge
# (found by stepping one pixel past the edge and projecting that direction onto the face it falls in) against the pixel
# one step inward on its own face; a seam shows as across >> inward. Sun: the face and pixel the sun direction projects
# to, and the centroid of the warmest pixels (R - B) over the four side faces.
CHECK_JS = r"""
() => {
  const B = window.__skyBake, S = B.size, F = B.faces;
  const cross = (a, b) => [a[1]*b[2] - a[2]*b[1], a[2]*b[0] - a[0]*b[2], a[0]*b[1] - a[1]*b[0]];
  const dot = (a, b) => a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
  const basis = {}; for (const [n, [f, u]] of Object.entries(B.axes)) basis[n] = { f, u, r: cross(f, u) };
  const dirOf = (n, i, j) => { const b = basis[n], x = (i + .5)/S*2 - 1, y = 1 - (j + .5)/S*2; return [0, 1, 2].map(k => b.f[k] + x*b.r[k] + y*b.u[k]); };
  const faceOf = d => { let best = null, bv = -Infinity; for (const n in basis){ const v = dot(d, basis[n].f); if (v > bv){ bv = v; best = n; } } return best; };
  const ndcOf = (n, d) => { const b = basis[n], w = dot(d, b.f); return [dot(d, b.r)/w, dot(d, b.u)/w]; };
  const pixOf = (n, d) => { const [x, y] = ndcOf(n, d); const c = v => Math.min(S - 1, Math.max(0, Math.floor(v))); return [c((x + 1)/2*S), c((1 - y)/2*S)]; };
  const px = (n, i, j) => { const o = (j*S + i)*4, a = F[n]; return [a[o], a[o + 1], a[o + 2]]; };
  const diff = (p, q) => Math.max(Math.abs(p[0] - q[0]), Math.abs(p[1] - q[1]), Math.abs(p[2] - q[2]));
  const seams = [];
  for (const n in basis) for (const [e, di, dj] of [['right', 1, 0], ['left', -1, 0], ['top', 0, -1], ['bottom', 0, 1]]){
    let across = 0, inward = 0, acrossMax = 0, nb = null;
    for (let k = 0; k < S; k++){
      const i = di > 0 ? S - 1 : di < 0 ? 0 : k, j = dj > 0 ? S - 1 : dj < 0 ? 0 : k;
      const d = dirOf(n, i + di, j + dj), m = faceOf(d), [ii, jj] = pixOf(m, d);
      if (k === S >> 1) nb = m;
      const a = diff(px(n, i, j), px(m, ii, jj)), b = diff(px(n, i, j), px(n, i - di, j - dj));
      across += a; inward += b; acrossMax = Math.max(acrossMax, a);
    }
    seams.push({ face: n, edge: e, neighbour: nb, across: across/S, inward: inward/S, acrossMax });
  }
  const sd = B.sunDir, sf = faceOf(sd), [sx, sy] = ndcOf(sf, sd), [spi, spj] = pixOf(sf, sd);
  const warm = new Int16Array(4*S*S), hist = new Uint32Array(511);
  ['Lf', 'Ft', 'Rt', 'Bk'].forEach((n, fi) => { const a = F[n]; for (let o = 0, p = fi*S*S; o < a.length; o += 4, p++){ warm[p] = a[o] - a[o + 2]; hist[warm[p] + 255]++; } });
  let cut = 255, seen = 0; while (cut > -255 && seen + hist[cut + 255] <= warm.length*.005){ seen += hist[cut + 255]; cut--; }
  const glow = {};
  ['Lf', 'Ft', 'Rt', 'Bk'].forEach((n, fi) => { let c = 0, xs = 0, ys = 0;
    for (let p = 0; p < S*S; p++) if (warm[fi*S*S + p] >= cut){ c++; xs += p % S; ys += Math.floor(p/S); }
    glow[n] = c ? { share: c, x: Math.round(xs/c), y: Math.round(ys/c) } : { share: 0 }; });
  const tot = Object.values(glow).reduce((s, g) => s + g.share, 0); for (const g of Object.values(glow)) g.share = +(g.share/tot).toFixed(3);
  return { seams, sun: { face: sf, ndc: [+sx.toFixed(4), +sy.toFixed(4)], pixel: [spi, spj] }, warmCut: cut, glow };
}
"""

STRIP_JS = r"""
([names, cell]) => {
  const B = window.__skyBake, S = B.size;
  const cv = document.createElement('canvas'); cv.width = cell*names.length; cv.height = cell;
  const g = cv.getContext('2d'); g.imageSmoothingEnabled = true; g.imageSmoothingQuality = 'high';
  names.forEach((n, i) => { const src = document.createElement('canvas'); src.width = src.height = S;
    src.getContext('2d').putImageData(new ImageData(B.faces[n], S, S), 0, 0); g.drawImage(src, i*cell, 0, cell, cell); });
  return cv.toDataURL('image/png');
}
"""

DEBUG_JS = r"""
([name, caption, S]) => {
  const cv = document.createElement('canvas'); cv.width = cv.height = S; const g = cv.getContext('2d');
  g.fillStyle = '#808080'; g.fillRect(0, 0, S, S);
  g.strokeStyle = '#5a5a5a'; g.lineWidth = S*.012; g.strokeRect(g.lineWidth/2, g.lineWidth/2, S - g.lineWidth, S - g.lineWidth);
  g.fillStyle = '#ffffff';                                   // arrow to image-up: shaft from the middle, head at the top
  const cx = S/2, w = S*.07, top = S*.06, head = S*.2;
  g.beginPath(); g.moveTo(cx, top); g.lineTo(cx + head*.75, top + head); g.lineTo(cx + w/2, top + head); g.lineTo(cx + w/2, S*.5);
  g.lineTo(cx - w/2, S*.5); g.lineTo(cx - w/2, top + head); g.lineTo(cx - head*.75, top + head); g.closePath(); g.fill();
  g.textAlign = 'center'; g.textBaseline = 'alphabetic';
  g.font = `bold ${Math.round(S*.3)}px Helvetica, Arial, sans-serif`; g.fillText(name.toUpperCase(), cx, S*.8);
  g.fillStyle = '#202020'; g.font = `${Math.round(S*.045)}px Helvetica, Arial, sans-serif`; g.fillText(caption, cx, S*.92);
  return cv.toDataURL('image/png');
}
"""


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


def write_png(path, data_url):
    head, b64 = data_url.split(',', 1)
    assert head == 'data:image/png;base64', head
    with open(path, 'wb') as f:
        f.write(base64.b64decode(b64))


def open_page(browser, url):
    pg = browser.new_page(viewport={'width': 1600, 'height': 900}, device_scale_factor=1)
    errs = []
    pg.on('pageerror', lambda e: errs.append('%s at %s' % (e, ' < '.join(l.strip()[3:] for l in (e.stack or '').splitlines()[1:4]))))
    pg.goto(url, wait_until='load')
    pg.wait_for_function('window.__cap && window.__cap.bakeSky && (window.__frameCount || 0) > 10', timeout=60000)
    pg.evaluate('window.__noGov = true; window.__fixedDt = 1/30; window.__paused = true;')
    # the page itself can throw on its first frame or two (hold-mode auto camera, before the clock settles); report
    # those apart from anything the bake raises
    if errs:
        print('startup page errors (before any bake):', sorted(set(errs)))
    errs.clear()
    return pg, errs


def main():
    httpd = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=HERE))
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    url = 'http://127.0.0.1:%d/moodstudy_capture.html' % httpd.server_address[1]
    worst = 0.0
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(channel='chrome', headless=True)
            try:
                pg, errs = open_page(browser, url)
                print('renderer:', pg.evaluate("(() => { const g = document.createElement('canvas').getContext('webgl2');"
                                               " const x = g && g.getExtension('WEBGL_debug_renderer_info');"
                                               " return x ? g.getParameter(x.UNMASKED_RENDERER_WEBGL) : 'unknown'; })()"))
                for wx in WEATHERS:
                    for look, elev in LOOKS:
                        tag = '%s_%s' % (look, wx)
                        d = os.path.join(OUT, tag)
                        os.makedirs(d, exist_ok=True)
                        st = pg.evaluate('([e, w]) => window.__cap.setLook(e, w)', [elev, wx])
                        assert st['elev'] == elev and st['wx'] == wx and st['gradeOn'], st
                        res = pg.evaluate('s => window.__cap.bakeSky(s)', SIZE)
                        for face in FACES:
                            write_png(os.path.join(d, face + '.png'), res['png'][face])
                        write_png(os.path.join(d, 'strip.png'), pg.evaluate(STRIP_JS, list(STRIP)))
                        chk = pg.evaluate(CHECK_JS)
                        seam = max(s['across'] - s['inward'] for s in chk['seams'])
                        seam_max = max(s['acrossMax'] for s in chk['seams'])
                        worst = max(worst, seam)
                        print('\n%s: elev %+g, turbidity %.2f, rayleigh %.3f, mie %.5f/%.2f, exposure %.4f, sunDir %s'
                              % (tag, elev, st['turbidity'], st['rayleigh'], st['mieCoefficient'], st['mieDirectionalG'],
                                 res['exposure'], [round(v, 4) for v in st['sunDir']]))
                        print('  grade: contrast %g, saturation %g, tint %s, lift %s, vignette %g, grain %g'
                              % (res['contrast'], res['saturation'], [round(v, 3) for v in res['tint']],
                                 [round(v, 3) for v in res['lift']], res['vignette'], res['grain']))
                        print('  seams (24 edges, 8-bit levels): worst mean(across - inward) %.2f, worst single pixel %d'
                              % (seam, seam_max))
                        print('  sun: face %s, ndc %s, pixel %s; warm glow (top 0.5%% R-B) by face %s'
                              % (chk['sun']['face'], chk['sun']['ndc'], chk['sun']['pixel'], chk['glow']))
                dd = os.path.join(OUT, 'debug')
                os.makedirs(dd, exist_ok=True)
                for face in FACES:
                    write_png(os.path.join(dd, face + '.png'), pg.evaluate(DEBUG_JS, [face, DEBUG_CAPTION[face], SIZE]))
                if errs:
                    print('page errors during the bake:', sorted(set(errs)))
            finally:
                browser.close()
    finally:
        httpd.shutdown()
    print('\nwrote %d looks + debug to %s; worst seam excess %.2f levels' % (len(LOOKS)*len(WEATHERS), OUT, worst))


if __name__ == '__main__':
    main()
