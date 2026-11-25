// A flowering tree, different every time: space colonization (Runions et al. 2007) toward cloud-like lobes.
// Units are metres in the street's space. Returns packed arrays for the GPU.
// Species (桜梅桃李): 0 cherry, the broad cloud it always was. 1 plum (ume): smaller and older-looking, a short
// gnarled trunk, angular zigzag limbs, long straight shoots rising from them, and flowers set singly and
// close along the twigs, many still in bud. (Peach and sumomo still use the cherry's form.)
export const MAX_SEGS = 9000, MAX_BLOSSOMS = 10000;

export function growTree(base, lean, seed, species = 0) {
  const plum = species === 1;
  let s = seed >>> 0 || 1; const R = () => { s = s + 0x6d2b79f5 | 0; let t = Math.imul(s ^ s >>> 15, 1 | s); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
  const G = () => Math.sqrt(-2 * Math.log(R() + 1e-9)) * Math.cos(6.2832 * R()), rr = (a, b) => a + (b - a) * R();
  const C = plum ? [base[0] + lean * 0.30, 1.62, base[2] + 0.05] : [base[0] + lean * 0.36, 2.04, base[2] + 0.05], RX = plum ? 1.02 : 1.38, RY = plum ? 0.58 : 0.80, RZ = plum ? 0.62 : 0.80;

  // Trunk: a slow S-curve that leans over the street.
  const px = [], py = [], pz = [], parent = [], kids = []; const add = (x, y, z, p) => { px.push(x); py.push(y); pz.push(z); parent.push(p); kids.push(0); if (p >= 0) kids[p]++; return px.length - 1; };
  const STEP = 0.048, w0 = rr(0, 6); let n = add(base[0], -0.1, base[2], -1), x = base[0], z = base[2];
  const tall = plum ? 0.66 : 0.92, kink = plum ? 3.2 : 1;   // an old ume trunk twists and leans hard
  for (let y = -0.1 + STEP; y < tall; y += STEP) { x += lean * 0.012 * (0.4 + y) * (plum ? 1.8 : 1) + Math.sin(y * 4.2 * (plum ? 1.7 : 1) + w0) * 0.007 * kink; z += Math.cos(y * 3.1 + w0) * 0.004 * kink; n = add(x, y, z, n); }

  const A = []; const lobes = Array.from({ length: plum ? 7 : 12 }, () => { const a = rr(0, 6.2832), q = Math.sqrt(R()) * 0.85; return [C[0] + Math.cos(a) * q * RX, C[1] + rr(-0.55, 0.85) * RY * Math.sqrt(1 - q * q * 0.8), C[2] + Math.sin(a) * q * RZ]; });
  for (let i = 0; i < (plum ? 700 : 1500); i++) {
    let p; if (R() < 0.88) { const l = lobes[Math.floor(R() * lobes.length)]; p = [l[0] + G() * 0.21, l[1] + G() * 0.115, l[2] + G() * 0.2]; }
    else { const u = rr(-1, 1), a = rr(0, 6.2832), q = Math.cbrt(R()), c = Math.sqrt(1 - u * u); p = [C[0] + c * Math.cos(a) * q * RX, C[1] + u * q * RY, C[2] + c * Math.sin(a) * q * RZ]; }
    if (p[1] > (plum ? 0.72 : 0.95)) A.push({ p, n: -1, d: 1e9 });
  }
  const look = i => { for (const a of A) { const dx = a.p[0] - px[i], dy = a.p[1] - py[i], dz = a.p[2] - pz[i], d = dx * dx + dy * dy + dz * dz; if (d < a.d) { a.d = d; a.n = i; } } };
  for (let i = 0; i < px.length; i++) look(i);
  let live = A.slice();
  for (let it = 0; it < 170 && live.length && px.length < 5200; it++) {
    const pull = new Map();
    for (const a of live) { if (a.d > 1.7) continue; const v = pull.get(a.n) || [0, 0, 0]; const l = Math.sqrt(a.d) || 1; v[0] += (a.p[0] - px[a.n]) / l; v[1] += (a.p[1] - py[a.n]) / l; v[2] += (a.p[2] - pz[a.n]) / l; pull.set(a.n, v); }
    const born = [];
    for (const [i, v] of pull) {
      if (kids[i] > 2) continue; let l = Math.hypot(...v) || 1; let d = v.map(q => q / l); const p = parent[i];
      if (p >= 0) { const q = [px[i] - px[p], py[i] - py[p], pz[i] - pz[p]], m = Math.hypot(...q) || 1; d = d.map((e, k) => e + q[k] / m * (plum ? 0.30 : 0.75)); }   // keep momentum: smooth limbs (a plum's are angular)
      const jag = plum ? 0.22 : 0.10; d[0] += G() * jag; d[1] += G() * jag + 0.02; d[2] += G() * jag; l = Math.hypot(...d) || 1;
      born.push(add(px[i] + d[0] / l * STEP, py[i] + d[1] / l * STEP, pz[i] + d[2] / l * STEP, i));
    }
    if (!born.length) break; for (const i of born) look(i);
    live = live.filter(a => a.d > 0.085 * 0.085); for (const a of live) a.age = (a.age || 0) + 1; live = live.filter(a => a.age < 120);
  }
  const core = px.length;
  // Plum: long straight shoots (the year's whips) rising almost vertically from the upper limbs.
  if (plum) for (let i = Math.floor(core * 0.25); i < core && px.length < MAX_SEGS - 16; i++) if (kids[i] < 2 && py[i] > 1.0 && R() < 0.30) {
    let p = i; const tilt = [G() * 0.18, 1, G() * 0.12], L = 4 + Math.floor(R() * 7);
    for (let k = 0; k < L; k++) p = add(px[p] + tilt[0] * 0.045 + G() * 0.003, py[p] + 0.045, pz[p] + tilt[2] * 0.045 + G() * 0.003, p);
  }
  // Fine twigs.
  for (let i = Math.floor(core * 0.2); i < core && px.length < MAX_SEGS - 4; i++) if (kids[i] < 2 && R() < (plum ? 0.30 : 0.45)) {
    let p = i, d = [G(), G() * 0.8 + 0.25, G()], l = Math.hypot(...d) || 1; d = d.map(q => q / l);
    for (let k = 0; k < 2; k++) { p = add(px[p] + d[0] * 0.034 + G() * 0.006, py[p] + d[1] * 0.034, pz[p] + d[2] * 0.034 + G() * 0.006, p); }
  }
  const N = px.length, rad = new Float32Array(N), dist = new Float32Array(N), E = 2.35;
  for (let i = N - 1; i >= 0; i--) { rad[i] = rad[i] > 0 ? Math.pow(rad[i], 1 / E) : 0.0034; if (parent[i] >= 0) rad[parent[i]] += Math.pow(rad[i], E); }
  let top = 0; for (let i = 1; i < N; i++) { const p = parent[i]; dist[i] = dist[p] + Math.hypot(px[i] - px[p], py[i] - py[p], pz[i] - pz[p]); top = Math.max(top, dist[i]); }
  const k = Math.min(1, 0.135 / rad[0]); const T = d => 5.4 * Math.pow(d / top, 0.86);   // seconds: quick at the root, unhurried at the tips

  const segs = new Float32Array(MAX_SEGS * 12); let m = 0;
  for (let i = 1; i < N && m < MAX_SEGS; i++, m++) { const p = parent[i], r1 = Math.max(0.0028, rad[i] * k), r0 = Math.min(rad[p] * k, r1 * 1.22); segs.set([px[p], py[p], pz[p], r0, px[i], py[i], pz[i], r1, T(dist[p]), T(dist[i]), dist[i], R()], m * 12); }
  const bl = new Float32Array(MAX_BLOSSOMS * 12), spots = []; for (let i = 1; i < N; i++) if (rad[i] * k < 0.0105 && py[i] > (plum ? 0.8 : 1.0)) spots.push(i);
  // Ume flowers sit singly and tight on the twig; cherries hang in loose clusters.
  const per = Math.min(plum ? 1.8 : 2.7, MAX_BLOSSOMS / Math.max(1, spots.length)); let b = 0;
  for (const i of spots) { const c = Math.floor(per) + (R() < per % 1 ? 1 : 0); for (let q = 0; q < c && b < MAX_BLOSSOMS; q++, b++) {
    const o = [G(), G(), G()], l = Math.hypot(...o) || 1, e = plum ? 0.004 + 0.008 * R() : 0.016 + 0.026 * R(); const X = [px[i] + o[0] / l * e, py[i] + o[1] / l * e, pz[i] + o[2] / l * e];
    const out = [(X[0] - C[0]) / RX, (X[1] - C[1]) / RY, (X[2] - C[2]) / RZ], depth = Math.min(1, Math.hypot(...out));
    const nn = [o[0] / l + out[0] * 0.5, o[1] / l + out[1] * 0.3 + 0.1, o[2] / l + out[2] * 0.5 - 0.35];
    bl.set([...X, T(dist[i]) + 1.1 + (plum ? 6.0 * R() : 3.6 * R() * R()), ...nn, plum ? 0.0125 + 0.004 * R() : 0.0165 + 0.0085 * R(), R(), depth, R() < (plum ? 0.32 : 0.12) ? 1 : 0, R()], b * 12);
  } }
  return { segs, nSegs: m, blossoms: bl, nBlossoms: b, center: C };
}
