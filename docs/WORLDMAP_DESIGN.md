# World map design

The out-of-battle presentation: a painted region PNG laid on a ground plane in a
`Node3D` scene, viewed from a fixed yaw at a steep pitch, the far distance washing
out into haze. This note covers the **ground rig** — the plane, its material, and the
camera that frames it. Roads, the node graph, travel time, and encounters are not here
yet and are not implied by anything below.

Every number was derived in `debug/worldmap/worldmap-framing.html`, which carries the
live explorer and the reasoning. This note records the conclusions and the contracts.

## 1. The tile convention

Map art is authored on a **16 px tile grid**, and **one tile is one world unit**.

That makes `units_per_map_pixel` exactly `1/16 = 0.0625`, and it makes every other
number in the rig readable as a tile count: a camera height of 66 is 66 tiles up, a fog
end of 116 is 116 tiles of depth, a 768×1024 region is 48×64 tiles. The alternative —
normalising to metres, or matching the battle board's cell size — buys nothing and costs
the ability to check a framing by counting tiles in a screenshot.

Sprites are 16×16 too, and are drawn at **fixed screen size**, not as world-space
billboards. In the reference, units at the top of the frame are no smaller than those at
the bottom, and all of them are drawn far larger than a ground tile at the same depth. A
world-space billboard renders the far party at a third the size of the near one. The
consequence to keep in mind: the party is not really *in* the scene, so anything that
must sit convincingly on the ground — a blob shadow, a road highlight touching its feet
— is positioned in world space even though the sprite it belongs to is not.

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

Planar depth rather than radial, because each screen row of this rig is a constant world
depth — planar depth keeps the haze a horizontal band instead of bulging at the screen
edges. The void is *substituted* rather than blended so an off-map fragment never carries
a smeared edge texel, and it is placed after fog so a fogged region edge stays soft while
an unfogged one reads as a hard plane edge, which is what the reference does.

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
| 0 | nearest, no mipmaps | maximum sparkle; what the low-resolution reference does |
| 1 | nearest + mipmap + anisotropic | crisp magnified, stable minified. **Default** |
| 2 | linear + mipmap + anisotropic | smooth; the comparison, not the target |

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

## 6. Open

- The region id `temp` is a placeholder. Naming it is a lore question.
- Whether the camera eases between a close travelling framing and a pulled-back planning
  one by context, rather than sitting at one height, is unresolved. If travel time is a
  resource the player needs a view that shows where the roads go, and the reference
  framing is not that view.
- Whether region art will be produced at the ~155-tile width the reference framing needs,
  or whether the camera commits to something closer. This is a real design choice, not
  only a texture budget: it changes how much of the world the player can weigh at once
  when deciding where to spend travel time.
