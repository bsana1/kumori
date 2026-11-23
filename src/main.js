import { loadShaders, createGPU, createProfiler } from './gpu.js?v=11';
import { createWater, UNIFORM_BYTES, MAX_PARTICLES } from './water.js?v=11';
import { createRenderer } from './render.js?v=11';
import { createGrowth } from './growth.js?v=11';
import { createLetters, loadStrokes } from './letters.js?v=11';

const $ = id => document.getElementById(id), canvas = $('c');
const q = new URLSearchParams(location.search), DEBUG = q.has('debug');
const SEED = +(q.get('seed') ?? 7), WARP = +(q.get('t') ?? 14), PX = q.get('px');
const CAP = 4.3e6;
let maxPx = +(PX ?? 3.2e6);
const DT = 1 / 60, HEIGHT = 900;
const log = m => window.klog?.(m);
const fail = m => { log('shown: ' + m); $('msg').style.display = 'grid'; $('msg').textContent = m; };

async function boot() {
  log('webgpu: ' + (navigator.gpu ? 'yes' : 'no'));
  const adapter = await navigator.gpu?.requestAdapter({ powerPreference: 'high-performance' });
  if (adapter) { const i = adapter.info || {}, L = adapter.limits; log(`adapter: ${i.vendor || '?'} ${i.architecture || ''} ${i.description || ''}${adapter.isFallbackAdapter ? ' (fallback)' : ''}`); log(`limits: storage/stage ${L.maxStorageBuffersPerShaderStage}, storage binding ${(L.maxStorageBufferBindingSize / 2 ** 20) | 0} MB, buffer ${(L.maxBufferSize / 2 ** 20) | 0} MB, invocations ${L.maxComputeInvocationsPerWorkgroup}, tex ${L.maxTextureDimension2D}; features: ${[...adapter.features].join(' ')}`); }
  if (!adapter) return fail('This window needs WebGPU. Try a current Chrome, Edge, or Safari 26 and later.');
  const device = await adapter.requestDevice({ requiredFeatures: adapter.features.has('timestamp-query') ? ['timestamp-query'] : [] });
  log('device: ok'); device.lost.then(i => { log('device lost: ' + i.reason + ' ' + i.message); if (i.reason !== 'destroyed') { console.error('device lost', i.message); fail('The graphics device was reset. Reload to carry on.'); } });
  const seen = new Set(); // the first error cascades every frame; report each distinct one once
  device.onuncapturederror = e => { if (!seen.has(e.error.message) && seen.size < 12) { seen.add(e.error.message); console.error('GPU', e.error.message); log('GPU error: ' + e.error.message.slice(0, 400)); } };

  const ctx = canvas.getContext('webgpu');
  const hdr = matchMedia('(dynamic-range: high)').matches;
  let format = hdr ? 'rgba16float' : navigator.gpu.getPreferredCanvasFormat();
  ctx.configure({ device, format, colorSpace: matchMedia('(color-gamut: p3)').matches ? 'display-p3' : 'srgb', toneMapping: { mode: hdr ? 'extended' : 'standard' }, alphaMode: 'opaque' });

  const sh = await loadShaders(['reset', 'field', 'beads', 'spawn', 'liquid', 'splat', 'blur', 'scene', 'lens', 'glass', 'finish', 'letters', 'shade:tree', 'shade:plants', 'shade:life', 'shade:snow', 'over', 'air']), chars = await loadStrokes();
  log(`shaders loaded; canvas format ${format}, hdr ${hdr}`);
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches, nSegs = chars.reduce((a, c) => a + c.strokes.reduce((b, s) => b + s.length - 1, 0), 0);
  let growth = null, letters = null, warming = false;
  const ub = device.createBuffer({ size: UNIFORM_BYTES, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
  const g = createGPU(device, ub), samp = device.createSampler({ magFilter: 'linear', minFilter: 'linear', mipmapFilter: 'linear', addressModeU: 'clamp-to-edge', addressModeV: 'clamp-to-edge' });
  const prof = createProfiler(device, DEBUG);
  let size = [0, 0], water = null, time = 0, frame = 0, rain = +(q.get('rain') ?? 0.5), condense = +(q.get('condense') ?? 1);
  let renderer = null, dry = 0, warm = 0;

  // ---- input: each touch is a finger; positions are in glass units
  const fingers = new Map();
  const toUnits = e => { const r = canvas.getBoundingClientRect(); return [(e.clientX - r.left) / r.width * size[0], (e.clientY - r.top) / r.height * size[1]]; };
  const down = (id, p, r = 21) => fingers.set(id, { a: p, b: p, next: p, vel: [0, 0], r });
  const move = (id, p) => { const f = fingers.get(id); if (f) f.next = p; };
  const radius = e => e.pointerType === 'touch' ? Math.min(34, Math.max(17, (e.width || 36) * 0.55 * size[1] / innerHeight)) : 21;
  canvas.addEventListener('pointerdown', e => { canvas.setPointerCapture(e.pointerId); down(e.pointerId, toUnits(e), radius(e)); });
  // The pointer is a drop. Its centre is always exactly the pointer; only its shape lags, like water.
  const cur = { p: [0, 0], from: [0, 0], v: [0, 0], seen: -1e9, over: false, a: 0, press: 0, t: performance.now() };
  const point = e => { if (e.pointerType === 'touch') return; cur.p = toUnits(e); if (!cur.over) cur.from = cur.p; cur.over = true; cur.seen = performance.now(); };
  canvas.addEventListener('pointermove', e => { point(e); move(e.pointerId, toUnits(e)); });
  canvas.addEventListener('pointerdown', point); canvas.addEventListener('pointerleave', () => { cur.over = false; });
  for (const n of ['pointerup', 'pointercancel']) canvas.addEventListener(n, e => fingers.delete(e.pointerId));
  canvas.addEventListener('contextmenu', e => e.preventDefault());

  // ---- tilt: which way is down in the plane of the screen (x right, y down), from the phone's orientation.
  // Water on the glass runs that way, and snow and petals fall slanting. Without a sensor it stays (0, 1).
  const tilt = { g: [0, 1], want: [0, 1], drift: 0, rate: 0 };
  function orient(e) {
    if (e.beta == null || e.gamma == null) return;
    const b = e.beta * Math.PI / 180, c = e.gamma * Math.PI / 180;
    const gx = Math.sin(c) * Math.cos(b), gy = -Math.sin(b);   // gravity in the device's frame, y towards its top
    const a = (screen.orientation?.angle ?? window.orientation ?? 0) * Math.PI / 180;   // the page turns with the phone
    const sx = gx * Math.cos(a) - gy * Math.sin(a), sy = gx * Math.sin(a) + gy * Math.cos(a);
    const m = Math.hypot(sx, sy); if (m < 0.2) return;   // lying flat: no clear down on the glass, keep the last one
    if (!tilt.seen) { tilt.seen = 1; log('tilt: reading'); }
    tilt.want = [sx / m, -sy / m];
  }
  // iPhone asks permission for motion, and only from a tap; elsewhere it simply arrives.
  if (typeof DeviceOrientationEvent !== 'undefined' && typeof DeviceOrientationEvent.requestPermission === 'function') {
    const ask = () => DeviceOrientationEvent.requestPermission().then(r => { log('tilt: ' + r); if (r === 'granted') addEventListener('deviceorientation', orient); }).catch(e => log('tilt: ' + e.message));
    canvas.addEventListener('touchend', ask, { once: true }); canvas.addEventListener('click', ask, { once: true });
  } else addEventListener('deviceorientation', orient);
  function lean(dt) {
    const k = Math.min(1, dt * 3.5); let [x, y] = [tilt.g[0] + (tilt.want[0] - tilt.g[0]) * k, tilt.g[1] + (tilt.want[1] - tilt.g[1]) * k];
    const m = Math.hypot(x, y) || 1; tilt.g = [x / m, y / m];
    // Snow and petals: sideways per metre fallen, kept within ±60 degrees (upside down, they still fall down the view).
    tilt.rate = Math.max(-1.7, Math.min(1.7, tilt.g[0] / Math.max(0.3, tilt.g[1]))); tilt.drift += tilt.rate * dt;
  }

  const data = new ArrayBuffer(UNIFORM_BYTES), f32 = new Float32Array(data), u32 = new Uint32Array(data);
  // Street lights: placed once, flicker each frame.
  const rs = (() => { let s = 0x2f6e2b1; return () => { s = s + 0x6d2b79f5 | 0; let t = Math.imul(s ^ s >>> 15, 1 | s); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; })();
  const lerp = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);
  const lamps = Array.from({ length: 18 }, (_, i) => { const a = rs(), b = rs(), red = rs() > 0.7; return { p: [(i % 2 ? 1 : -1) * (1.93 - 0.12 * b), 2.15 + 0.35 * b, 2.7 + (i >> 1) * 2.5 + a * 1.1 + (i % 2 ? 0 : 1.2)], r: 0.20 + 0.06 * a, c: red ? [1, 0.085, 0.045] : lerp([1, 0.42, 0.13], [1, 0.64, 0.32], a), f: rs() * 99 }; });
  const bulbs = Array.from({ length: 26 }, () => { const a = rs(), b = rs(), c = rs(), tint = b > 0.72 ? (a > 0.5 ? [0.5, 0.75, 1] : [1, 0.16, 0.12]) : [1, 0.55, 0.2]; return { p: [(rs() * 2 - 1) * 2.25, 1.1 + 3.6 * c * c, 9 + 34 * rs(), 0.035 + 0.05 * a], c: tint.map(v => v * (4 + 12 * c)), f: rs() * 99 }; });
  function lights() {
    let o = 80; for (const l of lamps) { const k = 0.94 + 0.06 * Math.sin(time * 7.3 + l.f) * Math.sin(time * 2.1 + l.f * 2); f32.set([l.p[0], l.p[1] + 0.015 * Math.sin(time * 0.9 + l.f), l.p[2], l.r, ...l.c.map(v => v * k), 0], o); o += 8; }
    for (const l of bulbs) { const k = 0.75 + 0.25 * Math.sin(time * 0.9 + l.f); f32.set([...l.p, ...l.c.map(v => v * k), 0], o); o += 8; }
  }
  function uniforms() {
    f32.set([size[0], size[1], canvas.width, canvas.height, time, DT, frame, SEED]);
    u32.set([...water.beadGrid, ...water.cellGrid], 8);
    f32.set([rain, condense, hdr ? 1.8 : 1, fingers.size ? 1 : 2], 12);
    f32.fill(0, 16, 80); let i = 0;
    for (const f of fingers.values()) { if (i > 7) break; f32.set([...f.a, ...f.b, ...f.vel, f.r, 1], 16 + i++ * 8); }
    if (letters && !warming) { f32.set(letters.breaths, 432); } else f32.fill(0, 432, 452);
    growth.uniforms(f32, 452, 528); f32.set([...tilt.g, tilt.drift, tilt.rate], 544); f32[551] = dry; lights(); device.queue.writeBuffer(ub, 0, data);
  }
  function pointer() {
    const now = performance.now(), dt = Math.min(0.1, (now - cur.t) / 1000) || 1e-3; cur.t = now; const k = Math.min(1, dt * 12);
    for (let i = 0; i < 2; i++) { cur.v[i] += ((cur.p[i] - cur.from[i]) / dt / 1100 - cur.v[i]) * k; cur.from[i] = cur.p[i]; }
    const l = Math.hypot(...cur.v), s = l > 0.9 ? 0.9 / l : 1, show = cur.over && now - cur.seen < 6000; cur.a += ((show ? 1 : 0) - cur.a) * Math.min(1, dt * (show ? 14 : 3)); cur.press += ((fingers.size ? 1 : 0) - cur.press) * Math.min(1, dt * 14);
    f32.set(cur.a > 0.01 ? [...cur.p, 10.5 * (1 - 0.18 * cur.press), cur.press, cur.v[0] * s, cur.v[1] * s, cur.a * (1 - 0.25 * cur.press), 0] : [0, 0, 0, 0, 0, 0, 0, 0], 552);
  }
  function step(enc, seen = true) {
    for (const f of fingers.values()) { f.a = f.b; f.b = f.next; f.vel = [(f.b[0] - f.a[0]) / DT, (f.b[1] - f.a[1]) / DT]; }
    if (letters && !warming) { for (const f of fingers.values()) letters.touch(f.a, f.b, f.r); letters.step(DT); water.setSegments(letters.data); }
    if (!warming) lean(DT); growth.step(DT, [...fingers.values()]); time += DT; frame++; uniforms(); growth.air(enc); water.step(enc, prof, seen, !fingers.size, frame);
  }
  const submit = fn => { const enc = device.createCommandEncoder(); fn(enc); device.queue.submit([enc.finish()]); };

  function resize(force) {
    const r = canvas.getBoundingClientRect(); let w = r.width * devicePixelRatio, h = r.height * devicePixelRatio;
    if (w < 2 || h < 2) { if (!water && !resize.told) { resize.told = 1; log('waiting: the page has no size yet'); } return; } const k = Math.min(1, Math.sqrt(maxPx / (w * h))); w = Math.round(w * k); h = Math.round(h * k);
    if (!force && water && w === canvas.width && h === canvas.height) return;
    canvas.width = w; canvas.height = h; const ns = [HEIGHT * w / h, HEIGHT];
    renderer ??= createRenderer(device, g, sh, samp, format);
    if (!water || Math.abs(ns[0] - size[0]) > 4) {
      water?.destroy(); growth?.destroy(); size = ns; growth = createGrowth(device, g, sh, size, renderer.noise); growth.lamps = lamps; water = createWater(device, g, sh, samp, size, nSegs, growth.view); letters = createLetters(chars, size, still, (l, p) => growth.wake(l.char, p), l => growth.busy(l.char)); warming = true; uniforms(); submit(e => water.reset(e));
      warm = WARP * 60; log(`warming up: ${canvas.width}x${canvas.height} px`);
    }
    renderer.resize(w, h, water, growth);
  }
  // The head start (WARP seconds of rain before the first frame) is fed to the GPU in small chunks, each
  // waited for. Every step is its own submit (its uniforms differ), and Safari on iPhone fails with
  // "Unable to begin compute pass" once about 64 are queued at once; this caps it at CHUNK.
  let warmBusy = false; const CHUNK = 24;
  function warmUp() {
    if (warmBusy) return; warmBusy = true; const n = Math.min(warm, CHUNK);
    for (let i = 0; i < n; i++) submit(e => step(e));
    warm -= n; device.queue.onSubmittedWorkDone().then(() => { warmBusy = false; });
    if (!warm) { warming = false; log('simulation ready'); }
  }
  const draw = () => submit(enc => { pointer(); uniforms(); growth.upload(); renderer.draw(enc, ctx.getCurrentTexture().createView(), prof); prof.resolve(enc); });
  resize(true);

  // ---- loop
  let drawn = 0, paused = false, last = performance.now(), acc = 0, fps = null, ema = 16; // fps stays null until a real frame has been drawn
  // Trade pixels for frame rate, both ways. The simulation is never reduced. Stepping up is cautious: if a
  // rise is followed by a fall it is not tried again for a minute.
  let slow = 0, calm = 0, rose = -1e9, ban = 0;
  function adapt(ms, now) {
    if (PX || document.hidden || ms > 250) { slow = calm = 0; return; }
    slow = ema > 20 ? slow + ms : 0; calm = ema < 17.6 ? calm + ms : 0;
    if (slow > 1500 && maxPx > 1.3e6) { if (now - rose < 10000) ban = now + 60000; maxPx = Math.max(1.3e6, Math.min(maxPx, canvas.width * canvas.height) * 0.8); slow = calm = 0; }
    else if (calm > 5000 && maxPx < CAP && now > ban) { maxPx = Math.min(CAP, maxPx * 1.2); rose = now; calm = 0; }
  }
  function tick(now) {
    if (paused) { last = now; return requestAnimationFrame(tick); }
    const ms = now - last; last = now; ema += (ms - ema) * 0.05; fps = 1000 / ema; adapt(ms, now);
    // A page opened with no size yet (a hidden or not-yet-shown tab) has nothing to draw: wait for one.
    resize(); if (!water) return requestAnimationFrame(tick);
    if (warm || warmBusy && warming) { if (warm) warmUp(); acc = 0; ema = 16; return requestAnimationFrame(tick); }
    prof.begin?.(); acc = Math.min(acc + ms / 1000, 2 * DT);
    while (acc >= DT - 1e-4) { acc -= DT; const last = acc < DT - 1e-4; submit(e => step(e, last)); }
    draw(); drawn++; if (drawn === 1) reveal(); prof.read(); if (DEBUG && frame % 20 === 0) overlay();
    requestAnimationFrame(tick);
  }
  // Lift the loading still once the first real frame has reached the screen, but not before the fog has
  // had a moment to gather (a flash of the still, then the live window, looks like a glitch).
  function reveal() {
    device.queue.onSubmittedWorkDone().then(() => setTimeout(() => requestAnimationFrame(() => {
      document.body.classList.add('live'); log('live'); setTimeout(() => log(`fps ${fps?.toFixed(0)} at ${canvas.width}x${canvas.height}`), 5000); setTimeout(() => $('veil')?.remove(), 2000);
    }), Math.max(0, 1400 - performance.now())));
  }
  requestAnimationFrame(tick);

  // ---- debug: reads the water ledger back from the GPU
  async function ledger() {
    const grab = async b => { const c = device.createBuffer({ size: b.size, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ }); submit(e => e.copyBufferToBuffer(b, 0, c, 0, b.size)); await c.mapAsync(GPUMapMode.READ); const r = c.getMappedRange().slice(0); c.destroy(); return r; };
    const [p, b, s, fr] = await Promise.all([grab(water.P), grab(water.B), grab(water.S), grab(water.F)]);
    const P = new Float32Array(p), B = new Float32Array(b), S = new Uint32Array(s); let n = 0, vol = 0, big = 0, nan = 0, fast = 0;
    for (let i = 0; i < P.length; i += 4) if (P[i] > -1e5) { n++; if (Math.hypot(P[i + 2], P[i + 3]) > 8) fast++; } else if (P[i] !== P[i]) nan++;
    for (let i = 2; i < B.length; i += 4) { vol += B[i]; if (B[i] > 8) big++; }
    return { particles: n, moving: fast, beadVolume: Math.round(vol), bigBeads: big, spawned: S[0], drained: S[1], dropped: S[2], rained: S[3], free: new Int32Array(fr)[0], nan, sum: n + new Int32Array(fr)[0] === MAX_PARTICLES };
  }
  let busy = false;
  async function overlay() {
    if (busy) return; busy = true; const l = await ledger(); busy = false; $('dbg').hidden = false;
    const t = prof.times, tot = Object.values(t).reduce((a, b) => a + b, 0);
    $('dbg').textContent = `${canvas.width}x${canvas.height}  ${fps?.toFixed(0)} fps\ngpu ${tot.toFixed(1)} ms\n` + Object.entries(t).map(([k, x]) => `  ${k.padEnd(11)} ${x.toFixed(2)}`).join('\n') + '\n' + Object.entries(l).map(([k, x]) => `${k.padEnd(12)} ${x}`).join('\n');
  }
  // Hook for scripted checks (see .agent/CODING_GUIDELINES.md).
  window.kumori = {
    device, ledger, draw, times: prof.times, tilt, orient, get growth() { return growth; }, wake: ch => growth.wake(ch, [size[0] / 2, size[1] * 0.4]), get size() { return size; }, get fps() { return fps; },
    advance(sec) { for (let i = 0; i < sec * 60; i++) submit(e => step(e)); draw(); },
    stroke(pts, sec, id = 'x') { // pts in 0..1
      const P = pts.map(p => [p[0] * size[0], p[1] * size[1]]), n = Math.max(1, Math.round(sec * 60)); down(id, P[0]);
      for (let i = 1; i <= n; i++) { const t = i / n * (P.length - 1), k = Math.min(P.length - 2, t | 0), f = t - k; move(id, [P[k][0] + (P[k + 1][0] - P[k][0]) * f, P[k][1] + (P[k + 1][1] - P[k][1]) * f]); submit(e => step(e)); }
      fingers.delete(id); draw();
    },
    // Throughput per stage: many copies in one submit, fenced. Pauses the loop while it runs.
    async bench(n = 12) {
      paused = true; const out = {}, wait = () => device.queue.onSubmittedWorkDone(); await wait();
      for (const [k, f] of [...Object.entries(water.stages), ...Object.entries(renderer.stages)]) {
        submit(f); await wait(); const t = performance.now(); submit(e => { for (let i = 0; i < n; i++) f(e); }); await wait(); out[k] = +((performance.now() - t) / n).toFixed(2);
      }
      out.total = +Object.values(out).reduce((a, b) => a + b, 0).toFixed(1); paused = false; return out;
    },
    // Real frames drawn per second; null if the page isn't being composited.
    async measure(sec = 4) { const a = drawn, t = performance.now(); await new Promise(r => setTimeout(r, sec * 1000)); return drawn === a ? null : +((drawn - a) / (performance.now() - t) * 1000).toFixed(1); },
    // Mean motion of loose petals (wind check).
    async petals() { const b = growth.AB, c = device.createBuffer({ size: b.size, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ }); submit(e => e.copyBufferToBuffer(b, 0, c, 0, b.size)); await c.mapAsync(GPUMapMode.READ); const a = new Float32Array(c.getMappedRange().slice(0)); c.destroy(); let n = 0, vx = 0, bad = 0; for (let i = 0; i < a.length; i += 8) if (a[i + 3] > 0) { n++; vx += a[i + 4]; if (a[i] !== a[i]) bad++; } return { n, vx: +(vx / Math.max(1, n)).toFixed(3), bad, wind: +growth.wind.toFixed(3) }; },
    get letters() { return letters; }, get growth() { return growth; },
    set paused(v) { paused = v; },
    // How far particles really drift in `sec` while untouched (jitter check).
    async drift(sec = 1) {
      const read = async () => { const c = device.createBuffer({ size: water.P.size, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ }); submit(e => e.copyBufferToBuffer(water.P, 0, c, 0, water.P.size)); await c.mapAsync(GPUMapMode.READ); const r = new Float32Array(c.getMappedRange().slice(0)); c.destroy(); return r; };
      paused = true; const a = await read(); for (let i = 0; i < sec * 60; i++) submit(e => step(e)); const b = await read(); paused = false; const d = [];
      for (let i = 0; i < a.length; i += 4) if (a[i] > -1e5 && b[i] > -1e5) d.push(Math.hypot(a[i] - b[i], a[i + 1] - b[i + 1]));
      d.sort((x, y) => x - y); const p = t => +(d[Math.floor(d.length * t)] ?? 0).toFixed(3); return { n: d.length, p25: p(.25), p50: p(.5), p75: p(.75), p95: p(.95) };
    },
    down, move, up: id => fingers.delete(id), set rain(v) { rain = v; }, set condense(v) { condense = v; }, set dry(v) { dry = v ? 1 : 0; },
  };
}
boot().catch(e => { console.error(e); log('boot failed: ' + (e?.stack || e)); fail('Something went wrong starting the window. Details are in the console.'); });
