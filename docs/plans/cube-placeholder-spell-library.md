# Cube placeholder spell library

Opened 2026-09-24. This cycle turns the accepted [24-study cube motion sketch](../sketches/2026-09-24-cube-spell-motion-studies.html) into the complete temporary spell-VFX vocabulary. The sketch is the visual source of truth and the implementation goal: every study ships as a selectable profile, representative spells use those profiles in battle, and every currently active spell effect remains cube-only. This is intentionally placeholder work. It does not restore the parked authored effects, create final spell art, or return the project to real 3D geometry.

All work is routed to **Opus 5 / GPT Sol** because the cycle contains architectural judgement at the renderer/catalog boundary, translation from an executable visual reference rather than a mechanical specification, and repeated look-and-feel decisions whose correctness is visual. The brief deliberately fixes outcomes and invariants while leaving implementation choices that require codebase-aware judgement to the executing model.

## Outcome

At closure:

- all 24 studies exist as active `cube_*` profiles in `SpellVfxCatalog`, alongside the existing `elemental_cube_crownburst` and `elemental_cube_spiral` fallbacks;
- the debug harness can render and capture every cube-placeholder profile in one reproducible batch;
- a curated spell roster maps to all 24 new profiles, while unmapped spells still resolve to one of the two existing cube rituals;
- battle playback supplies the source, target, body bounds, and complete hex footprint each choreography needs without presentation mutating simulation state;
- every cube is fake 3D: a sprite/quad drawn from a nearest-filtered cube atlas, never mesh cube geometry, physics debris, dynamic lighting, or a restored non-cube effect;
- pose at time `t` is deterministic for a given seed, survives pause/seek/rate changes, and disposes cleanly under the existing `VfxPlayback` contract;
- the full library passes catalog, lifecycle, determinism, anchor, footprint, population, and render-budget probes, and its canonical phase sheets are accepted against the sketch by a fresh-eyes visual pass.

## Source-of-truth contract

The retained HTML sketch is executable specification, not inspiration. Its `studies[].draw(t)` functions settle each effect's cube population, relative size hierarchy, trajectory, phase order, phase boundaries, staggering, and breakup pattern. Implementers may translate its normalized diagram coordinates into battle coordinates and may assign separate reference/battle durations, but must not smooth away, embellish, combine, or otherwise “improve” the choreography.

The authority order is:

1. The sketch owns visible choreography and normalized timing.
2. `VfxPlayback`, `VfxCastContext`, `HexVfxFootprint`, and the battle presentation boundary own lifecycle and spatial truth.
3. Current elemental palette resolution owns colour; the sketch's blue is only a neutral preview colour.
4. This plan's budgets own runtime structure where the browser sketch has no equivalent.

The neutral `C` and `T` cubes in the sketch are caster/target scale references and are never emitted by an effect. The 0–1 loop is a normalized choreography timeline, not a mandated wall-clock duration. Random-looking offsets produced by the sketch's `rnd()` may be seed-varied in game, but the same seed and normalized time must reproduce the exact same pose. Effects that use an area must consume the complete affected-cell footprint, including empty cells; effects that are merely target-bound must not claim surrounding cells.

## Profile roster and production carriers

The identifiers, populations, beat names, and initial spell carriers below are fixed for this cycle. “Population” describes the authored peak ingredients from the sketch, not the two neutral reference actors.

| # | Profile ID | Study / population | Normalized beats | Spatial contract | Initial carrier |
| --- | --- | --- | --- | --- | --- |
| 01 | `cube_arcing_pair` | Arcing pair; 2 medium, then impact chips | Gather / angled arcs / break | source → target | Ember Strike |
| 02 | `cube_scattershot` | Scattershot; 11 small, local chips | Pack / fan out / pepper | source → target cluster | Corrupting Splatter |
| 03 | `cube_corkscrew_bolt` | Corkscrew bolt; 1 medium + 7 tiny, burst | Wind up / bore forward / burst | source → target | Lightningbolt |
| 04 | `cube_returning_throw` | Returning throw; 1 large, impact chips | Throw wide / clip target / return | source → target → source | Steel Blade |
| 05 | `cube_skipping_stone` | Skipping stone; 1 medium, three contacts | Launch / hop → hop / last impact | source → target cluster | Splash |
| 06 | `cube_flanking_volley` | Flanking volley; 4 medium, burst | Separate / curve around / converge | source → target | Dark Bolt |
| 07 | `cube_ceiling_collapse` | Ceiling collapse; 12 dust + 7 heavy + rubble | Dust warning / heavy fall / rubble | complete target area | Ice Plume |
| 08 | `cube_ground_teeth` | Ground teeth; 5 four-cube stacks + debris | Tremble / punch upward / crumble | target or area footprint | Earth Spike |
| 09 | `cube_expanding_shockwave` | Expanding shockwave; 1 core → 24 small | Compress / expanding ring / scatter | complete target area | Dark Nova |
| 10 | `cube_implosion` | Implosion; 18 small → 1 dense core | Hang / snap inward / collapse | target-centred volume | Magenta Reduction |
| 11 | `cube_rolling_avalanche` | Rolling avalanche; 2 large + 10 small + debris | Rumble / roll through / break apart | source → target lane | Ice Plow |
| 12 | `cube_staggered_bombardment` | Staggered bombardment; 9 mixed + debris | First drops / uneven impacts / last heavy hit | complete target area | Solar Storm |
| 13 | `cube_rising_barricade` | Rising barricade; 15 medium | Seed line / build upward / withdraw | line between source and target | Barricade |
| 14 | `cube_closing_cage` | Closing cage; 16 medium | Corner posts / close overhead / hold | target body bounds | Bramble Crown; Aurora Veil |
| 15 | `cube_climbing_coil` | Climbing coil; 22 tiny | Find feet / climb / tighten | target body bounds | Thornlash |
| 16 | `cube_lifting_vortex` | Lifting vortex; 28 small | Sweep inward / spiral upward / release | target-centred volume | Smoke Tower |
| 17 | `cube_clapping_slabs` | Clapping slabs; two walls of 6 + fragments | Build sides / slam together / chip away | target body bounds | Closing of the Third Sanctuary |
| 18 | `cube_encasing_frost` | Encasing frost; 18 small/medium + release chips | Seed crystals / build shell / lock | target body bounds | Ice Statue |
| 19 | `cube_repair_mend` | Repair / mend; 12 tiny → 4 medium | Gather fragments / rise inward / reassemble | target or self | Mending |
| 20 | `cube_intercepting_guard` | Intercepting guard; 6 medium + incoming | Orbit / intercept / recover | protected target + source-side threat | Ooze Shield |
| 21 | `cube_siphon` | Siphon; 9 small → 1 medium | Loosen / pull to caster / absorb | target → source | Insatiable Famine |
| 22 | `cube_cleanse` | Cleanse; 10 attached → outward chips | Cling / lift off / cast away | target body bounds | Opening of the Third Sanctuary |
| 23 | `cube_blink_transfer` | Blink transfer; 8 medium | Disassemble / cross in a streak / reform | source → target | Feather Time |
| 24 | `cube_charge_release` | Charge and release; 16 tiny → 1 large → chips | Gather power / hold weight / fire | source → target | Pyre Blast |

The carrier mapping is a presentation assignment only. It does not alter damage, targeting, statuses, timing, or any other gameplay rule. `Ice Statue`, `Ice Plow`, `Smoke Tower`, `Magenta Reduction`, `Aurora Veil`, and `Solar Storm` deliberately replace their parked explicit non-cube tags with the cube profiles above. Spells outside this table retain the current offensive/non-offensive Crownburst/Spiral fallback.

## CPFX-1 — Batch capture contract

**Model:** Opus 5 / GPT Sol

**Model rationale:** this changes the proof surface used by every later item. The difficult part is choosing a batch boundary that remains generic, exits reliably, and composes with the existing capture/golden CLI rather than bolting cube-specific behaviour into the scene.

**Depends on:** none
**Touches:**

- `src/presentation/debug/VFXDebugController.gd`
- `src/presentation/debug/VfxDebugArguments.gd`
- `src/presentation/debug/VfxDebugCapture.gd`
- `scripts/hex_battle/cube_vfx/probe_batch_capture_args.gd`
- `scripts/hex_battle/cube_vfx/probe_batch_capture_args.gd.uid`
- `scripts/checks/probes/cube_vfx_batch_capture.json`
- `docs/VFX_DESIGN.md`

**End state:** a CLI selector such as `--effect-prefix=cube_`, combined with the existing seed/mode/camera/capture flags, renders every matching catalog profile into one predictably named phase sheet and writes a machine-readable manifest containing profile ID, command inputs, output path, and process result. No-match is a clear successful result with an empty manifest; an unknown exact `--effect` remains an error. Existing one-effect commands are byte-for-byte equivalent in semantics and exit behaviour.

**Implementation brief:** decide whether one Godot process can safely rebuild the scene across profiles or whether a small orchestrating layer is required. Preserve the existing capture component's responsibility for individual frames, golden comparison, and process exit codes. The batch abstraction must be generic catalog filtering; it must not know the 24 IDs or their choreography. Make interrupted/partial output distinguishable from a complete batch. Record the boundary choice and its failure semantics in the commit body.

**Risk:** a batch mode can accidentally retain an old playback, carry tunables into the next profile, or report success before asynchronous image writes complete. A second risk is creating a parallel capture path that silently diverges from the accepted single-effect harness.

**Validation — self-contained:** import scripts, run the focused registered probe, then exercise the new selector before any `cube_*` profiles exist and confirm a complete empty manifest. Also run one existing `elemental_cube_` batch at two capture times to prove deterministic naming, reset isolation, and normal process exit. Command families:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter cube_vfx_batch_capture
./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --import --quit --rendering-method gl_compatibility --audio-driver Dummy
./Godot_v4.4-stable_win64.exe --path . scenes/debug/VFXDebugScene.tscn --effect-prefix=elemental_cube_ --seed=7 --hide-hud --capture-at=0.30,0.70 --capture-sheet --render-resolution=640x480
```

**Validation — deferred:** none; the batch contract is exercised again by CPFX-9 with all profiles present.

## CPFX-2 — Isolated fake-3D cube substrate

**Model:** Opus 5 / GPT Sol

**Model rationale:** this is the architectural hinge: it must reconcile the sketch's arbitrary cube poses with Godot's deterministic playback, cast anchoring, and strict draw-call budget without turning the existing cube ritual into a shared dependency.

**Depends on:** none
**Touches:**

- `src/presentation/effects/cube_placeholders/shared/**`
- `scripts/hex_battle/cube_vfx/shared/**`
- `scripts/checks/probes/cube_vfx_shared.json`
- `docs/effects/cube-placeholder-foundation.md`

**End state:** a new, isolated cube-placeholder substrate can render at least 48 simultaneously visible fake-3D cubes with per-cube position, scale, yaw/frame, opacity, and palette role. It preallocates its maximum population, performs no node/resource allocation during timeline sampling, uses no more than four render nodes and four estimated draw calls at peak, and exposes deterministic normalized-pose sampling through a `VfxPlayback`-compatible owner. It understands source, target, target-body bounds, target-centred local space, and an optional complete `HexVfxFootprint`. If exact source-study sampling demonstrates a peak above 48, capacity rises to the measured peak; visible cubes are never dropped to protect the budget.

**Implementation brief:** choose the batching representation and the boundary between choreography data and rendering. A `MultiMesh`-style solution is the likely fit, but the choice belongs to the implementer because transparency, atlas frame selection, and ordering may change the correct answer. Copy the proven 12-frame fake-cube atlas construction and elemental palette relationships into this new owned area; do not extract, parameterize, or edit `ElementalCubeRitualEffect.gd`, `ElementalCubeRitualProfile.gd`, their materials, or their callers. Preserve nearest filtering, unshaded presentation, and the illusion of quarter-turn yaw. Decide how opacity groups and palette roles fit the draw-call limit, and explain the tradeoff in the commit body.

**Risk:** per-instance opacity/atlas choice can defeat batching; alpha ordering can make the fake depth unreadable; an attractive shared abstraction can create a forbidden regression surface for the two surviving rituals. Target/body scaling may also distort the sketch if world conversion is not uniform.

**Validation — self-contained:** the focused probe samples at least 101 normalized times in ascending, descending, and shuffled order for two seeds. It asserts finite transforms, identical repeated poses, no live-count growth, no post-construction resource/node allocation, peak capacity, ≤4 render nodes/draw calls, pause, zero rate, 4× rate, `skip_to_settle()`, and idempotent disposal. It also asserts that the existing ritual scripts/resources remain untouched by the commit. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter cube_vfx_shared
./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --import --quit --rendering-method gl_compatibility --audio-driver Dummy
```

**Validation — deferred:** none; appearance is judged through the family effects and final validation.

## CPFX-3 — Travel and delivery family

**Model:** Opus 5 / GPT Sol

**Model rationale:** six related but perceptually distinct source→target motions must be translated from executable diagrams into one coherent game-space family without erasing their characteristic trajectories. This is visual judgement within a fixed contract.

**Depends on:** CPFX-2
**Touches:**

- `src/presentation/effects/cube_placeholders/travel/**`
- `scripts/hex_battle/cube_vfx/travel/**`
- `scripts/checks/probes/cube_vfx_travel.json`
- `docs/effects/cube-placeholder-travel.md`

**End state:** profiles 01–06 exist as independently constructible playbacks whose normalized poses preserve the sketch's exact populations, relative sizes, lateral offsets, stagger order, contact count, arc character, convergence, and return path. Every path derives from live source/target anchors and remains legible at source distances 4, 6, and 10 without changing normalized phase boundaries.

**Implementation brief:** establish a shared coordinate conversion for the family, then translate each sketch function rather than designing anew. Preserve the important contrast: two weighted lobs, a widening pepper cone, a drilled helix, one broad returning sweep, three readable skips, and four simultaneous flanks. Duration may differ per profile and per playback mode, but changing duration cannot redistribute normalized beats. The first implemented profile is `cube_arcing_pair`; stop after its skeleton/phase sheet, show that proof, and correct the coordinate conversion before multiplying it across the family.

**Risk:** perspective and long source distances can flatten vertical arcs or hide z-offsets; global easing helpers can make six effects feel interchangeable; debris can outlive disposal or inflate capacity.

**Validation — self-contained:** a focused probe checks exact active-cube counts and semantic checkpoints at the sketch's phase/contact boundaries, source/target endpoint tolerance, three skips for `cube_skipping_stone`, target contact before return for `cube_returning_throw`, simultaneous convergence for `cube_flanking_volley`, deterministic seed/seek, and substrate budgets at distances 4/6/10.

**Validation — deferred:** capture and show `cube_arcing_pair` at `t=0.12,0.30,0.50,0.70,0.90` immediately after the family coordinate conversion exists. Before commit, produce the same five-frame sheet for all six profiles. CPFX-9 makes the final sketch comparison.

## CPFX-4 — Impact and area family

**Model:** Opus 5 / GPT Sol

**Model rationale:** these six studies carry the largest populations and the strongest implied mass. Translating them requires judgement about footprint projection, warning readability, overlap, and performance while the visible choreography remains fixed.

**Depends on:** CPFX-2
**Touches:**

- `src/presentation/effects/cube_placeholders/impact/**`
- `scripts/hex_battle/cube_vfx/impact/**`
- `scripts/checks/probes/cube_vfx_impact.json`
- `docs/effects/cube-placeholder-impact.md`

**End state:** profiles 07–12 preserve the sketch's dust-before-weight ceiling collapse, sequential teeth, core-to-ring shockwave, accelerating implosion, two-heavy avalanche, and uneven bombardment ending in its largest hit. Area-bound profiles fit the complete supplied hex footprint rather than a Euclidean guess and remain truthful when affected cells are empty.

**Implementation brief:** decide how diagram-area positions map onto arbitrary footprint topology while keeping the source study recognizable. The warning/impact distinction is non-negotiable: the ceiling's 12 dust cubes precede seven heavy cubes; bombardment culminates in the ninth heavy strike; the shockwave reads as one compressed core becoming a 24-cube ground ring. Preserve Manhattan/cross/line footprint truth where applicable, but do not invent extra cubes or change counts to fill awkward shapes. For source→target avalanche, treat the footprint as collision truth rather than a reason to bend its lane beyond recognition.

**Risk:** the sketch's planar area is not itself a hex-footprint algorithm; naïve radial placement can advertise cells gameplay does not hit. Overlapping debris may exceed capacity, and large alpha-sorted cubes can obscure warnings.

**Validation — self-contained:** the focused probe checks counts and ordering at every named beat, final-heavy-hit ordering, implosion radial monotonicity after snap, shockwave outward monotonicity, and placement inside representative single, diamond, cross, and line footprints including empty outer cells. It samples each profile across seed/seek/rate/disposal and asserts the shared render budget.

**Validation — deferred:** capture `cube_ceiling_collapse` first at all five canonical times before completing its siblings. Before commit, produce the family sheet for all six and a yaw 0/90 comparison for ceiling collapse and shockwave. CPFX-9 makes the final sketch comparison.

## Midpoint convergence review

After CPFX-1 through CPFX-4 are committed, stop before wave 3. Compare the retained sketch, both implemented families, probe evidence, render budgets, and the untouched existing rituals against the cycle outcome. Confirm that the shared substrate is serving the choreography rather than forcing visible compromises, that batch capture has not become cube-specific, and that the source-truth rules are being applied consistently. Correct drift only inside the remaining items' owned paths; if recovery requires changing CPFX-1/2 ownership or changing the promised visual outcome, stop and coordinate a revised plan with the user.

## CPFX-5 — Shape and control family

**Model:** Opus 5 / GPT Sol

**Model rationale:** the six effects must communicate persistent spatial states—wall, cage, snare, lift, crush, encasement—using identical raw material. Their success depends on silhouette and target-body adaptation, not mechanical transcription alone.

**Depends on:** CPFX-2 and the midpoint convergence review
**Touches:**

- `src/presentation/effects/cube_placeholders/control/**`
- `scripts/hex_battle/cube_vfx/control/**`
- `scripts/checks/probes/cube_vfx_control.json`
- `docs/effects/cube-placeholder-control.md`

**End state:** profiles 13–18 preserve the study populations, construction order, hold silhouettes, and exits. Body-bound cages/coils/shells adapt uniformly to standard, wide, and tall target bounds; the barricade occupies the source–target line without pretending to create gameplay obstruction; the vortex releases rather than simply fading; clapping slabs visibly contact before fragmenting.

**Implementation brief:** translate the sketch's body-sized coordinate system through one coherent bounds policy. Protect the silhouette of each effect: a three-layer 5×3 barricade, four four-cube cage posts closing overhead, a 22-cube tightening helix, a 28-cube skirt-to-column vortex, two six-cube slabs, and three rings of six frost cubes. Adaptation may scale/offset the complete composition; it may not alter counts or phase order to fit a body preset.

**Risk:** per-axis target scaling can turn cubes into non-cubes or make wide/tall bodies produce different choreography; dense shells may occlude the target completely; persistent holds may expose popping at seek boundaries.

**Validation — self-contained:** the focused probe checks exact structures and closure/contact events, uniform cube scale under all body presets, no claimed area for body-only profiles, barricade placement between live anchors, deterministic random access across hold boundaries, and all shared budgets.

**Validation — deferred:** capture `cube_closing_cage` at five canonical times for standard/wide/tall targets before finishing the family. Produce all-six family sheets before commit; CPFX-9 performs final comparison and yaw sweeps.

## CPFX-6 — Restore and transform family

**Model:** Opus 5 / GPT Sol

**Model rationale:** these effects carry semantic direction—repair, intercept, drain, cleanse, transfer, charge—that must read without bespoke iconography. Preserving that meaning with cubes requires motion-design judgement and careful two-anchor ownership.

**Depends on:** CPFX-2 and the midpoint convergence review
**Touches:**

- `src/presentation/effects/cube_placeholders/restore/**`
- `scripts/hex_battle/cube_vfx/restore/**`
- `scripts/checks/probes/cube_vfx_restore.json`
- `docs/effects/cube-placeholder-restore.md`

**End state:** profiles 19–24 preserve the sketch's directional semantics and exact population changes: fragments become four stable repair blocks; guards intercept and recover; siphon travels target→source; cleanse detaches outward; blink disassembles/transfers/reforms; charge visibly gathers, holds weight, fires, and breaks.

**Implementation brief:** make direction readable from motion alone and keep source/target roles explicit in profile data. Preserve the guard's incoming seventh cube as hostile motion distinct from its six orbiters. Preserve the charge's held large cube rather than collapsing gather and fire into one continuous travel. Self-target casts need a stable, non-zero basis when source and target coincide; decide that fallback from cast context without mutating gameplay positions.

**Risk:** coincident self-target anchors can produce undefined direction, target/source swaps can reverse spell meaning, and reassembly transitions can pop when time is sampled rather than played continuously.

**Validation — self-contained:** the focused probe checks directional derivatives, population handoffs, guard collision/recovery, stable coincident-anchor behaviour, charge hold interval, deterministic random access at every handoff, and shared budgets.

**Validation — deferred:** capture `cube_charge_release` first at five canonical times and verify the hold by eye before completing siblings. Produce all-six family sheets before commit; CPFX-9 performs final comparison.

## CPFX-7 — Catalog, spell roster, and battle integration

**Model:** Opus 5 / GPT Sol

**Model rationale:** this item owns the compatibility boundary among data, generic catalog factories, body/source/area binding, and the hex adapter. It must activate the library without resurrecting parked implementations or spreading per-profile branches through gameplay.

**Depends on:** CPFX-3, CPFX-4, CPFX-5, CPFX-6
**Touches:**

- `src/presentation/effects/SpellVfxCatalog.gd`
- `src/presentation/battle/effects/HexBattleVfxBridge.gd`
- `src/presentation/debug/VFXDebugController.gd`
- `data/spells.json`
- `docs/SPELL_CATALOG_SCHEMA.md`
- `docs/VFX_DESIGN.md`
- `docs/effects/README.md`
- `docs/MODULE_MAP.md`
- `scripts/hex_battle/probe_vfx_contract.gd`

**End state:** `SpellVfxCatalog.entries()` contains exactly 26 active profiles: the two unchanged elemental rituals and the 24 `cube_*` profiles. Every `cube_*` entry declares enough generic spatial metadata for the catalog/debug/battle path to supply its anchors, target bounds, and footprint without profile-name conditionals. The carrier table in this plan is reflected exactly in `data/spells.json`; all other spells retain fallback resolution. The debug picker can instantiate all 26. No active factory, explicit spell tag, or bridge branch selects a parked non-cube effect.

**Implementation brief:** decide the smallest generic catalog contract for spatial binding and factory construction. Reconcile it with `HexBattleVfxBridge.createPlayback()` so area footprints remain hex-native and include empty cells, but do not restore the retired `AREA_FACTORIES` behaviour for parked profiles or move presentation decisions into simulation. Prefer data-driven binding metadata over a 24-case match. Preserve the public semantics used by existing callers (`resolve`, `resolvedProfileId`, `actionHoldFraction`, `maxLive`, and `create`) or deliberately migrate every caller in this item's paths. Record why the chosen boundary will support more placeholder profiles without another bridge rewrite.

**Risk:** catalog metadata can become a shadow gameplay-targeting system; spell-data edits can accidentally change rules beyond `VFX_PROFILE`; a generic factory signature can break the existing rituals; area effects can regress to occupied-target cells only.

**Validation — self-contained:** extend `probe_vfx_contract.gd` to assert the exact 26-ID active set, exact carrier table, no active parked profile, unchanged fallback classification, constructibility of every entry, generic binding completeness, full footprint propagation including empty cells, and absence of profile-ID branching in battle gameplay paths. Parse `data/spells.json` and run import plus focused probes.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter vfx_contract
./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --import --quit --rendering-method gl_compatibility --audio-driver Dummy
```

**Validation — deferred:** CPFX-9 casts representative mapped and fallback spells through the real battle presentation path.

## CPFX-8 — Whole-library contract gate

**Model:** Opus 5 / GPT Sol

**Model rationale:** this is a cross-family verification design problem. The gate must catch visual-contract drift through inspectable pose signatures and spatial invariants without encoding implementation details so tightly that harmless refactoring breaks it.

**Depends on:** CPFX-7
**Touches:**

- `scripts/hex_battle/cube_vfx/probe_cube_placeholder_library.gd`
- `scripts/hex_battle/cube_vfx/probe_cube_placeholder_library.gd.uid`
- `scripts/hex_battle/fixtures/vfx/cube_placeholder_manifest.json`
- `scripts/checks/probes/cube_vfx_library.json`
- `scripts/hex_battle/probe_entrypoints.gd`

**End state:** one reviewable manifest names every profile's family, initial carrier(s), binding mode, exact authored ingredient counts, maximum simultaneous population, named beat boundaries, and pose-signature checkpoints. One registered probe constructs all 26 active profiles and verifies that the 24 new effects conform to that manifest while both existing rituals remain unchanged and constructible.

**Implementation brief:** choose pose signatures that defend the sketch—counts by role, centroid/radius/height ranges, endpoint/contact events, monotonic movement, phase handoffs—without snapshotting raw renderer internals. Sample enough times around discontinuities to catch one-frame holes and seek-only pops. Treat the manifest as the machine-readable mirror of this plan's roster, not as a second design document. Register any additional entrypoint only if required by the repository's probe loader.

**Risk:** weak signatures can pass visibly wrong motion; over-specific float snapshots can fail cross-platform for no perceptual reason. A whole-library probe can also hide the profile that failed unless diagnostics remain profile/time specific.

**Validation — self-contained:** run the focused library probe, the full probe sweep, import, and non-interactive project/debug-scene loads. The probe must sample forward/reverse/shuffled times, multiple seeds, source distances, body presets, and footprint shapes; assert exact catalog/mapping/manifest agreement, finite poses, lifecycle/rate/skip/dispose, no active non-cube factories, population caps, and ≤4 render nodes/draw calls per new effect. Record unrelated in-flight changes that can affect the broad sweep rather than repairing paths outside this item.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter cube_vfx_library
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1
./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --import --quit --rendering-method gl_compatibility --audio-driver Dummy
./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --quit-after 5 --rendering-method gl_compatibility --audio-driver Dummy
./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . scenes/debug/VFXDebugScene.tscn --quit-after 5 --rendering-method gl_compatibility --audio-driver Dummy
```

**Validation — deferred:** none beyond CPFX-9's visual/gameplay acceptance.

## CPFX-9 — Standalone visual and gameplay validation; cycle close

**Model:** Opus 5 / GPT Sol

**Model rationale:** acceptance is an independent judgement about motion fidelity, readability, and semantic fit across work from four implementation families. The implementing sessions cannot fairly validate their own look, and the checks span several subsystems, so this is a standalone fresh-eyes item.

**Depends on:** CPFX-8
**Touches:**

- `src/presentation/effects/cube_placeholders/**`
- `src/presentation/effects/SpellVfxCatalog.gd`
- `src/presentation/battle/effects/HexBattleVfxBridge.gd`
- `src/presentation/debug/VFXDebugController.gd`
- `src/presentation/debug/VfxDebugArguments.gd`
- `src/presentation/debug/VfxDebugCapture.gd`
- `data/spells.json`
- `scripts/hex_battle/cube_vfx/**`
- `scripts/hex_battle/fixtures/vfx/cube_placeholder_manifest.json`
- `scripts/checks/probes/cube_vfx_*.json`
- `scripts/hex_battle/probe_vfx_contract.gd`
- `scripts/hex_battle/probe_entrypoints.gd`
- `docs/VFX_DESIGN.md`
- `docs/SPELL_CATALOG_SCHEMA.md`
- `docs/MODULE_MAP.md`
- `docs/effects/**`
- `BACKLOG.md`
- `docs/plans/cube-placeholder-spell-library.md`

The retained sketch `docs/sketches/2026-09-24-cube-spell-motion-studies.html` is read-only in this item. Validation defects may be fixed only in the paths above. Existing elemental ritual implementation/resources and all parked VFX remain outside the write set.

**End state:** every study is visually accepted against the sketch at canonical times, representative effects survive yaw/body/distance/footprint variation, mapped and fallback spells work through battle presentation, all automated checks pass, any genuinely open out-of-scope work is recorded once in `BACKLOG.md`, and this cycle file is deleted in the validation commit. The retained sketch remains the durable record of the visual decision.

**Implementation brief:** validate at the exact committed revision and record unrelated in-flight paths that may affect observation. Use the batch harness to generate 24 canonical reference-mode sheets with seed 7, ice palette, source distance 6, standard target, HUD hidden, retro 640×480, and normalized times `0.12,0.30,0.50,0.70,0.90`. Compare every sheet side-by-side with the HTML at those same scrub positions. Judge counts, size hierarchy, trajectory, beat ordering, silhouettes, warning-before-impact, and directional meaning; do not judge pixel identity between Canvas and Godot. Fix deviations in owned paths, regenerate the affected family, and rerun its probe before proceeding.

Then perform:

- yaw 0/90/180 sheets for `cube_arcing_pair`, `cube_ceiling_collapse`, `cube_expanding_shockwave`, `cube_rising_barricade`, `cube_closing_cage`, `cube_lifting_vortex`, `cube_blink_transfer`, and `cube_charge_release`;
- standard/wide/tall body checks for cage, coil, encasing frost, guard, and cleanse;
- radius/shape checks that include empty cells for ceiling collapse, ground teeth, shockwave, and bombardment;
- live battle casts for one source→target attack, one target-bound control, one complete-area effect, one self/support effect, one Crownburst fallback, and one Spiral fallback;
- pause, forward/backward seek, zero rate, 4× rate, `skip_to_settle()`, live-cap pressure, interruption, and disposal checks;
- unchanged debug captures of both existing elemental cube rituals at the same seed/mode used before this cycle;
- the complete CPFX-8 command set after the last correction.

No permanent phase sheets or goldens are committed: they are proof output under `debug/`, and commands plus results belong in the validation commit body. If a mismatch is a deliberate change to this plan's locked visual target rather than an implementation defect, stop and ask the user; do not rewrite the retained sketch during validation.

**Risk:** a large visual pass can become superficial; validating only one camera hides flattened arcs and overlapping silhouettes; broad correction authority can tempt cleanup of parked/shared effects. Keep an explicit 24-row checklist and report each profile pass/fail with any correction.

**Validation — self-contained:** full probe sweep, import, project load, debug-scene load, focused diff/check of every owned path, and exact verification that the cycle file is the only plan path deleted.

**Validation — deferred:** all visual/gameplay checks above are this item's work and must pass before it commits. A failure keeps the cycle open.

## Waves

| Wave | Items | Why disjoint / validation form |
| --- | --- | --- |
| 1 | CPFX-1, CPFX-2 | Debug capture contract versus isolated renderer/substrate; no shared paths. |
| 2 | CPFX-3, CPFX-4 | Travel and impact family directories/probes/docs are disjoint; both depend only on committed CPFX-2. End the wave with the mandatory midpoint convergence review after implementation item 4. |
| 3 | CPFX-5, CPFX-6 | Control and restore family directories/probes/docs are disjoint and begin only after the review. |
| 4 | CPFX-7 | Single integration owner for catalog, bridge, spell data, central docs, and existing VFX contract probe. |
| 5 | CPFX-8 | Single whole-library gate owner after integration is committed. |
| 6 | CPFX-9 | **Validation: standalone.** Fresh-eyes visual judgement spans four families and battle/debug integration, so folding is not legal. This item also closes the cycle. |

Each executing session checks that its actual model is Opus 5 / GPT Sol before editing and reports a mismatch without stopping. One commit is required per item, with its self-contained evidence and design findings in the body and `Plan-Item: CPFX-N` as the last trailer. CPFX-3 through CPFX-7 are **implemented; pending validation** until CPFX-9 commits. CPFX-1, CPFX-2, and CPFX-8 are verified by their own self-contained checks.

## Deliberately excluded

- Real 3D cube meshes, physics, volumetrics, dynamic lighting, and camera changes.
- Restoration, retuning, deletion, or refactoring of parked non-cube effects.
- Refactoring or visual changes to the existing Crownburst and Spiral ritual implementations.
- Final bespoke spell art, lore-specific motifs, sound design, screenshake, damage numbers, or gameplay feedback beyond cube motion.
- Changes to spell mechanics, targets, balance, action timing, AI, or simulation state.
- New mappings beyond the explicit carrier table; unmapped spells use the current two-profile fallback.
- Permanent capture sheets or goldens without a repository runner that can compare them.
- General-purpose particle/VFX framework extraction. This library may have an internal substrate, but it is not authority to migrate unrelated callers.
