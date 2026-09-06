# World map editor -- Gate 1 findings

Run 2026-09-06, after WME-1 (tile law, `c875149`), WME-2 (editor camera, `2be7e10`) and WME-3
(editor scene shell, `75f4ea0`), plus the follow-up fix (`a4dc459`) correcting two defects found
by actually launching the scene: the editor camera's own input handler never received real
mouse or keyboard events (it lives inside a `SubViewport` displayed through a plain
`TextureRect`, which never forwards them), and the two HUD panels overlapped the map instead of
sitting beside it. Gate 1's job, per `docs/plans/worldmap-editor.md`: decide whether this tool
is going the right direction before Phase B pays for a data model, a bake pipeline and brushes
built on top of it.

## Verdict: CONTINUE

Phase B opens as written in the cycle file. One finding changes what Phase C opens WITH -- see
"Phase C scope, revised" below -- but nothing in Phase B depends on the layer list, so it is
unaffected.

## The five questions, answered

**1. Does orbit actually help read the map, or does the baked light direction make a rotated
view more confusing than it is worth?**

Helps -- kept. The user's own answer, after actually flying it.

**2. Is the top-down ortho view the one you would really author in?**

No -- the answer was a **free orbited view**, not ortho and not the shipping game camera.
This does not change WME-8 or WME-9 as written: `WorldMapSurfacePick`'s own item description
already scopes it to solve picking correctly "at every framing and curvature the rig offers,"
not ortho-specifically, so a free-orbit authoring view is already inside that contract. What it
does change is emphasis -- when WME-8 lands, its deferred check should include a free-orbit
picking pass alongside the ortho and contract cases it already names, since free orbit is now
confirmed as a real authoring view rather than a secondary one. Ortho stays in the tool as a
precision option, not the primary view the rest of the design should assume.

**3. Did WME-1's re-anchoring make temp2 better or worse?**

Better, and this one has evidence beyond the user's own look: `probe_tile_law.gd` and
`probe_props.gd` both report all 9 of temp2's structures on tile centres under the 16 px grid.
Before WME-1 they snapped to 8 px centres, half of which sat on the boundary between two walk
tiles -- the exact defect `WORLDMAP_DESIGN.md` section 9 was written to remove, reintroduced by
the old per-region tile-pixel reading. Visually confirmed too, in the screenshot sent after the
layout fix (`screenshot_editor_layout.png`, not committed -- `debug/` is gitignored).

**4. Is the layer list right, before any of them cost anything?**

No -- REVISED. See "Phase C scope, revised" below; this is the one real finding of the gate.

**5. Is an in-engine editor still the answer now that one exists to hold?**

Not asked as a separate question this round, but the CONTINUE verdict on Phase B answers it:
this session found and fixed two real defects (dead camera input, overlapping panels) by
launching the actual scene and looking at real screenshots under the shipping shader --
exactly the round-trip that was the whole argument for building this in-engine rather than
adopting Tiled or LDtk. Nothing observed this round argues against that.

## Phase C scope, revised

The user's own words, verbatim: *"For now I only think the map builder should deal with ground
and overlay, can we add more as we go later???"*

Ground and overlay stay. Height, props, walkability, graph, lighting and annotations are
**deferred out of Phase C's opening wave** -- not cancelled, and not demoted in the outcome
either. They come back as their own items when there is a reason to build them, rather than as
one bundled wave opened together the moment Gate 2 passes.

**Acted on immediately, in this session, rather than left for Gate 2:**
`WorldMapEditorController.LAYERS` is trimmed from eight rows to two -- `ground` and `overlay` --
because the chrome was visible on screen right now and there was no reason to leave six
placeholder rows sitting in the HUD after being told they are not wanted yet. No probe needed
updating: `probe_editor_shell.gd` iterates `LAYERS`/`TOOLS` generically, which was the entire
point of WME-3 declaring layers as data rather than code, and it now reports "all 2 layers
select" instead of "all 8" with the same assertions otherwise unchanged.

**Recorded here for Gate 2, not acted on now:** `docs/plans/worldmap-editor.md`'s Phase C
section (WME-10 through WME-14) is frozen and this finding does not edit it. When Gate 2
re-cuts Phase C into its own file, that re-cut should open with **ground autotiling and the
overlay/road layer only** -- a slimmed WME-10 and WME-11 -- and move WME-12 (props), WME-13
(walkability) and whatever of WME-14's linter checks depend on them into later, separately
opened items rather than one bundled wave. The corner-lattice decision in WME-10 is unaffected
by narrowing the opening scope: ground and overlay need it exactly the same way the full set
would have.

## What this gate did not re-litigate

Elevation stays Phase D, blocked on art (flat top-down liftable tiles, cliff faces), per the
existing plan and per section 8's rejection of 2.5D ground. Nothing in this round's findings
touches that boundary.

## Next

Phase B opens: WME-4 (tileset import with stable identity) and WME-5 (tile data model and file
format), the two items the rest of the phase is built on.
