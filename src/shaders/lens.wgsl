// The camera focuses on the glass, so the street is out of focus. Golden-angle gather.
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var src: texture_2d<f32>;
struct VO { @builtin(position) pos: vec4f, @location(0) uv: vec2f };
@vertex fn vs(@builtin(vertex_index) v: u32) -> VO { var o: VO; o.uv = vec2f(f32((v << 1u) & 2u), f32(v & 2u)); o.pos = vec4f(o.uv * vec2f(2, -2) + vec2f(-1, 1), 0, 1); return o; }
const TAU: f32 = 6.2831853;
fn gather(uv: vec2f, radius: f32, n: i32, lod: f32, soft: f32, jitter: f32) -> vec3f {
  var s = vec3f(0.0); var w = 0.0;
  for (var i = 0; i < n; i++) {
    let t = (f32(i) + 0.5) / f32(n); let r = sqrt(t); let a = f32(i) * 2.399963 + jitter;
    let k = mix(0.72 + 0.28 * r * r, exp(-2.6 * r * r), soft);       // bright-rimmed disc vs scattering lobe
    s += textureSampleLevel(src, samp, uv + vec2f(cos(a), sin(a)) * r * radius / U.size, lod).rgb * k; w += k;
  }
  return s / w;
}
@fragment fn clearView(i: VO) -> @location(0) vec4f { return vec4f(gather(i.uv, 9.5, 56, 1.2, 0.0, 0.0), 1.0); }
@fragment fn fogView(i: VO) -> @location(0) vec4f {
  // Fog is many overlapping scatter widths: a tight core keeps lights as discs, a wide skirt glows.
  let a = gather(i.uv, 30.0, 32, 2.3, 0.25, 0.0); let b = gather(i.uv, 105.0, 32, 4.1, 1.0, 1.3);
  return vec4f(a * 0.52 + b * 0.48, 1.0);
}
