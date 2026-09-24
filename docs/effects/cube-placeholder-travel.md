# Cube placeholders: travel and delivery

Six source-to-target cube motions, each a direct translation of one study in
the retained
[cube motion sketch](../sketches/2026-09-24-cube-spell-motion-studies.html).
The sketch owns their choreography; this page records how it was carried into
the world. The substrate they run on is described in
[cube-placeholder-foundation.md](./cube-placeholder-foundation.md).

Code: `src/presentation/effects/cube_placeholders/travel/`. Preview any of them
without gameplay registration:

```bash
Godot_v4.4-stable_win64.exe --path . scenes/debug/VFXDebugScene.tscn \
  --catalog-script=res://src/presentation/effects/cube_placeholders/travel/TravelCatalog.gd \
  --effect-prefix=cube_ --seed=7 --hide-hud --source-distance=8 --radius=1 \
  --render-resolution=640x480 --capture-at=0.12,0.30,0.50,0.70,0.90
```

`--source-distance=8` is the reference configuration (4 cells), where every
beat boundary is exactly the sketch's.

| Profile | Study | Beats (sketch time) | Impact | Peak |
| --- | --- | --- | --- | --- |
| `cube_arcing_pair` | 2 medium lobs, then 8 + 12 chips | Gather 0-.16 / Angled arcs .16-.68 / Break .68-1 | .68 | 21 |
| `cube_scattershot` | 11 small in a widening cone, 3 chips per hit | Pack 0-.16 / Fan out .16-.49 / Pepper .49-1 | .49 | 34 |
| `cube_corkscrew_bolt` | 1 medium lead, 7 tiny helix wake, 16-chip burst | Wind up 0-.16 / Bore forward .16-.64 / Burst .64-1 | .64 | 24 |
| `cube_returning_throw` | 1 large, out wide and back the other side, 8 chips | Throw wide 0-.505 / Clip target .505-.52 / Return .52-1 | .505 | 9 |
| `cube_skipping_stone` | 1 medium, three contacts, 6 chips each | Launch 0-.34 / Hop → hop .34-.78 / Last impact .78-1 | .78 | 7 |
| `cube_flanking_volley` | 4 medium curling round both flanks, 18-chip burst | Separate 0-.14 / Curve around .14-.7 / Converge .7-1 | .70 | 18 |

Travel beats are the flights: arcing pair .16-.68, scattershot .16-.49,
corkscrew .16-.64, returning throw .12-.505 and .52-.89, skipping stone
.12-.78, flanking volley .14-.70. Under `RANGE_SCALING: travel` only those
stretch. A beat whose name covers a still lead-in or tail is split into two
segments with the same name, so only the moving part stretches. The impact
time is where a battle caller holds the action queue. Peaks are measured by
the family probe, which fails if a declared peak differs from the sampled one.

## The family's coordinate conversion

A study's `C` and `T` become the live source and target, so every path begins
on the caster and ends on the target at any separation. A point the sketch
gives relative to `T` (`T + dx`) is placed relative to the target at the target
scale, never by extrapolating the path.

**Path scale.** The sketch draws every path over a 3.5-unit separation, so its
arcs are steep. At the plain world unit a real cast, which is longer, would
flatten them; at the full separation ratio a long cast would lob off screen.
Arc heights and lateral path offsets therefore scale by
`unit * sqrt(separation / 5.6)`, clamped to 0.6-2.0 units, where 5.6 world
units is the sketch's separation at the plain unit. Against the sketch's own
height-to-length ratio, arcs are 18% steeper at 2 cells, 16% flatter at the
4-cell reference, 25% flatter at 5 cells and 47% flatter at 10. Launch and
landing heights (0.8 and 0.7 in the sketch), cube sizes, the corkscrew's helix
radius and everything around the target keep their own scales, so the size
hierarchy against real bodies is untouched.

The skipping stone's two middle contacts sit at their sketch positions along
the path (progress 0.457 and 0.800); its last lands 0.55 sketch units beyond
the target. Scattershot's landing points are target-relative, so an
`AREA_SCALING: spread` spec opens the pepper pattern over the affected area
(authored half-width 1.3 sketch units) while the shot still leaves the caster
as one pack.

## Checks

`scripts/hex_battle/cube_vfx/travel/probe_cube_travel.gd` (manifest
`scripts/checks/probes/cube_vfx_travel.json`, `-Filter cube_vfx/travel`):
declared peak equals the maximum sampled over 1201 times at 2/4/6/10 cells and
seeds 0 and 7, with no overflow and within the render budget; every beat
boundary is exact at the reference; ascending, reverse and shuffled seeks
agree; travel stretch is 0.75/1.0/1.5/1.5 with the lead-in unchanged and the
hold lengthened past 4 cells. Per study: two lobs from opposite sides and 8
then 20 chips; the second lob lands beside the target; eleven shots in a cone
whose width grows; 1 bolt + 7 wake, a 16-chip burst, the bolt gone by 0.67;
the throw touches the target at 0.505, returns to the caster by 0.89 and comes
back on the other side; three stone contacts each landing on its node with
chips; four volley cubes on the target together at 0.699, two per flank at
mid-flight, an 18-chip burst.
