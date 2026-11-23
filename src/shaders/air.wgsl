// Loose petals as bodies in moving air: they have momentum, so a gust has to catch them and carry them.
struct Petal { p: vec3f, age: f32, v: vec3f, spin: f32 };
struct Blossom { p: vec3f, birth: f32, n: vec3f, size: f32, seed: f32, depth: f32, bud: f32, seed2: f32 };
@group(0) @binding(1) var<storage, read_write> A: array<Petal>;
@group(0) @binding(2) var<storage, read> B: array<Blossom>;
@compute @workgroup_size(64) fn air(@builtin(global_invocation_id) g: vec3u) {
  if (g.x >= arrayLength(&A)) { return; }
  var a = A[g.x]; let dt = U.dt; let k = g.x * 131u + u32(U.frame) * 2741u;
  if (a.age <= 0.0) {
    if (U.grow.x < 7.0 || U.grow.y > 6.0 || U.grow.w < 1.0) { return; }
    let b = B[u32(rnd(k) * U.grow.w) % u32(U.grow.w)]; let w = abs(windAt(b.p));
    // A quiet tree sheds a few petals; a gust shakes many loose, but only where it has arrived.
    if (rnd(k + 1u) < dt * (0.055 + 1.5 * w * w)) { a.p = b.p; a.v = vec3f(0.0); a.age = 0.01; a.spin = rnd(k + 2u) * 6.28; }
  } else {
    let h = rnd(g.x * 7u + 3u); let q = a.p * 1.7; let t = U.time * 0.45;
    // Eddies, stronger in a gust.
    let w = windAt(a.p); let e = vec3f(gnoise(q.xy + vec2f(t, h * 9.0)) - 0.5, gnoise(q.yx + vec2f(31.0 + t, h * 7.0)) - 0.5, gnoise(q.zy + vec2f(62.0, t)) - 0.5) * (0.75 + 2.2 * abs(w));
    let flow = vec3f(1.9 * w + 0.07, 0.28 * abs(w), -0.10 * abs(w)) + e;
    let flutter = vec3f(0.22 * sin(a.spin * 1.3 + h * 6.28), 0.10 * sin(a.spin * 2.1), 0.14 * cos(a.spin * 0.9 + h * 4.0));
    let sink = 0.27 + 0.16 * h; let aim = flow + flutter + vec3f(sink * U.tilt.w, -sink, 0.0);   // tipped phone: they fall slanting
    a.v += (aim - a.v) * min(1.0, dt * (1.3 + 1.1 * h)); a.p += a.v * dt; a.age += dt; a.spin += dt * (1.4 + 2.2 * h + 1.8 * length(a.v));
    if (a.p.y < -0.25 || a.age > 14.0 || abs(a.p.x) > 5.0 || a.p.z < 0.5) { a.age = 0.0; }
  }
  A[g.x] = a;
}
