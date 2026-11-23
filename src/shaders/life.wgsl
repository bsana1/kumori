// Birds and butterflies. No meshes: each part is a surface p(u, v) evaluated in the vertex shader, with its
// normal from finite differences after it has been bent. (Koi and cranes were removed 2026-11-23.)
struct Actor { p: vec3f, size: f32, f: vec3f, phase: f32, u: vec3f, seed: f32, pose: vec4f };
@group(0) @binding(1) var<storage, read> A: array<Actor>;
struct Sf { p: vec3f, l: vec3f };     // bent, and unbent for markings
struct AV { @builtin(position) pos: vec4f, @location(0) wp: vec3f, @location(1) n: vec3f, @location(2) lp: vec3f, @location(3) uv: vec2f, @location(4) @interpolate(flat) part: f32, @location(5) @interpolate(flat) seed: f32, @location(6) @interpolate(flat) pose: vec4f };
fn grid(v: u32, nu: u32, nv: u32) -> vec2f { let c = v / 6u; let q = QUAD[v % 6u] * 0.5 + 0.5; return vec2f((f32(c % nu) + q.x) / f32(nu), (f32(c / nu) + q.y) / f32(nv)); }
fn place(a: Actor, l: vec3f) -> vec3f { let r = cross(a.u, a.f); return a.p + (r * l.x + a.u * l.y + a.f * l.z) * a.size; }
fn turn(a: Actor, l: vec3f) -> vec3f { let r = cross(a.u, a.f); return normalize(r * l.x + a.u * l.y + a.f * l.z); }
fn fadeOut(p: vec2f, a: f32) -> f32 { return clamp(a * 1.6 - 0.6 * hash21(floor(p * 0.5)), 0.0, 1.0); }
fn bez(a: vec3f, b: vec3f, c: vec3f, d: vec3f, t: f32) -> vec3f { let s = 1.0 - t; return a * s * s * s + b * 3.0 * s * s * t + c * 3.0 * s * t * t + d * t * t * t; }

// ---- ōruri, the blue-and-white flycatcher. Length 1 = 16 cm, beak at z = 0.5. pose: flap strength, fold, fade, head turn.
// Males: cobalt above with a brighter crown, black face and breast, white belly, white at the tail's base.
// Females (seed < 0.3): olive-brown above, buff throat, pale belly.
const BIRD_V: u32 = 1248u;
fn birdWing(a: Actor, sd: f32, u0: f32, v: f32) -> vec3f {
  let u = clamp(u0, 0.0, 1.0); let fl = a.pose.x * sin(a.phase); let f2 = a.pose.x * sin(a.phase - 1.15); let k = 0.42; let A1 = 0.16 + 0.95 * fl; let A2 = A1 - 0.10 + 0.75 * f2;
  let inr = min(u, k) * 0.74; let otr = max(u - k, 0.0) * 0.74; let x = inr * cos(A1) + otr * cos(A2); let y = inr * sin(A1) + otr * sin(A2);
  let le = 0.150 + 0.05 * sin(3.14 * min(u / k, 1.0) * 0.5) - 0.30 * pow(max(u - 0.35, 0.0), 1.5); let ch = 0.265 * (1.0 - 0.25 * u) * pow(max(1.0 - u * u * u, 0.0), 0.55);
  let fly = vec3f(sd * (0.070 + x), 0.050 + y - 0.03 * v * (1.0 - u), le - v * ch);
  let fold = vec3f(sd * (0.100 + 0.022 * sin(3.14 * u) - 0.060 * u * u - 0.015 * v), 0.070 - v * 0.120 * (1.0 - 0.75 * u) - 0.040 * u, 0.12 - u * 0.62);
  return mix(fly, fold, a.pose.y);
}
fn turnHead(a: Actor, l: vec3f) -> vec3f {
  let s = 0.5 - l.z; let w = 1.0 - smoothstep(0.26, 0.40, s); let ang = a.pose.w * w; let c = vec2f(0.0, 0.5 - 0.33);
  let q = rot(ang) * (vec2f(l.x, l.z) - c) + c; return vec3f(q.x, l.y, q.y);
}
fn birdSurf(a: Actor, part: i32, u: f32, v: f32) -> Sf {
  var l: vec3f;
  switch (part) {
    case 0: { let s = clamp(u, 0.0, 1.0); let th = v * 6.2831853; let beak = 0.016 * smoothstep(0.0, 0.10, s); let head = 0.092 * exp(-pow((s - 0.225) / 0.100, 2.0) * 0.9); let body = 0.140 * exp(-pow((s - 0.57) / 0.26, 2.0)); let r = max(beak * (1.0 - smoothstep(0.1, 0.2, s)), (head + body * smoothstep(0.08, 0.34, s)) * smoothstep(0.085, 0.16, s)) * pow(max(1.0 - s * s * s * s, 0.0), 0.5);
      l = turnHead(a, vec3f(cos(th) * r * 0.92, sin(th) * r * select(1.0, 1.08, sin(th) < 0.0) + 0.036 * exp(-pow((s - 0.22) / 0.14, 2.0)) - 0.012, 0.5 - s)); }
    case 1: { let y = v * 2.0 - 1.0; l = vec3f(y * mix(0.036, mix(0.11, 0.050, a.pose.y), u), 0.0 - 0.022 * u * y * y, -0.40 - u * (0.36 - 0.04 * (1.0 - abs(y)))); }
    case 4, 5: { let sd = select(1.0, -1.0, part == 5); let th = v * 6.2831853; let r = 0.0075 * (1.0 - 0.3 * u); l = vec3f(sd * 0.030 + cos(th) * r, -0.075 - u * 0.13, 0.07 + 0.01 * u + sin(th) * r); }
    default: { l = birdWing(a, select(1.0, -1.0, part == 3), u, v); }
  }
  return Sf(l, l);
}
@vertex fn vsBird(@builtin(vertex_index) vi: u32, @builtin(instance_index) ii: u32) -> AV {
  let a = A[ii]; var o: AV; if (a.size <= 0.0) { o.pos = HIDE; return o; } var part = 0; var g: vec2f;
  if (vi < 672u) { g = grid(vi, 14u, 8u); } else if (vi < 768u) { part = 1; g = grid(vi - 672u, 4u, 4u); } else if (vi < 1152u) { part = 2 + i32((vi - 768u) / 192u); g = grid((vi - 768u) % 192u, 8u, 4u); }
  else { part = 4 + i32((vi - 1152u) / 48u); g = grid((vi - 1152u) % 48u, 4u, 2u); if (a.pose.y < 0.6) { o.pos = HIDE; return o; } }
  let s = birdSurf(a, part, g.x, g.y); let e2 = select(0.02, -0.02, g.x > 0.5); let ev = select(0.02, -0.02, g.y > 0.5); let du = (birdSurf(a, part, g.x + e2, g.y).p - s.p) / e2; let dv = (birdSurf(a, part, g.x, g.y + ev).p - s.p) / ev;
  var n = cross(dv, du); if (dot(n, n) < 1e-12) { n = vec3f(0.0, 0.0, 1.0); } o.n = turn(a, normalize(n)); o.wp = place(a, s.p); o.lp = s.l; o.uv = g; o.part = f32(part); o.seed = a.seed; o.pose = a.pose; o.pos = project(o.wp); return o;
}
// Soft overlapping feather tips: rows of rounded scales across the body, a little darker at each tip's edge.
fn plumage(p: vec2f) -> f32 { let r = floor(p.y); let q = vec2f(p.x + 0.5 * abs(r % 2.0), p.y); let f = fract(q) - vec2f(0.5, 0.0); let d = length(f * vec2f(1.0, 1.6)); return 0.86 + 0.14 * smoothstep(0.75, 0.45, d); }
@fragment fn fsBird(i: AV) -> @location(0) vec4f {
  let v = normalize(camPos() - i.wp); var n = normalize(i.n); let under = dot(n, v) < 0.0; if (under) { n = -n; } let face = max(dot(n, v), 0.0); let s = 0.5 - i.lp.z;
  let female = i.seed < 0.3; let th = atan2(i.lp.y, i.lp.x);
  // Structural blue: deeper face-on, shifting toward cerulean at grazing angles.
  var top = mix(vec3f(0.014, 0.032, 0.170), vec3f(0.050, 0.170, 0.420), pow(1.0 - face, 1.6));
  if (female) { top = vec3f(0.11, 0.085, 0.055); }
  var alb = top; var spec = 0.5; var a = 1.0;
  if (i.part < 0.5) {
    let crown = smoothstep(0.02, 0.07, i.lp.y) * smoothstep(0.13, 0.20, s) * smoothstep(0.38, 0.28, s); if (!female) { alb = mix(alb, vec3f(0.06, 0.24, 0.55), crown * 0.8); }
    let belly = smoothstep(0.01, -0.035, i.lp.y) * smoothstep(0.38, 0.50, s); alb = mix(alb, select(vec3f(0.80, 0.81, 0.84), vec3f(0.62, 0.56, 0.46), female), belly);
    let bib = smoothstep(0.045, 0.005, i.lp.y) * smoothstep(0.50, 0.38, s) * smoothstep(0.12, 0.16, s); alb = mix(alb, select(vec3f(0.010, 0.012, 0.028), vec3f(0.36, 0.28, 0.18), female), bib);
    alb = mix(alb, vec3f(0.025, 0.022, 0.024), smoothstep(0.125, 0.10, s)); spec = select(0.5, 1.4, s < 0.11);   // bill
    alb *= plumage(vec2f(th * 3.2, s * 26.0));
    let ed = length(vec3f(abs(i.lp.x), i.lp.y, i.lp.z) - vec3f(0.078, 0.046, 0.296)); alb = mix(alb, vec3f(0.004), smoothstep(0.019, 0.014, ed));
    if (ed < 0.016) { spec = 3.0; }                                                                     // the wet eye
    // Feathers break up the outline a little where the body turns away.
    a = smoothstep(0.02, 0.22, face + 0.25 * hash21(floor(i.pos.xy * 0.7)) - 0.08) * 0.6 + 0.4;
  } else if (i.part < 1.5) {
    if (!female) { alb = mix(alb, vec3f(0.80, 0.81, 0.84), smoothstep(0.40, 0.75, abs(i.uv.y * 2.0 - 1.0)) * smoothstep(0.55, 0.2, i.uv.x)); }
    let tip = abs(fract(i.uv.y * 6.0) - 0.5); if (i.uv.x > 0.93 - 0.08 * tip) { discard; }
  } else if (i.part < 3.5) {
    // Flight feathers: blackish, edged with the body's colour; coverts the body's colour. Each feather's tip is its own.
    let fe = fract(i.uv.y * 9.0 + i.uv.x * 1.5); alb *= 0.7 + 0.4 * smoothstep(0.0, 0.4, fe);
    let flight = smoothstep(0.30, 0.60, i.uv.y * 0.6 + i.uv.x * 0.6); alb = mix(alb, select(vec3f(0.010, 0.011, 0.024), vec3f(0.06, 0.045, 0.03), female) + top * 0.25 * (1.0 - smoothstep(0.0, 0.2, fe)), flight * 0.85);
    if (i.uv.y > 0.55) { let fi = abs(fract(i.uv.x * 7.0) - 0.5) * 2.0; if (i.uv.y > 1.0 - 0.10 * fi) { discard; } }
  } else { alb = vec3f(0.035, 0.032, 0.036); spec = 0.4; }
  let L = lit3(i.wp, n, 0.3, vec3f(0.60, 0.58, 0.62)); var c = alb * (L.a + L.b * select(0.12, 0.40, i.part > 0.5 && i.part < 3.5)) * 1.2;
  c += glint(i.wp, n, select(24.0, 90.0, spec > 2.0)) * select(vec3f(0.10, 0.22, 0.70), vec3f(0.30), female || spec > 1.0) * spec * 0.45 + select(vec3f(0.03, 0.07, 0.17), vec3f(0.03), female) * pow(1.0 - face, 3.0);
  return vec4f(c, a * fadeOut(i.pos.xy, i.pose.z));
}

// ---- cabbage whites over the field. pose: open angle, -, fade, -
@vertex fn vsFly(@builtin(vertex_index) vi: u32, @builtin(instance_index) ii: u32) -> AV {
  let a = A[ii]; var o: AV; if (a.size <= 0.0) { o.pos = HIDE; return o; } let sd = select(1.0, -1.0, vi >= 6u); let q = QUAD[vi % 6u] * 0.5 + 0.5; let an = a.pose.x; let l = vec3f(sd * q.x * cos(an), q.x * sin(an), (q.y - 0.5) * 1.15); let n = vec3f(-sd * sin(an), cos(an), 0.0);
  o.wp = place(a, l); o.n = turn(a, n); o.lp = l; o.uv = q; o.part = 0.0; o.seed = a.seed; o.pose = a.pose; o.pos = project(o.wp); return o;
}
@fragment fn fsFly(i: AV) -> @location(0) vec4f {
  let u = i.uv.x; let w = i.uv.y * 2.0 - 1.0; let fore = length((vec2f(u, w) - vec2f(0.46, 0.34)) * vec2f(1.0, 0.95) * rot(0.5)) / 0.50; let hind = length((vec2f(u, w) - vec2f(0.38, -0.36)) * vec2f(1.05, 1.0)) / 0.42; let d = min(fore, hind); if (d > 1.0 && u > 0.05) { discard; }
  var alb = vec3f(0.95, 0.95, 0.88); alb = mix(alb, vec3f(0.10, 0.10, 0.12), smoothstep(0.78, 0.9, u) * step(0.2, w)); alb = mix(alb, vec3f(0.12), smoothstep(0.09, 0.06, length(vec2f(u - 0.55, w - 0.28)))); alb = mix(alb, vec3f(0.15), step(u, 0.05));
  let L = lit3(i.wp, normalize(i.n), 0.6, vec3f(0.55)); return vec4f(alb * (L.a + L.b) * 0.75, fadeOut(i.pos.xy, i.pose.z));
}
