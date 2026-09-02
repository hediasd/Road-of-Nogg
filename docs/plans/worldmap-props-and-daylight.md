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
- The shadow's **edge treatment is a decision somebody looked at**, chosen against the
  reference the user painted, rather than inherited from what a canvas affine blit happens to
  produce.
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

- **Drag-to-pan in the debug scene is deliberately unclamped**, unlike the shipping
  `panTo(focus, rect)`. A debug tool has to be able to look at the map's edge, which is
  exactly what the clamp exists to prevent. The readout keeps flagging `EDGES SHOW`.

- **The tower's bottom row is a painted ground shadow** and is deliberately excluded from the
  standing sprite (`rows = h - 1`). It is not an off-by-one.

## Blocking input

**WMP-6 cannot start until the user supplies the shadow they painted next to the towers.**
It was asked for and could not be found: `temp2.png` hashes identical to `HEAD`
(`ab68cc0a1aeadc6e469b29db8767a817`), and nothing newer exists in the project or in
Downloads. WMP-6 is the item that chooses the edge treatment, and choosing it without the
reference is exactly the guessing this plan is meant to avoid. Every other item is unblocked.

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

### WMP-4 — Cast shadows on the ground

**Model:** Opus 5 / GPT Sol

**Model rationale:** New rendering with several independent ways to be quietly wrong — the
silhouette's fill rule, the shear, the composite order, and the interaction with the ground's
curvature. Each was found by looking at a render in the sketch rather than by reasoning, and
each has a "looks fine, is wrong" failure mode. The composite decision in particular is a
structural choice about how shadows accumulate, not a parameter.

**Depends on:** WMP-3.

**Touches:**
- `assets/shaders/worldmap_shadow.gdshader` (new)
- `src/presentation/worldmap/WorldMapProps.gd`
- `debug/worldmap/probe_shadows.gd` (new)

**End state:** Each structure casts a shadow onto the ground: its **solid** silhouette,
sheared so the foot edge stays put and the tip lands `h · cot(elevation)` away opposite the
sun, widening to `shadow_spread` at the tip. Shadows accumulate into one pass and composite
once, so two crossing shadows form a union. Shadow geometry takes the curve drop belonging to
its base.

**Implementation:** The silhouette is solid, not the sprite's alpha. Transparent pixels
*inside* a structure — the tower's open belfry, the gap beside a doorway — must not punch
holes in its shadow, because a building has a solid door and glazed windows. Find background
by flooding in from the bounding-box edge, four-connected; anything the flood cannot reach is
solid whatever colour it was. Taking the alpha directly gave the tower a shadow with a hole
through the middle.

**Risk:** Double-darkening where shadows overlap, which is invisible on temp2's nine
well-spaced structures and obvious the moment a village is dense. The probe places two
structures deliberately overlapping and asserts the crossed region is no darker than either
shadow alone.

**Adds to final validation:** overlapping shadows form a union; no shadow has a hole in it.

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

### WMP-6 — Choose the shadow's edge

**Model:** Opus 5 / GPT Sol

**Model rationale:** A judgment call with a house style at stake and a history of measurement
misleading on exactly this kind of question — ranking 2.5D options by mean pixel difference
once put the worst option first. The deliverable is a decision plus the evidence for it, and
the three candidates differ in what they claim about the art's identity, not in cost.

**Depends on:** WMP-4, **and the user's painted reference** (see Blocking input).

**Touches:**
- `assets/shaders/worldmap_shadow.gdshader`
- `docs/sketches/2026-09-02-worldmap-shadow-edge.html` (new)
- `docs/WORLDMAP_DESIGN.md` §10

**End state:** The shadow edge is one of three treatments, chosen by looking, with the other
two recorded as rejected and why. The sketch shows all three side by side at several framings
and times of day, against the user's painted reference.

**Implementation:** The current edge is not a decision, it is a side effect: the sketch draws
shadows as **hard-edged affine texture-mapped triangles** with nearest sampling, so the edge
is whatever the rasteriser produces. In the engine it becomes an alpha-cut quad, which is the
same hard edge by a different route. The three candidates:

1. **Hard alpha cut.** What exists. Pure, cheap, and consistent with a flat seven-colour
   palette that has no gradients anywhere else in it.
2. **Ordered-dither fringe.** A Bayer threshold across a band at the shadow's edge, so
   softness is faked with the palette rather than with new colours. This is the 8-bit-authentic
   answer and the one that fits "pixel noise and optical discrepancies are beauty for this type
   of game". Dither must be anchored in **screen space**, or the pattern swims as the camera
   pans.
3. **True alpha gradient.** Smooth, and the one most likely to read as modern and wrong
   against this art. Included because it is cheap to try and because rejecting it from
   reasoning alone is what this project keeps getting wrong.

Judge by looking. Do **not** rank these by a pixel-difference metric against the reference: a
metric of that kind reports how much changed, not whether it is better, and it has already
produced one bad recommendation on this exact map.

**Risk:** Choosing an edge that reads at Curved Close and falls apart at a pulled-back framing
where the shadow is a handful of pixels. The sketch must show every candidate at the near and
far framings, not only the one it was tuned at.

**Adds to final validation:** the chosen edge holds at both the closest and the most pulled-back
preset.

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

Wave 4 pairs the two items that touch different shaders. WMP-6 may stall on the blocking
input; if it does, run WMP-7 alone and hold WMP-6 for its own wave rather than letting it
block WMP-8.

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
- **Shadows for anything but structures.** Trees become possible once a prop layer exists, but
  temp2 has none and inventing them to test against is how the last 2.5D attempt went wrong.
- **Sorting and a depth buffer for dense prop fields.** Nine well-spaced structures do not
  exercise it. The problem is real and arrives with a denser map, not with this cycle.
- **Standing anything up on temp.** temp is dithered, its palette is not disjoint, and it has
  no prop layer. It must keep loading and rendering flat; that is all.
