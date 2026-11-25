// The cherry tree: tapered limbs as camera-facing cylinders, blossoms as five lit petals each,
// and petals on the air. Night illumination (yozakura): warm light from below, blue from the sky.
struct Seg { a: vec3f, ra: f32, b: vec3f, rb: f32, t0: f32, t1: f32, len: f32, seed: f32 };
struct Blossom { p: vec3f, birth: f32, n: vec3f, size: f32, seed: f32, depth: f32, bud: f32, seed2: f32 };
@group(0) @binding(1) var<storage, read> S: array<Seg>;
struct Petal { p: vec3f, age: f32, v: vec3f, spin: f32 };
@group(0) @binding(2) var<storage, read> B: array<Blossom>;
@group(0) @binding(3) var<storage, read> A: array<Petal>;
// Each tree has its own: grow = age, seconds into its ending, light, blossom count; kind = species
// (0 cherry, 1 plum, 2 peach, 3 sumomo), colour variety (plum: 0 white, 1 pink, 2 deep red), unused, unused.
struct TreeU { grow: vec4f, kind: vec4f };
@group(0) @binding(4) var<uniform> TU: TreeU;
fn sway(p: vec3f) -> vec3f {
  let h = max(p.y - 0.5, 0.0); let k = 0.010 * h * h; let t = U.time;
  // A limb bends with the gust, then shivers in it: the shiver is faster higher up and out of step.
  let w = windAt(p); let g = 0.5 + 0.5 * sin(t * 0.7 + p.x * 1.3); let sh = abs(w) * 0.011 * h;
  return vec3f((sin(t * 0.9 + p.y * 1.1) + 0.45 * sin(t * 2.3 + p.x * 5.0 + p.z * 3.0)) * k * (0.5 + g) + w * 0.034 * h * h + sh * sin(t * 7.3 + p.x * 6.0 + p.y * 4.0), 0.3 * k * sin(t * 1.7 + p.x * 4.0) + sh * 0.8 * sin(t * 8.9 + p.x * 9.0), k * 0.6 * sin(t * 1.1 + p.z * 4.0) + sh * sin(t * 6.1 + p.y * 7.0));
}
struct LO { @builtin(position) pos: vec4f, @location(0) u: f32, @location(1) v: f32, @location(2) wp: vec3f, @location(3) side: vec3f, @location(4) @interpolate(flat) fade: f32, @location(5) @interpolate(flat) sp: f32 };
@vertex fn vsLimb(@builtin(vertex_index) vi: u32, @builtin(instance_index) ii: u32) -> LO {
  let s = S[ii]; let age = TU.grow.x; var o: LO;
  let g = clamp((age - s.t0) / max(s.t1 - s.t0, 0.02), 0.0, 1.0); let thick = 0.22 + 0.78 * smoothstep(0.0, 4.5, age - s.t0);
  let a = s.a + sway(s.a); let b = mix(s.a, s.b, g) + sway(s.b); let q = QUAD[vi];
  let ax = b - a; let l = max(length(ax), 1e-4); let dir = ax / l; let mid = (a + b) * 0.5; let view = normalize(mid - camPos());
  let side = normalize(cross(dir, view)); let t = q.y * 0.5 + 0.5; let r = mix(s.ra, s.rb, t) * thick;
  let p = mix(a - dir * s.ra * 0.5 * thick, b + dir * s.rb * 0.5 * thick, t) + side * q.x * r;
  o.pos = project(p); o.u = q.x; o.v = s.len + t * l; o.wp = p; o.side = side; o.fade = 1.0; o.sp = TU.kind.x; if (g <= 0.0) { o.pos = vec4f(2, 2, 2, 1); } return o;
}
@fragment fn fsLimb(i: LO) -> @location(0) vec4f {
  let view = normalize(camPos() - i.wp); let n0 = normalize(i.side * i.u + view * sqrt(max(1.0 - i.u * i.u, 0.0)));
  // Cherry bark: dark, satiny, with pale horizontal lenticels.
  let around = asin(clamp(i.u, -0.999, 0.999)); let grain = gnoise(vec2f(around * 5.0, i.v * 60.0)); let len = smoothstep(0.66, 0.80, gnoise(vec2f(around * 2.2, i.v * 95.0)));
  let n = normalize(n0 + vec3f(0.0, (grain - 0.5) * 0.7, 0.0));
  var alb = mix(vec3f(0.040, 0.027, 0.025), vec3f(0.15, 0.11, 0.10), len * 0.6) * (0.35 + 1.2 * grain);
  if (i.sp > 0.5 && i.sp < 1.5) {
    // Ume bark: near black, rough and fissured, with grey-green lichen in patches on old wood.
    let fis = gnoise(vec2f(around * 9.0, i.v * 34.0)); let lich = smoothstep(0.62, 0.78, gnoise(vec2f(around * 3.0 + 7.0, i.v * 22.0)));
    alb = vec3f(0.030, 0.024, 0.022) * (0.4 + 1.3 * fis); alb = mix(alb, vec3f(0.20, 0.23, 0.18) * (0.7 + 0.5 * fis), lich * 0.55);
  }
  // Snow lies along the tops of the limbs while it falls (U.pane.z is how much has settled).
  let cap = smoothstep(0.62, 0.92, n0.y) * smoothstep(0.02, 0.25, U.pane.z) * smoothstep(0.35, 0.65, gnoise(vec2f(around * 4.0, i.v * 40.0)) + 0.3 * n0.y);   // patchy, on what faces up
  var c = alb * lit2(i.wp, n, 0.05).a * vec3f(0.72, 0.80, 0.90);
  c = mix(c, vec3f(0.80, 0.84, 0.92) * lit2(i.wp, n0, 0.3).a * 0.9, cap);
  let h = normalize(view + normalize(vec3f(0.2, 0.9, 0.5))); c += vec3f(0.05, 0.06, 0.09) * pow(max(dot(n, h), 0.0), 18.0) * (0.4 + grain);   // rain-wet sheen
  return vec4f(c, 1.0);
}

struct PO { @builtin(position) pos: vec4f, @location(0) q: vec2f, @location(1) light: vec3f, @location(2) back: vec3f, @location(3) @interpolate(flat) tint: vec2f, @location(4) @interpolate(flat) sp: vec2f };
fn emitPetal(c: vec3f, along: vec3f, across: vec3f, n: vec3f, size: f32, q: vec2f, tint: vec2f, ao: f32) -> PO {
  var o: PO; let y = q.y * 0.5 + 0.5;
  let p = c + along * y * size + across * q.x * size * 0.56 + n * size * 0.16 * (q.x * q.x - 0.4) * y;   // gently cupped
  o.pos = project(p); o.q = vec2f(q.x, y); o.tint = tint; let nn = normalize(n);
  let L = lit2(c, nn, 0.35); o.light = L.a * ao; o.back = L.b * ao; return o;
}
fn basis(n: vec3f) -> mat3x3f { let up = select(vec3f(0, 1, 0), vec3f(1, 0, 0), abs(n.y) > 0.95); let t = normalize(cross(up, n)); return mat3x3f(t, cross(n, t), n); }
@vertex fn vsBlossom(@builtin(vertex_index) vi: u32, @builtin(instance_index) ii: u32) -> PO {
  let b = B[ii / 5u]; let k = f32(ii % 5u); let age = TU.grow.x; let q = QUAD[vi]; var o: PO;
  let u = clamp((age - b.birth) / 1.5, 0.0, 1.0); let open = 1.0 - pow(1.0 - u, 3.0); let pop = open * (1.0 + 0.25 * sin(u * 3.1416) * (1.0 - u));
  let full = mix(1.0, 0.30, b.bud);                                   // some stay buds
  let M = basis(normalize(b.n)); let a = (k + b.seed) * 1.2566371 + 0.5 * b.seed2; let cup = mix(1.35, 0.30 + 0.25 * b.seed2, open * full) + 0.30 * abs(windAt(b.p)) * sin(U.time * 13.0 + b.seed * 40.0 + k);
  let rim = M[0] * cos(a) + M[1] * sin(a); let along = normalize(rim * cos(cup) + M[2] * sin(cup)); let across = normalize(cross(M[2], rim)); let n = normalize(cross(across, along));
  var c = b.p + sway(b.p); var al = along; var ac = across; var nn = n; var size = b.size * pop * mix(1.0, 0.62, b.bud);
  // The end: petals let go one by one and ride the gust away.
  let h = rnd(ii * 3u + 17u); let rel = TU.grow.y - 0.4 - 5.2 * h;
  if (rel > 0.0) {
    let s1 = rnd(ii * 3u + 18u); let s2 = rnd(ii * 3u + 19u); let blow = 1.0 - exp(-rel * 1.4);
    c += vec3f((0.35 + 0.9 * s1) * rel * U.wind.y * blow + 0.20 * sin(rel * 2.3 + s2 * 6.3), 0.16 * sin(rel * 1.9 + s1 * 6.3) * blow - rel * rel * 0.035 - rel * 0.10 * s2, -0.16 * rel * s2 + 0.14 * sin(rel * 2.7 + s1 * 9.0));
    let w = rel * (2.0 + 3.0 * s1) + s2 * 6.3; let cw = cos(w); let sw = sin(w); al = normalize(al * cw + nn * sw); nn = normalize(cross(ac, al)); size *= 1.0 - smoothstep(4.5, 7.0, rel);
  }
  o = emitPetal(c, al, ac, nn, size, q, vec2f(b.seed2, b.bud), mix(0.20, 1.0, smoothstep(0.25, 1.0, b.depth)) * (0.72 + 0.5 * vnoise(b.p.xy * 5.0 + b.p.z * 3.0)));
  o.sp = TU.kind.xy; if (u <= 0.0 || size < 1e-4) { o.pos = vec4f(2, 2, 2, 1); } return o;
}
@vertex fn vsFall(@builtin(vertex_index) vi: u32, @builtin(instance_index) ii: u32) -> PO {
  let a = A[ii]; var o: PO; let d = rnd(ii * 5u + 4u); let b = rnd(ii * 5u + 2u);
  let w = a.spin; let y = a.spin * (0.35 + 0.3 * d) + b * 6.3;
  let al = vec3f(cos(y) * cos(w), sin(w), sin(y) * cos(w)); let ac = normalize(vec3f(-sin(y), 0.15, cos(y))); let nn = normalize(cross(ac, al));
  let s = 0.021 * smoothstep(0.0, 0.4, a.age) * (1.0 - smoothstep(12.5, 14.0, a.age)) * (1.0 - smoothstep(7.0, 9.0, U.grow.y));
  o = emitPetal(a.p, al, ac, nn, s, QUAD[vi], vec2f(d, 0.0), 1.0); o.sp = vec2f(0.0);
  if (a.age <= 0.0 || s < 1e-4) { o.pos = vec4f(2, 2, 2, 1); } return o;
}
// Ume: five round petals, no notch, slightly cupped and waxy. White ume has a faint green-white base;
// pink ume flushes deeper toward the edge; kōbai is a deep crimson-pink throughout.
fn plumPetal(i: PO, ff: bool) -> vec4f {
  let x = abs(i.q.x); let y = i.q.y;
  let r = length(vec2f(x / 0.95, (y - 0.52) / 0.50)); let e = 1.0 - r; let a = smoothstep(-0.06, 0.04, e) * step(0.02, y); if (a < 0.03) { discard; }
  let v = i.sp.y; let tip = smoothstep(0.15, 0.95, y);
  var alb = vec3f(0.97, 0.97, 0.94);
  if (v > 0.5 && v < 1.5) { alb = mix(vec3f(1.0, 0.86, 0.86), vec3f(0.98, 0.52, 0.58), tip * (0.5 + 0.5 * i.tint.x)); }
  else if (v > 1.5) { alb = mix(vec3f(0.80, 0.16, 0.30), vec3f(0.70, 0.08, 0.22), tip); }
  else { alb = mix(vec3f(0.90, 0.95, 0.86), alb, smoothstep(0.0, 0.30, y)); }
  let vein = 1.0 - 0.04 * smoothstep(0.6, 1.0, abs(sin(atan2(i.q.x, y + 0.1) * 18.0))) * smoothstep(0.1, 0.6, y);
  let thin = smoothstep(-0.02, 0.16, -e + 0.16);
  let front = select(i.back, i.light, ff); let behind = select(i.light, i.back, ff);
  var c = alb * vein * (front * 0.85 + behind * vec3f(0.55, 0.45, 0.45) * (0.6 + 0.5 * thin));
  c += vec3f(0.06, 0.06, 0.07) * (front.r + front.g) * (1.0 - r) * 0.6;   // waxy sheen
  return vec4f(c, a);
}
@fragment fn fsPetal(i: PO, @builtin(front_facing) ff: bool) -> @location(0) vec4f {
  let x = abs(i.q.x); let y = i.q.y;
  if (i.sp.x > 0.5 && i.sp.x < 1.5) { return plumPetal(i, ff); }
  // Somei-yoshino: an oval petal with a small V cut at its tip.
  let w = 0.92 * pow(sin(3.14159 * clamp(pow(y, 0.72), 0.0, 1.0) * 0.93 + 0.06), 0.75); let notch = 0.97 - 0.15 * (1.0 - smoothstep(0.0, 0.30, x));
  let e = min(w - x, (notch - y) * 2.0); let a = smoothstep(-0.05, 0.05, e); if (a < 0.03) { discard; }
  // Almost white, faintly pink, flushing pink toward the base; the heart reddens as a flower ages (tint.x).
  let pink = mix(vec3f(1.0, 0.95, 0.95), vec3f(1.0, 0.86, 0.89), i.tint.x); var alb = mix(vec3f(0.98, 0.70, 0.78), pink, smoothstep(0.0, 0.38, y));
  alb = mix(alb, vec3f(0.93, 0.45, 0.58), i.tint.y * 0.7);
  // Fine veins fanning from the base, a little crinkle, and thinner (more see-through) toward the edge.
  let fan = atan2(i.q.x, y + 0.18); let vein = 1.0 - 0.06 * smoothstep(0.55, 1.0, abs(sin(fan * 26.0))) * smoothstep(0.1, 0.5, y);
  let crinkle = 0.96 + 0.08 * gnoise(vec2f(i.q.x * 9.0, y * 7.0) + i.tint.x * 30.0);
  let thin = smoothstep(-0.02, 0.18, -e + 0.18);
  let heart = 1.0 - smoothstep(0.02, 0.16, length(vec2f(i.q.x * 0.5, y)));
  let front = select(i.back, i.light, ff); let behind = select(i.light, i.back, ff);
  var c = alb * vein * crinkle * (front * 0.80 + behind * vec3f(0.60, 0.42, 0.44) * (0.8 + 0.6 * thin));   // thin petals glow with light from behind
  c = mix(c, mix(vec3f(0.62, 0.22, 0.22), vec3f(0.48, 0.07, 0.10), i.tint.x) * (front + behind) * 0.45, heart * 0.85);
  return vec4f(c, a);
}
// ---- the stamens: about thirty fine white filaments with yellow anthers round a green style, in the cup
// of each open flower. One quad per flower facing along its axis, drawn as rays.
struct SO { @builtin(position) pos: vec4f, @location(0) q: vec2f, @location(1) light: vec3f, @location(2) @interpolate(flat) k: vec2f, @location(3) @interpolate(flat) sp: f32 };
@vertex fn vsStamen(@builtin(vertex_index) vi: u32, @builtin(instance_index) ii: u32) -> SO {
  let b = B[ii]; let age = TU.grow.x; var o: SO; let u = clamp((age - b.birth - 0.5) / 1.5, 0.0, 1.0); let plum = TU.kind.x > 0.5 && TU.kind.x < 1.5;
  if (u <= 0.0 || b.bud > 0.5 || TU.grow.y > 0.4 + 5.2 * rnd(ii * 15u + 17u)) { o.pos = HIDE; return o; }
  let M = basis(normalize(b.n)); let q = QUAD[vi]; let size = b.size * select(0.52, 0.95, plum) * u;   // ume stamens are long and showy
  let c = b.p + sway(b.p) + M[2] * b.size * 0.16 * u; let p = c + (M[0] * q.x + M[1] * q.y) * size;
  o.pos = project(p); o.q = q; o.light = lit2(c, normalize(b.n), 0.6).a; o.k = vec2f(b.seed2, b.seed); o.sp = select(0.0, 1.0, plum); return o;
}
@fragment fn fsStamen(i: SO) -> @location(0) vec4f {
  let r = length(i.q); let th = atan2(i.q.y, i.q.x) + i.k.y * 6.3; let n = 30.0;
  let ray = abs(fract(th * n / 6.2832) - 0.5); let len = select(0.78, 0.62, i.sp > 0.5) + select(0.18, 0.36, i.sp > 0.5) * fract(sin(floor(th * n / 6.2832) * 91.7 + i.k.y * 13.0) * 4375.5);
  let fil = (1.0 - smoothstep(0.03, 0.07 + 0.05 * r, ray * (0.6 + r))) * step(0.12, r) * step(r, len);
  let anther = 1.0 - smoothstep(0.04, 0.085, length(vec2f(ray * (0.4 + r) * 2.0, r - len)));
  let style = 1.0 - smoothstep(0.08, 0.13, r);
  let a = max(max(fil * 0.8, anther), style); if (a < 0.05) { discard; }
  var alb = vec3f(0.95, 0.88, 0.88); alb = mix(alb, select(mix(vec3f(0.95, 0.80, 0.30), vec3f(0.55, 0.25, 0.15), i.k.x), vec3f(1.0, 0.82, 0.22), i.sp > 0.5), anther); alb = mix(alb, vec3f(0.55, 0.65, 0.25), style);
  return vec4f(alb * i.light * 0.9, a);
}
