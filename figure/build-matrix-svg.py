#!/usr/bin/env python3
"""Renders the mate invocation dot matrix (one dot per run) as SVG.
Data: the per-cell results in ../results, in actual run order."""

BLUE, GREEN, INK, MUT = "#2a78d6", "#008300", "#52514e", "#b9b7b0"
SURF, T1, T2 = "#fcfcfb", "#0b0b0b", "#52514e"

# per model: [no-files, discovery-current, discovery-PR, injected-current, injected-PR] as 0/1 strings
ROWS = [
    ("Claude models (subagent harness)", [
        ("haiku-4.5",      ["00000", "10000", "11111", "11011", "11111"], ""),
        ("sonnet-5",       ["00000", "10000", "11111", "11101", "11111"], ""),
    ]),
    ("external agent CLIs (headless)", [
        ("gpt-5.6-terra",  ["00010", "11111", "11111", "11111", "11111"], ""),
        ("gpt-5.6-luna",   ["00000", "11111", "11111", "11111", "11111"], ""),
        ("gpt-5.6-sol",    ["00000", "11111", "11111", "11111", "11111"], ""),
        ("grok-4.5",       ["00000", "11111", "11111", "11111", "11111"], ""),
        ("deepseek-v4-pro",["0000",  "01110", "11111", "11111", "11111"], "1"),
        ("kimi k3",        ["00000", "11001", "11101", "11111", "11111"], ""),
    ]),
    ("local open-weight (ollama)", [
        ("qwen3.8-27b",    ["00000", "10111", "11111", "01011", "11101"], "2"),
        ("qwen3:14b",      ["00000", "00000", "00000", "00000", "00000"], "3"),
    ]),
]

# column colors: no-files=ink, current text=blue, this PR=green
COLCOLOR = [INK, BLUE, GREEN, BLUE, GREEN]
X0 = [175, 264, 339, 429, 504]   # sub-column origins
DOT_DX, R_FILL, R_HOLLOW = 13, 4.5, 4

W, H = 600, 470
out = []
out.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
           f'viewBox="0 0 {W} {H}" font-family="system-ui, -apple-system, \'Segoe UI\', sans-serif">')
out.append(f'<rect width="{W}" height="{H}" fill="{SURF}"/>')
out.append(f'<text x="10" y="24" font-size="13" font-weight="600" fill="{T1}">mate invocation per run — one dot per run (n=5 per cell)</text>')

def center(i): return X0[i] + 32
# column headers
out.append(f'<text x="{center(0)}" y="52" font-size="11" fill="{T2}" text-anchor="middle">no instruction files</text>')
out.append(f'<text x="{(center(1)+center(2))//2}" y="52" font-size="11" fill="{T2}" text-anchor="middle">file discovery</text>')
out.append(f'<text x="{(center(3)+center(4))//2}" y="52" font-size="11" fill="{T2}" text-anchor="middle">injected</text>')
for i, lbl in [(1, "current text"), (2, "this PR"), (3, "current text"), (4, "this PR")]:
    out.append(f'<text x="{center(i)}" y="68" font-size="10" fill="{T2}" text-anchor="middle">{lbl}</text>')

def cell(x0, y, bits, color):
    s = []
    for i, b in enumerate(bits):
        cx = x0 + 6 + i * DOT_DX
        if b == "1":
            s.append(f'<circle cx="{cx}" cy="{y}" r="{R_FILL}" fill="{color}"/>')
        else:
            s.append(f'<circle cx="{cx}" cy="{y}" r="{R_HOLLOW}" fill="none" stroke="{MUT}" stroke-width="1.5"/>')
    return "".join(s)

y = 78
totals, ns = [0]*5, [0]*5
for gname, rows in ROWS:
    out.append(f'<text x="10" y="{y}" font-size="10" fill="{T2}" font-style="italic">{gname}</text>')
    y += 16
    for name, cells, fn in rows:
        sup = f'<tspan font-size="8" baseline-shift="super">{fn}</tspan>' if fn else ""
        out.append(f'<text x="10" y="{y+4}" font-size="12" fill="{T1}">{name}{sup}</text>')
        for ci, bits in enumerate(cells):
            out.append(cell(X0[ci], y, bits, COLCOLOR[ci]))
            totals[ci] += bits.count("1"); ns[ci] += len(bits)
        y += 24
    y += 6

# totals row + winner check mark
y += 2
out.append(f'<line x1="10" y1="{y-12}" x2="{W-10}" y2="{y-12}" stroke="#e5e4e0" stroke-width="1"/>')
out.append(f'<text x="10" y="{y+4}" font-size="11" font-weight="600" fill="{T1}">invoked, total</text>')
win = {2, 4}  # these win their channel
for ci in range(5):
    mark = " ✓" if ci in win else ""
    wt = "600" if ci in win else "400"
    out.append(f'<text x="{center(ci)}" y="{y+4}" font-size="11" font-weight="{wt}" fill="{T1}" text-anchor="middle">{totals[ci]}/{ns[ci]}{mark}</text>')
y += 24

# footnotes
cap = [
    "✓ = higher invocation total within its channel.  Hollow dots are runs without a single mate execution —",
    "e.g. sonnet-5’s one hollow dot under injected/current text is an explicit refusal of the imperative wording.",
    "¹ n=4 (one run lost to a tooling error)   ² invokes the tools but produced no working fix in any run   ³ no tool use, no edits",
]
for line in cap:
    out.append(f'<text x="10" y="{y}" font-size="9.5" fill="{T2}">{line}</text>')
    y += 13

# legend
y += 8
lx = 10
for color, filled, lbl in [(BLUE, True, "invoked — current text"), (GREEN, True, "invoked — this PR’s text"),
                           (INK, True, "invoked — no instructions"), (None, False, "not invoked")]:
    if filled:
        out.append(f'<circle cx="{lx+5}" cy="{y-4}" r="{R_FILL}" fill="{color}"/>')
    else:
        out.append(f'<circle cx="{lx+5}" cy="{y-4}" r="{R_HOLLOW}" fill="none" stroke="{MUT}" stroke-width="1.5"/>')
    out.append(f'<text x="{lx+14}" y="{y}" font-size="10.5" fill="{T2}">{lbl}</text>')
    lx += 150

out.append('</svg>')
path = "mate-invocation-matrix.svg"
open(path, "w").write("\n".join(out))
print(f"geschrieben: {path}  (Summen: {['%d/%d' % (t, n) for t, n in zip(totals, ns)]})")
