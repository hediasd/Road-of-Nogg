# Prompt — Magenta Reduction VFX

Hand this file to a fresh session. It is written to be self-contained: it does
not assume the conversation that produced it.

---

## The ask

Build the spell effect for **Magenta Reduction** (`data/spells.json`, water +
fire via `DAMAGE_LINES`, currently no `VFX_PROFILE`, `RANGE` 3, `TARGET_TYPE`
defaults to `single`). Register it as profile id `magenta_reduction` and set
`VFX_PROFILE` on the carrier.

**Read `docs/VFX_DESIGN.md` first and follow it.** In particular §4's two
standing rules — everything is a profile constant forwarded as a shader uniform,
and the effect is authored as a function of the footprint so it holds from
radius 1 to 5 — and §6's proof checkpoints, which are not optional here.

## Item zero — the carrier's radius is visual-only until `TARGET_TYPE` changes

The carrier is now `"RADIUS": 3`, so **author and judge this effect at radius 3**,
not at the harness default of 2. That is a 3-tile Manhattan diamond, reaching
3.5 world units from the centre.

But the spell is still `TARGET_TYPE: "single"`, and that combination is
inconsistent in a way the effect will expose:

- `_spellAffectedPositions` (`src/battle_sim/CombatResolver.gd:443`) returns
  `[centerPos]` alone whenever `targetType != "area"` and `self_radius <= 0`.
  **`RADIUS` does not affect gameplay here.** The spell hits exactly one tile.
- `_on_spell_cast_started` (`src/presentation/GodotVisualAdapter.gd:869`) reads
  `vfx_radius` off `RADIUS` unconditionally, for every cast, whatever the target
  type. **The effect will claim all 25 tiles of the diamond.**

`docs/VFX_DESIGN.md` §4 names exactly this as a real defect: an effect that
claims tiles the spell does not hit misinforms the player about the area.

Confirm with the user before item 1. Adding `"TARGET_TYPE": "area"` resolves it
and matches what the effect depicts, but it is a **gameplay** change — 25 tiles
of 3+3 dual-element damage at range 3 is a substantially stronger spell than a
single-target hit, and the damage numbers likely want revisiting alongside it.
If the spell is meant to stay single-target, the fix belongs on the presentation
side instead and the effect must be re-scoped before any of the work below.

## The look

A four-beat implosion-then-discharge. Not a storm: the fire and ice effects both
push outward and upward, this one pulls inward first.

| Beat | What is on screen |
| --- | --- |
| **Gather** | Slow fuchsia motes appear *on the footprint boundary*, sparse, drifting barely inward. The centre is empty. |
| **Spiral** | The motes are drawn to the centre along a tightening spiral, accelerating as they close. Angular speed rises as radius falls, so the field visibly winds up. |
| **Charge** | The spiral holds and compresses — a few seconds of swirling with a brightening core, before anything is released. This beat is the effect's identity; do not compress it away. |
| **Discharge** | A **thin** yellow-white and fuchsia blast lances from the centre back out to the boundary. All remaining motes dissipate with it. |

Reference language is Ragnarok Online, same as the existing effects: hard-edged
additive sprites, saturated hues, a core that blows out toward white at the
release, and a silhouette that is legible against a busy tile field. The
gather-and-release shape is RO's cast-convergence motif rather than its
ground-storm one.

Palette: fuchsia dominant (the spell is named for it), yellow-white only at the
core and in the discharge. Water and fire are the carrier's elements but this
should read as *magenta* — do not split it into a blue half and an orange half.

**Thin means thin.** The discharge is a lance or a narrow ring, not a dome. If
it fills the footprint as a solid mass it is wrong.

## What to reuse

Fork `FireStormEffect.gd` + `FireStormProfile.gd` +
`assets/shaders/effects/fire_storm_vortex.gdshader`. That vortex shader is
already most of this effect running backwards: it has spiral motion with a
radius-dependent angular rate (`swirl_base` / `swirl_crown`), per-particle
lifetime phase off `INDEX` and `playback_time`, the diamond-footprint clamp, and
`onset_fraction`. The inward-travel version is a change of sign and mapping, not
a new shader from scratch.

Carry over unchanged: the `VfxPlayback` lifecycle, `setFootprint()`, the
build-time budget asserts, `VfxTextures.groundWash()` for the shaped floor
decal, the seeded-RNG determinism approach, and `ACTION_HOLD_FRACTION`.

Drop the smoke crown — there is no equivalent. That is what frees node budget
for the core and the discharge.

Suggested layer roster (rename freely, but keep them separately toggleable):
`ground_wash`, `motes`, `core`, `discharge`, plus the motion toggles the fire
shader already exposes.

## Decision to raise before writing code

`docs/VFX_DESIGN.md` §4 says the **third** elemental effect is the trigger to
reconsider forking and extract a shared `SpellVfxProfile` resource. This is the
third.

Do not decide it silently. The case for still forking is that the shared shape
proven so far is between two *storms*, and this is not one — an implosion with a
discharge beat has different layers and a different timeline, so a resource
abstracted from three files where the third barely fits would be abstracted from
the wrong thing. The case against is that this is exactly the point the doc
names, and the new "everything is a parameter" rule pushes the same direction.

**Recommendation: fork, and record the reasoning in the new profile's header
comment the way `FireStormProfile` does.** Put the extraction on
`BACKLOG_LONGTERM.md` with the trigger restated as *the next effect that is
structurally a storm*. Confirm with the user before proceeding either way.

## Parameterization requirements

Beyond the general rule, these specifically must be profile constants and
uniforms, because they are the ones that will be retuned:

- The four beat boundaries, as normalized fractions, so the charge beat can be
  lengthened or shortened without touching motion code.
- Spiral tightness, inward speed, and the angular-rate-versus-radius
  relationship as separate values — collapsing them loses the wind-up.
- Mote count, per-mote alpha, and size range. Retune these from the new volume
  before anything else (§4): this geometry concentrates every particle into the
  centre by the charge beat, which is a far smaller volume than the fire
  column's, so the fire storm's numbers will saturate. Expect to need fewer
  motes and lower alpha than 80 / 0.34, and lower the alpha rather than the
  colours when the core clips to white.
- Discharge width, length, speed, and its two colours independently.
- Core size and its brightness curve.
- The mote spawn band on the boundary — how tightly they hug it.

## Proof checkpoints — stop and show at each

Per §6. Do not run past a bad frame.

1. **Skeleton** — registered, spawns, ground wash on the right footprint. One
   capture.
2. **Gather + spiral** — sheet across the first two beats. The question being
   answered is whether individual motes are legible and whether the spiral
   reads as winding up. Density and alpha get settled here, before anything
   else is built on top.
3. **Discharge** — sheet across the release. The question is whether it reads as
   thin and fast.
4. **Radius sweep** — one sheet each at radius 1, 3, 5. Radius 1 is where a
   boundary-spawned field is most likely to leak outside the footprint; 3 is the
   carrier's own and the one the look is judged at.
5. **Final** — carrier's real radius and shape, plus a fire-storm capture
   proving the fork did not break the donor through shared `VfxTextures`.

```bash
Godot_v4.4-stable_win64.exe --path . scenes/debug/VFXDebugScene.tscn \
  --effect=magenta_reduction --radius=3 --seed=7 --hide-hud \
  --capture-at=0.10,0.28,0.45,0.62,0.80,0.94 --capture-sheet --resolution 1400x900
```

Run `--import --headless` before the first scene launch: a scene launch does not
parse new scripts, so a new `class_name` never loads and a probe can print clean
while proving nothing. It also generates the `.uid` sidecars, which are
committed alongside the `.gd` and `.gdshader` files.

## Work items and model routing

| # | Item | Model |
| --- | --- | --- |
| 1 | Fork decision above, confirmed with the user; backlog entry if forking | **Opus 5** |
| 2 | `MagentaReductionProfile.gd` — full constant set, provenance labels, budget asserts | **Sonnet 5** |
| 3 | `magenta_implosion.gdshader` — inward spiral off `INDEX` + `playback_time`, beat boundaries, diamond clamp | **Opus 5** |
| 4 | `MagentaReductionEffect.gd` — layers, lifecycle, `setFootprint()`, layer toggles | **Sonnet 5** |
| 5 | Catalog row + `VFX_PROFILE` on the spell + `--import --headless` | **Sonnet 5** |
| 6 | Checkpoints 2 and 3, with retuning between them | **Opus 5** |
| 7 | Radius sweep and fixes | **Sonnet 5** |
| 8 | Goldens, and update `docs/VFX_DESIGN.md` if anything here changed the contract | **Sonnet 5** |

Items 3 and 6 carry the look and the judgement calls; the rest is contract-
following against a written spec.

## Scope boundaries

- Presentation only. No gameplay, targeting, damage, or catalog-schema change
  beyond adding `VFX_PROFILE` to the one spell.
- `AUTHORED` / `DERIVED` labels only. No reference-footage decomposition — §4
  records that it was the ice storm's single most expensive activity and does
  not transfer.
- `data/spells.json` currently has unrelated uncommitted edits to `Ice Plow` and
  `Smoke Tower` radii. Leave them alone; do not sweep them into a commit.
