// node render.js <layer back|front|shelf> <W> <H> <out.png>
const { chromium } = require('playwright');
const [layer, W, H, out] = [process.argv[2], +process.argv[3], +process.argv[4], process.argv[5]];

function rand(seed) { return () => (seed = (seed * 16807) % 2147483647) / 2147483647; }

function back(W, H) {
  const r = rand(7), u = H / 100;
  let stars = '';
  for (let i = 0; i < Math.round(W * H / 2600 / u / u * 3); i++) {
    const x = r() * W, y = r() * H * 0.75, s = (0.12 + r() * 0.35) * u;
    stars += `<circle cx="${x}" cy="${y}" r="${s}" fill="#fff" opacity="${0.25 + r() * 0.6}"/>`;
  }
  const beams = [-38, -16, 16, 38].map((a, i) => `
    <g transform="rotate(${a} ${W / 2} ${H * 0.92})">
      <polygon points="${W / 2 - 1.2 * u},${H * 0.92} ${W / 2 + 1.2 * u},${H * 0.92} ${W / 2 + 9 * u},${-H * 0.4} ${W / 2 - 9 * u},${-H * 0.4}"
        fill="url(#beam)" opacity="${i % 3 ? 0.7 : 0.45}" filter="url(#soft)"/>
    </g>`).join('');
  return `
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#04010c"/><stop offset="0.6" stop-color="#12052b"/><stop offset="1" stop-color="#2a0a45"/>
    </linearGradient>
    <radialGradient id="glow" cx="${W / 2}" cy="${H * 1.05}" r="${W * 0.62}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffd27a"/><stop offset="0.12" stop-color="#ff7a3d"/>
      <stop offset="0.32" stop-color="#e3197d" stop-opacity="0.85"/><stop offset="0.6" stop-color="#5b1ecf" stop-opacity="0.45"/>
      <stop offset="1" stop-color="#5b1ecf" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="beam" x1="0" y1="1" x2="0" y2="0">
      <stop offset="0" stop-color="#fff2e0" stop-opacity="0.9"/><stop offset="0.7" stop-color="#ffd6f0" stop-opacity="0.08"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#ff3d8b" stop-opacity="0"/><stop offset="0.3" stop-color="#ff5a6e"/>
      <stop offset="0.5" stop-color="#fff6e0"/><stop offset="0.7" stop-color="#ff5a6e"/><stop offset="1" stop-color="#ff3d8b" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="flare" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#6fe7ff" stop-opacity="0"/><stop offset="0.5" stop-color="#e8fbff"/><stop offset="1" stop-color="#6fe7ff" stop-opacity="0"/>
    </linearGradient>
    <filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="${1.6 * u}"/></filter>
    <filter id="blur3" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="${3 * u}"/></filter>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#sky)"/>
  ${stars}
  <rect width="${W}" height="${H}" fill="url(#glow)"/>
  ${beams}
  <ellipse cx="${W / 2}" cy="${H * 0.8}" rx="${W * 0.42}" ry="${0.5 * u}" fill="url(#flare)" opacity="0.9" filter="url(#soft)"/>
  <ellipse cx="${W / 2}" cy="${H * 0.8}" rx="${W * 0.3}" ry="${0.18 * u}" fill="url(#flare)"/>
  <ellipse cx="${W / 2}" cy="${H * 1.62}" rx="${W * 0.95}" ry="${H * 0.8}" fill="none" stroke="url(#rim)" stroke-width="${3 * u}" filter="url(#blur3)"/>
  <ellipse cx="${W / 2}" cy="${H * 1.62}" rx="${W * 0.95}" ry="${H * 0.8}" fill="#060110" stroke="url(#rim)" stroke-width="${0.5 * u}"/>`;
}

function emblem(cx, cy, h, u) {
  // Rounded play triangle: a filled path stroked in the same paint with round joins.
  const w = h * 0.9, k = h * 0.08;
  const p = `M ${cx - w * 0.42 + k} ${cy - h / 2 + k} L ${cx + w * 0.58 - k} ${cy} L ${cx - w * 0.42 + k} ${cy + h / 2 - k} Z`;
  return `
  <defs>
    <linearGradient id="gold" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#ffffff"/><stop offset="0.45" stop-color="#ffe7c2"/><stop offset="1" stop-color="#ff9a52"/>
    </linearGradient>
    <linearGradient id="shine" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff" stop-opacity="0.9"/><stop offset="0.5" stop-color="#fff" stop-opacity="0"/>
    </linearGradient>
    <filter id="halo" x="-60%" y="-60%" width="220%" height="220%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="${4 * u}" result="b"/>
      <feFlood flood-color="#ff3d8b" flood-opacity="0.95"/><feComposite in2="b" operator="in" result="g1"/>
      <feGaussianBlur in="SourceAlpha" stdDeviation="${1.2 * u}" result="b2"/>
      <feFlood flood-color="#ffb070" flood-opacity="0.9"/><feComposite in2="b2" operator="in" result="g2"/>
      <feMerge><feMergeNode in="g1"/><feMergeNode in="g2"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <clipPath id="tri"><path d="${p}" stroke-width="${2 * k}" stroke-linejoin="round"/></clipPath>
  </defs>
  <g filter="url(#halo)">
    <path d="${p}" fill="url(#gold)" stroke="url(#gold)" stroke-width="${2 * k}" stroke-linejoin="round"/>
  </g>
  <path d="M ${cx - w * 0.42} ${cy - h / 2} L ${cx + w * 0.62} ${cy - h * 0.02} L ${cx - w * 0.42} ${cy + h * 0.05} Z"
    fill="url(#shine)" opacity="0.55" clip-path="url(#tri)"/>`;
}

function svg() {
  const u = H / 100;
  if (layer === 'back') return back(W, H);
  if (layer === 'front') return emblem(W / 2 + 1.5 * u, H * 0.47, H * 0.5, u);
  // Top shelf: the scene with the emblem and the wordmark.
  const h = H * 0.42, cy = H * 0.46;
  return back(W, H) + emblem(W / 2 - 62 * u, cy, h, u) + `
  <defs><linearGradient id="word" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#ffc08a"/></linearGradient>
    <filter id="wglow" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur in="SourceAlpha" stdDeviation="${2.5 * u}" result="b"/>
    <feFlood flood-color="#ff3d8b" flood-opacity="0.8"/><feComposite in2="b" operator="in" result="g"/>
    <feMerge><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
  <text x="${W / 2 - 31 * u}" y="${cy + 13 * u}" font-family="Bebas Neue" font-size="${40 * u}" letter-spacing="${2.5 * u}"
    fill="url(#word)" filter="url(#wglow)">CAMFLIX</text>`;
}

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: W, height: H } });
  await p.setContent(`<html><head><link href="https://fonts.googleapis.com/css2?family=Bebas+Neue&display=block" rel="stylesheet">
    <style>html,body{margin:0;background:transparent}</style></head>
    <body><svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}">${svg()}</svg></body></html>`);
  await p.evaluate(() => document.fonts.ready);
  await p.waitForTimeout(300);
  await p.screenshot({ path: out, omitBackground: layer === 'front' });
  await b.close();
})();
