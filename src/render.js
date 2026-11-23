// Scene -> lens -> glass -> finish, in linear HDR.
export function createRenderer(device, g, sh, samp, format) {
  const { group, render, tex } = g; const U = GPUTextureUsage, RT = U.RENDER_ATTACHMENT | U.TEXTURE_BINDING;
  const HDR = 'rgba16float';
  const over = { color: { srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha' }, alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' } };
  const pipes = {
    scene: render(sh.scene, 'vs', 'fs', HDR), mip: render(sh.blur, 'vs', 'copy', HDR),
    clear: render(sh.lens, 'vs', 'clearView', HDR), fog: render(sh.lens, 'vs', 'fogView', HDR),
    over: render(sh.over, 'vs', 'over', HDR, { color: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' }, alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' } }),
    beads: render(sh.splat, 'vsBead', 'fsBead', 'rgba8unorm', over),
    glass: render(sh.glass, 'vs', 'fs', HDR), finish: render(sh.finish, 'vs', 'fs', format), bloom: render(sh.finish, 'vs', 'bloom', HDR),
  };
  const N = 256, noise = device.createTexture({ size: [N, N], format: 'r8unorm', usage: U.TEXTURE_BINDING | U.COPY_DST });
  let s = 1; const rand = () => (s = Math.imul(s ^ (s >>> 15), 2246822519) + 0x9e3779b9 | 0, ((s ^ (s >>> 13)) >>> 0) % 256);
  device.queue.writeTexture({ texture: noise }, Uint8Array.from({ length: N * N }, rand), { bytesPerRow: N }, [N, N]);
  const nz = { 14: device.createSampler({ addressModeU: 'repeat', addressModeV: 'repeat', magFilter: 'linear', minFilter: 'linear' }), 15: noise.createView() };
  let T = null, W = null, Gr = null, n = 0;
  const mipViews = t => Array.from({ length: t.mipLevelCount }, (_, i) => t.createView({ baseMipLevel: i, mipLevelCount: 1 }));
  const mipGroups = vs => vs.slice(0, -1).map(v => group(pipes.mip, { 1: samp, 2: v }));
  function resize(cw, ch, water, growth) {
    if (T) Object.values(T).forEach(t => t.destroy());
    const s = Math.min(1, 800 / cw);
    T = {
      street: tex(cw * s, ch * s, HDR, RT), scene: tex(cw * s, ch * s, HDR, RT, 6), clear: tex(cw / 3, ch / 3, HDR, RT), fog: tex(cw / 6, ch / 6, HDR, RT),
      beads: tex(cw, ch, 'rgba8unorm', RT), hdr: tex(cw, ch, HDR, RT, 6), bloom: tex(cw / 4, ch / 4, HDR, RT),
    };
    W = water; Gr = growth; n = 0; const V = water.views; const sv = mipViews(T.scene), hv = mipViews(T.hdr);
    bind = {
      over: group(pipes.over, { 1: samp, 2: growth.view }), gm: mipGroups(growth.mips),
      sv, hv, sm: mipGroups(sv), hm: mipGroups(hv), clearV: T.clear.createView(), fogV: T.fog.createView(), beadV: T.beads.createView(),
      streetV: T.street.createView(), scene: group(pipes.scene, nz), copy: group(pipes.mip, { 1: samp, 2: T.street.createView() }), clear: group(pipes.clear, { 1: samp, 2: T.scene.createView() }), fog: group(pipes.fog, { 1: samp, 2: T.scene.createView() }),
      beads: group(pipes.beads, { 1: water.B }),
      glass: [0, 1].map(i => group(pipes.glass, { 1: samp, 2: T.scene.createView(), 3: T.clear.createView(), 4: T.fog.createView(), 5: V.field[i], 6: V.liq, 7: V.wide, 8: T.beads.createView(), 9: V.mask, 10: growth.view, ...nz })),
      bloomV: T.bloom.createView(), bloom: group(pipes.bloom, { 1: samp, 2: T.hdr.createView() }), finish: group(pipes.finish, { 1: samp, 2: T.hdr.createView(), 3: T.bloom.createView() }),
    };
  }
  let bind = null;
  const pass = (enc, view, pipe, bg, verts = 3, inst = 1, tw, loadOp = 'clear', clip) => {
    const p = enc.beginRenderPass({ colorAttachments: [{ view, loadOp, storeOp: 'store', clearValue: [0, 0, 0, 0] }], timestampWrites: tw });
    if (clip) p.setScissorRect(...clip); p.setPipeline(pipe); p.setBindGroup(0, bg); p.draw(verts, inst); p.end();
  };
  return {
    resize, noise: nz,
    stages: {
      scene: e => pass(e, bind.streetV, pipes.scene, bind.scene), mips: e => bind.sm.forEach((m, i) => pass(e, bind.sv[i + 1], pipes.mip, m)),
      clearView: e => pass(e, bind.clearV, pipes.clear, bind.clear), fogView: e => pass(e, bind.fogV, pipes.fog, bind.fog),
      beads: e => pass(e, bind.beadV, pipes.beads, bind.beads, 6, W.beadInstances), tree: e => { if (Gr.draw(e)) bind.gm.forEach((m, i) => pass(e, Gr.mips[i + 1], pipes.mip, m)); }, glass: e => pass(e, bind.hv[0], pipes.glass, bind.glass[W.fieldIndex]), bloom: e => pass(e, bind.bloomV, pipes.bloom, bind.bloom), hdrMips: e => bind.hm.forEach((m, i) => pass(e, bind.hv[i + 1], pipes.mip, m)),
    },
    draw(enc, target, prof) {
      const b = bind, w = n => prof?.writes(n);
      // The street changes slowly, so alternate: redraw it on even frames, refocus it on odd ones.
      // Nothing outside changes quickly, and it is all defocused. Each frame redraws a quarter of the street;
      // the growth, and the recomposed and refocused view, take turns on even and odd frames.
      const first = n === 0, k = n++ % 4, h = T.street.height, q = Math.ceil(h / 4);
      pass(enc, b.streetV, pipes.scene, b.scene, 3, 1, w('scene'), first ? 'clear' : 'load', first ? null : [0, k * q, T.street.width, Math.min(q, h - k * q)]);
      if (first || k % 2 === 0) { if (Gr.draw(enc, prof)) b.gm.forEach((m, i) => pass(enc, Gr.mips[i + 1], pipes.mip, m)); }
      if (first || k % 2 === 1) {
        pass(enc, b.sv[0], pipes.mip, b.copy); if (Gr.active) pass(enc, b.sv[0], pipes.over, b.over, 3, 1, undefined, 'load');
        b.sm.forEach((m, i) => pass(enc, b.sv[i + 1], pipes.mip, m));
        if (first || k === 1) pass(enc, b.clearV, pipes.clear, b.clear, 3, 1, w('lens'));
        if (first || k === 3) pass(enc, b.fogV, pipes.fog, b.fog, 3, 1, w('lens'));
      }
      pass(enc, b.beadV, pipes.beads, b.beads, 6, W.beadInstances, w('beads'));
      pass(enc, b.hv[0], pipes.glass, b.glass[W.fieldIndex], 3, 1, w('glass')); b.hm.forEach((m, i) => pass(enc, b.hv[i + 1], pipes.mip, m));
      pass(enc, b.bloomV, pipes.bloom, b.bloom, 3, 1, w('finish'));
      pass(enc, target, pipes.finish, b.finish, 3, 1, w('finish'));
    },
  };
}
