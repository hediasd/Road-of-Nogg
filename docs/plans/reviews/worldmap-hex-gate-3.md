# World map hex authoring — Gate 3 findings

Run 2026-09-07, after WMH-7 (placed objects), WMH-8 (terrain height), WMH-9 (one history for
three kinds of edit) and WMH-10 (sub-triangle detail, `7169153`). Gate 3's job, per
`docs/plans/worldmap-hex-authoring.md`: decide whether the confirmed product — paint, sculpt,
place, save, export — is demonstrably there, and whether Phase 4 opens as written.

## Verdict: CONTINUE, with one item recommended before WMH-11

The **model** is complete and correct. The **editor** is not: three of the four things Phase 3
built have no user interface at all. Phase 4 as written adds a fifth.

## The question, answered

**The data model, yes. The tool, no.**

One map was authored end to end and carried through every step the item names. A 19 × 14 lattice
(266 cells, 29 × 29 units), ground painted in three strokes, terrain sculpted into a hill and a
basin, 36 sub-triangle detail slots along a road, five buildings placed — then undone, redone,
saved, reopened, re-saved and exported.

| Step | Result |
|---|---|
| Author ground | 266-cell fill, an 18-cell hex line, a 19-cell hex disc, 3 strokes |
| Sculpt | hill peak **+2.93**, basin floor **−1.37**, untouched ground **0.00** (246 vertices, 2 strokes) |
| Paint detail | 36 slots over 18 cells, masked to their own triangles |
| Place objects | `o000`–`o004`; the hilltop tower anchors at 2.93, a lowland house at 0.00 |
| Undo, then redo | 6 strokes spanning tile, height **and** object edits, on one stack, back to an identical document |
| Save | source and bake both written, dirty cleared |
| Reopen | **failed** — see finding 1, now fixed |
| Re-save with no edit | **failed** — same defect, now fixed |
| Export | refused in-session (Gate 2's import friction, unchanged), succeeded after an import pass |
| Instantiate | root + `Ground` + `Objects/o000…o004`, editor absent |

The one interpolation held all the way through: the exported terrain mesh's vertices run from
**−1.398 to +2.963** and match `WorldMapHeightField.sample()` at every cell centre checked. What
was sculpted is what shipped.

## Finding 1 — the object layer did not survive disk (fixed, `2793e39`)

Reopening a map with buildings on it produced a document that differed from the one saved, and
re-saving it with no edit rewrote the file — 5,064 bytes became 5,104.

```
line 278: 6,                 -> 6.0,
line 281: "FACING": 0,       -> "FACING": 0.0,
line 282: "FOOTPRINT": 0,    -> "FOOTPRINT": 0.0,
```

JSON has one number type. Every integer field of every object record came back from the parser as
a float, so `WorldMapTileData.saveTo`'s own documented invariant — *"a re-save with nothing
changed produces a byte-identical file"* — was false for every map with a building on it. The
committed `temp2_hex32_authored.json` would have been rewritten field by field the first time
anyone opened and saved it.

**The list is the one layer kind this could happen to.** Grid, heights and detail each rebuild
typed storage from their own RLE; the list stores dictionaries the format has no schema for, so
it alone could not restore what JSON dropped. The fix puts that schema in `WorldMapObjectLayer`,
the file that defines what an item means, rather than hardcoding object field names into the
format.

Nothing rendered or stood in the wrong place — every read already went through `int()` or
`float()` — so this was file churn, not a wrong map. It is fixed rather than merely reported
because a format defect gets more expensive with every map authored against it.

`probe_document_loop` now exercises all four layer kinds in one document and compares **bytes**
across a real reload. Its previous check said "byte-for-byte identical" while comparing
dictionaries of a document that had only grid layers — which is exactly why four items' worth of
new layer kinds went by without this surfacing.

## Finding 2 — the editor reaches one of the four layers

This is the finding that decides the verdict.

```
WorldMapEditorController.LAYERS  = ground, overlay
WorldMapEditorController.TOOLS   = navigate, inspect, paint, rectangle, line,
                                   fill, eyedropper, stamp, scatter, replace
WorldMapEditorHud                = no reference to heights, objects or detail
```

A human sitting in front of the editor today can paint tile-grade layers and nothing else. There
is no sculpt tool, no place-an-object tool, no detail brush, and no layer row for any of the
three. Every step of the exercise above that touched heights, objects or detail was driven
through the module APIs, exactly as this gate's driver had to.

The controller is not ignorant of the new work — it already samples the height field when picking
(so a click lands on sculpted terrain rather than the flat plane) and the exporter already ships
all of it. The gap is precisely and only the authoring surface.

That matters more than a missing convenience, because **WMH-13 is "Prove the whole workflow, and
measure it"**, and a workflow that has to be driven from a script is not the workflow being
proved. Water (WMH-11) would add a fifth layer with no way to author it either.

## Finding 3 — sculpting works and cannot be seen

The map ships real relief and the player cannot tell. At the shipping framing the sculpted map
and a flat one are indistinguishable:

| Framing | Hill reads? |
|---|---|
| pitch 60, whole map (`gate3_map_oblique`) | no |
| pitch 88, top down (`gate3_map_top`) | no |
| pitch 35, close on the hilltop (`gate3_hill_closeup`) | no |
| pitch 15, grazing (`gate3_hill_grazing`) | **yes** — the horizon visibly bulges under the tower |

The geometry is correct at every one of these; the ground is unlit flat-colour art, so a 2.93-unit
rise across a 12-unit hill produces no shading and almost no silhouette until the camera drops to
the editor's minimum pitch. Gate 2 deferred this as a lighting question; Gate 3 measured it, and
it is now the largest gap between what the tool stores and what the game shows.

It is a **look** problem, not a data problem, and it is not obviously a lighting one — a
hand-painted world map may well want cliff and slope art rather than a light source. Naming it
here, unresolved, because whoever picks it up should decide that question rather than reach for a
`DirectionalLight3D` by reflex.

## What else the run measured

- **Sub-triangle detail reads clearly at every framing** — the one Phase 3 feature that is visible
  in the shipped scene. WMH-10's per-pixel triangle mask holds up visually: painted slots are
  clean triangles inside their hex, not whole frames.
- **Detail still has no undo.** Confirmed live rather than by reading code: the session's stack
  held 6 strokes covering tile, height and object edits, and the 36 detail slots were outside it.
  Named in `WORLDMAP_EDITOR.md` §16; still open.
- **The exported scene is 32,798 bytes, and 27,209 of them are the terrain mesh** — one ArrayMesh
  sub-resource per map, scaling with cell count. A 266-cell map costs 27 KB of text-encoded
  geometry; ten times the map is roughly ten times that. Correct (it is derived and regenerated
  wholesale, unlike the embedded-image failure WMH-6 refuses) but a number worth knowing before
  Phase 4 builds anything large.
- **Objects ship as box placeholders**, unchanged since WMH-7. Position, facing and anchoring are
  the contract; the art is not.
- **`scenes/worldmap/generated/` was not ignored.** WMH-6 decided exported scenes must never be
  committed, and nothing enforced it — every export left the tree dirty. Fixed in the same commit.
- **Gate 2's import friction is unchanged**: author → save → **import** → export, and the middle
  step is still one the standalone editor cannot take.
- Two stale probes (`probe_catalogs`, `probe_validation`) fail to parse on a
  `WorldMapGroundUniforms.K_CLOUD_STRENGTH` that no longer exists. Pre-existing, unrelated to this
  cycle, reported rather than fixed. The other 18 worldmap probes pass.

## Recommendation

**Insert one item before WMH-11: give the editor the three layers it cannot reach.** Layer rows
for heights, objects and detail; a sculpt tool, a place tool and a triangle brush; detail routed
through `WorldMapEditHistory` so undo covers all four kinds rather than three.

The argument for doing it now rather than after Phase 4: every item since WMH-7 has widened the
distance between what the format stores and what a person can author, and WMH-11 widens it again.
WMH-13 cannot prove a workflow that only a script can drive.

The argument against — worth stating, since it is a real judgement and not a formality: Phase 4's
items are about *representation* (how water works, how a bridge spans), and representation
decisions are cheaper to change before a UI is built against them. Doing the UI first means
building it twice if water changes what a layer row is.

I think the first argument wins, because water and bridges are additions to the same layer kinds
the UI would expose, not new kinds. But this is a plan change, so it is a recommendation and not
an edit — `docs/plans/worldmap-hex-authoring.md` is untouched by this gate.

## Next

Phase 4 opens with WMH-11 (minimal water), routed to Opus 5 / GPT Sol — unless the recommended
editor item is inserted first.
