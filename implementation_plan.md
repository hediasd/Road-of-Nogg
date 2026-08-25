# Polygonal Technique Aura Cycle

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

**Depends on:** AURA-1 and user acceptance of its silhouette checkpoint.

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

**Depends on:** AURA-2 and a blocking user decision naming the production spell
or explicitly retaining the profile as debug-only. The current spell pipeline
supports one `VFX_PROFILE`; combining this charge aura with an existing impact
effect is excluded unless separately authorized as shared-pipeline work.

**End state:** If a carrier is approved, only that spell selects the new aura
and its gameplay values remain identical. If the user retains debug-only scope,
the catalog entry remains an authoring profile and no spell data changes. In
either case, the effect's current geometry, ownership, texture provenance,
timeline, ceilings, tunables, and capture command are documented.

**Implementation:** Update at most the chosen spell's presentation metadata;
do not change damage, range, targeting, resolver behavior, adapter flow, or any
existing effect. Update `docs/VFX_DESIGN.md` and the module map only where they
own current runtime truth. Record approved goldens after the visual checkpoint.

**Risk:** A carrier that already owns a custom impact profile would silently
lose it; source anchoring can drift on elevated terrain; documentation can claim
battle behavior that a debug-only decision never exercised.

**Adds to final validation:** Explicit debug-only or production status, correct
carrier metadata if selected, unchanged gameplay catalog values, current docs,
goldens, and real source anchoring when production integration exists.

**Resolution:** Not started; blocked after AURA-2 on carrier/user acceptance.

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

## Deliberately excluded

- Any modification or extraction of an existing VFX implementation, shader,
  texture, material, factory, timeline, or lifecycle method.
- Multiple simultaneous VFX profiles per spell or a new pre-cast pipeline.
- Gameplay, balance, targeting, damage, animation-queue ownership, or model
  material mutation.
- A pixel-for-pixel copy of the supplied Digimon World 1 frames. They define
  structure and motion; the project texture and shader are original assets.
