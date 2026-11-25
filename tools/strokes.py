#!/usr/bin/env python3
"""Flatten KanjiVG stroke paths (M, C, c only) to polylines.  usage: strokes.py DIR OUT.json"""
import json, re, sys
# 桜梅桃李 (ōbaitōri): cherry, plum, peach, sumomo; each blooms in its own way. (Until 2026-11-25: 辺流菜瑠土.)
CHARS = [("桜", "0685c"), ("梅", "06885"), ("桃", "06843"), ("李", "0674e")]

def flatten(d, step=1.6):
    tok = re.findall(r"[A-Za-z]|-?(?:\d+\.\d+|\.\d+|\d+)", d)
    i, cmd, x, y, pts = 0, None, 0.0, 0.0, []
    def num():
        nonlocal i; v = float(tok[i]); i += 1; return v
    while i < len(tok):
        if tok[i].isalpha(): cmd = tok[i]; i += 1
        if cmd == "M": x, y = num(), num(); pts.append((x, y))
        elif cmd in "Cc":
            p = [num() for _ in range(6)]
            if cmd == "c": p = [v + (x if k % 2 == 0 else y) for k, v in enumerate(p)]
            x0, y0 = x, y
            for k in range(1, 25):
                t = k / 24; u = 1 - t
                pts.append((u**3*x0 + 3*u*u*t*p[0] + 3*u*t*t*p[2] + t**3*p[4], u**3*y0 + 3*u*u*t*p[1] + 3*u*t*t*p[3] + t**3*p[5]))
            x, y = p[4], p[5]
        else: raise SystemExit(f"unhandled path command {cmd}")
    out = [pts[0]]
    for q in pts[1:]:
        if (q[0]-out[-1][0])**2 + (q[1]-out[-1][1])**2 >= step*step: out.append(q)
    if out[-1] != pts[-1]: out.append(pts[-1])
    return [[round(a - 54.5, 2), round(b - 54.5, 2)] for a, b in out]   # KanjiVG's box is 109 units

res = [{"char": c, "strokes": [flatten(d) for d in re.findall(r'<path[^>]*? d="([^"]+)"', open(f"{sys.argv[1]}/{f}.svg", encoding="utf8").read())]} for c, f in CHARS]
doc = {"credit": "Stroke order and shapes from KanjiVG (https://kanjivg.tagaini.net), copyright Ulrich Apel, CC BY-SA 3.0. Flattened to polylines by tools/strokes.py; this file is under the same licence.", "box": 109, "chars": res}
json.dump(doc, open(sys.argv[2], "w", encoding="utf8"), ensure_ascii=False, separators=(",", ":"))
for r in res: print(r["char"], len(r["strokes"]), sum(len(s) for s in r["strokes"]))
