// Shared by everything that grows: the camera, and the street's light on both faces of a surface.
const QUAD = array<vec2f, 6>(vec2f(-1, -1), vec2f(1, -1), vec2f(-1, 1), vec2f(-1, 1), vec2f(1, -1), vec2f(1, 1));

fn project(p: vec3f) -> vec4f {
  let v = p - camPos(); let asp = U.size.x / U.size.y; let z = max(v.z, 0.05);
  return vec4f((v.x - 0.02 * z) / (asp * 0.59), 0.06 * z + v.y / 0.59, (z - 0.3) * 1.02, z);
}
// Light on both faces at once. Only the eight nearest lanterns: the rest are too far to tell.
struct Two { a: vec3f, b: vec3f };
fn lit2(p: vec3f, n: vec3f, wrap: f32) -> Two { return litBase(p, n, wrap, 1.0); }
fn litBase(p: vec3f, n: vec3f, wrap: f32, ground: f32) -> Two {
  var f = vec3f(0.0); var k = vec3f(0.0); let iw = 1.0 / (1.0 + wrap);
  for (var i = 0; i < 8; i++) { let d = U.lamps[i * 2].xyz - p; let d2 = dot(d, d) + 0.10; let c = dot(n, d) * inverseSqrt(d2); let e = U.lamps[i * 2 + 1].rgb / d2; f += e * max(0.0, (c + wrap) * iw); k += e * max(0.0, (wrap - c) * iw); }
  f *= 0.14; k *= 0.14;
  if (U.grow.z > 0.0) { for (var i = 0; i < 2; i++) {   // ground lights, one each side of the trunk
    let d = U.treePos.xyz + vec3f(select(-0.75, 0.65, i == 1), -1.95, select(-0.75, -0.35, i == 1)) - p; let d2 = dot(d, d) + 0.75; let c = dot(n, d) * inverseSqrt(d2);
    let e = vec3f(1.0, 0.80, 0.64) * select(1.0, 0.75, i == 1) * 5.8 * ground * U.grow.z / d2; f += e * max(0.0, (c + wrap) * iw); k += e * max(0.0, (wrap - c) * iw);
  } }
  let s = vec3f(0.030, 0.042, 0.090); return Two(f + s * (0.6 + 0.4 * n.y), k + s * (0.6 - 0.4 * n.y));
}
// Plus the glow at the far end of the street, which comes from behind, and a soft key from the window side.
fn lit3(p: vec3f, n: vec3f, wrap: f32, key: vec3f) -> Two {
  var L = litBase(p, n, wrap, 0.22); let iw = 1.0 / (1.0 + wrap);
  let a = dot(n, vec3f(0.06, 0.28, 0.958)); let d = vec3f(0.42, 0.27, 0.17); L.a += d * max(0.0, (a + wrap) * iw); L.b += d * max(0.0, (wrap - a) * iw);
  let b = dot(n, vec3f(-0.33, 0.76, -0.56)); L.a += key * max(0.0, (b + wrap) * iw); L.b += key * max(0.0, (wrap - b) * iw); return L;
}
fn glint(p: vec3f, n: vec3f, sharp: f32) -> vec3f {
  let v = normalize(camPos() - p); var s = vec3f(0.0);
  for (var i = 0; i < 8; i++) { let d = U.lamps[i * 2].xyz - p; let d2 = dot(d, d); let h = normalize(v + d / sqrt(d2)); s += U.lamps[i * 2 + 1].rgb * pow(max(dot(n, h), 0.0), sharp) / (d2 + 0.4); }
  let h = normalize(v + vec3f(-0.33, 0.76, -0.56)); return s * 0.5 + vec3f(0.85, 0.80, 0.72) * pow(max(dot(n, h), 0.0), sharp * 1.6) * 0.5;
}
// World x of a place on the screen (-1..1) at depth z.
fn across(sx: f32, z: f32) -> f32 { return 0.12 + (sx * U.size.x / U.size.y * 0.59 + 0.02) * z; }
fn rot(a: f32) -> mat2x2f { return mat2x2f(cos(a), sin(a), -sin(a), cos(a)); }
const HIDE = vec4f(2.0, 2.0, 2.0, 1.0);
