// Particles -> additive liquid field; beads -> normal/height/coverage.
@group(0) @binding(1) var<storage, read> P: array<vec4f>;
struct VO { @builtin(position) pos: vec4f, @location(0) q: vec2f, @location(1) @interpolate(flat) r: f32 };
const QUAD = array<vec2f, 6>(vec2f(-1, -1), vec2f(1, -1), vec2f(-1, 1), vec2f(-1, 1), vec2f(1, -1), vec2f(1, 1));
fn place(c: vec2f, q: vec2f, r: f32) -> vec4f { let u = (c + q * r) / U.size * 2.0 - 1.0; return vec4f(u.x, -u.y, 0.0, 1.0); }
@vertex fn vsLiquid(@builtin(vertex_index) v: u32, @builtin(instance_index) i: u32) -> VO {
  let p = P[i]; var o: VO; o.q = QUAD[v]; o.r = SPLAT_R;
  // Stretch along motion so fast drops streak slightly.
  let sp = length(p.zw); let st = min(sp * 0.0022, 0.35);
  let d = select(vec2f(0, 1), p.zw / max(sp, 1e-3), sp > 1.0); let n = vec2f(-d.y, d.x);
  let off = d * o.q.y * (1.0 + st) + n * o.q.x * (1.0 - st * 0.5);
  o.pos = place(p.xy, off, SPLAT_R); if (p.x < -1e5) { o.pos = vec4f(2, 2, 2, 1); }
  return o;
}
@fragment fn fsLiquid(i: VO) -> @location(0) vec4f { let k = max(0.0, 1.0 - dot(i.q, i.q)); return vec4f(k * k * k, 0, 0, 1); }
@vertex fn vsBead(@builtin(vertex_index) v: u32, @builtin(instance_index) i: u32) -> VO {
  let b = P[i]; let c = vec2f(f32(i % U.beadGrid.x), f32(i / U.beadGrid.x)); let r = pow(max(b.z, 0.0), 0.3333);
  var o: VO; o.q = QUAD[v]; o.r = r; let w = r + 0.6 * U.size.y / U.canvas.y;
  o.q *= w / max(r, 0.01); o.pos = place((c + b.xy) * 3.0, QUAD[v], w); if (r < 0.15) { o.pos = vec4f(2, 2, 2, 1); }
  return o;
}
@fragment fn fsBead(i: VO) -> @location(0) vec4f {
  // Slightly irregular outline; real condensation beads are rarely true circles.
  let l2 = dot(i.q, i.q); let l = sqrt(l2); let aa = max(fwidth(l), 1e-3); let a = 1.0 - smoothstep(1.0 - aa, 1.0 + aa * 0.2, l);
  if (a <= 0.004) { discard; }
  return vec4f(i.q * 0.5 + 0.5, clamp(i.r / 5.0, 0.0, 1.0), a);
}
