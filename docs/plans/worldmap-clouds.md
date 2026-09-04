# World map clouds

Opened 2026-09-03. The world map's clouds today are four octaves of value noise multiplied
into the ground in `worldmap_ground.gdshader` — no shape anybody drew, no cloud above them
to explain them, and no altitude. This cycle deletes that outright and replaces it with the
supplied art: two cloud shapes and two matching ground shadows, standing at an altitude and
casting by the same sun the buildings do.

A cloud here is a **horizontal sprite at altitude**. The ground is real geometry viewed at a
steep pitch, so a flat quad above it is perspective-correct for free and gets parallax for
free — no separate projection, no scroll hack. Its shadow lands on the ground by the same
relation the standing structures use, `altitude × cot(sun elevation)` opposite the sun, with
altitude in place of a building's height.

Everything below the item list was settled in `debug/worldmap/clouds.html` and measured
there. **One honest caveat, because it changes what the last item is for: I was never able
to look at that sketch.** The browser pane stopped compositing while it was being built and
did not recover. Every number in it is real — coverage, parallax, shadow offsets, off-palette
counts — and none of them is a judgement about whether it reads. WMC-6 is where a human
looks, and it is standalone for that reason.

This is **not** a weather cycle. There is no overcast state, no rain, no cloud that grows or
dissipates, and nothing that reaches the battle renderer. A cloud is a sprite with a position
and a shadow.

## Outcome

When this closes:

- The cloud art lives in `assets/` **on temp2's exact palette**, with its four pieces
  declared in a catalog rather than as rects hardcoded in a renderer.
- A **pure cloud field** decides where clouds are, how the wind moves them, and where each
  one's shadow falls — deterministic from a seed, with no node and no rendering in it.
- Clouds **stand at altitude over the map**, taking the ground's curvature, the ground's fog
  and the day's light tint, so a distant cloud hazes into the same wash the ground does.
- The procedural noise cloud shadows are **gone** — uniforms, noise function, console rows,
  command-line flags and the preset that turned them on.
- Cloud shadows are drawn in **map-pixel space** like the cast shadows, so they land on the
  terrain's grid, union instead of stacking, and take fog and filtering for free.
- A cloud passing over a building **darkens the building too**, rather than sliding under it.
- All of it is reachable from the debug console and from the command line.

## Present-state facts an executing agent must not "fix"

- **The shadow art's colours are a reference, not the output.** The two shadow pieces are
  painted in `08696a` (shadowed sea) and `e69900` (shadowed sand) — the artist drew *shadowed
  terrain*, not a translucent overlay, which is independently the same answer the building
  shadows reached. So a fixed-colour shadow sprite is only correct over the terrain it was
  painted for. Measured on the ground alone: darkening the ground and snapping to the region's
  palette gives **7 distinct colours and 0 pixels outside temp2's palette**; blitting the art's
  own pixels gives 22 and **42,410**. Use the art for its *shape*.

- **Zero partial alpha in the file is not a defect to repair with a blur.** 55,872 fully clear
  pixels, 9,664 fully opaque, 0 partial. Softness is an **ordered dither anchored to map
  pixels**, not a blur — a blur produces colours between palette entries, which is the whole
  thing the snap exists to prevent.

- **Uniform-random cloud placement is wrong and it looks like it works.** The visible slice of
  a plane at altitude is far smaller than the visible ground — the cloud ray is
  `camera_height − altitude` long instead of `camera_height`, about 60% of the ground's reach
  at altitude 6. A random field measured 9% layer coverage with a *completely empty sky*, every
  cloud outside the slice. Use the jittered grid.

- **`spread` defaults to 1.15.** It scales the shadow against its cloud. At 2.2 the shadow is
  nearly 4× the cloud's area and reads as a separate object.

- **The shadow offset uses the sun's geometric `elevation`, floored at `sun_low` — not
  `lit`.** Same rule, same reason as the buildings: `cot` runs away at the horizon.

- **Do not reuse `WorldMapSun.at().shadow_step` for clouds.** It is clamped by `K_SUN_REACH`,
  a limit that exists to stop a *building* becoming a twenty-tile scratch. A cloud's shadow is
  a blob and being far from its cloud is correct. Recompute from the returned `direction`:
  `step = -direction.xz / direction.y`. The elevation floor still applies, because it is
  already baked into `direction`.

- **The cloud shadow layer belongs in map space and must not be "optimised" into a
  ground-level quad.** This is WMP-4's finding again, plus one more: two alpha-blended quads
  that overlap produce a darker patch, where a mask unions. Map space also buys pixel-grid
  alignment, no crawl under camera motion, and free fog.

- **temp2 is 248×176 map pixels.** A map-space layer at that size is not a performance
  question, and no argument that starts with its cost is a real one.

- **Fog is computed from GROUND-PLANE forward distance**, `CAMERA_POSITION_WORLD.z −
  world.z`, not view-space depth. They differ by roughly 3× at this pitch. The comment in
  `worldmap_ground.gdshader` records what happened the last time this was got wrong.

- **A shader that moves vertices needs `extra_cull_margin`.** Godot culls against the
  undisplaced mesh AABB. This was not what made the props vanish last cycle, but it is a real
  hole and the clouds open it again.

- **`debug/worldmap/probe_clouds.gd` tests the noise system.** It stops meaning anything the
  moment WMC-4 lands. That is not a regression; replace it rather than keeping it passing.

- **The `Tile-Exact, Filtered` preset sets `K_CLOUD_STRENGTH: 0.28` and its description sells
  cloud shadows in prose.** Both go. A preset that silently keeps a removed key is how a dead
  uniform survives a deletion cycle.

## Items

### WMC-1 — Land the cloud art on temp2's palette and declare its pieces

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A stated end state over a small known set of files: copy an asset, correct
five colour values to a list that is already written down, and mirror `WorldMapSkyCatalog`'s
shape for a second catalog. The one judgement — that the near-misses are eyedropper drift
rather than intent — is made here in the plan, so what is left is mechanical and checkable by
a pixel count.

**Depends on:** nothing.

**Touches:**
- `assets/worldmap/clouds/temp2_clouds.png` (new, plus `.import`)
- `src/presentation/worldmap/WorldMapCloudCatalog.gd` (new)
- `debug/worldmap/probe_cloud_art.gd` (new)

**End state:** The four pieces are declared by rect and role, and every pixel in the sheet is
either fully clear or exactly one of temp2's seven colours.

**Implementation:** The source is `debug/worldmap/cloud_models_src.png`, 256×256, four pieces:
`cloud A (16,16,88,40)`, `cloud B (152,16,88,40)`, `shadow A (16,64,88,40)`,
`shadow B (152,72,88,32)`. Four of its five colours are *near*-misses of temp2's palette and
one is exact:

| in the sheet | temp2 | |
|---|---|---|
| `31aeac` | `37aeae` | the one-pixel outline, on clouds **and** shadows |
| `08696a` | `0b696a` | |
| `ffd262` | `ffd363` | |
| `f6fff6` | `f5fff5` | |
| `e69900` | `e69900` | exact |

Snap each to its nearest temp2 colour. The outline one matters most: it was meant to be the
sea colour and is not, so as drawn every cloud carries a hairline of an eighth colour wherever
it crosses the coast. Do the correction as an explicit five-entry table, not a
nearest-neighbour sweep over the whole image — every value is already known, and a sweep would
silently move a colour that was already right. The catalog carries a set id (`temp2`), the
texture, and the four rects with their pairing, so a cloud and its shadow cannot be looked up
independently and drift apart.

**Risk:** Getting a snap backwards puts an eighth colour in the sheet permanently. The probe
catches it.

**Validation:**
- Self-contained: `probe_cloud_art.gd` asserts 4 pieces at the recorded rects, 0 pixels of
  partial alpha, and 0 pixels outside temp2's seven colours.

### WMC-2 — The cloud field: placement, wind, and the sun's ground offset

**Model:** Opus 5 / GPT Sol

**Model rationale:** The boundary item — every later item reads it and none can be checked
before it is right. It is also where three separate traps live: the visible slice at altitude
being smaller than the map, the clamp on `shadow_step` that must not be inherited, and wrap
behaviour at the map edge. Pure code with no rendering, so the cost of getting it wrong is
paid entirely downstream, which is exactly the shape that wants the higher tier.

**Depends on:** nothing. It takes a piece *count*, not the catalog — the field returns an
index and the caller resolves the rect, so it does not wait on WMC-1.

**Touches:**
- `src/presentation/worldmap/WorldMapCloudField.gd` (new)
- `debug/worldmap/probe_cloud_field.gd` (new)

**End state:** `WorldMapCloudField.at(framing, seedValue, clockSeconds) -> Array` returns one
dictionary per cloud: its centre in map pixels, its size, its piece index, and its shadow's
centre in map pixels. No nodes, no state, deterministic for a given seed and clock.

**Implementation:** Placement is a **jittered grid** — a 5×5 lattice over the field's extent
with a per-cell offset from the seed, then shuffled so raising `count` reveals clouds
scattered rather than filling row by row. The shuffle is not cosmetic: an unshuffled list
makes a low `count` look like a placement bug. Wind is a speed and an angle integrated against
the clock and wrapped over the field extent. The shadow offset is `altitude × step` with
`step = -direction.xz / direction.y` taken from `WorldMapSun.at()`, unclamped — see the facts
above. Quantise both centres to whole map pixels; a sub-pixel position is what makes a
map-space layer crawl.

**Risk:** A wrap that is right in the middle of the map and wrong at its edge shows only when
a cloud is straddling one. The probe walks a cloud all the way around.

**Validation:**
- Self-contained: `probe_cloud_field.gd` reproduces the sketch's four measurements — parallax
  (a 4-unit pan moves the ground 122.2 px against a cloud's 90.7 at altitude 6); shadow offset
  symmetric about noon; offset linear in altitude (3.2 / 6.3 / 12.6 tiles at altitude
  4 / 8 / 16); and coverage non-empty at altitudes 3, 6 and 12. Plus determinism for a fixed
  seed, and continuity across a wrap.

### WMC-3 — Stand the clouds up at altitude

**Model:** Opus 5 / GPT Sol

**Model rationale:** A new shader whose vertex stage has to agree with two existing ones about
curvature, whose fragment stage has to agree with the ground about which distance fog uses,
and which reopens the cull-margin hole. Every one of those cost a regression round last cycle.
It also owns the scene and the controller wiring for the rest of the cycle.

**Depends on:** WMC-1, WMC-2.

**Touches:**
- `assets/shaders/worldmap_cloud.gdshader` (new, plus `.uid`)
- `src/presentation/worldmap/WorldMapClouds.gd` (new)
- `scenes/WorldMap.tscn`
- `src/presentation/debug/WorldMapDebugController.gd`
- `src/presentation/debug/WorldMapDebugHud.gd`
- `debug/worldmap/probe_clouds_altitude.gd` (new)

**End state:** Clouds are visible over the map at a settable altitude, drifting on the wind,
fogged and tinted like the ground, bending with the same curvature, and reachable from the
console as Count, Size, Altitude, Wind speed, Wind angle and Cloud opacity.

**Implementation:** One `MeshInstance3D` per cloud holding a flat quad, following what
`WorldMapProps` already does rather than inventing a MultiMesh for a maximum of 24 quads. The
quad is horizontal, so there is no billboarding here at all — the perspective is the camera's,
and that is the point of the approach. Curvature takes the drop from the quad's **base** and
applies it to the whole quad: the curve must *carry* a sprite, not shear it, which is the same
finding both earlier shaders record. Fog from ground-plane forward distance. The day's tint
multiplies, like everything else that is not emissive. Set `extra_cull_margin`.

Softness is deliberately **not** offered on the cloud body — the art is hard-edged and that is
the look. It belongs to the shadow, and it arrives in WMC-4.

**Risk:** A cloud that is correct at Curved Close and gone at height 70 is exactly the failure
the props had, and it does not show in a single screenshot. Sweep curvature against camera
height, as `probe_full_retest.gd` does.

**Validation:**
- Self-contained: `probe_clouds_altitude.gd` — clouds render non-zero coverage at altitudes
  3/6/12; parallax against the ground matches WMC-2's prediction within a pixel; clouds
  survive the curvature × height × pitch sweep; every new console row's default round-trips
  through the framing dictionary.
- Deferred: whether clouds at the default altitude read as *above* the map rather than painted
  on it.

### WMC-4 — Replace the noise cloud shadows with a map-space layer

**Model:** Opus 5 / GPT Sol

**Model rationale:** It edits the ground shader's fixed pass order, deletes a shipped system
across five files at once, and owns the two judgements the sketch could not settle without
eyes — how dark a cloud shadow should be and how its edge should break up. Deleting a feature
cleanly is also where dead uniforms survive; that wants care rather than speed.

**Depends on:** WMC-3. There has to be a caster on screen before a shadow can be aimed under
it.

**Touches:**
- `assets/shaders/worldmap_ground.gdshader`
- `src/presentation/worldmap/WorldMapCloudShadows.gd` (new)
- `src/presentation/worldmap/WorldMapGround.gd`
- `src/presentation/worldmap/WorldMapGroundUniforms.gd`
- `src/presentation/worldmap/WorldMapFramingCatalog.gd`
- `src/presentation/debug/WorldMapDebugController.gd`
- `src/presentation/debug/WorldMapDebugHud.gd`
- `debug/worldmap/probe_clouds.gd` (replaced)

**End state:** `cloud_strength`, `cloud_scale`, `cloud_speed`, `cloud_cover()` and their
console rows, command-line flags and preset value no longer exist anywhere. In their place the
ground samples a map-space cloud coverage layer, unioned with the cast-shadow mask and snapped
to the region's palette.

**Implementation:** A `SubViewport` at the region's map-pixel size (248×176 for temp2) with a
`Node2D` blitting each shadow piece at its whole-pixel centre from WMC-2, drawing up to four
copies for a piece straddling an edge. Coverage comes from the art's alpha, white on black.

In the fragment stage, combine before fog and with **max, not sum**:

```
float shade = max(masks.r * shadow_strength, cloud.r * cloud_shadow_strength);
```

One darkening pass, one snap. Summing puts a building's shadow under a cloud off palette,
which is the same reasoning the lamps use. Softness is a Bayer dither on the coverage edge
anchored to `floor(uv * map_size)` — **map pixels, never screen** — reusing the constant
`WorldMapShadowMask.BAYER4` already carries. Confine the dither to a band at the edge: applied
across the whole falloff it checkerboards the entire shadow, which the sketch did once.

Delete `value_noise()` as well if `cloud_cover()` was its only caller, and rewrite the
`Tile-Exact, Filtered` preset description.

**Risk:** Removing keys from `DEFAULTS`/`ORDER` while a console row still names them breaks
the debug scene at load. That is why the row removal is in this item and not a later one.

**Validation:**
- Self-contained: replacement `probe_clouds.gd` asserts 0 pixels outside temp2's palette with
  shadows at full strength; coverage responds to `count`; two overlapping shadows are no
  darker than one; shadow edges land on map-pixel boundaries; and a grep-level check that no
  `cloud_strength` / `cloud_scale` / `cloud_speed` reference survives in `src/`, `assets/` or
  `scenes/`.
- Deferred: the shadow's strength and its dither band, which are look decisions.

### WMC-5 — Let cloud shadows fall on the standing structures too

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** One sampler and one lookup added to an existing shader, against a seam
that is already named and already solved once for the lamps. The design decision — that a prop
reads the coverage at its **foot**, not per-fragment — is made here, so the work is a
transcription of an existing pattern.

**Depends on:** WMC-4.

**Touches:**
- `assets/shaders/worldmap_prop.gdshader`
- `src/presentation/worldmap/WorldMapProps.gd`
- `debug/worldmap/probe_cloud_on_props.gd` (new)

**End state:** A cloud passing over a building darkens the building by the same amount it
darkens the grass around it, so the shadow crosses the scene as one edge rather than sliding
under the structures.

**Implementation:** Sample the cloud layer once at the prop's **base** map position and apply
it uniformly to the quad. Not per-fragment: a standing sprite occupies map pixels it is not
actually standing on, so a per-fragment lookup would sample ground the building is merely in
front of, and the sprite would be striped by whatever is behind it. This is the same reason
shadows use the sprite's true height rather than its billboard-corrected one — a screen-space
quantity must not be allowed to drive a world-space one.

**Risk:** A building that darkens a frame before or after the grass at its feet reads worse
than one that never darkens at all. Compare the transition frames, not the steady state.

**Validation:**
- Self-contained: `probe_cloud_on_props.gd` drives a cloud across a known structure and
  asserts the prop's mean brightness and the ground's at its foot move together, within the
  tolerance the palette snap allows.

### WMC-6 — Document the clouds and validate the cycle

**Model:** Opus 5 / GPT Sol

**Model rationale:** Acceptance here is a judgement about how something looks, across a
feature nobody in the cycle has yet seen rendered, and it writes the section of the design doc
that stops the next cycle re-deriving all of it.

**Depends on:** WMC-1 … WMC-5. Runs alone in a quiet tree.

**Touches:**
- `docs/WORLDMAP_DESIGN.md` (new §13; §12 Open updated)
- `docs/sketches/worldmap-clouds.html` (promoted from `debug/worldmap/clouds.html`)
- `debug/worldmap/probe_cloud_retest.gd` (new)

**End state:** §13 records the approach, the numbers, and what was rejected. The sketch is
promoted self-contained. Every deferred check above has been run and reported with its
measurement.

**Implementation:** Consolidate the deferred checks: clouds reading as above the map, shadow
strength, the dither band, and the prop transition. Sweep the same space
`probe_full_retest.gd` does — curvature × camera height × pitch, every framing preset, both
regions — with clouds on, and re-run every earlier probe. The promoted sketch must carry its
own art and map as data URIs, as `standing-structures.html` does.

State plainly in the commit whether the look questions were settled by looking or are still
open. An unlooked-at feature reported as validated is worse than one reported as unverified.

**Validation:**
- Self-contained: `probe_cloud_retest.gd` plus every prior probe green.
- Deferred: none — this is the deferred item.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | WMC-1, WMC-2 | an art asset and its catalog vs. a pure geometry module; no shared file, and the field takes a piece count rather than the catalog |
| 2 | WMC-3 | needs both; owns the scene and the debug wiring |
| 3 | WMC-4 | owns the ground shader and its uniforms; needs a caster to aim under |
| 4 | WMC-5 | prop shader; needs the cloud layer to exist |
| 5 | WMC-6 | validation, alone, quiet tree |

## Deliberately excluded

- **Weather.** No overcast state, no rain, no storm, no cloud that grows or dissipates. Count
  and wind are settings, not a simulation.
- **Clouds beyond the region.** They live over the map. A cloud drifting out across the void
  or in front of the sky backdrop raises where the map's edge *is*, which is a framing question
  this cycle should not reopen.
- **Per-region cloud sets in `regions.json`.** A catalog with a set id, like the skies, is the
  closer analogue, and the second region does not exist yet. Moving it into region data is a
  ten-line change when a map wants its own clouds.
- **Altitude-dependent penumbra.** Real shadows soften with the caster's height. The art is
  hard-edged pixel art and the softness knob is a dither, so a physically-scaled blur has
  nowhere to land. Reconsider only if the altitude range grows.
- **Clouds occluding props in depth.** At any altitude the map allows, a cloud is above
  everything on the ground; there is no case where one passes in front of a tower.
- **Anything in the battle renderer.** Untouched.
