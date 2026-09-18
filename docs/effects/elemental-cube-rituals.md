# Elemental cube rituals

Two source-bound spell placeholders express power channeled from the elemental
realms. They use the same exact-source pixel cube, palette system, generated
rotation atlas, and lifecycle; choreography distinguishes the cast role. Crownburst is the
offensive placeholder. Spiral Invocation is the support and utility
placeholder. A spell with an explicit `VFX_PROFILE` keeps its authored effect.

The shared VFX contract and authoring conventions live in
[`../VFX_DESIGN.md`](../VFX_DESIGN.md).

| profile id | role | choreography | duration |
| --- | --- | --- | --- |
| `elemental_cube_crownburst` | Offensive fallback | Eight cubes accelerate from an inner ring into an even crown, orbit and spin in lockstep, then release outward and down. | 2.10s battle / 5.20s reference |
| `elemental_cube_spiral` | Support and utility fallback | One close train emerges successively from the ground and follows a shared rising helical path before dissolving successively at its top. | 2.10s battle / 5.20s reference |

## Shared visual language

Each ritual builds eight `Sprite3D` cubes at `0.30u` apparent width. Rotation
frame zero is the exact 32x32 Wind cube from `element cubes.png`, stored as a
pixel-role map so all ten accepted palettes retain the same source silhouette,
one-pixel seams, corner accents, and face proportions. Eleven generated frames
complete one 90-degree turn; cubic symmetry repeats that quarter-turn for the
full spin. Every frame is hard-rasterized without antialiasing and uses only
the palette's direct, middle, and shadow colors.

All eight instances share one per-effect `ImageTexture` atlas, use nearest
filtering, remain camera-facing, and cast no shadows. The effect owns no
particles, lights, timers, custom material, or per-cube texture and is capped
at nine nodes, eight geometry instances, and eight draw calls.

The cubes never drift independently. Their angular speed and self-spin are
derived from one analytic normalized clock, every cube selects the same atlas
frame at a given instant, and orbital spacing is mathematical rather than
spring- or noise-driven. Seeking, replaying, pausing, and changing playback
speed therefore cannot desynchronize the formation.

The sprites deliberately do not respond to scene lights: the original's top,
middle, and shadow arrangement is part of the pixel drawing. Intermediate
rotation frames keep those three screen-facing roles stable, avoiding the
erratic face-color swaps that occurred under thresholded realtime lighting.
This trades physically correct light response for exact palette discipline and
the supplied artwork's identity at battle scale.

| element | direct | middle | shadow |
| --- | --- | --- | --- |
| Wind | `#99E550` | `#6ABE30` | `#37946E` |
| Fire | `#D95763` | `#AC3232` | `#76428A` |
| Ice | `#FFFFFF` | `#CBDBFC` | `#5FCDE4` |
| Water | `#5FCDE4` | `#639BFF` | `#3F3F74` |
| Wood | `#D9A066` | `#8F563B` | `#4B692F` |
| Earth | `#EEC39A` | `#8A6F30` | `#45283C` |
| Steel | `#CBDBFC` | `#9BADB7` | `#3F3F74` |
| Darkness | `#D77BBA` | `#76428A` | `#323C39` |
| Light | `#FFFFFF` | `#FBF236` | `#D9A066` |
| Thunder | `#FBF236` | `#DF7126` | `#3F3F74` |

## Crownburst

All cubes manifest together at `0.26u` radius and `0.90u` height, then ease to
an even `1.02u` crown at `1.18u` height. Their fixed phase offsets are exactly
one eighth of a turn, so no two cubes can bunch together. At normalized time
`0.72` the ring releases: radius gains `1.55u`, height loses `0.50u`, and scale
falls quickly enough to finish by `0.95` at the accepted maximum dissipation.

The accepted authoring settings are 2.4 orbit turns, 3.2 self-spin turns, 2.8
acceleration, and 2.4 dissipation. These are also exposed as live-authoring
tunables in the VFX debug scene.

## Spiral Invocation

The trailing cube starts at ground height only after the cube ahead has begun
the same path. A `0.055` normalized path gap keeps the eight cubes on the
vacated trail with a little more air between them; at the start only the first cube is
visible. The path grows from `0.34u` to `0.86u` radius while rising `1.55u`, and
uses the same acceleration as Crownburst. Spiral coils counter-clockwise while
all eight cubes self-spin clockwise in lockstep, creating a woven motion
without introducing independent rotations. After reaching the top, each cube
uses Crownburst's release language over a `0.28` normalized path window: it
peels radially outward, falls `0.50u`, and shrinks away at full opacity.

## Routing and ownership

`HexBattleVisualAdapter` asks `SpellVfxCatalog.profileForSpell()` for the cast
profile. Positive damage, positive damage lines, inflicted statuses, and
explicitly negative effects count as offensive. A non-healing spell aimed away
from self is also treated as offensive; the remaining casts use Spiral
Invocation. The decision is presentation-only and does not change simulation
state, targeting, damage, or spell data.

Both effects reanchor to `VfxCastContext.source_world_position`, not the target
or impact position. The generic aura remains the catalog safety fallback for
an unrecognized explicit profile id.
