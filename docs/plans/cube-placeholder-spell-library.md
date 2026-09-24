# Cube placeholder spell library

Opened 2026-09-24. This cycle turns the accepted [24-study cube motion sketch](../sketches/2026-09-24-cube-spell-motion-studies.html) into the complete temporary spell-VFX vocabulary. The sketch is the visual source of truth and the implementation goal: every study ships as a selectable profile, representative spells use those profiles in battle, and every currently active spell effect remains cube-only. This is intentionally placeholder work. It does not restore the parked authored effects, create final spell art, or return the project to real 3D geometry. Revised the same day, before execution, after a review against the code: each spell now carries a presentation-only VFX spec that decides how its effect spreads, anchors, colours itself, and scales with area radius and cast range; the debug scene gains hex footprints, per-family catalog loading, and a by-spell preview; and the four first-profile proofs are blocking user checkpoints.

All work is routed to **Opus 5 / GPT Sol** because the cycle contains architectural judgement at the renderer/catalog boundary, translation from an executable visual reference rather than a mechanical specification, and repeated look-and-feel decisions whose correctness is visual. The brief deliberately fixes outcomes and invariants while leaving implementation choices that require codebase-aware judgement to the executing model.

## Outcome

At closure:

- all 24 studies exist as active `cube_*` profiles in `SpellVfxCatalog`, alongside the existing `elemental_cube_crownburst` and `elemental_cube_spiral` fallbacks;
- every spell can carry a presentation-only VFX spec (see "Per-spell VFX spec") that decides profile, spread, anchor, area scaling, range scaling, and elements; every aspect has a default, and adding a new aspect later is one vocabulary row plus the effects that read it, not a bridge or adapter rewrite;
- the debug harness can render and capture every cube-placeholder profile in one reproducible batch, on a real hex footprint, and can preview a real spell by name with that spell's spec, radius, shape, and range;
- a curated spell roster maps to all 24 new profiles with the settings in this plan's carrier table, while spells without a spec still resolve to one of the two existing cube rituals;
- battle playback supplies the source, target, body bounds, complete hex footprint, spec, and derived caster front each choreography needs without presentation mutating simulation state;
- every cube is fake 3D: a sprite/quad drawn from a nearest-filtered cube atlas, never mesh cube geometry, physics debris, dynamic lighting, or a restored non-cube effect;
- pose at time `t` is deterministic for a given seed and spec, survives pause/seek/rate changes, and disposes cleanly under the existing `VfxPlayback` contract;
- the full library passes catalog, spec, lifecycle, determinism, anchor, footprint, population, and render-budget probes, and its canonical phase sheets are accepted against the sketch by a fresh-eyes visual pass.

## Present-state facts an executing agent must not "fix"

- An unknown `--effect=` in the VFX debug scene warns and falls back to the first catalog entry (`VFXDebugController._resolveInitialEffectIndex`). That behaviour stays for single-effect runs. Only the new batch selector treats a bad request as an error.
- The debug scene currently builds square-radius footprints and calls `setFootprint(radius, 0, shape)`; the battle calls `setHexFootprint(footprint, groundSpan, areaShape)`. The two elemental rituals keep receiving exactly what they receive today. The new cube profiles implement only the hex path: do not add a square `setFootprint` to them.
- `HexBattleVfxBridge.createPlayback` already forwards the complete affected-cell footprint to any playback that has `setHexFootprint`, and both battle callers (`HexBattleVisualAdapter.playSpell` and `HexBattleCombatFeedback._startCast`) already pass the full affected cells and a `VfxCastContext`. Extend this seam; do not build a second one.
- `scripts/hex_battle/probe_vfx_contract.gd` is quarantined (`"gate": false`) because Godot crashes on exit while releasing `VfxTextures`' static texture cache. Its assertions still run. An item that relies on it reads the `HXB_VFX_OK` marker and the probe's own failures, not the sweep's exit code. Do not un-quarantine it.
- `SpellReferences` passes keys it does not know through unchanged, so a nested `VFX` object on a spell reaches presentation without touching `src/factories/`. Gameplay code never reads it.
- Hex battle units have no facing. "In front of the caster" is derived in presentation (see the spec's `ANCHOR`), never added to simulation.
- `run_probe_sweep.ps1 -Filter` matches the registered probe's **script path**, not its manifest file name. Every command in this plan filters on a script-path fragment.
- `SpellReferences` defaults `RADIUS` to 1, so every spell without an explicit radius reports radius 1 and a one-cell footprint.

## Source-of-truth contract

The retained HTML sketch is executable specification, not inspiration. Its `studies[].draw(t)` functions settle each effect's cube population, relative size hierarchy, trajectory, phase order, phase boundaries, staggering, and breakup pattern. Implementers may translate its normalized diagram coordinates into battle coordinates and may assign separate reference/battle durations, but must not smooth away, embellish, combine, or otherwise "improve" the choreography.

The authority order is:

1. The sketch owns visible choreography and normalized timing **at the reference configuration**: source distance 4 cells, one-cell target area, standard target body.
2. The per-spell VFX spec owns how that choreography adapts away from the reference: spread, anchor, area scaling, range scaling, elements.
3. `VfxPlayback`, `VfxCastContext`, `HexVfxFootprint`, and the battle presentation boundary own lifecycle and spatial truth.
4. Elemental palette resolution owns colour; the sketch's blue is only a neutral preview colour.
5. This plan's budgets own runtime structure where the browser sketch has no equivalent.

The neutral `C` and `T` cubes in the sketch are caster/target scale references and are never emitted by an effect. The 0–1 loop is a normalized choreography timeline, not a mandated wall-clock duration. At the reference configuration the normalized beat boundaries match the sketch exactly; range scaling may lengthen travel beats in absolute time away from it (see `RANGE_SCALING`), which is the only permitted change to the beat layout. Random-looking offsets produced by the sketch's `rnd()` may be seed-varied in game, but the same seed, spec, and normalized time must reproduce the exact same pose. Effects that use an area must consume the complete affected-cell footprint, including empty cells; effects that are merely target-bound must not claim surrounding cells.

## Per-spell VFX spec

Each spell may carry one nested, presentation-only object under the key `VFX` in `data/spells.json`. It replaces the flat `VFX_PROFILE` string for every spell this cycle touches. Legacy `VFX_PROFILE` values stay readable so untouched spells keep their fallback behaviour. The vocabulary below is fixed for this cycle. Its parser, defaults, and validation live in one presentation file so that a later aspect (for example cast-height or caster-size scaling) is a new row there plus the effects that read it.

| Key | Values | Default | Meaning |
| --- | --- | --- | --- |
| `PROFILE` | any active catalog profile ID | Crownburst/Spiral fallback by the current offensive rule | Which choreography plays. |
| `SPREAD` | `centre`, `each_target` | `centre` | `centre`: one composition at the cast centre, around the unit there or the default body bounds when the cell is empty. `each_target`: one playback draws the composition around every affected unit, and at the centre when there are none. |
| `ANCHOR` | `target`, `caster_front` | `target` | `caster_front`: the composition sits one cell from the caster toward its derived front. The front points toward the nearest living hostile unit by hex distance, with ties broken by lowest `uniqueID`. With no hostile alive, the executing item chooses a deterministic fallback and records it. |
| `AREA_SCALING` | `spread`, `none` | `spread` for area-bound profiles, `none` for body-bound ones | `spread`: cube count and cube size stay as in the sketch, and positions stretch to fill the footprint's extent. `none`: the composition keeps its reference size whatever the radius. |
| `RANGE_SCALING` | `travel`, `fixed` | `travel` for profiles that have travel beats, `fixed` otherwise | `travel`: travel beats last `clamp(distance / 4, 0.75, 1.5)` times their reference length; gather, hold and impact beats keep their length. `fixed`: total duration is the same at every distance. The 4-cell reference and the 0.75–1.5 clamp are provisional and may be retuned in CPFX-9 only. |
| `ELEMENTS` | array of element names | `[ELEMENT]` when set, otherwise the distinct elements of `DAMAGE_LINES` in order, otherwise `["none"]` | Palettes the cubes draw from. With two or more, cubes take palettes in a deterministic round-robin by cube index, so each element is visibly present. |

Every profile declares which of its normalized beats are travel beats and which cast inputs it can use. For example, `cube_siphon` travels during "Pull to caster" and `cube_closing_cage` has no travel beat. A spec value that a profile cannot honour is a data error the probe reports; it never silently falls back.

### Carrier settings

These are proposed settings, approved for this cycle. They are presentation assignments only and do not alter damage, targeting, statuses, timing, or any other gameplay rule. The user will review them after the cycle closes. Blank cells use the default.

| # | Spell | `PROFILE` | `SPREAD` | `ANCHOR` | `AREA_SCALING` | `RANGE_SCALING` | `ELEMENTS` |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 01 | Ember Strike | `cube_arcing_pair` | | | | | |
| 02 | Corrupting Splatter | `cube_scattershot` | | | `spread` | | |
| 03 | Lightningbolt | `cube_corkscrew_bolt` | | | | | |
| 04 | Steel Blade | `cube_returning_throw` | | | | | |
| 05 | Splash | `cube_skipping_stone` | | | | | |
| 06 | Dark Bolt | `cube_flanking_volley` | | | | | |
| 07 | Ice Plume | `cube_ceiling_collapse` | | | | | |
| 08 | Earth Spike | `cube_ground_teeth` | | | | | |
| 09 | Dark Nova | `cube_expanding_shockwave` | | | | | |
| 10 | Magenta Reduction | `cube_implosion` | | | `spread` | | |
| 11 | Ice Plow | `cube_rolling_avalanche` | | | | | |
| 12 | Solar Storm | `cube_staggered_bombardment` | | | | | |
| 13 | Barricade | `cube_rising_barricade` | | `caster_front` | | `fixed` | |
| 14 | Bramble Crown | `cube_closing_cage` | `centre` | | `spread` | | |
| 14 | Aurora Veil | `cube_closing_cage` | `centre` | | `none` | | |
| 15 | Thornlash | `cube_climbing_coil` | | | | | |
| 16 | Smoke Tower | `cube_lifting_vortex` | | | `spread` | | |
| 17 | Closing of the Third Sanctuary | `cube_clapping_slabs` | `centre` | | `none` | | |
| 18 | Ice Statue | `cube_encasing_frost` | | | | | |
| 19 | Mending | `cube_repair_mend` | | | | | |
| 20 | Ooze Shield | `cube_intercepting_guard` | `each_target` | | | | |
| 21 | Insatiable Famine | `cube_siphon` | | | | | |
| 22 | Opening of the Third Sanctuary | `cube_cleanse` | `centre` | | `none` | | |
| 23 | Feather Time | `cube_blink_transfer` | | | | | `["steel", "wind"]` |
| 24 | Pyre Blast | `cube_charge_release` | | | | | |

Notes on the judgement calls:

- **Barricade** is a self spell with range 0, so it has no source–target line. Its wall rises one cell in front of the caster. The wall's line runs across the direction the caster faces.
- **Ooze Shield** buffs allies within 2 cells, so every buffed ally gets its own guard ring. Each ally's incoming "hostile" cube arrives from that ally's own derived front. This is a per-spell choice, not a rule for self or support spells.
- **Bramble Crown, Aurora Veil, and Closing/Opening of the Third Sanctuary** are area spells on body-bound profiles. Each plays one shape at the cast centre. Bramble Crown's briar "encircles" its area, so its cage spreads to the footprint. The other three keep body size.
- **Feather Time** has no `ELEMENT` and deals steel + wind damage, so it names both elements and shows cubes of each colour.
- `Ice Statue`, `Ice Plow`, `Smoke Tower`, `Magenta Reduction`, `Aurora Veil`, and `Solar Storm` deliberately replace their parked explicit non-cube tags with the settings above. Spells outside this table retain the current offensive/non-offensive Crownburst/Spiral fallback.

## Profile roster

The identifiers, populations, and beat names below are fixed for this cycle. "Population" describes the authored peak ingredients of one composition from the sketch, not the two neutral reference actors. With `SPREAD: each_target` the playback draws one composition per anchor.

| # | Profile ID | Study / population | Normalized beats | Spatial contract |
| --- | --- | --- | --- | --- |
| 01 | `cube_arcing_pair` | Arcing pair; 2 medium, then impact chips | Gather / angled arcs / break | source → target |
| 02 | `cube_scattershot` | Scattershot; 11 small, local chips | Pack / fan out / pepper | source → target cluster |
| 03 | `cube_corkscrew_bolt` | Corkscrew bolt; 1 medium + 7 tiny, burst | Wind up / bore forward / burst | source → target |
| 04 | `cube_returning_throw` | Returning throw; 1 large, impact chips | Throw wide / clip target / return | source → target → source |
| 05 | `cube_skipping_stone` | Skipping stone; 1 medium, three contacts | Launch / hop → hop / last impact | source → target cluster |
| 06 | `cube_flanking_volley` | Flanking volley; 4 medium, burst | Separate / curve around / converge | source → target |
| 07 | `cube_ceiling_collapse` | Ceiling collapse; 12 dust + 7 heavy + rubble | Dust warning / heavy fall / rubble | complete target area |
| 08 | `cube_ground_teeth` | Ground teeth; 5 four-cube stacks + debris | Tremble / punch upward / crumble | target or area footprint |
| 09 | `cube_expanding_shockwave` | Expanding shockwave; 1 core → 24 small | Compress / expanding ring / scatter | complete target area |
| 10 | `cube_implosion` | Implosion; 18 small → 1 dense core | Hang / snap inward / collapse | target-centred volume |
| 11 | `cube_rolling_avalanche` | Rolling avalanche; 2 large + 10 small + debris | Rumble / roll through / break apart | source → target lane |
| 12 | `cube_staggered_bombardment` | Staggered bombardment; 9 mixed + debris | First drops / uneven impacts / last heavy hit | complete target area |
| 13 | `cube_rising_barricade` | Rising barricade; 15 medium | Seed line / build upward / withdraw | a line across an anchor point |
| 14 | `cube_closing_cage` | Closing cage; 16 medium | Corner posts / close overhead / hold | target body bounds |
| 15 | `cube_climbing_coil` | Climbing coil; 22 tiny | Find feet / climb / tighten | target body bounds |
| 16 | `cube_lifting_vortex` | Lifting vortex; 28 small | Sweep inward / spiral upward / release | target-centred volume |
| 17 | `cube_clapping_slabs` | Clapping slabs; two walls of 6 + fragments | Build sides / slam together / chip away | target body bounds |
| 18 | `cube_encasing_frost` | Encasing frost; 18 small/medium + release chips | Seed crystals / build shell / lock | target body bounds |
| 19 | `cube_repair_mend` | Repair / mend; 12 tiny → 4 medium | Gather fragments / rise inward / reassemble | target or self |
| 20 | `cube_intercepting_guard` | Intercepting guard; 6 medium + incoming | Orbit / intercept / recover | protected anchor + threat from its front |
| 21 | `cube_siphon` | Siphon; 9 small → 1 medium | Loosen / pull to caster / absorb | target → source |
| 22 | `cube_cleanse` | Cleanse; 10 attached → outward chips | Cling / lift off / cast away | target body bounds |
| 23 | `cube_blink_transfer` | Blink transfer; 8 medium | Disassemble / cross in a streak / reform | source → target |
| 24 | `cube_charge_release` | Charge and release; 16 tiny → 1 large → chips | Gather power / hold weight / fire | source → target |

The plan groups these into four **families** of six, each built by one item in its own folder: travel (01–06, CPFX-3), impact and area (07–12, CPFX-4), shape and control (13–18, CPFX-5), and restore and transform (19–24, CPFX-6). The sketch's `family: 0–3` field uses the same grouping.

## CPFX-1 — Batch capture, hex footprints, and family catalogs in the debug scene

**Model:** Opus 5 / GPT Sol

**Model rationale:** this changes the proof surface every later item uses, and it has three boundaries to choose: a generic batch mode that composes with the existing capture/golden CLI, a debug-only way for a family to show its profiles before the catalog owns them, and a hex footprint in a scene built around square radii. None can be allowed to become cube-specific or to change what the two existing rituals receive.

**Depends on:** none
**Touches:**

- `src/presentation/debug/VFXDebugController.gd`
- `src/presentation/debug/VfxDebugArguments.gd`
- `src/presentation/debug/VfxDebugCapture.gd`
- `src/presentation/debug/VfxDebugWorld.gd`
- `src/presentation/debug/VfxDebugHud.gd`
- `scripts/hex_battle/cube_vfx/probe_batch_capture_args.gd`
- `scripts/hex_battle/cube_vfx/probe_batch_capture_args.gd.uid`
- `scripts/checks/probes/cube_vfx_batch_capture.json`
- `docs/VFX_DESIGN.md`

**End state:**

- **Batch selector.** A CLI selector such as `--effect-prefix=cube_`, combined with the existing seed/mode/camera/capture flags, renders every matching profile into one predictably named phase sheet per profile. It writes a machine-readable manifest containing profile ID, command inputs, output path, and process result. No match is a clear successful result with an empty manifest. Interrupted or partial output is distinguishable from a complete batch. Existing single-effect commands keep their current semantics and exit behaviour, including the unknown-`--effect` fallback.
- **Family catalogs.** A generic debug-only flag such as `--catalog-script=res://…` loads any script whose static `entries()` returns rows in the `SpellVfxCatalog.entries()` format and merges them into the picker, the batch selector, and capture. It is repeatable. Gameplay never sees these rows.
- **Hex footprint.** The debug scene builds a real `HexVfxFootprint` from its radius/shape settings, empty cells included, and hands it to any playback that has `setHexFootprint`. Playbacks without that method (the two rituals) keep receiving the current `setFootprint` call unchanged.

**Implementation brief:** decide whether one Godot process can safely rebuild the scene across profiles or whether a small orchestrating layer is required. Note that `_runCaptureMode` already replays from zero before every seek for byte-reproducibility; the batch must preserve that. Preserve the existing capture component's responsibility for individual frames, golden comparison, and process exit codes. The batch and catalog-script abstractions must be generic; they must not know the 24 IDs or their choreography. For the hex footprint, decide how a synthetic hex map sits under the existing caster/target anchors without moving them. Record the boundary choices and failure semantics in the commit body.

**Risk:** a batch mode can accidentally retain an old playback, carry tunables into the next profile, or report success before asynchronous image writes complete. A parallel capture path can silently diverge from the accepted single-effect harness. The hex footprint can drift from the on-screen footprint guide.

**Validation — self-contained:** import scripts, run the focused registered probe (argument parsing, catalog-script merging, footprint construction for single/circle/cross/line shapes including empty cells), then exercise the new selector before any `cube_*` profiles exist and confirm a complete empty manifest. Also run one existing `elemental_cube_` batch at two capture times to prove deterministic naming, reset isolation, and normal process exit, and confirm both rituals' single-effect captures at seed 7 are byte-identical to captures taken before this item's first edit. Commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter cube_vfx/probe_batch_capture
./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --import --quit --rendering-method gl_compatibility --audio-driver Dummy
./Godot_v4.4-stable_win64.exe --path . scenes/debug/VFXDebugScene.tscn --effect-prefix=elemental_cube_ --seed=7 --hide-hud --capture-at=0.30,0.70 --capture-sheet --render-resolution=640x480
```

**Validation — deferred:** none; the batch contract is exercised again by CPFX-9 with all profiles present.

## CPFX-2 — Isolated fake-3D cube substrate and the spell VFX spec

**Model:** Opus 5 / GPT Sol

**Model rationale:** this is the architectural hinge. It must reconcile the sketch's arbitrary cube poses with Godot's deterministic playback, cast anchoring, multi-anchor spread, multi-element palettes, range-stretched beats, and a strict draw-call budget. It also sets the spec vocabulary every family consumes, and it must do all of this without turning the existing cube ritual into a shared dependency.

**Depends on:** none
**Touches:**

- `src/presentation/effects/cube_placeholders/shared/**`
- `src/presentation/effects/SpellVfxSpec.gd`
- `src/presentation/effects/SpellVfxSpec.gd.uid`
- `scripts/hex_battle/cube_vfx/shared/**`
- `scripts/checks/probes/cube_vfx_shared.json`
- `docs/effects/cube-placeholder-foundation.md`

**End state:**

- **Spec.** `SpellVfxSpec` parses a spell reference's `VFX` object (and legacy `VFX_PROFILE`) into a validated spec with every default from the "Per-spell VFX spec" table, and reports unknown keys, unknown values, and wrong types as errors. It is presentation-only and has no dependency on gameplay code beyond reading the reference dictionary.
- **Substrate.** An isolated cube-placeholder substrate renders at least 48 simultaneously visible fake-3D cubes per composition, with per-cube position, scale, yaw/frame, opacity, and palette (element) role. It preallocates its maximum population once the spec and cast context are known, before play, and performs no node/resource allocation during timeline sampling. At peak it uses no more than four render nodes and four estimated draw calls **per playback**, including a two-element spec and an `each_target` spread over six anchors.
- **Timeline.** It exposes deterministic normalized-pose sampling through a `VfxPlayback`-compatible owner. A profile declares its beats and which are travel beats, and the substrate applies `RANGE_SCALING` to them. It also exposes the impact time a battle caller should hold the action for.
- **Inputs.** It understands source, target, target-body bounds, target-centred local space, an optional complete `HexVfxFootprint`, `SPREAD`, `ANCHOR` with a supplied caster-front direction, and `AREA_SCALING`. If exact source-study sampling shows a single-composition peak above 48, capacity rises to the measured peak; visible cubes are never dropped to protect the budget.

**Implementation brief:** choose the batching representation and the boundary between choreography data and rendering. A `MultiMesh`-style solution is the likely fit, but the choice belongs to the implementer because transparency, atlas frame selection, ordering, and several element palettes may change the correct answer. Copy the proven 12-frame fake-cube atlas construction and elemental palette relationships into this new owned area; do not extract, parameterize, or edit `ElementalCubeRitualEffect.gd`, `ElementalCubeRitualProfile.gd`, their materials, or their callers. Build textures per playback or give any static cache an explicit release path: `VfxTextures`' unreleased static cache is why `probe_vfx_contract` crashes on exit, and a new probe that inherits that crash cannot gate. Preserve nearest filtering, unshaded presentation, and the illusion of quarter-turn yaw. Decide where the caster-front direction is computed so the debug scene and the battle adapter derive it the same way, without adding facing to simulation. Explain the draw-call and palette tradeoffs, and how a future spec aspect is added, in the commit body.

**Risk:** per-instance opacity/atlas/palette choice can defeat batching; alpha ordering can make the fake depth unreadable; an attractive shared abstraction can create a forbidden regression surface for the two surviving rituals. Target/body scaling may distort the sketch if world conversion is not uniform. Range stretching can make seek non-deterministic if the stretch is computed from anything but the configured inputs.

**Validation — self-contained:** the focused probe samples at least 101 normalized times in ascending, descending, and shuffled order for two seeds, using a test composition built only for the probe. It asserts:

- finite transforms, identical repeated poses, no live-count growth, and no post-construction resource/node allocation;
- peak capacity and ≤4 render nodes/draw calls, both with one element and one anchor and with two elements and six `each_target` anchors;
- pause, zero rate, 4× rate, `skip_to_settle()`, and idempotent disposal;
- exact reference beat boundaries at distance 4, and stretched travel beats at distances 2, 6, and 10 within the clamp;
- spec parsing of every default and every error case;
- that the commit leaves the existing ritual scripts/resources untouched.

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter cube_vfx/shared
./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --import --quit --rendering-method gl_compatibility --audio-driver Dummy
```

**Validation — deferred:** none; appearance is judged through the family effects and final validation.

## Family items — shared rules for CPFX-3 to CPFX-6

These rules apply to each of the four family items below:

- **Family catalog.** Each family ships `<Family>Catalog.gd` in its own source folder, exposing its six profiles through a static `entries()` in the `SpellVfxCatalog.entries()` format. The debug scene loads it with CPFX-1's catalog-script flag, which lets the family capture its own work before CPFX-7 registers anything with gameplay.
- **Blocking checkpoint.** Each family builds its first-named profile before the others. At that point it captures a five-frame sheet at `t=0.12,0.30,0.50,0.70,0.90` in the reference configuration, sends it to the user, and **stops until the user approves**. It builds the remaining five only after approval, and records the checkpoint outcome in the commit body. This is a user decision point, not a self-check.
- **Proof sheets.** Before commit, the family produces the same five-frame sheet for all six profiles through the batch harness, and records the commands in the commit body. These are self-contained proof, not deferred validation. CPFX-9 still makes the final fresh-eyes comparison.
- **Probe command.** `-Filter cube_vfx/<family>` runs the family's focused probe.

## CPFX-3 — Travel and delivery family

**Model:** Opus 5 / GPT Sol

**Model rationale:** six related but perceptually distinct source→target motions must be translated from executable diagrams into one coherent game-space family without erasing their characteristic trajectories, and each must stretch with range without losing its shape. This is visual judgement within a fixed contract.

**Depends on:** CPFX-1, CPFX-2
**Touches:**

- `src/presentation/effects/cube_placeholders/travel/**`
- `scripts/hex_battle/cube_vfx/travel/**`
- `scripts/checks/probes/cube_vfx_travel.json`
- `docs/effects/cube-placeholder-travel.md`

**End state:** profiles 01–06 exist as independently constructible playbacks. Their normalized poses preserve the sketch's exact populations, relative sizes, lateral offsets, stagger order, contact count, arc character, convergence, and return path. Every path derives from live source/target anchors. At distance 4 the beat boundaries match the sketch; at distances 2, 6, and 10 only the declared travel beats stretch, and each effect stays legible.

**Implementation brief:** establish a shared coordinate conversion for the family, then translate each sketch function rather than designing anew. Preserve the important contrast: two weighted lobs, a widening pepper cone, a drilled helix, one broad returning sweep, three readable skips, and four simultaneous flanks. The blocking checkpoint profile is `cube_arcing_pair`: correct the coordinate conversion from the user's feedback before multiplying it across the family.

**Risk:** perspective and long source distances can flatten vertical arcs or hide z-offsets; global easing helpers can make six effects feel interchangeable; debris can outlive disposal or inflate capacity.

**Validation — self-contained:** a focused probe checks:

- exact active-cube counts and semantic checkpoints at the sketch's phase/contact boundaries;
- source/target endpoint tolerance;
- three skips for `cube_skipping_stone`, target contact before return for `cube_returning_throw`, and simultaneous convergence for `cube_flanking_volley`;
- deterministic seed/seek, travel-beat stretch at distances 2/4/6/10, and substrate budgets.

It also covers the family's proof sheets.

**Validation — deferred:** CPFX-9 makes the final sketch comparison.

## CPFX-4 — Impact and area family

**Model:** Opus 5 / GPT Sol

**Model rationale:** these six studies carry the largest populations and the strongest implied mass. Translating them requires judgement about footprint projection, area spread, warning readability, overlap, and performance while the visible choreography remains fixed.

**Depends on:** CPFX-1, CPFX-2
**Touches:**

- `src/presentation/effects/cube_placeholders/impact/**`
- `scripts/hex_battle/cube_vfx/impact/**`
- `scripts/checks/probes/cube_vfx_impact.json`
- `docs/effects/cube-placeholder-impact.md`

**End state:** profiles 07–12 preserve the sketch's dust-before-weight ceiling collapse, sequential teeth, core-to-ring shockwave, accelerating implosion, two-heavy avalanche, and uneven bombardment ending in its largest hit. Under `AREA_SCALING: spread`, area-bound profiles fit the complete supplied hex footprint rather than a Euclidean guess, keep sketch counts and cube sizes, and remain truthful when affected cells are empty. Under `none`, they keep reference size.

**Implementation brief:** decide how diagram-area positions map onto arbitrary footprint topology while keeping the source study recognizable. The warning/impact distinction is non-negotiable: the ceiling's 12 dust cubes precede seven heavy cubes; bombardment culminates in the ninth heavy strike; the shockwave reads as one compressed core becoming a 24-cube ground ring. Preserve cross/line footprint truth where applicable, but do not invent extra cubes or change counts to fill awkward shapes. For source→target avalanche, treat the footprint as collision truth rather than a reason to bend its lane beyond recognition. The blocking checkpoint profile is `cube_ceiling_collapse`.

**Risk:** the sketch's planar area is not itself a hex-footprint algorithm; naïve radial placement can advertise cells gameplay does not hit. Overlapping debris may exceed capacity, and large alpha-sorted cubes can obscure warnings. At radius 4 a fixed count can look sparse; that is accepted, not a reason to add cubes.

**Validation — self-contained:** the focused probe checks:

- counts and ordering at every named beat, and final-heavy-hit ordering;
- implosion radial monotonicity after the snap, and shockwave outward monotonicity;
- placement inside representative single, circle radius 1–4, cross, and line footprints, including empty outer cells, under both `spread` and `none`;
- every profile across seed/seek/rate/disposal, and the shared render budget.

It also covers the family's proof sheets, plus a yaw 0/90 comparison for ceiling collapse and shockwave.

**Validation — deferred:** CPFX-9 makes the final sketch comparison.

## Midpoint convergence review

After CPFX-1 through CPFX-4 are committed, stop before wave 3. Compare the retained sketch, both implemented families, probe evidence, render budgets, the spec's behaviour under both families, and the untouched existing rituals against the cycle outcome. Confirm that:

- the shared substrate is serving the choreography rather than forcing visible compromises;
- batch capture and catalog-script loading have not become cube-specific;
- range and area scaling keep each study recognizable;
- the source-truth rules are being applied consistently.

Correct drift only inside the remaining items' owned paths. If recovery requires changing CPFX-1/2 ownership or the promised visual outcome, stop and coordinate a revised plan with the user.

## CPFX-5 — Shape and control family

**Model:** Opus 5 / GPT Sol

**Model rationale:** the six effects must communicate persistent spatial states — wall, cage, snare, lift, crush, encasement — using identical raw material. Their success depends on silhouette, target-body adaptation, the `caster_front` anchor, and area spread of a body-bound shape, not mechanical transcription alone.

**Depends on:** CPFX-1, CPFX-2, and the midpoint convergence review
**Touches:**

- `src/presentation/effects/cube_placeholders/control/**`
- `scripts/hex_battle/cube_vfx/control/**`
- `scripts/checks/probes/cube_vfx_control.json`
- `docs/effects/cube-placeholder-control.md`

**End state:** profiles 13–18 preserve the study populations, construction order, hold silhouettes, and exits. Body-bound cages, coils, and shells adapt uniformly to standard, wide, and tall target bounds. Under `AREA_SCALING: spread` the cage grows to enclose the footprint with unchanged cube count and size. The barricade stands one cell in front of its anchor, running across the caster's front direction, and does not pretend to create gameplay obstruction. The vortex releases rather than simply fading. The clapping slabs visibly make contact before fragmenting.

**Implementation brief:** translate the sketch's body-sized coordinate system through one coherent bounds policy. Protect the silhouette of each effect: a three-layer 5×3 barricade, four four-cube cage posts closing overhead, a 22-cube tightening helix, a 28-cube skirt-to-column vortex, two six-cube slabs, and three rings of six frost cubes. Adaptation may scale or offset the complete composition; it may not alter counts or phase order to fit a body preset or an area. The blocking checkpoint profile is `cube_closing_cage`, captured for standard, wide, and tall targets and for a radius-2 `spread` footprint.

**Risk:** per-axis target scaling can turn cubes into non-cubes or make wide/tall bodies produce different choreography; dense shells may occlude the target completely; persistent holds may expose popping at seek boundaries; an area-spread cage can read as a wall rather than a cage.

**Validation — self-contained:** the focused probe checks:

- exact structures and closure/contact events;
- uniform cube scale under all body presets and under area spread;
- no claimed area for body-only profiles under `none`;
- barricade placement relative to the anchor and front direction, including a zero-length source–target case;
- deterministic random access across hold boundaries, and all shared budgets.

It also covers the family's proof sheets.

**Validation — deferred:** CPFX-9 performs the final comparison and yaw sweeps.

## CPFX-6 — Restore and transform family

**Model:** Opus 5 / GPT Sol

**Model rationale:** these effects carry semantic direction — repair, intercept, drain, cleanse, transfer, charge — that must read without bespoke iconography. Preserving that meaning with cubes requires motion-design judgement, careful two-anchor ownership, per-anchor threat direction, and a self-target fallback.

**Depends on:** CPFX-1, CPFX-2, and the midpoint convergence review
**Touches:**

- `src/presentation/effects/cube_placeholders/restore/**`
- `scripts/hex_battle/cube_vfx/restore/**`
- `scripts/checks/probes/cube_vfx_restore.json`
- `docs/effects/cube-placeholder-restore.md`

**End state:** profiles 19–24 preserve the sketch's directional semantics and exact population changes:

- repair fragments become four stable blocks;
- guards intercept and recover, and under `each_target` every protected anchor has its own ring with its threat arriving from that anchor's front;
- siphon travels target→source;
- cleanse detaches outward;
- blink disassembles, transfers, and reforms, and with two elements both colours are visibly present;
- charge visibly gathers, holds weight, fires, and breaks.

**Implementation brief:** make direction readable from motion alone and keep source/target roles explicit in profile data. Preserve the guard's incoming seventh cube as hostile motion distinct from its six orbiters. Preserve the charge's held large cube rather than collapsing gather and fire into one continuous travel. Self-target casts need a stable, non-zero basis when source and target coincide; decide that fallback from cast context and the derived front without mutating gameplay positions. The blocking checkpoint profile is `cube_charge_release`; verify the hold in the sheet before the user sees it.

**Risk:** coincident self-target anchors can produce undefined direction, target/source swaps can reverse spell meaning, and reassembly transitions can pop when time is sampled rather than played continuously. Six guard rings can overlap into noise when allies stand adjacent.

**Validation — self-contained:** the focused probe checks:

- directional derivatives and population handoffs;
- guard collision/recovery with one anchor and with six adjacent anchors;
- stable coincident-anchor behaviour;
- two-element palette distribution;
- the charge hold interval;
- deterministic random access at every handoff, and shared budgets.

It also covers the family's proof sheets.

**Validation — deferred:** CPFX-9 performs the final comparison.

## CPFX-7 — Catalog, spell data, battle integration, and spell preview

**Model:** Opus 5 / GPT Sol

**Model rationale:** this item owns the compatibility boundary among spell data, the spec, generic catalog factories, body/source/area binding, the hex adapter, and action pacing. It must activate the library without resurrecting parked implementations or spreading per-profile branches through gameplay.

**Depends on:** CPFX-3, CPFX-4, CPFX-5, CPFX-6
**Touches:**

- `src/presentation/effects/SpellVfxCatalog.gd`
- `src/presentation/battle/effects/HexBattleVfxBridge.gd`
- `src/presentation/battle/HexBattleVisualAdapter.gd`
- `src/presentation/battle/HexBattleCombatFeedback.gd`
- `src/presentation/debug/VFXDebugController.gd`
- `src/presentation/debug/VfxDebugWorld.gd`
- `src/presentation/debug/VfxDebugHud.gd`
- `data/spells.json`
- `docs/SPELL_CATALOG_SCHEMA.md`
- `docs/VFX_DESIGN.md`
- `docs/effects/README.md`
- `docs/MODULE_MAP.md`
- `scripts/hex_battle/probe_vfx_contract.gd`

Before the first edit, confirm that no open item in another cycle claims `HexBattleVisualAdapter.gd`, `HexBattleCombatFeedback.gd`, or `docs/MODULE_MAP.md`; several older cycles name them. If one does, stop and coordinate the hand-off with the user.

**End state:**

- **Catalog.** `SpellVfxCatalog.entries()` contains exactly 26 active profiles: the two unchanged elemental rituals and the 24 `cube_*` profiles, sourced from the four family catalogs. Every `cube_*` entry declares enough generic spatial metadata for the catalog, debug, and battle paths to supply its anchors, target bounds, footprint, and spec without profile-name conditionals. The debug picker can instantiate all 26.
- **Spell data.** `data/spells.json` carries the carrier settings table exactly, as `VFX` objects; the six parked `VFX_PROFILE` tags are gone. All other spells keep fallback resolution.
- **Battle.** The cast payload carries the parsed spec and the derived caster front (per anchor for `each_target`). The bridge configures playbacks from it. The action hold uses the playback's own impact time where it provides one, so range-stretched travel still lands the hit on its impact beat; the rituals keep their current hold fraction.
- **Spell preview.** `--spell="<name>"` in the debug scene applies that spell's spec, radius, shape, and range the way the battle would.
- **Parked effects.** No active factory, spell spec, or bridge branch selects a parked non-cube effect.

**Implementation brief:** decide the smallest generic catalog contract for spatial binding and factory construction. Extend the bridge's existing `setHexFootprint` seam rather than replacing it, and do not restore `AREA_FACTORIES` behaviour for parked profiles or move presentation decisions into simulation. Prefer data-driven binding metadata over a 24-case match. Preserve the public semantics used by existing callers (`resolve`, `resolvedProfileId`, `actionHoldFraction`, `maxLive`, `create`, and `profileForSpell`) or deliberately migrate every caller in this item's paths. Decide how `maxLive` behaves for an `each_target` playback. Record why the chosen boundary will support more placeholder profiles and more spec aspects without another bridge rewrite.

**Risk:** catalog metadata or the spec can become a shadow gameplay-targeting system; spell-data edits can accidentally change rules beyond the `VFX` block; a generic factory signature can break the existing rituals; area effects can regress to occupied-target cells only; a playback-supplied hold time can desynchronise the queue if it is read before play.

**Validation — self-contained:** extend `probe_vfx_contract.gd` to assert:

- the exact 26-ID active set, the exact carrier settings table, and no active parked profile;
- unchanged fallback classification, and constructibility of every entry;
- generic binding completeness, and full footprint propagation including empty cells;
- spec propagation to the playback, including `each_target` and a two-element spec;
- hold time equal to the impact beat at distances 2/4/6;
- absence of profile-ID branching in battle gameplay paths.

The probe is quarantined, so read its `HXB_VFX_OK` marker and failure lines rather than the sweep exit code. Parse `data/spells.json` and run import plus focused probes.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter probe_vfx_contract
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

Before editing `probe_entrypoints.gd`, confirm no open item in another cycle claims it; if one does, stop and coordinate.

**End state:** one reviewable manifest names, for every profile:

- its family, carrier spell(s), and their spec;
- its binding mode, exact authored ingredient counts, and maximum simultaneous population;
- its named beat boundaries and which beats are travel beats;
- its pose-signature checkpoints.

One registered probe constructs all 26 active profiles and verifies that the 24 new effects conform to that manifest, while both existing rituals remain unchanged and constructible.

**Implementation brief:** choose pose signatures that defend the sketch — counts by role, centroid/radius/height ranges, endpoint/contact events, monotonic movement, phase handoffs — without snapshotting raw renderer internals. Sample enough times around discontinuities to catch one-frame holes and seek-only pops. Treat the manifest as the machine-readable mirror of this plan's roster and carrier table, not as a second design document. Register any additional entrypoint only if required by the repository's probe loader.

**Risk:** weak signatures can pass visibly wrong motion; over-specific float snapshots can fail cross-platform for no perceptual reason. A whole-library probe can also hide the profile that failed unless diagnostics remain profile/time specific.

**Validation — self-contained:** run the focused library probe, the full probe sweep, import, and non-interactive project/debug-scene loads. The probe must sample:

- forward, reverse, and shuffled times, with multiple seeds;
- source distances 2/4/6/10, body presets, footprint shapes, and both `SPREAD` values.

It must assert:

- exact catalog/mapping/spec/manifest agreement;
- finite poses, lifecycle/rate/skip/dispose, and no active non-cube factories;
- population caps and ≤4 render nodes/draw calls per new playback.

Record unrelated in-flight changes that can affect the broad sweep rather than repairing paths outside this item.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1 -Filter cube_vfx/probe_cube_placeholder_library
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checks/run_probe_sweep.ps1
./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --import --quit --rendering-method gl_compatibility --audio-driver Dummy
./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --quit-after 5 --rendering-method gl_compatibility --audio-driver Dummy
./Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . scenes/debug/VFXDebugScene.tscn --quit-after 5 --rendering-method gl_compatibility --audio-driver Dummy
```

**Validation — deferred:** none beyond CPFX-9's visual/gameplay acceptance.

## CPFX-9 — Standalone visual and gameplay validation; cycle close

**Model:** Opus 5 / GPT Sol

**Model rationale:** acceptance is an independent judgement about motion fidelity, readability, and semantic fit across work from four implementation families plus spec-driven adaptation. The implementing sessions cannot fairly validate their own look, and the checks span several subsystems, so this is a standalone fresh-eyes item.

**Depends on:** CPFX-8
**Touches:**

- `src/presentation/effects/cube_placeholders/**`
- `src/presentation/effects/SpellVfxCatalog.gd`
- `src/presentation/effects/SpellVfxSpec.gd`
- `src/presentation/battle/effects/HexBattleVfxBridge.gd`
- `src/presentation/battle/HexBattleVisualAdapter.gd`
- `src/presentation/battle/HexBattleCombatFeedback.gd`
- `src/presentation/debug/VFXDebugController.gd`
- `src/presentation/debug/VfxDebugArguments.gd`
- `src/presentation/debug/VfxDebugCapture.gd`
- `src/presentation/debug/VfxDebugWorld.gd`
- `src/presentation/debug/VfxDebugHud.gd`
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

The retained sketch `docs/sketches/2026-09-24-cube-spell-motion-studies.html` is read-only in this item. Validation defects may be fixed only in the paths above. Existing elemental ritual implementation/resources and all parked VFX remain outside the write set. In `data/spells.json` only the `VFX` objects may change, and only the range-scaling clamp and reference distance may be retuned from the provisional values.

**End state:**

- every study is visually accepted against the sketch at canonical times;
- representative effects survive yaw, body, distance, footprint, and spread variation;
- mapped and fallback spells work through battle presentation;
- all automated checks pass;
- `BACKLOG.md` carries one entry for the user's post-cycle review of the carrier settings, plus any genuinely open out-of-scope work, each recorded once;
- this cycle file is deleted in the validation commit. The retained sketch remains the durable record of the visual decision.

**Implementation brief:** validate at the exact committed revision and record unrelated in-flight paths that may affect observation. Use the batch harness to generate 24 canonical reference-mode sheets with seed 7, ice palette, the reference configuration (source distance 4, one-cell area, standard target), HUD hidden, retro 640×480, and normalized times `0.12,0.30,0.50,0.70,0.90`. Compare every sheet side by side with the HTML at those same scrub positions. Judge counts, size hierarchy, trajectory, beat ordering, silhouettes, warning-before-impact, and directional meaning; do not judge pixel identity between Canvas and Godot. Fix deviations in owned paths, regenerate the affected family, and rerun its probe before proceeding.

Then perform:

- yaw 0/90/180 sheets for `cube_arcing_pair`, `cube_ceiling_collapse`, `cube_expanding_shockwave`, `cube_rising_barricade`, `cube_closing_cage`, `cube_lifting_vortex`, `cube_blink_transfer`, and `cube_charge_release`;
- native-resolution (no retro preset) sheets for arcing pair, ceiling collapse, closing cage, and charge release, since battle renders natively by default;
- standard/wide/tall body checks for cage, coil, encasing frost, guard, and cleanse;
- radius/shape checks that include empty cells for ceiling collapse, ground teeth, shockwave, and bombardment;
- range checks at distances 2, 4, 6, and 10 for arcing pair, siphon, blink transfer, and charge release;
- `--spell` previews of every carrier in the settings table, including Barricade's front wall, Ooze Shield's per-ally rings, Bramble Crown's spread cage against Aurora Veil's centre cage, and Feather Time's two colours;
- live battle casts for one source→target attack, one target-bound control, one complete-area effect, one self/support effect, one `each_target` spell, one Crownburst fallback, and one Spiral fallback, confirming that the hit lands on each effect's impact beat;
- pause, forward/backward seek, zero rate, 4× rate, `skip_to_settle()`, live-cap pressure, interruption, and disposal checks;
- unchanged debug captures of both existing elemental cube rituals at the same seed/mode used before this cycle;
- the complete CPFX-8 command set after the last correction.

No permanent phase sheets or goldens are committed: they are proof output under `debug/`, and commands plus results belong in the validation commit body. If a mismatch is a deliberate change to this plan's locked visual target rather than an implementation defect, stop and ask the user; do not rewrite the retained sketch during validation. When reporting closure, list the carrier settings table as shipped so the user can start the post-cycle review from it.

**Risk:** a large visual pass can become superficial; validating only one camera hides flattened arcs and overlapping silhouettes; broad correction authority can tempt cleanup of parked/shared effects. Keep an explicit 24-row checklist and report each profile pass/fail with any correction.

**Validation — self-contained:** full probe sweep, import, project load, debug-scene load, focused diff/check of every owned path, and exact verification that the cycle file is the only plan path deleted.

**Validation — deferred:** all visual/gameplay checks above are this item's work and must pass before it commits. A failure keeps the cycle open.

## Waves

| Wave | Items | Why disjoint / validation form |
| --- | --- | --- |
| 1 | CPFX-1, CPFX-2 | Debug scene and capture contract versus isolated substrate and spec; no shared paths. |
| 2 | CPFX-3, CPFX-4 | Travel and impact family directories/probes/docs are disjoint; both depend on committed CPFX-1 and CPFX-2. Each session stops once at its blocking user checkpoint. End the wave with the mandatory midpoint convergence review after implementation item 4. |
| 3 | CPFX-5, CPFX-6 | Control and restore family directories/probes/docs are disjoint and begin only after the review. Each session stops once at its blocking user checkpoint. |
| 4 | CPFX-7 | Single integration owner for catalog, spell data, battle adapter/feedback, bridge, debug spell preview, central docs, and existing VFX contract probe. |
| 5 | CPFX-8 | Single whole-library gate owner after integration is committed. |
| 6 | CPFX-9 | **Validation: standalone.** Fresh-eyes visual judgement spans four families and battle/debug integration, so folding is not legal. This item also closes the cycle. |

Each executing session checks that its actual model is Opus 5 / GPT Sol before editing and reports a mismatch without stopping. One commit is required per item, with its self-contained evidence and design findings in the body and `Plan-Item: CPFX-N` as the last trailer. CPFX-3 through CPFX-7 are **implemented; pending validation** until CPFX-9 commits. CPFX-1, CPFX-2, and CPFX-8 are verified by their own self-contained checks.

## Deliberately excluded

- Real 3D cube meshes, physics, volumetrics, dynamic lighting, and camera changes.
- Restoration, retuning, deletion, or refactoring of parked non-cube effects.
- Refactoring or visual changes to the existing Crownburst and Spiral ritual implementations.
- Final bespoke spell art, lore-specific motifs, sound design, screenshake, damage numbers, or gameplay feedback beyond cube motion.
- Changes to spell mechanics, targets, balance, action timing rules, AI, or simulation state, including any unit facing in simulation.
- Spec aspects beyond the six in this plan's vocabulary; later aspects are added through the same parser in a later cycle.
- New mappings beyond the carrier settings table; spells without a spec use the current two-profile fallback.
- Permanent capture sheets or goldens without a repository runner that can compare them.
- General-purpose particle/VFX framework extraction. This library may have an internal substrate, but it is not authority to migrate unrelated callers.
