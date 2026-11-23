# Kumori guidelines

No dependencies and no build. If something needs a package, first check whether fifty lines would do.

Say so in the shader when something is a heuristic. The contact-line behaviour in `liquid.wgsl` is one: mobility from local mass against a noise map, not real contact-angle hysteresis. The optics are another: a lens offset from the surface normal, not a traced ray.

Full-screen passes use the noise texture (`nz`, `fbz`). The hashed `vnoise` is for the simulation, where values must not depend on texture filtering. Swapping them in `glass.wgsl` tripled its cost once.

`active`, `target` and other WGSL reserved words bite. Pipelines use `layout: 'auto'`, which drops unused bindings, so every entry point must actually read `U`.

There is no test suite; checks go through `window.kumori` in the console. `advance(seconds)` steps and draws, `stroke(points, seconds)` wipes, `ledger()` reads the water back, `bench()` times each stage, `drift()` measures jitter, `dry = true` hides fog and beads so a growth can be judged on its own, `growth.wake(char, [x, y])` wakes one without touching, and `growth.setAge(i, seconds)` jumps it. Serve with `python3 tools/serve.py 4180`, not plain `http.server`: without `Cache-Control: no-cache` a browser can pair new and old modules, as Safari did. Static hosting needs the same header, or bump the `?v=` stamp on the imports. URL options: `?debug`, `?t=` seconds of warm-up, `?seed=`, `?px=` fixed pixel budget (turns off adaptive resolution), `?rain=`, `?condense=`. `bench()` and fence timing are trustworthy; the `?debug` per-pass timestamps on Apple GPUs are not, because passes overlap.

Each milestone stops for Bernardo to look and touch before the next begins.

Frame rate: use `kumori.measure()`, which counts frames really drawn and returns null when the page isn't being composited (hidden or covered pane). An earlier counter defaulted to 60 and was once reported as a measurement. Queued work outlives the call that made it: `advance(20)` submits 1,200 steps, and GPU load sampled while they drain looks like another app. Await `device.queue.onSubmittedWorkDone()` first, and to learn the true background load close Kumori entirely and wait ten seconds.
