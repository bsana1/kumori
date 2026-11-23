@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var src: texture_2d<f32>;
struct VO { @builtin(position) pos: vec4f, @location(0) uv: vec2f };
@vertex fn vs(@builtin(vertex_index) v: u32) -> VO { var o: VO; o.uv = vec2f(f32((v << 1u) & 2u), f32(v & 2u)); o.pos = vec4f(o.uv * vec2f(2, -2) + vec2f(-1, 1), 0, 1); return o; }
fn gauss(uv: vec2f, dir: vec2f, sigma: f32) -> vec4f {   // sigma in glass units
  var s = vec4f(0); var w = 0.0;
  for (var i = -4; i <= 4; i++) { let x = f32(i) / 4.0 * 2.2; let k = exp(-0.5 * x * x); s += textureSampleLevel(src, samp, uv + dir * x * sigma / U.size, 0.0) * k; w += k; }
  return s / w;
}
fn five(uv: vec2f, dir: vec2f) -> vec4f {
  let s = 0.95 / U.size; var c = textureSampleLevel(src, samp, uv, 0.0) * 0.357;
  for (var i = 1; i <= 2; i++) { let o = dir * f32(i) * 0.9 * s; c += (textureSampleLevel(src, samp, uv + o, 0.0) + textureSampleLevel(src, samp, uv - o, 0.0)) * select(0.0835, 0.238, i == 1); }
  return c;
}
@fragment fn narrowX(i: VO) -> @location(0) vec4f { return five(i.uv, vec2f(1, 0)); }
@fragment fn narrowY(i: VO) -> @location(0) vec4f { return five(i.uv, vec2f(0, 1)); }
@fragment fn wideX(i: VO) -> @location(0) vec4f { return gauss(i.uv, vec2f(1, 0), 6.0); }
@fragment fn wideY(i: VO) -> @location(0) vec4f { return gauss(i.uv, vec2f(0, 1), 6.0); }
@fragment fn copy(i: VO) -> @location(0) vec4f { return textureSampleLevel(src, samp, i.uv, 0.0) + U.dt * 0.0; }
