# World map props and daylight

Opened 2026-09-02. `WorldMapProps` ships: it finds the buildings painted into a region's
ground art, paints the ground back in underneath, and stands them up as billboarded sprites,
selectable from the debug console in three modes. Two things about it are known to be
temporary and one is known to be missing, and all three were measured rather than assumed —
`docs/WORLDMAP_DESIGN.md` §9 carries the numbers.

The extractor is **fitted to one map**. The same colour key that finds 9 of 9 structures on
temp2 returns 302 components on temp, 94% of them four pixels or smaller. Trees cannot work at
all: tree-green and grass-green are one continuous population with no trough to threshold at.
The layered fix for that is understood and deliberately deferred — see "Deliberately
excluded". What this cycle does instead is stop the rule being hardcoded, so a map with its
own disjoint palette needs data rather than code.

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

- A region **declares the colours that identify its structures**, so a second map is a data
  change rather than a code change. Buildings still emerge from the single ground PNG.
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
- Buildings **light a circle of ground after dark** by withholding the night inside it, so the
  lamp reveals the daytime palette instead of adding light to it, and cannot produce a colour
  the art does not already contain.
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

- **The single ground PNG is a decision, not an oversight.** Buildings emerge from the region
  art and there is no second layer. Do not add one; see "Deliberately excluded" for why it is
  deferred and what would have to change first.

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

### WMP-1 — Move the extraction rule into region data

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A stated end state across a small, known set of files: constants move from
GDScript into a catalog accessor and a JSON block, and the matcher reads them. The decision —
that the single PNG stays for now — is made here in the plan, so what is left is mechanical.

**Depends on:** nothing.

**Touches:**
- `src/presentation/worldmap/WorldMapRegionCatalog.gd`
- `src/presentation/worldmap/WorldMapProps.gd`
- `data/worldmap/regions.json`
- `debug/worldmap/probe_prop_layer.gd` (new)

**End state:** A region declares the colours that identify its structures, and
`WorldMapProps` reads them rather than carrying temp2's palette as GDScript constants. A
second map with its own disjoint palette becomes a data change, not a code change. temp2
finds exactly the same 9 structures as before, with the same rects and kinds.

**Implementation:** The single ground PNG stays and buildings keep emerging from it — that is
a decision, not an oversight, and the layered alternative is recorded under
"Deliberately excluded" with the measurement that motivates it. What this item removes is the
*hardcoding*: `_isBuilt`'s three colour tests, `_isDoor`'s orange, the aspect threshold that
separates towers from houses, and the minimum component size all become region properties.

Keep the tolerances — the matcher is `abs(channel - value) < tol`, not equality, because the
PNG round-trips through import. Do not "simplify" it to an exact match.

**Risk:** A region omitting the block and silently finding nothing. Absent keys fall back to
the current constants, and the readout already reports the structure count, so a region that
finds zero says so on screen.

**Adds to final validation:** temp2 finds 9 structures (7 houses, 2 towers) from region data
alone; temp still loads and renders flat.

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
### WMP-7 — Lamps after dark, subtractive

**Model:** Opus 5 / GPT Sol

**Model rationale:** The mechanism is a design decision with a house style at stake, not a
parameter — additive and subtractive light are different models that happen to look similar in
a thumbnail, and only one of them can stay inside the palette. It also shares the light-level
representation with WMP-4 and WMP-6, so getting it wrong fragments the thing those two items
are building.

**Depends on:** WMP-1, WMP-3, WMP-4.

**Touches:**
- `src/presentation/worldmap/WorldMapShadowMask.gd`
- `assets/shaders/worldmap_ground.gdshader`
- `assets/shaders/worldmap_prop.gdshader`
- `src/presentation/worldmap/WorldMapProps.gd`
- `data/worldmap/regions.json`

**End state:** After dark a structure lights a circular area of ground around it. The night is
**not applied** inside that circle, so the ground keeps its daytime colours; nothing in the
lamp path can produce a colour the art does not already contain. **The structures inside a lit
circle are lit too** — a building standing in its own pool of light must not be the one dark
thing in it — and its emissive pixels hold their colour on top of that. Lamps rise as the sun
sets, driven by the honest elevation rather than a hardcoded hour.

**Implementation:** **Subtractive, not additive.** A lamp is a region where the night is
withheld, not warm light painted on top. That is the whole item. An additive glow — which the
sketch keeps as a comparison mode — invents colours between the palette entries and is what
makes procedural light look grafted onto pixel art.

The lamp field is a distance field in **map-pixel space**, the same space as WMP-4's shadow
mask, and for the same reason: its edge then lands on the terrain's own grid and cannot swim
under camera motion. Shadow and lamp are the same mechanism seen twice — both modulate a
per-pixel light level, and the palette decides what a level looks like. Build them as one
representation; two parallel systems that happen to agree is the failure mode here.

Combine overlapping lamps with **max, not sum**. Two lamps together light a wider area, not a
brighter one, and summing is exactly what blows a cluster out to white. temp2's three-house
cluster is the test case.

Four shapes were prototyped and measured at map-pixel resolution in the sketch:

- **Hard circle.** One level, a clean pixel circle. The most graphic answer.
- **Stepped rings.** Concentric levels; the classic tile-era light radius. Quantise with
  `round`, not `ceil` — `ceil` biases the whole lit area outward by half a level and puts the
  outermost ring one step brighter than the falloff says.
- **Dithered rings.** Ordered dither, **confined to a narrow band where two levels meet**.
  This is the one with a trap in it, and it was caught by reading the light field at map-pixel
  resolution rather than by looking at a thumbnail: a plain Bayer threshold across the whole
  falloff alternates on nearly every pixel of the light and reads as noise, not as softness.
  The band is centred on `frac = 0.5`, which is where a ring boundary sits, and the pattern
  sweeps across it. The Bayer index comes from **map** coordinates.
- **Additive glow.** Kept only as the comparison that shows why the others exist.

The sprite and the ground must take their tint from **one function and one field**. A building
lit to one value while the grass under it is lit to another is the exact seam this is meant to
remove, and it is invisible in a thumbnail. Measured at 22:00 on the building pixels: 80,92,98
with no lamps, 132,153,112 under stepped rings, against 130,156,124 in full daylight.

**Risk:** The lamp circle reading as a hole punched in the night rather than as light. Tint
lit pixels toward a slightly warm value rather than to neutral white; the sketch's `LIT`
constant is the starting point, not a final answer.

**Adds to final validation:** no lamp produces a colour outside the region's palette; the
three-house cluster does not clip; lamps rise and fall with the sun.
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
- **A separate prop layer, for now.** The measurement stands: a per-region second image,
  transparent except where props sit with the ground painted complete underneath, makes
  extraction exact instead of inferred, works for trees, and deletes the ground-patch
  guesswork. It is deferred because it needs art that does not exist and because the single
  PNG is good enough for the maps in hand. Everything this cycle builds below the extraction
  survives that change unaltered, which is what makes deferring it cheap.
- **Shadows for anything but structures.** Trees become possible once a prop layer exists, but
  temp2 has none and inventing them to test against is how the last 2.5D attempt went wrong.
- **Sorting and a depth buffer for dense prop fields.** Nine well-spaced structures do not
  exercise it. The problem is real and arrives with a denser map, not with this cycle.
- **Standing anything up on temp.** temp is dithered, its palette is not disjoint, and it has
  no prop layer. It must keep loading and rendering flat; that is all.
