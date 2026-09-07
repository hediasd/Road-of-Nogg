# World map hex authoring — Gate 2 findings

Run 2026-09-07, after WMH-5 (the document lifecycle, `6b55eee`), WMH-5B (hex baking, `f065d1f`)
and WMH-6 (scene export, `d4b6f4a`). Gate 2's job, per `docs/plans/worldmap-hex-authoring.md`:
decide whether an exported map is genuinely usable outside the editor before Phases 3 and 4 add
objects and terrain on top of that premise.

## Verdict: CONTINUE

Phase 3 opens as written. One finding — a real workflow break, not a blocker — see below.

## The question, answered

**Yes.** The user's own verdict, and it holds up against the sequence this gate is defined by: a
map authored, saved, reopened, exported and instantiated with the editor absent.

Run as one continuous chain on a **hex** map (15 × 11 cells, 23 × 23 units), not on the square
`temp2_authored` that WMH-6's probe uses — the committed square map has a bake that is already
imported, which is exactly the condition a freshly authored hex map does not meet, and routing
around that would have hidden the finding below.

| Step | Result |
|---|---|
| 1. Author a hex map through the editor | new `hex_flat` document, painted with a fill, a radius-3 disc and a hex line |
| 2. Save | source and bake both written; dirty flag cleared |
| 3. Reopen from disk | byte-identical to what was saved |
| 4. Export | **refused** — see the finding |
| 4′. Export, after an import pass | 2,454 bytes, no embedded `Image` |
| 5. Instantiate with the editor absent | root + `Ground (MeshInstance3D)`, sampling `res://assets/worldmap/regions/generated/…png` |

The exported map carries its region, layout, extent and source path as metadata, and its ground
samples the committed bake as an **external** dependency — 2,454 bytes of scene, against the
67,404 an embedded copy of a *64 × 64* image cost when WMH-6 measured that failure mode. Rendered
in a gameplay scene built from nothing but a `Node3D` and a `Camera3D`, touching no editor or
debug class at all.

## The finding: you cannot author and export in one standalone session

Step 4 fails on a freshly authored map, and the diagnosis is exact:

```
error: no importable bake at res://assets/…/_gate2_hexmap.png
ResourceLoader.exists(bake)  = false
FileAccess.file_exists(bake) = true
```

The PNG is on disk. Godot has not imported it, so it is not yet a loadable resource, so the
export refuses — correctly, because the only available fallback is embedding a runtime texture,
which is the megabyte-scale duplication WMH-6 exists to prevent. Inserting an import pass
(`godot --headless --import`) and retrying makes step 4 and step 5 succeed unchanged.

So the working sequence is **author → save → import → export**, and the import is a step the
editor cannot perform on its own: `EditorFileSystem` exists only inside the Godot editor, not in
a running game, which is what the editor scene is when launched standalone. Running the editor
from *inside* the Godot editor imports on window focus and hides this entirely; running it
standalone does not.

**This is a workflow break, not a correctness bug.** Nothing produces a wrong map — the refusal
is loud, names the path it wanted, and says what to do. But "author a map and export it" is the
one sentence describing what this tool is for, and today it takes a step the tool cannot take.

**What I would change, recorded for a later item rather than done here** (a gate touches only its
own review): the candidate real fix is to write the bake as a **native Godot resource** rather
than a PNG. `ResourceSaver.save()` writes a `.tres`/`.res` that `ResourceLoader` can read
immediately, with no import step at all, which would remove the break entirely. It is not a free
change: the baked PNG is also the committed region art, and `WORLDMAP_DESIGN.md` §4's filter and
mipmap behaviour comes from that PNG's *import settings* — which a native resource would have to
carry some other way, and which `probe_bake_parity` currently asserts. That is its own item's
worth of design, not a side fix. Until then the mitigation is documentation: `WORLDMAP_EDITOR.md`
§13 already states the precondition, and the export's own error message already names it.

The cheaper interim option, if the friction bites before that item is written: run the editor
scene from inside the Godot editor rather than standalone, where the import is automatic.

## What this gate did not re-litigate

- **The export's shape.** Root + Ground, metadata, no camera or environment: settled in WMH-6 and
  confirmed here by instantiating one. Unchanged.
- **Whether generated scenes should be committed.** WMH-6 measured `ResourceSaver.save()`
  assigning random resource ids per save, so a committed export would show a spurious diff every
  time. That decision stands.
- **Hex tool routing** (Rectangle and Stamp still call the square-only brush functions) — named in
  `WORLDMAP_EDITOR.md` §12, still open, and still not a Phase 3 blocker.

## Direction beyond this cycle

The user's stated next priority is **a mock of a hex map battle**, and they were explicit that it
is a **separate plan, not a re-cut of this one**. Phases 3 and 4 stay exactly as written; this
gate changes nothing about them.

Two observations worth carrying into that plan when it opens, both from what this gate handled:

- **The export already gives a battle most of what it needs to place units on hexes.** The root
  carries `worldmap_layout`, `worldmap_cells` and `worldmap_extent`, and `WorldMapHexGrid` — which
  lives outside the `editor/` package and is therefore importable by gameplay — turns those into
  cell centres. A battle does not need the editor to know where a hex is.
- **What it does not carry is per-cell data.** The exported scene holds a composed image, not a
  grid: nothing in it says which hexes are walkable. `WALKABLE` exists in the tileset ledger and
  is still read by nothing (`WORLDMAP_EDITOR.md` §2). `worldmap_source` points back at the
  authored JSON, so a battle can load the cells from there — but whether walkability should ride
  in the exported scene instead is a real question for that plan to answer, not this one.

## Next

Phase 3 opens: WMH-7 (the placed object layer), routed to Opus 5 / GPT Sol.
