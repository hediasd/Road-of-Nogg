# World map props and daylight

Opened 2026-09-02. `WorldMapProps` ships: it finds the buildings painted into a region's
ground art, paints the ground back in underneath, and stands them up as billboarded sprites,
selectable from the debug console in three modes. Two things about it are known to be
temporary and one is known to be missing, and all three were measured rather than assumed —
`docs/WORLDMAP_DESIGN.md` §9 carries the numbers.

The extractor is a **bootstrap for one map**. The same colour key that finds 9 of 9 structures
on temp2 returns 302 components on temp, 94% of them four pixels or smaller. Trees cannot work
at all: tree-green and grass-green are one continuous population with no trough to threshold
at. This cycle replaces detection with authorship.

The props are also **unfogged**, which does not show at Curved Close only because structures
sit at 13–22 units against a fog start of 21. And the day/night sun with its cast shadows,
lamps and light tint exists **only in the sketch** (`debug/worldmap/standing-structures.html`,
recorded as §10). This cycle brings all of it into the engine.

This is **not** a lighting-model cycle. There is no shadow map, no light source the player can
place, no per-prop normal map, and nothing that touches the battle renderer. The sun is a
direction and a colour; a shadow is a silhouette sheared onto the ground. It is also not a
simulation cycle: the clock drives pixels and nothing else.

## Outcome

When this closes:

- A region can carry an **authored prop layer** — a second image the same size, transparent
  except where props sit, with the ground painted complete underneath. Extraction from it is
  exact, works for trees, and needs no ground patching. The colour key survives as a
  documented fallback for regions without one.
- Props are drawn by **one shader** that does billboarding, the ground's own fog, and the
  day's light tint, so a distant structure fades into the same haze the ground does instead
  of popping out of it.
- The world map has a **sun**: a time of day, a direction that sweeps a narrow northward arc,
  and a colour that moves from dawn through noon to night.
- Structures **cast shadows** onto the ground — solid silhouettes, sheared by the sun,
  composited once so crossing shadows form a union rather than a darker patch.
- Those shadows **read as pixel art and stay reading as it** while the sun moves and the
  camera pans: edges on map-pixel boundaries, colours from the region's own palette, and a sun
  quantised so the shadow steps between stable shapes instead of crawling.
- Buildings **light their windows after dark** and spill a low pool onto the ground.
- All of it is reachable from the debug console and from the command line.

## Present-state facts an executing agent must not "fix"

- **The squash is not `cos(pitch)`, and the correction is per sprite.** It is
  `f / D` with `D = H·sin p + f·cos p`, which equals `cos p` at the frame centre and nowhere
  else; measured across one frame at Curved Close it runs 0.33 near to 0.76 far. Do not
  "simplify" `updateGain` to a single global factor. That was tried, and it left the near
  house at `h/w 0.931` and the far one at `1.291` against a painted `0.875`.

- **`clampf(depth / denom, 0.1, 8.0)` has a floor of 0.1 on purpose.** Past the frame centre
  a vertical quad is *magnified*, not squashed, so far sprites are corrected downward and the
  factor is legitimately below 1. A floor of 1.0 looks like the obvious guard and silently
  leaves everything beyond mid-frame too tall.

- **`gain` and `face` producing the same rectangle is a measured result, not a redundant
  mode.** 0.00 px at every pitch in the sketch, 0.00% worst aspect error over all nine
  structures in `probe_props.gd`. They differ in what they claim about world space, which is
  why both are kept. Do not delete one as a duplicate.

- **Props being unfogged is this cycle's WMP-3, not a bug to patch early.** Do not reach for
  `Sprite3D.modulate` as a stopgap: modulate multiplies, and fog blends *toward* a pale
  colour, so it cannot be expressed that way.

- **302 components on temp is not a thresholding failure.** temp is dithered and no colour in
  it is exclusive to anything. A better threshold does not exist; that is the finding, and it
  is why WMP-1 exists.

- **The black bars down each side of every standing building are the art.** The house sprite
  carries a black outline drawn to read on a flat top-down sprite; stood up and magnified it
  becomes a vertical bar. That is an art decision and it is out of scope here.

- **Shadows use the sprite's true height, not its billboard-corrected height.** The billboard
  correction is a screen-space trick. Letting it into the lighting swings every shadow by 2×
  when the gain is switched on.

- **The shadow mask lives in map space and must not be "optimised" into screen space.** A
  screen-space shadow quad is what a 3D engine makes easy, renders fewer pixels, and needs no
  extra texture — and it is the reason procedural shadows do not look painted. Its edge lands
  at arbitrary sub-pixel positions and angles that do not align to the map's grid, and it
  crawls under camera motion. No edge treatment repairs that. See WMP-4.

- **Drag-to-pan in the debug scene is deliberately unclamped**, unlike the shipping
  `panTo(focus, rect)`. A debug tool has to be able to look at the map's edge, which is
  exactly what the clamp exists to prevent. The readout keeps flagging `EDGES SHOW`.

- **The tower's bottom row is a painted ground shadow** and is deliberately excluded from the
  standing sprite (`rows = h - 1`). It is not an off-by-one.

## Items

### WMP-1 — Give a region an authored prop layer

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A stated end state across a small, known set of files: one catalog
accessor, one JSON key, one branch at the top of `rebuild()`, and an export probe. The hard
part — deciding that authorship beats detection — is already settled and measured in §9. No
boundary is being moved; the prop source becomes a parameter of something that already exists.

**Depends on:** nothing.

**Touches:**
- `src/presentation/worldmap/WorldMapRegionCatalog.gd`
- `src/presentation/worldmap/WorldMapProps.gd`
- `data/worldmap/regions.json`
- `assets/worldmap/regions/temp2_props.png` (new)
- `assets/worldmap/regions/temp2_ground.png` (new)
- `debug/worldmap/probe_prop_layer.gd` (new)

**End state:** A region may declare `PROPS` and `GROUND` textures in `regions.json`. When
`PROPS` is present, `WorldMapProps.rebuild()` takes its structures from that layer's
connected alpha components and uses `GROUND` untouched — no colour key, no patching, no modal
fill. When it is absent the current colour-key path runs unchanged, so temp keeps working.
temp2 ships both layers, exported from what the extractor finds today, and renders
identically through either path.

**Implementation:** The export is the part worth getting right, because it is what makes this
checkable rather than aspirational: `probe_prop_layer.gd` runs the existing extractor once and
writes `temp2_props.png` (bounding boxes, transparent elsewhere) and `temp2_ground.png` (the
patched ground). That gives a real layer to test against *and* hands the artist a starting file
to paint over rather than a blank canvas. Structures come from alpha components in the prop
layer, which is why a tree works here and cannot work through a colour key.

**Risk:** The two paths silently diverging. The probe asserts the same structure count, kinds
and rects from both, on temp2, and fails loudly if not.

**Adds to final validation:** temp2 renders identically through the prop layer and the colour
key; temp still loads through the fallback.

### WMP-2 — A sun the world map can ask the time of

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Pure derivation with an exact reference to hit. Every number and every
sign is already fixed by §10 and by the sketch, the whole thing is headless-testable, and it
adds one new file plus a block of keys to a contract whose shape is established. Judgment was
spent when the arc and the elevation floor were measured; what is left is transcription.

**Depends on:** nothing.

**Touches:**
- `src/presentation/worldmap/WorldMapSun.gd` (new)
- `src/presentation/worldmap/WorldMapGroundUniforms.gd`
- `debug/worldmap/probe_sun.gd` (new)

**End state:** `WorldMapSun` turns a time of day into a direction, two elevations, a ground
shear step, a light tint and a night factor. Framing gains `time_of_day`, `sun_high`,
`sun_low`, `sun_arc`, `sun_reach`, `shadow_strength`, `shadow_spread`, `light_tint`,
`lamp_strength` and `lamp_reach`, each defaulting so that a framing which names none of them
behaves exactly as today. `probe_sun.gd` reproduces the sketch's measured tables.

**Implementation:** Two elevations, and they are not interchangeable. The honest one reaches
zero at both ends of the day and drives light colour, lamps and shadow opacity. The geometric
one never drops below `sun_low`, because `cot(elevation)` runs away at the horizon. Azimuth
sweeps `90° ± sun_arc`, not a full semicircle: a full sweep puts the sun due east at dawn and
throws the shadow due *west*, sideways across the screen with no northward component at all.

**Risk:** A sign error in the azimuth turns every shadow toward the camera, which looks
plausible in a still and is wrong. The probe asserts the northward component is positive at
every hour of daylight.

**Adds to final validation:** shadow direction leans north at every daylight hour; the
measured arc table matches the sketch.

### WMP-3 — One prop shader: billboard, fog and light in the vertex stage

**Model:** Opus 5 / GPT Sol

**Model rationale:** This moves a boundary. Props currently borrow `Sprite3D`'s internal
material, which is what makes `face` free and forces `gain` to be a CPU pass over every sprite
every frame; a `material_override` takes the billboard away and the shader must do it. Getting
that wrong is silent — a shader that billboards subtly differently still renders something
plausible. It also has to reproduce the ground shader's fog exactly, including the two
departures from the obvious that were each a defect once: ground-plane distance rather than
view-space depth, and a gamma-space blend.

**Depends on:** WMP-1, WMP-2.

**Touches:**
- `assets/shaders/worldmap_prop.gdshader` (new)
- `src/presentation/worldmap/WorldMapProps.gd`
- `src/presentation/worldmap/WorldMapGroundUniforms.gd`
- `docs/WORLDMAP_DESIGN.md` §9

**End state:** Props draw through one `ShaderMaterial`. It implements all three billboard
modes in the vertex stage, applies the ground's fog against the same uniforms and the same
maths, and multiplies the day's light tint. `updateGain()` and its per-frame CPU pass are
gone. A structure at the far edge of a fogged framing is the same colour as the ground it
stands on.

**Implementation:** Fog uses `CAMERA_POSITION_WORLD.z - world_position.z`, not view-space
depth — they differ roughly 3× at this pitch. The blend is in gamma space, matching the ground
shader's deliberate departure from physical correctness. Billboard modes resolve to an up-axis
in the vertex stage: world `(0,1,0)`, camera `(0, cos p, −sin p)`, and for `gain` the closed
form `h = h0·D / (f + h0·sin p)` from §9. The sprite's base must stay planted under all three.

**Risk:** The mode that regresses is `gain`, because it is the one whose correctness is a
number rather than a look. `probe_props.gd` already measures worst aspect error across all
nine structures and must still report 0.00%.

**Adds to final validation:** all three billboard modes still measure 0.00% aspect error;
props and ground agree in colour at the fog's far edge.

### WMP-4 — Cast shadows as a map-space mask

**Model:** Opus 5 / GPT Sol

**Model rationale:** This is an architectural choice that decides whether the shadows can
ever look like pixel art, and the obvious implementation is the wrong one. Screen-space
shadow quads are what a 3D engine makes easy and they cannot be made to read as painted at
any edge treatment. Choosing the other representation, and seeing why, is the item.

**Depends on:** WMP-3.

**Touches:**
- `src/presentation/worldmap/WorldMapShadowMask.gd` (new)
- `src/presentation/worldmap/WorldMapProps.gd`
- `src/presentation/worldmap/WorldMapGround.gd`
- `assets/shaders/worldmap_ground.gdshader`
- `debug/worldmap/probe_shadows.gd` (new)

**End state:** Shadows are rendered into a **region-sized mask texture in map-pixel space**
(248×176 for temp2), which the ground shader samples with the same UV and the same nearest
filter it already uses for the region art. A shadow's edge therefore lands on exact map
pixels, aligned with the terrain's own pixel grid, and it is fogged, curved and filtered by
the ground path for free because it *is* the ground.

**Implementation:** The insight that makes this simple: a shadow lies on the ground plane,
and **map space is the ground plane**. So the shear is a plain 2D affine in map pixels —
the foot edge stays, the tip edge moves by `h · cot(elevation)` converted to map pixels and
widens by `shadow_spread`. There is no 3D projection anywhere in the shadow path, and no
possibility of the shadow disagreeing with the ground about where it is.

Build it as a `SubViewport` sized to the region in map pixels, with one 2D polygon per prop
carrying the silhouette, drawn opaque. Its texture is the mask. Three properties fall out of
that rather than needing to be engineered:

- **Union compositing is free.** Every shadow is drawn opaque into the same buffer, so two
  crossing shadows cannot double-darken. Ground in shadow twice over is just ground in shadow.
- **Fog, curvature and filtering are free.** The ground already does all three, and the mask
  rides the same sample.
- **The mask is tiny.** 44k pixels for temp2, regenerated only when the sun moves.

The silhouette is **solid**, not the sprite's alpha. Transparent pixels *inside* a structure —
the tower's open belfry, the gap beside a doorway — must not punch holes in its shadow,
because a building has a solid door and glazed windows. Find background by flooding in from
the bounding-box edge, four-connected; anything the flood cannot reach is solid whatever
colour it was. Taking the alpha directly gave the tower a shadow with a hole through the
middle.

**Risk:** The mask and the region art drifting out of alignment by a pixel, which reads as a
shadow that is subtly detached from its building. The probe asserts a structure's shadow at a
noon sun starts on the exact map pixel row its foot occupies.

**Adds to final validation:** shadow edges land on map-pixel boundaries; overlapping shadows
form a union; a shadow's foot is pixel-exact against its caster.

### WMP-5 — Daylight controls in the debug console

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Additive work on a surface built to be extended — `SECTIONS` declares
controls as data and `WorldMapDebugHud`'s own header documents adding one as the intended
seam. Two new sections, matching handlers, readout rows, and command-line parity that rides
the existing override loop. No decisions, and a clear end state.

**Depends on:** WMP-2.

**Touches:**
- `src/presentation/debug/WorldMapDebugHud.gd`
- `src/presentation/debug/WorldMapDebugController.gd`

**End state:** Daylight and Lamps sections drive every key WMP-2 added, with a running clock
that can be started and stopped, and a readout showing the time, both elevations, the shadow's
reach in tiles and whether it is clamped. Every key has a `--flag=` and unknown enum values
warn and fall back rather than silently doing nothing.

**Implementation:** The clock is wall-clock driven, not frame-counted, so its speed does not
depend on frame rate. Follow the `--sky=` precedent for validation: the generic override loop
only coerces types, so a typo in an enum silently produces wrong behaviour while the readout
names the right thing.

**Risk:** Low. The failure mode is a control that reads a key nothing consumes, which the
readout makes visible immediately.

**Adds to final validation:** every daylight key is reachable from both the panel and the
command line.

### WMP-6 — Make the shadows read as pixel art, and hold still

**Model:** Opus 5 / GPT Sol

**Model rationale:** The judgment item. Three decisions that interact, a house style at stake,
and a history on this exact map of a metric recommending the worst option. What "good" means
here cannot be written down in advance, which is the whole reason the item exists separately
from WMP-4 rather than being folded into it.

**Depends on:** WMP-4, WMP-5.

**Touches:**
- `assets/shaders/worldmap_ground.gdshader`
- `src/presentation/worldmap/WorldMapShadowMask.gd`
- `data/worldmap/regions.json`
- `docs/sketches/2026-09-02-worldmap-shadow-edge.html` (new)
- `docs/WORLDMAP_DESIGN.md` §10

**End state:** Shadows look painted rather than composited, and they stay looking painted
while the sun moves and the camera pans. Three decisions are made, each with the rejected
alternatives and the reason recorded.

**Implementation:** WMP-4 buys pixel alignment. It does not buy the look. Three separate
questions remain, and they are separate — an answer to one does not imply an answer to
another:

**1. What colour is a shadowed pixel?**
- *Multiply or darken.* Arithmetic. Introduces colours the palette does not contain — a
  darkened sand that is not any of temp2's seven — which is precisely what makes procedural
  shading look grafted onto pixel art.
- *Palette-mapped.* Every terrain colour gets an authored shadowed counterpart, so shadowed
  sand is the specific colour someone chose for sand-in-shadow. Seven entries for temp2. This
  is how the art would be painted by hand and is the strong candidate.
- *Derived palette map.* Multiply, then snap to the nearest existing palette entry. Free, no
  authoring, and it may collapse two terrain colours onto one shadowed colour and lose the
  boundary between them. Worth measuring before assuming it does.

**2. What happens at the edge?**
- *Hard.* At map-pixel resolution a hard edge **is** a pixel edge, which is a much stronger
  position than it was in screen space. Likely correct for a flat seven-colour palette with no
  gradients anywhere else in it.
- *Ordered dither in map space.* A Bayer threshold across a one- or two-pixel band, dithering
  between lit and shadowed palette entries. Palette-locked, authentic to the era, and the
  thing that fits "pixel noise and optical discrepancies are beauty". In map space the pattern
  is anchored to the terrain and cannot swim.
- *Alpha gradient.* Included only to be rejected on sight; it necessarily produces
  off-palette colours and is question 1 in disguise.

**3. How does it move?** This is the one that decides whether it looks *consistent*, and it
has no analogue in a still image. A sun rotating continuously drags a hard pixel edge across
the map one pixel at a time, and the boundary pixels flicker as it goes — the shadow crawls.
The fix is to **quantise the sun's azimuth** to a fixed number of steps so the mask changes
between stable configurations instead of shimmering. Find the step count by looking at it in
motion: too few and the shadow visibly snaps, too many and it crawls. The same question
applies to elevation, which changes the length.

Judge all three by **looking, and looking at motion**. Do not rank them by pixel difference
against anything: that metric reports how much changed rather than whether it improved, and it
has already produced one bad recommendation on this map. The sketch must show the candidates
at rest *and* stepping through a day, because question 3 is invisible in a still.

**Risk:** Tuning at Curved Close and shipping something that falls apart pulled back, where a
shadow is a handful of map pixels and a two-pixel dither band is the whole shadow. Every
candidate is shown at the closest and the most pulled-back preset.

**Adds to final validation:** shadows hold their look across the framing range and do not
crawl as the sun steps through a day.
### WMP-7 — Lamps after dark

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Two well-specified effects — an emissive mask on the prop shader and an
additive ground pool — both prototyped, with the placement question already answered by WMP-1.
The one genuine design decision, that an emissive mask belongs in the prop layer rather than in
a colour rule, is made here in the plan.

**Depends on:** WMP-1, WMP-3.

**Touches:**
- `src/presentation/worldmap/WorldMapProps.gd`
- `assets/shaders/worldmap_prop.gdshader`
- `assets/worldmap/regions/temp2_props.png`

**End state:** After dark, a structure's emissive pixels hold their colour instead of taking
the night tint, and each structure spills a low additive pool onto the ground whose radius is
`lamp_reach`. Lamps come up as the sun goes down, driven by the honest elevation, not by a
hardcoded hour.

**Implementation:** The emissive mask is **authored into the prop layer**, not derived. The
sketch's rule — white with a teal neighbour in the same row, plus orange — is fitted to one
map's art and is the wrong shape for a pipeline; carry it once to generate the initial mask,
then let it be painted. A lit window is emissive: lerp the whole pixel toward the lamp colour
rather than multiplying by the night tint and adding warmth back, which gives a muddy grey.
The ground pool is an ellipse squashed by `sin(pitch)`, because a circle of light on the ground
is a circle seen at the camera's angle; drawing it round is what makes ground decals read as
stickers on the lens.

**Risk:** Additive pools blowing out to white where structures cluster. temp2 has a
three-house cluster that is the test case.

**Adds to final validation:** lamps rise and fall with the sun; the three-house cluster does
not clip to white.

### WMP-8 — Validation and the design note

**Model:** Opus 5 / GPT Sol

**Model rationale:** Reads the whole working tree, reconciles seven items' claims against what
is actually on screen, and decides what §9 and §10 should say now that the sketch-only caveat
is gone. Consolidation and judgment, not transcription.

**Depends on:** all of WMP-1 … WMP-7.

**Touches:**
- `docs/WORLDMAP_DESIGN.md` §9, §10
- `debug/worldmap/probe_validation.gd`
- `docs/sketches/2026-09-02-worldmap-standing-structures.html` (promoted)

**End state:** Every "Adds to final validation" line above is checked and reported. §10 no
longer says "in the sketch only". The standing-structures sketch is promoted to
`docs/sketches/` with its base64 stripped, because it is the sketch that settled the billboard
question, the shadow geometry and the daylight model.

**Implementation:** Extend `probe_validation.gd` rather than starting a second harness. Its
existing negative control matters: a check that cannot fail is a check that tests nothing, and
that trap has been hit once already on this rig.

**Risk:** Declaring a pass from metrics without looking. Several of these are look-decisions;
capture the renders and say plainly which claims were checked numerically and which by eye.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | WMP-1, WMP-2 | prop source (Props, catalog, region data) vs. the sun (new file + Uniforms); no shared path |
| 2 | WMP-3 | boundary item; takes Props, Uniforms and the design note together |
| 3 | WMP-4, WMP-5 | shadow shader + Props vs. the debug panel's two files |
| 4 | WMP-6, WMP-7 | shadow shader + §10 vs. prop shader + Props + the prop layer art |
| 5 | WMP-8 | validation, alone, quiet tree |

Wave 2 is a single item because `WorldMapProps.gd` and `WorldMapGroundUniforms.gd` are the
spine of this cycle — nearly everything reads one or both — and WMP-3 rewrites how props are
drawn. Nothing can safely run beside it.

Wave 4 pairs the two items that touch different shaders: WMP-6 works on the ground shader and
the shadow mask, WMP-7 on the prop shader and the prop art. WMP-6 also needs WMP-5's clock,
because question 3 — whether the shadow crawls — is invisible in a still and can only be judged
by stepping a day.

## Deliberately excluded

- **A simulation clock.** Travel time being a resource means the hour could eventually mean
  something in the model, and it does not here. The sun is a rendering input the debug console
  sets. Coupling it to anything is a separate decision.
- **Re-lighting the art.** The region PNG and every prop sprite have their lighting baked in.
  Cast shadows move and the overall colour moves, but the shading on a building's own face
  does not, and it will not until either per-direction sprites or per-prop normal maps exist.
  The relief experiment of 2026-09-01 is a reason to be careful about the second.
- **The black outline bars.** Stood up and magnified, the art's own outline becomes a vertical
  bar down each side of a building. That is an art call, not a rendering one.
- **Shadows falling on anything but the ground.** The mask is the ground plane, so a building
  cannot shade its neighbour's wall. That needs a different representation and there is nothing
  on temp2 close enough together to want it.
- **Shadows for anything but structures.** Trees become possible once a prop layer exists, but
  temp2 has none and inventing them to test against is how the last 2.5D attempt went wrong.
- **Sorting and a depth buffer for dense prop fields.** Nine well-spaced structures do not
  exercise it. The problem is real and arrives with a denser map, not with this cycle.
- **Standing anything up on temp.** temp is dithered, its palette is not disjoint, and it has
  no prop layer. It must keep loading and rendering flat; that is all.
