@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var src: texture_2d<f32>;
@group(0) @binding(3) var glow: texture_2d<f32>;
struct VO { @builtin(position) pos: vec4f, @location(0) uv: vec2f };
@vertex fn vs(@builtin(vertex_index) v: u32) -> VO { var o: VO; o.uv = vec2f(f32((v << 1u) & 2u), f32(v & 2u)); o.pos = vec4f(o.uv * vec2f(2, -2) + vec2f(-1, 1), 0, 1); return o; }
fn tent(uv: vec2f, lod: f32) -> vec3f {
  let t = exp2(lod) / U.canvas; var s = vec3f(0.0);
  for (var y = -1; y <= 1; y++) { for (var x = -1; x <= 1; x++) { s += textureSampleLevel(src, samp, uv + vec2f(f32(x), f32(y)) * t, lod).rgb * f32((2 - abs(x)) * (2 - abs(y))); } }
  return s / 16.0;
}
// AgX (Troy Sobotka), polynomial approximation by Benjamin Wrensch.
fn agx(c0: vec3f) -> vec3f {
  let m = mat3x3f(0.842479062253094, 0.0423282422610123, 0.0423756549057051, 0.0784335999999992, 0.878468636469772, 0.0784336, 0.0792237451477643, 0.0791661274605434, 0.879142973793104);
  var v = m * c0; v = clamp(log2(max(v, vec3f(1e-10))), vec3f(-12.47393), vec3f(4.026069)); v = (v + 12.47393) / 16.5;
  let x2 = v * v; let x4 = x2 * x2;
  v = 15.5 * x4 * x2 - 40.14 * x4 * v + 31.96 * x4 - 6.868 * x2 * v + 0.4298 * x2 + 0.1191 * v - 0.00232;
  // A little contrast and saturation, the "punchy" look.
  let l = dot(v, vec3f(0.2126, 0.7152, 0.0722)); v = pow(max(v, vec3f(0.0)), vec3f(1.22)); let l2 = dot(v, vec3f(0.2126, 0.7152, 0.0722));
  v = l2 + (v - l2) * 1.38;
  let inv = mat3x3f(1.19687900512017, -0.0528968517574562, -0.0529716355144438, -0.0980208811401368, 1.15190312990417, -0.0980434501171241, -0.0990297440797205, -0.0989611768448433, 1.15107367264116);
  return clamp(inv * v, vec3f(0.0), vec3f(1.0)) + l * 0.0;   // display-encoded
}
@fragment fn bloom(i: VO) -> @location(0) vec4f { return vec4f(tent(i.uv, 2.0) * 0.30 + tent(i.uv, 3.0) * 0.28 + tent(i.uv, 4.0) * 0.24 + tent(i.uv, 5.0) * 0.18, 1.0); }
@fragment fn fs(i: VO) -> @location(0) vec4f {
  var c = textureSampleLevel(src, samp, i.uv, 0.0).rgb;
  let bloom = textureSampleLevel(glow, samp, i.uv, 0.0).rgb;
  c = mix(c, bloom, 0.13) * 1.6;
  var o = agx(c);
  let g = rnd(u32(i.pos.x) + u32(i.pos.y) * 5119u + u32(U.frame) * 7919u) - 0.5;
  o += g * 0.020 * (1.0 - 0.6 * dot(o, vec3f(0.33)));
  if (U.hdrPeak > 1.0) { let hi = max(dot(c, vec3f(0.3, 0.6, 0.1)) - 2.0, 0.0); o *= 1.0 + min(hi * 0.12, U.hdrPeak - 1.0); }
  return vec4f(o, 1.0);
}
