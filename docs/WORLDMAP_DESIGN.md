# World map design

The out-of-battle presentation: a painted region PNG laid on a ground plane in a
`Node3D` scene, viewed from a fixed yaw at a steep pitch, the far distance washing
out into haze. This note covers the **ground rig** — the plane, its material, and the
camera that frames it. Roads, the node graph, travel time, and encounters are not here
yet and are not implied by anything below.

Every number was derived in `debug/worldmap/worldmap-framing.html`, which carries the
live explorer and the reasoning. This note records the conclusions and the contracts.

## 1. The tile convention

**One tile is one world unit.** That is the whole convention, and it is what makes every
other number in the rig readable as a tile count: a camera height of 62.5 is 62.5 tiles up,
a fog end of 331 is 331 tiles of depth, a 31x22 region is 31x22 tiles.

A tile's **pixel size is a property of the art, not of the world**, and it varies per region.
`temp` is drawn on a 16 px grid, `temp2` on an 8 px grid. It is declared per region as
`TILE_PIXELS` in `data/worldmap/regions.json`, validated against the texture on load, and it
**never reaches the camera**: a 31x22 region of 8 px tiles and a 31x22 region of 16 px tiles
occupy the same ground and frame identically, differing only in how many texels each tile
gets. A region's world size simply *is* its tile count.

This was originally written with 16 hardcoded and a `units_per_map_pixel` framing key that
happened to cancel out. The first 8 px region exposed it. The key is gone -- it was redundant
with the tile count, and it was actively harmful: it was also a live slider in the debug
scene, and moving it sent the camera off the map, which the focus clamp then hid by
recentring.

Sprites are drawn at **fixed screen size**, not as world-space billboards. In the reference,
units at the top of the frame are no smaller than those at the bottom, and all are drawn far
larger than a ground tile at the same depth. A world-space billboard renders the far party at
a third the size of the near one. The consequence to keep in mind: the party is not really
*in* the scene, so anything that must sit convincingly on the ground -- a blob shadow, a road
highlight touching its feet -- is positioned in world space even though the sprite is not.

## 2. There is no horizon

The reference captures show **no horizon and no sky**. The map runs off the top of the
frame and the fog never completes on screen; it is a mild distance wash, not a wall.

Geometrically, the horizon is on screen only when `pitch < fov/2`. The rig is
comfortably the other side of that line, so no sky is ever drawn and the first framing
question is not "where does the horizon sit" but "is there one at all" — and the answer
is no. Do not add a sky dome, and do not lower the pitch until a horizon appears.

## 3. Framing

Pitch and FOV are not independent, and neither describes the look on its own. The number
that does is the **near-to-far depth ratio** across the frame, which is what sets how
strongly the world converges:

```
R = (u·sin + cos)(sin + u·cos) / ((cos − u·sin)(sin − u·cos)),   u = tan(fov/2)
```

Measured off the sharpest reference capture — tree sprites ~22 px tall at the bottom of
the frame and ~7 px near the top — `R ≈ 3`. Solving gives **pitch 60° / FOV 25°**.

Scale comes from counting tiles rather than from judgment. In a 256×224 reference frame
a 16 px tile lands at ~7.5 frame pixels: the ground is **minified about 2×** even at its
nearest point, putting ~34 tiles across the bottom edge. At 16:9 the equivalent framing
is **~53 tiles across**.

Two things that are easily conflated and are separate decisions:

- **Framing** is *tiles across the frame*. Set by camera height against
  units-per-map-pixel, and resolution-independent. At fixed pitch and FOV it scales
  linearly with height, which is why every preset varies only height.
- **Pixel density** is *buffer pixels per tile*. Set by render scale alone. The
  reference's 7.5 needs a ~384-wide buffer at this framing; a native 960-wide buffer
  gives 18, the ground stops being minified, and the look goes with it.

### Yaw is fixed at 0

A painted map has one baked light direction and upright icons, so rotating it breaks
both. Fixing yaw is also what allows roads and settlements to be composited into the
region PNG instead of existing as separate meshes. Orbit belongs to the battle camera;
it is not coming here for parity.

### The region-size constraint

The far edge of the frame is `R` times wider than the near edge, so:

```
region_width_in_tiles  ≥  tiles_across_bottom × R
```

At the reference framing that is `53 × 2.89 ≈ 155` tiles — a **2480 px** wide region.
This multiplies; it is not a margin you add. It is also **not fixable with fog**: the
void appears at a fixed depth set by region width and FOV, and at the reference framing
that depth is already nearer than the bottom of the screen, so no fog band reaches it.
The only levers are a larger region or a closer camera.

The first region, `temp` at 48×64 tiles, is roughly a third of what the reference framing
needs. Its plane edges showing is expected, and the `fit` preset exists for it.

## 4. The ground material

One custom spatial shader, `assets/shaders/worldmap_ground.gdshader`, `unshaded`.

**Fog is computed in the shader, never by a `WorldEnvironment`.** Godot 4 skips
environment fog on unshaded materials, so routing it there produces either no fog or a
lit ground. It also keeps the map's haze from being coupled to whatever environment the
battle scene wants.

Pass order is fixed:

1. Sample the region texture.
2. Darken by the cast-shadow and cloud-shadow masks, unioned with `max` and snapped to the
   region's palette -- see §10 and §12. (Not a plain multiply: that described the procedural
   cloud noise this shader no longer carries.)
3. Apply the day's light tint, withheld wherever a lamp reaches -- see §10.
4. Blend toward the fog colour by planar depth.
5. Substitute the void colour where the sample falls outside the region rectangle.

The depth the fog uses is the **ground-plane forward distance** — how far the fragment lies
ahead of the camera along the ground — and specifically *not* the view-space depth along the
camera's tilted forward axis. At pitch 60 those differ by about 3x: a fragment at the bottom
of the frame is 21 units forward along the ground but 68 along the view axis. Every fog
number was tuned against the former, so using view depth fogs the entire frame and halves
the gradient's range. Yaw is pinned to 0, so the ground distance is exactly the world-Z
difference. It is also planar rather than radial, because each screen row of this rig is a
constant ground distance — planar depth keeps the haze a horizontal band instead of bulging at the screen
edges. The void is *substituted* rather than blended so an off-map fragment never carries
a smeared edge texel, and it is placed after fog so a fogged region edge stays soft while
an unfogged one reads as a hard plane edge, which is what the reference does.

The fog blend happens in **gamma space, not linear**. This is a deliberate departure from
physical correctness: the framing and fog numbers were tuned in an 8-bit sRGB explorer
against console captures, and the hardware being imitated blended in gamma space too.
Blending the same fog fraction in linear space lands visibly lighter — about 0.50 against
0.39 on a mid green at 29% fog — so a linear blend silently invalidates every tuned number.

The plane is deliberately **larger than the region** so fog has somewhere to close before
the art runs out. `region_origin` and `region_size` say where the art sits on it.

**Curvature** is `y = -k·d²` in view space, applied in the vertex stage. Zero is flat and
is the reference; non-zero pulls the horizon nearer and makes the world fall away. The
texture lookup uses the *undisplaced* world position, because the bend is a visual effect
and the map coordinates must not move with it.

**Cloud shadows** default to off. They are in the shader because the debug scene must be
able to explore them, and because they are the cheapest thing that makes a static map
feel alive. The noise is generated in the shader rather than sampled: no particular cloud
shape has been asked for, and a texture would be one more asset to keep in step with the
region art.

`cloud_scale` is **world units per noise cell, and is bounded above by the region size**,
not by taste. The cover function needs several cells across the visible ground to read as
cloud rather than as a flat tint, so past roughly a third of the region's width it does
nothing at all. Measured on the 48-tile region: usable to ~16, negligible by 40, and
exactly zero by 80. The default is 12. This is a real trap when porting numbers from the
HTML explorer, whose noise used a different coordinate convention -- a value of 40 came
across and silently did nothing.

### What lies beyond the edge belongs to the region

`fog_color` and `void_color` are owned by the **region**, not the framing. What lies past a
map's edge and the haze it fades into are properties of the place: `temp`'s sea is deep blue,
`temp2`'s is teal, and one framing applied to both would give one of them the wrong void.
They are declared in `data/worldmap/regions.json` and are deliberately absent from
`Uniforms.DEFAULTS`, so `complete()` leaves them unset and `completeForRegion()` fills them.
That absence is what makes "the region's, unless the framing says otherwise" expressible at
all. Precedence runs **region -> preset -> explicit override**, so the CRT preset keeps its
own fog colour while every other preset inherits the place's.

Setting a region's void to its **own sea colour** is what removes the map's edge: the world
reads as ocean continuing into the haze rather than a slab floating in a void. This is the
answer to "what goes behind the map", and it is why the backdrop below is off by default.

### The backdrop

Wherever the ground stops, a backdrop can show through. It is a **quad parented to the
camera**, sized to fill the frustum at 2000 units -- far beyond any ground plane the rig
builds, well inside the camera's 4000 unit far plane. A flat backdrop rather than a dome is
enough because yaw is pinned to 0 and the camera never rolls, so the sky can only ever be
seen from one direction. Offset and zoom happen in UV, so the quad always fills the frame
exactly and only the image slides inside it.

It is deliberately **not** a `WorldEnvironment` sky, for the same reason the fog is not
environment fog: introducing an environment purely for a background would couple the world
map's sky to the battle scene's, for no gain.

**Enabling a backdrop makes the ground discard its off-map fragments** rather than paint the
void colour. This is not optional -- the plane is far larger than the region, so its fogged
void otherwise sits in front of the sky and hides everything except the strip above the
plane's own edge. With the backdrop off, the void colour behaves exactly as before.

Skies live in `WorldMapSkyCatalog`, a flat list rather than a JSON catalog because there are
two of them and they are chosen by eye. If skies ever become per-region or per-time-of-day
it should move to `data/worldmap/` beside the regions, in the same shape.

`temp2_sunset` is `Skies2.png` recoloured onto region `temp2`'s own seven colours: upper sky
and muted bands to its dark teal, the bright band to its sea teal, the sun to its orange, the
lower field to its sand. Every destination colour is one the region actually uses, so a
backdrop cannot drift off-palette from the map in front of it. That constraint is worth
keeping for any future sky.

### Filtering, and why the sparkle is kept

On this project the pixel noise and optical artefacts are wanted. The question is not how
to stop the shimmer but **how to render so it reads as texture rather than as a bug**,
and the lever for that is render scale, not filtering. A low internal buffer makes
aliasing coherent and chunky; a native buffer with nearest filtering makes it fine-grained
and twitchy, which is the version that reads as broken.

Filtering still matters at the margin, because the near ground is magnified — one map
pixel covering several screen pixels, where there is no mip level to choose — while the
mid-distance minifies. `filter_mode` selects between three sampler uniforms bound to the
same texture, because Godot resolves filtering from the uniform hint at compile time and
a hint cannot be changed from GDScript:

| mode | filtering | use |
|------|-----------|-----|
| 0 | nearest, no mipmaps | maximum sparkle; what the reference does. **Default** |
| 1 | nearest + mipmap + anisotropic | crisp magnified, stable minified; measurably softer |
| 2 | linear + mipmap + anisotropic | smooth; the comparison, not the target |

Mode 0 is the default because it is what the explorer's reference preset used, and matching
it is the point. Measured as mean adjacent-pixel difference at `tile_exact`: mode 0 scores
12.04 against the explorer's 12.02, while mode 1 scores 7.70 — a third less sharp. Mode 1 is
the right answer if the far-field sparkle ever becomes a problem, but on this project the
sparkle is wanted, so it costs more than it buys.

Region textures import with **nearest filtering and mipmaps generated**. Godot's importer
defaults to linear with mipmaps off, which is exactly backwards for this rig: the near
ground goes soft and the far ground has nothing to fall back on.

### Pre-stretching: rejected

A top-down map compresses vertically by `sin(pitch)`, so a circular lake reads as an
ellipse. It can be compensated by pre-stretching the source art by `1/sin(pitch)`.

At pitch 60 that factor is **1.15×** — small enough that pre-stretching buys almost
nothing, while still costing a non-square source texture and locking the art to one pitch
forever. **Accept the squash.** Whoever draws a region should know vertical distances
compress by about 13%, and anything that must read as a specific shape is worth checking
in the explorer before the art is finished.

## 5. The framing contract

A framing is a plain `Dictionary`, not a `Resource`: the debug scene builds one per frame
from live controls, and a preset that omits a key should inherit the default rather than
carry a null. Presets are authored as a diff against `DEFAULTS` and merged with
`WorldMapGroundUniforms.complete()`; never index a raw preset.

`WorldMapGroundUniforms` holds every uniform name and framing key as a constant, and it
is the reason four files can be written independently. `set_shader_parameter()` on a name
the shader does not declare is a **no-op, not an error**, so a misspelling anywhere in
that chain fails silently — go through the constants.

The split of responsibility:

| | owns |
|---|---|
| `WorldMapGroundUniforms` | key and uniform spellings, defaults, ground-half application |
| `WorldMapFramingCatalog` | the named presets, as diffs against defaults |
| `WorldMapGround` | the plane mesh, sized from a region |
| `WorldMapCameraRig` | pitch/FOV/height/pan, and the derived readout numbers |

Yaw is absent from the framing keys on purpose. It is pinned to 0 and is not a choice.

## 6. Validated

Checked against the running game with frames read back from a `SubViewport`, so each of
these is a pixel test rather than the arithmetic that produced it:

- Every one of the seven presets renders; none produces a flat frame.
- Haze, curvature and cloud shadows each change the frame independently, and no
  `WorldEnvironment` is involved anywhere.
- The `fit` preset shows no void panning to all four region corners and the centre. The
  negative control passes too: `tile_exact` shows ~17k void pixels on the same region, as
  the region-size constraint predicts, so the test is capable of failing.
- Region `temp` loads by id and its declared 48x64 tiles match its 768x1024 texture.
- The debug scene's dropdown and `--preset=` produce identical readouts for all seven.
- The ground material's transfer function is **exact**: five swatches, saturated green and
  blue among them, render back at precisely their source values with fog off. There is no
  colour-space error in the rig.

`WorldMapCameraRig`'s framing maths reproduces the HTML explorer independently -- 53.26
tiles across, 7.21 buffer px per tile, ratio 2.906, 155 tiles of region needed -- so two
implementations of the same trigonometry agree.

### Verified against the explorer

The game render and `debug/worldmap/worldmap-framing.html` were compared band by band at
identical settings — same region, same 384x216 buffer, camera positions matching to 0.01.
Mean per-band channel error across six horizontal bands went **266 -> 74 -> ~1** as the two
defects above were fixed. All seven presets now agree with the explorer to within 1/255.

Two differences remain and are deliberate, each confirmed by isolating it:

- **`filtered` differs by ~5-9 per channel**, entirely because of the cloud layer. With
  clouds off it matches exactly. The shader generates noise procedurally; the explorer
  samples a precomputed tile. Different noise, different mean cover — not a defect.
- **`overview` differs at the top of the frame**, entirely because of the camera's focus
  clamp. The explorer has no clamp; the rig pushes the focus back to keep void off screen
  (from z=32 to z=35.6 at that framing). Unclamped, the two match exactly.

Re-deriving these numbers is one command each: `probe_allpresets.gd` in the game, and the
band-signature snippet against the explorer's internal buffer.

## 7. Rejected: a sky behind the map

Tried 2026-09-01 and rejected. The backdrop exists and works, but is **off by default** and
should stay that way except at a shallow framing.

The reason is geometric, not technical. Every framing in use has pitch 40-60 degrees against
a FOV of 20-25, so `pitch >> fov/2` and **every ray in the frustum points downward** -- the
mathematical horizon sits above the top of the frame at all times, which is section 2 of this
note and what the debug readout reports on every screenshot. There is no direction in which
the camera sees sky. What lies beyond the map's edge is not sky, it is off the edge of the
world, and painting a sunset there reads as a slab lying on a poster.

Measured across seven framings spanning heavy zoom to pulled back and curvature 0 to 0.003:
the ground's far edge lands anywhere from **0% to 44%** down the frame, while a
camera-parented backdrop's horizon is pinned at 45%. They agreed twice, by coincidence.

**A cube or a sphere would not fix this.** A skybox is the right tool when the camera can
look at the sky; here it would render exactly what a flat quad renders -- whichever part of
it falls below the horizon -- for more geometry and a dome to maintain. The mismatch is not
caused by the backdrop's shape.

The answer is not to put something behind the map but to **extend the map**: give the region
a void colour equal to its own sea, and let the fog close the distance. Verified at every
framing, because there is no second element that has to agree with the camera.

## 8. Rejected: 2.5D depth for the ground

Explored 2026-09-01 and **rejected in full**. The map stays flat. Eleven approaches were
built and rendered against the real region art; the sketch is
`docs/sketches/2026-09-01-worldmap-2p5d-options-rejected.html`.

What failed, and why, so none of it is re-proposed from reasoning alone:

- **Per-tile extrusion.** Quantising organic mountain blobs to the 16 px tile grid turns
  them into a staircase of cubes.
- **Tile-grid billboards.** The objects in this art are 10-40 px and do not align to tiles,
  so cutting sprites on tile boundaries slices straight through them.
- **Parallax offset.** Shears the texture rather than lifting it, and at the Overland
  framing's 40.5 degree pitch it scores *below* plain contact shadows. Its worst case is
  exactly the framing in use.
- **Contact shadow ellipses.** Read as smudges under objects, not as contact.
- **Normal-map relief** from a mask-derived height field, and **connected-component sprites
  stood upright** in the manner of the Pokemon GBC decomps, both got much closer and were
  still rejected on look.

One measurement worth keeping from it: a metric that reports *how much* a frame changed
says nothing about whether the change is good. Ranking these options by mean pixel
difference put the cube extrusion first, and it was the worst of them.

An observation about the art worth keeping too: every object in the region PNG is already
drawn in **oblique view with a top and a front** -- each mountain has a pale lit crest above
a dark body, the fort a light roof over a battlemented wall. That is why the map reads as
having depth while lying perfectly flat, and it is the reason flat is the right answer here.

## 9. Standing structures

Buildings painted into a region's ground art can be lifted out and stood back up as
billboarded sprites. `WorldMapProps` does it, `WorldMapDebugHud`'s Structures section
selects the mode, and the sketch is
`docs/sketches/2026-09-02-worldmap-standing-structures-and-daylight.html`.

This is not a reversal of section 8. That rejected standing up *everything* -- mountains and
trees included -- and failed because those are organic blobs drawn in oblique view. Buildings
are a different case: small, rectangular, and already drawn as **front elevations**. A house
on temp2 is a teal upper wall with three windows over a white wall with an orange door, and
there is no roof in the image at all, so tipping it upright shows it at the angle it was
painted for.

### The squash is not cos(pitch)

The load-bearing correction. A world-vertical quad seen from a camera pitched down by `p` is
squashed, and the obvious guess -- one factor `cos p` for the whole frame -- is wrong. For a
sprite of world height `h` and width `W` at ground distance `f`:

    hpx / wpx = (h/W) * f / (D - h*sin p),    D = H*sin p + f*cos p

so the squash is `f/D`: **zero at the camera's feet, `1/cos p` far away, and exactly `cos p`
at the centre of the frame and nowhere else.** Measured on Curved Close it runs **0.33 at the
near edge to 0.76 at the far edge** -- a 2.3x swing inside one frame. A single global gain
therefore cannot be right anywhere but the middle: applied as `1/cos p` it left the near house
at `h/w 0.931` and the far one at `1.291` against a painted `0.875`.

### The three modes are two answers, and they are the same rectangle

| Mode | What it does | Cost |
|---|---|---|
| `world` | Nothing. The uncorrected baseline. | Up to **52.5%** aspect error across one frame. |
| `gain` | Solves the identity per sprite for the height that lands on painted proportions. | The object is genuinely taller in world space, by a factor that changes as the camera moves. |
| `face` | Godot's `BILLBOARD_ENABLED`. | The quad's top leans away by `h sin p`, claiming ground it is not standing on. |

`face` works because putting the camera's up-axis into the identity gives `A = 1, B = 0`, so
`hpx/wpx = h/W` exactly, at every distance and every pitch, with no correction term. That,
not "it cancels cos p", is why it is the robust answer -- and with yaw pinned, Godot's own
billboard *is* that case, so the engine does it correctly for free.

**Measured, the two converge completely.** In the sketch every sprite corner agrees to
**0.00 px at every pitch tested**; in the engine `probe_props.gd` reports **0.00% worst
aspect error** across all nine structures for `gain`. They are not similar, they are the same
rectangle, by construction: same base, same width, same forced `h/w`. They differ only in
what they claim about world space, and neither claim is observable while sprites are the only
3D thing in the scene. **Prefer `face`** -- it needs no per-object solve and no per-frame
update.

Two traps found while porting, both of which pass silently:

- The correction is **not bounded below by 1**. Past the frame centre a vertical quad is
  magnified rather than squashed, so far sprites are corrected *downward*. Clamping at 1.0
  leaves everything beyond the middle of the frame too tall -- the same defect the mode
  exists to remove.
- Curvature must **carry** a sprite, not deform it. The projection applies the drop `k*d^2`
  per point from that point's own distance, which is right for the ground -- the ground *is*
  the curved surface -- and wrong for anything standing on it. The whole quad takes the drop
  belonging to its base.

### Finding structures does not generalise, and trees never will

The extractor is a **bootstrap for temp2, not a pipeline**, and this was measured rather than
assumed. `probe_segmentation_limits.gd` runs the identical colour key over both regions:

| | temp2 | temp |
|---|---|---|
| palette | 7 colours | 1080 colours |
| components found | 9 | 302 |
| distinct box shapes | 2 | 10 |
| median component | 50 px | 1 px |
| components of <= 4 px | 0 (0%) | 283 (94%) |

Nine-out-of-nine on temp2 is a property of *that map's palette*: three of its seven colours
appear nowhere but on buildings. temp is dithered, no colour in it is exclusive, and the same
rule returns 302 blobs of which 94% are noise.

Trees are worse and cannot work at all. A tree is made of the same pigment as the vegetation
it stands in. Bucketing every green pixel on temp by its green channel
(`probe_tree_key.gd`) gives one continuous population -- 9k/34k/26k/14k/24k/236k/123k/12k --
with **no trough to threshold at**. Any cut that catches trees takes a slab of grass with it.

**The answer is to author it, not detect it.** Give a region a second image the same size, a
prop layer, transparent except where props sit, with the ground painted complete underneath.
Extraction becomes exact instead of inferred, it works for trees, and the ground-patch
guesswork disappears because the artist painted what is under the house. Everything below the
extraction -- the billboard maths, the anchoring, the atlas -- is indifferent to where the
sprite list came from.

### One shader, not Sprite3D

Props are drawn by `worldmap_prop.gdshader` on a quad, not by `Sprite3D`. Sprite3D gives
billboarding away free, which is what made `face` cheap -- but its material cannot be replaced
without losing that, so `gain` had to be a CPU pass rescaling every sprite every frame, and
there was nowhere to put fog at all. Props therefore did not fog while the ground did.

All three modes now live in the vertex stage and the CPU pass is gone. The fog is a
transcription of the ground shader's, including both of its deliberate departures from the
obvious -- ground-plane distance rather than view-space depth, and a gamma-space blend. If the
ground's fog changes, this must change with it.

Two things caught while porting, neither of which announces itself:

- **The camera's basis is in `INV_VIEW_MATRIX`, not `VIEW_MATRIX`.** `VIEW_MATRIX` is the
  world-to-view transform and its columns are not the camera's axes. Taking `sin(pitch)` from
  the wrong one still produces a plausible-looking sprite.
- **Measuring a vertical sprite's width from its bounding box measures the lean, not the
  proportions.** A world-vertical quad seen from above has its top edge nearer the camera, so
  the top projects wider than the base and the box width is the top width. Compared against
  the vertical extent that made a *correct* `gain` sprite look 23% wrong. The width has to come
  from the projection -- one tile at the prop's base -- or from the foot row.

Measured end to end by `probe_props.gd`, rendering each prop alone and reading its pixels:
`world` 28-33% off painted proportions, `gain` and `face` both **1.2% worst**, and identical
to each other at 63/37/37 px. `probe_prop_fog.gd` closes the fog and watches the prop-to-ground
colour gap halve, 1.236 to 0.598.

### Known gaps

- **The art carries a black outline** that was drawn to read on a flat top-down sprite. Stood
  up and magnified it becomes a bold vertical bar down each side of every building. That is an
  art decision, not a rendering one.
- **The day/night sun and cast shadows exist only in the sketch.** See section 10.

## 10. Daylight, cast shadows and lamps

In the engine. `WorldMapSun` turns a time of day into a direction, a colour and a shear;
`WorldMapShadowMask` renders the results into a mask in map space; the ground and prop shaders
read it. The sketch that settled it is
`docs/sketches/2026-09-02-worldmap-standing-structures-and-daylight.html`.

### Shadows live in map-pixel space

The representation is the whole decision. A screen-space shadow quad is what a 3D engine makes
easy and it **cannot** be made to read as pixel art at any edge treatment: its edge lands at
arbitrary sub-pixel positions and angles that do not align to the map's grid, and it crawls
under camera motion.

A shadow lies on the ground plane, and **map space is the ground plane**, so the shear is a
plain 2D affine in map pixels with no 3D projection anywhere. Four properties then fall out
rather than needing to be built: edges land on exact map pixels; fog, curvature and filtering
come free because the mask rides the ground's own sample; crossing shadows form a union because
every shadow writes at full value; and the mask is 44k pixels that only change when the sun
moves. Shadow and lamp share one texture -- R and G -- because they are the same mechanism seen
twice.

### The sun keeps two elevations

`lit` reaches zero at both ends of the day and drives light colour, lamps and shadow opacity.
`elevation` never drops below `sun_low` and is what the shadow GEOMETRY uses, because
`cot(elevation)` runs away at the horizon. Measured, for a 0.88-tile house:

| `sun_low` | 10 deg | 18 deg | 22 deg | **27 deg** | 32 deg | 40 deg |
|---|---|---|---|---|---|---|
| longest shadow | 3.50 | 2.60 | 2.11 | **1.68** | 1.38 | 1.03 tiles |

The azimuth sweeps a narrow arc about due north rather than the full semicircle. A full sweep
puts the sun due east at dawn, and a shadow cast from due east points due *west* -- sideways
across the screen with no northward component at all.

### What alignment does not answer

Three questions remain once the mask is pixel-aligned, and they were decided by measurement
and by looking.

**What colour is a shadowed pixel.** `multiply` darkens arithmetically and puts **10 distinct
colours on screen for a 7-colour map** -- it invents three. `palette` snaps the darkened result
to the nearest colour the art actually uses and holds at **7**. Looked at, the difference is
not subtle: multiply gives a muddy brown-grey smear, while palette turns a shadow on sand into
the map's own darker orange and it reads as painted terrain. **Palette is the default.** Its
cost is real and worth knowing: **3 of temp2's 7 colours collapse onto a shared shadowed
colour**, so where a shadow crosses those terrain boundaries the boundary disappears. The
palette is read from the region texture at load rather than declared, because the palette *is*
whatever was painted and a hand-kept list drifts from the PNG silently.

**What happens at the edge.** At map-pixel resolution `hard` is already a pixel edge, which is
a far stronger position than it was in screen space -- there are no gradients anywhere else in
this art. `dither` feathers the outer boundary with an ordered pattern anchored to MAP pixels,
removing about 37% of the shadow's pixels (565 to 355 on temp2). It dithers only near the
border; applied across the whole shadow it checkerboards the lot and reads as noise.

**How it moves.** The one that decides whether it looks *consistent*, and it has no analogue in
a still. Walking the sun in four-minute ticks and counting mask pixels that change:

| sun headings | mean pixels changed per tick | ticks that changed at all |
|---|---|---|
| continuous | 10.7 | 21/23 |
| 64 | 22.0 | 17/23 |
| 32 | 12.1 | 14/23 |
| **16** | **9.5** | **13/23** |

Quantising the heading trades frequency for size: the mask changes on fewer ticks but jumps
further when it does. 16 is the default. The residual motion is the shadow's **length**, which
is deliberately left continuous -- it changes slowly, and quantising it makes shadows visibly
pop in and out as the sun climbs.

### Lamps are subtractive

A lamp is a circular region where the night is **not applied**, so the ground keeps its daytime
colours. Nothing in that path can produce a colour the art does not contain. Measured, no
subtractive shape pushes a single pixel past what full daylight gave it, and none clips.

**There is deliberately no additive mode in the engine.** The sketch keeps one, because seeing
warm light painted on top is what makes the subtractive choice legible; shipping one here would
ship the thing this rejected.

Overlapping lamps combine with **max, not sum** -- two lamps light a wider area, not a brighter
one, and summing is what blows a cluster out to white. The shapes differ measurably: hard 8496,
band 2702, dither 2708, smooth 2536 lit map px.

**The buildings inside a lit circle are lit too**, from the same field and the same function as
the ground. Mean building colour at 22:00: **0.382 unlit, 0.550 lit, against 0.523 in full
daylight**. A building standing in its own pool of light must not be the one dark thing in it.

Ring sizing: `lamp_core` holds a fraction of the radius at full brightness and the remaining
levels split what is left. The outer boundary does not move, so growing the core trades width
away from the middle rings rather than from the light's reach -- 8/15/9 px at core 0, 16/10/6
at 0.35, both spanning 32 px.

### What the day cycle still cannot do

**The art has its lighting baked in.** Cast shadows move and the overall colour moves, but the
shading on a building's own face does not. Fixing that means per-direction sprites or a normal
map per prop, and the relief experiment of 2026-09-01 is a reason to be careful about the
second.

## 11. Validated

Every claim in sections 9 and 10 is checked by a probe in `debug/worldmap/`, and each is
written so it can fail. Run them together when touching this rig:

| Probe | What it holds | Needs a renderer |
|---|---|---|
| `probe_prop_layer.gd` | temp2 finds 9 structures in 2 shapes from region data; temp declares none and finds none | no |
| `probe_sun.gd` | northward component never negative; geometric elevation never below `sun_low`; the `sun_low` table matches the sketch | no |
| `probe_shadows.gd` | silhouette solid; feet planted at every hour; mask values only 0 and 1 | no |
| `probe_props.gd` | `world` 51% off painted proportions, `gain` and `face` 1.2% | yes |
| `probe_prop_fog.gd` | prop-to-ground colour gap halves as fog closes | yes |
| `probe_lamps.gd` | no shape exceeds daylight or clips; shapes produce different lit areas; buildings lit by their own lamps | yes |
| `probe_shadow_look.gd` | palette mode holds 7 colours against multiply's 10; quantised headings change on fewer ticks | yes |

`probe_validation.gd` still passes its original 18 checks, negative control included.

Three of these were rewritten after they passed while measuring nothing, which is the failure
mode worth guarding against here:

- `probe_props.gd` compared a sprite's height against its **bounding-box** width, which on a
  world-vertical quad is the *top* width and measures the lean. It reported a correct `gain`
  sprite as 23% wrong and sent me hunting a shader bug that did not exist.
- `probe_lamps.gd` first counted pixels brighter than daylight across the whole frame and got
  777 for every mode alike, including the control. Those were the emissive windows, which are
  supposed to be brighter. The claim is about the ground, so the props are hidden for it.
- `probe_shadows.gd` read the mask through `ImageTexture.get_image()`, which does not reliably
  reflect an in-place `update()`. Coverage came back identical at three different sun angles.

## 12. World map clouds

In the engine. `WorldMapCloudField` derives placement, wind and each shadow's offset;
`WorldMapClouds` stands the art up at altitude; `WorldMapCloudShadows` renders their shadows
into a mask in map space, read by the ground and prop shaders alongside the cast-shadow mask.
The sketch that opened it is `docs/sketches/2026-09-04-worldmap-clouds.html`; it was extended,
not fully superseded -- see below for what it got right and what the art corrected.

### A cloud is a horizontal sprite at altitude

The ground is real geometry viewed at a steep pitch, so a flat quad parallel to it gets the
camera's own perspective and parallax for nothing -- no separate projection, no scroll hack.
Measured over a 4-unit pan against a ground that moved 26.97 px: a cloud at altitude 3 slides
0.60 px further, at 6 it is 1.21 px further, at 12 it is 2.50 px, at 24 it is 5.17 px --
monotone in altitude, as the geometry requires.

Its shadow lands on the ground by the same relation the standing structures use,
`altitude x cot(sun elevation)`, opposite the sun, with altitude standing in for a building's
height. It is unclamped, unlike the buildings' own `shadow_step`: that value carries a
`sun_reach` limit meant to stop a *building* becoming a twenty-tile scratch, and a cloud's
shadow being far from its cloud at a low sun is correct rather than a defect to clamp away.

### The art fixed two things the plan had guessed at

**The display scale is not a free slider.** Every piece in the supplied sheet resolves to
whole 8x8 px blocks under a 1 px outline -- the only cells that are not one flat colour are the
ten the outline steps through. That pins the scale at exactly 1:1 against map pixels: 88x40,
which on temp2's 8 px tiles is 11x5 tiles. At any other scale the blocks stop being square and
the outline stops being one pixel wide, and at a fractional scale the palette goes with them.
The console's Size control takes a whole multiple of native rather than a free width in tiles.

**Each shadow is drawn, not scaled from its cloud.** Shadow A is cloud A with its top two
block-rows narrowed and shifted; shadow B is cloud B a full row shorter with its top widened --
foreshortening applied by hand, differently to each shape. A `spread` factor scaling a shadow
against its cloud, which both the plan and the sketch carried, would only have resampled by
approximation what the artist had already done exactly. It does not exist in the engine.

### The shadow's colour is not a taste setting

The supplied shadow art is painted in `0b696a` and `e69900` -- temp2's own shadowed sea and
shadowed sand. The artist reached the same conclusion the standing structures' shadows did: a
shadow is shadowed *terrain*, not a translucent overlay, so a fixed-colour shadow sprite is
only correct over the terrain it was painted for. The engine therefore takes the art for its
*shape* only -- a coverage mask, white on black -- and derives the colour by darkening the
ground and snapping to its own palette, the same mechanism the cast shadows use.

Darkening a palette colour and snapping it back reproduces the artist's exact two colours for
every shade from 0.25 to 0.50:

| shade | `37aeae` (sea) becomes | `ffd363` (sand) becomes |
|---|---|---|
| 0.20 | `37aeae` (no change) | `ffd363` (no change) |
| **0.25** | `0b696a` -- matches the art | `e69900` -- matches the art |
| **0.40 (default)** | `0b696a` | `e69900` |
| 0.50 | `0b696a` | `e69900` |
| 0.55 | `0b696a` | `0b696a` -- sand collapses onto sea |
| 0.70 | `021500` | `021500` -- both to near-black |

The default sits in the middle of the band the derivation and the art agree on. Above 0.55 the
shadow stops distinguishing sand from sea, which is the ceiling a "how dark" slider has to
respect rather than a number chosen by eye.

Cast and cloud shadows combine with **max, not sum**, and the combined result takes one
darkening pass and one snap -- the same reasoning the lamps use. A building already in its own
shadow does not get darker again for standing under a cloud too; summing would land the result
between two palette entries and force the snap to guess. Measured with both active at once: 0
pixels off temp2's seven-colour palette.

### Softness dithers; it does not blur

The art's alpha is binary -- 55,872 fully clear pixels, 9,664 fully opaque, zero partial -- so
any softness has to be invented at render time. A blur is not available: it produces colours
between the palette's entries, which is the entire reason the snap exists. Softness is instead
an ordered dither on the coverage mask's edge, anchored to `floor(uv * map_size)` in **map**
pixels (never screen pixels, or the pattern swims under a panning camera), reusing the same
4x4 Bayer matrix the lamps already carry. It is confined to a band at the boundary -- applied
across the whole shape it checkerboards the entire shadow, which an earlier pass of this
mechanism did once before being confined. At 3 px of dither the shadow loses area rather than
fading, and stays at 0 pixels off palette.

### Cloud shadows reach the standing structures too

A cloud sliding under a building without darkening it is the same seam the subtractive lamps
exist to remove on the night side -- the ground moves and the thing standing on it does not,
which reads as a cutout. The prop shader samples the cloud mask **once, at the prop's base**,
in the vertex stage, and applies it flatly across the whole quad -- the same treatment
`prop_fog` already gets, for the same reason: a standing sprite occupies map pixels it is not
actually standing on, so a per-fragment lookup would sample whatever the building happens to
stand in front of and stripe the sprite with shadow that belongs to the background.

Measured, in de-gamma'd linear luminance across a seed sweep that put a single cloud's shadow
over a known tower and then away from it: the prop's mean brightness dropped 0.2611 on covered
trials against clear ones, the ground immediately beside its foot dropped 0.1684 -- both
positive, moving together. Eleven of twelve trials matched the shader's own linear multiply to
within 0.003; the twelfth is a genuine boundary case, not a defect -- the check reads coverage
at an integer map pixel while the shader samples by continuous UV, and within about one texel
of a shadow's own edge the two can legitimately land on different texels.

### Placement is a jittered lattice sized from the art, not a fixed grid

The visible slice of a plane at altitude is smaller than the visible ground -- the cloud ray is
`camera_height - altitude` long rather than `camera_height` -- so uniform-random placement can
leave the sky measurably "covered" while nothing is actually on screen. The field is instead a
lattice whose cell size comes from the cloud's own native size, so cells are never smaller than
what they hold; for temp2 that is 3x5 cells over a 336x216 extent (the region plus one cloud of
margin on each axis), a capacity of fifteen. Cells are drawn in a seeded shuffled order, so
lowering the count scatters the remaining clouds rather than emptying the lattice from one edge.

The wrap seam sits at that margin, not at the region's own edge -- wrapping over the region
itself would put a cloud's re-entry at an edge the camera is already looking at, and temp2 is
small enough that both edges are commonly on screen together.

### Validated

- Clouds appear in all nine shipped framing presets, at their own height and pitch, with a
  full field (fifteen clouds). Every combination in a curvature x height x pitch sweep that
  left the camera with any geometric room above the ground it aims at drew its clouds; every
  loss was traced to zero clouds projecting into the frame at all -- a camera-placement fact,
  not a culling defect -- and none was traced to the `extra_cull_margin` guard.
- `probe_cloud_art.gd`: the sheet lands on exactly temp2's seven colours (0 px off), alpha is
  binary, all four pieces are intact at their declared rects, and each shadow is verified as
  drawn rather than copied from its cloud's silhouette.
- `probe_cloud_field.gd`: parallax, shadow linearity in altitude, mirror symmetry about noon,
  no shadow with the sun down, determinism from a seed, and continuity across 138 observed
  wraps in a 600-second walk -- all measured, none assumed.
- `probe_clouds.gd`: 0 pixels off palette with cast and cloud shadows both active; the removed
  noise system is confirmed gone by a grep audit across six files, not merely by a passing test.
- `probe_cloud_on_props.gd`: the prop/ground correlation above, plus the palette-derived
  discovery that `WorldMapProps` had been reading the region's palette only after its early
  returns -- meaning a cloud shadow with the default billboard mode (`off`, no structures)
  degraded silently to arithmetic darkening and put 27,508 pixels off palette. Fixed in the
  same item that found it, since it is upstream of everything WMC-4 and WMC-5 measure.

### What this closing pass actually looked at

Every number above was measured before this pass began. What had not happened is anyone
looking at a render -- the sketch's own author never saw one composite. Eight framed
screenshots and a tight before/after crop on a shadowed tower were rendered and inspected
directly for this section, resolving that gap:

- The overview at Tile-Exact reads as intended: clouds sit visibly above the terrain, their
  shadows are legible dark patches rather than a wash, and the shadow's position visibly
  differs between 08:00 and 12:00.
- The softness dither is subtle and reads as a broken-up edge rather than a smear, consistent
  with the rest of the map's hard-edged pixel art.
- The palette cost of a translucent cloud *body* (17 colours, 27,508 px off palette at the
  default 0.85 opacity, against 0 at full opacity) is real by the numbers and close to
  invisible by eye at this frame size -- a case where the measured defect and the visual one
  diverge, worth knowing for whoever tunes the default next.
- The cloud-on-prop effect is visible without instrumentation: the same tower reads
  perceptibly greyer in the "covered" crop than in the "clear" one, at the same camera
  position, same time of day, same everything but the one cloud's seed.
- **Not fixed, and worth flagging rather than silently accepting:** at Curved Close and Closer,
  a single native-scale cloud spans roughly a third to a half of the frame's width, and its own
  body can sit close enough to structures to partly occlude them rather than just shadow them.
  The fixed native scale that WMC-1 established is correct for the art and correct for
  Tile-Exact; it was never tested against a close framing until this pass looked at one. See
  "Open".

## 13. Open

- The region id `temp` is a placeholder. Naming it is a lore question.
- Whether the camera eases between a close travelling framing and a pulled-back planning
  one by context, rather than sitting at one height, is unresolved. If travel time is a
  resource the player needs a view that shows where the roads go, and the reference framing
  is not that view.
- Whether region art will be produced at the ~155-tile width the reference framing needs,
  or whether the camera commits to something closer. This is a real design choice, not only
  a texture budget: it changes how much of the world the player can weigh at once when
  deciding where to spend travel time.
- **A single native-scale cloud dominates a close framing.** At Curved Close and Closer it
  spans roughly a third to a half of the frame's width and its body can sit near enough to a
  structure to partly occlude it rather than just shadow it -- found by actually looking at a
  render while closing the clouds cycle, not by any measurement in it. The fixed native scale
  is correct for the art and correct at Tile-Exact; nothing in the clouds cycle adjusts count
  or size by framing, and the console's own Count/Size ranges do not currently know a close
  camera is looking. Whichever direction this resolves in -- fewer clouds by default at a
  closer framing, a size ceiling tied to the frame, or leaving it as weather that is simply
  large up close -- it is a judgement, not a bug, and belongs to whoever next tunes the
  presets.
- **`WorldMapCameraRig._curveDropAtFocus()` overshoots badly at higher curvature**, surfaced
  while adding clouds and not fixed in that cycle. It estimates the ground's drop from the
  camera's *nominal* view depth before the camera has moved to compensate for it; at
  `curvature 0.012, height 90, pitch 45` the estimate is 104.4 units against a real drop of
  0.7, which puts the camera 104 units below the ground it is aiming at and renders an empty
  frame. `curve_fold` does not catch it -- it reads 0.63 for that framing, well under its own
  1.0 warning threshold, because the fold metric was built to catch the world leaving frame
  from *above*, not the camera ending up *underneath*. The shipped presets are unaffected
  (curvature 0.0008 and 0.0039, far below where the estimate's error becomes visible); this
  only bites a curvature the console's own slider can reach but no preset uses.
