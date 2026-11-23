// Falling snow (流). Nothing stored: each flake has a place on the pane and a depth from its number, and
// falls through its own column, wrapping from the ground back to the top of the view. Flakes are 4-10 mm,
// fall at 0.5-0.9 m/s with a slow flutter, and are pushed by the wind a wipe makes (displacement only:
// they drift back once the gust has passed, which is an approximation of being carried).
// This layer is redrawn at half the frame rate, so each flake is drawn as the short streak a camera's
// shutter would catch (1/90 s), rather than jumping from place to place.
const FLAKES: u32 = 14000u;
struct SV { @builtin(position) pos: vec4f, @location(0) q: vec2f, @location(1) @interpolate(flat) c: vec4f, @location(2) @interpolate(flat) k: vec4f };
fn flakeAt(id: u32, t: f32) -> vec4f {
  let h = vec4f(rnd(id * 4u + 7u), rnd(id * 4u + 8u), rnd(id * 4u + 9u), rnd(id * 4u + 10u));
  let z = 0.9 + 13.0 * pow(h.y, 1.6); let asp = U.size.x / U.size.y;
  let top = 1.62 + (1.0 - 0.06) * 0.59 * z + 0.4; let H = top + 0.05; let v = mix(0.45, 0.85, h.z);
  let fall = fract(t * v / H + h.w); let cyc = floor(t * v / H + h.w);
  var p = vec3f(across(h.x * 2.4 - 1.2, z), top - fall * H, z);
  let ph = h.w * 40.0 + cyc * 3.1;
  p.x += 0.07 * sin(t * (0.9 + h.z) + ph) + 0.025 * sin(t * 2.3 + ph * 1.7); p.z += 0.03 * cos(t * (0.9 + h.x) + ph);
  p.x += windAt(p) * (0.9 + 0.6 * h.z);
  return vec4f(p, cyc);
}
@vertex fn vsSnow(@builtin(vertex_index) vi: u32, @builtin(instance_index) id: u32) -> SV {
  var o: SV; let W = U.world[1]; let dens = W.z;
  let h = rnd(id * 4u + 11u); let f = flakeAt(id, U.time); let cyc = f.w;
  // How heavy the fall is decides how many flakes take part; each flake keeps its turn for a whole fall.
  let keep = rnd(id * 9u + u32(cyc) * 131u); if (keep > dens * (0.25 + 0.75 * smoothstep(0.0, 14.0, W.x)) || W.x <= 0.0) { o.pos = HIDE; return o; }
  let p = f.xyz; let p0 = flakeAt(id, U.time - 1.0 / 90.0).xyz;   // a short exposure: snow should read as flakes, not rain
  let c = project(p); let c0 = project(p0);
  if (c.w < 0.3 || p.y < 0.0) { o.pos = HIDE; return o; }
  // Size: the flake, but never under ~1 px, keeping its light; near ones swell a little out of focus.
  // Radius: 4-10 mm flakes, the clumped kind of a heavy fall.
  let r0 = mix(0.0018, 0.0050, h * h); let px = 2.0 * 0.59 * c.w / 1000.0; let R = max(r0 * (1.0 + 0.6 / c.w), px * 0.8);
  let asp = U.size.x / U.size.y; let s = vec2f(1.0 / (asp * 0.59), 1.0 / 0.59);
  let a = c.xy / c.w; let b = c0.xy / c0.w; let d = (a - b) * vec2f(asp, 1.0); let L = length(d); let dir = select(vec2f(0.0, 1.0), d / max(L, 1e-5), L > 1e-5); let side = vec2f(-dir.y, dir.x);
  // Depth of field, as a photograph focused about 3 m out: flakes near the lens spread into soft discs,
  // those near the focus stay small and crisp. Circle of confusion in NDC height units.
  let coc = 0.0075 * abs(1.0 - 3.0 / c.w);
  let q = QUAD[vi]; let sharp = R / c.w * 1.0 / 0.59; let rr = max(sharp, coc);   // radius in NDC (height units)
  let along = q.y * (L * 0.5 + rr); let mid = (a + b) * 0.5;
  let ndc = mid + (dir * along + side * q.x * rr) / vec2f(asp, 1.0);
  o.pos = vec4f(ndc * c.w, (c.w - 0.3) * 1.02, c.w); o.q = vec2f(q.x, along / max(L * 0.5 + rr, 1e-6));
  // Lit by the street's lanterns from every side (a flake scatters light all round), and the night sky.
  let lt = litBase(p, normalize(camPos() - p), 1.0, 0.0); let light = (lt.a + lt.b) * 0.9 + vec3f(0.09, 0.105, 0.15);
  let energy = pow(min(1.0, (r0 * r0) / (R * R)), 0.6) * pow(min(1.0, (sharp * sharp) / (rr * rr)), 0.75) * sqrt(rr / (L * 0.5 + rr));   // a bigger drawn disc or a longer streak is fainter (softened: the eye sees flakes, not a sum of light)
  o.c = vec4f(light * vec3f(0.92, 0.95, 1.0), energy); o.k = vec4f(L / max(L + 2.0 * rr, 1e-6), smoothstep(0.0, 0.6, p.y), smoothstep(1.2, 2.5, coc / max(sharp, 1e-6)), h * 97.0 + f.w * 13.0); return o;
}
@fragment fn fsSnow(i: SV) -> @location(0) vec4f {
  let y = max(abs(i.q.y) - i.k.x, 0.0) / max(1.0 - i.k.x, 1e-3); let v = vec2f(i.q.x, y); let r = length(v);
  // In focus: a small clump of crystals, its outline uneven. Out of focus: the lens's disc, evenly lit with
  // a slightly brighter rim and a soft edge, as in a night photograph of falling snow.
  let th = atan2(v.y, v.x); let edge = 0.72 + 0.16 * sin(th * 3.0 + i.k.w) + 0.10 * sin(th * 5.0 + i.k.w * 1.7);
  let clump = (1.0 - smoothstep(edge * 0.55, edge, r)) * (0.75 + 0.25 * sin(th * 6.0 + i.k.w * 2.3) * (1.0 - r));
  let disc = (1.0 - smoothstep(0.86, 1.0, r)) * (0.82 + 0.25 * smoothstep(0.55, 0.95, r));
  let m = mix(clump, disc, i.k.z); let a = m * i.c.w * 0.95 * i.k.y; return vec4f(i.c.rgb * a, a);
}
