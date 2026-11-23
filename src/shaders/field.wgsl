// Mist density (r), wet film left by water or a finger (g).
struct Req { n: atomic<u32>, pad: array<u32, 3>, data: array<vec4f> };
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var prev: texture_2d<f32>;
@group(0) @binding(3) var liq: texture_2d<f32>;
@group(0) @binding(4) var out: texture_storage_2d<rgba16float, write>;
@group(0) @binding(5) var<storage, read_write> R: Req;
@group(0) @binding(6) var mask: texture_2d<f32>;
@group(0) @binding(7) var grown: texture_2d<f32>;

const MIST_MASS: f32 = 0.05;       // bead-volume units held by one unit^2 of full mist

fn request(p: vec2f, v: vec2f) { let i = atomicAdd(&R.n, 1u); if (i < arrayLength(&R.data)) { R.data[i] = vec4f(p, v); } }

@compute @workgroup_size(8, 8) fn main(@builtin(global_invocation_id) g: vec3u) {
  let dim = vec2f(textureDimensions(out)); let uv = (vec2f(g.xy) + 0.5) / dim; let p = uv * U.size;
  let f = textureLoad(prev, vec2i(g.xy), 0); var mist = f.r; var wet = f.g;
  let inL = smoothstep(LIQ_T * 0.8, LIQ_T * 1.3, textureSampleLevel(liq, samp, uv, 0.0).r);

  // Cold glass: more fog low and toward the frame, uneven everywhere.
  let edge = length((uv - vec2f(0.5, 0.42)) * vec2f(1.0, 0.9));
  // Per-frame growth is below half-float precision and would round away, so each texel takes an
  // eight-frame step on its own turn. The turn is hashed: an ordered one shows as a weave.
  let turn = (pcg(g.x + pcg(g.y)) + u32(U.frame / U.pace)) % 8u == 0u;
  if (turn) {
    let aim = clamp(0.60 + 0.34 * cloud(p * 0.007 + U.seed) + 0.28 * edge, 0.0, 1.0);
    // Fog creeps in from fog: growth is quicker beside it, and a little diffusion rounds the front.
    let t = 1.0 / dim; let spin = rnd(g.x * 31u + g.y * 4099u + u32(U.frame / U.pace)) * 6.2831853;
    let d0 = vec2f(cos(spin), sin(spin)); let d1 = vec2f(-d0.y, d0.x);
    let near = 0.25 * (textureSampleLevel(prev, samp, uv + d0 * 1.6 * t, 0.0).r + textureSampleLevel(prev, samp, uv - d0 * 1.6 * t, 0.0).r + textureSampleLevel(prev, samp, uv + d1 * 1.6 * t, 0.0).r + textureSampleLevel(prev, samp, uv - d1 * 1.6 * t, 0.0).r);
    let far = 0.25 * (textureSampleLevel(prev, samp, uv + d0 * 9.0 * t, 0.0).r + textureSampleLevel(prev, samp, uv - d0 * 9.0 * t, 0.0).r + textureSampleLevel(prev, samp, uv + d1 * 9.0 * t, 0.0).r + textureSampleLevel(prev, samp, uv - d1 * 9.0 * t, 0.0).r);
    let speed = 0.085 * (0.45 + 0.9 * cloud(p * 0.03 + 5.0)) * (0.40 + 1.0 * far) * (1.0 - 0.92 * wet);
    mist += (aim - mist) * speed * (U.dt * U.pace) * 8.0;
    mist += (near - mist) * 0.05 * (1.0 - inL);
  }
  // A drop clears most of the fog under it; a soft patchy remnant stays in its track.
  if (inL > 0.001) { mist = mix(mist, min(mist, 0.05 + 0.24 * smoothstep(0.42, 0.85, cloud(p * vec2f(0.30, 0.20)))), inL * select(0.4, 0.64, U.pace > 1.5)); }
  for (var i = 0; i < 5; i++) {
    let B = U.breaths[i]; if (B.w <= 0.0) { continue; }
    let d = length(p - B.xy) / B.z; if (d > 1.5) { continue; }
    let puff = B.w * exp(-d * d * 1.7) * (0.55 + 0.9 * cloud(p * 0.018 + B.xy)); mist += max(0.0, 0.97 - mist) * min(1.0, puff * (U.dt * U.pace)) * (1.0 - inL);
  }
  // What grows outside warms the pane: fog thins wherever it can be seen, except around letters
  // nobody has touched yet. Slow, so it also runs only on this texel's turn.
  if (turn && U.pane.y > 0.0) {
    var c = max(textureSampleLevel(grown, samp, uv, 3.0).a, min(1.0, 1.5 * textureSampleLevel(grown, samp, uv, 5.0).a)) * U.pane.y;
    for (var i = 0; i < 2; i++) { let T = U.thin[i]; if (T.w > 0.0) { let d = length((uv - T.xy) * vec2f(U.size.x / U.size.y, 1.35)) / T.z; c = max(c, T.w * (1.0 - smoothstep(0.35, 1.0, d + 0.5 * (cloud(p * 0.006 + 3.0) - 0.5)))); } }
    if (c > 0.004) {
      var keep = 0.0;
      for (var i = 0; i < 5; i++) { let B = U.breaths[i]; let d = length(p - B.xy) / max(B.z, 1.0); if (B.w < 0.0 && d < 1.35) { keep = max(keep, 1.0 - smoothstep(0.62, 1.12, d + 0.35 * (cloud(p * 0.02) - 0.5))); } }
      if (keep < 1.0) { let n = cloud(p * 0.025); mist = mix(mist, min(mist, 0.04 + 0.10 * n), clamp(c * (1.0 - keep) * (0.5 + n) * 1.1 * (U.dt * U.pace) * 8.0, 0.0, 1.0)); }
    }
  }
  let letter = textureSampleLevel(mask, samp, uv, 0.0).r;
  if (letter > 0.002) { mist = mix(mist, min(mist, 0.03 + 0.05 * gnoise(p * 0.25)), letter * select(0.35, 0.58, U.pace > 1.5)); }
  // A widened copy of the letters, for the misty ridge the glass shader draws beside each stroke.
  let hx = vec2f(3.2 / U.size.x, 0.0); let hy = vec2f(0.0, 3.2 / U.size.y);
  let halo = max(letter, max(max(textureSampleLevel(mask, samp, uv + hx, 0.0).r, textureSampleLevel(mask, samp, uv - hx, 0.0).r), max(textureSampleLevel(mask, samp, uv + hy, 0.0).r, textureSampleLevel(mask, samp, uv - hy, 0.0).r)));
  wet = max(wet * exp(-(U.dt * U.pace) * 0.28), inL);

  for (var i = 0; i < 8; i++) {
    let k = U.fingers[i]; if (k.on < 0.5) { continue; }
    if (capsule(p, k.a, k.b) > k.r + 10.0) { continue; }
    let lump = (cloud(p * 0.12) - 0.5) * 5.0;
    let d = capsule(p, k.a, k.b) + lump; if (d > k.r + 4.0) { continue; }
    let m = 1.0 - smoothstep(k.r - 4.0, k.r + 2.0, d);
    // A finger leaves a thin greasy film with streaks along its path.
    let dir = normalize(k.vel + vec2f(0.001, 0.0)); let across = dot(p - k.b, vec2f(-dir.y, dir.x));
    let keep = 0.03 + 0.07 * gnoise(vec2f(across * 0.8, dot(p, dir) * 0.02));
    let wiped = max(0.0, mist - keep) * m; mist -= wiped;
    wet = max(wet, m * 0.45);
    let mass = wiped * (U.size.x / dim.x) * (U.size.y / dim.y) * MIST_MASS;
    let s = g.x + g.y * 4099u + u32(U.frame / U.pace) * 7621u + u32(i);
    if (rnd(s) < mass / PARTICLE_MASS) {
      // Wiped water is shoved to the rim of the finger, mostly sideways and ahead.
      let side = select(-1.0, 1.0, across > 0.0);
      let rim = onPath(p, k.a, k.b) + vec2f(-dir.y, dir.x) * side * (k.r + 1.5 + 3.0 * rnd(s + 1u)) + dir * (rnd(s + 2u) * 0.9 - 0.2) * k.r;
      request(rim, k.vel * 0.04);
    }
  }
  textureStore(out, vec2i(g.xy), vec4f(clamp(mist, 0.0, 1.0), wet, halo, 1.0));
}
