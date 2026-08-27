# Polygonal Technique Aura Cycle

**This is a single-session cycle. Run one item at a time; do not dispatch it as
a wave.** Its items carry no **Touches** lists and there is no wave table, and
that is not an oversight to repair: AURA-2's write set is derivable from its
stated end state, but AURA-3's is genuinely unknowable until the carrier
decision it is blocked on is made, so no legal wave table can be authored for
it. See `docs/plans/README.md`, "Single-session cycles".

**It also stays on `main`.** It was already in flight when the
branch-per-cycle contract landed on 2026-08-26, and `AGENTS.md` is explicit
that an in-flight cycle is not retroactively moved to a branch. The next cycle
opened gets one.

**Relocated 2026-08-26.** This cycle was authored at `implementation_plan.md`
under the previous one-plan-at-a-time contract, and moved here unchanged when
that file was retired. Its per-item **Resolution** sections predate the rule
that a cycle file is frozen during execution — read them as history, and record
new findings in commit bodies with a `Plan-Item: AURA-n` trailer rather than
editing this file.

**Opened 2026-08-25.** The previous contents were the Battle Legibility Cycle.
Its hover readout, hover reach, status silhouettes, portrait turn-order rail,
and attributed danger zone were committed as implemented pending consolidated
validation; its deep reference card was never started, and its final integrated
validation never ran. Those two genuinely open outcomes now live in
`BACKLOG_CRITICAL.md`. The withdrawn plate and forecast items remain withdrawn.
A repository search found the old cycle's identifiers only in this plan, and
its complete contents remain recoverable with
`git show 61d6576:implementation_plan.md`.

The user approved the visual direction from four Digimon World 1 finishing-
technique frames and chose to begin debug-only. Production carrier selection is
therefore deliberately deferred until the debug effect has been shown and
accepted; no spell data or shared cast pipeline changes before that decision.

## Outcome

An original previewable aura surrounds the debug caster with a bright noisy
ground circle and a low-poly cylindrical wall. Each wall face receives the same
effect-owned square yellow texture: strongest and most opaque at the ground,
then lighter and more transparent toward a mostly level top edge. The wall
flickers slightly in height and luminosity without becoming flame, smoke, or
television static. It is deterministic, seekable, pauseable, speed-scalable,
bounded, and isolated from every existing VFX implementation.

Solar Storm is a read-only process reference: this cycle follows its effect /
profile / shader ownership, local playback clock, tunable, ceiling, and capture
patterns. It does not fork or modify Solar Storm, Aurora Veil, Spell Cast Aura,
`VfxPlayback`, `VfxCastContext`, `GodotVisualAdapter`, or `VfxTextures`.

## Items

### AURA-1 — Build the isolated debug silhouette

**Model:** Opus 5 / GPT Sol

**Depends on:** nothing. The user's debug-only decision resolves the earlier
carrier gate for this item.

**End state:** The VFX debug catalog can play a static, source-bound technique
aura made entirely from new owned implementation and resources. It has two
toggleable layers: a bright ground circle and an open 8-12-sided wall whose
independent faces each map the full square aura texture. The enclosed proxy
remains readable at the battle camera's front, side, and rear yaws.

**Implementation:** Add an effect class, profile class, shader, and original
square RGBA texture under names owned by the new preview profile. Build the wall
as an effect-local `ArrayMesh` with per-face `0..1` UVs so the texture repeats
once per polygon rather than stretching around the circumference. Keep the
bottom vertices grounded, omit the top cap, and add a separate horizontal
circle/ring just above terrain. Register one additive debug-catalog row; do not
edit any existing row or donor file. Anchor through the existing cast context's
source position without widening that context.

**Proof checkpoint:** Show one static mid-timeline sheet at camera yaw 0, 90,
and 180 degrees, plus ground-only and wall-only captures, before authoring
motion.

**Risk:** Transparent near/far faces can compound into a blown-out tube; per-
face UV seams can reveal the prism; the circle can z-fight with terrain; an
overly smooth or tapered mesh would miss the source's low-poly cylinder.

**Adds to final validation:** Repeated face texture, open polygonal silhouette,
ground contact, layer toggles, source anchoring, camera-yaw consistency, proxy
readability, and unchanged Solar Storm rendering.

**Resolution (2026-08-25):** Implemented; pending end-of-plan validation.

The debug catalog now owns `technique_charge_aura`: a fresh playback and
profile, one owned wall/ground shader, and a 64x64 RGBA opacity mask generated
with the built-in image tool and downsampled into
`assets/vfx/technique_charge_aura/aura_panel.png`. Ten independent wall faces
each map the complete square mask; a separate plane supplies the bright ground
circle. `configure_cast_context()` reanchors only this playback to the existing
source position. The only pre-existing source edit is one additive catalog
preload and row; no donor row or implementation changed.

Intermediate smoke evidence, not final acceptance: the focused editor
import/parse probe exited 0 and generated every new `.uid`; the fresh worktree's
known Windows progress-dialog import crash was bypassed with a temporary copy of
the main workspace's ignored import cache and in-progress font asset, after
which the asset import and rendered harness path completed. Hidden-window
captures at normalized time 0.50 exited 0 for yaw 0, 90, 180, ground-only, and
wall-only. The first plate exposed excessive transparent headroom; the owned
shader now remaps the mask over the full character-height prism while retaining
a faint level top. The accepted checkpoint sheet is outside the repository at
`aura-proofs/aura1-checkpoint-sheet.png`. The temporary font copy was removed;
the user's original font work was never modified.

### AURA-2 — Author deterministic flicker, noise, and lifecycle

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-1, AURA-5 and AURA-6. The silhouette must be settled
before motion is authored on top of it; the 2026-08-26 checkpoint rejected the
ground ring and found the wall open on its far side.

**Touches:**
- `assets/shaders/effects/technique_charge_aura.gdshader`
- `src/presentation/effects/TechniqueChargeAuraProfile.gd`
- `src/presentation/effects/TechniqueChargeAuraEffect.gd`

The debug tunables this item adds are served by a static `tunables()` on the
effect script — `VFXDebugController._tunablesFor()` calls it through the
registry — so no debug or catalog file is written.

**End state:** The aura ignites from the ground, holds as a noisy yellow charge
with restrained coherent height and brightness flutter, then releases cleanly.
Its base never lifts. Motion is exact under normalized seek and deterministic
for a seed.

**Implementation:** Drive the owned shader only from `playback_time`, seed, and
profile constants; never use shader `TIME`. Combine two modest noise scales
with a small bottom-anchored vertical displacement and opacity modulation. Keep
the top broadly level rather than growing flame tongues. Add authored ignition,
hold, and release curves plus debug tunables for dimensions, side count, bottom
strength, fade, noise, flicker, and circle treatment. Implement the complete
`VfxPlayback` lifecycle, reporting, ceilings, pause/speed, settle, overlap, and
disposal contracts without changing their base methods.

**Proof checkpoints:** Show an ignition/hold/flicker/release phase sheet, a
layer-separated sheet, and matched native/retro frames before settling goldens.

**Risk:** Fast high-contrast noise reads as static; large displacement reads as
flame; independent face phases tear the cylinder; transparent sorting can vary
between camera angles or overlap instances.

**Adds to final validation:** Matching-seed replay, different-seed variation,
forward/backward seek, pause, 0.5x/2x speed, settle, overlap cap, disposal,
native/retro motion readability, and stable grounded geometry.

**Resolution:** Not started.

### AURA-3 — Integrate the accepted carrier and document the profile

**Model:** Sonnet 5 / GPT Terra

**Depends on:** AURA-2.

**Carrier decision (2026-08-26):** the user retains debug-only scope for this
cycle. No spell is selected, no spell data changes, and the catalog entry stays
an authoring profile. The user's stated production direction — the aura shown
briefly on the casting entity just before it releases a spell, as a cast
telegraph — is real intent but out of scope here: it implies a spell selecting
it through `VFX_PROFILE`, which is a live gameplay-facing integration this
cycle was opened to defer. It is recorded in `BACKLOG_LONGTERM.md` as a design
direction, not scheduled work, so it is not lost and is not silently attempted
under this item's debug-only scope.

**Touches:**
- `docs/VFX_DESIGN.md`
- `docs/MODULE_MAP.md` (only if it currently omits debug-catalog effects of
  this kind — check current content before assuming a write is needed)
- `BACKLOG_LONGTERM.md` (append-only, per `AGENTS.md`)

**End state:** The effect's current geometry, ownership, texture provenance,
timeline, ceilings, tunables, and capture command are documented in
`docs/VFX_DESIGN.md`. No spell data, resolver, adapter, or existing-effect file
changes. The cast-telegraph direction is recorded in `BACKLOG_LONGTERM.md`.

**Implementation:** Write the documentation entry from the settled AURA-1/5/6
implementation, not from the plan's original description — the wall is now
`cull_disabled` at `WALL_OPACITY = 0.47`, and the ground layer is AURA-6's spill
rather than the original ring. Update `docs/MODULE_MAP.md` only where it
currently owns runtime truth this effect would contradict by omission.

**Risk:** Writing documentation against the plan's original ring-and-cull_back
description instead of the as-shipped AURA-5/AURA-6 result would immediately
misdocument the effect. Confirm current shader/profile state before writing.

**Adds to final validation:** Current docs match shipped behavior, the deferred
telegraph direction is captured in the backlog, and no gameplay file changed.

**Resolution:** Not started.

### AURA-4 — Consolidated aura and cross-effect validation

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-1, AURA-2, and AURA-3.

This is the only item that runs the complete acceptance pass:

1. Capture the new aura across ignition, charge, two flicker states, and release
   at camera yaw 0, 90, and 180 degrees in native, harsh retro, and CRT modes.
2. Toggle ground and wall independently; exercise multiple seeds, exact forward
   and backward seek, pause, 0.5x/2x speed, settle, overlap, disposal, replay,
   and scene exit. Confirm node, instance, and draw-call ceilings remain true.
3. Confirm the aura remains grounded and the enclosed proxy readable on the
   debug world's flat and elevated surfaces. If a production carrier exists,
   cast it through `Battle25D` and confirm queue pacing and gameplay results are
   unchanged.
4. Render every pre-existing `SpellVfxCatalog` row, including every Solar Storm
   rung, and compare stored goldens where present. Any change in appearance,
   timing, playback, or lifecycle fails validation and must be corrected inside
   the new effect's owned implementation.
5. Confirm the focused diff contains no donor/shared implementation changes,
   run the Godot import/parse gate, run `git diff --check`, and inspect staged
   ownership before committing.

**Risk:** Low-resolution alpha ordering, cylinder seams, and subtle motion can
pass static native captures while failing under the actual orbiting camera or
retro pipeline. Existing catalog selection can also regress from an additive
registry edit even when no effect file changed.

**Completion:** Record observations and captures. Fix defects in this session,
rerun the affected consolidated checks, reconcile relevant backlog entries,
grep for this cycle's identifiers outside the plan, and clear this entire plan
after acceptance passes.

**Resolution:** Not started.

### AURA-5 — Close the wall so the aura encircles the source

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** One render-mode token and one profile constant, both in
files this cycle already owns, with the replacement alpha given below as
arithmetic rather than taste. The judgement this item would otherwise carry —
what stays constant when the halves overlap — was settled by the user on
2026-08-26 and is written into the end state, which leaves fully-specified
single-purpose work.

**Depends on:** AURA-1.

**Touches:**
- `assets/shaders/effects/technique_charge_aura.gdshader`
- `src/presentation/effects/TechniqueChargeAuraProfile.gd`

**End state:** The wall renders both its near and far faces, so the aura reads
as a closed ring around the source at every camera yaw. Peak alpha where the
two halves overlap matches the pre-fix single-wall peak.

**Implementation:** The shader declares `cull_back`, which discards every
far-side face of the decagon because its outward normal points away from the
camera. Change it to `cull_disabled`. With `blend_mix` and `depth_draw_never`,
two overlapping faces at per-face alpha `a` integrate to `1 - (1 - a)^2`, so
holding the current 0.72 peak requires `a = 1 - sqrt(1 - 0.72)`, i.e. set
`WALL_OPACITY` to **0.47**.

The near half is unchanged by this fix — it already sits between camera and
model — so the far half only fills in behind the model, where depth testing
hides it against the model's own silhouette. Expect the wash over the model's
lower body to *ease* as a consequence of the lower per-face alpha. That is the
intended direction and must not be "corrected" back.

**Risk:** Disabling culling doubles the fragment count on the wall, which the
draw-call ceiling does not measure. Sorting between the two halves is unstable
in principle because the wall never writes depth; if the far half ever draws
over the near half the silhouette will flicker as the camera orbits, which a
static sheet cannot reveal — note it for AURA-4 rather than fixing it blind.

**Adds to final validation:** Closed-ring silhouette at all four battle yaws,
overlap density unchanged from the AURA-1 baseline, and no sorting flicker
during a camera orbit.

**Resolution:** Not started.

### AURA-6 — Replace the ground ring with an entity-centred spill

**Model:** Opus 5 / GPT Sol

**Model rationale:** This removes an authored visual element and replaces it
with a different function whose falloff shape, reach, and density are decided
against how much the closed wall already deposits at the model's feet. That
composition judgement cannot be stated as a target value in advance, and it is
the item most able to make the aura read as a targeting decal if it is got
wrong.

**Depends on:** AURA-5. The wall's base band changes what the ground still
needs to contribute, so tuning this against the open wall would tune it twice.

**Touches:**
- `assets/shaders/effects/technique_charge_aura.gdshader`
- `src/presentation/effects/TechniqueChargeAuraProfile.gd`

**End state:** The ground layer is a soft radial spill centred on the source:
mildly transparent directly under the model, falling off outward and gone by a
short distance past the wall. No annulus, no hard rim, and no edge that reads as
a bounded area. It shares the wall's mask so it reads as the same light on a
different surface.

**Implementation:** Retire `GROUND_INNER_RADIUS_UV`, `GROUND_OUTER_RADIUS_UV`,
and `GROUND_EDGE_SOFTNESS_UV` along with the shader's inner/outer smoothstep
pair; the faint `ground_fill_alpha` term is the surviving shape and becomes the
whole layer. Author the falloff to still be reaching at the wall radius
(0.74u) and to die shortly after: at the real battle framing the entire aura is
roughly forty pixels tall, so a falloff that vanishes inside the wall will be a
handful of pixels and disappear at the scale that matters.

The brightest part of this gradient is directly beneath the model, where the
model itself occludes it. Judge the layer by the ring of falloff that remains
visible around the feet, not by its centre value.

**Risk:** A ground plane bright enough to read past the model's occlusion is
also bright enough to look like a selection decal, which is exactly the meaning
this item exists to remove — the game already uses bright ground shapes for
danger zones and movement range. Z-fighting is held off only by
`GROUND_HEIGHT_U`'s 0.025u lift; a larger plane makes any depth precision
problem more visible.

**Adds to final validation:** No annulus at any yaw, spill still legible at
ortho size 14, no z-fighting on sloped terrain, and no read as an area marker.

**Resolution:** Not started.

## Waves

Authored 2026-08-26, after the AURA-1 checkpoint. Every remaining item writes
`technique_charge_aura.gdshader`, so **this cycle has no legal parallel wave** —
one shader owns the whole look, and disjointness is impossible by construction.
The table records execution order rather than concurrency.

| Wave | Items | Note |
|------|-------|------|
| 1 | AURA-5 | closes the wall; must precede any tuning judged against it |
| 2 | AURA-6 | ground spill, tuned against the closed wall |
| 3 | AURA-2 | motion, authored on the settled silhouette |
| 4 | AURA-3 | debug-only scope decided 2026-08-26; unblocked |
| 5 | AURA-4 | consolidated validation, alone, quiet tree |

AURA-5 and AURA-6 share both their Touches paths, so they may not run
simultaneously. One session may take them as a **lane** — two items, two
commits — in which case that session runs at the higher of the two tiers,
Opus 5 / GPT Sol.


## Deliberately excluded

- Any modification or extraction of an existing VFX implementation, shader,
  texture, material, factory, timeline, or lifecycle method.
- Multiple simultaneous VFX profiles per spell or a new pre-cast pipeline.
- Gameplay, balance, targeting, damage, animation-queue ownership, or model
  material mutation.
- A pixel-for-pixel copy of the supplied Digimon World 1 frames. They define
  structure and motion; the project texture and shader are original assets.
