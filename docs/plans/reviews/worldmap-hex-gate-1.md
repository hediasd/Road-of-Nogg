# World map hex authoring — Gate 1 findings

Run 2026-09-07, after WMH-1 (camera fit and shortcut focus, `676e2e1`), WMH-2 (the hex lattice
and hex picking, `b95ee46`), WMH-3 (the hex grid overlay, `e2694c8`) and WMH-4 (hex brushes,
`9af9585`). Gate 1's job, per `docs/plans/worldmap-hex-authoring.md`: decide whether hex
authoring is going the right direction before Phase 2 pays for a document loop and an export
path built on top of it.

Run against a real window (Vulkan, Forward+), not headless — the renders below are actual
frames. Every render uses **synthetic flat colours**, not `temp2_hex32_ground`, because the
cycle file says in terms that the placeholder art is 2× upscaled square art and nothing visual
may be tuned against it. What is being judged here is the lattice, the overlay and the brush
geometry, none of which the placeholder can mislead.

## Verdict: CONTINUE

Phase 2 opens as written. Two findings, both concrete, neither structural — see "Findings".
The geometric bet the whole cycle rests on is confirmed correct.

## The four questions, answered

### 1. Is 32 px the right hex size at the framing you actually use?

**Yes — 32 px, confirmed by measurement, and the two alternatives are both wrong by a wide
margin.** Measured from `WorldMapCameraRig.framingReadout` at 1920×1080:

| preset | tiles/row | hexes across | buffer px/hex |
|---|---|---|---|
| `tile_exact` | 53.3 | **35.5** | 28.84 |
| `closer` | 36.3 | 24.2 | 42.30 |
| `crt` | 45.1 | 30.1 | 28.33 |
| `overview` | 84.7 | 56.5 | 18.13 |

Against the alternatives the gate named, at `tile_exact`:

| art px | world units | hexes across | vs the ~34 the console reference used |
|---|---|---|---|
| 24 px | 1.50 | 47.3 | **+39%** |
| **32 px** | **2.00** | **35.5** | **+4%** |
| 48 px | 3.00 | 23.7 | **−30%** |

32 px lands within 4% of the reference density. Nothing else is close.

**One argument that does not work, recorded so it is not re-litigated:** art-to-buffer
minification is **invariant at 1.11× across all three sizes**, because a bigger hex buys a
proportionally bigger world cell. Sharpness cannot distinguish these options — only on-screen
density can. Anyone reopening this question with a "but the art would be crisper at N px"
argument is using a number that is the same for every N.

### 2. Does the overlay carry the lattice well enough that uniform terrain is still navigable?

**Yes, at tile grade — and this is the gate's most important positive result.**

Without the overlay, a uniform field is exactly what the cycle file predicted: hex structure is
completely invisible, appearing only at terrain boundaries and the map edge. With WMH-3's
overlay on, the lattice reads clearly across the whole field, holds up into the distance under
fog, and shows no shimmer or moiré at pitch 60.

Two things worth recording beyond a pass:

- **The hexes read as *regular* hexagons on screen.** This is the load-bearing geometric claim
  of the entire cycle — flat-top hexes pre-stretched so the pitch-60 vertical squash cancels —
  and it is now confirmed visually rather than only in the arithmetic. If this had been wrong,
  everything downstream would have been drawn against a distorted cell.
- **The cursor is the hex's own silhouette**, not its bounding box, which is what WMH-3 was for.

At **sub-triangle grade the answer changes**, and that is Finding 2 below.

### 3. Do the brushes behave as expected on both column parities?

**Yes.** Painted by hand through the real WMH-4 brushes and rendered: two radius-3 discs on an
even and an odd column read as the same shape; two `stampHex` flowers (anchor plus all six
axial neighbours) anchored on an even and an odd column come out **identical**; hex lines are
connected with every step hex-adjacent and no diagonal jumps.

The stamp pair is the one that matters. `stampHex` addresses by axial offset precisely because
offset deltas are not translation-invariant across a parity boundary — had it used offset
deltas, one of those two flowers would have come out malformed. It does not. The probe already
asserted this arithmetically; this gate confirms it is also true of what reaches the screen.

### 4. Is the square-with-margin shape right, or does the margin want a terrain?

**The shape is right, and the margin does not want a terrain.** The margin is structurally
bounded: the lattice always packs to within one step of the declared side, so margin can never
exceed **1.5 units horizontally or 2.0 vertically** regardless of map size. Searching for the
worst case near 50 units gives a 48.475-unit square inscribing a 31×23 lattice — margin
1.48 × 1.48 units, **3.0% of the side**, and shrinking in relative terms as maps grow (well
under 1% on the 155-unit reference map).

Rendered with the margin as void colour and again as a water terrain, the two are nearly
indistinguishable: the margin sits exactly where fog closes and the void takes over anyway.
Making it authorable would be a knob that changes almost nothing. **Void colour stays.**

That said, the margin is where this gate found its sharpest defect — Finding 1.

## Findings

### Finding 1 — The overlay and the picker are bounded by the REGION, not the LATTICE (defect)

**This is a real defect in shipped code, not a preference.** On a map with margin, the overlay
draws a full column of hexes over the margin strip, the cursor highlights them, and picking
returns them as ordinary cells — but they hold no data and cannot be painted. Verified end to
end rather than reasoned about:

```
a point at (47.5, 10.0) — inside region, outside lattice:
  worldToCell     -> (31, 4)
  inside region?  -> true
  Hex.contains?   -> false
painting that cell:
  brush reported  -> false
  getCell         -> '-'
  history entries -> 0
```

So the user sees a hex, hovers it and it lights up, clicks it, and **nothing happens with no
feedback whatsoever**. The left edge of the same map (no margin there — the lattice starts at
the origin, so margin is always right and bottom) ends cleanly, which is what makes the
asymmetry visible in the render.

The cause is inherited rather than careless: `WorldMapSurfacePick.pickTile` bounds-checks
against `region`, and the shader's `off_map` test does the same. Both were correct while region
and lattice were the same rectangle. The square path still is. The hex path is not, and WMH-3
and WMH-2 both carried the old assumption forward without anyone noticing, because until this
gate no map with actual margin had been rendered.

**Fix, both small:** `pickTile` returns `null` when `WorldMapHexGrid.contains` is false, and the
shader bounds the hex overlay by the lattice extent rather than the region rect. Being done as
an immediate follow-up to this gate rather than deferred — it is a defect in code this cycle
just shipped, and it is cheap.

### Finding 2 — Sub-triangle grade costs the hex read (design change, routed to WMH-10)

At tile grade the hexes read cleanly. Turn the sub-triangle fan on and the primary read flips
from "a field of hexes" to "a field of triangles" — the hex boundary becomes hard to trace even
though hex edges are drawn at 0.30 alpha against the fan's 0.12.

This is not a bug in the fan; the fan is geometrically correct. Six spokes per hex, tiled, form
a triangular lattice — that is simply what the correct answer looks like. The problem is that
**hex edges and spokes share geometry**: spokes terminate exactly on hex vertices, so the two
line sets interlock into one lattice and a 2.5× alpha ratio is not enough separation. The square
path never faced this, because cel lines sat at a 4× finer pitch *inside* tiles and were
obviously subordinate.

**Recommendation, recorded for WMH-10 rather than acted on now:** draw the sub-triangle fan only
within a small radius of the cursor rather than across the whole map. You only need triangle
precision where you are actually pointing, it removes the legibility problem completely instead
of trading it against a contrast ratio, and it costs less fill besides. If that is rejected,
the fallback is a much wider alpha split plus a weight difference, but the local-fan answer is
better and should be tried first.

This is deliberately **not** fixed here: WMH-10 is the item that builds sub-triangle tools, and
this is a decision about how those tools present, not a defect in what WMH-3 shipped.

## What this gate did not re-litigate

- **Flat-top over pointy-top.** Settled in the cycle file on a geometric property, and this
  gate confirms the property holds on screen. Closed.
- **The 16 px world unit.** Unchanged and unchallenged; the 32 px hex result *depends* on
  keeping it, since that is what makes a hex exactly two world units.
- **`temp2_hex32_ground`'s look.** Explicitly out of scope per the cycle file. No render here
  used it.
- **Whether the square path still works.** Not this gate's question; `probe_bake_parity`'s
  byte-exact test guards it and no shipping code changed during this gate.

## Next

Phase 2 opens: WMH-5 (the document lifecycle), the item the rest of the phase is built on.

Before it, one follow-up commit fixes Finding 1 — it is in code this cycle shipped, the fix is
two small bounds changes, and leaving a defect in the picker underneath a phase that builds a
document loop on top of it would be the wrong order.
