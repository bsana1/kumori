// One bead per jittered grid site. Merging is two-phase so volume is conserved:
// phase 1 a bead hands its volume to its largest overlapping neighbour, phase 2 applies it.
struct Req { n: atomic<u32>, pad: array<u32, 3>, data: array<vec4f> };
@group(0) @binding(1) var<storage, read_write> B: array<vec4f>;   // offset.xy in cell, volume r^3, seed
@group(0) @binding(2) var<storage, read_write> gain: array<atomic<u32>>;
@group(0) @binding(3) var<storage, read_write> R: Req;
@group(0) @binding(4) var samp: sampler;
@group(0) @binding(5) var liq: texture_2d<f32>;
@group(0) @binding(6) var field: texture_2d<f32>;
@group(0) @binding(7) var mask: texture_2d<f32>;
const FIX: f32 = 4096.0;
const CELL: f32 = 3.0;
fn bpos(c: vec2i) -> vec2f { let b = B[u32(c.x) + u32(c.y) * U.beadGrid.x]; return (vec2f(c) + b.xy) * CELL; }
fn request(p: vec2f, v: vec2f) { let i = atomicAdd(&R.n, 1u); if (i < arrayLength(&R.data)) { R.data[i] = vec4f(p, v); } }

@compute @workgroup_size(64) fn merge(@builtin(global_invocation_id) g: vec3u) {
  let n = U.beadGrid.x * U.beadGrid.y; if (g.x >= n) { return; }
  let c = vec2i(i32(g.x % U.beadGrid.x), i32(g.x / U.beadGrid.x));
  let vol = B[g.x].z; if (vol < 0.001) { return; }
  let p = bpos(c); let r = pow(vol, 0.3333); var best = -1; var bestV = vol;
  for (var y = -2; y <= 2; y++) { for (var x = -2; x <= 2; x++) {
    let o = c + vec2i(x, y);
    if ((x == 0 && y == 0) || any(o < vec2i(0)) || any(o >= vec2i(U.beadGrid))) { continue; }
    let j = u32(o.x) + u32(o.y) * U.beadGrid.x; let v = B[j].z;
    if (v < bestV || (v == bestV && j < g.x)) { continue; }
    if (distance(p, bpos(o)) < (r + pow(v, 0.3333)) * 0.88) { best = i32(j); bestV = v; }
  } }
  if (best >= 0) { atomicAdd(&gain[best], u32(vol * FIX)); atomicOr(&gain[g.x], 0x80000000u); }
}

@compute @workgroup_size(64) fn apply(@builtin(global_invocation_id) g: vec3u) {
  let n = U.beadGrid.x * U.beadGrid.y; if (g.x >= n) { return; }
  let c = vec2i(i32(g.x % U.beadGrid.x), i32(g.x / U.beadGrid.x));
  var b = B[g.x]; let raw = atomicExchange(&gain[g.x], 0u);
  if ((raw & 0x80000000u) != 0u) { b.z = 0.0; }
  b.z += f32(raw & 0x7fffffffu) / FIX;
  let p = (vec2f(c) + b.xy) * CELL; let uv = p / U.size;
  let s = g.x * 5u + u32(U.frame / U.pace) * 104729u;
  let fl = textureSampleLevel(field, samp, uv, 0.0);
  let L = textureSampleLevel(liq, samp, uv, 0.0).r;

  // Condensation: each site has its own pace and a soft size limit.
  let cap = 0.45 + 0.75 * rnd(g.x * 3u + 11u) + 2.1 * pow(rnd(g.x * 3u + 12u), 16.0);
  let r0 = pow(max(b.z, 0.0), 0.3333);
  if (r0 < cap) {
    // Clumpy nucleation, so regrowth never reads as a lattice.
    let pace = U.growth * 0.011 * (0.25 + 1.5 * smoothstep(0.30, 0.70, gnoise(p * 0.07))) * (0.3 + 1.4 * b.w) * (0.25 + fl.r) * (1.0 + 4.0 * fl.g * step(r0, 0.55 * b.w + 0.15));
    let r1 = r0 + pace * (U.dt * U.pace); b.z = r1 * r1 * r1;
  }
  // Swallowed by running water: the volume joins it (one particle, with matching odds).
  if (L > LIQ_T * 0.8 && b.z > 0.0) { if (rnd(s) < b.z / PARTICLE_MASS) { request(p, vec2f(0.0)); } b.z = 0.0; }
  for (var i = 0; i < 8; i++) {
    let k = U.fingers[i]; if (k.on < 0.5 || b.z <= 0.0) { continue; }
    if (capsule(p, k.a, k.b) < k.r) {
      if (rnd(s + 1u) < b.z / PARTICLE_MASS) {
        let dir = normalize(k.vel + vec2f(0.001, 0.0)); let nrm = vec2f(-dir.y, dir.x);
        let side = select(-1.0, 1.0, dot(p - k.b, nrm) > 0.0);
        request(onPath(p, k.a, k.b) + nrm * side * (k.r + 1.5 + 3.0 * rnd(s + 2u)) + dir * (rnd(s + 3u) * 0.9 - 0.2) * k.r, k.vel * 0.04);
      }
      b.z = 0.0;
    }
  }
  // Written strokes hold no beads. A fifth of that water is left as a ridge beside the stroke;
  // the rest is taken to leave with the fingertip, or every letter would drip itself away.
  if (b.z > 0.0 && textureSampleLevel(mask, samp, uv, 0.0).r > 0.45) {
    if (rnd(s + 60u) < 0.2 * b.z / PARTICLE_MASS) { let a = rnd(s + 61u) * 6.2831853; request(p + vec2f(cos(a), sin(a)) * 8.0, vec2f(0.0)); }
    b.z = 0.0;
  }
  // Too heavy to be a bead any more: becomes free liquid.
  if (b.z > 46.0) {
    let m = b.z / PARTICLE_MASS; let cnt = u32(m) + select(0u, 1u, rnd(s + 4u) < fract(m));
    for (var q = 0u; q < cnt; q++) { request(p + (vec2f(rnd(s + 5u + q), rnd(s + 25u + q)) - 0.5) * 5.0, vec2f(0.0)); }
    b.z = 0.0;
  }
  if (b.z == 0.0) { b.x = rnd(s + 50u); b.y = rnd(s + 51u); }
  B[g.x] = b;
}
