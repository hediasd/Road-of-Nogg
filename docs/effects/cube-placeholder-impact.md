# Cube placeholders: impact and area

Six cube studies with the largest populations and the strongest implied mass,
translated from the retained
[cube motion sketch](../sketches/2026-09-24-cube-spell-motion-studies.html).
The substrate is described in
[cube-placeholder-foundation.md](./cube-placeholder-foundation.md).

Code: `src/presentation/effects/cube_placeholders/impact/`. Preview without
gameplay registration:

```bash
Godot_v4.4-stable_win64.exe --path . scenes/debug/VFXDebugScene.tscn \
  --catalog-script=res://src/presentation/effects/cube_placeholders/impact/ImpactCatalog.gd \
  --effect-prefix=cube_ --seed=7 --hide-hud --source-distance=8 --radius=2 \
  --render-resolution=640x480 --capture-at=0.12,0.30,0.50,0.70,0.90
```

| Profile | Binding | Study | Beats (sketch time) | Impact | Peak |
| --- | --- | --- | --- | --- | --- |
| `cube_ceiling_collapse` | area | 12 dust, then 7 heavy, 5 rubble each | Dust warning 0-.4 / Heavy fall .4-.66 / Rubble .66-1 | .62 | 42 |
| `cube_ground_teeth` | area | 5 trembles, 5 four-cube stacks, 5 crumbs each | Tremble 0-.18 / Punch upward .18-.65 / Crumble .65-1 | .35 | 45 |
| `cube_expanding_shockwave` | area | 1 compressing core, then a 24-cube ring | Compress 0-.3 / Expanding ring .3-.63 / Scatter .63-1 | .30 | 24 |
| `cube_implosion` | volume | 18-cube shell snapping into 1 core | Hang 0-.29 / Snap inward .29-.69 / Collapse .69-1 | .69 | 19 |
| `cube_rolling_avalanche` | two-anchor lane | 2 boulders + 10 trail, 18 rubble | Rumble 0-.08 / Roll through .08-.64 (travel) / Break apart .64-1 | .60 | 30 |
| `cube_staggered_bombardment` | area | 9 diagonal strikes, the last largest | First drops 0-.27 / Uneven impacts .27-.766 / Last heavy hit .766-1 | .766 | 29 |

The warnings are the point of three of these and the probe defends them: all
twelve dust cubes start before the heavies appear at .27 and no heavy lands
before .62; the teeth rise one after another; the ninth strike is both the
largest cube and the last to land.

## Footprint projection

The sketch lays its area studies out on a flat rectangle around `T`. A hex
footprint is neither flat-sided nor always centred on the target: a cross has
arms and gaps, a line runs from the caster. Placing the sketch's points radially
at some scale would drop cubes on cells the spell did not hit.

So `ImpactComposition.areaPoint(dx, dz)` keeps each authored ground point's
direction from the pattern's origin and remaps only its distance: its share of
the study's authored radius becomes that share of the footprint's reach in that
direction. A pattern fills a disc as a disc, stretches along a cross's arms and
pulls in between them, and runs along a line. Counts, order and the internal
layout are untouched; only the ground changes shape.

- The origin is the anchor if it stands on an affected cell, otherwise the
  affected cell nearest it (a line spell's centre need not be on its line).
- Reach per direction is measured once per cast, in 48 directions, as the
  union of one disc per cell (0.9 of the cell's half-extent). This never
  overstates the reach. A pattern uses 85% of it; rubble chips may use 95%.
- `AREA_SCALING: spread` makes the pattern reach the footprint's edge.
  `none` keeps the authored size and only pulls a point in where the footprint
  is smaller than the pattern. On a single cell the two agree.
- A final guard walks any point that would still land off the affected cells
  back toward the origin, which makes "never outside" a guarantee.
- Heights, cube sizes and rubble reach stay at the plain cube scale: an area
  spread moves cubes apart, never enlarges them.

Only cubes on or near the ground claim cells. A bombardment strike still high
on its diagonal passes over empty cells; it lands on an affected one.

The implosion is a target-centred volume, not an area: under
`AREA_SCALING: spread` its sphere grows with the footprint's reach through the
frame's target scale, and it is not projected. The avalanche is a lane from
just behind the caster to 0.7 sketch units beyond the target; the footprint is
collision truth for its break-apart rubble, which stays on affected cells, but
the lane itself is never bent to follow them. At long range the boulders reach
the target just before the break (0.639 sketch time at 10 cells, against 0.58
in the sketch), because the lane's overshoot is target-relative.

On a single cell the ceiling's heavies and the teeth crowd together. They keep
their counts and read as the same study, just tighter. That is the cost of not
advertising neighbouring cells a single-target spell does not hit.

## Checks

`scripts/hex_battle/cube_vfx/impact/probe_cube_impact.gd` (manifest
`scripts/checks/probes/cube_vfx_impact.json`, `-Filter cube_vfx/impact`):
declared peaks equal the maximum over 801 samples with no footprint, one cell
and a radius-3 disc, in default, spread and none modes, seeds 0 and 7, within
the render budget; reverse and shuffled seeks agree; 4x rate; settle. For the
four area profiles, every cube within 1.0 world units of the ground stands on
an affected cell for single, disc r1-4, cross r1 and r3 and line r3, in both
modes; spread reaches past 60% of a disc's radius at r3 and r4 and further than
none on r4; spread and none agree on one cell. Per study: dust alone before the
heavies, all twelve starting before .27, seven heavies by .50, no landing
before .62, rubble after; five trembles, each tooth ahead of the next, five
stacks of four; one core that compresses, then a 24-cube ring whose mean radius
grows; an 18-cube shell whose mean radius shrinks, one core at .72, nothing at
.95, and a wider shell under spread; two boulders and ten trail cubes passing
the target at 2/4/6/10 cells with the travel stretch; the ninth strike lands
last and is the largest, with a 14-chip burst.
