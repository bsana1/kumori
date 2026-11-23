// Fill the particle free list, seed beads and the mist field.
struct Free { top: atomic<i32>, idx: array<u32> };
@group(0) @binding(1) var<storage, read_write> P: array<vec4f>;
@group(0) @binding(2) var<storage, read_write> F: Free;
@group(0) @binding(3) var<storage, read_write> B: array<vec4f>;
@group(0) @binding(4) var fieldOut: texture_storage_2d<rgba16float, write>;
@compute @workgroup_size(64) fn particles(@builtin(global_invocation_id) g: vec3u) {
  let n = arrayLength(&P); if (g.x >= n) { return; }
  P[g.x] = vec4f(-1e6, 0.0, 0.0, U.seed * 0.0);
  F.idx[g.x] = g.x;
  if (g.x == 0u) { atomicStore(&F.top, i32(n)); }
}
@compute @workgroup_size(64) fn beads(@builtin(global_invocation_id) g: vec3u) {
  let n = U.beadGrid.x * U.beadGrid.y; if (g.x >= n) { return; }
  let s = g.x * 4u + u32(U.seed) * 7919u;
  // Mature glass: many tiny beads, a thin tail of big ones.
  let r = 0.35 + 0.75 * rnd(s) + 2.6 * pow(rnd(s + 1u), 14.0);
  B[g.x] = vec4f(rnd(s + 2u), rnd(s + 3u), r * r * r, rnd(s + 9u));
}
@compute @workgroup_size(8, 8) fn field(@builtin(global_invocation_id) g: vec3u) {
  let d = textureDimensions(fieldOut); let p = (vec2f(g.xy) + 0.5) / vec2f(d) * U.size;
  textureStore(fieldOut, vec2i(g.xy), vec4f(0.70 + 0.30 * cloud(p * 0.007 + U.seed), 0.0, 0.0, 1.0));
}
