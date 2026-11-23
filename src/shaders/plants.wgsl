// Plants that need no state: reeds and plumes at the water's edge, the rapeseed field, and the sheet of
// water itself. Every position comes from the instance number and the age.
const QN: i32 = 46;
fn h4(i: u32) -> vec4f { return vec4f(rnd(i * 4u), rnd(i * 4u + 1u), rnd(i * 4u + 2u), rnd(i * 4u + 3u)); }
fn breeze(p: vec3f) -> vec3f { let t = U.time; let w = windAt(p); return vec3f(w * 0.36 + 0.045 * sin(t * 0.9 + p.x * 1.7 + p.z) + abs(w) * 0.05 * sin(t * 8.0 + p.x * 9.0 + p.z * 5.0), 0.0, 0.03 * sin(t * 0.7 + p.z * 2.0 + p.x)); }
struct PV { @builtin(position) pos: vec4f, @location(0) uv: vec2f, @location(1) wp: vec3f, @location(2) front: vec3f, @location(3) back: vec3f, @location(4) @interpolate(flat) k: vec4f };
const KEY: vec3f = vec3f(0.30, 0.29, 0.30);
fn strip(vi: u32, segs: u32) -> vec2f { let q = QUAD[vi % 6u]; return vec2f(q.x, (f32(vi / 6u) + q.y * 0.5 + 0.5) / f32(segs)); }
const POOL: f32 = 0.06;
fn shoreR() -> f32 { let W = U.world[0]; return 6.2 * (1.0 - exp(-W.x * 0.34)) * (1.0 - smoothstep(0.5, 6.5, W.y)); }
// How far inside the spreading water a point of ground is.
fn poolAt(q: vec2f) -> f32 { let c = vec2f(across(U.world[0].w, 2.8), 2.9); let d = length((q - c) * vec2f(1.0, 0.62)); return shoreR() - d + 0.75 * (gnoise(q * 1.1 + 4.0) - 0.5) + 0.22 * (gnoise(q * 3.7) - 0.5); }
fn mirrorIt(p: vec3f) -> vec3f { var q = p; q.y = 2.0 * POOL - p.y; let d = max(p.y - POOL, 0.0); q.x += 0.020 * sin(p.z * 3.0 + d * 19.0 + U.time * 1.7) * min(1.0, d * 2.0); return q; }

// ---- reeds
struct Root { p: vec3f, g: f32, s: f32 };
fn reedRoot(id: u32, clumps: u32, spread: f32) -> Root {
  let c = id % clumps; let hc = h4(c + 900u); let hi = h4(id + 7000u); let s0 = select(1.0, -1.0, U.world[0].w <= 0.0);
  let side = select(-s0, s0, c % 3u != 0u); let sx = side * mix(select(0.62, 0.40, c % 3u != 0u), 1.10, hc.x); let z = mix(1.75, 5.4, hc.y * hc.y);
  let a = hi.x * 6.283; let r = spread * sqrt(hi.y); let p = vec3f(across(sx, z) + cos(a) * r, 0.0, z + sin(a) * r);
  let W = U.world[0]; let d = abs(p.x - across(W.w, z)); let t = W.x - 0.4 - d * 0.45 - 1.4 * hi.z;
  let u = clamp(t / 3.6, 0.0, 1.0); let out = 1.0 - smoothstep(0.6 + 2.6 * hi.w, 3.4 + 2.8 * hi.w, W.y);
  return Root(p, (1.0 - pow(1.0 - u, 2.6)) * out, hc.z);
}
fn leafAt(r: Root, h: vec4f, t0: f32) -> vec3f {
  let t = t0 * r.g; let H = mix(0.62, 1.28, h.x); let a = h.y * 6.283; let lean = mix(0.18, 0.62, h.z);
  var p = r.p + vec3f(cos(a) * lean * H * t * t, H * (t - 0.30 * lean * t * t * t), sin(a) * lean * H * t * t * 0.8);
  p += breeze(p) * t * t * H; return p;
}
@vertex fn vsReed(@builtin(vertex_index) vi: u32, @builtin(instance_index) i0: u32) -> PV {
  let N = 1300u; let ii = i0 % N; let mir = i0 >= N; var o: PV; let h = h4(ii + 300u); let r = reedRoot(ii, 34u, 0.20); let q = strip(vi, 7u);
  var p = leafAt(r, h, q.y); let tn = normalize(leafAt(r, h, q.y + 0.03) - p + vec3f(0.0, 1e-4, 0.0)); let view = normalize(p - camPos());
  let face = normalize(cross(tn, vec3f(cos(h.w * 6.283), 0.1, sin(h.w * 6.283)))); let sd = normalize(mix(face, normalize(cross(tn, view)), 0.45));
  let w = 0.0105 * (0.55 + 0.9 * h.w) * pow(max(1.0 - q.y, 0.0), 0.65) * (0.5 + 0.5 * smoothstep(0.0, 0.15, q.y)); p += sd * q.x * max(w, 0.0012 * p.z * (1.0 - q.y));
  let n = normalize(cross(sd, tn)); let L = lit3(p, n, 0.45, KEY);
  o.uv = q; o.wp = p; o.front = L.a; o.back = L.b; o.k = vec4f(h.x, r.s, select(1.0, 0.42, mir), h.w); o.pos = project(select(p, mirrorIt(p), mir)); if (r.g < 0.01) { o.pos = HIDE; } return o;
}
@fragment fn fsReed(i: PV, @builtin(front_facing) ff: bool) -> @location(0) vec4f {
  let f = select(i.back, i.front, ff); let b = select(i.front, i.back, ff); let mid = 1.0 - smoothstep(0.0, 0.22, abs(i.uv.x));
  let alb = mix(vec3f(0.035, 0.085, 0.062), vec3f(0.20, 0.18, 0.085), smoothstep(0.35, 1.05, i.uv.y * 0.75 + i.k.x * 0.35)) * (0.72 + 0.5 * mid) * (0.45 + 0.9 * i.k.w);
  let c = alb * (f + b * vec3f(0.55, 0.60, 0.30)) * mix(0.10, 1.0, smoothstep(0.0, 0.65, i.uv.y)) * i.k.z; return vec4f(c, 1.0);
}
// ---- plumes: many fine hairs hanging from the last part of a tall stalk
fn stalkAt(r: Root, h: vec4f, t0: f32) -> vec3f {
  let t = t0 * r.g; let H = mix(1.30, 2.02, h.x); let dx = (h.y - 0.5) * 0.5;
  var p = r.p + vec3f((dx + 0.12 * sign(h.y - 0.5)) * H * t * t * t, H * (t - 0.04 * t * t), (h.z - 0.5) * 0.3 * H * t * t); p += breeze(p) * t * t * H * 0.62; return p;
}
@vertex fn vsPlume(@builtin(vertex_index) vi: u32, @builtin(instance_index) i0: u32) -> PV {
  var o: PV; let N = 64u * u32(QN); let i1 = i0 % N; let mir = i0 >= N; let si = i1 / u32(QN); let k = i1 % u32(QN); let h = h4(si + 5200u); let r = reedRoot(si * 5u + 3u, 34u, 0.26); if (r.g < 0.01) { o.pos = HIDE; return o; } let q = strip(vi, 4u);
  var p: vec3f; var tn: vec3f; var w: f32; var tip = 0.0;
  if (k == 0u) { p = stalkAt(r, h, q.y); tn = stalkAt(r, h, q.y + 0.03) - p; w = 0.0042 * (1.0 - 0.55 * q.y); }
  else {
    let e = h4(i1 * 3u + 11u); let s = 0.76 + 0.24 * f32(k) / f32(QN); let a0 = stalkAt(r, h, s); let ax = normalize(stalkAt(r, h, s + 0.02) - a0 + vec3f(0.0, 1e-4, 0.0));
    let open = smoothstep(0.72, 1.0, r.g); let an = e.x * 6.283; let dr = sign(h.y - 0.5); let out = vec3f(cos(an) * 0.65 + dr * 0.55, 0.15, sin(an) * 0.65); let l = mix(0.13, 0.27, e.y) * (1.15 - 0.5 * (s - 0.76) / 0.24);
    let y = q.y; p = a0 + (ax * y * 0.85 + out * 0.50 * open * pow(y, 1.4) - vec3f(0.0, 0.42, 0.0) * open * y * y) * l + breeze(a0 + vec3f(e.z, 0.0, e.w)) * 0.30 * y * y;
    let y2 = y + 0.05; tn = a0 + (ax * y2 * 0.85 + out * 0.50 * open * pow(y2, 1.4) - vec3f(0.0, 0.42, 0.0) * open * y2 * y2) * l - p; w = 0.0027 * (1.0 - 0.6 * y); tip = y;
  }
  tn = normalize(tn + vec3f(0.0, 1e-5, 0.0)); let sd = normalize(cross(tn, normalize(p - camPos()))); let wide = max(w, 0.00062 * p.z); p += sd * q.x * wide;
  let L = lit3(p, normalize(cross(sd, tn)), 0.9, KEY); o.uv = q; o.wp = p; o.front = L.a; o.back = L.b; o.k = vec4f(w / wide * select(1.0, 0.80, k > 0u), h.w, select(1.0, 0.42, mir), select(0.0, 1.0, k > 0u)); o.pos = project(select(p, mirrorIt(p), mir));
  if (r.g < 0.01 || (k > 0u && r.g < 0.5)) { o.pos = HIDE; } return o;
}
@fragment fn fsPlume(i: PV) -> @location(0) vec4f {
  let L = i.front + i.back; let alb = mix(vec3f(0.34, 0.32, 0.16), mix(vec3f(0.95, 0.80, 0.62), vec3f(0.92, 0.86, 0.86), i.k.y), i.k.w); let d = 0.35 + 0.65 * smoothstep(1.0, 4.5, i.wp.z); return vec4f(alb * (i.front * 0.22 + i.back * 0.34 + L * 0.10) * mix(0.5, 0.65 + 0.55 * i.uv.y, i.k.w) * d * i.k.z, i.k.x);
}
// ---- the water that spreads over the street
struct WV { @builtin(position) pos: vec4f, @location(0) wp: vec3f };
@vertex fn vsPool(@builtin(vertex_index) vi: u32) -> WV { var o: WV; let q = QUAD[vi]; let z = mix(1.25, 11.0, q.y * 0.5 + 0.5); o.wp = vec3f(across(q.x * 1.35, z), POOL, z); o.pos = project(o.wp); return o; }
@fragment fn fsPool(i: WV) -> @location(0) vec4f {
  let q0 = i.wp.xz; let m = poolAt(q0); let q = q0; let a0 = smoothstep(0.0, 0.5, m) * (1.0 - smoothstep(7.0, 11.0, q0.y)); if (a0 < 0.004) { discard; }
  let t = U.time; let e = 0.02; let far = 1.0 / (0.6 + 0.35 * q.y);
  let f0 = gnoise(q * vec2f(2.2, 3.6) + vec2f(t * 0.22, -t * 0.31)) + 0.5 * gnoise(q * vec2f(6.0, 9.0) - vec2f(t * 0.4, t * 0.2)); let fx = gnoise((q + vec2f(e, 0.0)) * vec2f(2.2, 3.6) + vec2f(t * 0.22, -t * 0.31)) + 0.5 * gnoise((q + vec2f(e, 0.0)) * vec2f(6.0, 9.0) - vec2f(t * 0.4, t * 0.2)); let fz = gnoise((q + vec2f(0.0, e)) * vec2f(2.2, 3.6) + vec2f(t * 0.22, -t * 0.31)) + 0.5 * gnoise((q + vec2f(0.0, e)) * vec2f(6.0, 9.0) - vec2f(t * 0.4, t * 0.2));
  var g = vec2f(fx - f0, fz - f0) / e * 0.020 * (1.0 + 3.0 * abs(windAt(i.wp)));
  // Rings where rain lands.
  for (var k = 0; k < 2; k++) { let s = 1.6 + f32(k) * 0.9; let c = floor(q * s + f32(k) * 5.3); let h = hash22(c + f32(k) * 31.0); let u = fract(t * 0.55 + h.x); let d = fract(q * s + f32(k) * 5.3) - 0.5 - (h - 0.5) * 0.5; let l = length(d); g += d / max(l, 0.01) * sin((l - u * 0.5) * 60.0) * exp(-abs(l - u * 0.5) * 20.0) * (1.0 - u) * step(0.45, h.y) * 0.10; }
  let n = normalize(vec3f(-g.x, 1.0, -g.y)); let v = normalize(i.wp - camPos()); let r = reflect(v, n); let fr = 0.04 + 0.96 * pow(1.0 - max(dot(-v, n), 0.0), 4.0);
  var c = mix(vec3f(0.055, 0.060, 0.105), vec3f(0.008, 0.015, 0.045), clamp(r.y * 1.6, 0.0, 1.0));
  c += vec3f(0.60, 0.32, 0.17) * exp(-dot(r.xy - vec2f(0.03, 0.03), r.xy - vec2f(0.03, 0.03)) * 26.0);
  for (var k = 0; k < 14; k++) { let d = U.lamps[k * 2].xyz - i.wp; let l2 = dot(d, d); let s = max(dot(r, d / sqrt(l2)), 0.0); let rr = U.lamps[k * 2].w; let pw = 2.2 * l2 / (rr * rr + l2 * 0.004); c += U.lamps[k * 2 + 1].rgb * 3.4 * pow(s, pw); }
  if (U.grow.z > 0.0) { let d = U.treePos.xyz - i.wp; let s = max(dot(r, normalize(d)), 0.0); c += vec3f(1.0, 0.66, 0.70) * U.grow.z * 0.5 * pow(s, 22.0); }
  let rim = smoothstep(0.0, 0.10, m) * (1.0 - smoothstep(0.10, 0.34, m));
  let a = a0 * mix(0.50, 0.94, fr) ; return vec4f((c * (0.30 + 0.75 * fr) + vec3f(0.10, 0.10, 0.12) * rim * 0.5) * a0, a);
}
// ---- the rapeseed field
struct Stem { p: vec3f, g: f32, H: f32, d: f32 };
fn stemRoot(id: u32) -> Stem {
  let h = h4(id + 21000u); let z = 1.5 + 5.6 * pow(h.y, 1.55); let sx = mix(-1.14, 1.14, h.x); let p = vec3f(across(sx, z), 0.0, z); let W = U.world[2];
  let d = length(vec2f(p.x - across(W.w, z), (z - 2.6) * 0.8)); let t = W.x - 0.2 - d * 0.62 - 0.7 * h.z; let u = clamp(t / 2.4, 0.0, 1.0);
  let out = 1.0 - smoothstep(0.4 + 2.6 * h.w, 3.2 + 3.2 * h.w, W.y); let patchy = 0.72 + 0.5 * gnoise(p.xz * 0.9 + 9.0);
  // A path is left open through the middle, and the flowers stand in drifts.
  let mid = smoothstep(0.30, 0.85, abs(p.x - 0.15 - 0.25 * sin(z * 0.9)) / (0.35 + 0.18 * z)); let drift = gnoise(p.xz * vec2f(0.85, 0.65) + 20.0) + 0.25 * (gnoise(p.xz * 2.6) - 0.5);
  let keep = step(0.38 + 0.30 * (1.0 - mid) + 0.10 * h.w, drift + 0.10 * smoothstep(0.5, 1.0, abs(sx)));
  return Stem(p, keep * (1.0 - pow(1.0 - u, 2.4)) * out, mix(0.50, 0.98, h.z) * patchy * mix(0.80, 1.08, smoothstep(1.5, 4.0, z)), t);
}
fn stemAt(s: Stem, id: u32, t0: f32) -> vec3f {
  let t = t0 * s.g; let a = rnd(id + 55u) * 6.283; let b = 0.10 + 0.14 * rnd(id + 56u); var p = s.p + vec3f(cos(a) * b * t * t, t, sin(a) * b * t * t) * s.H; p += breeze(p) * t * t * s.H * 1.15; return p;
}
@vertex fn vsStem(@builtin(vertex_index) vi: u32, @builtin(instance_index) id: u32) -> PV {
  var o: PV; let s = stemRoot(id); if (s.g < 0.02) { o.pos = HIDE; return o; } var p: vec3f; var tn: vec3f; var w: f32; var sd: vec3f; var q: vec2f; var leaf = 0.0;
  if (vi >= 96u) {
    // Seed pods (siliques) on short stalks below the flowers: thin, 5-9 cm, angled up and out.
    let k = (vi - 96u) / 24u; q = strip((vi - 96u) % 24u, 4u); let e = h4(id * 5u + k + 81000u); let b = stemAt(s, id, 0.62 + 0.07 * f32(k) + 0.04 * e.x); let a = e.y * 6.283 + f32(k) * 2.4;
    let dir = normalize(vec3f(cos(a) * 0.55, 1.0, sin(a) * 0.55)); let l = mix(0.05, 0.09, e.z) * smoothstep(0.7, 1.0, s.g); p = b + dir * q.y * l + breeze(b) * 0.2 * q.y; tn = dir; sd = normalize(cross(tn, p - camPos())); w = max(0.0016 * sin(3.1416 * min(q.y * 1.1 + 0.05, 1.0)), 0.0006 * p.z); leaf = 0.5;
  } else if (vi < 24u) { q = strip(vi, 4u); p = stemAt(s, id, q.y); tn = normalize(stemAt(s, id, q.y + 0.04) - p + vec3f(0.0, 1e-4, 0.0)); sd = normalize(cross(tn, p - camPos())); w = max(0.0052 * (1.0 - 0.5 * q.y), 0.0007 * p.z); }
  else {
    let k = (vi - 24u) / 24u; q = strip((vi - 24u) % 24u, 4u); let e = h4(id * 3u + k + 61000u); let b = stemAt(s, id, 0.16 + 0.24 * f32(k) + 0.1 * e.x); let a = e.y * 6.283; let l = mix(0.14, 0.26, e.z) * s.g * (1.0 - 0.18 * f32(k));
    let dir = vec3f(cos(a), 0.0, sin(a)); let y = q.y; p = b + (dir * y * (1.0 - 0.15 * y) + vec3f(0.0, 0.75 * y - 0.85 * y * y, 0.0)) * l; tn = normalize(dir + vec3f(0.0, 0.75 - 1.7 * y, 0.0)); sd = normalize(cross(tn, vec3f(0.0, 1.0, 0.0))); w = 0.034 * sin(3.1416 * clamp(pow(y, 0.8) * 0.96 + 0.03, 0.0, 1.0)) * (0.8 + 0.2 * sin(y * 26.0)); leaf = 1.0;
  }
  p += sd * q.x * w; let n = normalize(cross(sd, tn)); let L = lit3(p, n, 0.4, KEY * 0.7); let dk = shadeAt(s.p); o.uv = q; o.wp = p; o.front = L.a * dk; o.back = L.b * dk; o.k = vec4f(leaf, rnd(id + 9u), smoothstep(0.05, 0.55, p.y), 0.0); o.pos = project(p); if (s.g < 0.02) { o.pos = HIDE; } return o;
}
@fragment fn fsStem(i: PV, @builtin(front_facing) ff: bool) -> @location(0) vec4f {
  let f = select(i.back, i.front, ff); let b = select(i.front, i.back, ff); let alb = mix(vec3f(0.17, 0.27, 0.10), vec3f(0.10, 0.22, 0.12), i.k.x) * (0.8 + 0.4 * i.k.y) * (1.0 + 0.5 * i.k.x * (1.0 - smoothstep(0.0, 0.12, abs(i.uv.x))));
  return vec4f(alb * (f + b * vec3f(0.55, 0.62, 0.2)) * mix(0.14, 1.0, i.k.z), 1.0);
}
const FL: u32 = 20u;
fn shadeAt(p: vec3f) -> f32 { return mix(0.16, 1.0, smoothstep(1.6, 4.2, p.z)) * mix(0.45, 1.15, smoothstep(0.35, 0.65, gnoise(p.xz * 0.75 + 2.0))); }
@vertex fn vsFloret(@builtin(vertex_index) vi: u32, @builtin(instance_index) ii: u32) -> PV {
  var o: PV; let id = ii / FL; let k = ii % FL; let fk = f32(k) / f32(FL); let s = stemRoot(id); if (s.g < 0.02) { o.pos = HIDE; return o; } let e = h4(ii + 90000u); let top = stemAt(s, id, 1.0); let ax = normalize(top - stemAt(s, id, 0.92) + vec3f(0.0, 1e-4, 0.0));
  let a = f32(k) * 2.39996 + e.x; let rim = vec3f(cos(a), 0.0, sin(a)); let bud = k < 4u; let R = 0.010 + 0.052 * pow(fk, 0.7); let c = top + (ax * (0.045 - 0.175 * fk) + rim * R + vec3f(e.y, e.z, e.w) * 0.012) * smoothstep(0.5, 1.0, s.g);
  let born = s.d - 1.5 - 1.5 * (1.0 - fk) - 0.5 * e.y; let u = clamp(born / 0.9, 0.0, 1.0); let open = (1.0 - pow(1.0 - u, 3.0)) * smoothstep(0.35, 0.8, s.g);
  let n = normalize(rim * (0.35 + 0.75 * fk) + vec3f(0.0, 0.75 - 0.45 * fk, 0.0) + (e.yzw - 0.5) * 0.5 + breeze(c) * 0.4); let up = select(vec3f(0, 1, 0), vec3f(1, 0, 0), abs(n.y) > 0.95); let t1 = normalize(cross(up, n)); let t2 = cross(n, t1); let sp = e.w * 6.283; let x = t1 * cos(sp) + t2 * sin(sp); let y = cross(n, x);
  let size = select(0.0165, 0.0062, bud) * (0.85 + 0.35 * e.z) * open * max(1.0, 0.0022 * c.z / 0.0165); let q = QUAD[vi]; let cup = 0.30 * dot(q, q) - 0.15; let p = c + (x * q.x + y * q.y + n * cup) * size;
  let L = lit3(p, n, 0.35, KEY * 0.75); let sd = shadeAt(c) * mix(0.40, 1.0, smoothstep(0.55, 1.0, (c.y - s.p.y) / max(s.H, 0.1))); o.uv = q; o.wp = p; o.front = L.a * sd; o.back = L.b * sd; o.k = vec4f(select(0.0, 1.0, bud), e.x, mix(0.75, 1.0, smoothstep(0.0, 0.5, fk)), 0.0); o.pos = project(p); if (open < 0.02) { o.pos = HIDE; } return o;
}
@fragment fn fsFloret(i: PV, @builtin(front_facing) ff: bool) -> @location(0) vec4f {
  let r = length(i.uv); let f = select(i.back, i.front, ff); let b = select(i.front, i.back, ff);
  var alb: vec3f; var a: f32;
  if (i.k.x > 0.5) {
    // A bud: a closed green-yellow ovoid, the sepals still wrapped round it.
    a = 1.0 - smoothstep(0.70, 0.85, length(i.uv * vec2f(1.0, 0.8))); alb = mix(vec3f(0.55, 0.62, 0.10), vec3f(0.80, 0.70, 0.08), smoothstep(0.1, 0.7, r));
  } else {
    // An open crucifer flower: four petals in a cross, each broad at the tip and narrowing to a thin claw at
    // the centre, with a gap between them; six stamens and a green pistil in the middle.
    let th = atan2(i.uv.y, i.uv.x) + i.k.y * 6.283; let d = th - round(th / 1.5708) * 1.5708; let al = r * cos(d); let pe = abs(r * sin(d));
    let t = clamp((al - 0.10) / 0.86, 0.0, 1.0); let w = 0.05 + 0.30 * pow(sin(3.1416 * min(t * 0.85 + 0.15, 1.0)), 0.8) * smoothstep(0.0, 0.35, t);
    a = smoothstep(0.02, -0.02, pe - w) * step(0.08, al) * smoothstep(0.98, 0.92, al);
    let vein = 1.0 - 0.10 * smoothstep(0.6, 1.0, abs(sin(atan2(pe * 3.0, al) * 7.0))) * t;
    alb = mix(vec3f(1.0, 0.80, 0.03), vec3f(1.0, 0.92, 0.16), smoothstep(0.1, 0.8, t) * (0.6 + 0.4 * i.k.y)) * vein;   // clear lemon yellow
    let mid = 1.0 - smoothstep(0.06, 0.12, r); let st = 1.0 - smoothstep(0.025, 0.05, length(vec2f(fract(th * 6.0 / 6.283) - 0.5, r - 0.12)));
    a = max(a, max(mid, st)); alb = mix(alb, vec3f(0.95, 0.72, 0.05), st); alb = mix(alb, vec3f(0.40, 0.55, 0.10), mid);
  }
  if (a < 0.04) { discard; }
  return vec4f(alb * (f * 0.85 + b * vec3f(0.85, 0.75, 0.15)) * i.k.z * vec3f(0.92, 1.0, 1.0), a);   // light through the petals is yellow; a touch less red against the warm lanterns
}
