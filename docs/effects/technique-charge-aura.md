# Technique charge aura

A polygonal light carrier that rises around a casting entity. Two versions ship
side by side in the debug catalog, both debug-only: **v1** grows out of the
floor, bounces, and settles into a quiet idle; **v2** forks it and never
settles — the stack turns around the caster, its blades churn, and the charge
disperses outward rather than fading in place.

The contract and conventions both implement live in
[`../VFX_DESIGN.md`](../VFX_DESIGN.md). Neither is wired to a spell; that is the
pre-cast telegraph item in
[`../../BACKLOG_LONGTERM.md`](../../BACKLOG_LONGTERM.md).

| version | profile id | shape | length |
| --- | --- | --- | --- |
| [v1](#v1-debug-only-source-silhouette) | `technique_charge_aura_v1` | Three rings: a vertical core wall and two outward flares. Rises, bounces, holds. | 2.00s |
| [v2](#v2-spin-blades-and-a-dispersing-release) | `technique_charge_aura_v2` | Same stack, spun, faces drawn as discrete blades. Flares cut after verification. | 1.50s |

v2 is a fork rather than an edit, per the sibling rule: it owns its own profile,
effect, shader and copy of the mask, and v1 is untouched. Reading them in order
is the intended way round — several of v2's decisions are answers to
measurements v1 recorded.

## v1: debug-only source silhouette

`SpellVfxCatalog` registers it additively; no spell selects it through
`VFX_PROFILE`. Building it from four Digimon World 1 finishing-technique
reference frames was authorized on 2026-08-25 explicitly to defer that
decision. Making it a real pre-cast telegraph needs a spell to select the
profile and a pre-cast timing hook `GodotVisualAdapter` does not currently
have, both of which are live gameplay integration the authoring cycle was
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

### Motion: bounce, breath and ring phase

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

### Anything varying around the rim must be periodic in the angle

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

### Timeline

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

### Budgets and authoring

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

### Open: the flares read as terraced plates at the battle pitch

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
[The flares are cut](#the-flares-are-cut) below.

## v2: spin, blades, and a dispersing release

Forked from v1 on 2026-08-29, owning its own profile, effect, shader and copy
of the mask. It is 1.00s of charge and 0.50s of release.

### The timeline is authored in seconds, and the total is a consequence

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

### Nothing speeds up to pay for an early release

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

### Faces are discrete blades, and that is forced

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

### Spin is evaluated, never accumulated

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

### Verified

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

### The flares are cut

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
