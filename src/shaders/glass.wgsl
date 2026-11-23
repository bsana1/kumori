// Everything the eye sees on the pane: fog, beads, running water.
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var scene: texture_2d<f32>;
@group(0) @binding(3) var clearV: texture_2d<f32>;
@group(0) @binding(4) var fogV: texture_2d<f32>;
@group(0) @binding(5) var field: texture_2d<f32>;
@group(0) @binding(6) var liq: texture_2d<f32>;
@group(0) @binding(7) var wide: texture_2d<f32>;
@group(0) @binding(8) var beads: texture_2d<f32>;
@group(0) @binding(9) var mask: texture_2d<f32>;
@group(0) @binding(10) var grown: texture_2d<f32>;
@group(0) @binding(14) var noiseS: sampler;
@group(0) @binding(15) var noiseT: texture_2d<f32>;
// One-tap value noise from a small random texture: much cheaper than hashing in full-screen passes.
fn nz(p: vec2f) -> f32 { let i = floor(p); let f = fract(p); return textureSampleLevel(noiseT, noiseS, (i + f * f * (3.0 - 2.0 * f) + 0.5) / 256.0, 0.0).r; }
fn fbz(p0: vec2f) -> f32 { var p = ROT * p0; var a = 0.5; var s = 0.0; for (var i = 0; i < 4; i++) { s += a * nz(p); p = ROT * p * 2.03 + 17.1; a *= 0.5; } return s / 0.9375; }
struct VO { @builtin(position) pos: vec4f, @location(0) uv: vec2f };
@vertex fn vs(@builtin(vertex_index) v: u32) -> VO { var o: VO; o.uv = vec2f(f32((v << 1u) & 2u), f32(v & 2u)); o.pos = vec4f(o.uv * vec2f(2, -2) + vec2f(-1, 1), 0, 1); return o; }

// The fog map is coarser than the screen; B-spline filtering hides its texels.
fn smoothField(uv: vec2f) -> vec4f {
  let d = vec2f(textureDimensions(field)); let st = uv * d - 0.5; let i = floor(st); let f = st - i;
  let w0 = (1.0 - f) * (1.0 - f) * (1.0 - f) / 6.0; let w1 = (4.0 - 6.0 * f * f + 3.0 * f * f * f) / 6.0; let w3 = f * f * f / 6.0; let w2 = 1.0 - w0 - w1 - w3;
  let g0 = w0 + w1; let g1 = w2 + w3; let a = (i - 0.5 + w1 / g0) / d; let b = (i + 1.5 + w3 / g1) / d;
  return g0.y * (g0.x * textureSampleLevel(field, samp, vec2f(a.x, a.y), 0.0) + g1.x * textureSampleLevel(field, samp, vec2f(b.x, a.y), 0.0))
       + g1.y * (g0.x * textureSampleLevel(field, samp, vec2f(a.x, b.y), 0.0) + g1.x * textureSampleLevel(field, samp, vec2f(b.x, b.y), 0.0));
}
fn rawField(uv: vec2f) -> f32 {
  let a = textureSampleLevel(liq, samp, uv, 0.0).r; let w = textureSampleLevel(wide, samp, uv, 0.0).r;
  return a * 0.75 + w * smoothstep(0.1, 0.6, a) * 0.55 + (nz(uv * U.size * 0.22) - 0.5) * 0.07;
}
fn heightOf(f: f32) -> f32 { return 2.3 * sqrt(max(f - LIQ_T, 0.0) + 0.0008); }

// The dim room behind us, as faintly reflected by the water.
fn room(d: vec3f) -> vec3f {
  let panel = smoothstep(0.10, 0.02, abs(d.x + 0.30) - 0.10) * smoothstep(0.10, 0.02, abs(d.y - 0.42) - 0.12);
  return vec3f(0.018, 0.016, 0.018) + vec3f(1.0, 0.90, 0.78) * panel * 1.1 + vec3f(0.03, 0.04, 0.07) * smoothstep(0.0, 0.9, d.y);
}
// Look through a water lens. n: surface normal, power: how strongly it bends.
fn lens(uv: vec2f, n: vec3f, power: f32, lod: f32) -> vec3f {
  let dir = n.xy * power / vec2f(U.size.x / U.size.y, 1.0);
  let u0 = uv - dir * 0.985; let u1 = uv - dir; let u2 = uv - dir * 1.018;
  var c = vec3f(textureSampleLevel(scene, samp, u0, lod).r, textureSampleLevel(scene, samp, u1, lod).g, textureSampleLevel(scene, samp, u2, lod).b);
  let o = max(abs(u1 - 0.5) - 0.5, vec2f(0.0)); c *= exp(-dot(o, o) * 30.0);
  // Grazing rays are totally reflected: the dark rim every real drop has.
  let rim = smoothstep(0.16, 0.62, n.z); c *= mix(0.16, 1.45, rim); c += vec3f(0.020, 0.022, 0.028) * rim;
  let fr = 0.02 + 0.6 * pow(1.0 - n.z, 4.0);
  let rd = reflect(vec3f(0, 0, -1), n);
  return c + room(vec3f(rd.x, -rd.y, rd.z)) * fr * 1.6;
}
@fragment fn fs(i: VO) -> @location(0) vec4f {
  let uv = i.uv; let p = uv * U.size; let e = 0.9 / U.size;
  let fl = smoothField(uv); let pr = ROT * p;
  let mist = smoothstep(0.02, 0.95, fl.r) * (1.0 - U.pane.w);

  // ---- bare glass and fog
  let clearC = textureSampleLevel(clearV, samp, uv, 0.0).rgb;
  let grit = vec2f(nz(p * 1.9), nz(p * 1.9 + 60.0)) - 0.5;
  let fogC = textureSampleLevel(fogV, samp, uv + grit * 5.0 / U.size * mist, 0.0).rgb;
  let fogWide = textureSampleLevel(fogV, samp, uv + grit.yx * 30.0 / U.size, 0.0).rgb;
  let lum = dot(fogC, vec3f(0.25, 0.6, 0.15));
  // Scattered light lifts and greys the dark areas, as fog on a window does.
  var veil = fogC * 0.60 + fogWide * 0.36 + vec3f(0.098, 0.106, 0.122) * (0.6 + 0.8 * (0.62 * nz(pr * 0.014) + 0.38 * nz((ROT * pr) * 0.037 + 5.0))) + lum * vec3f(0.12);
  let micro = nz(pr * 2.6) * nz((ROT * pr) * 5.1 + 9.0);
  veil *= 0.90 + 0.42 * micro;
  var c = mix(clearC, veil, mist);
  // A wiped or wet patch keeps a thin film that smears the lights a little.
  let film = fl.g * (1.0 - mist); let wob = vec2f(nz(pr * 0.11), nz(pr * 0.11 + 20.0)) - 0.5;
  c = mix(c, textureSampleLevel(clearV, samp, uv + wob * 9.0 / U.size * film, 0.0).rgb, film * 0.8 * (1.0 - mist));

  // The growth sits nearer than the street, so it is drawn over the defocused view with a much smaller blur.
  if (U.pane.x > 0.0) {
    let vis = 1.0 - mist * 0.93;
    let gu = uv + wob * 9.0 / U.size * film; let r = 0.8 / U.size; var g = textureSampleLevel(grown, samp, gu, 0.0) * 0.36;
    g += (textureSampleLevel(grown, samp, gu + vec2f(r.x, r.y * 0.5), 0.0) + textureSampleLevel(grown, samp, gu + vec2f(-r.x * 0.5, r.y), 0.0) + textureSampleLevel(grown, samp, gu - vec2f(r.x, r.y * 0.5), 0.0) + textureSampleLevel(grown, samp, gu + vec2f(r.x * 0.5, -r.y), 0.0)) * 0.16;
    c = c * (1.0 - g.a * vis) + g.rgb * vis;
  }
  // Written strokes: bare glass loses the fog's glow, and a fine ridge of displaced mist edges them.
  let ink = textureSampleLevel(mask, samp, uv, 0.0).r;
  let halo = fl.b;
  c *= 1.0 - 0.30 * ink; c *= 1.0 + 0.20 * halo * (1.0 - ink) * mist;
  // ---- beads
  let b = textureSampleLevel(beads, samp, uv, 0.0);
  let L = rawField(uv); let inL = smoothstep(LIQ_T - 0.05, LIQ_T + 0.05, L);
  if (b.a > 0.01 && U.pane.w < 0.5) {
    let q = (b.xy / b.a - 0.5) * 2.0 * 0.93; let r = b.z / b.a * 5.0;
    let nz = sqrt(max(1.0 - dot(q, q), 0.0)); let n = normalize(vec3f(q.x, q.y, nz * 1.25 + 0.06));
    let bc = lens(uv, n, 0.22 + 0.03 * r, 2.6 - clamp(r * 0.35, 0.0, 1.4));
    c = mix(c, bc, b.a * smoothstep(0.25, 0.9, r + 0.25) * (1.0 - inL));
  }
  // ---- contact shadow and the soft glow a drop throws on the fog below it
  let sh = smoothstep(LIQ_T * 0.5, LIQ_T * 1.4, textureSampleLevel(liq, samp, uv - vec2f(-0.6, 2.6) / U.size, 0.0).r);
  c *= 1.0 - 0.30 * sh * (1.0 - inL) * (0.4 + 0.6 * mist);

  // ---- running water
  if (L > LIQ_T - 0.06) {
    let hx = heightOf(rawField(uv + vec2f(e.x, 0))) - heightOf(rawField(uv - vec2f(e.x, 0)));
    let hy = heightOf(rawField(uv + vec2f(0, e.y))) - heightOf(rawField(uv - vec2f(0, e.y)));
    let n = normalize(vec3f(-hx / 1.8, -hy / 1.8, 1.0));
    let h = heightOf(L);
    let wc = lens(uv, n, 0.30 + 0.045 * h, 1.0);
    // Light focused through the body of the drop gathers toward its lower edge.
    let caust = 1.0 + 0.35 * clamp(n.y, 0.0, 1.0) * smoothstep(1.0, 4.0, h);
    c = mix(c, wc * caust, inL);
  }
  // ---- the pointer: one round drop that rides on top of everything
  if (U.cursor.z > 0.0) {
    let R = U.cursor.z; let d = p - U.cursor.xy; let sv = U.cursorV.xy; let sp = length(sv); let dir = select(vec2f(0.0, -1.0), sv / max(sp, 1e-4), sp > 1e-3);
    var al = dot(d, dir); let ac = dot(d, vec2f(-dir.y, dir.x));
    al /= select(1.0 + 1.5 * sp, 1.0 + 0.15 * sp, al > 0.0);                // a tail behind, a blunt nose ahead
    let q = vec2f(al, ac * (1.0 + 0.45 * sp)) / R; let r = length(q); let on = U.cursorV.z;
    if (r < 2.4) {
      let sh = length((d - vec2f(0.6, 2.4)) / R); c *= 1.0 - 0.42 * on * (1.0 - smoothstep(0.65, 1.5, sh));
      let edge = 1.0 - smoothstep(0.94, 1.04, r);
      if (edge > 0.0) {
        let qs = (dir * q.x + vec2f(-dir.y, dir.x) * q.y) * 0.96; let n = normalize(vec3f(qs, sqrt(max(1.0 - dot(qs, qs), 0.0)) * 1.1 + 0.04));
        var w = lens(uv, n, 0.36, 1.2) * 1.25 + vec3f(0.035, 0.04, 0.048);
        w += vec3f(1.0, 0.97, 0.92) * 1.5 * (1.0 - smoothstep(0.10, 0.24, length(qs - vec2f(-0.34, -0.40))));           // window glint
        w += vec3f(0.75, 0.82, 0.95) * 0.55 * smoothstep(0.62, 0.86, r) * (1.0 - smoothstep(0.88, 0.97, r)) * smoothstep(0.1, 0.8, dot(qs, vec2f(0.5, 0.75)));   // light gathered low
        c = mix(c, w, edge * on);
      }
    }
  }
  // ---- the pane itself: soft vignette and the faintest room reflection
  let v = length((uv - 0.5) * vec2f(1.0, 0.92)); c *= 1.0 - 0.50 * smoothstep(0.36, 0.86, v);
  return vec4f(max(c, vec3f(0.0)), 1.0);
}
