# Elemental cube rituals

Two source-bound spell placeholders express power channeled from the elemental
realms. They use the same small, softly beveled cubes, palette system, shader,
and lifecycle; choreography distinguishes the cast role. Crownburst is the
offensive placeholder. Spiral Invocation is the support and utility
placeholder. A spell with an explicit `VFX_PROFILE` keeps its authored effect.

The shared VFX contract and authoring conventions live in
[`../VFX_DESIGN.md`](../VFX_DESIGN.md).

| profile id | role | choreography | duration |
| --- | --- | --- | --- |
| `elemental_cube_crownburst` | Offensive fallback | Eight cubes accelerate from an inner ring into an even crown, orbit and spin in lockstep, then release outward and down. | 2.10s battle / 5.20s reference |
| `elemental_cube_spiral` | Support and utility fallback | One close train emerges successively from the ground and follows a shared rising helical path before dissolving successively at its top. | 2.10s battle / 5.20s reference |

## Shared visual language

Each ritual builds eight `0.24u` cubes. A `0.025u` geometric bevel removes the
pointed silhouette; a restrained `0.075` Fresnel contribution supplies the
slight polished edge without turning the cubes metallic or glossy. All eight
instances share one generated mesh and one shader material. The effect owns no
particles, lights, or timers and is capped at nine nodes, eight geometry
instances, and eight draw calls.

The cubes never drift independently. Their angular speed and self-spin are
derived from one analytic normalized clock, every cube has the same local
rotation at a given instant, and orbital spacing is mathematical rather than
spring- or noise-driven. Seeking, replaying, pausing, and changing playback
speed therefore cannot desynchronize the formation.

The shader is unshaded and evaluates a fixed virtual key in world space. It
uses two `smoothstep` blends rather than thresholds, so a rotating face moves
continuously from shadow to middle to direct color instead of jumping between
swatches. The key points from above and slightly camera-left; that makes a
direct, middle, and shadow-facing surface visible together at the normal battle
camera more often. Rounded bevel normals carry a narrow blend of the adjacent
face shades across each edge.

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
the same path. A `0.04` normalized path gap keeps the eight cubes close to the
vacated trail without stacking them; at the start only the first cube is
visible. The path grows from `0.34u` to `0.86u` radius while rising `1.55u`, and
uses the same accelerating orbit and synchronized self-spin as Crownburst.
Each cube dissolves only after reaching the top, preserving the ordered train
through the exit.

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
