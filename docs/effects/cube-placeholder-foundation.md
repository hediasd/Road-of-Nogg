# Cube placeholder foundation

The shared substrate every cube placeholder spell profile runs on, and the
per-spell VFX spec that tells it how to adapt to a cast. The 24 profiles
themselves are translations of the retained
[cube motion sketch](../sketches/2026-09-24-cube-spell-motion-studies.html);
each family page (travel, impact, control, restore) covers its own six. The
shared VFX contract lives in [`../VFX_DESIGN.md`](../VFX_DESIGN.md).

Code: `src/presentation/effects/cube_placeholders/shared/` and
`src/presentation/effects/SpellVfxSpec.gd`.

## Split of responsibility

| Piece | Owns |
| --- | --- |
| `CubePlaceholderComposition` | One study: its beats (which are travel beats), roles, peak population, binding, impact and settle times, and `sample(t, frame)`, which emits the cubes visible at sketch time `t`. Pure: no state between calls, no allocation. |
| `CubePlaceholderFrame` | One anchor's coordinate frame: sketch x/y/z to world, the three scales, the seeded `rnd`, the ground clamp, `cube()`. |
| `CubePlaceholderEffect` | The `VfxPlayback`: lifecycle, the range warp, anchors from the spec, palettes, and the renderer. One generic factory, `create(parent, position, colour, overrides, compositionScript)`, which catalog rows bind a composition script to. |
| `CubePlaceholderPoseBuffer` | The preallocated cubes of one sample. |
| `CubePlaceholderAtlas`, `CubePlaceholderProfile` | The sprite atlas and the authored constants, copied from the rituals rather than shared with them. |
| `CubePlaceholderFootprintReach` | How far an affected footprint reaches from an origin in each direction, measured once per cast; what keeps a spread shape on the cells a spell hit. The impact family keeps its own earlier copy of the same measurement. |
| `SpellVfxSpec` | Parsing, defaults and validation of a spell's `VFX` block, and the `frontToward` rule for "in front of". |

## Rendering: one MultiMesh, one draw call

Every cube of a playback is an instance of one `MultiMesh` quad, billboarded
in its shader and textured from an atlas of twelve quarter-turn frames across
and one palette row per element down. Per-instance custom data picks the frame
(from the cube's yaw), the palette row (from the cube's stable id, round-robin
over the spec's elements) and an opacity. So a playback is one render node and
one draw call whatever its cube count, element count or anchor count. The
substrate budget (four render nodes, four draw calls) is a ceiling a family
could only reach by adding nodes of its own.

The tradeoff that choice settled: per-instance opacity usually forces alpha
blending, and alpha-blended billboards need sorting, which a single MultiMesh
cannot do per instance. The sketch never fades a cube by opacity — its cubes
grow and shrink — so the cubes are opaque with an alpha cut, and depth orders
them against each other and the world with nothing to sort. The rare opacity
below 1 is an ordered 4x4 dither, which stays in the opaque pass. Because
billboards are all parallel to the view plane, two cubes never intersect;
the nearer centre wins, which is the sketch's own painter's order.

Resources are built per playback and freed with it: shader, material, atlas,
quad, multimesh. A static cache would save compiling one small shader per cast
and would reintroduce what `VfxTextures`' unreleased static cache does today —
a crash at engine exit that keeps any probe touching it from gating.

## Coordinates and the three scales

The sketch's x runs from its caster reference `C = -2.25` to its target
reference `T = 1.25`; y is up; z is lateral. A frame maps x to the horizontal
source-to-anchor direction, y to world up, and z to `forward x up`.

- **Along a path** the anchors decide: `along(q, y, z)` interpolates source to
  anchor by progress `q`, so a path starts at the caster and ends on the target
  at any separation. `progressOfSketchX(x)` converts a sketch x.
- **Around an anchor** `nearTarget(dx, y, dz)` uses `targetScale()`: `UNIT_U`
  (1.6 world units per sketch unit), times the body adaptation for a body-bound
  composition, times the area spread when the spec spreads it.
- **Cube edges** use `cubeScale()`: the unit times the body adaptation only.
  Spreading over a larger area moves cubes apart; it never makes them bigger.

`UNIT_U = 1.6` is measured, not chosen: the sketch's reference actor is 0.84
sketch units tall and 0.45 wide, the standard target body 1.30 tall above a 0.20
base and 0.70 wide. Height gives 1.79, width 1.56; 1.6 keeps a medium cube the
same share of a body's width as in the sketch. The sketch's `C`-`T` separation
is therefore 5.6 world units, shorter than the 8-unit reference cast; paths are
longer than the diagram in proportion, which is the price of keeping the size
hierarchy against real bodies.

Body adaptation is uniform: `max(widest horizontal extent / 0.70, top / 1.50)`.
Standard is 1; a wide body scales the whole composition until it encloses the
width, a tall one until it clears the head. Cubes stay cubes.

Area spread is `max(1, footprint reach / authored area radius)`, where reach is
the farthest affected cell centre from the anchor plus half a cell. It never
shrinks a study below its authored size, so at the reference configuration
(one cell) every study is exactly as drawn.

## Time and range

A composition is authored on the sketch's 0-1 timeline and declares its beats.
Under `RANGE_SCALING: travel`, its travel beats last
`clamp(cells / 4, 0.75, 1.5)` times their reference length and every other beat
keeps its length, where cells is the horizontal source-to-cast-centre distance
over the 2.0-unit row pitch. The playback maps its normalized time onto sketch
time piecewise-linearly, so at 4 cells the map is the identity and every beat
boundary is the sketch's. The debug scene's reference separation is therefore
`--source-distance=8`. The 4-cell reference and the clamp are provisional.

`get_action_hold_seconds()` is the warped time of the composition's impact
beat, so a battle caller that holds the action queue that long lands the hit on
the impact at any distance. `skip_to_settle()` jumps to the warped settle time.

## The spec and its anchors

The vocabulary, defaults and meaning of each aspect are in
[`../SPELL_CATALOG_SCHEMA.md`](../SPELL_CATALOG_SCHEMA.md) once the catalog
integration documents them; `SpellVfxSpec.ASPECTS` is the source. The
substrate reads it like this:

- `ANCHOR: caster_front` makes one anchor a cell in front of the caster, facing
  its front. `SPREAD: each_target` makes one anchor per cast-context target,
  each with its own body bounds and front. Otherwise there is one anchor on the
  cast centre, around the unit standing there or the default body when the
  cell is empty (`frame.hasBody` says which).
- `AREA_SCALING` and `RANGE_SCALING` left open take the composition's defaults:
  area-bound compositions spread, compositions with travel beats stretch.
- `ELEMENTS` picks the palette rows. With no spec, or a spec whose only element
  is `none` and no spec was configured, the colour the playback was created
  with picks the palette by nearest reference colour, exactly as the rituals do.
- Fronts come from `configure_facing(sourceFront, targetFronts)`. Units have no
  facing, so "front" is `SpellVfxSpec.frontToward`: the direction to the nearest
  living hostile, ties to the lowest id, falling back to the given direction
  and then world +X. The debug scene and the battle adapter call the same rule.
  Without it, an anchor faces along its source direction, and a coincident
  source and anchor faces the caster's front or +X.

Capacity is `max(peak, 48)` cubes per anchor, allocated in preparation. A
composition that emits past its declared peak is reported, never silently cut:
the buffer counts the overflow and the playback pushes an error.

## Checks

`scripts/hex_battle/cube_vfx/shared/probe_cube_substrate.gd`, registered in
`scripts/checks/probes/cube_vfx_shared.json`, runs a probe-only composition
(two roles, one travel beat, a peak of exactly 48) through the real playback.
It covers spec parsing and every error case, that every current spell parses,
`frontToward`, the warp, palettes, 101-time sampling in three orders for two
seeds with no object, node or resource growth, capacity, render budget, role
layers, rate, settle, hold, disposal, range stretch at 2/4/6/10 cells, six
`each_target` anchors with two elements in one draw call, `caster_front`, and
that no shared script depends on the elemental cube rituals.
