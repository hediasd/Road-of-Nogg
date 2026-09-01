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
2. Multiply by cloud shadow.
3. Blend toward the fog colour by planar depth.
4. Substitute the void colour where the sample falls outside the region rectangle.

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

## 9. Open

- The region id `temp` is a placeholder. Naming it is a lore question.
- Whether the camera eases between a close travelling framing and a pulled-back planning
  one by context, rather than sitting at one height, is unresolved. If travel time is a
  resource the player needs a view that shows where the roads go, and the reference framing
  is not that view.
- Whether region art will be produced at the ~155-tile width the reference framing needs,
  or whether the camera commits to something closer. This is a real design choice, not only
  a texture budget: it changes how much of the world the player can weigh at once when
  deciding where to spend travel time.
