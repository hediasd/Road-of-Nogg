# World map hex authoring — WMH-13, the acceptance example and the measurements

Run 2026-09-07, after WMH-12 (`92a8643`), against the whole cycle: WMH-1 through WMH-12 plus
WMH-10B and three gates. Artifacts in `debug/worldmap/validation/hex/` (gitignored).

## Verdict: the cycle delivers what it promised, and the editor does not scale to a full-size map

The acceptance example ran end to end and every fact survived the round trip exactly. The
measurements are where the news is: on the 103 × 77 region this cycle was sized against, **a
partial rebake of a map carrying sub-triangle detail takes 27 seconds where a full bake of the
whole map takes 1.6** — so the editor's incremental redraw, the thing that makes painting feel
immediate, is the slowest part of it, by two orders of magnitude.

That is a bug with an obvious fix, not a design failure, and it is named in full below.

## The acceptance example

One map, 19 × 14 (266 cells), authored through the editor's own gesture entry points wherever a
tool exists — `_beginToolGesture` / `_endToolGesture` with screen positions projected from known
cells, never by calling the modules underneath. Gate 3's ruling was that a workflow only a script
can drive is not the workflow being proved, so the run records which is which.

| Step | Driven by |
|---|---|
| create a map (New, 19 × 14) | **tool** |
| paint hex ground (266 cells, plus a hex line road) | **tool** |
| add sub-triangle detail (24 slots) | **tool** |
| sculpt a hill (+6.00) and a riverbed (−1.67) | **tool** |
| place water (14 river cells) | *script* — no water tool, and no water preview either |
| place an upright building | **tool** |
| place a bridge (deck 0.80, clearing 1.20 over water) | *script* — the Place tool anchors to terrain |
| undo and redo 100 strokes across tile, height and object edits | **tool** |
| save, reopen, export, instantiate | **tool** (Ctrl+S / Open / Ctrl+E) |

**Six of the eight authoring steps are reachable with a mouse.** The two that are not are the two
layers added after WMH-10B built the tool pattern — water and bridges — and for the same reason in
both cases: their items' Touches lists covered the layer, the format and the export, not the
controller. Water is the worse of the two, because the editor does not *preview* it either:
`_bakeAndDisplayDocument` builds a ground and an object preview, and `buildWater` is reached only
by `buildRuntime`, which the editor never calls. Authored water is invisible until it is exported.

### What survived the round trip

Every number below was written down before the save and re-read after reopening from disk in a
fresh session, with an import pass in between.

| | authored | after reopen |
|---|---|---|
| hill centre | 6.00 | 6.00 |
| riverbed centre | −1.67 | −1.67 |
| wet cells | 14 | 14 |
| objects | 2 | 2 |
| detail slots | 24 | 24 |
| bridge deck | 0.80 | 0.80 |
| clearance over water | 1.20 | 1.20 |
| baked texture | sha256 | **byte-identical re-bake** |

Appearance is checked as a hash rather than by eye: the bake is byte-deterministic
(`probe_bake_parity`), so re-baking a reopened map and getting the same file back is a stronger
claim than a screenshot comparison, and anything that perturbed the art would break it.

### The shipped scene, with the editor absent

Exported to `scenes/worldmap/generated/`, 34,568 bytes, then instantiated under a bare `Node3D`
with a `Camera3D` and nothing else — the editor scene **removed from the tree**, not merely
unused. The first run of this check captured the editor window around the map, which is exactly
the kind of evidence that proves nothing; the shots in `validation/hex/` are from the corrected
run.

- `Ground` + `Water` + `Objects/o000`, `Objects/o001`
- the bridge stands at **0.800** in the shipped scene, its authored deck height
- the building stands at its authored anchor
- the ground samples `res://assets/worldmap/regions/generated/…png` as an external resource — no
  embedded `Image`, the failure mode WMH-6 refuses

## Measured timings

The 103 × 77 lattice `WorldMapHexGrid.exactSquareLattices()` tops out at: **7,931 cells, 155 × 155
world units, a 2,480 × 2,480 px bake.** Medians of repeated runs, on the machine this cycle was
developed on (RTX 3060 laptop, Vulkan, Forward+).

### Editing the data is free

| operation | cost |
|---|---|
| paint stroke, 127 cells | 0.82 ms |
| sculpt stroke, 127 cells (294 vertices) | 3.21 ms |
| detail stroke, 127 slots | 0.76 ms |
| undo one stroke | 0.23 ms |

### Navigating is free

| operation | cost per mouse move |
|---|---|
| cursor pick over sculpted terrain (ray/terrain secant solve) | 0.081 ms |
| camera orbit | 0.002 ms |

A cursor pick on a full-size sculpted map costs eight hundredths of a millisecond. WMH-8's secant
refinement is not a performance concern at any map size this project will reach.

### Redrawing is not

| operation | ground only | with a detail layer |
|---|---|---|
| full bake, 7,931 cells | **179 ms** | **1,597 ms** |
| partial rebake, 1 cell | 4.9 ms | **221 ms** |
| partial rebake, 127 cells | 181 ms | **27,078 ms** |
| marking 127 dirty rects | 1.3 ms | 1.0 ms |
| full 2,480² texture upload | 3.2 ms | 3.2 ms |

## The finding: the incremental redraw is the slow path

Three things fall out of that table, and the third inverts the item's own premise.

**1. Sub-triangle detail dominates everything.** A detail layer makes a full bake 9× more
expensive and a 127-cell partial rebake **150×** more expensive. The cause is
`WorldMapBaker._maskToTriangle`, which builds a fresh masked copy of a 32 px frame by testing
every one of its 1,024 pixels barycentrically, in GDScript — **per slot, per cell, per composed
rect**. A radius-12 disc of detail is 469 cells × 6 slots = 2,814 masked images per full bake;
under per-cell dirty marking the same cells are re-masked once per overlapping rect, thousands of
times.

The mask depends only on the frame size and the slot index — **not on the tile**. Six masks per
frame size, computed once and reused, would turn the inner loop from a per-pixel barycentric test
into a blit. That is the fix, it is small, and it is not made here: this item touches its own
review and nothing else.

**2. "Partial" stops paying at about a hundred cells.** Even with no detail at all, recomposing
127 cells costs 181 ms against 179 ms to re-bake the entire 7,931-cell map. Past that size the
incremental path is *slower than starting over*. Marking is not the problem — 127 rects mark in
1.3 ms — it is that `flush()` clears and recomposes each rect separately, and each rect drags in a
padded neighbourhood of candidate cells. Marking the same 127 cells as **one** rect instead of 127
costs 1,171 ms with detail against 27,078; the union is 23× cheaper than the pieces.
`WorldMapEditorController._afterCellsEdited` marks per cell.

**3. The texture upload is not the problem, and never was.** 3.2 ms for the full 2,480² surface —
under 2% of even the ground-only full bake, and 0.01% of the detail partial rebake. WMH-13's brief
says to measure the implemented behaviour rather than report against the original plan's promise
of a partial upload; the measurement says that promise would have optimised the one part of the
pipeline that is already negligible. Godot 4 having no partial 2D upload costs this project
nothing.

## Deferred checks from the cycle, consolidated

Everything each item deferred to "does it read at the shipping framing" was re-checked on one map
in `validation/hex/`: hex ground and the hex line road, sub-triangle detail, a sculpted hill and
riverbed, water with its shoreline band, an upright building, and a bridge over the river. All
read as intended at pitch 60 and at a low grazing angle.

**One deferred check remains outstanding and cannot be discharged here:** WMH-10B's own — whether
sculpting, placing and detail painting *feel* right under a mouse, in a live editor session,
judged by the user. The gestures were decided in one item by one agent; nobody has yet used them.

## Open gaps, carried forward

None of these blocks the merge; each is named rather than left to be discovered.

- **The detail mask is rebuilt per composite** — the finding above. The largest single improvement
  available to this tool.
- **Dirty rects are never merged**, only absorbed when one encloses another, so a large stroke
  pays per cell. `_afterCellsEdited` could mark one bounding rect.
- **Water and bridges have no tool**, and water has no editor preview.
- **Water is not fogged** while the ground is (§18); `worldmap_prop.gdshader` is the project's
  existing answer to that shape.
- **Author → export needs an import pass** (Gate 2), unchanged: the standalone editor cannot run
  Godot's importer.
- **Relief is invisible at pitch 60** (Gate 3), unchanged. Water helped — a shoreline is a contour
  the eye reads — but a dry hill still reads flat.
- **Rectangle and Stamp are still square-only** on a hex document (§12).
- Two stale probes (`probe_catalogs`, `probe_validation`) fail to parse on a
  `WorldMapGroundUniforms.K_CLOUD_STRENGTH` that no longer exists. Pre-existing, unrelated.

## The merge call

**Merge `plan/worldmap-hex-authoring` into `main`.** 27 commits, one per plan item plus three gate
reviews and four small fixes. `main` has not moved since the branch left it, so this is a
fast-forward.

Branch audit, per the standing rule that unmerged work is never swept unexamined:

| branch | state | action |
|---|---|---|
| `plan/worldmap-hex-authoring` | this cycle, 27 commits ahead of `main` | **merge** |
| `claude/agitated-heyrovsky-f020df` | fully merged into `main`, nothing unique | safe to delete |
| `plan/hex-battle-migration` | **6 commits not on any other branch** — a live cycle | leave alone |

Two commits on this branch (`21e2aa9`, `3b7d16b`) belong to the hex battle plan rather than to
this cycle. They touch only `docs/plans/hex-battle-migration.md`, and the battle branch already
contains both, so merging carries no duplicate work and strands nothing.

## What this cycle built

A hex map editor: a lattice and picking that resolve to a hex, an overlay that draws the hex's own
silhouette, hex-aware brushes, a document lifecycle, a bake that composites overlapping hex frames,
an export that ships a gameplay scene, placed objects with never-reissued ids, smooth terrain on
the vertex lattice, one undo history across four kinds of edit, sub-triangle detail, tools that
reach all of it, authored water, and bridges with a clearance check.

The thing it does not yet have is a map anyone would want to look at, and that is an art question
this cycle deliberately never touched — `temp2_hex32_ground` is upscaled placeholder art carried
the whole way through, and every judgement about how the tool *reads* was made against it.
