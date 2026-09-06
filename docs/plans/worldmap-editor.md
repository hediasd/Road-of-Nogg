# World map editor

Opened 2026-09-05. The world map renders; nothing authors it. `WorldMapGround` builds a single
`PlaneMesh` and the shader does one `texture()` lookup against a hand-painted region PNG, so
"tile" is a unit convention and not a data structure — there is no tile model, no layer model,
and no way to place anything. This programme builds the editor that produces regions, and it
does so under the shipping shader so what is authored is seen the way it will ship.

Three laws were fixed by the user on 2026-09-05 and are not open questions inside this file:

1. **An entity walks a 16 px tile, always.** One tile is one world unit. 8 px is *cel* — art
   detail, four to a tile, observable by nobody. `TILE_PIXELS` stops being a per-region
   property.
2. **Tile data is authoritative.** PNGs enter this project as *tilesets* only. There is no
   external map format and no external map editor.
3. **The editor is built here.** Tiled and LDtk were considered and rejected by the user:
   they do not serve the demands this map makes.

This is **not** a gameplay cycle. Travel, encounters and the party are not implemented here;
Phase D authors the graph they will later read, and stops there. It is also not a rendering
cycle for its own sake: every render change exists to let something be authored or judged.

## How this file is used

This is a **programme in four phases**, not one cycle. Phase A opens now as
`plan/worldmap-editor`. Phases B, C and D are authored here so the direction is visible and so
each phase can be argued with before it is paid for — but they are **provisional by
construction**. A cycle file freezes when execution starts, so a phase that changes direction
cannot edit itself; instead each gate re-cuts the next phase into its own cycle file.

**Four review gates punctuate the work at the user's instruction.** A gate is a real item with
a real commit, it runs alone in a quiet tree, and its job is to answer one question: *is this
tool going the right way?* Each gate ends in exactly one of three verdicts, recorded in its
commit body and its findings file:

- **CONTINUE** — the next phase is cut as written.
- **REVISE** — the next phase is re-cut with the changes the gate names, into a new file.
- **STOP** — the programme ends here and what exists is merged or reverted deliberately.

A gate that never returns REVISE is not doing its job. Gates are cheap, and they are placed
where changing direction is still cheap: before the data format exists, before the layers
multiply, and before elevation is allowed to invalidate art.

## Outcome

When the whole programme closes:

- A region is **authored, not painted**. Tile data is the source; the region PNG is a build
  artifact that no human edits.
- Tilesets **import from PNG** with stable identity, so re-exporting a sheet with a tile
  inserted cannot silently rewrite every map that used it.
- The scene the map is authored in is the scene the map is **rendered** in: the same shader,
  the same fog, the same clouds, the same sun. Painting a tile and judging it are one action.
- The camera **orbits, pans, zooms and drops to a top-down orthographic grid** for authoring,
  and returns to the shipping framing with one key — without the shipping framing's contract
  being loosened to allow it.
- Ground is painted at **cel resolution** over a **tile-resolution** world, and the two grids
  never negotiate at runtime because their ratio is a constant.
- Terrain **elevates on the tile-corner lattice**, so neighbouring cells adjust to a raised
  corner as a consequence of the data rather than as a rule somebody wrote.
- Roads, bridges, props, walkability and the travel graph are **separate authored layers**,
  and the colour-key structure extractor is retired.
- The editor **lints**: off-palette tiles, structures off tile centre, height steps it cannot
  render, and regions too small for the framing they are drawn for.

## Present-state facts an executing agent must not "fix"

- **§8's rejection of 2.5D ground stands for the existing art, and elevation does not
  overturn it.** Eleven approaches were built and rendered; per-tile extrusion — the obvious
  reading of "elevate a tile" — turned mountains into a staircase of cubes. It failed for an
  **art** reason: every object in the region PNG is drawn in oblique view with a top and a
  front, so lifting it geometrically double-counts depth. Phase D is legal only because it
  introduces flat top-down liftable tiles and a flag that refuses to raise anything else. Do
  not raise painted oblique art.

- **Yaw is pinned at 0 for the game camera and stays pinned.** A painted map has one baked
  light direction and upright icons; roads and settlements are composited into the region art
  precisely because yaw cannot move. WME-2 gives the *editor* an orbit. That orbit is an
  authoring aid for reading elevation and occlusion, it is off-contract by definition, and the
  scene says so on screen while it is off zero. Nothing about how the map *looks* may be
  judged from a rotated view, and `WorldMapCameraRig` is not loosened to provide it.

- **Baking to one contiguous texture is the decision, not a compatibility shim.** The
  alternative — a tile-index texture plus an atlas sampled live — was rejected here. §4 keeps
  three sampler uniforms bound to the same texture because nearest-with-no-mipmaps *is* the
  look and the far field still needs mips; an atlas cannot be mipmapped without bleeding
  across tile borders, and nearest-filtered at magnification it is one texel-rounding error
  from sampling its neighbour. Do not "optimise away" the bake.

- **The debug scene's drag-to-pan is deliberately unclamped**, unlike the shipping
  `panTo(focus, rect)`. An authoring tool must be able to look at the map's edge, which is
  exactly what the shipping clamp prevents. The `EDGES SHOW` readout is the feature. §1
  records a bug that the focus clamp *hid* by silently recentring; an editor that recentres
  on its own will hide the same class of error.

- **`gain` and `face` producing the same rectangle is a measured result.** 0.00 px at every
  pitch in the sketch, 0.00% worst aspect error across nine structures in `probe_props.gd`.
  Do not delete one as a duplicate while touching props.

- **`clampf(depth / denom, 0.1, 8.0)` has a floor of 0.1 on purpose.** Past the frame centre a
  vertical quad is magnified, not squashed. A floor of 1.0 looks like the obvious guard and
  silently leaves everything beyond mid-frame too tall.

- **The shadow mask lives in map-pixel space and must not move to screen space.** That is what
  makes shadows land on the art's pixel grid instead of crawling at arbitrary sub-pixel
  angles. Elevation makes the baker harder; it does not make screen space correct.

- **Fog is in the shader, never a `WorldEnvironment`, and it uses ground-plane forward
  distance rather than view-space depth** — they differ about 3x at pitch 60 — and it blends
  in gamma space. Both are deliberate. Anything new that fogs transcribes them.

- **The black bars down each side of every standing building are the art**, an outline drawn
  to read on a flat top-down sprite. Not a rendering defect.

- **302 components on `temp` is the finding, not a thresholding failure.** temp is dithered
  and no colour in it is exclusive to anything; tree-green and grass-green are one continuous
  population with no trough. This is why WME-12 authors props instead of detecting them, and
  why nobody should attempt a better threshold.

- **Moving a structure moves its record, not its sprite.** A structure's `x`/`y` feeds the
  sprite, its cast shadow, its silhouette and its lamp, three of them derived in map-pixel
  space from the same numbers. Relocating only the rendered quad leaves a building standing
  apart from its own shadow and its own light — a defect no probe catches, because both sides
  still agree with each other.

## Items

---

## Phase A — the law, and something to fly around in

Nothing can be authored until the grid means one thing and the camera can look at it. Phase A
deliberately ships no data model: it is the cheapest possible point at which the tool can be
looked at and abandoned.

### WME-1 — Make the walk tile a constant and re-anchor everything to it

**Model:** Opus 5 / GPT Sol

**Model rationale:** This changes a documented contract (§1 currently states the opposite),
reclassifies an existing region, and repairs a latent defect whose symptom is invisible. The
same divisor feeds prop anchoring, cloud scale and the map-pixel conversions, so the item has
to decide what each of them *meant* by "tile" rather than mechanically substitute a constant —
`WorldMapClouds` genuinely wants pixels-per-unit, which is now the same number for every
region and stops being a per-region lookup. Judgment, not transcription.

**Depends on:** nothing.

**Touches:**
- `src/presentation/worldmap/WorldMapGroundUniforms.gd`
- `src/presentation/worldmap/WorldMapRegionCatalog.gd`
- `src/presentation/worldmap/WorldMapProps.gd`
- `src/presentation/worldmap/WorldMapClouds.gd`
- `src/presentation/worldmap/WorldMapCloudCatalog.gd`
- `src/presentation/debug/WorldMapDebugController.gd`
- `data/worldmap/regions.json`
- `docs/WORLDMAP_DESIGN.md` §1, §9
- `debug/worldmap/probe_tile_law.gd` (new)

**End state:** `TILE_PIXELS = 16` and `CEL_PIXELS = 8` are constants, four cels to a tile. No
runtime path reads a per-region tile size. `WorldMapProps._standOnTiles` snaps to the 16 px
tile grid regardless of the grid a region's art was drawn on. §1 states the two-grid law and
what each grid owns. `regions.json` keeps the old value only as a legacy `GRID` marker on
painted regions.

**Implementation:** `temp2` is 248x176 px, which under this law is **15.5 x 11 walk tiles** —
not the 31x22 it declares. It is placeholder art and is **not re-cut**: it is marked a legacy
painted region drawn on the cel grid, and its declared tile dimensions are corrected to what
they are. Its nine structures currently snap to 8 px centres via `WorldMapProps.gd:435`, and
half of those centres are exactly the boundary between two walk tiles — the identical defect §9
was written to fix, reintroduced by the law. Re-anchoring will **visibly move buildings by up
to half a tile**. That is the correction, not a regression.

Move the *record*, never the sprite alone — see the present-state fact above.

**Risk:** Cloud scale on temp2 changes, because the cloud field's pixels-per-unit was reading
8 and now reads 16. Expect clouds at half their former apparent size over that region; confirm
against the clouds sketch rather than assuming either size is correct. A silent alternative
failure is some path still dividing by a stale per-region value — the probe greps for it.

**Validation:**
- Self-contained: `probe_tile_law.gd` asserts no runtime path reads a per-region tile size;
  every structure on every region anchors to a 16 px tile centre; temp still loads and renders.
- Deferred: temp2's buildings sit *in* tiles rather than on tile lines, and its clouds read at
  a plausible scale.

### WME-2 — An editor camera that orbits, pans, zooms and drops to a top-down grid

**Model:** Opus 5 / GPT Sol

**Model rationale:** The failure mode is silent in both directions. A rig that quietly clamps
or recentres hides map-edge errors the debug scene exists to show; a rig that leaks its
freedoms back into `WorldMapCameraRig` breaks a shipping contract that fog, props, the void
colour and the whole framing table depend on. It also has to reconcile orbit against art with
one baked light direction, which is a design judgement about what the orbit is *for* rather
than a feature to implement.

**Depends on:** WME-1.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapEditorCamera.gd` (new)
- `docs/WORLDMAP_DESIGN.md` §3 (an "editor views" subsection only)
- `debug/worldmap/probe_editor_camera.gd` (new)

**End state:** A separate rig, used by the editor scene and by nothing that ships. It provides:

| control | binding | note |
|---|---|---|
| orbit yaw | middle-drag / Q,E | free 360°, snaps to 45° with Shift |
| pitch | middle-drag vertical | 15°–89°, never past vertical |
| pan | right-drag / WASD | unclamped; may leave the region |
| zoom | wheel | dolly along view, not FOV |
| top-down ortho | Tab | true axis-aligned grid view for precision work |
| **snap to contract** | Space | yaw 0, the active framing preset, exactly what ships |
| frame region | F | fit the whole region |

`WorldMapCameraRig` is **not modified**. While yaw ≠ 0 or the projection is orthographic, the
scene displays an **OFF-CONTRACT** badge naming which freedom is active.

**Implementation:** Orbit is an authoring aid for reading elevation, occlusion and prop
placement — it is not a preview. The art has one baked light direction and upright icons, so a
rotated view is *wrong on purpose*; the badge exists so nobody judges a look from one or files
a bug against it. Pan stays unclamped for the reason the debug scene's pan is unclamped.

Zoom dollies rather than changing FOV: FOV is half of the framing contract's near-to-far ratio
`R`, and moving it silently changes the thing every framing preset was solved for.

Orbit is around a **focus point on the ground**, not around the camera, and that focus must be
raised by the curvature drop `k*d^2` at its own distance — otherwise the map slides under the
cursor as yaw changes, at an error that grows with distance from the camera.

**Risk:** Orbiting the camera while the sky quad is parented to it. The backdrop is a
camera-parented quad sized to the frustum and is off by default; if it is on, orbit must not
make it swim. Probe both states.

**Validation:**
- Self-contained: `probe_editor_camera.gd` asserts `WorldMapCameraRig`'s outputs are identical
  before and after the item; that Space restores the exact framing the preset specifies; and
  that the ground focus point is stable across a full 360° orbit at three curvature values.
- Deferred: orbit, pan and zoom feel controllable at speed; the OFF-CONTRACT badge is legible.

### WME-3 — The editor scene shell: modes, layers, and where input goes

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Multi-file with a fully stated end state and no boundary being moved. The
layer set, the mode set and the routing rule are all decided in this plan; what remains is a
new scene, a controller that owns mode state, and a HUD that mirrors an existing one. The
architectural risk sits in WME-2 and WME-5, not here.

**Depends on:** WME-2.

**Touches:**
- `scenes/debug/WorldMapEditorScene.tscn` (new)
- `src/presentation/worldmap/editor/WorldMapEditorController.gd` (new)
- `src/presentation/worldmap/editor/WorldMapEditorHud.gd` (new)
- `debug/worldmap/probe_editor_shell.gd` (new)

**End state:** A scene that loads a region, instantiates the ground, props, clouds and sun
exactly as the debug scene does, and adds an editor HUD with: an active-layer selector, a tool
selector, per-layer visibility and lock toggles, and the OFF-CONTRACT badge. Input hit-tests
**only the active layer**. The existing `WorldMapDebugScene` is untouched and keeps working.

**Implementation:** The layer list is fixed here even though most layers are empty until later
phases — ground, height, overlay, props, walkability, graph, lighting, annotations. An empty
layer shows as disabled rather than absent, so the shape of the tool is visible from the first
gate and the later phases add data rather than chrome.

Do not fork `WorldMapDebugController`. Reuse it for the parts that are identical (framing
presets, sun, clouds, shadow controls) and let the editor controller own only mode and layer
state; two copies of the framing controls will diverge.

**Risk:** Duplicating the debug scene wholesale, then having to maintain both. The probe
asserts the editor scene instantiates the same ground and prop nodes rather than new ones.

**Validation:**
- Self-contained: `probe_editor_shell.gd` loads the scene headless, switches every layer and
  every tool, and asserts input routing reaches only the active layer.
- Deferred: the HUD is readable and the mode you are in is obvious without hunting.

### WME-R1 — Gate 1: is this the right tool to be building?

**Model:** Opus 5 / GPT Sol

**Model rationale:** A judgement, and the only kind of item that is allowed to end the
programme. It weighs an ergonomic experience against a plan and decides whether the next phase
is paid for.

**Depends on:** WME-1, WME-2, WME-3.

**Touches:**
- `docs/plans/reviews/worldmap-editor-gate-1.md` (new)
- `debug/worldmap/validation/gate1/` (new)

**End state:** A findings file carrying a verdict of CONTINUE, REVISE or STOP, with the
evidence for it.

**Implementation:** Run the editor. Fly the camera. Answer these, in writing:

1. Does orbit actually help read the map, or does the baked light direction make every rotated
   view useless? *If useless, orbit is deleted rather than kept as a trap.*
2. Is the top-down ortho view the one you would really author in? If it is, the shipping
   framing is a preview and the tool should be built around ortho — which changes WME-8's
   picking and WME-9's brushes materially.
3. Did WME-1's re-anchoring make temp2 better or worse? A law that makes the only real map
   look worse is a law worth re-examining before anything is authored under it.
4. Is the layer list right, before any of them cost anything?
5. Is an in-engine editor still the answer now that one exists to hold?

**Risk:** Rubber-stamping. A gate that returns CONTINUE without naming at least one thing it
would change is evidence the gate was not run.

**Validation:**
- Deferred: this item *is* a deferred check. Quiet tree, alone.

---

## Phase B — data, bake, and the ground editing loop

Provisional until Gate 1. This is the phase that makes the tool real, and the phase whose
decisions are hardest to reverse: an identity scheme and a file format outlive everything
around them.

### WME-4 — Import tilesets from PNG, with identity that survives re-export

**Model:** Opus 5 / GPT Sol

**Model rationale:** The trap here corrupts data silently and unrecoverably, which is the
signature of an architectural item. Positional tile ids mean inserting one tile into a sheet
renumbers every map that referenced it, with no error at any layer. Choosing between a content
hash and a committed id map, and defining what a re-import reports, is a boundary decision
that every later item inherits.

**Depends on:** WME-3 (or Gate 1's re-cut).

**Touches:**
- `src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd` (new)
- `data/worldmap/tilesets.json` (new)
- `assets/worldmap/tilesets/` (new)
- `debug/worldmap/probe_tileset_ids.gd` (new)
- `docs/WORLDMAP_EDITOR.md` (new)

**End state:** A tileset is a PNG plus a descriptor. Per set: grid (`tile` or `cel`), palette,
source path. Per tile: **stable id**, name, terrain class, default walkability, autotile role,
variant group, and a `liftable` flag reserved for Phase D. Re-importing a sheet reports
`added` / `moved` / `changed` / `removed` per tile and never renumbers.

**Implementation:** Identity is a content hash of the tile's pixels, with an explicit
`id -> cell` map committed beside the sheet that is only ever appended to. Hash alone cannot
distinguish two identical tiles that mean different things; the map alone cannot survive a
re-cut sheet. Both, and the importer reconciles them.

Palette validation belongs **here and only here**. The ground shader snaps shadows to a
16-entry `palette[]` uniform, and the backdrop recolour was built so a sky cannot drift
off-palette. Validate a tileset against its region palette once, at import, and no brush stroke
can ever produce an illegal colour.

`liftable` is authored now and unused until Phase D, because retrofitting a flag onto tiles
already drawn means revisiting every sheet.

**Risk:** A hash collision, or an artist re-exporting a sheet with a one-pixel change and
seeing every tile reported as `changed`. Report, do not auto-resolve.

**Validation:**
- Self-contained: `probe_tileset_ids.gd` imports a sheet, inserts a tile, re-imports, and
  asserts every pre-existing id is unchanged and the report names the insertion.
- Deferred: none.

### WME-5 — The tile data model and its file format

**Model:** Opus 5 / GPT Sol

**Model rationale:** A file format is permanent in a way code is not, and this one has to
survive several agent sessions sharing one working tree — which makes diffability and merge
behaviour a correctness property, not a preference. The layer set, coordinate spaces and
versioning scheme are all boundaries later items build directly on.

**Depends on:** WME-4.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapTileData.gd` (new)
- `data/worldmap/authored/` (new)
- `src/presentation/worldmap/WorldMapRegionCatalog.gd`
- `data/worldmap/regions.json`
- `docs/WORLDMAP_EDITOR.md`
- `debug/worldmap/probe_tile_format.gd` (new)

**End state:** An authored region is a text file carrying `FORMAT_VERSION`, region metadata,
and one block per layer. A region entry in `regions.json` declares `KIND: painted | authored`;
painted regions keep today's behaviour untouched, authored regions load tile data and their
`TEXTURE` becomes a generated path.

**Implementation:** Deterministic key order and per-layer chunking, because several sessions
share one tree and an unstable or monolithic serialisation produces conflicts that are not
real disagreements. RLE the ground and cel layers; leave sparse layers (props, graph) as lists.

**The baked PNG is a build artifact.** Treat it as generated: never hand-edited, and
regenerable from data alone. Whether it is committed is a repository-hygiene call recorded here
and not left to each session to decide — commit it, so a fresh checkout renders without a bake
step, and let the linter flag one that disagrees with its source.

`FORMAT_VERSION` and a migration hook exist from the first commit. They are nearly free now
and impossible to add later.

**Risk:** A format that cannot express something Phase D needs, forcing a migration before
anything has shipped. Reserve the height layer's shape now even though it stays empty.

**Validation:**
- Self-contained: `probe_tile_format.gd` round-trips a region through save and load and
  asserts identical output; asserts a painted region's load path is unchanged.
- Deferred: none.

### WME-6 — Bake tile data into the region texture

**Model:** Opus 5 / GPT Sol

**Model rationale:** This is the item that decides whether the whole downstream stack keeps
working for free. It has to reproduce, from composed tiles, a texture indistinguishable to
fog, curvature, palette-snapped shadows, cloud shadows, the void substitution and three filter
modes — none of which can be told it was not painted. Getting the invalidation model wrong is
the difference between a usable tool and an unusable one, and it cannot be bolted on.

**Depends on:** WME-5.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapBaker.gd` (new)
- `src/presentation/worldmap/WorldMapGround.gd`
- `debug/worldmap/probe_bake_parity.gd` (new)
- `docs/WORLDMAP_EDITOR.md`

**End state:** Tile data composes into a single region texture at the region's true pixel size,
uploaded to the same sampler the painted path uses. Editing a tile rebakes **only the affected
rect** and re-uploads only that region of the texture. A bake is deterministic: the same data
produces the same bytes.

**Implementation:** The dirty model is a rect set, not a boolean, and it cascades — a ground
edit dirties the cast-shadow mask, the ground patch and the cloud-shadow layer, all of which
are CPU-baked. Track what each edit invalidates explicitly; a single global "something changed"
flag rebakes everything on every stroke and the tool dies at full region size.

Import textures generated by the bake with **nearest filtering and mipmaps on**, matching the
region import settings §4 specifies. Godot's importer defaults to the exact opposite.

**Risk:** Cel-grade tiles landing half a texel off and shimmering under the nearest sampler.
The parity probe compares a bake against a reference composition pixel-for-pixel rather than
by eye.

**Validation:**
- Self-contained: `probe_bake_parity.gd` bakes a known tile layout twice and asserts identical
  bytes; asserts a partial rebake equals a full rebake; asserts generated import flags.
- Deferred: an authored region renders with the same sparkle and fog as a painted one.

### WME-7 — Undo and redo, at stroke granularity

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A single new file implementing a well-understood pattern against a data
model that already exists, with a stated end state. It is foundational rather than difficult —
the reason it appears this early is scheduling, not complexity.

**Depends on:** WME-5.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapEditHistory.gd` (new)
- `src/presentation/worldmap/editor/WorldMapEditorController.gd`
- `debug/worldmap/probe_edit_history.gd` (new)

**End state:** Every mutation goes through a command. A drag coalesces into **one** undo entry,
not one per tile. Undo and redo restore tile data and trigger the same dirty-rect invalidation
a forward edit does. Depth is bounded and configurable.

**Implementation:** Commands store the *delta*, not a snapshot of the region — a full-region
snapshot per stroke is unaffordable at real region sizes. Coalescing opens on press and closes
on release, so a tool that edits without a release (flood fill) closes its own command.

Undo must invalidate exactly what the forward edit did. An undo that skips the shadow-mask
rebake leaves a shadow for a building that is no longer there, and nothing reports it.

**Risk:** A command that captures a reference rather than a copy, so undoing mutates the
history. The probe undoes a hundred randomised strokes and asserts the data equals its
starting state exactly.

**Validation:**
- Self-contained: `probe_edit_history.gd` — randomised stroke/undo/redo fuzz to an identical
  round trip, and coalescing asserted at one entry per drag.
- Deferred: none.

### WME-8 — Surface picking and the grid overlay

**Model:** Opus 5 / GPT Sol

**Model rationale:** The maths is the kind that produces a plausible wrong answer. Intersecting
the ray with `y = 0` looks right near the camera and drifts with distance because the ground is
quadratically curved, and the same code must later accept a height field without being
rewritten. Folding the overlay into the ground shader rather than a second pass is a boundary
call about where the single source of vertex displacement lives.

**Depends on:** WME-6.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapSurfacePick.gd` (new)
- `assets/shaders/worldmap_ground.gdshader`
- `src/presentation/worldmap/WorldMapGroundUniforms.gd`
- `debug/worldmap/probe_pick_accuracy.gd` (new)

**End state:** Screen position resolves to a tile and a cel by raycasting the **displaced**
surface, correct at every framing and curvature the rig offers. A grid overlay and a cursor
highlight are drawn on that surface: tile lines solid, cel lines faint and visible only while a
cel-grade tool is active.

**Implementation:** The overlay goes into the ground shader behind a `grid_mode` uniform that
defaults to 0, so the shipping path is untouched and there is **exactly one** vertex
displacement in the project. The alternative — a second shader transcribing the displacement —
is the prop-shader fog situation again, and that one is documented as needing manual
synchronisation forever. One displacement is worth the shared file.

Solve the ray against the curve rather than iterating: the drop is `k*d^2`, so the intersection
is a quadratic with a closed form. The commit that replaced an estimated curve drop with an
exact solve already established that estimating this overshoots.

Structure it so the height field is a second term added later, not a rewrite.

**Risk:** Picking a billboarded prop's upper rows and resolving to the tile behind it — a
building leans toward the camera, so its top is nearer than its base. Props resolve to their
base tile explicitly.

**Validation:**
- Self-contained: `probe_pick_accuracy.gd` picks a grid of screen points at every framing
  preset and three curvature values, asserting the recovered tile matches a forward projection
  to within zero tiles.
- Deferred: the grid reads clearly at pitch 60 without shimmering, and the cursor sits on the
  tile under the mouse at the far edge of the frame.

### WME-9 — Ground brushes

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A defined list of tools over a data model, a history and a picker that all
exist by now. The judgement — that scatter must be seeded, that cel and tile brushes are
distinct — is made in this plan.

**Depends on:** WME-7, WME-8.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapBrushes.gd` (new)
- `src/presentation/worldmap/editor/WorldMapEditorController.gd`
- `src/presentation/worldmap/editor/WorldMapEditorHud.gd`
- `debug/worldmap/probe_brushes.gd` (new)

**End state:** Point, rectangle, line, flood fill, eyedropper, multi-tile stamp,
random-from-set, and replace-all-of-kind. Each declares whether it works on the tile or the cel
grid; a cel brush cannot write anything an entity observes.

**Implementation:** Random-from-set draws from a **stored seed** on the region, so re-baking a
region reproduces it exactly — the same discipline the golden-ratio cloud scatter already
follows. A scatter tool that reseeds from the system clock makes a region unreproducible and
its bake non-deterministic, which quietly breaks WME-6's guarantee.

Flood fill is bounded by the region rect and by terrain class, and it is one undo entry.

**Risk:** A cel brush being allowed to set walkability through a shared code path. The probe
asserts the tile layer is unchanged after every cel-grade operation.

**Validation:**
- Self-contained: `probe_brushes.gd` exercises every tool headless, asserts one history entry
  per operation, and asserts cel operations leave tile-grade layers untouched.
- Deferred: brushes feel responsive on a full-size region.

### WME-R2 — Gate 2: can a region actually be authored?

**Model:** Opus 5 / GPT Sol

**Model rationale:** Judgement against a working tool, with the authority to re-cut or end the
programme. The question it answers — whether authoring under the shipping shader is worth what
it cost — is the premise the remaining two phases rest on.

**Depends on:** WME-9.

**Touches:**
- `docs/plans/reviews/worldmap-editor-gate-2.md` (new)
- `debug/worldmap/validation/gate2/` (new)
- `data/worldmap/authored/` (the trial region only)

**End state:** A findings file with a verdict, and a **real region authored end to end** as its
evidence — replacing temp2 is the natural target: small, seven colours, already understood.

**Implementation:** Author it. Then answer:

1. How long did a region take, and does that scale to a 155-tile region the framing actually
   wants? If not, which tool is the bottleneck?
2. Does the authored region hold up against the painted one under fog, clouds and the day
   cycle — the thing building in-engine was supposed to buy?
3. Is the file format surviving contact? Check a real diff of a real edit.
4. Is the dirty-rect model fast enough, measured, at full region size rather than at temp2's?
5. Has anything about the two-grid law been awkward in practice?
6. **Is elevation still wanted?** Phase D is the expensive one and the one that can invalidate
   art. If the flat authored map already reads well, saying so here saves the most money this
   programme can save.

**Risk:** Authoring a trial region that is too small to expose the scaling problem. The gate
must extrapolate from measured timings, not from feel on a 16-tile map.

**Validation:**
- Deferred: this item *is* a deferred check. Quiet tree, alone.

---

## Phase C — layers

Provisional until Gate 2. Ground alone is not a map; this phase adds everything else that is
authored, and retires the extractor that was always a bootstrap.

### WME-10 — Autotiling on the corner lattice

**Model:** Opus 5 / GPT Sol

**Model rationale:** Choosing the lattice is the unifying architectural decision of the whole
programme — terrain transitions and elevation are the same adjacency problem, and solving them
on different lattices means maintaining two systems that disagree at every diagonal forever.
The decision is made here and Phase D inherits it.

**Depends on:** WME-9 (or Gate 2's re-cut).

**Touches:**
- `src/presentation/worldmap/editor/WorldMapAutotile.gd` (new)
- `src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd`
- `data/worldmap/tilesets.json`
- `debug/worldmap/probe_autotile.gd` (new)
- `docs/WORLDMAP_EDITOR.md`

**End state:** Painting a terrain resolves its own edges and its neighbours' against the
**corner** lattice. A tileset declares which corner combinations it supplies; an unsupplied
combination is reported by the linter rather than silently drawn as a hole.

**Implementation:** Corner-based, because elevation is a corner property and the two must agree
— that agreement is the reason to prefer it over a cell bitmask, not aesthetics. Resolution is
a pure function of the corner state, so it is recomputed rather than stored, and a re-import
that adds transition tiles improves existing maps without touching their data.

**Risk:** A 4-corner scheme with N terrains needing an unbuildable number of tiles. Cap the
terrains that may meet at one corner and have the linter enforce it.

**Validation:**
- Self-contained: `probe_autotile.gd` asserts every corner combination resolves or is reported;
  asserts resolution is a pure function by recomputing a region twice.
- Deferred: transitions read as intentional art rather than as a seam.

### WME-11 — The overlay layer: roads, paths and bridges

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A new layer that reuses the autotiler, the history and the brushes, with a
stated end state. Its one design decision — that overlay geometry and graph edges are authored
together and stored separately — is made in this plan.

**Depends on:** WME-10.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapOverlayLayer.gd` (new)
- `src/presentation/worldmap/editor/WorldMapTileData.gd`
- `src/presentation/worldmap/editor/WorldMapBaker.gd`
- `debug/worldmap/probe_overlay_layer.gd` (new)

**End state:** A cel-grade layer drawn over the ground and composited into the same bake, with
its own autotile sets for roads and paths. Drawing a road emits a **provisional graph edge**
alongside its pixels, held until WME-18 gives it somewhere to live.

**Implementation:** Roads and bridges are graph edges wearing a costume. Author the visual and
capture the topology in one action, or the two will be drawn twice and disagree. A bridge is
distinguished from a road by crossing a tile whose terrain is impassable — detect and record
that at authoring time, when the intent is known.

**Risk:** Overlay compositing into the bake changing the ground's palette. Validate against the
region palette on composite, not only on import.

**Validation:**
- Self-contained: `probe_overlay_layer.gd` asserts overlay composites within palette and that
  road strokes emit connected provisional edges.
- Deferred: roads read as roads at the shipping framing.

### WME-12 — Author props, and retire the extractor

**Model:** Opus 5 / GPT Sol

**Model rationale:** This moves a boundary that §9 already identified and deferred: props stop
being *inferred* from ground pixels and start being *declared*. Everything downstream of
extraction — anchoring, the atlas, cast shadows, silhouettes, lamps — must keep working while
its input changes shape, and the failure mode where a record and its mask still agree with each
other but both moved is explicitly called out in §9 as one no probe catches.

**Depends on:** WME-11.

**Touches:**
- `src/presentation/worldmap/WorldMapProps.gd`
- `src/presentation/worldmap/editor/WorldMapPropLayer.gd` (new)
- `src/presentation/worldmap/editor/WorldMapTileData.gd`
- `docs/WORLDMAP_DESIGN.md` §9
- `debug/worldmap/probe_authored_props.gd` (new)

**End state:** An authored region's props come from the prop layer: a placed instance with a
tileset reference, a tile position and a lamp flag. The colour-key extractor survives **only**
as a one-shot migration path for painted regions, and §9 records that it is no longer the
pipeline. Ground is painted complete underneath a prop, so the ground-patch guesswork
disappears.

**Implementation:** §9's own conclusion, finally paid for: *the answer is to author it, not
detect it.* Trees become possible for the first time — extraction could never separate
tree-green from grass-green, and placement does not have to.

Placement anchors to the tile centre through the **same** code path WME-1 fixed. Do not add a
second anchoring rule for authored props; that is how a record and its shadow drift apart.

**Risk:** Authored and extracted props coexisting on one region with two anchoring rules. A
region is one or the other, asserted at load.

**Validation:**
- Self-contained: `probe_authored_props.gd` asserts an authored prop's sprite, shadow,
  silhouette and lamp all derive from one record; asserts painted regions still extract 9 of 9
  on temp2's migration snapshot.
- Deferred: an authored prop is indistinguishable from an extracted one under the day cycle.

### WME-13 — Walkability

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** One tile-grade layer with defaults inherited from the tileset, a paint
tool that already exists, and an overlay visualisation. Fully specified.

**Depends on:** WME-12.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapWalkLayer.gd` (new)
- `src/presentation/worldmap/editor/WorldMapTileData.gd`
- `assets/shaders/worldmap_ground.gdshader`
- `debug/worldmap/probe_walk_layer.gd` (new)

**End state:** A tile-grade layer of walkability classes, defaulted from the tile's terrain and
overridable per tile, with a colour-coded overlay behind the same `grid_mode` uniform. Cels
cannot write it.

**Implementation:** Tile grade only. Cel-grade walkability quadruples pathing cost for detail
no entity can stand on, and the party sprite is drawn at fixed screen size and is not really
*in* the scene to begin with.

**Risk:** Silent divergence between a tile's terrain and its overridden class after a tileset
re-import. The linter reports overrides whose underlying terrain changed.

**Validation:**
- Self-contained: `probe_walk_layer.gd` asserts defaults inherit, overrides persist across a
  re-import, and cel operations cannot write the layer.
- Deferred: the overlay is readable over the art.

### WME-14 — The editor as linter

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A defined list of checks against data models that all exist, reported
through a HUD panel. Each check is individually simple; the value is in having them, not in
devising them.

**Depends on:** WME-13.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapLinter.gd` (new)
- `src/presentation/worldmap/editor/WorldMapEditorHud.gd`
- `debug/worldmap/probe_linter.gd` (new)
- `docs/WORLDMAP_EDITOR.md`

**End state:** A panel listing live findings, each clickable to focus the offending tile:
off-palette tiles, tile size mismatches, structures not on a tile centre, unresolved autotile
combinations, orphan props, doors with no interior, walkability overrides whose terrain
changed, a baked PNG that disagrees with its source, and **region too small for its intended
framing**.

**Implementation:** The framing check is the one worth building carefully, because it catches a
problem *while art is being drawn* rather than after: §3 gives
`region_width_in_tiles >= tiles_across_bottom * R`, about 155 tiles at the reference framing
against temp's 48. Report the number the region needs for the framing it declares.

**Risk:** A linter noisy enough to be ignored. Severities, and off-palette is an error while
region-too-small is a warning.

**Validation:**
- Self-contained: `probe_linter.gd` constructs a region violating each rule and asserts exactly
  the expected findings.
- Deferred: none.

### WME-R3 — Gate 3: are the layers right, and is elevation still worth it?

**Model:** Opus 5 / GPT Sol

**Model rationale:** The last gate before the expensive, art-invalidating phase, and the one
with the strongest reason to return STOP.

**Depends on:** WME-14.

**Touches:**
- `docs/plans/reviews/worldmap-editor-gate-3.md` (new)
- `debug/worldmap/validation/gate3/` (new)

**End state:** A verdict, with a full multi-layer region as evidence.

**Implementation:** Answer:

1. Is switching layers and tools fluent, or is the mode model in the way?
2. Did retiring the extractor cost anything that was not obvious?
3. Is the linter catching real problems, and is anyone reading it?
4. **Does the flat authored map already look the way the game should look?** §8 rejected 2.5D
   on evidence and Phase D is a deliberate reopening. If the answer here is yes, returning STOP
   is the correct and cheapest outcome, and the programme ends having delivered an editor.
5. If elevation continues: which tiles will be redrawn flat top-down, and who draws them? Phase
   D is blocked on art that does not exist yet, and that is a scheduling fact, not a risk.

**Risk:** Continuing to Phase D out of momentum. This gate exists specifically to make stopping
respectable.

**Validation:**
- Deferred: this item *is* a deferred check. Quiet tree, alone.

---

## Phase D — elevation, and the graph

Provisional until Gate 3, and **blocked on art** that does not exist: flat top-down liftable
tiles and cliff faces. Do not open this phase without them.

### WME-15 — The corner height lattice

**Model:** Opus 5 / GPT Sol

**Model rationale:** Y is already occupied by curvature, and this adds a second displacement
term that every dependent system must agree with. The quantisation choice determines whether
cliff-versus-slope is decidable at all, which determines whether the rest of the phase is
buildable.

**Depends on:** WME-14 (or Gate 3's re-cut).

**Touches:**
- `src/presentation/worldmap/editor/WorldMapHeightField.gd` (new)
- `src/presentation/worldmap/editor/WorldMapTileData.gd`
- `src/presentation/worldmap/WorldMapGround.gd`
- `assets/shaders/worldmap_ground.gdshader`
- `debug/worldmap/probe_height_field.gd` (new)

**End state:** A `(w+1) x (h+1)` lattice of quantised corner heights. A cell's form — flat,
slope, ramp, cliff — is derived from its four corners and never stored. The ground mesh
displaces to it, composed with curvature in a defined order.

**Implementation:** Integer or half-unit steps, never continuous: continuous heights make
cliff-versus-slope undecidable, and undecidable means no face tile can be chosen and no
walkability computed. Raise a corner and the four cells sharing it adjust — that is the whole
reason the lattice is corners, and it is what makes "surrounding tiles adjust" a consequence
of the data rather than a rule somebody maintains.

The plane is already subdivided 64x64 for curvature; height needs the mesh resolution to match
the **tile** grid instead, which is a real mesh change and not a uniform.

Curvature is applied per point from that point's own distance because the ground *is* the
curved surface. Height is applied first, in region space, then curvature. Reversing them curves
the heights.

**Risk:** Mesh resolution changing under a curvature value tuned at 64 subdivisions. Re-verify
curvature smoothness at the new resolution at `k = 0.02`.

**Validation:**
- Self-contained: `probe_height_field.gd` asserts corner edits move exactly four cells; asserts
  a flat lattice renders identically to the pre-item ground.
- Deferred: a raised region reads as terrain rather than as a staircase.

### WME-16 — Cliffs, skirts, and the liftable flag

**Model:** Opus 5 / GPT Sol

**Model rationale:** This is where the plane stops being a plane, and it is the specific
failure §8 documented. It requires geometry a heightfield cannot express, a texture strategy a
planar projection cannot supply, and an enforcement rule preventing oblique art from being
lifted — three coupled decisions with one shared failure mode.

**Depends on:** WME-15.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapCliffMesh.gd` (new)
- `src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd`
- `assets/shaders/worldmap_ground.gdshader`
- `debug/worldmap/probe_cliffs.gd` (new)
- `docs/WORLDMAP_DESIGN.md` §8 (an addendum recording what changed, not a deletion)

**End state:** Where a corner step exceeds the cliff threshold, a skirt strip is generated and
textured with dedicated cliff-face tiles. The editor **refuses to raise a tile whose tileset
entry is not `liftable`**, and says why.

**Implementation:** A planar-projected texture smears vertically down a steep face — this is
not fixable with filtering, and it is why cliff faces are their own tiles rather than the
ground's texture stretched. §8 is amended, not deleted: its rejection was correct for oblique
art and remains the reason the `liftable` gate exists.

**Risk:** Reintroducing the staircase of cubes. The gate on `liftable` is the control; the
probe asserts no non-liftable tile can be raised through any code path.

**Validation:**
- Self-contained: `probe_cliffs.gd` asserts skirts generate at every step magnitude, and that
  raising a non-liftable tile fails loudly.
- Deferred: a cliff reads as a cliff at the shipping framing, judged from yaw 0 only.

### WME-17 — Make everything sample the height field

**Model:** Opus 5 / GPT Sol

**Model rationale:** The cascade item, and the one where a missed consumer produces a defect
that looks like an art problem. Props, cast shadows, lamps, cloud shadows and picking each
assume `y = 0` today, and §9 already records that a prop and its shadow drifting apart is a
failure both sides agree on and no probe catches.

**Depends on:** WME-16.

**Touches:**
- `src/presentation/worldmap/WorldMapProps.gd`
- `src/presentation/worldmap/WorldMapShadowMask.gd`
- `src/presentation/worldmap/WorldMapCloudShadows.gd`
- `src/presentation/worldmap/editor/WorldMapSurfacePick.gd`
- `assets/shaders/worldmap_prop.gdshader`
- `debug/worldmap/probe_height_cascade.gd` (new)

**End state:** Every consumer samples the height field at its base: a prop stands on its tile's
height, its cast shadow and lamp land at that height, cloud shadows fall on raised terrain, and
picking resolves against the displaced surface. Terrain self-shadows.

**Implementation:** Curvature must **carry** a standing object, not deform it — the whole quad
takes the drop belonging to its base. Height behaves identically: one sample at the base, not
per vertex.

The shadow mask stays in map-pixel space. Height makes the baker harder; it does not make
screen space correct.

**Risk:** The cascade being incomplete. The probe enumerates every consumer of a ground
position and asserts each one moved.

**Validation:**
- Self-contained: `probe_height_cascade.gd` raises one tile and asserts the prop, its shadow,
  its lamp, the cloud shadow and the pick result all moved by the same amount.
- Deferred: nothing floats or sinks anywhere on a fully elevated region.

### WME-18 — The travel graph layer

**Model:** Opus 5 / GPT Sol

**Model rationale:** The first authored data the *simulation* will consume rather than the
renderer, so its shape is a boundary between presentation and the headless layers `AGENTS.md`
keeps separate. It also has to adopt the provisional edges WME-11 has been emitting.

**Depends on:** WME-17.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapGraphLayer.gd` (new)
- `src/presentation/worldmap/editor/WorldMapTileData.gd`
- `data/worldmap/authored/`
- `debug/worldmap/probe_graph_layer.gd` (new)
- `docs/WORLDMAP_EDITOR.md`

**End state:** Nodes (settlements, sites, region entrances), edges with travel cost, encounter
zones and spawn points, authored on the map and stored as graph data. WME-11's provisional road
edges are adopted here. Entrances on adjacent regions are checked for correspondence.

**Implementation:** Graph records carry **deterministic ids**, per `AGENTS.md` — never
`get_instance_id()` — because quests, encounters and save data will reference them and editing
a map must not renumber anything.

Store the graph so a headless consumer can read it without touching presentation. This item
authors and validates; it does not implement travel.

**Risk:** Designing travel semantics here by accident. Cost is a number the editor stores; what
it means is not decided in this cycle.

**Validation:**
- Self-contained: `probe_graph_layer.gd` asserts ids are stable across an edit, that adopted
  road edges match their overlay, and that the graph parses without presentation loaded.
- Deferred: none.

### WME-19 — Ergonomics

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A batch of independent, individually small features over subsystems that
all exist, with a stated list. Grouped because each is too small to dispatch alone and they
share the HUD.

**Depends on:** WME-18.

**Touches:**
- `src/presentation/worldmap/editor/WorldMapEditorHud.gd`
- `src/presentation/worldmap/editor/WorldMapEditorController.gd`
- `src/presentation/worldmap/editor/WorldMapMinimap.gd` (new)
- `debug/worldmap/probe_editor_ergonomics.gd` (new)

**End state:** Minimap with click-to-navigate; copy/paste of a selection carrying heights and
props; autosave with crash recovery; neighbouring-region edge context; and a reference-sprite
toggle for judging scale.

**Implementation:** The minimap is not a luxury: at the shipping framing about 53 tiles are
visible across the bottom of a region the framing check wants to be 155 wide, so most of the
map is off screen at all times.

The reference sprite exists because party sprites are drawn at **fixed screen size**, not as
world-space billboards, so nothing else in the scene gives an honest sense of scale.

**Risk:** Autosave writing over an authored region during a crash. Autosave writes beside the
source and is promoted explicitly, never in place.

**Validation:**
- Self-contained: `probe_editor_ergonomics.gd` asserts copy/paste round-trips heights and props
  and that autosave never writes the source path.
- Deferred: navigation on a full-size region is comfortable.

### WME-20 — Write down what was decided

**Model:** Opus 5 / GPT Sol

**Model rationale:** This records contracts, and a contract recorded imprecisely is worse than
one not recorded. It must reconcile an amended §8, a rewritten §1, and a new authoring document
against what the code actually ended up doing.

**Depends on:** WME-19.

**Touches:**
- `docs/WORLDMAP_EDITOR.md`
- `docs/WORLDMAP_DESIGN.md` §1, §3, §8, §9, §13 (new)
- `docs/LEARNINGS.md`
- `docs/README.md`

**End state:** `WORLDMAP_EDITOR.md` is the authoring contract: the two-grid law, the file
format, tileset identity, the layer set, the bake, and the gates' verdicts.
`WORLDMAP_DESIGN.md` gains §13 for the editor's rendering additions, and §1, §3, §8 and §9 are
corrected where this programme changed them.

**Implementation:** Record what was *measured*, in the register the existing document uses —
conclusions and contracts, with the numbers that forced them. Any gate that returned REVISE has
a finding worth keeping; carry it here rather than leaving it in a review file nobody rereads.

**Risk:** Documenting the plan instead of the outcome. Write this last, from the commits.

**Validation:**
- Self-contained: cross-reference audit — every section referenced by code comments exists, and
  every doc claim about a constant matches the constant.
- Deferred: none.

### WME-R4 — Gate 4: final validation

**Model:** Opus 5 / GPT Sol

**Model rationale:** Consolidates every deferred check across four phases and makes the merge
call. Design judgement in the acceptance forces standalone.

**Depends on:** WME-20.

**Touches:**
- `docs/plans/reviews/worldmap-editor-gate-4.md` (new)
- `debug/worldmap/validation/gate4/` (new)

**End state:** Every deferred check in this file, run in a quiet tree, with a verdict and
screenshots.

**Implementation:** Consolidate the deferred lines from every item. Judge look from **yaw 0
only** — the editor's orbit is not a preview and never was.

**Validation:**
- Deferred: the whole item. Quiet tree, alone.

## Waves

Phase A runs as cycle `plan/worldmap-editor`. Later phases are re-cut at their gates.

| Wave | Items | Why disjoint |
|------|-------|--------------|
| A1 | WME-1 | law change; everything after depends on it |
| A2 | WME-2 | new rig, own file; nothing else writes it |
| A3 | WME-3 | new scene; depends on the rig |
| A4 | **WME-R1** | **gate, alone, quiet tree** |
| B1 | WME-4, WME-5 | tileset catalog + assets vs. tile data model + region catalog |
| B2 | WME-6, WME-7 | baker + ground vs. history + controller |
| B3 | WME-8 | ground shader; shared file, runs alone |
| B4 | WME-9 | brushes; needs history and picking |
| B5 | **WME-R2** | **gate, alone, quiet tree** |
| C1 | WME-10 | autotiler + tileset descriptor |
| C2 | WME-11 | overlay layer; extends tile data |
| C3 | WME-12 | props boundary; touches shipping prop code, runs alone |
| C4 | WME-13 | walk layer; extends tile data after the overlay |
| C5 | WME-14 | linter; reads everything, writes its own file |
| C6 | **WME-R3** | **gate, alone, quiet tree** |
| D1 | WME-15 | height field + ground shader |
| D2 | WME-16 | cliffs; shares the ground shader, runs alone |
| D3 | WME-17 | cascade; touches five shipping files, runs alone |
| D4 | WME-18, WME-19 | graph layer vs. HUD and minimap |
| D5 | WME-20 | docs, alone |
| D6 | **WME-R4** | **validation, alone, quiet tree** |

WME-11 and WME-13 both extend `WorldMapTileData.gd`, which is why they are separate waves
rather than one. If Gate 2's re-cut finds the layer blocks are cleanly separable in the format,
they may be merged into a single wave — that is the re-cut's call, made with the format in
front of it, not the executor's.

## Deliberately excluded

- **Tiled and LDtk.** Rejected by the user on 2026-09-05: they do not serve the demands this
  map makes. Not to be re-proposed on the grounds that they would be cheaper — that was
  considered and answered.
- **Per-region tile pixel sizes.** Deleted by the law in WME-1. A region's art grid is 16 px
  tiles and 8 px cels; a region drawn otherwise is legacy.
- **Cel-grade walkability, collision or elevation.** Cels are art. Anything an entity can
  observe is tile-grade, always.
- **Unpinning yaw for the game camera.** The editor orbits; the game does not. Baked light
  direction, upright icons and roads composited into the region art all depend on it.
- **A sky dome or a `WorldEnvironment` sky.** §7 rejected it on geometry: at every framing in
  use, every ray in the frustum points downward and there is no direction the camera sees sky.
- **An atlas sampled live in the shader instead of a bake.** See the present-state facts.
- **Animated tiles.** No mechanism in the ground shader samples time, and a tile-index
  indirection for animation would reintroduce the atlas problem. Revisit only with a reason.
- **Multi-region world editing.** WME-19 gives neighbour edge context; editing two regions at
  once, and whatever world-level structure that implies, is a later programme.
- **Travel, encounters and the party.** WME-18 authors the graph. Nothing consumes it here.
- **Retiring the painted-region path.** `temp` is 1080 colours and dithered; it stays painted
  and stays supported. Authored and painted regions coexist.

## 2026-09-06 — Product clarification and hands-on editor review

Added at the user's explicit request after playtesting the map editor. This is an authorized
addendum to the normally frozen plan, not a completion record for a WME item. The original
items above remain intact so their assumptions and committed work can still be understood.
The confirmed requirements below supersede conflicting assumptions in the provisional phases;
the proposed implementation order is a recommendation to use when re-cutting those phases.
Do not dispatch the original later waves unchanged on the strength of this review.

### Confirmed intended product

The user wants a 3D-oriented equivalent of Tiled, built inside Godot for this 2.5D game:

- Paint ground with 16x16 tiles, with occasional 8x8 surface details.
- Place buildings, bridges and similar objects above the ground, using upright sprites or
  simple 3D models as appropriate. This is a separate object layer, not merely pixels
  composited into the ground texture.
- Raise and lower ground vertices to make smooth hills, lake basins and riverbeds.
- Save authored maps for later use/export into actual gameplay scenes, independently of the
  debug scene and map-building UI.

These requirements bring object placement and smooth terrain into the essential authoring
workflow. Gate 1's wish for a simple layer list still applies; its deferral of props and
elevation must not now be read as deferring the user's core workflow indefinitely. No new
lore, visual theme, battle movement rules or travel gameplay is decided here.

### Playtest scope and evidence

Launched `scenes/debug/WorldMapEditorScene.tscn` with the bundled Godot 4.4 executable,
Forward+ on the RTX 3060, requesting a 1280x720 window. The last committed item at launch was
`dccc89a` (stroke undo/redo). Picking/shader work was also present in the working tree without
a WME-8 completion commit. The user explicitly directed this playtest to proceed despite
another session being active. These are observations of that mixed working tree, not formal
quiet-tree gate acceptance or proof of any concurrent item's completion.

Used real window inputs and inspected screenshots after actions. The successful visible
launch log contained the Godot/Vulkan startup banner and no script, shader or runtime errors
through shutdown. An earlier sandboxed launch reported shader-cache access errors; it was
stopped and rerun with normal user-data access before judging application behavior. Only this
review's launched processes were stopped; the pre-existing Godot editor was left alone.
The successful run's local log was `%TEMP%/wme-playtest-20260906.log`.

| Check | Observed result |
|---|---|
| Initial scene | Painted `temp2` renders with clouds; editor panel and debug controls appear beside the map. |
| Tab from initial canvas state | Switches to a top-down orthographic view; the off-contract badge identifies the mode. |
| F in orthographic view | **Defect:** enlarges the map until much of it is cropped, instead of fitting the region. |
| Space from initial camera interaction | Restores the gameplay framing and removes the off-contract badge. |
| Wheel over the map | Zoom changes visibly and the badge reports a dollied camera. |
| 16 px grid toggle | Shows/hides a visible tile lattice. This control uses the existing debug grid, not acceptance evidence for the new surface picker. |
| Region picker | Switching from `temp2` to `temp2 authored` succeeds; the readout changes from 15.5x11 to 15x11 tiles. |
| Tools on the authored map | The menu offers only Navigate and Inspect. Both layer rows still say empty. |
| Inspect and click terrain | No visible tile information or editable selection appears. No paint palette or brush controls are available. |
| Ctrl+Z | No visible content change or error. There was no editable stroke to undo, so this does not validate undo correctness. |
| Tab after HUD interaction | Moves focus to the grid checkbox instead of switching the camera mode. |
| Space with grid checkbox focused | **Defect:** resets the camera and also toggles the grid checkbox. One shortcut has two visible effects. |
| Close | Playtest process exited; final log contains no application errors. |

Short Q/A key taps did not establish visible orbit/pan behavior. Sustained keyboard movement
and middle/right-button dragging were not validated in this pass; do not count them as either
passing or broken. Curved-surface picking accuracy, large-map responsiveness, full undo/redo,
painting, object placement, terrain sculpting, save/reopen and gameplay export were not
validated. Most of that authoring workflow has no UI yet.

### Defects and usability findings to carry into the re-cut

1. **Fit-region must fit the actual editing viewport.** `WorldMapEditorCamera.frameRegion()`
   sets orthographic size to `max(region.width, region.height) * 0.6`, without considering
   viewport aspect. The observed portrait-shaped centre viewport makes the cropping obvious.
   Fit all region bounds with padding, respecting projection, aspect and camera orientation.
   Verify both the small painted/authored samples and a large region after window resizing.
2. **Camera shortcuts need deliberate focus handling.** Reproduce Tab/Space after choosing
   a region or tool and focusing a checkbox. Camera actions must not accidentally activate
   HUD controls too; text entry must keep its normal input behavior. Test with real events,
   not only direct calls to controller handlers.
3. **Give authoring most of the window.** The two panels left roughly 36% of the captured
   window width for the map. Clouds repeatedly obscured the small terrain while inspecting
   it. Recommend collapsible debug controls and an obvious authoring-view option to hide
   clouds, while retaining the complete gameplay preview for judging the shipped look.
4. **Show document state honestly.** Selecting a populated authored sample still displays
   Ground (empty) and Overlay (roads) (empty). Source inspection confirms `_document` remains
   null and `_onHistoryApplied()` is empty. Connect document loading, layer availability,
   selection and invalidation before presenting these rows as usable editing controls.

Verdict: the scene is a working preview/navigation shell with useful data infrastructure.
It is not yet an end-to-end map editor, and the camera/focus defects need correction before
the authoring workflow is accepted. No runtime code was changed by this review.

### Recommended changes to the remaining programme

**Keep the foundations.** The tile/cel law, stable identity ledger, versioned map data,
deterministic bake, stroke-delta pattern and separate editor camera remain useful. No restart
is proposed. The existing identity limitation for pixel-identical tiles with different
metadata remains documented; the UI must surface ambiguous re-imports rather than hiding it.

**Make scene production explicit and early.** Retain authored map data as the source of truth.
Use one map builder to construct the runtime terrain and placed objects for both the editor
preview and gameplay. Export a reusable scene with the needed resources, without the editor
HUD, editor camera or debug controller. A shipping camera/environment can be supplied by the
gameplay scene. `scenes/WorldMap.tscn` already provides a separate node hierarchy, but there is
no completed document-to-gameplay-scene export workflow. Regeneration should update generated
map content without overwriting hand-authored gameplay additions in a wrapper scene.
Godot 4.4 supports saving an owned node hierarchy with `PackedScene.pack()` and
`ResourceSaver.save()`; exported child ownership and resource dependencies require explicit
save/reload checks ([PackedScene reference](https://docs.godotengine.org/en/4.4/classes/class_packedscene.html)).
Keep camera-dependent world curvature a rendering transform, not terrain height stored in
the map or baked permanently into exported geometry.

**Keep two understandable authoring areas.** Ground contains the 16x16 paint surface, an 8x8
detail sublayer and terrain tools. Objects contains independently placed sprites/models.
This need not expose eight top-level layers. The original WME-11 baked overlay is appropriate
for surface paths/details; it cannot substitute for buildings or a raised bridge. Re-scope
WME-12 around explicit placed assets with stable instance identity, position, orientation,
footprint and height anchoring. Buildings normally remain upright; bridges need an authored
deck height or support rule rather than being draped over the riverbed. Preserve the existing
painted-region rendering path while the authored path gains these capabilities.

**Bring smooth terrain forward.** Re-scope WME-15 around shared corner heights with raise,
lower, smooth and flatten tools, brush radius/strength, and optional height snapping. The
original mandatory integer/half-unit restriction is not necessary for this product. Its
claim that continuous heights make slope classification undecidable is false: an explicit
slope threshold can classify continuous heights. Choose interpolation/triangulation once;
rendering, picking, object anchoring and exported terrain must sample the same surface.
Extend the history beyond string tile IDs to cover numeric heights and object operations.
Do not confuse this visual terrain model with the battle simulator's integer height rules.
Suitable ground textures are needed to judge the final look, but dedicated cliff-face art
should not block a smooth hill/basin prototype. Dedicated cliffs and terrain self-shadowing
can follow the basic authoring workflow rather than being prerequisites for it.

**Define modest water authoring.** A lowered basin is terrain, not a water surface. Recommend
authored water coverage and surface height for lakes and simple river sections, stored and
exported with the map. Flow simulation is not proposed. Decide the minimal water appearance
with the user rather than importing a new visual style. Validate bridge clearance and shore
placement against the same terrain surface.

**Prioritize the complete document loop.** New/open/save/save-as, tileset selection,
paint/erase, selection, visible active-tool state and undo/redo need explicit implementation
ownership. Add safe unsaved-change handling and export/reopen feedback. Keep stroke deltas,
but include objects and height edits in the same user-facing undo history. Measure full-size
editing with the implemented partial CPU composition/full texture upload behavior; do not
continue promising the original partial GPU-upload end state.

### Proposed next milestone and routing

The re-cut itself belongs to **Opus 5 / GPT Sol**: it changes document/runtime ownership,
object representation, terrain semantics and item dependencies. The rows below are proposed
delivery stages, not dispatch-ready replacement items. Each needs a complete Touches list,
dependencies and classified checks before execution; preserve one commit per actual item.

| Proposed order | Delivery | Suggested tier |
|---|---|---|
| 1 | Repair camera fit/focus and connect document loading, painting, history and bake updates; finish surface-picking integration. | Opus 5 / GPT Sol for integration/picking boundaries; Sonnet 5 / GPT Terra for separately scoped, fully specified UI/brush work. |
| 2 | Prove save/reopen and production of a reusable flat map scene in a separate gameplay scene. | Opus 5 / GPT Sol. |
| 3 | Add simple sprite/model placement and smooth terrain tools, with shared surface queries and complete undo. | Opus 5 / GPT Sol. |
| 4 | Add the agreed minimal water representation and bridge placement to complete the example map. | Opus 5 / GPT Sol for representation; Sonnet 5 / GPT Terra for subsequently specified controls. |
| 5 | Independently validate the whole authoring-to-gameplay workflow and measure larger-map performance. | Opus 5 / GPT Sol. |

Acceptance example: create a small map, paint 16x16 grass, add 8x8 detail, sculpt a smooth hill
and riverbed, place water, an upright building and a bridge, undo/redo tile/height/object
changes, save and reopen, export, then instantiate that result in a gameplay scene with the
editor absent. Verify tile appearance, terrain shape, object height and required resources
survive this round trip. Repeat representative strokes/navigation on a realistic full-size
region with timings. This is the first useful product milestone, not a claim that it passes
today. Autotiling, elaborate cliffs, travel graphs and extensive ergonomics should not delay
proving this workflow.

The original wave table also needs correction during the re-cut: B1 pairs WME-4 with its
dependent WME-5 and gives both `docs/WORLDMAP_EDITOR.md`; D4 pairs WME-18 with its dependent
WME-19. Neither is a legal parallel wave under the repository contract. Use committed
dependencies and disjoint Touches lists when authoring their replacements.
