# Kumori architecture

Kumori is a full-screen foggy window you wipe with your fingers. It is an original piece inspired by a teamLab room Bernardo's family visited in Kyoto. The finished version writes his name, 辺流菜瑠土, in the fog; touching a character makes the strokes run and something grow behind the glass. Milestones 1 to 4 are built: the glass, the name, the cherry tree, then the other four growths (a bear that came when all five were awake was removed on 2026-11-23). Sound, iPad tuning and idle self-play are not.

Everything is WebGPU with no libraries and no build step. `index.html` loads `src/main.js`, which fetches the WGSL files at startup and prepends `common.wgsl` to each.

Positions are in "glass units": the pane is always 900 units tall whatever the screen, so the water behaves the same on a phone and a 4K display. Changing resolution never touches the simulation; only a change of aspect ratio rebuilds it.

## Water

Water lives at three scales because no single method looks right at all of them. Mist is a texture (`field.wgsl`: red is fog density, green is the wet film left by a drop or finger). Beads are about 144,000 growing droplets, one per jittered grid site, which makes neighbour search trivial (`beads.wgsl`). Liquid is a 2D particle fluid (`liquid.wgsl`) whose attraction below rest density gives surface tension, so drops merge, stretch and split without rules for it.

Water moves between scales through one request buffer. A shader that takes water away asks for a particle with probability equal to the mass removed divided by a particle's mass. That conserves mass on average without any per-cell bookkeeping. `spawn.wgsl` turns requests into particles using a free list.

Particles are splatted into a texture each step and blurred twice. The narrow blur is the visible surface. The wide one tells each particle how much water is around it, which decides whether a drop clings or runs.

## The name

`letters.js` runs each character through wait, breath, write, hold, melt and gone. `assets/strokes.json` holds stroke-order polylines from KanjiVG (CC BY-SA 3.0, credited in the page source, CREDITS.md and the README; `tools/strokes.py` made it). Every step the segments go to the GPU, where `letters.wgsl` draws them into a mask. The mask holds fog and beads off the strokes, so the letters are simply clear glass.

Before a letter is written, a puff of breath fogs its spot, because a clear stroke needs fog around it to be seen. Touching a held letter sends a front outward from the fingertip; segments release particles as it passes and the fluid does the rest. `createLetters` takes an `onWake(letter, point)` callback; it returns how long the letter should stay away, so 土 is not rewritten over its own tree. Panes taller than wide read top to bottom.

## Growth

`growth.js` owns one HDR layer (1000 rows, premultiplied, 4x MSAA, mipped) that everything else samples: the street takes it before its blurs, so fog and drops carry its colour; `glass.wgsl` draws it again over the defocused street with a much smaller blur; `field.wgsl` thins the fog wherever it has coverage, except around letters still waiting to be touched. That exception is why blossoms first show only through the strokes of the other characters.

`tree.js` builds a different cherry every time by space colonization in about 75 ms, once, on the CPU. `tree.wgsl` does the rest from age alone: limbs, 10,000 blossoms of five petals and the final gust hold no simulation state. Loose petals (up to 1,400, `air.wgsl`) do: they are bodies with momentum in moving air.

Wind starts with a wipe but is not the wipe. `growth.js` stores the push as energy, the wind follows a beat later and fades, and four seconds of its history go to the GPU. `windAt` reads that history with a delay that grows with distance from where the wipe began, so a gust crosses the tree, bends limbs, shivers blossoms and shakes petals loose only where it has arrived.
 The layer is drawn on alternate displayed frames, not per simulation step, so `kumori.advance(20)` in one call sees a stale layer and the fog lags; step in tenths when testing growth.

Each letter wakes one thing: 辺 a sheet of water with reeds and plumes, 流 snowfall, 菜 a rapeseed field with butterflies, 瑠 twelve ōruri (blue-and-white flycatchers, a third of them brown females), 土 the tree. `growth.js` runs their lifecycles (30 s for the reeds and field, 35 s for the tree, 20 s for the snow and birds, then a leaving of 6-8 s) and answers `busy(char)` so a letter is not rewritten over its own growth.

`plants.wgsl` places reeds, plumes, flowers and water from the instance number and age, in screen-relative positions so any pane shape is filled. `snow.wgsl` is stateless too: 14,000 flakes (4-10 mm) each fall through their own column at 0.5-0.9 m/s with a flutter, pushed sideways by the wipe wind, lit by the street lanterns, drawn as the short streak a 1/90 s shutter would catch because the growth layer only updates every other frame. Snow that has settled is not geometry: `growth.cover` (0..1, in `U.pane.z`) builds while it falls and melts slowly after, and `scene.wgsl` whitens the street (edges first, trodden tracks in the middle last, drifts lit by the lanterns, a fine sparkle), the tops of the eaves and roof edges, the lantern lids and the umbrellas, and thickens the air while it falls.

`creatures.js` moves the birds and butterflies on the CPU, because they need to know about fingers, perches and each other; it uploads 64 bytes each. Birds fly perch to perch in bounding flight (beats, then wings shut) and, perched, turn their heads and hop on the ground. Perches are the tops of the nearer street lanterns (`growth.lamps`, set by `main.js`), the ground, and the tree when grown. `life.wgsl` draws birds and butterflies with no meshes: every part is a surface p(u, v) evaluated in the vertex shader. The water draws mirrored copies of the reeds and plumes beneath a blended plane.

A wipe's wind swirls the snow; a fast wipe near a perched bird sends it to another perch. Each growth leaves on its own clock, and its letter is written again in the fog once it has gone.

The mouse pointer is a drop drawn last in `glass.wgsl`. Its centre is exactly the pointer; only its shape lags. It is hidden for touch and fades after six seconds still.

## Light

`scene.wgsl` draws a wet back street analytically (planes, ellipsoids, billboards, one reflection). `lens.wgsl` defocuses it twice: a modest disc blur seen through clear glass, and a wide scatter seen through fog. `glass.wgsl` combines them, and refracts the sharp scene through every bead and drop. `finish.wgsl` adds bloom, AgX tone mapping and grain. Each frame redraws a quarter of the street; the growth layer and the recomposed, refocused view take turns on even and odd frames. Bloom is built once at quarter size. With nobody touching, fog and beads run on alternate simulation steps with twice the time (`pace`); a finger brings them back to every step. The visible surface blur runs only on a frame's last step. Resolution adapts both ways between 1.3M and 4.3M pixels.

## Tilt (added 2026-11-23)

On a phone, `main.js` reads `deviceorientation` (on iPhone and in recent Chrome only after a tap, via `DeviceOrientationEvent.requestPermission`), turns it into the direction of gravity in the plane of the screen allowing for screen rotation, smooths it (time constant ~0.3 s) and writes it to `U.tilt` (the slot the bear's `world[4]` used to occupy): `xy` is "down" on the glass (x right, y down; (0, 1) upright or without a sensor), `z` is snow's sideways drift accumulated so far, `w` its current rate (sideways metres per metre fallen, kept within ±60°). The liquid's gravity follows `tilt.xy`, and drops run off a side frame when the glass is tipped towards it. Snow, which is stateless, shifts each flake sideways by `drift × its speed`, wrapped round the view's width at its depth, so it falls slanting while tipped and straight once level. Loose petals sink along the same slant. The scene itself does not turn with the phone; only what falls and runs does.
