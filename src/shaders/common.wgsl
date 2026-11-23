// Shared by every pass. Distances are in "glass units": the pane is always 900 units tall.
struct Finger { a: vec2f, b: vec2f, vel: vec2f, r: f32, on: f32 };
struct Uniforms {
  size: vec2f, canvas: vec2f,
  time: f32, dt: f32, frame: f32, seed: f32,
  beadGrid: vec2u, cellGrid: vec2u,
  rain: f32, growth: f32, hdrPeak: f32, pace: f32,   // pace: simulation steps covered by one fog/bead run (2 when idle)
  fingers: array<Finger, 8>,
  lamps: array<vec4f, 36>,   // pos+radius, colour: 18 paper lanterns
  bulbs: array<vec4f, 52>,   // pos+radius, colour: 26 far pinpoints
  breaths: array<vec4f, 5>,  // xy, radius, strength: someone exhaling on the glass
  grow: vec4f,               // tree age, seconds into its ending, light, blossom count
  treePos: vec4f,            // canopy centre, presence
  wind: vec4f,               // gust now, direction of the final gust, history phase, where gusts start (x)
  gusts: array<vec4f, 16>,   // the last four seconds of wind, 15 samples a second, newest first
  world: array<vec4f, 5>,    // age, seconds into its ending, light, letter's screen x (-1..1): shore, stream, field, birds, bear
  pane: vec4f,               // anything growing (0/1), its light, unused, 1 = dry glass (checks only)
  cursor: vec4f,             // the pointer's drop: xy, radius (0 hidden), pressed
  cursorV: vec4f,            // its stretch xy, opacity
  bear: array<vec4f, 3>,     // position, yaw | step phase, stride, head yaw, head pitch | scale, fade, breath, unused
  thin: array<vec4f, 2>,     // fog held thin for things that move: uv, radius, strength
};
@group(0) @binding(0) var<uniform> U: Uniforms;

const PARTICLE_MASS: f32 = 5.0;   // in bead volume units (r^3)
const SPLAT_R: f32 = 3.6;
const LIQ_T: f32 = 0.40;           // iso level of the liquid field

fn pcg(v: u32) -> u32 { let s = v * 747796405u + 2891336453u; let w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u; return (w >> 22u) ^ w; }
fn rnd(v: u32) -> f32 { return f32(pcg(v)) / 4294967295.0; }
fn hash21(p: vec2f) -> f32 { let q = vec2u(vec2i(floor(p)) + 32768); return rnd(q.x + pcg(q.y)); }
fn hash22(p: vec2f) -> vec2f { let q = vec2u(vec2i(floor(p)) + 32768); let a = pcg(q.x + pcg(q.y)); return vec2f(rnd(a), rnd(a + 7919u)); }
fn vnoise(p: vec2f) -> f32 {
  let i = floor(p); var f = fract(p); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2f(1, 0)), f.x), mix(hash21(i + vec2f(0, 1)), hash21(i + vec2f(1, 1)), f.x), f.y);
}
const ROT = mat2x2f(0.80, 0.60, -0.60, 0.80);   // turn each octave so no grid lines up with the screen
fn fbm(p0: vec2f) -> f32 { var p = ROT * p0; var a = 0.5; var s = 0.0; for (var i = 0; i < 4; i++) { s += a * vnoise(p); p = ROT * p * 2.03 + 17.1; a *= 0.5; } return s / 0.9375; }
// Gradient noise: rounder than value noise, whose blobs read as squares once thresholded.
fn grad(i: vec2f, f: vec2f) -> f32 { let a = hash21(i) * 6.2831853; return dot(vec2f(cos(a), sin(a)), f); }
fn gnoise(p0: vec2f) -> f32 {
  let p = ROT * p0; let i = floor(p); let f = fract(p); let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  return 0.5 + 0.72 * mix(mix(grad(i, f), grad(i + vec2f(1, 0), f - vec2f(1, 0)), u.x), mix(grad(i + vec2f(0, 1), f - vec2f(0, 1)), grad(i + vec2f(1, 1), f - vec2f(1, 1)), u.x), u.y);
}
// Domain-warped gradient noise: wandering, cloud-like.
fn cloud(p: vec2f) -> f32 { let w = vec2f(gnoise(p * 0.7 + 11.0), gnoise(p * 0.7 + 47.0)) - 0.5; return 0.65 * gnoise(p + w * 1.8) + 0.35 * gnoise((ROT * p) * 2.3 + w * 2.4 + 5.0); }
fn onPath(p: vec2f, a: vec2f, b: vec2f) -> vec2f { let ba = b - a; return a + ba * clamp(dot(p - a, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0); }
// Wind reaches a place late, by how far it is from where the gust began.
fn gustAt(i: i32) -> f32 { let j = clamp(i, 0, 63); return U.gusts[j / 4][j % 4]; }
fn windAt(p: vec3f) -> f32 {
  let d = min(abs(p.x - U.wind.w) / 3.4 + 0.10 * max(p.y - 1.0, 0.0) + 0.18 * sin(p.x * 2.1 + p.y * 3.3), 3.9);
  let s = max(d, 0.0) * 15.0 + U.wind.z; let i = i32(floor(s)); return mix(gustAt(i), gustAt(i + 1), fract(s));
}
fn camPos() -> vec3f { return vec3f(0.12 + sin(U.time * 0.11) * 0.01, 1.62 + sin(U.time * 0.083) * 0.01, 0.0); }
fn capsule(p: vec2f, a: vec2f, b: vec2f) -> f32 { let pa = p - a; let ba = b - a; let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0); return length(pa - ba * h); }
