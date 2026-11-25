// What grows behind the glass. Everything draws into one HDR layer (premultiplied) that the street, fog,
// drops and glass all sample. Each letter wakes one thing.
import { growTree, MAX_SEGS, MAX_BLOSSOMS } from './tree.js?v=11';
import { koi, birds, butterflies, unproject } from './creatures.js?v=11';
const FALLING = 1400, DELAY = 1.3, MS = 4, REEDS = 1300, PLUMES = 64 * 46, STEMS = 1700, FLORETS = 20;
// The window's words are 桜梅桃李 (ōbaitōri, "each blooms in its own way"): cherry, plum, peach, sumomo.
// Each letter wakes a slot. The slots keep their old order (it matches U.world): 0 water, reeds and koi,
// 1 snow, 2 rapeseed field (no letter wakes it now), 3 birds, 4 the cherry tree. 梅 wakes the snow and a
// plum tree with it; 桃 and 李 will each get their own tree too.
// Seconds each stays, then seconds it takes to leave.
const KIND = { '李': 0, '梅': 1, '桃': 3, '桜': 4 }, HOLD = [30, 30, 30, 25, 35], END = [6, 7, 6, 6, 8];
const SPECIES = { 4: 0, 1: 1 };   // slot -> tree species (tree.js); the cherry keeps its own buffers
const FLAKES = 14000;   // match snow.wgsl

export function createGrowth(device, g, sh, size, noise) {
  const { group, compute, tex, buf } = g, U = GPUTextureUsage, HDR = 'rgba16float', asp = size[0] / size[1];
  const room = Math.max(0.5, Math.min(1, asp / 1.4)), N = { koi: Math.max(6, Math.round(9 * room)), birds: 12, fly: 14 };
  // Rows in the growth layer. 1000 keeps petals and flowers crisp on a large screen (680 looked soft).
  const h = 1000, w = Math.round(h * asp);
  const layer = tex(w, h, HDR, U.RENDER_ATTACHMENT | U.TEXTURE_BINDING, 6);
  const msaa = device.createTexture({ size: [w, h], format: HDR, sampleCount: MS, usage: U.RENDER_ATTACHMENT });
  const depth = device.createTexture({ size: [w, h], format: 'depth24plus', sampleCount: MS, usage: U.RENDER_ATTACHMENT });
  const SB = buf(MAX_SEGS * 48), BB = buf(MAX_BLOSSOMS * 48), UB = device.createBuffer({ size: 32, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST }), AB = buf(FALLING * 32), act = { koi: buf(N.koi * 64), bird: buf(N.birds * 64), fly: buf(N.fly * 64) };
  const mods = {}; const mod = f => mods[f] ??= device.createShaderModule({ code: sh[f], label: f });
  const pipe = (f, vs, fs, kind = 'solid') => device.createRenderPipeline({
    label: vs, layout: 'auto', vertex: { module: mod(f), entryPoint: vs }, primitive: { topology: 'triangle-list' }, multisample: { count: MS, alphaToCoverageEnabled: kind === 'cut' },
    fragment: { module: mod(f), entryPoint: fs, targets: [{ format: HDR, blend: kind === 'over' ? { color: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' }, alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' } } : undefined }] },
    depthStencil: { format: 'depth24plus', depthWriteEnabled: kind !== 'over', depthCompare: 'less' },
  });
  const P = {
    limb: pipe('tree', 'vsLimb', 'fsLimb'), bloom: pipe('tree', 'vsBlossom', 'fsPetal', 'cut'), fall: pipe('tree', 'vsFall', 'fsPetal', 'cut'), stamen: pipe('tree', 'vsStamen', 'fsStamen', 'cut'),
    reed: pipe('plants', 'vsReed', 'fsReed'), plume: pipe('plants', 'vsPlume', 'fsPlume', 'cut'), pool: pipe('plants', 'vsPool', 'fsPool', 'over'), stem: pipe('plants', 'vsStem', 'fsStem'), floret: pipe('plants', 'vsFloret', 'fsFloret', 'cut'),
    snow: pipe('snow', 'vsSnow', 'fsSnow', 'over'), koi: pipe('life', 'vsKoi', 'fsKoi', 'cut'), bird: pipe('life', 'vsBird', 'fsBird', 'cut'), fly: pipe('life', 'vsFly', 'fsFly', 'cut'),
  };
  const none = k => group(P[k], {}), bg = { fall: group(P.fall, { 3: AB }) };   // tree limbs, blossoms and stamens are bound per tree (trees[slot].bg)
  for (const k of ['reed', 'plume', 'pool', 'stem', 'floret', 'snow']) bg[k] = none(k); for (const k in act) bg[k] = group(P[k], { 1: act[k] });
  const airPipe = compute(sh.air, 'air'), airBg = group(airPipe, { 1: AB, 2: BB });
  const mv = msaa.createView(), dv = depth.createView(), lv = layer.createView({ baseMipLevel: 0, mipLevelCount: 1 });

  const W = Array.from({ length: 5 }, () => ({ on: false, pending: 0, at: [0.5, 0.5], age: 0, hold: 60 }));
  const trees = {}; let tree = null, raw = 0, wind = 0, gust = 1, from = 0, tick = 0, fresh = false, dirty = true, seed = 20261122, flock = null, swim = null, cover = 0, whites = null;
  const hist = new Float32Array(64);
  const ss = (a, b, x) => { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
  const ending = i => W[i].on ? Math.max(0, W[i].age - W[i].hold) : 0, light = i => W[i].on ? ss(0.3, 4, W[i].age) * (1 - ss(END[i] * 0.33, END[i], ending(i))) : 0;
  const any = () => W.some(x => x.on), next = () => seed = Math.imul(seed, 48271) + 11 | 0;
  const sx = i => W[i].at[0] * 2 - 1;

  function start(i) {
    const s = W[i]; s.on = true; s.age = 0; s.hold = HOLD[i]; const at = s.at;
    if (i in SPECIES) {
      // Choose a depth so the trunk stands under the letter without leaving the street.
      const sp = SPECIES[i], z = sp === 0 ? 2.62 : 2.35, x = Math.max(-1.72, Math.min(1.72, 0.12 + ((at[0] - 0.5) * asp * 1.18 + 0.02) * z)), lean = Math.abs(x) < 0.3 ? (x < 0 ? 0.5 : -0.5) : -Math.sign(x);
      const t0 = performance.now(), t = growTree([x, 0, z], lean, next(), sp); t.ms = performance.now() - t0;
      // The cherry reuses SB/BB, which the loose petals (air.wgsl) also read; other trees get their own.
      const own = sp !== 0, sb = own ? buf(MAX_SEGS * 48) : SB, bb = own ? buf(MAX_BLOSSOMS * 48) : BB, ub = own ? device.createBuffer({ size: 32, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST }) : UB;
      device.queue.writeBuffer(sb, 0, t.segs, 0, t.nSegs * 12); device.queue.writeBuffer(bb, 0, t.blossoms, 0, t.nBlossoms * 12);
      const variety = sp === 1 ? [0, 1, 1, 2][Math.floor(Math.abs(next()) % 4)] : 0;   // plum: white, pink (twice as likely) or deep red
      trees[i] = { t, sp, variety, own, sb, bb, ub, bg: { limb: group(P.limb, { 1: sb, 4: ub }), bloom: group(P.bloom, { 2: bb, 4: ub }), stamen: group(P.stamen, { 2: bb, 4: ub }) } };
      if (sp !== 0) return;
      tree = t; gust = lean; fresh = true;
      tree.seats = []; for (let k = 0; k < tree.nBlossoms; k += 7) { const o = k * 12; if (tree.blossoms[o + 9] > 0.45) tree.seats.push([tree.blossoms[o], tree.blossoms[o + 1], tree.blossoms[o + 2]]); }
    } else if (i === 3) flock = birds(N.birds, asp, next());
    else if (i === 2) whites = butterflies(N.fly, asp, next());
    else if (i === 0) swim = koi(N.koi, asp, at, next());   // 辺: reeds and water keep no state; the koi do
  }
  function stop(i) {
    W[i].on = false; dirty = true; const tr = trees[i]; if (tr) { if (tr.own) for (const b of [tr.sb, tr.bb, tr.ub]) b.destroy(); delete trees[i]; }
    if (i === 4) tree = null; if (i === 3) flock = null; if (i === 0) swim = null; if (i === 2) whites = null; }
  // What the birds and butterflies know about. Birds settle in the tree, on the street lanterns or on the
  // ground beside the path, never in the stream.
  const ground = R => { const z = 2.9 + 2.6 * R(); const x = 0.12 + (R() - 0.5) * 3.4; return [x, 0, z]; };
  let lamps = [];   // the street's paper lanterns, set by main.js: a bird can sit on the cap of one
  const ctx = {
    touch: [], wind: 0,
    perch(R, not) {
      const near = lamps.filter(l => l.p[2] < 5.2); const o = ['ground']; if (near.length) o.push('lamp', 'lamp', 'lamp'); if (tree && W[4].age > 7 && !ending(4)) o.push('tree', 'tree', 'tree');
      const k = o[Math.floor(R() * o.length)]; const q = k === 'tree' ? { k, t: tree, p: tree.seats[Math.floor(R() * tree.seats.length)] } : k === 'lamp' ? { k, l: near[Math.floor(R() * near.length)] } : { k, p: ground(R) };
      q.at = ctx.where(q); return q;
    },
    valid: q => q.k === 'tree' ? tree === q.t && ending(4) < 0.3 && Math.abs(wind) < 0.55  : true,
    where: q => q.k === 'tree' ? [q.p[0] + wind * 0.12, q.p[1] + 0.03, q.p[2] - 0.03] : q.k === 'lamp' ? [q.l.p[0] - Math.sign(q.l.p[0]) * 0.03, q.l.p[1] + q.l.r / 0.74 + 0.045, q.l.p[2]] : [q.p[0], 0.033, q.p[2]],
  };
  return {
    layer, AB, get active() { return any(); }, get tree() { return tree; }, get wind() { return wind; }, get state() { return W.map(s => s.on ? +s.age.toFixed(1) : s.pending ? 'soon' : 0); }, get birds() { return flock; }, get cover() { return cover; },
    view: layer.createView(), mips: Array.from({ length: 6 }, (_, i) => layer.createView({ baseMipLevel: i, mipLevelCount: 1 })),
    // For scripted checks: jump a growth's age.
    setAge(i, a) { W[i].age = a; },
    set lamps(l) { lamps = l; },
    wake(char, p) { const i = KIND[char]; if (i === undefined || W[i].on || W[i].pending) return; W[i].pending = DELAY; W[i].at = [p[0] / size[0], p[1] / size[1]]; },
    busy(char) { const s = W[KIND[char]]; return !!s && (s.on || s.pending > 0); },
    step(dt, fingers) {
      // A wipe pushes on the air rather than on anything in it: it stores energy in `raw`, the wind follows
      // a beat later and dies away slowly, whatever the finger does next.
      ctx.touch = [];
      for (const f of fingers) {
        ctx.touch.push([f.b[0] / size[0], f.b[1] / size[1]]); if (Math.hypot(...f.vel) > 500) flock?.startle(unproject(f.b[0] / size[0], f.b[1] / size[1], 3.2, asp), 0.8, ctx);
        const v = Math.max(-1500, Math.min(1500, f.vel[0])) / 1500; if (Math.abs(v) < 0.02) continue; if (Math.abs(raw) < 0.06) from = 0.12 + ((f.b[0] / size[0] - 0.5) * asp * 1.18 + 0.02) * 2.62; raw += v * dt * 3.4;
      }
      raw = Math.max(-1.15, Math.min(1.15, raw * Math.exp(-dt * 0.75))); wind += (raw - wind) * dt * 2.4; ctx.wind = wind;
      if (++tick % 4 === 0) { hist.copyWithin(1, 0, 63); hist[0] = wind; }
      W.forEach((s, i) => {
        if (s.pending && (s.pending -= dt) <= 0) { s.pending = 0; start(i); }
        if (s.on) { s.age += dt; if (s.age > s.hold + END[i]) stop(i); }
      });
      swim?.step(dt, W[0].age, ending(0), ctx); flock?.step(dt, W[3].age, ending(3), ctx); whites?.step(dt, W[2].age, ending(2), ctx);
      // Snow settles while it falls (white over in about thirty seconds, just as it stops) and melts slowly once it stops.
      cover = W[1].on && !ending(1) ? Math.min(1, cover + dt * light(1) * 0.05) : Math.max(0, cover - dt * 0.03);
    },
    uniforms(f32, o, o2) {
      f32.set(tree ? [W[4].age, ending(4), light(4), tree.nBlossoms, ...tree.center, 1] : [0, 0, 0, 0, 0, 0, 0, 0], o); f32.set([wind, gust, 1 - (tick % 4) / 4, from], o + 8); f32.set(hist, o + 12);
      for (let i = 0; i < 4; i++) f32.set([W[i].on ? W[i].age : 0, ending(i), light(i), sx(i)], o2 + i * 4);
      // world[4] and the bear slots stay in the uniform layout but are unused since the bear was removed.
      f32.fill(0, o2 + 16, o2 + 20); f32.fill(0, o2 + 32, o2 + 44);
      const L = Math.max(...W.map((_, i) => light(i))); f32.set([any() ? 1 : 0, L, cover, 0], o2 + 20);
      f32.set([0.5, 0.36, 0.95, 0.35 * light(3), 0, 0, 1, 0], o2 + 44);
    },
    upload() { for (const i in trees) { const tr = trees[i]; device.queue.writeBuffer(tr.ub, 0, new Float32Array([W[i].age, ending(+i), light(+i), tr.t.nBlossoms, tr.sp, tr.variety, 0, 0])); }
      if (swim) device.queue.writeBuffer(act.koi, 0, swim.out); if (flock) device.queue.writeBuffer(act.bird, 0, flock.out); if (whites) device.queue.writeBuffer(act.fly, 0, whites.out); },
    air(enc) { if (!tree) return; if (fresh) { enc.clearBuffer(AB); fresh = false; } const p = enc.beginComputePass(); p.setPipeline(airPipe); p.setBindGroup(0, airBg); p.dispatchWorkgroups(Math.ceil(FALLING / 64)); p.end(); },
    draw(enc, prof) {
      if (!any() && !dirty) return false;
      const p = enc.beginRenderPass({ colorAttachments: [{ view: mv, resolveTarget: lv, loadOp: 'clear', storeOp: 'discard', clearValue: [0, 0, 0, 0] }], depthStencilAttachment: { view: dv, depthClearValue: 1, depthLoadOp: 'clear', depthStoreOp: 'discard' }, timestampWrites: prof?.writes('growth') });
      const go = (k, verts, inst) => { p.setPipeline(P[k]); p.setBindGroup(0, bg[k]); p.draw(verts, inst); };
      if (swim) go('koi', 3144, N.koi); if (flock) go('bird', 1248, N.birds);
      for (const tr of Object.values(trees)) for (const [k, v, n] of [['limb', 6, tr.t.nSegs], ['bloom', 6, tr.t.nBlossoms * 5], ['stamen', 6, tr.t.nBlossoms]]) { p.setPipeline(P[k]); p.setBindGroup(0, tr.bg[k]); p.draw(v, n); }
      if (tree) go('fall', 6, FALLING);
      if (W[2].on) { go('stem', 192, STEMS); go('floret', 6, STEMS * FLORETS); go('fly', 12, N.fly); }
      if (W[0].on) { go('reed', 42, REEDS * 2); go('plume', 24, PLUMES * 2); }
      if (W[0].on) go('pool', 6, 1);
      if (W[1].on) go('snow', 6, FLAKES);   // last: flakes are see-through and would hide what is drawn after them
      p.end(); dirty = any(); return true;
    },
    destroy() { for (const tr of Object.values(trees)) if (tr.own) for (const b of [tr.sb, tr.bb, tr.ub]) b.destroy(); for (const t of [layer, msaa, depth, SB, BB, UB, AB, ...Object.values(act)]) t.destroy(); },
  };
}
