# Charge aura v2: spin, sustained churn, expand-and-flatten release

2026-08-29. The technique charge aura (now `technique_charge_aura_v1`) grows
out of the floor, bounces, and settles into a quiet idle. v2 is a distinct
effect built alongside it, not a retune: the whole ring stack turns around the
caster at a fixed rate, every blade churns hard for the full charge instead of
settling, and at 1.00s the charge disperses outward rather than fading in
place. v1 stays untouched and previewable; this cycle forks it under files v2
owns, per the sibling rule in `docs/VFX_DESIGN.md` §4.

Every decision below was made against
`docs/sketches/2026-08-29-charge-aura-v2-spin-and-release.html`, which stays
the record of the reasoning. This file is the shape of the work, not the case
for it.

## Outcome

`technique_charge_aura_v2` exists as its own catalog entry, previewable
side by side with v1, with:
- A ring stack that spins around the caster at a fixed, authored rate and
  direction (not accumulated per frame — a pure function of the clock).
- Faces that read as discrete blades (soft `UV.x` falloff at both edges)
  churning at a sustained ±20%, not a breath that settles.
- A release at 1.00s: a 60ms brightness flash, spin accelerating 2.2×, the
  ring expanding to +70% radius while flattening to 55% height, blades
  extinguishing in a per-angle unzip, ground spill lagging out last. Nothing
  in the release compresses or speeds up the entrance or the spin to
  compensate for the earlier release — see "Present-state facts" below.
- The whole effect ending at 1.50s (1.00s charge + 0.50s release).
- Live tunables for spin rate, differential, churn amplitude, and every
  release constant.
- Verification: rim integrity now that faces are discrete blades, seek
  exactness with rotation animating, foot-stacking under spin, footprint at
  peak expansion, a yaw sweep, and a judgment call on whether the flares
  (kept for v2) survive being spun.

## Present-state facts an executing agent must not "fix"

- **The spin and entrance rates are authored, not derived from the release
  time.** An earlier draft of the sketch scaled the entrance ×0.63 and the
  spin ×1.44 to "recover" the turn and hold that a later release produced —
  Henri rejected this explicitly. The rate is character, not a budget to
  balance against duration. V2-C and V2-D use the *same* rise/period/decay
  and the *same* spin-rate constants regardless of when the release lands.
- **The hold read against a sustained churn is not what v1 measured.** v1's
  "entrance settled" threshold was the core's bounce falling under a flat 3%,
  which matched v1's idle (a ±7.5% breath ramping in). v2's idle is a
  sustained ±20% churn from the first frame. Measuring v2's entrance against
  v1's 3% threshold understates how quickly the bounce stops being the
  dominant motion — see the sketch's "Nothing speeds up to pay for the early
  release" section for the corrected numbers (bounce down to the churn's own
  size by 0.33s, half of it by 0.61s).
- **The release window (0.50s) is the authored constant, not the runtime.**
  The effect's total length (1.50s) is a consequence of `RELEASE_SECONDS +
  RELEASE_WINDOW_SECONDS`, not a duration the release stretches to fill.
  Padding the window to hit some other total is backwards.
- **v1's corner-gap and mask findings still apply and are why blades must be
  discrete.** v1 measured the corner gap at a ±7.5% breath: 0.0337u, 0.8px at
  battle framing, hidden by the mask's ragged top edge. v2's ±20% churn with
  near-full per-blade independence would scale that to roughly 4px of visible
  notch at every corner. The fix, already decided, is a soft `UV.x` falloff
  making each face its own blade rather than a softer churn — do not revisit
  this by proposing to dampen the churn instead.
- **The flares stay in v2 "for now."** Henri's words. v1's verification found
  they read as flat terraced plates at the battle camera's pitch; whether
  spin rescues that is one of V2-F's open questions, not a decision to make
  early by cutting them preemptively.
- **`assets/vfx/technique_charge_aura/aura_panel.png` stays v1's.** v2 takes
  its own copy under its own directory. Do not point v2 at v1's texture path
  — see V2-A.

## Items

### AURA2-A — Fork v1 into files v2 owns

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Mechanical fork-and-rename with no new behavior; the
donor is fully specified and the copy is checked against it for byte-for-byte
render parity.

**Depends on:** none.

**Touches:**
- `src/presentation/effects/TechniqueChargeAuraV2Effect.gd` (new)
- `src/presentation/effects/TechniqueChargeAuraV2Profile.gd` (new)
- `assets/shaders/effects/technique_charge_aura_v2.gdshader` (new)
- `assets/vfx/technique_charge_aura_v2/aura_panel.png` (new, copied from v1)
- `src/presentation/effects/SpellVfxCatalog.gd`

**End state:** `technique_charge_aura_v2` is a catalog entry
(`TechniqueChargeAuraV2Profile.PROFILE_ID`), previewable in the debug scene,
and renders **identically** to v1 at every seek position and seed — this item
makes no behavior change. Class names, the shader's preload path, and the mask
path are updated to the v2 files; nothing else changes.

**Implementation:** Copy rather than `git mv` (v1 must remain intact).
Rewrite `TechniqueChargeAuraV1*` identifiers to `TechniqueChargeAuraV2*`
throughout the copies, `technique_charge_aura_v1.gdshader` references to
`technique_charge_aura_v2.gdshader`, and the mask preload to
`res://assets/vfx/technique_charge_aura_v2/aura_panel.png`. `PROFILE_ID`
becomes `"technique_charge_aura_v2"`; catalog `display_name` becomes
`"Technique Charge Aura v2 (preview)"`.

**Risk:** A missed identifier leaves v2 silently calling into v1 (e.g. a
stray shader path) — verify by diffing the two files after the rewrite;
every difference should be exactly the renamed identifiers, nothing else.

**Adds to final validation:** v1 renders unchanged after v2 exists
(isolation proof, per `docs/VFX_DESIGN.md` §4's donor guardrail).

### AURA2-B — Blades: discrete faces and sustained churn

**Model:** Opus 5 / GPT Sol

**Model rationale:** The mask has no side margin (v1's own measurement,
alpha ~253 in its edge columns); getting the `UV.x` falloff and the retuned
per-blade amplitude right without reopening the corner-gap problem needs the
full context of that finding and of v1's tip-bright/base-faint grade it must
not disturb.

**Depends on:** AURA2-A.

**Touches:**
- `assets/shaders/effects/technique_charge_aura_v2.gdshader`
- `src/presentation/effects/TechniqueChargeAuraV2Profile.gd`

**End state:** Each face reads as a discrete blade — soft falloff at both
`UV.x` edges, verified against v1's `RING_TIP_BRIGHT` / base-faint grade
still applying per ring. Per-blade churn amplitude retuned to a sustained
±20% (`CHURN_AMPLITUDE`, no ramp, no idle it ramps into — this replaces
v1's `BREATH_MIN`/`BREATH_MAX`/ramp entirely for v2). `BREATH_FACE_MIX`'s
v1 role (bounding the corner step) is superseded by the blade falloff, not
stacked with it.

**Implementation:** One `smoothstep` pair on `UV.x` in the fragment stage
before the existing density/grade math. Confirm blades stay legible at v1's
ten-sided count before considering any face-count change (none is planned).

**Risk:** Retuning churn without the blade falloff first would reproduce
v1's corner-gap failure at ~4px. Land the falloff before raising amplitude
past v1's ±7.5%, and re-measure the gap at ±20% before calling this item
done (folds into V2-F's verification, but a sanity check here catches it
before spin makes it worse).

**Adds to final validation:** Corner-gap re-measurement at v2's churn
amplitude (V2-F does the full sweep; this item's own check is a spot-measure
at rest, no spin).

### AURA2-C — Spin as a pure function of the clock

**Model:** Opus 5 / GPT Sol

**Model rationale:** Determinism is the load-bearing property of this whole
system (`docs/VFX_DESIGN.md` §3) — rotation is the one new quantity in v2
most likely to be implemented as `rotation.y += rate * delta`, which would
break seek exactness silently (a seek would still *look* plausible; only a
byte-compare catches accumulated drift). Needs the judgment to get the
closed-form integral right, not just working code.

**Depends on:** AURA2-A.

**Touches:**
- `src/presentation/effects/TechniqueChargeAuraV2Effect.gd`
- `src/presentation/effects/TechniqueChargeAuraV2Profile.gd`

**End state:** `rotation.y` (or the shader-space equivalent) is set each
frame from a closed-form function of `playback_seconds`, never accumulated.
Rate eases from an authored launch rate to an authored hold rate
(340°/s → 230°/s, unchanged by release timing per the present-state facts
above), with a per-ring differential (core 1.0×, mid 1.15×, outer 1.32×) so
the stack shears rather than moving as one rigid body. Direction is fixed
across casts (no seed dependence).

**Implementation:** The exponential-ease rate has a closed-form integral;
derive and use it rather than numerically integrating per frame (the sketch's
JS prototype numerically integrates for simplicity — do not carry that into
the shader/GDScript implementation).

**Risk:** The obvious wrong turn is `+=` per `_process`. Prove otherwise:
seek to the same normalized time from two different prior positions and
byte-compare the rendered frame (same method v1's AURA-5G used).

**Adds to final validation:** Seek-exactness re-verification specifically
with rotation live (V2-F).

### AURA2-D — The release envelope

**Model:** Opus 5 / GPT Sol

**Model rationale:** Five coupled sub-envelopes (flash, spin acceleration,
radius/height flatten, per-blade unzip, ground lag) that have to read as one
event rather than five independent timers drifting apart, plus the signed
direction that keeps collapse reachable without a branch — this is the item
most likely to look right in isolation and wrong assembled.

**Depends on:** AURA2-B, AURA2-C.

**Touches:**
- `assets/shaders/effects/technique_charge_aura_v2.gdshader`
- `src/presentation/effects/TechniqueChargeAuraV2Profile.gd`
- `src/presentation/effects/TechniqueChargeAuraV2Effect.gd`

**End state:** At `RELEASE_SECONDS` (1.00s): brightness flashes to 1.35× over
60ms before any alpha drops; spin accelerates to 2.2× across the 0.50s
release window; ring radius eases to +70% while height eases to 55%
(`DIRECTION` a signed constant — `+1` expand per this cycle, `-1` collapse
reachable by flipping it, per the present-state facts above collapse is not
re-litigated here, just kept cheap); each blade's alpha fades over 220ms,
starts staggered across a 160ms sweep by blade angle so the ring unzips;
ground spill lags 180ms behind release start and fades last. Total runtime
ends at `RELEASE_SECONDS + RELEASE_WINDOW_SECONDS` = 1.50s exactly (no
padding — see present-state facts).

**Implementation:** One envelope family parameterized by `DIRECTION` rather
than an `if expand / else collapse` branch, per the sketch's plan. Match the
sketch's timings exactly; they are the authored decision, not a starting
point.

**Risk:** Flatten and expand fighting each other visually if their eases
don't share a curve family — use the same ease shape for both so they read
as one motion, not two effects layered.

**Adds to final validation:** none beyond V2-F's general sweep.

### AURA2-E — Live tunables

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Mechanical exposure of already-decided constants
through the existing `tunables()` / `rebuild` pattern v1 established; no new
design judgment once V2-B/C/D land.

**Depends on:** AURA2-B, AURA2-C, AURA2-D.

**Touches:**
- `src/presentation/effects/TechniqueChargeAuraV2Effect.gd`

**End state:** Spin rate (launch/hold), per-ring spin differential, churn
amplitude, and every release constant (release time, window, flash, expand
factors, unzip sweep/fade, ground lag, direction) are live tunables,
following v1's established `rebuild: true` discipline for anything baked
into built geometry (radius/lean-affecting constants) versus live-pushed
uniforms for everything else.

**Implementation:** Mirror v1's `_pushRingUniforms` / `tunable()` pattern
(`TechniqueChargeAuraV1Effect.gd` is the reference). Group as Spin, Churn,
Release in the debug panel.

**Risk:** none beyond the general risk of a rebuild-tier constant misflagged
as live (caught immediately by the debug panel behaving wrong, not silent).

**Adds to final validation:** none.

### AURA2-F — Verification and the design note

**Model:** Opus 5 / GPT Sol

**Model rationale:** Same verification discipline as v1's AURA-5G, which
found a real defect (the flutter tearing every corner) that a less
thorough pass would have missed; this item also has to render a judgment
call (do the flares survive spinning) that needs the effect actually
running to answer, not guessed at.

**Depends on:** AURA2-A, AURA2-B, AURA2-C, AURA2-D, AURA2-E.

**Touches:**
- `debug/` (new harness, gitignored)
- `docs/VFX_DESIGN.md`
- `BACKLOG_LONGTERM.md` (if the flares are cut, or if either open question
  resolves into a follow-up item)

**End state:** A verification harness (v1's `debug/aura5_proof.gd` is the
template) confirms: rim integrity at peak expansion across a yaw sweep now
that faces are discrete blades; seek exactness with rotation live, at rest
and mid-release; foot-stacking under spin; footprint at peak expansion
(does +70% radius reawaken the area-marker read v1 held its footprint to
avoid — present-state facts flags this as genuinely open); node/instance/
draw-call ceilings unchanged. `docs/VFX_DESIGN.md` gains a v2 section
alongside v1's, written the way v1's was — measured claims, not
descriptions. The flares-under-spin judgment call is made and recorded
(kept, cut to one, or cut entirely) with the reasoning, not left as a TODO.

**Implementation:** Adapt `debug/aura5_proof.gd`'s structure; do not
copy-paste-modify without updating the ring-count/blade-discreteness
assumptions the corner-gap analytic check relies on (blades are now
independent surfaces at their edges, not welded).

**Risk:** none beyond the general risk of a verification pass that confirms
what's expected instead of measuring what's there — read v1's AURA-5G
commit for the standard this is held to.

**Adds to final validation:** this item *is* final validation.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | AURA2-A | boundary item; everything after depends on it existing |
| 2 | AURA2-B, AURA2-C | shader fragment/churn vs. rotation/spin — different functions in the same two files, but AURA2-D depends on both landing first so they must both complete before wave 3 opens even though their diffs don't overlap |
| 3 | AURA2-D | needs B and C both committed |
| 4 | AURA2-E | needs D committed |
| 5 | AURA2-F | validation, alone, quiet tree |

Wave 2's two items touch the same files (`technique_charge_aura_v2.gdshader`,
`TechniqueChargeAuraV2Profile.gd`) in different functions. Treat them as
sequential within the wave rather than dispatching both sessions at once
unless the executing agent partitions the diff by hand — the wave table
records the dependency graph, not a concurrency guarantee here.

## Deliberately excluded

- **Retuning the entrance or spin rate to compensate for release timing.**
  Considered and rejected twice (see present-state facts). Not a knob for a
  future session to turn.
- **Cutting the flares now.** Considered; deferred to AURA2-F where it can be
  judged against the running effect instead of guessed at.
- **A face-count change.** Not discussed; v1's ten sides are assumed to carry
  over unless AURA2-B finds a concrete reason otherwise.
- **Wiring v2 into a real spell cast.** Both v1 and v2 stay debug-catalog
  previews; production integration is the separate backlog item in
  `BACKLOG_LONGTERM.md`.
