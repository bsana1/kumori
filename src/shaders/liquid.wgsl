// 2D particle fluid: double-density relaxation (Clavet et al. 2005) in Jacobi form.
// The attraction below rest density is what gives surface tension.
// The contact-line physics is a heuristic: mobility depends on how much water is nearby
// against a fixed "wettability" noise, so small drops stick and big ones hesitate, then run.
struct Free { top: atomic<i32>, idx: array<u32> };
struct Stats { spawned: atomic<u32>, drained: atomic<u32>, dropped: atomic<u32>, rained: atomic<u32> };
@group(0) @binding(1) var<storage, read_write> P: array<vec4f>;       // pos, vel
@group(0) @binding(2) var<storage, read_write> X: array<vec4f>;       // previous pos, density, near density
@group(0) @binding(3) var<storage, read_write> D: array<vec4f>;       // displacement, mobility
@group(0) @binding(4) var<storage, read_write> cnt: array<atomic<u32>>;
@group(0) @binding(5) var<storage, read_write> cells: array<u32>;
@group(0) @binding(6) var<storage, read_write> F: Free;
@group(0) @binding(7) var<storage, read_write> S: Stats;
@group(0) @binding(8) var samp: sampler;
@group(0) @binding(9) var wide: texture_2d<f32>;
@group(0) @binding(10) var field: texture_2d<f32>;

const H: f32 = 4.2;
const CAP: u32 = 16u;
const REST: f32 = 3.55;
const K: f32 = 2900.0;
const KN: f32 = 4350.0;
fn dead(p: vec4f) -> bool { return p.x < -1e5; }
fn cellOf(p: vec2f) -> vec2i { return clamp(vec2i(floor(p / H)), vec2i(0), vec2i(U.cellGrid) - 1); }
fn sdt() -> f32 { return U.dt * 0.5; }

@compute @workgroup_size(64) fn clearCells(@builtin(global_invocation_id) g: vec3u) {
  if (g.x < U.cellGrid.x * U.cellGrid.y) { atomicStore(&cnt[g.x], 0u); }
}
@compute @workgroup_size(64) fn predict(@builtin(global_invocation_id) g: vec3u) {
  if (g.x >= arrayLength(&P)) { return; }
  var p = P[g.x]; if (dead(p)) { return; }
  let dt = sdt(); let uv = p.xy / U.size;
  let mass = textureSampleLevel(wide, samp, uv, 0.0).r;
  let wet = textureSampleLevel(field, samp, uv, 0.0).g;
  let grip = 0.65 + 0.7 * vnoise(p.xy * vec2f(0.09, 0.05));
  let going = smoothstep(6.0, 40.0, length(p.zw));
  // Thin edges cling: this is what makes a running drop shed a tail of small beads.
  let body = mix(0.30, 1.0, smoothstep(0.5, 2.0, X[g.x].z));
  var mob = smoothstep(0.60 - 0.12 * going, 1.8, mass / grip + 0.04 * wet) * body;
  // Wetting defects: scattered sites that hold on to the thin rear of a passing drop.
  let held = hash21(p.xy / 3.2) > 0.70 && X[g.x].z < 1.9;
  if (held) { mob *= 0.03; }
  var v = p.zw;
  v += 1500.0 * mob * dt * U.tilt.xy;   // down is wherever the phone says it is
  v.x += (vnoise(p.xy * vec2f(0.045, 0.03) + 31.0) - 0.5) * 1100.0 * mob * dt;
  // Drops are drawn into tracks that are already wet.
  let e = 7.0 / U.size.x;
  let gx = textureSampleLevel(field, samp, uv + vec2f(e, 0.012), 0.0).g - textureSampleLevel(field, samp, uv + vec2f(-e, 0.012), 0.0).g;
  v.x += gx * 320.0 * mob * dt;
  v *= exp(-mix(16.0, 5.0, mob) * dt);
  X[g.x] = vec4f(p.xy, 0.0, 0.0);
  D[g.x] = vec4f(0.0, 0.0, mob, 0.0);
  P[g.x] = vec4f(p.xy + v * dt, v);
}
@compute @workgroup_size(64) fn insert(@builtin(global_invocation_id) g: vec3u) {
  if (g.x >= arrayLength(&P)) { return; }
  let p = P[g.x]; if (dead(p)) { return; }
  let c = cellOf(p.xy); let k = u32(c.x) + u32(c.y) * U.cellGrid.x;
  let s = atomicAdd(&cnt[k], 1u); if (s < CAP) { cells[k * CAP + s] = g.x; }
}
@compute @workgroup_size(64) fn density(@builtin(global_invocation_id) g: vec3u) {
  if (g.x >= arrayLength(&P)) { return; }
  let p = P[g.x]; if (dead(p)) { return; }
  let c = cellOf(p.xy); var rho = 0.0; var near = 0.0;
  for (var y = -1; y <= 1; y++) { for (var x = -1; x <= 1; x++) {
    let o = c + vec2i(x, y); if (any(o < vec2i(0)) || any(o >= vec2i(U.cellGrid))) { continue; }
    let k = u32(o.x) + u32(o.y) * U.cellGrid.x; let n = min(atomicLoad(&cnt[k]), CAP);
    for (var s = 0u; s < n; s++) {
      let j = cells[k * CAP + s]; if (j == g.x) { continue; }
      let d = distance(p.xy, P[j].xy);
      if (d < H) { let q = 1.0 - d / H; rho += q * q; near += q * q * q; }
    }
  } }
  X[g.x].z = rho; X[g.x].w = near;
}
@compute @workgroup_size(64) fn relax(@builtin(global_invocation_id) g: vec3u) {
  if (g.x >= arrayLength(&P)) { return; }
  let p = P[g.x]; if (dead(p)) { return; }
  let me = X[g.x]; let c = cellOf(p.xy); var dx = vec2f(0.0); var dv = vec2f(0.0); let dt = sdt();
  for (var y = -1; y <= 1; y++) { for (var x = -1; x <= 1; x++) {
    let o = c + vec2i(x, y); if (any(o < vec2i(0)) || any(o >= vec2i(U.cellGrid))) { continue; }
    let k = u32(o.x) + u32(o.y) * U.cellGrid.x; let n = min(atomicLoad(&cnt[k]), CAP);
    for (var s = 0u; s < n; s++) {
      let j = cells[k * CAP + s]; if (j == g.x) { continue; }
      let r = P[j].xy - p.xy; let d = length(r); if (d >= H) { continue; }
      let q = 1.0 - d / H; let other = X[j];
      let a = f32(g.x * 13u + j) * 2.4;
      let dir = select(vec2f(cos(a), sin(a)), r / max(d, 1e-5), d > 1e-3);
      let pr = K * (me.z + other.z - 2.0 * REST) * q + KN * (me.w + other.w) * q * q;
      dx -= dir * pr * 0.5 * dt * dt;
      dv += (P[j].zw - p.zw) * q;
    }
  } }
  dx *= 0.75; let lim = 0.8; let l = length(dx); if (l > lim) { dx *= lim / l; }
  // XSPH-style viscosity keeps a drop moving as one body.
  D[g.x] = vec4f(dx + dv * 0.05 * dt, D[g.x].z, 0.0);
}
@compute @workgroup_size(64) fn integrate(@builtin(global_invocation_id) g: vec3u) {
  if (g.x >= arrayLength(&P)) { return; }
  let p = P[g.x]; if (dead(p)) { return; }
  let dt = sdt(); let old = X[g.x].xy; var np = p.xy + D[g.x].xy; let mob = D[g.x].z;
  // Static friction: below a small creep the contact line holds and shape changes freeze.
  let moved = np - old; let stick = mix(0.075, 0.003, mob);
  if (length(moved) < stick) { np = old; }
  var v = (np - old) / dt;
  for (var i = 0; i < 8; i++) {
    let k = U.fingers[i]; if (k.on < 0.5) { continue; }
    let pa = np - k.a; let ba = k.b - k.a; let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    let q = k.a + ba * h; let d = np - q; let l = length(d);
    if (l < k.r + 1.0) {
      var n = d / max(l, 1e-3);
      // Water under the fingertip squeezes out sideways rather than being dragged along for ever.
      let dir = normalize(k.vel + vec2f(0.0, 0.001)); let nrm = vec2f(-dir.y, dir.x);
      n = normalize(n + nrm * sign(dot(n, nrm) + 0.001) * 0.8);
      np = q + n * (k.r + 1.0 + rnd(g.x) * 2.0); v = k.vel * 0.12 + n * 12.0;
    }
  }
  let sp = length(v); if (sp > 700.0) { v *= 700.0 / sp; }
  // The side frames hold water back, unless the glass is tipped towards them: then it runs off there.
  let offSide = (np.x < -12.0 && U.tilt.x < -0.2) || (np.x > U.size.x + 12.0 && U.tilt.x > 0.2);
  if (!offSide) { if (np.x < 1.0 && U.tilt.x >= -0.2) { np.x = 1.0; v.x = abs(v.x) * 0.2; } if (np.x > U.size.x - 1.0 && U.tilt.x <= 0.2) { np.x = U.size.x - 1.0; v.x = -abs(v.x) * 0.2; } }
  if (offSide || np.y > U.size.y + 12.0 || np.y < -80.0 || !(np.x == np.x)) {
    P[g.x] = vec4f(-1e6, 0.0, 0.0, 0.0);
    let t = atomicAdd(&F.top, 1); F.idx[t] = g.x; atomicAdd(&S.drained, 1u); return;
  }
  P[g.x] = vec4f(np, v);
}
