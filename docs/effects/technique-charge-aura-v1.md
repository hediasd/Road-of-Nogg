# Technique charge aura v1

`technique_charge_aura_v1` — debug-only source silhouette. The contract and
conventions this implements live in [`../VFX_DESIGN.md`](../VFX_DESIGN.md);
its successor is
[`technique-charge-aura-v2.md`](./technique-charge-aura-v2.md).

`technique_charge_aura_v1` is a debug-catalog entry, not a production
carrier. It carries a version suffix because a v2 is being designed against
it: v2 forks this profile under its own files per the sibling rule in [`../VFX_DESIGN.md`](../VFX_DESIGN.md) §4 and
leaves v1 untouched, so both stay previewable side by side in the catalog.
`SpellVfxCatalog` registers it additively; no spell selects it through
`VFX_PROFILE`. Building it from four Digimon World 1 finishing-technique
reference frames was authorized on 2026-08-25 explicitly to defer that
decision. Showing it briefly on the casting entity as a pre-cast telegraph is
the intended production direction and is recorded, not implemented, in
[`../../BACKLOG_LONGTERM.md`](../../BACKLOG_LONGTERM.md): it needs a spell to select the profile through
`VFX_PROFILE` and a pre-cast timing hook `GodotVisualAdapter` does not
currently have, both of which are live gameplay integration this cycle was
opened to defer.

The effect is a ground plane and a **three-ring stack**,
`TechniqueChargeAuraV1Effect` reanchored through `configure_cast_context()` to
the cast context's source position only — it never reads target fields. Ring 0
is the vertical core wall the effect originally shipped as; rings 1 and 2 are
flares leaning outward off the floor. `RING_LEAN_DEGREES` is measured from the
ground plane, so 90° is the core and 40° is the shallowest flare. One wall
alone reads as a caster standing in light; the flares exist to make the effect
read as something coming up out of the ground instead.

| ring | lean | base r | resting reach | opacity | launch | period | overshoot |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 core | 90° | 0.74u | 1.62u tall | 0.47 | +0ms | 420ms | +30% |
| 1 mid flare | 62° | 0.78u | r 1.02u, 0.46u tall | 0.32 | +40ms | 320ms | +40% |
| 2 outer flare | 40° | 0.90u | r 1.16u, 0.22u tall | 0.22 | +80ms | 260ms | +48% |

All three rings are appended into **one `ArrayMesh` surface**, 120 vertices,
each face still four unwelded vertices mapping the complete `aura_panel.png`
mask rather than stretching it around the circumference. Three
`MeshInstance3D` children would have been three geometry instances and three
draw calls against authored ceilings of two; one surface is one of each, so
the stack is free at the only budget ever asserted. A vertex carries its ring's
index in `COLOR.r` as 0.0 / 0.5 / 1.0 — the three values that round-trip
exactly through 8-bit vertex colour whatever compression the mesh ends up with
— and that identity is the only thing the shader needs to look the rest of a
ring's constants up from its uniform arrays.

`aura_panel.png` is `AUTHORED`: generated with the editor's built-in image tool
and downsampled to 64×64, no external reference traced. Two measured facts
about it drive design decisions elsewhere in this effect. Its **side columns
run at alpha ~253** — there is no horizontal margin, so panels butt together at
full opacity and a height difference between two faces leaves a hard step at
the corner they share with nothing to hide it. Its **vertical profile tapers
hard**: over the wall's own sampled range the mask carries 2% of peak alpha at
the tip, 24% a tenth of the way down, 53% a quarter down and 95% by halfway.
That taper is the core's top edge, and it is generous enough to absorb a
sub-pixel corner step.

The wall renders both faces (`cull_disabled`) so it encircles the source at
every camera yaw; an earlier `cull_back` pass showed only the near face. The
core's `RING_OPACITY` is 0.47 per face, chosen so two overlapping faces
integrate under `blend_mix`/`depth_draw_never` to the single-face peak of 0.72
the silhouette was accepted at (`1 - (1 - 0.47)^2 ≈ 0.72`). The flares are
dimmer because they are meant to flick rather than dominate, and because near
and far halves of three rings can overlap six deep at the foot. They also
invert the core's vertical grade: the core is faint at its base and strong up
top (`WALL_BOTTOM_STRENGTH`), a flare is near-zero where it meets the floor and
brightest through its leading third (`RING_TIP_BRIGHT` blends between the two
curves, a float weight rather than a bool because the shader's uniform arrays
are float only). Piling three rings' density at the foot would otherwise build
exactly the solid collar `WALL_BOTTOM_STRENGTH` exists to prevent — measured at
0.790 peak with all three rings against 0.732 for the core alone, so the flares
add 7.9% there rather than a collar.

The ground layer is a radial spill centred on the source, not a rim — a bright
annulus already means "this area is affected" elsewhere in this project's
vocabulary (danger zones, movement range), which is the wrong statement for a
non-area effect. `GROUND_DIAMETER_U` is sized against the outer flare's **built**
radius (1.3375u), not its resting one (1.1605u): the flare reaches the larger
figure during its own launch, and a plane sized against the resting radius
leaves the flare's peak sitting outside its own light.

## Motion: bounce, breath and ring phase

Motion is a pure function of a `playback_seconds` / `playback_time` pair the
effect pushes from its own clock and a small per-cast seed; the shader never
reads `TIME`. That is the whole mechanism behind normalized seek landing
exactly on the frame the same seek produced before, and behind pause/speed
needing no special handling — a playback scale of zero simply stops changing
the pushed value. The oscillator lives in the shader rather than in GDScript
because its phase varies per vertex, so it has to be evaluated per vertex. The
seed offset must stay small: it is added to the noise coordinate *after*
scaling by `noise_scale_coarse`/`noise_scale_fine`, never before. An earlier
version wrapped the seed up to a few hundred and added it before scaling, which
pushed the hash's `fract()` past float32's fractional precision and collapsed
every seed to an identical pattern.

Three systems drive one height, and each ring runs all three with its own
constants:

- **The bounce.** A launch to peak on an ease-out cubic, then
  `1 + overshoot·e^(-decay·τ)·cos(ωτ)`. The two halves meet at the peak by
  construction — the cosine is 1 there — so there is no join to hide. It
  crosses *below* the resting length on its first dip, which is the beat that
  makes the entrance read as energy arriving rather than as a bar filling up.
- **The breath.** An idle that never stops, from two unrelated rates so it has
  no readable loop or countable beat. Its amplitude ramps from `BREATH_MIN` to
  `BREATH_MAX` on the core ring's own decay term, so it never competes with the
  entrance and arrives exactly where the aura would otherwise go still. The
  handoff falls out of the arithmetic instead of being scheduled: around 1.04s
  the decaying bounce drops under the breath's amplitude.
- **The ring phase.** The entrance is spread around the rim so the dip sweeps
  rather than happening everywhere at once.

Height alone was not enough to make the breath visible. At the battle camera's
framing the whole aura is roughly forty pixels tall, so ±7.5% of height is two
or three pixels. The same breath factor is therefore also coupled into
brightness (`BREATH_BRIGHT_COUPLING`, ~1.6×) and into the top-edge flutter
amount, carried from the vertex stage to the fragment stage in a
`v_breathFactor` varying. Brightness is legible at any size; height alone was
not.

Growth is a vertex scale, not a reveal. Base and tip of a ring sit on the same
radial line, so the base is recoverable from the built vertex and the ring's own
radius alone, and the whole motion is `mix(anchored, VERTEX, extension)` —
radius and height interpolating together so a flare pivots open at the floor.
The mesh is built at a **ceiling extension** derived from each ring's own
overshoot and breath scale (`ring_ceiling_for()`, because both multiply), which
is what keeps the scale factor at or below 1: the mask can never be asked to
cover geometry that does not exist, and an overshoot never needs a rebuild.
Measured headroom is 6.9% / 9.4% / 11.8% per ring — the clamp never engages, so
no bounce is being clipped. `WALL_HEIGHT_U` is consequently the core's *resting*
length, not its built one.

Charge noise is sampled in mesh space, not in UV. Sampled in UV it would squash
and stretch with the ring, and since the height is now never constant the
texture would look like the thing breathing instead of the body.

## Anything varying around the rim must be periodic in the angle

This is the trap this effect keeps setting, and it has caught two different
quantities. A value that ramps linearly with `theta` wraps at ±π and tears at
exactly one corner; a value taken from `UV.x` reads 1 on one side of a shared
corner and 0 on the other and tears at *every* corner.

Neighbouring faces are built with coincident corner vertices, so any quantity
derived from **vertex position** resolves to the same value on both sides of a
corner and cannot tear. The entrance phase is taken from
`atan(VERTEX.z, VERTEX.x)` and shaped as sines of that angle for exactly this
reason. The edge flutter originally sampled `UV.x` and tore the rim at all ten
corners at once with the same sign at each — a regular sawtooth rather than the
flame licks intended. Measured over a full-timeline sweep at every corner of
every ring, the flutter contributed 0.0714u of the core's 0.0906u worst gap
against the 0.0327u the deliberate per-face breath contributes. Sampling a
point on the ring's own circle instead dropped the flutter's contribution to
0.0013u and the core's worst gap to 0.0337u — 0.8 px at battle framing.

The breath is the deliberate exception: it is taken **per face**, from
`atan(NORMAL.z, NORMAL.x)`, so panels shimmer against each other. That is what
`BREATH_FACE_MIX` bounds, and it is why the per-face term is a smooth
three-lobed function of the face's azimuth rather than an independent sample
per face — neighbours stay close, so the step at their shared corner stays
inside what the mask's ragged top edge can absorb.

## Timeline

`DURATION_SECONDS` is 2.00. The oscillator works in real seconds
(`RING_LAUNCH_SECONDS` and friends) so that changing the effect's length does
not silently retune every bounce in it; only the alpha envelopes and the settle
point are expressed as fractions of the duration.

`SETTLE_NORMALIZED_TIME` (0.60) and `RELEASE_START_NORMALIZED` (0.89) are **no
longer the same value**, unlike the shipped single-wall envelope where they
were identical by construction. Nothing is ever fully still once the breath is
running, so there is no exact "settled" frame to point at; 1.20s is where the
core's bounce has decayed under the breath's amplitude, making it the first
frame that reads as charged rather than arriving. With a real hold between the
two, `skip_to_settle()` landing at the release point would put every debug
preview one frame from vanishing. `ACTION_HOLD_FRACTION`, the field
`SpellVfxCatalog` exposes, shares the settle value for the same reason.

The wall's own alpha only has to reach full quickly rather than reproduce the
entrance a second time — the ring geometry's bounce already carries the
silhouette growing in — so `IGNITE_END_NORMALIZED` is 0.03, about a third of the
core's 0.16s rise. The ground carries its **own** envelope: it ignites faster
still (`GROUND_IGNITE_LEAD_NORMALIZED`) so the floor visibly lights an instant
before the ring above it, and it shares the wall's release so the two still
vanish as one source. The ground's brightness additionally tracks the core
ring's bounce per fragment (`GROUND_PULSE_STRENGTH`, floored at
`GROUND_PULSE_FLOOR`), re-flaring on every crest and dimming on every dip,
because a wall bouncing off an unlit floor stops reading as one source with its
own ground contact.

## Budgets and authoring

The build is two `MeshInstance3D` children under one root: 2 geometry
instances, 2 draw calls, 3 effect nodes, asserted at construction against
`MAX_GEOMETRY_INSTANCES` / `MAX_DRAW_CALLS` / `MAX_EFFECT_NODES` and verified
sitting exactly at all three. It declares 28 `tunables()` in ten groups
(Dimensions, Wall, Noise, Motion, Fade, Circle, Bounce, Breath, Ring, Flares).
Eight are `rebuild: true`: `WALL_SIDES`, `WALL_RADIUS_U`, `WALL_HEIGHT_U` and
`GROUND_DIAMETER_U` shape geometry assembled in `_buildOwnedLayers()`, while
`BOUNCE_OVERSHOOT`, `BREATH_MAX`, `FLARE_LEAN_OFFSET_DEGREES` and
`FLARE_REACH_SCALE` feed the ceiling the mesh is built at. `_pushRingUniforms()`
sources its `ring_ceiling` uniform from the same per-ring spec dictionary
`_ringSpecs()` just built the mesh from, rather than recomputing it from the
profile's authored default, so a live override cannot leave the geometry and
the uniform that gates it describing different ceilings.

The Bounce group tunes the core only, and the Flares group moves both flares
together with one lean/reach/opacity triple rather than exposing two
independent absolute sets — six fewer rows, and the mid and outer flares keep
their relative distinctiveness. The lean row's ±20° range cannot push either
flare's authored lean outside the `(0, 90]` bound `_appendRing()` asserts, which
matters because the radial part of a face's normal is `sin(lean)` and that is
the only thing carrying the face's azimuth to the shader.

```bash
Godot_v4.4-stable_win64.exe --path . scenes/debug/VFXDebugScene.tscn \
  --effect=technique_charge_aura_v1 --seed=7 --hide-hud \
  --capture-at=0.08,0.185,0.29,0.60,0.94 --capture-sheet --resolution 1400x900
```

Those five normalized stops are the launch peak (0.16s), the first dip (0.37s),
the second crest (0.58s), the idle at the settle point (1.20s) and mid-release
(1.88s). No golden set exists yet for this effect; the checkpoints that verified
it used standalone harnesses (gitignored, under `debug/`) rather than the
debug-scene capture path, because they needed byte-comparison of seek and seed
determinism, an analytic sweep of corner gaps and extension headroom, and an
alpha-stacking A/B rendered against black — none of which a visual sheet can
carry. The command above is the debug-scene equivalent for a future golden set.

## Open: the flares read as terraced plates at the battle pitch

Verified and unresolved. At the battle camera's 55.8° pitch the two flares
present nearly face-on, and their hard-edged decagonal silhouettes read as flat
concentric plates — a terraced platform rather than light splashing off the
floor. This is the area-marker failure this effect's own ground layer is shaped
to avoid, arriving through the flares instead, and it is the *shape* carrying
that meaning rather than the brightness. It is stable across camera yaw, so it
is not a single-angle artifact. The core wall, being edge-on at the same pitch,
does not have the problem.

The mask's missing side margin is part of why: with panels butting together at
full opacity and the charge noise deliberately floored at 0.55 to avoid reading
as television static, a flare's silhouette is essentially the mask's silhouette,
which is a hard decagon. Softening it is a design iteration on the flare
concept, not a parameter tweak, and is deliberately left open rather than
guessed at.

**Resolved by v2: the answer was to cut them.** v2 kept the flares on the
hypothesis that spin would rescue them, and measured that it does not — see
[`technique-charge-aura-v2.md`](./technique-charge-aura-v2.md).
