# Cube placeholders: shape and control

Six cube studies that build a persistent spatial state — wall, cage, snare,
lift, crush, encasement — out of identical cubes, translated from the retained
[cube motion sketch](../sketches/2026-09-24-cube-spell-motion-studies.html).
The substrate is described in
[cube-placeholder-foundation.md](./cube-placeholder-foundation.md).

Code: `src/presentation/effects/cube_placeholders/control/`. Preview without
gameplay registration:

```bash
Godot_v4.4-stable_win64.exe --path . scenes/debug/VFXDebugScene.tscn \
  --catalog-script=res://src/presentation/effects/cube_placeholders/control/ControlCatalog.gd \
  --effect-prefix=cube_ --seed=7 --hide-hud --source-distance=8 --shape=single \
  --target-body=standard --camera-size=8 --camera-focus=target \
  --render-resolution=640x480 --capture-at=0.12,0.30,0.50,0.70,0.90
```

| Profile | Binding | Structure | Beats (sketch time) | Impact | Peak |
| --- | --- | --- | --- | --- | --- |
| `cube_rising_barricade` | two-anchor | 3 layers of 5, rising from the middle out | Seed line 0-.14 / Build upward .14-.8 / Withdraw .8-1 | .45 | 15 |
| `cube_closing_cage` | body | 4 posts of 4; the top cubes close to 0.3 over the head | Corner posts 0-.42 / Close overhead .42-.65 / Hold .65-1 | .65 | 16 |
| `cube_climbing_coil` | body | 22 tiny cubes in a rising helix that tightens 0.77 → 0.48 | Find feet 0-.15 / Climb .15-.62 / Tighten .62-1 | .80 | 22 |
| `cube_lifting_vortex` | volume | 28 cubes from a 1.65 skirt up a spiral, flung out at the top | Sweep inward 0-.3 / Spiral upward .3-.7 / Release .7-1 | .60 | 28 |
| `cube_clapping_slabs` | body | 2 slabs of 6 on the cast axis, 26 fragments | Build sides 0-.38 / Slam together .38-.62 / Chip away .62-1 | .62 | 38 |
| `cube_encasing_frost` | body | 3 rings of 6 from the feet up, 12 release chips | Seed crystals 0-.17 / Build shell .17-.56 / Lock .56-1 | .56 | 30 |

None has travel beats, so none stretches with range.

## One bounds policy

Every body-bound study is drawn around the sketch's standard actor. On a real
target the whole composition scales by one factor, the substrate's body
adaptation: large enough to enclose the widest horizontal extent, tall enough
to clear the head. Cubes scale with it and stay cubes. No axis stretches on its
own, so a wide and a tall body see exactly the same choreography, only larger.
The probe checks that every cube's size changes by exactly that factor on the
wide and tall presets. On the wide preset (1.20 wide) the factor is 1.71; on
the tall one (top at 2.05) it is 1.37.

When a spell's spec spreads a body-bound shape over its footprint — Bramble
Crown's cage, whose briar encircles its area — `ControlComposition.around()`
spreads the ground plan by the frame's target scale and keeps heights and
cube sizes at the body scale. A spread cage is wider, never taller, so its
posts stay columns of touching cubes. Each spread point is then held within
85% of the footprint's reach in its own direction
(`CubePlaceholderFootprintReach`), and never pulled inside its body-sized
position: spreading only widens a shape onto affected cells. Where the
footprint is narrower than the body-sized shape (a disc clipped by the board
edge, the gaps of a cross), the shape keeps its body size there, exactly as
without a spread. Without a spread, a footprint changes nothing: a body-only
shape claims no area.

That hold was added in the cycle's live-battle validation. Before it, a spread
shape scaled uniformly to the farthest affected cell, which put cage posts on
unaffected cells in most directions and, near the board edge, off the board.
The probe now fails that old behaviour on a full disc, a clipped disc and a
cross.

## Judgement calls

- **Where the barricade stands.** The sketch puts the wall at x = -.25, 57%
  of the way from caster to target, and that is where it stands on a
  two-anchor cast. When the anchor is no more than a cell from the caster —
  Barricade's own self-cast, anchored a cell in front of the caster, or an
  adjacent target — the wall stands on the anchor itself, because 57% of one
  cell puts it against the caster's body. Either way it runs across the
  source-to-anchor direction and never claims a cell.
- **The slabs stand on the cast axis**, one on the caster's side, one beyond
  the target. The cubic ease is the slam: they barely move for most of the
  beat, meet on the body at .62, and stay pressed together until they shatter
  at .68.
- **The vortex releases**: the last fifth of each cube's climb turns its
  radius outward again (the sketch's `p > .8` term), so cubes are flung off
  the top before they fade.
- **The frost shell occludes the target.** Its radius is tight to the body
  (0.54 sketch units around a 0.225 half-width) and grows with it. That is the
  point of a freeze, not a defect.

## Checks

`scripts/hex_battle/cube_vfx/control/probe_cube_control.gd` (manifest
`scripts/checks/probes/cube_vfx_control.json`, `-Filter cube_vfx/control`):
declared peaks equal the maximum over 801 samples on standard, wide and tall
bodies and seeds 0 and 7, within the render budget; reverse and shuffled seeks
across the holds agree; every cube scales by exactly the body factor on wide
and tall; with a radius-3 footprint and no spread a body-bound shape is
identical to having no footprint and stays within reach of the body; with
spread it widens with cube sizes unchanged; spread over a full disc, a clipped
disc and a cross, the cage and the vortex never widen a grounded cube onto an
unaffected cell and never pull one inside its body-sized position. Per study: a 15-cube wall between
caster and target, across the cast direction, stacking upward, gone at .99; the
same wall on its anchor a cell in front of a self-cast (zero-length source to
impact) and across the front; four posts of four whose lid closes to under half
its radius and holds still; 22 climbing cubes that tighten; all 28 vortex cubes
sweep in then fly out; two slabs of six meeting on the body at .62 after
starting over a unit further out, then 26 fragments; three rings of six at lock,
starting from the feet, then 12 chips.
