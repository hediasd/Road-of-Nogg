# World map ground rig

Authored 2026-08-31. **Queued, not open.** `plan/battle-camera-direction` is still
checked out and its cycle file is still present, and one cycle runs at a time. This
opens with `git switch -c plan/world-map-ground-rig` only after that cycle merges,
in a quiet tree, on the user's word.

The out-of-battle world map does not exist. This cycle builds the thing the player
stands on: a painted region PNG laid on a ground plane in a `Node3D` scene, viewed
from a fixed yaw at a steep pitch with the far distance washing out into haze — plus
the debug scene that lets its framing be chosen rather than guessed, and which later
world-map work extends rather than replaces.

Every number below was derived in `debug/worldmap/worldmap-framing.html`, which
carries the reasoning and the live explorer. The short version: the reference has
**no horizon** — the map runs off the top of the frame and the fog never completes on
screen. Pitch 60 / FOV 25 comes from the ~3:1 near-to-far depth ratio measured off the
sharpest capture. Scale comes from counting 16 px tiles: ~53 across the bottom edge at
~7.5 buffer px each, the ground minified ~2.1×.

This is **not** the world map feature. There are no roads, no node graph, no travel
time, no encounters, no menu. Those need this rig to exist first and are listed under
Deliberately excluded so they are not smuggled in.

## Outcome

When this closes:

- A `WorldMap` scene renders a region PNG on a ground plane under a fixed-yaw camera,
  with distance haze, an off-map void colour, and optional ground curvature and cloud
  shadows — all from one custom spatial shader.
- The framing presets derived from the reference captures exist as a catalog in the
  same shape as `RenderPresetCatalog`, and switching between them is one call.
- A `WorldMapDebugScene` switches presets live, exposes every shader and camera
  uniform as a control, draws the 16 px tile grid, and prints the readout that makes
  framing checkable — tiles across, buffer px per tile, and the region width the
  current framing demands. Every control has a command-line equivalent.
- That debug scene has a stated extension seam, so adding a road tool or a node-graph
  inspector later is a new section rather than a rewrite.
- `docs/WORLDMAP_DESIGN.md` states the rig's contract: the framing dictionary keys,
  the tile convention, and why yaw is fixed.

## Present-state facts an executing agent must not "fix"

- **The horizon is off-screen and that is the whole point.** Pitch 60 with FOV 25 puts
  the horizon far above the top of the frame, so no sky ever draws and the fog never
  reaches full opacity on screen. Do not add a sky dome, do not "fix" the missing
  horizon, and do not lower the pitch until one appears. The reference has none.

- **Fog must not come from `WorldEnvironment`.** Godot 4 unshaded materials skip
  environment fog, so routing it there produces either no fog or a lit ground. It is a
  manual blend inside the ground shader. This also keeps the map's fog from being
  coupled to whatever environment the battle scene wants.

- **Yaw is fixed at 0 and is not a knob.** A painted map has one baked light direction
  and upright icons; rotating it breaks both, and a fixed yaw is what allows roads and
  settlements to be composited into the PNG instead of being separate meshes. Do not
  add orbit "for parity with the battle camera".

- **1 tile = 1 world unit is a deliberate convention**, not an oversight. At 16 px per
  tile that makes `world_units_per_map_pixel` exactly `0.0625`, and it makes camera
  height, fog distances and region size all readable as tile counts. Do not normalise
  to metres, and do not scale it to match the battle board's cell size.

- **The world map's render scale is not `RetroRenderController`'s retro preset.** On
  the battle side the low-resolution viewport exists only under a retro preset and the
  default is native. Here, buffer pixels per tile is a *framing* decision — it is what
  makes the ground minify, which is what makes the pixel sparkle read as texture
  rather than as a defect. A world map at native resolution stops looking like the
  reference. Give the world map its own scale and do not wire it to the battle's
  preset.

- **The party marker is drawn at fixed screen size, not as a world-space billboard.**
  In the reference, units at the top of the frame are no smaller than those at the
  bottom and all are drawn far larger than a ground tile at the same depth. A naive 3D
  billboard renders the far party at a third the size of the near one. The marker not
  shrinking with distance is correct.

- **`temp_map.png` is too small for the reference framing, and the visible plane edges
  are expected.** It is 768×1024 = 48×64 tiles. With a 2.89:1 near-to-far ratio the
  frame's far edge is 2.89× wider than its near edge, so filling the frame at 53 tiles
  across needs a **155-tile-wide** region. No fog setting hides this: the void appears
  at a fixed depth set by map width and FOV, and at that framing it is already nearer
  than the bottom of the screen. Preset `fit` exists for this reason. Do not "fix" it
  by upscaling the art or by clamping the camera.

- **Curvature defaults to 0 and cloud shadows default to off.** Both are in the shader
  because the debug scene must be able to explore them; neither is in the reference.
  Do not enable them to make a screenshot look nicer.

- **`run/main_scene` stays `res://scenes/Battle25D.tscn`.** This cycle adds a scene; it
  does not change what the game boots into.

## Items

### MAP-1 — Ground shader, uniform contract, and the design note

**Model:** Opus 5 / GPT Sol

**Model rationale:** Authors the contract every later item implements against, so a
loose decision here propagates into four files. The shader itself is real work —
per-fragment fog against a curved plane, an off-map test that must not smear the edge
texel, and a mip/anisotropy story that has to survive a deliberately minified ground.
It also has to encode a taste decision (sparkle is wanted) as a default rather than
silently filtering it away.

**Depends on:** nothing. Boundary item.

**Touches:**
- `assets/shaders/worldmap_ground.gdshader`
- `src/presentation/worldmap/WorldMapGroundUniforms.gd`
- `docs/WORLDMAP_DESIGN.md`

**End state:** A spatial shader, `render_mode unshaded`, that samples a region texture
on a horizontal plane and applies, in order: cloud-shadow multiply, distance fog blend
toward a fog colour, and an off-map void colour where the sample falls outside the
texture. A vertex stage bends the plane by `y = -k * d²` where `d` is forward distance,
inert at `k = 0`. `WorldMapGroundUniforms.gd` holds the uniform name constants and the
**framing dictionary keys** — pitch, fov, height, units-per-map-pixel, fog start/end/
curve, fog colour, void colour, curvature, cloud strength/scale/speed, render scale,
sprite mode — so MAP-2 and MAP-3 can be written concurrently against one spelling.
`docs/WORLDMAP_DESIGN.md` states the tile convention, the fixed yaw, why fog is in the
shader and not the environment, and the `region_width ≥ tiles_across × near_far_ratio`
constraint with its derivation.

**Implementation:** Fog is per-fragment on world-space distance from the camera. The
off-map test runs in texture space before sampling and returns the void colour rather
than clamping, because clamping streaks the edge texel across the whole far field.
Cloud shadows sample a tiling value-noise texture scrolled over world XZ; generate the
noise procedurally in the shader rather than shipping an asset, since no specific cloud
shape has been asked for. Do not add a `WorldEnvironment` to anything.

**Risk:** Getting the fog into linear vs sRGB space wrong makes the haze read as grey
mud instead of bright cyan. Compare against the sketch's rendered strip: land should
lift from roughly `61,169,70` near the camera to `107,177,111` at the top of the frame.

**Adds to final validation:** The ground renders with haze, void, curvature and cloud
shadows each independently switchable, with no `WorldEnvironment` involved.

---

### MAP-2 — Framing preset catalog

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Transcription of numbers that are already settled into a file
shape that already exists — `RenderPresetCatalog.gd` is the template, down to the
`PRESETS` array of `{id, label, description}` dictionaries. No design judgment remains;
the descriptions are written below. Mechanical, well-bounded, and its correctness is
checkable by reading it against this file.

**Depends on:** MAP-1 (uniform and framing-key spelling).

**Touches:**
- `src/presentation/worldmap/WorldMapFramingCatalog.gd`

**End state:** A `WorldMapFramingCatalog` with `class_name`, id constants, and a
`PRESETS` array carrying every framing key from MAP-1. Seven entries, all at pitch 60 /
FOV 25 / units-per-map-pixel 0.0625, differing in camera height (the zoom knob), fog
band scaled with height, and render scale:

| id | label | height | fog start/end | render scale | notes |
|----|-------|--------|---------------|--------------|-------|
| `fit` | Fits this region | 20 | 6 / 35 | 0.40 | 16 tiles across; the widest a 48-tile region can fill |
| `tile_exact` | Tile-exact | 66 | 21 / 116 | 0.40 | 53 tiles across, 7.5 px/tile — the derived reference |
| `closer` | Closer capture | 45 | 14 / 79 | 0.40 | 36 tiles across; matches the 512×448 capture |
| `crt` | CRT photo | 56 | 12 / 74 | 0.333 | heavier, earlier haze; fog curve 1.1, colour `#d8ecf2` |
| `overview` | Route planning | 105 | 34 / 185 | 0.40 | 85 tiles across; not a reference match |
| `walking` | Walking | 30 | 10 / 53 | 0.40 | 24 tiles across; not a reference match |
| `filtered` | Tile-exact, filtered | 66 | 21 / 116 | 1.00 | anisotropic + clouds on; the comparison, not the target |

**Implementation:** Descriptions are player-invisible and read by whoever is choosing a
framing, so say what each is *for* and where it came from, as `RenderPresetCatalog`
does. `crt` and `filtered` carry extra keys the others leave at default; make the
catalog merge over a `DEFAULTS` dictionary rather than repeating every key seven times.

**Risk:** Silently drifting a number. Every value in the table above is a measurement,
not a preference — transcribe, do not round.

**Adds to final validation:** All seven presets load and none produces a black frame.

---

### MAP-3 — World map scene, ground plane, and camera rig

**Model:** Opus 5 / GPT Sol

**Model rationale:** Scene construction with real geometry decisions — how finely to
subdivide the plane so curvature is smooth without wasting vertices, how to size the
plane from a region's tile dimensions, and how to clamp panning so the player cannot
push the void into frame. The camera rig is small but its contract is what every later
world-map item drives.

**Depends on:** MAP-1.

**Touches:**
- `scenes/WorldMap.tscn`
- `src/presentation/worldmap/WorldMapGround.gd`
- `src/presentation/worldmap/WorldMapCameraRig.gd`

**End state:** `WorldMap.tscn` is a `Node3D` holding a `MeshInstance3D` ground and a
`Camera3D`. `WorldMapGround` builds a subdivided `PlaneMesh`, applies the MAP-1
material, and sizes the plane from a region's tile dimensions at 1 tile = 1 world unit.
`WorldMapCameraRig` accepts a framing dictionary, applies pitch as
`rotation_degrees.x = -pitch` with yaw pinned to 0, sets `fov` (vertical, since
`keep_aspect` is `KEEP_HEIGHT`), positions the camera at the framing's height above a
focus point, and exposes `panTo()` clamped to the region's bounds. It also reports the
derived numbers — tiles across the bottom edge, buffer px per tile, near:far depth
ratio, and required region width — because MAP-5 displays them and MAP-6 checks them.

**Implementation:** The derived-number maths is worked out in the sketch; port it
rather than re-deriving. Tiles across scales linearly with camera height at fixed
pitch/FOV, which is why every preset in MAP-2 varies only height. Subdivide the plane
enough for curvature to be smooth at `k = 0.02` (the explorer's maximum) and no more.

**Risk:** Panning clamped to the region's rectangle is not sufficient — the *far* edge
of the frame is 2.89× wider than the near edge, so a camera centred inside the region
can still show void. Clamp against the frame's far-edge footprint, not the camera
position, or accept visible edges and say so.

**Adds to final validation:** Panning to each region corner in the `fit` preset never
shows void.

---

### MAP-4 — Region catalog, and the first region imported

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Asset import flags and a small data catalog against an established
pattern in `data/`. The only subtlety — nearest filtering with mipmaps on — is stated
in the end state rather than left to be discovered.

**Depends on:** MAP-1.

**Touches:**
- `assets/worldmap/regions/temp.png` (from `debug/worldmap/temp_map.png`)
- `assets/worldmap/regions/temp.png.import`
- `data/worldmap/regions.json`
- `src/presentation/worldmap/WorldMapRegionCatalog.gd`

**End state:** `temp_map.png` lives in `assets/` as region id `temp`, imported with
**nearest filtering and mipmaps generated** — nearest because the near ground is meant
to be chunky, mipmaps because the far ground is minified ~2× and has nothing to fall
back on without them. `regions.json` records each region's id, texture path, and tile
dimensions; `WorldMapRegionCatalog` loads it and exposes lookup by id. The catalog
validates tile dimensions against the texture and fails loudly on a mismatch.

**Implementation:** The id `temp` is a placeholder. Naming this region is a lore
question — raise it with the Lorekeeper, do not invent a name here.

**Risk:** Godot's importer defaults to linear filtering with mipmaps off, which is
exactly backwards for this rig: the near ground goes soft and the far ground aliases.
Check the `.import` file, not just the inspector.

**Adds to final validation:** The region loads by id and its tile dimensions match the
texture.

---

### MAP-5 — World map debug scene

**Model:** Opus 5 / GPT Sol

**Model rationale:** A new debug surface that later world-map cycles extend, so its
seam is the deliverable as much as its controls are. Mirrors an established pattern
(`VFXDebugController` / `VfxDebugHud` / `VfxDebugWorld`) that has to be adapted rather
than copied, and carries the command-line parity that pattern adopted deliberately.

**Depends on:** MAP-2, MAP-3, MAP-4.

**Touches:**
- `scenes/debug/WorldMapDebugScene.tscn`
- `src/presentation/debug/WorldMapDebugController.gd`
- `src/presentation/debug/WorldMapDebugHud.gd`

**End state:** A standalone scene using the shipping pipeline, structured like the VFX
debug scene: the controller owns policy, the HUD owns control references and readout
formatting. It provides:

- A **preset dropdown** over `WorldMapFramingCatalog`, switching framing live. This is
  the item's headline: choosing between the presets is one control.
- A live slider or field for every framing key, so a preset is a starting point rather
  than a cage. Editing any control moves the readout to a `custom` framing, exactly as
  `RenderPresetCatalog` handles `CUSTOM`.
- A **16 px tile grid overlay**, projected onto the ground, so tile counts can be
  verified by eye against a reference screenshot.
- A **readout block** carrying tiles across, buffer px per tile, near:far ratio,
  required region width against the loaded region's actual width, and a visible warning
  when the framing demands more region than exists.
- A **region dropdown** over `WorldMapRegionCatalog`.
- **Copy-settings**, printing the current framing as a block that can be pasted into
  `WorldMapFramingCatalog` or a design note.
- **Command-line parity**: `--preset=`, `--region=`, and an override for every framing
  key, so a validation observation is scriptable rather than a sequence of clicks.

**Implementation:** State the extension seam in the controller's doc comment and build
to it: the HUD gets collapsible sections declared as data (as `VfxDebugHud.STATUS_ROWS`
declares its readout), so a later road-spline tool or node-graph inspector is a new
section entry plus its handlers, not surgery on a monolith. Do not add road, node, or
encounter tooling now — leave the seam, not a stub.

**Risk:** The VFX debug controller is 1500 lines. Copying its structure wholesale
imports that mass before this scene has earned it. Take the section/readout/argument
patterns and leave the rest.

**Adds to final validation:** Every preset is reachable from the dropdown and from
`--preset=`, and the two produce identical readouts.

---

### MAP-6 — Final validation

**Model:** Opus 5 / GPT Sol

**Model rationale:** Judges whether the rig actually reproduces the reference, which is
a taste call against screenshots, not a checklist. Also owns any correction to
`docs/WORLDMAP_DESIGN.md` that the build turned up.

**Depends on:** MAP-1 through MAP-5. Alone in its wave, quiet tree.

**Touches:**
- `docs/WORLDMAP_DESIGN.md`
- `debug/worldmap/worldmap-framing.html`

**End state:** Every "adds to final validation" line above is confirmed against the
running game, not against the HTML sketch. The `tile_exact` preset is compared
side-by-side with the reference captures and the verdict recorded — including, if it
comes to it, that a number derived from a screenshot did not survive the real renderer.
The sketch's opening paragraph is updated from "Settled so far" to the decision that
was actually reached, and the sketch is promoted to `docs/sketches/` if it earned it
under that directory's bar, with its embedded base64 region stripped first.

**Implementation:** Only one session may launch the game at a time; confirm the tree is
quiet before starting. The numbers to check against are in the sketch's readout: 53
tiles across, 7.2 buffer px per tile, near:far 1:2.89.

**Risk:** The real renderer may not reproduce the sketch, whose fog, filtering and
scanline sampling are a JavaScript approximation. A mismatch is a finding to record,
not a reason to bend the game toward the sketch.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | MAP-1 | boundary item; fixes the shader and framing-key contract everything else implements against |
| 2 | MAP-2, MAP-3, MAP-4 | preset data vs. scene and rig scripts vs. asset import and region data |
| 3 | MAP-5 | debug scene; needs all three of wave 2 committed |
| 4 | MAP-6 | validation, alone, quiet tree |

## Deliberately excluded

- **Roads, the node graph, travel time, and encounter markers.** The whole gameplay
  layer. It needs a ground to sit on; that is what this cycle is.
- **Fog of war and the heavy cloud layer** that hides unexplored regions. Agreed as
  wanted, deferred. Note the cloud layer is a *second* plane above the ground and a
  separate texture from the cloud-shadow noise — do not conflate them when it arrives.
- **The world map ↔ battle transition.** Diving into a stage node instead of cutting is
  a good idea that reaches back into the battle camera contract; it needs both cameras
  to exist first.
- **The menu overlay**, and what the map does behind it.
- **Party sprite art and a walk cycle.** The marker stays a placeholder quad; MAP-3
  only has to prove fixed-screen-size positioning works.
- **Animated water, day/night tint, region streaming, and multiple regions loaded at
  once.** One region, loaded by id.
- **Changing `run/main_scene`.** The game still boots into the battle.
- **Pre-stretching the region art vertically.** Measured and rejected: at pitch 60 the
  compensation is 1.15×, small enough that the perspective squash is not worth an art
  pipeline change. Recorded here so it is not re-proposed.
