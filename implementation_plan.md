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
that footprint rather than fading in as an already complete plume. After the
first convergence pass proved too sharp and petal-like, the cycle was expanded
on 2026-08-13 with a user-previewed fog prototype, component-by-component
integration, and a longer rooted rise/crest/dissolve lifecycle before final
gameplay validation.

## Outcome

Recreate the reference as a responsive, body-enclosing, world-space casting aura:

- zero aura at normalized time `0.0`;
- a footprint ignition followed by a measurable bottom-to-top emission front;
- a wide, continuous blue/cyan plume whose broad ghastly fog surrounds the
  model, with sparse ghost-ray emphasis that never reads as literal shards;
- a longer zero-to-emergence, rise, high crest, and vaporous fade arc, without
  making battle command resolution wait for the entire visual tail;
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
2. Build a paired source/current sheet. Fog-prototype work must build a
   source/current/prototype triptych and include enlarged aperture, body, and
   tip crops. For onset work also build a dense `0.00`-to-first-source-state
   sheet; for carrier work also capture yaw `0/90/180` on dark and light
   terrain.
3. Recompute at least: faint and dense silhouette bounds, width by height,
   vertical energy centroid, footprint/aperture radius, angular energy profile,
   temporal frame delta, blue/cyan luminance ratios, body-overdraw,
   horizontal-band periodicity, edge-density/gradient energy, and the ratio of
   diffuse envelope energy to bright-core energy. The extracted-source branch
   may add layer and keyframe metrics but may not remove these common metrics.
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

**Resolution (2026-08-13):** Implemented; pending end-of-plan validation.

- The old `effect_visibility` onset multiplier is gone. Footprint ignition,
  plume-root ignition, reveal-front height, keyed plume energy, and lifecycle
  decay are independent normalized channels. Both plume shaders hard-zero
  coverage at and above the front and feather behind it; no already-complete
  crown is translated or globally faded into view.
- The authored sequence is empty at `0.00`; the footprint reaches full ignition
  by `0.018`; plume emission begins at `0.010`, its root reaches full strength
  at `0.040`, and the front finishes above UV 1.0 at `0.08`. The ring-only read
  therefore lasts roughly two 0.01 probes (about 23 ms at the 1.15 s duration),
  not a slow puddle phase.
- Nine captures at 0.01 spacing prove zero initial blue/aura pixels, monotonic
  visible height, and monotonic energy-centroid rise after ignition. At `0.08`,
  all 4,484 faint-mask pixels and the complete image are byte-identical to the
  frozen first source-state render.
- The eleven-state comparison classifies every silhouette, aperture, palette,
  angular, and band/edge metric as **unchanged**; no supplied source state got
  worse, and all eleven complete images are byte-identical to the frozen
  baseline. A second process captured the nine onset times in scrambled order;
  every hash matches the ascending-order capture, proving history-independent
  seek. Relative to the user's uncaptured onset authority, zero-to-rise is
  **closer** because the previous full-height alpha fade has been replaced by
  measurable bottom-to-top growth.
- Partial captures at `0.03` and `0.04` expose the current shell as a smooth
  hoop/cup before it becomes the full petal cage. AURA-R3 is replanned to include
  `0.03`, `0.04`, and `0.05` in every carrier A/B and to reject any technique
  whose partial reveal announces its carrier even when its complete state is
  source-closer.
- The comparator now accepts a frozen baseline and reports per-metric
  closer/unchanged/worse verdicts; optional onset frames add zero-pixel, height,
  energy, and centroid checks without mislabeling them as supplied source.
  Godot 4.4's rendered capture log contains no shader/script errors, its editor
  import/parse exited 0, and the focused `git diff --check` passed. No battle
  was launched. No backlog edit was needed: the exposed carrier defect is the
  next in-scope item, and the pre-existing battle shutdown defect is already
  tracked in `BACKLOG_CRITICAL.md`.

### AURA-R3 — Eliminate striped terraces and select the world-space carrier

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-R2.

**End state:** The horizontal striped lines and stacked ledges are absent in
native and retro rendering. The carrier reads as continuous rising energy at
all battle-camera yaws, never as flat shards, crossed cards, flower petals, or
a conical wall behind the character. The character remains visibly inside the
plume rather than in front of it. The aura opens upward **and outward** from its
root: carrier radius is monotonic non-decreasing with world height and the top
is never narrower than the middle. Spike centre paths must not turn back toward
the caster as they rise. Local alpha edges may taper into a point, as they do
in the source; do not mistake legitimate tip taper for inward carrier motion.

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
terrace artifact by itself. Reject every candidate with `top_radius <
middle_radius`, a negative average `dr/dy`, or inward-leaning upper spike paths.
The A/B report must include carrier radii at fixed height fractions and a
screen-space left/right envelope plot for the partial reveal. Interpret that
plot together with the carrier profile: outward mean paths are mandatory, but
the source's pointed upper wisps are allowed to narrow locally.

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

The comparison set for this item now includes the partial-onset states `0.03`,
`0.04`, and `0.05` in addition to the eleven source checkpoints. This addition
is required by the preceding onset evidence: a complete-state render can hide
the hoop/cup silhouette that becomes unmistakable while the reveal front is
mid-carrier.

**Resolution (2026-08-13):** Implemented; pending end-of-plan validation.

- Candidate A increased the shell from 24 to 96 height bands while retaining
  the raster ray lookup. Partial-onset and `0.08` crops retained the inward cup
  and made its closely spaced terraces more obvious. Haze-only/ray-only
  isolation then proved the haze carrier was continuous and every stripe came
  from the ray treatment, so an unrelated ribbon carrier was not justified.
- Candidate B changed both profiles to monotonic outward flares and replaced
  the magnified raster ray mask with a per-fragment analytic angular field.
  Affine UV interpolation, face discard, and single-hemisphere rasterization
  were each tested and rejected before this selection: none removed the
  rowwise steps. Analytic rays remove them because leaning edges are evaluated
  continuously rather than inherited from the atlas's 256 height samples.
- Haze radii are 0.72/1.05/1.38 and ray radii are 0.78/1.14/1.52 at
  root/middle/top. Mesh construction asserts monotonic ordering. The registered
  envelope report records left/right radii at six height fractions; pointed
  mask tips taper locally, but their mean carrier paths do not turn inward.
- Relative to the frozen report, faint-width error improved 0.7602 to 0.4201,
  dense-width 0.2680 to 0.1395, centroid-height 0.3716 to 0.2951, aperture-width
  0.4827 to 0.2257, horizontal-edge ratio 0.0958 to 0.0366, plateau ratio 0.1465
  to 0.0740, and angular-profile L1 1.0491 to 0.8462. Faint height is unchanged.
  Dense-height error changed by only 0.0008, below one registered pixel.
- Palette MAE worsened from 21.53 to 26.55 and direct comparison shows broad,
  pale petals instead of the source's darker smoky curtain; light terrain also
  washes out the current rays. The next material item is revised to treat those
  as explicit alpha, density, softness, and tint failures without restoring the
  rejected inward carrier or raster lookup.
- `0.00` has zero aura pixels. At `0.03`, `0.04`, and `0.05`, visible height and
  energy centroid rise monotonically while the reveal remains rooted. Native
  and 320x240 retro captures at yaw 0/90/180 remain radial and world-space on
  black; native/retro light-terrain captures retain the same geometry. No
  billboard or camera-driven transform was introduced.
- The comparator now emits registered radial-envelope samples and an optional
  plot. The profile documentation records the selected carrier and the reason
  analytic rays replaced the raster mask. Full battle/gameplay acceptance is
  deferred to the plan's final validation item. No backlog edit was needed:
  the remaining visual mismatch is the next in-scope item.

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

**Implementation:** Re-author the haze/ghost-ray material fields from the
forensics contract while retaining the selected outward carrier and analytic
angular ray sampling. Match the source's broad low skirt, sharp
upward spike taper, asymmetric gaps, and clean caster composite. Use additive
only where overlap in the source actually accumulates light; use alpha or
premultiplied alpha for smoke-like body where additive overlap would make a
white curtain. Keep the generic element tint contract without forcing a white
core absent from the reference. Mask flow and shader displacement may vary
individual spikes but must preserve the carrier's outward mean direction;
neither UV bending nor tip shaping may curl the upper envelope inward. Start
from the selected carrier evidence: retain analytic angular ray sampling,
replace the present broad opaque petals with more numerous lower-alpha soft
columns, deepen the blue/cyan palette, and preserve contrast on light terrain.
Treat palette MAE 26.55, the washed light-terrain capture, and the visibly empty
space between petals as measured failures. Do not restore the low-resolution
green-channel ray lookup merely because it remains available in the atlas.
This item owns the stable base palette and blend response; later temporal work
may key their intensity but may not replace them to hide a material defect.

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

**Resolution (2026-08-13):** Implemented; pending end-of-plan validation.

- The three remaining items were re-audited against the selected outward
  carrier and still form the correct dependency chain. This item was narrowed
  to stable material fields and blend response; temporal curves and motion stay
  in the next item, while carrier/path checks and gameplay lifecycle stay in
  consolidated validation. The final path check now distinguishes an outward
  carrier/centre path from legitimate pointed-alpha taper.
- Footprint-only, haze-only, ray-only, and combined captures prove one source
  job per retained draw: the existing footprint is the single dark aperture;
  haze is the low connective body; rays are sparse high-energy tips. No ring,
  card, particle, column, or white-core layer was added.
- Candidate A replaced the petal cage with 24 overlapping haze columns and a
  denser soft-ray field, but its under-energized thresholds worsened width,
  angular distribution, and palette. Candidate B restored source-scale energy
  and improved seven measures. Candidate C targeted the source palette's
  bright tail. Candidate D removed only ray grazing attenuation and is retained:
  Candidate E's further emission increase produced identical measured output.
- Against the preceding carrier report, the retained material improves faint
  width 0.4201 to 0.4091, faint height 0.1191 to 0.1113, dense height 0.2445 to
  0.2234, centroid height 0.2951 to 0.2596, aperture 0.2257 to 0.2178, band
  periodicity 0.1472 to 0.1217, horizontal-edge ratio 0.0366 to 0.0273,
  plateau ratio 0.0740 to 0.0732, angular-profile L1 0.8462 to 0.8241, and
  palette MAE 26.55 to 20.14. Dense-width error is the only regression, from
  0.1395 to 0.1599; its state variation is explicitly passed to the keyed
  scale/energy tuning item rather than distorting the accepted base material.
- The final haze uses analytic low-contrast columns and root fog with only
  subtle measured-atlas variation. The final ray field uses 24 deterministic
  seeds, soft shoulders, low additive alpha, and no raster lookup or
  grazing-angle fade. Both reconstruct angular position from local world-space
  geometry and preserve the monotonic outward carrier.
- Dark/light terrain plates keep the composite readable. Ice, fire, thunder,
  and darkness plates preserve the generic tint contract. A hue-aware warm
  branch fixes fire luminance while the ice capture remains byte-identical.
  All authored masks remain procedural project code; no source pixels or
  proprietary assets were copied or imported.
- No full game or battle was launched. No backlog edit was needed: remaining
  dense-width variation, spin, oscillation, and state timing are the next
  in-scope item, while the known shutdown defect remains already tracked.

### AURA-R5 — Match the eleven-state motion, spin, oscillation, and final grading

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-R4.

**End state:** The reconstructed layers follow the reference's full temporal
shape: onset from zero, first rise, crest/trough/swell changes visible in the
supplied sequence, and terminal recession. The plume rotates around the caster;
outer ghost spikes oscillate vertically with restrained phase offsets while
remaining rooted. Motion changes the distribution of energy, not the carrier's
identity. Keyed scale, blue/cyan balance, opacity, aperture, spike density, and
duration converge to the registered source at comparable character scale
without redefining the stable materials accepted by the preceding item.

**Implementation:** Retune the eleven-state curves in
`SpellCastAuraProfile.gd` and state interpolation in `SpellCastAura.gd`. Drive
spin and vertical tip oscillation from normalized progress and deterministic
seed data. Use the quantitative comparison report to tune in this order:
silhouette and body enclosure, onset/temporal energy, aperture, color, then
secondary texture detail. Do not use a parameter change to conceal carrier or
blend defects discovered in earlier items. Spin must preserve radius, and
oscillation may move tips vertically or add small outward displacement but may
not make the mean upper radius smaller than the band below it at any phase.

**Risk:** Excessive spin reads as a rotating cage; synchronized oscillation
reads as breathing geometry; tuning one hero frame can degrade the other ten.

**Adds to final validation:** Registered eleven-frame contact sheet, temporal
delta curve, multi-seed exact-seek proof, motion-path stability, element sweep,
and an explicit final gap report rather than a subjective pass claim.

**Item gate:** Run the mandatory gate across all eleven frames after each tuning
iteration inside the item. No hero-frame improvement may advance if the mean
sequence distance or any primary state materially worsens. Update the final
validation tolerances to the best achieved evidence before committing.

**Resolution (2026-08-13):** Implemented; pending end-of-plan validation.

- Re-capturing the merged branch established the true pre-motion baseline. It
  also exposed that the previous material screenshots predated the final
  luminance reduction in `a47ccbf`; the committed effect no longer reproduced
  its accepted evidence and was substantially too dark and narrow. The tuning
  loop therefore used the current render rather than a stale screenshot.
- Motion is normalized-seek only: footprint and haze rotate 0.10 turn, rays
  rotate 0.18 turn, and 24 ray tips oscillate through 1.15 cycles at 0.105
  normalized-height amplitude with a 1.731-radian per-tip phase step. Seed
  changes retain only the existing small deterministic offset. No shader reads
  `TIME`, and no transform depends on the camera.
- Six all-eleven iterations were compared. The retained fifth candidate keeps
  the outward carrier, broadens keyed ray width, lowers keyed haze/ray height,
  restores the registered blue/cyan luminance range, separates low-haze grading
  from ray-tip grading, and keeps the original single aperture curve. A sixth
  upper-fade experiment was rejected because its tiny threshold-height gain
  worsened both width measures and centroid without a visible source gain.
- Against the actual merged baseline, the retained pass improves faint-width
  error `0.9405 -> 0.2382`, dense-width `1.1348 -> 0.2304`, aperture
  `0.3542 -> 0.2037`, horizontal-band periodicity `0.2191 -> 0.1627`,
  horizontal-edge ratio `0.0487 -> 0.0321`, angular-profile L1
  `1.2755 -> 1.1797`, and palette MAE `41.91 -> 28.71`. Mean body overdraw
  rises `0.1054 -> 0.1412`, faint energy `48,314 -> 102,363`, and temporal
  delta error improves `0.3738 -> 0.2149`.
- Faint-height error is `0.1082`, dense-height `0.0925`, centroid `0.2932`, and
  plateau ratio `0.1145`; these are the explicit remaining gaps. The old timid
  render reported superficially better height/centroid values because most aura
  pixels failed the faint threshold. Preserving those numbers would preserve
  the commissioned defect. The retained candidate is the best sequence-wide
  compromise after two bounded vertical reductions, not a hero-frame choice.
- Seed-7 black-isolation acceptance ceilings for final validation are: faint
  width `0.245`, dense width `0.238`, faint height `0.112`, dense height `0.096`,
  centroid `0.300`, aperture `0.210`, band periodicity `0.168`, edge ratio
  `0.034`, plateau ratio `0.118`, angular L1 `1.190`, palette MAE `29.0`, and
  temporal delta error `0.220`. Mean body overdraw must remain at least `0.138`
  and faint energy at least `100,000` under that exact contract.
  `replica_convergence.json` stores the per-frame report without source pixels.
  At that point the final gameplay/lifecycle item was the only open item; the
  user-requested fog and duration revision below now precedes it.

### AURA-R6 — Prototype and preview the ghastly fog vocabulary

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-R1 through AURA-R5.

**End state:** One small, reversible prototype demonstrates whether the current
three-layer, world-space carrier can reproduce the source's soft vapor mass
without returning to puddle rings, a camera-facing curtain, or hard petals. A
source/current/prototype preview is shown to the user before integration. The
item pauses at that preview; the user's direction is a **blocking decision**.
Rejected candidates are removed, and only the selected vocabulary and its
evidence advance.

**Implementation:** Work only in owned spell-aura shader/profile variants.
Prototype two bounded variants, each applying the following three treatments,
on five representative source states plus dense onset and terminal-fade samples:

1. replace per-lobe maximums and crisp alpha shoulders with smoothly accumulated
   broad lobes, two-scale low-frequency domain warping, and a soft root-to-tip
   density falloff so neighboring columns merge into one fog mass;
2. give each ghost ray a wide, low-alpha vapor envelope and a much fainter narrow
   energy spine, with irregular dissolved tips instead of geometric point caps;
3. soften the footprint into one irregular mist-edged aperture, retaining the
   dark centre but removing crisp rim/striated-ring emphasis.

Do not add a fourth layer or import an external texture unless both procedural
candidates demonstrably fail for a named source feature. Any asset proposal must
identify provenance, license, runtime cost, and the exact metric/crop it fixes;
Ragnarok pixels remain evidence only and may not be shipped. Treat the user's
earlier softer Road of Nogg plume screenshot as a qualitative vocabulary
reference, not as higher authority than the eleven source states. Produce layer
isolations, enlarged crops, yaw `0/90/180`, light/dark terrain plates, and a
single labelled preview sheet that makes the choice reviewable without opening
the project.

**Risk:** Simple blur can turn the petal cage into soft petals, erase the spell's
casting force, wash over the character, or create alpha-sorting seams. A
procedural noise texture can read as generic smoke instead of the source plume.

**Adds to final validation:** Approved fog vocabulary, component-isolation
reference captures, source-relative edge/gradient and diffuse-to-core measures,
alpha-sorting checks, and the explicit user-approved preview.

**Item gate:** Apply the mandatory comparison gate to each candidate. Present
the best non-regressing candidate beside the source and current render, state
what became closer/unchanged/worse, and wait for user approval before committing
or beginning integration. Replan the next two items from that response.

**Resolution (2026-08-13):** Implemented; pending end-of-plan validation. The
user approved the selected fog vocabulary after reviewing the labelled
source/current/prototype triptych and explicitly asked to proceed with the full
cycle.

- Candidate A broadened and accumulated the existing lobe construction. Its
  gradients softened, but the silhouette remained a countable shallow petal
  bowl, proving that blur/width alone could not fix the material language.
  Candidate A and its code path were removed.
- Candidate B removes lobe-local ceilings. One low-frequency, noise-shaped fog
  ceiling supplies continuous body density; diffuse angular bands sit inside it
  as subdued ghost energy; the aperture uses one misted irregular edge. The
  retained prototype remains debug-selected until the next item makes the
  approved vocabulary authoritative.
- Against the preceding convergence report, Candidate B improves dense-width
  error `0.2304 -> 0.1191`, energy-centroid error `0.2932 -> 0.2839`, horizontal
  periodicity `0.1627 -> 0.1561`, horizontal-edge ratio `0.0321 -> 0.0269`,
  plateau ratio `0.1145 -> 0.1077`, angular-profile L1 `1.1797 -> 0.9431`, and
  palette MAE `28.71 -> 22.18`. It worsens faint width `0.2382 -> 0.2774`, faint
  height `0.1082 -> 0.1191`, dense height `0.0925 -> 0.2226`, and aperture
  `0.2037 -> 0.3417`; those measured shape gaps are not hidden by the user's
  vocabulary approval and become explicit integration targets.
- Footprint-only, haze-only, ray-only, combined, yaw `0/90/180`, black-isolation,
  and gameplay-terrain captures were inspected. They prove camera independence
  and one retained job per layer, but also reveal bright footprint emphasis and
  grazing shell arcs on light terrain. The integration item is therefore
  replanned to correct aperture energy and carrier-edge visibility before final
  combined grading, while retaining the approved fog field itself.
- The selected post-cleanup capture is byte-identical to its measured Candidate
  B frame. Godot 4.4 parses/imports the shaders cleanly with AppData access. No
  external texture, source pixel, additional layer, billboard, or draw call was
  added. The full game and battle flow were not launched, and no backlog change
  was needed.

### AURA-R7 — Integrate the approved fog treatment across every aura component

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-R6 and its blocking user approval.

**End state:** Footprint, plume body, ghost rays, compositing, and element grading
share the approved ghastly/foggy visual language. The caster reads as standing
inside one continuous aura mass; individual analytic lobes are not countable at
normal play scale. Sparse ray energy still supplies upward/outward casting force,
but its soft envelope dominates its core and no component reads as a shard,
puddle, opaque column, or billboard.

**Implementation:** Integrate and review one component at a time in this order:
footprint, haze body, ghost rays, then the combined blend/order. After each
substep, run the mandatory source comparison and retain it only if the relevant
crop and sequence metrics improve without regressing body enclosure or outward
carrier behavior. Remove rejected prototype branches and duplicate parameters.
Keep world-space radial reconstruction, deterministic seed/seek behavior, the
three-draw budget, tint support, and camera independence. Use premultiplied or
energy-conserving alpha shaping where needed to avoid additive chalkiness on
light terrain; do not raise brightness to hide discontinuity. The approved
prototype evidence makes two corrections mandatory: suppress the footprint's
bright cyan-ring emphasis without losing the dark aperture, and extinguish the
profiled shells' grazing arcs on light terrain without narrowing their
source-scale body. Treat the prototype's faint/dense height and aperture errors
as regressions to recover, not as accepted consequences of softness.

**Risk:** Cross-layer fog accumulation can over-occlude the model, clip on the
ground, reveal sorting boundaries, or destroy the source's blue/cyan contrast.
Changing a shared material surface could regress other elements or VFX callers.

**Adds to final validation:** Component-by-component before/after evidence,
combined-layer continuity, caster enclosure/readability, dark/light terrain,
native/retro, yaw/pitch, tint, shared-caller, and draw-budget coverage.

**Item gate:** Build a source/current sheet after every component substep and a
final all-eleven sheet for the combined result. If the isolated component is
closer but the composite is worse, replan blend/order in this item rather than
advancing the disconnected layers. Show the integrated comparison preview to
the user before lifecycle retiming.

### AURA-R8 — Author the longer zero-ground, rise, crest, and vapor fade

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-R7.

**End state:** The aura is invisible at exact time zero, emits from the single
ground aperture, expands upward and outward through a visible emission front,
reaches a modestly taller high-energy crest, breathes/spins while enclosing the
caster, then thins and dissolves like vapor. It lasts materially longer than the
current `1.15` seconds while preserving responsive battle sequencing. Identical
normalized time and seed still produce identical frames.

**Implementation:** Retune the owned duration and phase curves with an initial
target range of `1.8–2.2` seconds, selecting the final duration through preview
evidence rather than treating the range as acceptance. Start all layer opacity,
height, and emission at true zero. Sequence footprint ignition, bottom-to-top
plume reveal, outward expansion, a `1.08–1.15` height crest, restrained spin and
asynchronous tip drift, then staggered ray/haze/aperture recession. Fade by
advecting and dissolving density; do not scale a completed shape back into the
ground or expose a hard alpha cutoff. Remap the eleven supplied states into the
sustained middle portion and capture extra uncaptured lead-in/tail checkpoints.
Retune adapter hold fraction so the longer visual tail can outlive command
resolution without materially increasing the present action-queue hold time.

**Risk:** A longer effect can stall the action queue, overlap following actions,
or feel slow; global scaling can make the plume contract inward; a hard terminal
fade can expose the analytic masks the fog pass was meant to hide.

**Adds to final validation:** Exact-zero proof, dense emergence contact sheet,
world-space upward/outward front tracking, crest height, sustained-source-state
mapping, staggered dissolve tail, real-time duration, action-hold duration,
overlap/cleanup, pause/speed/seek, and deterministic replay coverage.

**Item gate:** Compare and replan after onset, rise/crest, and fade subiterations.
Each checkpoint must include the current source-relative sequence report and a
dense timing strip. A later phase may not repair an earlier regression by hiding
it with opacity. Show the complete lifecycle preview before final validation.

### AURA-R9 — Consolidated gameplay, lifecycle, and regression validation

**Model:** Opus 5 / GPT Sol

**Depends on:** AURA-R1 through AURA-R8.

This is the only item that launches the full manual gameplay/integration flow.
Validate the union of all prior evidence in one pass:

1. Reproduce exact zero, the dense zero-to-rise sequence, the approved crest and
   dissolve tail, and all eleven registered states in the VFX debug scene.
   Confirm the revised tolerances recorded by AURA-R6 through AURA-R8. Inspect
   the partial-onset envelope and verify outward carrier-radius monotonicity and
   non-inward energy-centre paths at every sampled motion phase. Local fog and
   ray alpha may taper as they do in the source.
2. Exercise native and retro modes, light and dark terrain, battle-camera yaw
   and pitch movement, several deterministic seeds, and ice/fire/thunder/
   darkness/neutral tints. Confirm the caster stays inside but readable and the
   approved diffuse-to-core/edge-softness contract survives every presentation.
3. Exercise pause, speed scale, forward/backward seek, skip-to-settle, overlap,
   replay, disposal, and scene exit. Measure real-time visual and action-hold
   duration; confirm identical frames for identical normalized time and seed.
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
- Changing battle-state cast resolution, spell balance, or spell data; only the
  presentation duration and adapter hold fraction needed to keep existing
  command responsiveness are in scope.
