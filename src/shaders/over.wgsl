@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var src: texture_2d<f32>;
struct VO { @builtin(position) pos: vec4f, @location(0) uv: vec2f };
@vertex fn vs(@builtin(vertex_index) v: u32) -> VO { var o: VO; o.uv = vec2f(f32((v << 1u) & 2u), f32(v & 2u)); o.pos = vec4f(o.uv * vec2f(2, -2) + vec2f(-1, 1), 0, 1); return o; }
@fragment fn over(i: VO) -> @location(0) vec4f { return textureSampleLevel(src, samp, i.uv, 0.5) + U.dt * 0.0; }
