// The world outside: a wet Kyoto back street at blue hour. Analytic planes rather than a full
// raymarch, so it can be re-rendered every frame with moving people and flickering lanterns.
@group(0) @binding(14) var noiseS: sampler;
@group(0) @binding(15) var noiseT: texture_2d<f32>;
// One-tap value noise from a small random texture: much cheaper than hashing in full-screen passes.
fn nz(p: vec2f) -> f32 { let i = floor(p); let f = fract(p); return textureSampleLevel(noiseT, noiseS, (i + f * f * (3.0 - 2.0 * f) + 0.5) / 256.0, 0.0).r; }
fn fbz(p0: vec2f) -> f32 { var p = ROT * p0; var a = 0.5; var s = 0.0; for (var i = 0; i < 4; i++) { s += a * nz(p); p = ROT * p * 2.03 + 17.1; a *= 0.5; } return s / 0.9375; }
struct VO { @builtin(position) pos: vec4f, @location(0) uv: vec2f };
@vertex fn vs(@builtin(vertex_index) v: u32) -> VO { var o: VO; o.uv = vec2f(f32((v << 1u) & 2u), f32(v & 2u)); o.pos = vec4f(o.uv * vec2f(2, -2) + vec2f(-1, 1), 0, 1); return o; }

const HALF: f32 = 2.35;            // half width of the alley, metres
const NL: i32 = 18;                // lanterns
struct Lamp { p: vec3f, c: vec3f, r: f32 };
fn lamp(i: i32) -> Lamp { let a = U.lamps[i * 2]; return Lamp(a.xyz, U.lamps[i * 2 + 1].rgb, a.w); }
fn lampLight(p: vec3f, n: vec3f) -> vec3f {
  var s = vec3f(0.0);
  for (var i = 0; i < NL; i++) { let L = lamp(i); let d = L.p - p; let d2 = dot(d, d) + 0.06; s += L.c * max(0.12, dot(n, d) / sqrt(d2)) / d2; }
  // The lit canopy warms the street around it.
  let d = U.treePos.xyz - p; s += vec3f(1.0, 0.62, 0.60) * U.grow.z * 1.5 * max(0.12, dot(n, d) / length(d)) / (dot(d, d) + 0.6);
  return s * 0.34;
}
fn sky(rd: vec3f) -> vec3f {
  let h = clamp(rd.y, 0.0, 1.0); let fall = U.world[1].z;
  return vec3f(0.035, 0.030, 0.034) * fall * (1.0 - h * 0.6) + mix(vec3f(0.055, 0.062, 0.12), vec3f(0.006, 0.013, 0.042), pow(h, 0.5)) + vec3f(0.11, 0.05, 0.03) * exp(-h * 9.0);
}
fn facade(p: vec3f, side: f32) -> vec3f {
  let n = vec3f(-side, 0.0, 0.0); let z = p.z; let y = p.y;
  let bayW = 2.2; let bz = z / bayW; let id = floor(bz) + side * 37.0; let u = fract(bz); let h = hash22(vec2f(id, 5.0));
  let grain = 0.7 + 0.6 * nz(vec2f(z * 2.0, y * 40.0));
  var alb = vec3f(0.060, 0.036, 0.024) * grain; var em = vec3f(0.0);
  let post = step(u, 0.05) + step(0.95, u);
  if (y < 2.45 && post < 0.5) {
    if (h.x < 0.58) {                              // koshi lattice over a lit room
      let inW = step(0.10, u) * step(u, 0.90) * step(0.55, y) * step(y, 2.15);
      let bars = smoothstep(0.30, 0.42, abs(fract(z * 4.5) - 0.5) * 2.0);
      let glow = mix(vec3f(1.0, 0.50, 0.18), vec3f(1.0, 0.72, 0.42), h.y) * (0.55 + 0.45 * nz(vec2f(z * 1.7, y * 1.3)));
      let hang = exp(-pow((y - 1.75) * 1.3, 2.0) - pow((u - 0.3 - 0.4 * h.x) * 3.2, 2.0));   // a lamp somewhere in the room
      let room = 0.10 + 0.9 * hang + 0.25 * smoothstep(0.5, 0.75, nz(vec2f(z * 5.0, y * 4.0)));
      em = glow * inW * bars * room * (0.15 + 0.75 * h.y);
    } else if (h.x < 0.82) {                       // doorway with a noren curtain
      let door = step(0.15, u) * step(u, 0.85) * step(y, 2.1); let cloth = step(1.35 + 0.03 * sin(z * 14.0 + U.time), y);
      let dye = select(vec3f(0.05, 0.07, 0.22), vec3f(0.30, 0.04, 0.03), h.y > 0.5);
      em = door * mix(vec3f(1.0, 0.52, 0.20) * (0.05 + 0.55 * exp(-pow((y - 1.0) * 1.1, 2.0) - pow((u - 0.5) * 3.4, 2.0))), dye * 0.22, cloth);
    }
  } else if (y > 2.75 && y < 4.9 && post < 0.5) {  // upper floor: bamboo blinds, some lit
    let win = step(0.14, u) * step(u, 0.86) * step(3.25, y) * step(y, 4.45);
    let slats = 0.55 + 0.45 * smoothstep(0.2, 0.6, abs(fract(y * 16.0) - 0.5) * 2.0);
    em = win * slats * vec3f(1.0, 0.58, 0.26) * step(0.45, h.y) * 0.30 * (0.15 + exp(-pow((u - h.x) * 2.6, 2.0))) ;
  }
  let eave = smoothstep(2.42, 2.46, y) * (1.0 - smoothstep(2.72, 2.76, y)) + smoothstep(4.95, 5.0, y);
  if (eave > 0.5) { alb = vec3f(0.020, 0.022, 0.028); em = vec3f(0.0); }
  // Settled snow along the top of each eave and the roof edge, thicker in places.
  let ledge = (smoothstep(2.74, 2.76, y) * (1.0 - smoothstep(2.76 + 0.05 * U.pane.z, 2.78 + 0.05 * U.pane.z, y)) + smoothstep(4.99, 5.0, y) * (1.0 - smoothstep(5.0 + 0.07 * U.pane.z, 5.03 + 0.07 * U.pane.z, y))) * smoothstep(0.25, 0.6, U.pane.z + 0.3 * (nz(vec2f(z * 3.0, side * 7.0)) - 0.5));
  if (ledge > 0.01) { alb = mix(alb, vec3f(0.62, 0.64, 0.70), ledge); em *= 1.0 - ledge; }
  return alb * (lampLight(p, n) + vec3f(0.05, 0.07, 0.13)) + em * mix(0.05, 1.0, smoothstep(3.0, 15.0, z));
}
fn sign(p2: vec2f, size: vec2f) -> f32 { let d = abs(p2) - size; return 1.0 - smoothstep(0.0, 0.02, max(d.x, d.y)); }

// Colour along a ray, ignoring the ground (so the ground can reuse it for its reflection).
fn above(ro: vec3f, rd: vec3f, rough: f32) -> vec3f {
  var col = sky(rd); var tHit = 1e5;
  for (var s = -1.0; s < 1.5; s += 2.0) {
    let t = (s * HALF - ro.x) / rd.x;
    if (t > 0.0 && t < tHit) { let p = ro + rd * t; if (p.y < 5.35 + 0.35 * hash21(vec2f(floor(p.z / 4.4), s)) && p.y > -0.02 && p.z < 46.0) {
      tHit = t; col = facade(p, s);
    } }
  }
  // Cross street glow at the far end.
  let te = (46.0 - ro.z) / rd.z; if (te > 0.0 && te < tHit) { let p = ro + rd * te; if (abs(p.x) < HALF && p.y < 4.6) { tHit = te; col = vec3f(1.0, 0.55, 0.28) * (0.06 + 1.1 * exp(-dot(p.xy - vec2f(0.4, 1.5), p.xy - vec2f(0.4, 1.5)) * 0.35)); } }
  let hz = 1.0 - exp(-max(min(tHit, 60.0), 0.0) * (0.020 + 0.012 * U.world[1].z));   // falling snow thickens the air
  col = mix(col, vec3f(0.062, 0.044, 0.056), hz);
  // Strings of small bulbs and far windows: pinpoints that become bokeh.
  for (var i = 0; i < 26; i++) {
    let B = U.bulbs[i * 2]; let t = (B.z - ro.z) / rd.z; if (t < 0.0 || t > tHit) { continue; }
    let p = ro + rd * t; let r = B.w + rough * 0.12; let d = length(p.xy - B.xy); if (d > r) { continue; }
    col += U.bulbs[i * 2 + 1].rgb * (1.0 - smoothstep(r * 0.6, r, d));
  }
  // Upright illuminated signs.
  for (var i = 0; i < 5; i++) {
    let k = f32(i); let side = select(-1.0, 1.0, (i % 2) == 1); let z = 6.5 + k * 4.6;
    let t = (z - ro.z) / rd.z; if (t < 0.0 || t > tHit) { continue; }
    let p = ro + rd * t; let q = p.xy - vec2f(side * (HALF - 0.28), 3.15 + 0.25 * sin(k * 3.0)); let m = sign(q, vec2f(0.17, 0.62));
    if (m > 0.0) {
      let pal = array<vec3f, 5>(vec3f(0.55, 0.85, 1.0), vec3f(1.0, 0.30, 0.42), vec3f(0.95, 0.95, 0.85), vec3f(0.30, 1.0, 0.70), vec3f(1.0, 0.75, 0.30));
      let glyph = 0.35 + 0.65 * step(0.42, nz(vec2f(q.x * 22.0, q.y * 15.0 + k * 9.0)));
      col = mix(col, pal[i] * 0.85 * glyph, m); tHit = t;
    }
  }
  // People with umbrellas, walking slowly.
  for (var i = 0; i < 3; i++) {
    let k = f32(i); let dir = select(-1.0, 1.0, i == 1); let span = 26.0;
    let z = 5.0 + span * fract(0.31 * k + 0.13 + dir * U.time * 0.0105 * (1.0 + 0.2 * k)); let t = (z - ro.z) / rd.z;
    if (t < 0.0 || t > tHit) { continue; }
    let p = ro + rd * t; let bob = 0.025 * abs(sin(U.time * 2.6 + k * 2.0));
    let q = p.xy - vec2f(-0.75 + 0.75 * k + 0.1 * sin(U.time * 0.5 + k), bob);
    let body = step(length(vec2f(q.x / 0.24, (q.y - 0.72) / 0.82)), 1.0) + step(length(q - vec2f(0.0, 1.50)), 0.12);
    let uq = q - vec2f(0.10, 1.62); let um = step(length(vec2f(uq.x / 0.62, uq.y / 0.40)), 1.0) * step(0.0, uq.y);
    let back = lampLight(p, vec3f(0, 0, 1));
    if (body > 0.5) { col = mix(vec3f(0.010, 0.010, 0.014) + back * 0.010, col, hz * 0.3); tHit = t; }
    if (um > 0.5) { let dye = select(vec3f(0.35, 0.03, 0.03), vec3f(0.05, 0.08, 0.22), i == 1); col = dye * (0.10 + back * 0.55) * (0.6 + 0.4 * step(0.08, abs(fract(atan2(uq.y, uq.x) * 2.55) - 0.5))); let cap = smoothstep(0.55, 0.8, uq.y / 0.40) * smoothstep(0.1, 0.5, U.pane.z); col = mix(col, vec3f(0.55, 0.58, 0.66) * (0.12 + back * 0.6), cap); tHit = t; }
  }
  // Paper lanterns: ellipsoids lit from inside.
  for (var i = 0; i < NL; i++) {
    let L = lamp(i); let sc = vec3f(1.0, 0.74, 1.0); let o = (ro - L.p) * sc; let d = rd * sc;
    let a = dot(d, d); let b = dot(o, d); let rr = L.r + rough * 0.25; let c = dot(o, o) - rr * rr; let disc = b * b - a * c;
    if (disc > 0.0) {
      let t = (-b - sqrt(disc)) / a; if (t > 0.0 && t < tHit) {
        let p = o + d * t; let face = sqrt(disc / (a * rr * rr)); let rib = 0.86 + 0.14 * sin(p.y * 120.0);
        let cap = smoothstep(0.80, 0.86, abs(p.y) / rr);
        col = mix(L.c * rib * (1.1 + 6.5 * pow(face, 3.0)) * (0.8 + 0.4 * clamp(-p.y / rr, 0.0, 1.0)), vec3f(0.01), cap);
        let lid = cap * step(0.0, p.y) * smoothstep(0.15, 0.5, U.pane.z); col = mix(col, L.c * 0.35 + vec3f(0.10, 0.11, 0.13), lid);   // snow on the lid, lit by the lantern
      }
    }
    // Soft air glow around each lantern.
    let tc = max(0.0, dot(L.p - ro, rd)); let m = ro + rd * tc - L.p; col += L.c * 0.020 * exp(-dot(m, m) * 3.0) * step(tc, tHit + 0.5);
  }
  return col;
}
@fragment fn fs(i: VO) -> @location(0) vec4f {
  let asp = U.size.x / U.size.y; let ro = camPos();
  let rd = normalize(vec3f((i.uv.x - 0.5) * asp * 1.18 + 0.02, (0.47 - i.uv.y) * 1.18, 1.0));
  var col: vec3f;
  let tg = -ro.y / min(rd.y, -1e-4); let pg = ro + rd * tg;
  if (rd.y < -0.0005 && abs(pg.x) < HALF && pg.z < 46.0) {
    let st = pg.xz * vec2f(1.55, 1.15) + vec2f(0.5 * floor(pg.z * 1.15 % 2.0), 0.0); let f = fract(st); let id = floor(st);
    let joint = smoothstep(0.0, 0.05, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
    let puddle = smoothstep(0.42, 0.62, fbz(pg.xz * vec2f(0.9, 0.45) + 3.0));
    let nz = (vec2f(nz(pg.xz * 9.0), nz(pg.xz * 9.0 + 40.0)) - 0.5) * mix(0.16, 0.012, puddle) + (hash22(id) - 0.5) * 0.03 * (1.0 - puddle);
    // Drip rings in the puddles.
    let rc = floor(pg.xz * 2.2); let rh = hash22(rc); let rt = fract(U.time * 0.7 + rh.x); let rq = fract(pg.xz * 2.2) - 0.5 - (rh - 0.5) * 0.4; let rl = length(rq);
    let ring = sin((rl - rt * 0.5) * 70.0) * exp(-abs(rl - rt * 0.5) * 22.0) * (1.0 - rt) * step(0.5, rh.y) * puddle;
    let n = normalize(vec3f(nz.x + ring * 0.08 * rq.x / max(rl, 0.01), 1.0, nz.y * 1.8 + ring * 0.08 * rq.y / max(rl, 0.01)));
    let rr = reflect(rd, n); let fres = 0.05 + 0.95 * pow(1.0 - max(dot(-rd, n), 0.0), 4.0);
    let alb = vec3f(0.050, 0.047, 0.050) * (0.6 + 0.6 * hash21(id)) * (0.35 + 0.65 * joint);
    col = alb * (lampLight(pg + vec3f(0, 0.02, 0), vec3f(0, 1, 0)) + vec3f(0.05, 0.07, 0.14));
    col += above(pg + vec3f(0, 0.01, 0), normalize(vec3f(rr.x, max(rr.y, 0.004), rr.z)), 0.35) * mix(0.30, 0.80, puddle) * (0.25 + 0.75 * fres);
    // Snow on the ground: it gathers first at the edges and between the stones, last where people walk in
    // the middle, and the tracks stay darker and wet. Lit by the lanterns, with a fine sparkle.
    let S = U.pane.z;
    if (S > 0.0) {
      let tread = exp(-pow((pg.x - 0.1 - 0.25 * sin(pg.z * 0.35)) / 0.55, 2.0)) * (0.55 + 0.45 * fbz(pg.xz * vec2f(2.0, 0.6)));
      // Each spot whitens once the snowfall so far passes its own threshold: the edges and the stones' tops
      // first, the joints later, the trodden middle last. With no snow yet nothing is white anywhere.
      let T = clamp(0.10 + 0.55 * tread + 0.12 * (1.0 - joint) - 0.10 * smoothstep(1.2, 2.2, abs(pg.x - 0.1)) + 0.25 * (fbz(pg.xz * 1.7 + 11.0) - 0.5), 0.06, 0.95);
      let cov = smoothstep(T - 0.04, T + 0.12, S) * mix(0.55, 1.0, smoothstep(0.0, 0.6, S));   // a first dusting lets the stones show through
      // Soft drifts: the snow's surface rises and falls a little, and the lanterns pick that out.
      let e = 0.05; let h0 = fbz(pg.xz * vec2f(1.3, 0.8) + 30.0); let hx = fbz((pg.xz + vec2f(e, 0.0)) * vec2f(1.3, 0.8) + 30.0); let hz2 = fbz((pg.xz + vec2f(0.0, e)) * vec2f(1.3, 0.8) + 30.0);
      let sn_n = normalize(vec3f(-(hx - h0) / e * 0.10, 1.0, -(hz2 - h0) / e * 0.10));
      let sn = vec3f(0.70, 0.72, 0.78) * (0.94 + 0.06 * hash21(floor(pg.xz * 23.0)));
      let lit = lampLight(pg + vec3f(0, 0.03, 0), sn_n) * 1.6 + vec3f(0.030, 0.038, 0.070);
      let spark = step(0.993, hash21(floor(pg.xz * 140.0))) * 2.5 * max(dot(lit, vec3f(0.33)) - 0.05, 0.0);
      col = mix(col, sn * lit + spark, cov);
    }
    col = mix(col, vec3f(0.062, 0.044, 0.056), 1.0 - exp(-tg * 0.018));
  } else { col = above(ro, rd, 0.0); }
  return vec4f(min(max(col, vec3f(0.0)), vec3f(40.0)), 1.0);
}
