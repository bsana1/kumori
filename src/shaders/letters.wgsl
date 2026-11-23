// The name. Stroke segments are drawn into a mask that keeps glass clear of fog (r),
// and, when a letter is touched, they release water along their length.
struct Seg { a: vec2f, b: vec2f, r: f32, alpha: f32, rate: f32, pad: f32 };
struct Req { n: atomic<u32>, pad: array<u32, 3>, data: array<vec4f> };
@group(0) @binding(1) var<storage, read> G: array<Seg>;
@group(0) @binding(2) var<storage, read_write> R: Req;
struct VO { @builtin(position) pos: vec4f, @location(0) p: vec2f, @location(1) @interpolate(flat) i: u32 };
const QUAD = array<vec2f, 6>(vec2f(-1, -1), vec2f(1, -1), vec2f(-1, 1), vec2f(-1, 1), vec2f(1, -1), vec2f(1, 1));
@vertex fn vs(@builtin(vertex_index) v: u32, @builtin(instance_index) i: u32) -> VO {
  let s = G[i]; let l = length(s.b - s.a); let d = select(vec2f(1, 0), (s.b - s.a) / max(l, 1e-4), l > 1e-3); let n = vec2f(-d.y, d.x); let w = s.r + 5.0;
  var o: VO; o.i = i; o.p = (s.a + s.b) * 0.5 + d * QUAD[v].x * (l * 0.5 + w) + n * QUAD[v].y * w;
  let c = o.p / U.size * 2.0 - 1.0; o.pos = vec4f(c.x, -c.y, 0, 1); if (s.alpha <= 0.0) { o.pos = vec4f(2, 2, 2, 1); } return o;
}
@fragment fn fs(i: VO) -> @location(0) vec4f {
  let s = G[i.i];
  // Skin drags unevenly: the edge wanders a little, and wanders the same way every frame.
  let q = i.p + (vec2f(gnoise(i.p * 0.10), gnoise(i.p * 0.10 + 70.0)) - 0.5) * 3.2;
  let d = capsule(q, s.a, s.b); return vec4f(s.alpha * (1.0 - smoothstep(s.r - 2.0, s.r + 1.2, d)), 0, 0, 1);
}
@compute @workgroup_size(64) fn emit(@builtin(global_invocation_id) g: vec3u) {
  if (g.x >= arrayLength(&G)) { return; }
  let s = G[g.x]; if (s.rate <= 0.0) { return; }
  let k = g.x * 97u + u32(U.frame) * 15731u; let n = u32(s.rate) + select(0u, 1u, rnd(k) < fract(s.rate));
  let d = normalize(s.b - s.a + vec2f(1e-4, 0)); let nrm = vec2f(-d.y, d.x);
  for (var j = 0u; j < n; j++) {
    let i = atomicAdd(&R.n, 1u); if (i >= arrayLength(&R.data)) { return; }
    R.data[i] = vec4f(mix(s.a, s.b, rnd(k + 3u + j * 2u)) + nrm * (rnd(k + 4u + j * 2u) - 0.5) * s.r * 1.1, 0.0, 0.0);
  }
}
