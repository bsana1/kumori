// Thin helpers over WebGPU. No abstraction beyond what this project repeats.
export async function loadShaders(names) {
  const get = async n => { const r = await fetch(new URL(`./shaders/${n}.wgsl`, import.meta.url), { cache: 'no-cache' }); if (!r.ok) throw Error(`shader ${n}: ${r.status}`); return r.text(); };
  const common = await get('common');
  // 'shade:tree' is tree.wgsl with shade.wgsl in front of it, under the name 'tree'.
  return Object.fromEntries(await Promise.all(names.map(async n => { const p = n.split(':'); return [p.at(-1), [common, ...await Promise.all(p.map(get))].join('\n')]; })));
}
export function createGPU(device, uniformBuffer) {
  const mods = new Map();
  const mod = (code, label) => { if (!mods.has(code)) mods.set(code, device.createShaderModule({ code, label })); return mods.get(code); };
  // `at` maps binding number -> resource; binding 0 is always the uniforms.
  const group = (pipe, at) => device.createBindGroup({ label: pipe.label, layout: pipe.getBindGroupLayout(0), entries: [{ binding: 0, resource: { buffer: uniformBuffer } }, ...Object.entries(at).map(([b, r]) => ({ binding: +b, resource: r instanceof GPUBuffer ? { buffer: r } : r }))] });
  const compute = (code, entry) => device.createComputePipeline({ label: entry, layout: 'auto', compute: { module: mod(code, entry), entryPoint: entry } });
  const render = (code, vs, fs, format, blend) => device.createRenderPipeline({ label: fs, layout: 'auto', vertex: { module: mod(code, fs), entryPoint: vs }, fragment: { module: mod(code, fs), entryPoint: fs, targets: [{ format, blend }] }, primitive: { topology: 'triangle-list' } });
  const tex = (w, h, format, usage, mips = 1) => device.createTexture({ size: [Math.max(1, w | 0), Math.max(1, h | 0)], format, mipLevelCount: mips, usage });
  const buf = (size, usage = GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST) => device.createBuffer({ size, usage });
  return { group, compute, render, tex, buf };
}
// GPU time per named pass, when the adapter supports it.
export function createProfiler(device, on) {
  const ok = on && device.features.has('timestamp-query'); const MAX = 32; const times = {};
  if (!ok) return { writes: () => undefined, resolve() {}, read() {}, times };
  const qs = device.createQuerySet({ type: 'timestamp', count: MAX * 2 });
  const rb = device.createBuffer({ size: MAX * 16, usage: GPUBufferUsage.QUERY_RESOLVE | GPUBufferUsage.COPY_SRC });
  const mb = device.createBuffer({ size: MAX * 16, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
  let names = [], busy = false, armed = false, snap = [];
  return {
    times,
    begin() { names = []; },
    writes(name) { if (names.length >= MAX) return; const i = names.push(name) - 1; return { querySet: qs, beginningOfPassWriteIndex: i * 2, endOfPassWriteIndex: i * 2 + 1 }; },
    resolve(enc) { if (busy || !names.length) return; enc.resolveQuerySet(qs, 0, names.length * 2, rb, 0); enc.copyBufferToBuffer(rb, 0, mb, 0, names.length * 16); snap = names.slice(); armed = true; },
    async read() { if (!armed || busy) return; armed = false; busy = true; try { await mb.mapAsync(GPUMapMode.READ); const t = new BigInt64Array(mb.getMappedRange()); const acc = {}; snap.forEach((n, i) => { acc[n] = (acc[n] || 0) + Number(t[i * 2 + 1] - t[i * 2]) / 1e6; }); for (const n in acc) times[n] = times[n] == null ? acc[n] : times[n] * 0.9 + acc[n] * 0.1; mb.unmap(); } catch (e) { console.warn('profiler', e.message); } busy = false; },
  };
}
