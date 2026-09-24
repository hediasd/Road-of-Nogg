# Cube placeholders: restore and transform

Six cube studies whose meaning is a direction — repair, intercept, drain,
cleanse, transfer, charge — translated from the retained
[cube motion sketch](../sketches/2026-09-24-cube-spell-motion-studies.html).
The substrate is described in
[cube-placeholder-foundation.md](./cube-placeholder-foundation.md).

Code: `src/presentation/effects/cube_placeholders/restore/`. Preview without
gameplay registration:

```bash
Godot_v4.4-stable_win64.exe --path . scenes/debug/VFXDebugScene.tscn \
  --catalog-script=res://src/presentation/effects/cube_placeholders/restore/RestoreCatalog.gd \
  --effect-prefix=cube_ --seed=7 --hide-hud --source-distance=8 --shape=single \
  --render-resolution=640x480 --capture-at=0.12,0.30,0.50,0.70,0.90
```

| Profile | Binding | Population change | Beats (sketch time) | Impact | Peak |
| --- | --- | --- | --- | --- | --- |
| `cube_repair_mend` | body | 12 fragments → 4 stacked blocks | Gather fragments 0-.3 / Rise inward .3-.57 / Reassemble .57-1 | .65 | 16 |
| `cube_intercepting_guard` | body | 6 orbiters + 1 incoming → 9 chips | Orbit 0-.25 / Intercept .25-.66 / Recover .66-1 | .55 | 15 |
| `cube_siphon` | two-anchor | 9 stream cubes → 1 growing absorber | Loosen 0-.07 / Pull to caster .07-.79 (travel) / Absorb .79-1 | .43 | 10 |
| `cube_cleanse` | body | 10 attached → cast away | Cling 0-.32 / Lift off .32-.52 / Cast away .52-1 | .52 | 10 |
| `cube_blink_transfer` | two-anchor | 8-cube cluster, caster → target | Disassemble 0-.2 / Cross in a streak .2-.636 (travel) / Reform .636-1 | .636 | 8 |
| `cube_charge_release` | two-anchor | 16 gather → 1 heavy → 24 chips | Gather power 0-.42 / Hold weight .42-.55 / Fire .55-.76 (travel) and .76-1 | .76 | 24 |

## Direction and roles

Every study names its roles by the cast: the caster is the source, the anchor
the target. The drain runs target to source and its absorber only grows; the
charge gathers at the source and fires at the target; the blink leaves the
caster and reforms at the target, crossing in sequence; the guard faces its
anchor's front.

**A self-cast still has a direction.** When source and anchor coincide the
substrate gives the frame the anchor's front as its forward, so direction
vectors are always unit length. A two-anchor study played on itself collapses
its path to zero length and keeps its vertical motion. Nothing reads a
direction that is not there, so nothing produces NaN; the probe checks every
study this way, with and without `SPREAD: each_target`.

## Judgement calls

- **Repair stands beside the body, not inside it.** The sketch draws the four
  blocks at `T` itself. In its 2D painter's order that paints over the
  reference actor; in the world it would bury them inside the target's body.
  Its own description says "beside the target", so the stack stands on the side
  axis just clear of a standard body (the actor's half-width plus half a block),
  and the fragments converge on the stack.
- **The guard's threat axis is the anchor's front.** In the sketch the hostile
  seventh cube comes from the caster. A shield cast by an ally has no hostile
  caster, so the six orbiters form their 2x3 wall on the side of the anchor's
  nearest hostile, which the battle supplies per protected ally, and the
  incoming cube travels in along that axis from the sketch's own 3.5 units out.
  Without a supplied front the axis is the frame's forward, so the threat comes
  from beyond the anchor; a caller that wants the sketch's picture supplies the
  front toward the caster. The incoming cube gives way to its chips at .55
  instead of sharing that instant with them: it is absorbed there.
- **The charge holds.** From .42, fully grown, to .55 the heavy cube stays put
  over the caster, trembling only in size, before it fires. The hold is not a
  travel beat, so it keeps its length at any range; only the flight stretches.
- **Blink colours by column.** With two elements (a steel-and-wind spell) ids
  alternate by column, so each column of the cluster shows one element.
- Paths between the anchors use the travel family's path scale, copied into
  `RestoreComposition` rather than shared across families.

## Checks

`scripts/hex_battle/cube_vfx/restore/probe_cube_restore.gd` (manifest
`scripts/checks/probes/cube_vfx_restore.json`, `-Filter cube_vfx/restore`):
declared peaks equal the maximum over 801 samples at 2/4/10 cells and seeds 0
and 7, within the render budget; seeks just before, at and after every beat
boundary agree in either order; every study stays finite with a unit forward on
a self-cast. Per study: 12 fragments, then fragments and blocks together at .58,
then four blocks stacked beside the body, the fragments gathering; six orbiters
on the threat side meeting the incoming cube at .55, which arrives along the
threat axis and becomes 9 chips, then the orbit recovered; six protected allies
each with their own ring and wall on their own front, peak 90 in one draw call;
every stream cube leaving the target and closing on the caster at 2/4/10 cells
while the absorber grows; ten attached cubes cast outward, the target clear by
.9; the cluster at the caster, crossing in sequence, reformed at the target,
both elements present; sixteen gathering, one heavy cube held still over the
caster from .42 to .55 with the hold's seconds unchanged at any range, firing
toward the target and shattering into 24.
