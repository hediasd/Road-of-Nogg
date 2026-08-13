# Spell-Cast Aura Source-Convergence Cycle

**Opened 2026-08-13.** The previous plan contained the full history of the
generic spell-cast aura experiments through the measured plume-atlas rebuild.
Those implementation steps are committed and recoverable with
`git show 1a942bf^:implementation_plan.md`. Its consolidated battle/lifecycle
validation did not complete because `Battle25D` still exits with the
pre-existing script-resource access violation already described in
`BACKLOG_CRITICAL.md`; that genuinely open work remains there. No other open
item required relocation. A repository search found the retired plan's item
identifiers only inside the plan itself, so no persistent reference needed
rewriting.

This cycle replaces iteration-by-accumulation with iteration-by-evidence. The
eleven supplied Ragnarok Online frames are the visual authority. The user's
additional onset direction is authoritative for the uncaptured lead-in: the
effect starts with zero visible aura, ignites at the footprint, and rises from
that footprint rather than fading in as an already complete plume.

## Outcome

Recreate the reference as a fast, body-enclosing, world-space casting aura:

- zero aura at normalized time `0.0`;
- a footprint ignition followed by a measurable bottom-to-top emission front;
- a wide, continuous blue/cyan plume whose sharp ghost spikes surround the
  model, rotate, and oscillate without becoming literal shards;
- no slow puddle rings, opaque column, billboard card, horizontal striping, or
  visible polygon terraces;
- the eleven recorded source states reproduced at comparable character scale;
- stable appearance under the moving battle camera, exact seek/replay, element
  tinting, and the established VFX lifecycle contract.

## Mandatory comparison-and-replan gate

Every implementation item below is one session and one focused commit. It must
start from a task-owned clean boundary while preserving the unrelated modified
`gamerefs/` files and `src/battle_sim/PassiveSkillResolver.gd`.

At the end of **every** item, before its commit:

1. Capture the affected states with the same orthographic camera, character
   scale, crop, exposure, background, seed, and native/retro setting as the
   frozen baseline. Focused debug captures are allowed here; the full battle
   flow remains consolidated in the final item.
2. Build a paired source/current sheet. For onset work also build a dense
   `0.00`-to-first-source-state sheet; for carrier work also capture yaw
   `0/90/180` on dark and light terrain.
3. Recompute at least: faint and dense silhouette bounds, width by height,
   vertical energy centroid, footprint/aperture radius, angular energy profile,
   temporal frame delta, blue/cyan luminance ratios, body-overdraw, and
   horizontal-band periodicity. The extracted-source branch may add layer and
   keyframe metrics but may not remove these common metrics.
4. Record a per-metric verdict of **closer**, **unchanged**, or **worse**. A
   primary silhouette, onset, body-occlusion, or banding regression prevents
   advancement: rework or revert it inside the current item.
5. Rewrite the still-pending items in this file when the evidence changes the
   next technique, tolerances, or file scope. Do not preserve a planned
   technique merely because it was planned. Record the comparison evidence and
   replanning decision in the current item's Resolution, then commit only the
   task-owned files.

Untracked comparison captures may contain user-supplied or locally extracted
Ragnarok material and must stay outside commits. Only measurements, hashes,
layer descriptions, and original Road of Nogg assets may enter the repository.

## Items

### AURA-R1 — Identify the original effect and freeze the convergence baseline

**Model:** Opus 5 / GPT Sol

**End state:** The current Road of Nogg render and all eleven source frames have
one reproducible comparison pipeline and one frozen baseline report. Source
forensics tests the most plausible client effects first—especially the
water-element cast-initiation effect `EF_BEGINSPELL2`, followed by the relevant
newer blue cast-aura/cone variants—and accepts a candidate only when its
silhouette and temporal behavior match the supplied frames. The report says
whether the effect is an archive-authored STR/texture composition, a sprite
animation, a client-native effect, or still unresolved; it records layer count,
blend mode, texture references, transforms, alpha, rotation, and frame timing
where those facts are actually observable.

**Asset decision (blocking only the extraction branch):** Inspect only a
Ragnarok client/archive the user owns or is authorized to inspect. The user must
provide its local path before that branch runs. Do not download unofficial GRFs
or commit/distribute Gravity textures, sprites, STR files, or rendered
extractions. If no authorized archive is available, resolve this item through
the screenshot/video baseline and mark archive identity as unavailable; later
items remain executable.

**Implementation:** Extend the existing measurement/generation tooling around
`assets/vfx/spell_cast_aura/source_measurements.json` so one command produces
registered paired sheets and machine-readable metrics. For the authorized
asset branch, inventory `data.grf`/`sdata.grf`, extract only candidate files to
an external evidence directory, reproduce the candidate through a compatible
viewer/client where possible, and capture the client's file-access trace while
triggering the candidate effect so referenced textures can be distinguished
from unrelated archive neighbors. Hash rather than import the proprietary
files. Treat `.str` as one possibility, not an assumption: the early cast aura
may be constructed by client code from texture primitives.

**Risk:** Choosing the wrong regional/client-era effect would optimize the
replica toward a visually related but different animation; retaining extracted
art would introduce a licensing and compatibility surface.

**Adds to final validation:** Exact source candidate/provenance status, frozen
source registration, deterministic comparison command, baseline metrics, and
an explicit record of what may and may not be shipped.

**Item gate:** Run the mandatory gate on all eleven states. The source candidate
is accepted only on visual/timing evidence. Replan every later carrier/material
assumption from any recovered layer data before committing.

**Resolution (2026-08-13):** Implemented through the screenshot branch; pending
end-of-plan validation. No authorized archive path was available, so exact
effect identity remains explicitly unresolved. `EF_BEGINSPELL2`,
`EF_BEGINSPELL_N1`, and `EF_BEGINSPELL_N2` remain candidates rather than
accepted facts, and no Ragnarok archive or extracted asset was downloaded,
read, retained, or committed.

- `compare_replica.py` now registers the red/orange debug proxy onto the source
  character's centre, feet, width, and height, then emits one paired sheet and
  one JSON report from eleven ordered source/render paths. The user-supplied
  files are all 340x340; the earlier measurement contract was 350x350, so the
  report records their original sizes and the deterministic bicubic conversion
  rather than silently mixing coordinate systems.
- The frozen Road of Nogg command is native rendering, black comparison
  isolation, camera size 5 focused on target, ice tint, and seed 7 at the
  eleven source checkpoints. The tracked report stores source/render SHA-256
  hashes, body registration, per-state measurements, temporal deltas, and the
  capture label. Source pixels and the paired sheet remain untracked.
- Signed sequence means expose the primary gap: faint width is 0.7602 character
  widths too small; dense width is 0.2680 too small; dense height is 0.2437
  character heights too large; the dense-energy centroid is 0.3716 too high;
  and the aperture is 0.4827 character widths too large. Mean angular-profile
  L1 distance is 1.0491, and the replica's mean frame delta is 0.3205 versus
  the source's 0.4976, confirming that the tidy petal cage reorganizes too
  little compared with the irregular source plume.
- The paired sheet also exposes flattened, repeated tip terraces. The scalar
  band/edge probes do not uniquely classify this artifact because the source's
  legitimate radial rays carry strong row-edge energy too. AURA-R3 is therefore
  replanned to require enlarged tip crops and direct visual continuity evidence
  alongside source-relative metrics; no single stripe score can pass it.
- Rendering code and assets were untouched, so every visual metric is
  **unchanged** for this item. The item advances because it freezes the target
  and makes later closer/worse verdicts reproducible, not because it improves
  the look.
- All eleven Godot captures are byte-identical across two independent rendered
  launches. The JSON report and paired sheet are byte-identical across repeated
  comparator runs. Godot 4.4's escalated editor import/parse exited 0 and the
  focused `git diff --check` passed. No battle was launched, as required for an
  implementation item. The backlogs needed no edit: asset extraction remains
  an optional authorized-input branch here, while the pre-existing battle exit
  defect is already described in `BACKLOG_CRITICAL.md`.

### AURA-R2 — Replace global fade-in with zero-to-rise emission choreography

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-R1.

**End state:** At `0.0` every aura layer contributes zero pixels. The footprint
then ignites from zero and seeds a vertical reveal front. Plume energy exists
only below that rising front until it reaches the first measured source state;
the complete crown never appears early under a low global opacity. Root
brightness, reveal height, plume amplitude, and terminal fade are independent
timeline channels, all derived from normalized playback progress with no
`TIME` dependency. Forward seek, backward seek, replay, pause, and speed scale
produce the same image at the same normalized time.

**Implementation:** Add an explicit onset window to
`SpellCastAuraProfile.gd`; pass root ignition, reveal-front height, and reveal
softness through `SpellCastAura.gd` to the footprint, haze, and ghost-ray
materials. Clip/reconstruct plume coverage in world height, feathering only at
the moving front. Keep the roots attached to the ring while the front rises;
do not translate an already complete shell upward. Treat `0.00` through `0.08`
as the evidenced implementation window: `0.08` must still register to source
state 1 while `0.00` is empty, with dense probes at least every `0.01`.

**Risk:** A soft global fade can masquerade as growth in a single still, while
hard clipping can create a scan line or make the aura look like a lifting tube.

**Adds to final validation:** Dense onset captures from `0.00` through the
first source state, proof of zero initial contribution, monotonic rising energy
centroid during emission, absence of pixels above the reveal front, and exact
history-independent seek hashes.

**Item gate:** Compare the dense onset sheet to an extracted original onset if
available and otherwise to the user's explicit zero/rise direction. Reject the
item if a full-height silhouette is visible before the reveal arrives or if the
ring reads as a slow puddle. Replan carrier geometry if clipping exposes its
tessellation.

### AURA-R3 — Eliminate striped terraces and select the world-space carrier

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-R2.

**End state:** The horizontal striped lines and stacked ledges are absent in
native and retro rendering. The carrier reads as continuous rising energy at
all battle-camera yaws, never as flat shards, crossed cards, flower petals, or
a conical wall behind the character. The character remains visibly inside the
plume rather than in front of it.

**Implementation:** Run a controlled source-registered A/B between at least:
(a) a sufficiently tessellated smooth radial curtain whose deformation is
analytic and continuous in the shader, and (b) a small set of curved
world-space ribbons or another carrier justified by recovered source layers.
Do not use a full camera-facing billboard. Increasing the current 24 height
bands alone is not an accepted fix unless the band-periodicity metric, retro
captures, yaw sweep, and cost all prove it solves the underlying terrace
artifact. Retain only the winning carrier and its owned materials. The winning
comparison must move the sequence in the measured directionâ€”roughly 0.76
character-widths broader at the faint envelope, 0.37 character-heights lower
at the energy centroid, and 0.48 character-widths tighter at the apertureâ€”not
merely brighten the existing petals. Include enlarged crown-tip crops in every
A/B; the row-periodicity and edge metrics are supporting evidence because the
source's legitimate radial rays prevent either scalar from identifying the
terrace artifact by itself.

**Risk:** More tessellation may hide rather than solve the defect, while too few
ribbons reproduce shards and too much overlapping transparency obscures the
model or becomes camera-order dependent.

**Adds to final validation:** Native/retro yaw sweeps on dark and light terrain,
horizontal-band score, body-overdraw mask, carrier node/instance/draw cost, and
proof that no camera billboard rule controls the plume.

**Item gate:** Compare each carrier A/B directly to the same source states and
choose on recorded evidence. If neither is closer in both silhouette and
continuity, commit no visual carrier change, update this item with the failed
evidence, and replan a third technique before advancing.

### AURA-R4 — Reconstruct the source layer stack with project-owned masks and materials

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-R3 and the source-composition findings from AURA-R1.

**End state:** Road of Nogg reproduces the evidenced source composition rather
than accumulating motifs: one controlled footprint/aperture system and the
minimum continuous plume layers needed for low blue body, cyan inner energy,
and sparse ghostly spikes. Masks are original project assets or analytic
functions derived from measurements—not copied Ragnarok pixels. Blend mode,
softness, layer ordering, and energy distribution follow extracted metadata or
the eleven-frame decomposition. Unjustified rings, cards, shards, columns, and
detail layers are removed.

**Implementation:** Re-author the plume-flow masks/atlas and the haze/ghost-ray
shaders from the forensics contract. Match the source's broad low skirt, sharp
upward spike taper, asymmetric gaps, and clean caster composite. Use additive
only where overlap in the source actually accumulates light; use alpha or
premultiplied alpha for smoke-like body where additive overlap would make a
white curtain. Keep the generic element tint contract without forcing a white
core absent from the reference.

**Risk:** Tracing source pixels would create derivative copyrighted art;
procedural noise without measured anchors would return to the same generic VFX
look and errors as earlier passes.

**Adds to final validation:** Layer-isolation captures, source-layer audit,
copyright-safe asset provenance, all-eleven silhouette/color metrics, and
several element tints with a clean character composite.

**Item gate:** Compare footprint-only, plume-body-only, spike-only, and combined
captures. Remove any layer that cannot be mapped to a visible source job. If
the combined render is worse than its strongest isolated layer, replan the
blend/order instead of compensating with brightness.

### AURA-R5 — Match the eleven-state motion, spin, oscillation, and final grading

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-R4.

**End state:** The reconstructed layers follow the reference's full temporal
shape: onset from zero, first rise, crest/trough/swell changes visible in the
supplied sequence, and terminal recession. The plume rotates around the caster;
outer ghost spikes oscillate vertically with restrained phase offsets while
remaining rooted. Motion changes the distribution of energy, not the carrier's
identity. Scale, blue/cyan balance, opacity, aperture, spike density, and
duration converge to the registered source at comparable character scale.

**Implementation:** Retune the eleven-state curves in
`SpellCastAuraProfile.gd` and state interpolation in `SpellCastAura.gd`. Drive
spin and vertical tip oscillation from normalized progress and deterministic
seed data. Use the quantitative comparison report to tune in this order:
silhouette and body enclosure, onset/temporal energy, aperture, color, then
secondary texture detail. Do not use a parameter change to conceal carrier or
blend defects discovered in earlier items.

**Risk:** Excessive spin reads as a rotating cage; synchronized oscillation
reads as breathing geometry; tuning one hero frame can degrade the other ten.

**Adds to final validation:** Registered eleven-frame contact sheet, temporal
delta curve, multi-seed exact-seek proof, motion-path stability, element sweep,
and an explicit final gap report rather than a subjective pass claim.

**Item gate:** Run the mandatory gate across all eleven frames after each tuning
iteration inside the item. No hero-frame improvement may advance if the mean
sequence distance or any primary state materially worsens. Update the final
validation tolerances to the best achieved evidence before committing.

### AURA-R6 — Consolidated gameplay, lifecycle, and regression validation

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-R1 through AURA-R5.

This is the only item that launches the full manual gameplay/integration flow.
Validate the union of all prior evidence in one pass:

1. Reproduce the zero-to-rise onset and all eleven registered states in the VFX
   debug scene; confirm the final tolerances recorded by AURA-R5.
2. Exercise native and retro modes, light and dark terrain, battle-camera yaw
   and pitch movement, several deterministic seeds, and ice/fire/thunder/
   darkness/neutral tints. Confirm the caster stays inside but readable.
3. Exercise pause, speed scale, forward/backward seek, skip-to-settle, overlap,
   replay, disposal, and scene exit. Confirm identical frames for identical
   normalized time and seed.
4. Search every caller of any changed shared primitive/factory and render every
   returned effect, including the existing specific-profile regression set;
   compare stored goldens where they exist.
5. Cast the generic aura in `Battle25D` through the real adapter/event path and
   verify timing, attachment, camera movement, and cleanup. Recheck the known
   shutdown failure: if it still prevents lifecycle acceptance, record the
   evidence and leave the cycle blocked rather than claiming completion.
6. Verify asserted node/instance/draw budgets, Godot 4.4 import/parse, focused
   diff, and `git diff --check`. Remove stale completed aura entries from the
   backlogs and add only newly discovered actionable out-of-scope work.

**Risk:** A debug-scene replica can still fail through battle ownership,
cleanup, shared material reuse, element tinting, or retro quantization.

**Completion:** Record commands, captures, metrics, caller coverage, and manual
observations. If defects appear, fix them in this validation session and rerun
the affected consolidated flow. Once all acceptance evidence passes, grep for
this cycle's item identifiers outside this file, rewrite any persistent hits as
durable descriptions, commit the final resolution, then clear this plan file in
accordance with the plan lifecycle policy.

## Deliberately excluded

- Downloading or redistributing Ragnarok client archives or Gravity artwork.
- Shipping extracted source pixels unless the user separately proves a license
  that permits it and explicitly changes this scope.
- Returning to camera-facing full-plume billboards.
- Fixing the pre-existing `Battle25D` shutdown crash inside a visual item; it
  remains critical prerequisite work unless final validation proves it gone.
- Changing gameplay timing, battle state, spell balance, or spell data.
