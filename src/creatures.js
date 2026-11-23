// What moves by itself: birds and butterflies. Few enough to think about on the CPU.
// Each writes 16 floats: position, size, forward, phase, up, seed, pose[4] (see life.wgsl).
const TAU = Math.PI * 2, clamp = (x, a, b) => Math.max(a, Math.min(b, x)), mix = (a, b, t) => a + (b - a) * t;
const ss = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const len = v => Math.hypot(v[0], v[1], v[2]), norm = v => { const l = len(v) || 1; return [v[0] / l, v[1] / l, v[2] / l]; };
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
export const EYE = [0.12, 1.62, 0];
// A place on the pane (0..1) at depth z, and back again.
export const unproject = (u, v, z, asp) => [EYE[0] + ((u * 2 - 1) * asp * 0.59 + 0.02) * z, EYE[1] + ((1 - v * 2) - 0.06) * 0.59 * z, z];
export const toPane = (p, asp) => { const z = Math.max(0.05, p[2]); return [0.5 + ((p[0] - EYE[0]) - 0.02 * z) / (asp * 0.59 * z) / 2, 0.5 - (0.06 + (p[1] - EYE[1]) / (0.59 * z)) / 2]; };
function rng(seed) { let s = seed >>> 0 || 1; return () => { s = s + 0x6d2b79f5 | 0; let t = Math.imul(s ^ s >>> 15, 1 | s); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
function put(out, i, p, size, f, phase, u, seed, pose) { const r = cross(u, f); const l = len(r) || 1; const rr = [r[0] / l, r[1] / l, r[2] / l], uu = cross(f, rr); out.set([p[0], p[1], p[2], size, f[0], f[1], f[2], phase, uu[0], uu[1], uu[2], seed, ...pose], i * 16); }

// ---- a few ōruri. Each flies from perch to perch (the street lanterns, the tree, the ground) in the
// bounding flight of small birds: bursts of wingbeats, then a short dive with the wings shut. Perched, it
// looks about in quick turns of the head, and on the ground it hops.
export function birds(n, asp, seed) {
  const R = rng(seed), out = new Float32Array(n * 16);
  const offscreen = () => unproject(R() < 0.5 ? -0.2 : 1.2, 0.05 + 0.3 * R(), 2.6 + 2.5 * R(), asp);
  const B = Array.from({ length: n }, (_, i) => ({ mode: 'wait', born: 0.6 + i * 0.7 + R() * 1.0, p: offscreen(), from: null, to: null, spot: null, t: 0, T: 1, ph: R() * TAU, yaw: R() * TAU, look: 0, lookTo: 0, nextLook: 0, hop: 0, gap: 2, rest: 0, seed: i % 3 === 1 ? 0.1 + 0.15 * R() : 0.35 + 0.65 * R(), s: 0.16 + 0.015 * R(), f: [0, 0, 1], up: [0, 1, 0] }));
  const fly = (b, to, ctx) => { b.mode = 'fly'; b.from = b.p.slice(); b.to = to; b.t = 0; const d = Math.hypot(to.at[0] - b.p[0], to.at[1] - b.p[1], to.at[2] - b.p[2]); b.T = 0.7 + d / 2.6; };
  const bez = (a, b, c, d, t) => { const s = 1 - t; return [0, 1, 2].map(k => a[k] * s * s * s + b[k] * 3 * s * s * t + c[k] * 3 * s * t * t + d[k] * t * t * t); };
  const path = (b, ctx, t) => { const A = b.from, D = b.to.at, dist = Math.hypot(D[0] - A[0], D[2] - A[2]); return bez(A, [A[0], A[1] + 0.35 + 0.15 * dist, A[2]], [D[0], D[1] + 0.45 + 0.1 * dist, D[2]], D, t); };
  return {
    n, out, list: B, get seated() { return B.filter(b => b.mode === 'sit').length; },
    startle(p, r, ctx) { for (const b of B) if (b.mode === 'sit' && Math.hypot(b.p[0] - p[0], b.p[1] - p[1]) < r) { const s = ctx.perch(R, b.spot); if (s) fly(b, s, ctx); } },
    step(dt, age, end, ctx) {
      B.forEach((b, i) => {
        if (b.mode === 'wait') { if (age < b.born) { out[i * 16 + 3] = 0; return; } const s = ctx.perch(R, null); if (!s) { out[i * 16 + 3] = 0; return; } fly(b, s, ctx); }
        if (end > 0 && b.mode !== 'out' && end > b.seed * 2) { b.mode = 'fly'; b.from = b.p.slice(); b.to = { at: offscreen(), out: true }; b.t = 0; b.T = 2.2; b.mode = 'out'; }
        let flap = 0, fold = 0;
        if (b.mode === 'fly' || b.mode === 'out') {
          if (b.to.k && !ctx.valid(b.to)) { const s = ctx.perch(R, b.to); if (s) b.to = s; }
          if (b.to.k) b.to.at = ctx.where(b.to);
          b.t = Math.min(1, b.t + dt / b.T); const t = b.t * b.t * (3 - 2 * b.t), q = path(b, ctx, t), q2 = path(b, ctx, Math.min(1, t + 0.02));
          b.p = q; const v = [q2[0] - q[0], q2[1] - q[1] + 1e-4, q2[2] - q[2]];
          // Bounding: about 0.3 s of beats, 0.15 s shut; beating throughout the take-off and the flare to land.
          const cyc = (age * 2.2 + b.seed * 3) % 1, edge = b.t < 0.25 || b.t > 0.8; flap = edge || cyc < 0.66 ? 1 : 0; fold = flap ? 0 : 0.85;
          b.ph += dt * (edge ? 52 : 46) * flap;
          const fwd = norm([v[0], v[1] * 0.6 + (b.t > 0.82 ? 0.5 : 0), v[2]]); for (let c = 0; c < 3; c++) b.f[c] += (fwd[c] - b.f[c]) * Math.min(1, dt * 10);
          b.up = [0, 1, 0];
          if (b.t >= 1) { if (b.mode === 'out') { out[i * 16 + 3] = 0; b.mode = 'gone'; return; } b.mode = 'sit'; b.spot = b.to; b.rest = 3 + 7 * R(); b.yaw = Math.atan2(-b.p[2], 0.12 - b.p[0]) + (R() - 0.5) * 2.4; }
        } else if (b.mode === 'sit') {
          if (!ctx.valid(b.spot)) { const s = ctx.perch(R, b.spot); if (s) { fly(b, s, ctx); return; } }
          const at = ctx.where(b.spot); b.rest -= dt; fold = 1;
          if (b.spot.k === 'ground') {   // a hop now and then, a little way and a turn
            b.hop -= dt; if (b.hop < -b.gap) { b.hop = 0.22; b.gap = 1.2 + 4 * R(); const a = b.yaw; b.spot.p = [b.spot.p[0] + Math.cos(a) * 0.10, 0, b.spot.p[2] + Math.sin(a) * 0.10]; b.yaw += (R() - 0.5) * 1.6; }
          }
          const hopY = b.hop > 0 ? Math.sin(Math.PI * (1 - b.hop / 0.22)) * 0.05 : 0;
          for (let c = 0; c < 3; c++) b.p[c] += (at[c] + (c === 1 ? hopY : 0) - b.p[c]) * Math.min(1, dt * 14);
          if (age > b.nextLook) { b.lookTo = (R() - 0.5) * 1.8; b.nextLook = age + 0.4 + 1.8 * R(); } b.look += (b.lookTo - b.look) * Math.min(1, dt * 20);
          const f = norm([Math.cos(b.yaw), 0.78, Math.sin(b.yaw)]); for (let c = 0; c < 3; c++) b.f[c] += (f[c] - b.f[c]) * Math.min(1, dt * 8);
          if (b.rest < 0 && end <= 0) { const s = ctx.perch(R, b.spot); if (s) fly(b, s, ctx); else b.rest = 2; }
        } else { out[i * 16 + 3] = 0; return; }
        const fade = ss(0, 0.5, age - b.born) * (b.mode === 'out' ? 1 - ss(0.75, 1, b.t) : 1);
        put(out, i, b.p, b.s, norm(b.f), b.ph, b.up, b.seed, [flap ? 1 : 0, fold, fade, b.mode === 'sit' ? b.look : 0]);
      });
    },
  };
}

// ---- cabbage whites
export function butterflies(n, asp, seed) {
  const R = rng(seed), out = new Float32Array(n * 16), L = Array.from({ length: n }, () => ({ a: R() * 99, sx: R() * 1.7 - 0.85, z: 1.7 + 2.2 * R(), s: 0.030 + 0.012 * R(), ph: R() * TAU, r: 0.6 + R(), p: null }));
  return {
    n, out, step(dt, age, end, ctx) {
      L.forEach((b, i) => {
        const t = age - 4 - (i % 7) * 0.5; if (t <= 0) { out[i * 16 + 3] = 0; return; }
        const w = age * 0.33 * b.r + b.a, x = EYE[0] + (b.sx * asp * 0.59) * b.z + 0.5 * Math.sin(w) + 0.22 * Math.sin(w * 2.7), y = 0.86 + 0.16 * Math.sin(w * 1.9) + 0.07 * Math.sin(w * 7.3) + 0.03 * Math.sin(b.ph * 0.5) + 0.5 * ss(0, 4, end), z = b.z + 0.32 * Math.cos(w * 0.8);
        const p = [x + ctx.wind * 0.5, y, z], q = b.p || p, d = [p[0] - q[0], 0, p[2] - q[2]]; b.p = p; b.ph += dt * (15 + 6 * Math.sin(w * 3)); const f = len(d) > 1e-5 ? norm([d[0], 0.35 * len(d), d[2]]) : [1, 0, 0];
        put(out, i, p, b.s * ss(0, 1, t), f, b.ph, [0, 1, 0], b.a, [0.25 + 0.95 * (0.5 + 0.5 * Math.sin(b.ph)), 0, 1 - ss(2, 4.5, end), 0]);
      });
    },
  };
}
