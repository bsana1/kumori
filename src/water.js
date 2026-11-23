// Mist, beads and liquid: buffers, pipelines, and one fixed step of simulation.
export const MAX_PARTICLES = 32768, MAX_REQ = 2048, BEAD = 3, CELL = 4.2, CAP = 16;
export const UNIFORM_BYTES = 64 + 8 * 32 + 88 * 16 + 5 * 16 + 3 * 16 + 16 * 16 + 13 * 16;

export function createWater(device, g, sh, samp, size, nSegs, growthView) {
  const { group, compute, render, tex, buf } = g;
  const U = GPUTextureUsage, TB = U.TEXTURE_BINDING;
  const beadGrid = [Math.ceil(size[0] / BEAD), Math.ceil(size[1] / BEAD)];
  const cellGrid = [Math.ceil(size[0] / CELL), Math.ceil(size[1] / CELL)];
  const nBeads = beadGrid[0] * beadGrid[1], nCells = cellGrid[0] * cellGrid[1];

  const P = buf(MAX_PARTICLES * 16), X = buf(MAX_PARTICLES * 16), D = buf(MAX_PARTICLES * 16);
  const cnt = buf(nCells * 4), cells = buf(nCells * CAP * 4), F = buf(4 + MAX_PARTICLES * 4);
  const B = buf(nBeads * 16), gain = buf(nBeads * 4), R = buf(16 + MAX_REQ * 16), S = buf(16), G = buf(nSegs * 32);
  const fw = size[0] * 0.6, fh = size[1] * 0.6;
  const fields = [0, 1].map(() => tex(fw, fh, 'rgba16float', TB | U.STORAGE_BINDING | U.COPY_SRC));
  const LQ = 1.4, lw = size[0] * LQ, lh = size[1] * LQ;
  const mkL = (w, h) => tex(w, h, 'r16float', TB | U.RENDER_ATTACHMENT);
  const raw = mkL(lw, lh), tmp = mkL(lw, lh), liq = mkL(lw, lh);
  const wa = mkL(size[0] / 3, size[1] / 3), wb = mkL(size[0] / 3, size[1] / 3), wc = mkL(size[0] / 3, size[1] / 3);
  const maskT = tex(size[0], size[1], 'r8unorm', TB | U.RENDER_ATTACHMENT);
  const all = [G, maskT, P, X, D, cnt, cells, F, B, gain, R, S, ...fields, raw, tmp, liq, wa, wb, wc];
  const v = t => t.createView();
  const V = { raw: v(raw), tmp: v(tmp), liq: v(liq), wa: v(wa), wb: v(wb), wide: v(wc), field: fields.map(v), mask: v(maskT) };

  const C = (file, entry) => compute(sh[file], entry);
  const add = { color: { srcFactor: 'one', dstFactor: 'one', operation: 'add' }, alpha: { srcFactor: 'one', dstFactor: 'one', operation: 'add' } };
  const most = { color: { srcFactor: 'one', dstFactor: 'one', operation: 'max' }, alpha: { srcFactor: 'one', dstFactor: 'one', operation: 'max' } };
  const pipes = {
    mask: render(sh.letters, 'vs', 'fs', 'r8unorm', most), emit: C('letters', 'emit'),
    rp: C('reset', 'particles'), rb: C('reset', 'beads'), rf: C('reset', 'field'),
    field: C('field', 'main'), merge: C('beads', 'merge'), apply: C('beads', 'apply'),
    spawn: C('spawn', 'main'), rain: C('spawn', 'rain'), clear: C('spawn', 'clear'),
    clearCells: C('liquid', 'clearCells'), predict: C('liquid', 'predict'), insert: C('liquid', 'insert'), density: C('liquid', 'density'), relax: C('liquid', 'relax'), integrate: C('liquid', 'integrate'),
    splat: render(sh.splat, 'vsLiquid', 'fsLiquid', 'r16float', add),
    nx: render(sh.blur, 'vs', 'narrowX', 'r16float'), ny: render(sh.blur, 'vs', 'narrowY', 'r16float'),
    down: render(sh.blur, 'vs', 'copy', 'r16float'), wx: render(sh.blur, 'vs', 'wideX', 'r16float'), wy: render(sh.blur, 'vs', 'wideY', 'r16float'),
  };
  const bg = {
    mask: group(pipes.mask, { 1: G }), emit: group(pipes.emit, { 1: G, 2: R }),
    rp: group(pipes.rp, { 1: P, 2: F }), rb: group(pipes.rb, { 3: B }), rf: group(pipes.rf, { 4: V.field[0] }),
    field: [0, 1].map(i => group(pipes.field, { 1: samp, 2: V.field[i], 3: V.liq, 4: V.field[1 - i], 5: R, 6: V.mask, 7: growthView })),
    merge: group(pipes.merge, { 1: B, 2: gain }),
    apply: [0, 1].map(i => group(pipes.apply, { 1: B, 2: gain, 3: R, 4: samp, 5: V.liq, 6: V.field[i], 7: V.mask })),
    spawn: group(pipes.spawn, { 1: R, 2: F, 3: P, 4: S }), rain: group(pipes.rain, { 2: F, 3: P, 4: S }), clear: group(pipes.clear, { 1: R }),
    clearCells: group(pipes.clearCells, { 4: cnt }),
    predict: [0, 1].map(i => group(pipes.predict, { 1: P, 2: X, 3: D, 8: samp, 9: V.wide, 10: V.field[i] })),
    insert: group(pipes.insert, { 1: P, 4: cnt, 5: cells }), density: group(pipes.density, { 1: P, 2: X, 4: cnt, 5: cells }),
    relax: group(pipes.relax, { 1: P, 2: X, 3: D, 4: cnt, 5: cells }), integrate: group(pipes.integrate, { 1: P, 2: X, 3: D, 6: F, 7: S }),
    splat: group(pipes.splat, { 1: P }),
    nx: group(pipes.nx, { 1: samp, 2: V.raw }), ny: group(pipes.ny, { 1: samp, 2: V.tmp }),
    down: group(pipes.down, { 1: samp, 2: V.raw }), wx: group(pipes.wx, { 1: samp, 2: V.wa }), wy: group(pipes.wy, { 1: samp, 2: V.wb }),
  };
  let cur = 0;
  const w64 = n => Math.ceil(n / 64);
  const pass = (enc, view, pipe, bgr, verts, inst, tw) => {
    const p = enc.beginRenderPass({ colorAttachments: [{ view, loadOp: 'clear', storeOp: 'store', clearValue: [0, 0, 0, 0] }], timestampWrites: tw });
    p.setPipeline(pipe); p.setBindGroup(0, bgr); p.draw(verts, inst); p.end();
  };
  const one = (enc, n, b, x, y = 1) => { const c = enc.beginComputePass(); c.setPipeline(pipes[n]); c.setBindGroup(0, b); c.dispatchWorkgroups(x, y); c.end(); };
  function surface(enc, prof, seen = true) {
    pass(enc, V.raw, pipes.splat, bg.splat, 6, MAX_PARTICLES, prof?.writes('splat'));
    if (seen) { pass(enc, V.tmp, pipes.nx, bg.nx, 3, 1, prof?.writes('blur')); pass(enc, V.liq, pipes.ny, bg.ny, 3, 1, prof?.writes('blur')); }
    pass(enc, V.wa, pipes.down, bg.down, 3, 1); pass(enc, V.wb, pipes.wx, bg.wx, 3, 1, prof?.writes('blur')); pass(enc, V.wide, pipes.wy, bg.wy, 3, 1, prof?.writes('blur'));
  }
  return {
    beadGrid, cellGrid, nBeads, B, P, S, F, beadInstances: nBeads, views: V, pipes,
    get fieldView() { return V.field[cur]; }, get fieldIndex() { return cur; },
    reset(enc) {
      cur = 0; const c = enc.beginComputePass();
      c.setPipeline(pipes.rp); c.setBindGroup(0, bg.rp); c.dispatchWorkgroups(w64(MAX_PARTICLES));
      c.setPipeline(pipes.rb); c.setBindGroup(0, bg.rb); c.dispatchWorkgroups(w64(nBeads));
      c.setPipeline(pipes.rf); c.setBindGroup(0, bg.rf); c.dispatchWorkgroups(Math.ceil(fw / 8), Math.ceil(fh / 8));
      c.end(); enc.clearBuffer(S); enc.clearBuffer(R); enc.clearBuffer(gain); surface(enc);
    },
    setSegments(d) { device.queue.writeBuffer(G, 0, d); },
    // idle: nobody is touching, so fog and beads each run on alternate steps (with twice the time).
    step(enc, prof, seen, idle, frame) {
      pass(enc, V.mask, pipes.mask, bg.mask, 6, nSegs);
      let c = enc.beginComputePass({ timestampWrites: prof?.writes('mist+beads') });
      const run = (n, b, x, y = 1) => { c.setPipeline(pipes[n]); c.setBindGroup(0, b); c.dispatchWorkgroups(x, y); };
      if (!idle || frame % 2 === 0) { run('field', bg.field[cur], Math.ceil(fw / 8), Math.ceil(fh / 8)); cur = 1 - cur; }
      run('emit', bg.emit, w64(nSegs)); if (!idle || frame % 2 === 1) { run('merge', bg.merge, w64(nBeads)); run('apply', bg.apply[cur], w64(nBeads)); }
      run('spawn', bg.spawn, w64(MAX_REQ)); run('rain', bg.rain, 1); run('clear', bg.clear, 1);
      c.end();
      c = enc.beginComputePass({ timestampWrites: prof?.writes('liquid') }); const n = w64(MAX_PARTICLES);
      for (let s = 0; s < 2; s++) {
        run('clearCells', bg.clearCells, w64(nCells)); run('predict', bg.predict[cur], n); run('insert', bg.insert, n);
        run('density', bg.density, n); run('relax', bg.relax, n); run('integrate', bg.integrate, n);
      }
      c.end(); surface(enc, prof, seen);
    },
    // Each stage alone, for kumori.bench(). Order-independent enough for timing.
    stages: {
      field: e => one(e, 'field', bg.field[cur], Math.ceil(fw / 8), Math.ceil(fh / 8)), merge: e => one(e, 'merge', bg.merge, w64(nBeads)), apply: e => one(e, 'apply', bg.apply[cur], w64(nBeads)),
      predict: e => one(e, 'predict', bg.predict[cur], w64(MAX_PARTICLES)), density: e => one(e, 'density', bg.density, w64(MAX_PARTICLES)), relax: e => one(e, 'relax', bg.relax, w64(MAX_PARTICLES)), cells: e => one(e, 'clearCells', bg.clearCells, w64(nCells)),
      splat: e => pass(e, V.raw, pipes.splat, bg.splat, 6, MAX_PARTICLES), narrow: e => { pass(e, V.tmp, pipes.nx, bg.nx, 3, 1); pass(e, V.liq, pipes.ny, bg.ny, 3, 1); },
      wide: e => { pass(e, V.wa, pipes.down, bg.down, 3, 1); pass(e, V.wb, pipes.wx, bg.wx, 3, 1); pass(e, V.wide, pipes.wy, bg.wy, 3, 1); },
    },
    destroy() { all.forEach(r => r.destroy()); },
  };
}
