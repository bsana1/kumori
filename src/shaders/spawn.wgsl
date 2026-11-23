// Turn spawn requests (plus a little rain) into particles.
struct Req { n: atomic<u32>, pad: array<u32, 3>, data: array<vec4f> };
struct Free { top: atomic<i32>, idx: array<u32> };
struct Stats { spawned: atomic<u32>, drained: atomic<u32>, dropped: atomic<u32>, rained: atomic<u32> };
@group(0) @binding(1) var<storage, read_write> R: Req;
@group(0) @binding(2) var<storage, read_write> F: Free;
@group(0) @binding(3) var<storage, read_write> P: array<vec4f>;
@group(0) @binding(4) var<storage, read_write> S: Stats;
fn add(p: vec2f, v: vec2f) {
  let t = atomicSub(&F.top, 1) - 1;
  if (t < 0) { atomicAdd(&F.top, 1); atomicAdd(&S.dropped, 1u); return; }
  P[F.idx[t]] = vec4f(p, v); atomicAdd(&S.spawned, 1u);
}
@compute @workgroup_size(64) fn main(@builtin(global_invocation_id) g: vec3u) {
  let n = min(atomicLoad(&R.n), arrayLength(&R.data));
  if (g.x >= n || U.dt <= 0.0) { return; }
  add(R.data[g.x].xy, R.data[g.x].zw);
}
@compute @workgroup_size(1) fn rain() {
  let s = u32(U.frame) * 911u + u32(U.seed) * 13u;
  if (rnd(s) < U.rain * U.dt) {
    let c = vec2f(rnd(s + 1u) * U.size.x, (rnd(s + 2u) * 0.75 - 0.03) * U.size.y);
    let k = 2u + u32(24.0 * pow(rnd(s + 3u), 2.2));
    for (var i = 0u; i < k; i++) {
      let a = f32(i) * 2.39996; let r = 1.6 * sqrt(f32(i) + 0.3);
      add(c + vec2f(cos(a), sin(a)) * r, vec2f(0.0)); atomicAdd(&S.rained, 1u);
    }
  }
}
@compute @workgroup_size(1) fn clear() { atomicStore(&R.n, 0u); let keep = U.dt; }
