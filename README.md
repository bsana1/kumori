# 曇り Kumori

![A rain-fogged window at night with five Japanese characters written in the mist](assets/card.jpg)

**Try it: [kumori-bernardosana.pages.dev](https://kumori-bernardosana.pages.dev)** (best on a phone)

Kumori ("cloudy") is an interactive rainy window at night. It was inspired by a room at teamLab in Kyoto,
where characters floated in the mist and came alive when my kids touched them. It's a small piece made for
delight. It isn't affiliated with teamLab.

## How to play

- **Wipe the glass** with your finger (or mouse). The fog clears, water gathers at the edge of your
  finger and runs down in drops.
- **Touch a character.** Its strokes melt and run, and something grows behind the glass:
  辺 reeds on still water · 流 snow settling on the street · 菜 a field of rapeseed with butterflies ·
  瑠 little blue ōruri birds · 土 a cherry tree in bloom.
- **Tilt your phone.** Drops on the glass, falling snow and petals follow which way is down.
  The first tap asks for permission to use motion.
- Leave it alone and the glass fogs over again and the character is written back.

The characters spell my name, Bernardo, as *be-ru-na-ru-do*.

## What it needs

A browser with WebGPU: Safari on iOS 26 or later, or a recent Chrome or Edge. Older browsers show a short
message instead. Adding `?diag` to the address shows a startup report on screen, which is handy on a phone.

## How it works

It is plain JavaScript and WebGPU shaders (WGSL), with no libraries and no build step.

- **Water at three scales.** Fog is a texture, small beads are about 144,000 growing droplets, and running
  water is a 2D particle fluid. Water moves between them, so wiping turns fog into drops that run.
- **Light.** The street behind the glass is a small 3D scene with lanterns, defocused like a photograph. The
  glass refracts it through every drop.
- **The name** is written stroke by stroke from KanjiVG stroke-order data.
- **The growths** (tree, field, reeds, snow, birds) are drawn mostly from time and position alone, so they
  cost little to keep.

More detail is in [`.agent/ARCHITECTURE.md`](.agent/ARCHITECTURE.md), and the reasons behind choices are in
[`.agent/DECISIONS.md`](.agent/DECISIONS.md).

## Run it locally

```bash
python3 tools/serve.py
```

Then open http://localhost:4180. Any static file server works. This one tells the browser not to cache, so
edits always show.

## Credits

Made by Bernardo Sana, built together with [Claude](https://claude.com) (Anthropic).
Stroke order from [KanjiVG](https://kanjivg.tagaini.net) by Ulrich Apel, CC BY-SA 3.0. See
[CREDITS.md](CREDITS.md).
