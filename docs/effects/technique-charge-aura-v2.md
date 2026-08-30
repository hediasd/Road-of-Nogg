# Technique charge aura v2

`technique_charge_aura_v2` — spin, blades, and a dispersing release. The
contract and conventions this implements live in
[`../VFX_DESIGN.md`](../VFX_DESIGN.md); the version it forked from is
[`technique-charge-aura-v1.md`](./technique-charge-aura-v1.md).

`technique_charge_aura_v2` is a second debug-catalog entry, forked from v1 on
2026-08-29 under [`../VFX_DESIGN.md`](../VFX_DESIGN.md) §4's sibling rule and owning its own profile, effect, shader
and copy of the mask. v1 is untouched and both are previewable side by side.
Neither is wired to a spell; that is still the [`../../BACKLOG_LONGTERM.md`](../../BACKLOG_LONGTERM.md) item.

Where v1 grows out of the floor, bounces and settles into a quiet idle, v2
never settles. The stack **turns** around the caster, every blade **churns**
hard for the whole charge, and at 1.00s the charge **disperses outward** rather
than fading in place. It is 1.00s of charge and 0.50s of release: 1.50s total.

## The timeline is authored in seconds, and the total is a consequence

`RELEASE_SECONDS` (1.00) and `RELEASE_WINDOW_SECONDS` (0.50) are the two
authored numbers; `DURATION_SECONDS` is their sum. That direction of dependency
is deliberate — a 0.50s dispersal stretched to hold some other end goes limp,
so moving the release ends the effect earlier rather than slowing the fade.

| beat | window | what moves |
| --- | --- | --- |
| flash | 1.00–1.06s | brightness to 1.35× and back, before any alpha drops |
| whip | 1.00–1.50s | spin accelerating to 2.2× |
| disperse | 1.00–1.50s | radius to +70%, height to 55%, one shared eased square |
| unzip | 1.06–1.44s | each blade fading over 220ms, starts spread across a 160ms sweep |
| residual | 1.18–1.50s | ground trailing 180ms behind, last to go dark |

The flash comes first and alone, so the release has an onset instead of merely
starting to be less. The unzip is per fragment, staggered by the blade's own
azimuth, so the ring goes out as a wave rather than thirty blades vanishing
together — which is why the wall's own envelope has no release term at all. A
layer-wide fade multiplied on top would flatten that wave back into everything
dimming at once. `RELEASE_DIRECTION` is a signed constant rather than a branch:
+1 disperses, −1 collapses through the same arithmetic.

## Nothing speeds up to pay for an early release

The spin rate and the entrance timing are authored properties, not a budget
balanced against duration. An earlier draft scaled the entrance ×0.63 and the
spin ×1.44 to "recover" the turn and hold that a 1.00s release cost; that was
rejected, and the rejection is the rule. The core reaches **265.4°** by the
release — three quarters of a revolution — and that is the correct amount.

The arithmetic behind the earlier draft was also wrong, which is worth keeping
written down. It measured the entrance as spent when the core's bounce fell
under a flat 3%, giving 1.11s. That threshold is *v1's*, from a version whose
idle was a ±7.5% breath. v2 runs a sustained ±20% churn, and measured against
the motion actually running underneath it the bounce is down to the churn's own
size by 0.33s and to half of it by 0.61s. The entrance is visually over well
before the release with no compression at all.

## Faces are discrete blades, and that is forced

v2's churn is ±20% sustained with a face mix of 0.85, against v1's ±7.5% at
0.45. v1 held its per-face motion small precisely because neighbouring panels
share corner vertices and any difference between them opens a step there; the
mask carries no side margin (alpha ~253 in its edge columns) so nothing hides
it. Measured over the full timeline, v2's worst corner gap is **0.3558u on the
core — 8.8 px** at battle framing, against v1's 0.0337u / 0.8px.

The answer is not a smaller churn. A `smoothstep` pair on `UV.x`
(`BLADE_EDGE_SOFTNESS` 0.26) fades every face out at both vertical edges, so
the shared corner draws **exactly 0.0000** opacity and the gap has nothing to
show in. It also makes the spin read better: you see individual blades sweep
past rather than a wall rotating.

## Spin is evaluated, never accumulated

`spin_radians()` is the closed-form integral of a rate easing from 340°/s to
230°/s, plus an exact integral of the release's whip term. Rings turn at 1.0 /
1.15 / 1.32 times it so the stack shears rather than moving as one rigid body.
Direction is fixed across every cast — a telegraph should be recognised, not
admired for its variety.

`rotation.y += rate * delta` would render an identical picture while playing and
a different one after a seek, because an accumulated value depends on the path
taken rather than the position reached. That is proved rather than assumed: the
harness reaches three instants by three routes — direct seek, seek past and
back, and *actually playing frame by frame* — and byte-compares. The playback
route is the one that catches an accumulator.

Rotation is applied in the vertex stage from a per-ring uniform, not on the
node, because a node rotation cannot carry a per-ring differential. It happens
last, after everything that reads the vertex's own angle: `theta` for the
entrance phase and `face_angle` for the blade's churn are both taken from
unrotated geometry, so they travel with the blade rather than the blade sweeping
past a pattern pinned to world space.

## Verified

Measured by `debug/aura_v2_proof.gd`, all with no failures:

- **Extension headroom** 9.7% / 11.9% / 13.9% per ring — the clamp never
  engages, so no entrance is truncated by geometry built too short. The churn no
  longer decays, so unlike v1 the peak of bounce × churn can land anywhere in
  the timeline; it lands around 0.15s.
- **Visible footprint** peaks at **1.86u across**, inside the 2.32u v1 held
  itself to for the area-marker read. The *geometry* reaches 4.33u by 1.44s,
  but the blades are extinguishing as they fly out, so that figure is never
  drawn. Measured off the rendered image rather than computed.
- **Alpha stacking at the foot** peaks at 0.770 under spin, against v1's 0.732.
  No collar.
- **Seek exactness** holds mid-charge and mid-release, with rotation and the
  release both live; the seed still varies the draw.
- **Budgets unchanged**: one surface, 120 vertices, 3/3 nodes, 2/2 instances,
  2/2 draw calls. The whole three-ring stack is one extra surface's worth of
  vertices, not extra passes.

## The flares are cut

v1 left open whether spin would rescue the flares. It does not. Captured at six
camera yaws half a face apart and at three points in the timeline, they read as
a segmented flat ring at every one — *closer* to an area marker than v1's
continuous version, because the blade gaps make it look like a deliberately
drawn circle.

The cause is geometric rather than a tuning miss: a surface leaning 40° or 62°
off the ground presents nearly face-on to a camera pitched 55.8° down, so it
projects as a plate however it is graded or dimmed. Reviving the idea needs
different geometry — a much steeper lean, or a different carrier — not a pass
over these numbers.

`RING_OPACITY` is therefore `[WALL_OPACITY, 0.0, 0.0]`. The geometry is still
built, because the shader's uniform arrays are sized 3 and the ring identity
baked into vertex colour divides by `RING_COUNT - 1`; that one line is the whole
switch. Cutting them also resolved the footprint question above — the visible
peak fell from 2.98u to 1.86u.

```bash
Godot_v4.4-stable_win64.exe --path . scenes/debug/VFXDebugScene.tscn \
  --effect=technique_charge_aura_v2 --seed=7 --hide-hud \
  --capture-at=0.107,0.55,0.667,0.687,0.853,0.973 --capture-sheet \
  --resolution 1400x900
```

Those six normalized stops are the launch peak (0.16s), the charge (0.82s), the
release (1.00s), the flash (1.03s), mid-unzip (1.28s) and the tail (1.46s).

---
