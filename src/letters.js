// The name in breath: each letter is breathed on, written stroke by stroke, held, melted by touch, rewritten.
// Writing pace is in glass units per second.
const SPEED = 430, LIFT = 0.13, BREATH = 1.5, GAP = 0.25, GONE = 24, FRONT = 300;

export async function loadStrokes() { const r = await fetch(new URL('../assets/strokes.json', import.meta.url)); if (!r.ok) throw Error('strokes: ' + r.status); return (await r.json()).chars; }

export function createLetters(chars, size, instant, onWake, away) {
  const [W, H] = size, n = chars.length, tall = W < H * 0.95;   // tall panes read top to bottom, as Japanese may
  const box = tall ? Math.min(W * 0.46, H * 0.92 / n) : Math.min(H * 0.36, W * 0.88 / n);
  const r = Math.max(3.4, box * 0.026), jig = i => Math.sin(i * 12.9 + 4) * 0.5;
  const letters = chars.map((c, i) => {
    const cx = tall ? W / 2 + jig(i) * 10 : W / 2 + (i - (n - 1) / 2) * box * 1.03, cy = tall ? H / 2 + (i - (n - 1) / 2) * box * 1.0 : H * 0.42 + jig(i + 2) * 16;
    const rot = jig(i + 5) * 0.05, k = box / 109, co = Math.cos(rot) * k, si = Math.sin(rot) * k;
    const strokes = c.strokes.map(s => s.map(([x, y]) => [cx + x * co - y * si, cy + x * si + y * co]));
    const segs = []; let t = 0;
    strokes.forEach((s, si) => { for (let j = 1; j < s.length; j++) { const L = Math.hypot(s[j][0] - s[j - 1][0], s[j][1] - s[j - 1][1]); const u = j / (s.length - 1); segs.push({ a: s[j - 1], b: s[j], L, t0: t, t1: t + L / SPEED, r: r * (0.86 + 0.22 * Math.sin(Math.PI * Math.min(1, u * 1.15))), end: j === s.length - 1, si, melt: null }); t += L / SPEED; } t += LIFT; });
    const len = segs.reduce((a, s) => a + s.L, 0);
    // Particles released per unit of stroke: simple letters still need enough water to run.
    return { char: c.char, i, cx, cy, segs, dur: t, water: Math.max(0.72, Math.min(1.5, 620 / len)), state: 'wait', t: 0 };
  });
  const count = letters.reduce((a, l) => a + l.segs.length, 0), data = new Float32Array(count * 8), breaths = new Float32Array(n * 4);
  let hush = 0.8;                                             // a pause before the first breath
  const busy = () => letters.some(l => l.state === 'breath' || l.state === 'write');
  const set = (l, s) => { l.state = s; l.t = 0; };
  function wake(l, p) {
    for (const s of l.segs) s.melt = Math.max(0, Math.hypot((s.a[0] + s.b[0]) / 2 - p[0], (s.a[1] + s.b[1]) / 2 - p[1]) - 18) / FRONT;
    set(l, 'melt'); onWake?.(l, p);
  }
  return {
    letters, count, data, breaths, box, instances: count,
    touch(a, b, rad) {
      for (const l of letters) {
        if (l.state !== 'hold' || Math.abs(b[0] - l.cx) > box || Math.abs(b[1] - l.cy) > box) continue;
        const near = l.segs.some(s => { const mx = (s.a[0] + s.b[0]) / 2, my = (s.a[1] + s.b[1]) / 2, vx = b[0] - a[0], vy = b[1] - a[1], q = Math.max(0, Math.min(1, ((mx - a[0]) * vx + (my - a[1]) * vy) / Math.max(1e-4, vx * vx + vy * vy))); return Math.hypot(mx - a[0] - vx * q, my - a[1] - vy * q) < rad + 4; });
        if (near) wake(l, b);
      }
    },
    step(dt) {
      hush -= dt;
      if (hush <= 0 && !busy()) { const l = letters.find(l => l.state === 'wait'); if (l) set(l, 'breath'); }
      let o = 0; breaths.fill(0);
      for (const l of letters) {
        l.t += dt;
        // Negative strength marks a letter that still needs its fog (see field.wgsl).
        if (l.state === 'write' || l.state === 'hold') breaths.set([l.cx, l.cy, box * 0.62, -1], l.i * 4);
        if (l.state === 'breath') {
          breaths.set([l.cx, l.cy, box * 0.62, 2.6 * Math.sin(Math.PI * Math.min(1, l.t / BREATH))], l.i * 4);
          if (l.t > BREATH) set(l, instant ? 'hold' : 'write');
        } else if (l.state === 'write' && l.t > l.dur) { set(l, 'hold'); hush = GAP; }
        else if (l.state === 'melt' && l.t > Math.max(...l.segs.map(s => s.melt)) + 1.6) set(l, 'gone');
        else if (l.state === 'gone' && l.t > GONE && !away?.(l)) set(l, 'wait');
        for (const s of l.segs) {
          let alpha = 0, rate = 0, b = s.b;
          if (l.state === 'write') {
            const u = (l.t - s.t0) / (s.t1 - s.t0); alpha = u > 0 ? 1 : 0; if (u > 0 && u < 1) b = [s.a[0] + (s.b[0] - s.a[0]) * u, s.a[1] + (s.b[1] - s.a[1]) * u];
            if (s.end && l.t >= s.t1 && l.t - dt < s.t1) rate = 1.6;   // a little water collects where the finger lifts
          } else if (l.state === 'hold') alpha = 1;
          else if (l.state === 'melt') {
            const u = (l.t - s.melt) / 0.55; alpha = 1 - Math.max(0, Math.min(1, (u - 0.5) / 1.6));
            if (u > 0 && u < 1) rate = s.L * l.water * dt / 0.55;
          }
          data.set([s.a[0], s.a[1], b[0], b[1], s.r, alpha, rate, 0], o); o += 8;
        }
      }
    },
    get state() { return letters.map(l => l.char + ':' + l.state); },
  };
}
