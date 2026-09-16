# Hex battle playability restoration

2026-09-12. Restore the battle presentation and player-facing information that
Battle 25D supplied, using its frozen square reference as the visual baseline
and the approved hex rules as the gameplay baseline. This is a source-audited
plan, not a claim that the current scene has passed visual inspection. Opening
this cycle writes only this file; it does not execute the implementation items.

## Outcome

A player can start a reproducible scenario, identify every unit and side, read
health and effects, inspect an actor and target, understand a command before
confirming it, watch its consequences, and reach an intelligible result. CPU
battles are equally readable and controllable. Terrain, models, lighting,
camera, UI and effects form one usable scene at 1280x720 and 1920x1080.

Restore existing artwork and visual language. New monster art, lore, combat
rules, roster editing and balance are excluded. A party-order display replaces
the predecessor's individual speed rail; do not restore obsolete scheduling.

## Evidence and compatibility baseline

Source inspection at `e3e37a7`, against archive commit
`0c101e16f6dd26062cb6c76d0b74b46d6dc73361`:

| Surface | Current evidence | Restoration owner |
|---|---|---|
| Initial population | `emitInitialBoard()` is connected before battle start; already fixed in `0fc9eb1` | Preserve; do not repeat the fix |
| Terrain | Existing First hex battle cycle owns authored terrain, picking and fallback | External dependency below |
| Model color | `HexBattleVisualAdapter._on_monster_spawned` passes `[]` as elements | HPR-1 |
| Model artwork | `MonsterVisualRegistry.VISUAL_PATHS` is empty in both the archive and current source; the authored procedural silhouette is the baseline | HPR-1; no promise of missing bespoke assets |
| Lighting/background/render | Controller creates the shared ambient environment but no directional light, animated sky or `RetroRenderController`; archived controller supplies all three | HPR-3 |
| Combat feedback | Adapter queues MOVE only; most event handlers inherit no-ops; `playSpell()` exists but is not an event subscription | HPR-4 |
| Defeat/withdrawal | Models are freed directly in event callbacks, ahead of queued playback | HPR-4 |
| Above-unit icons | Archived adapter uses projected `StatusBadgeRow` controls; current adapter creates none | HPR-5 |
| Inspection and battle HUD | `HexBattleHud` supplies party selection, command menu and status text; actor/target windows, health and resonance readouts are absent | HPR-6 |
| Setup/result | Invalid seed silently becomes zero; controller hides start refusal detail; result prints Team 0 for draw; completion offers no explicit result controls | HPR-2, HPR-7 |

Read `docs/README.md`, `POLICIES.md`, `ARCHITECTURE.md`, `GAME_DESIGN.md`,
`UI_DESIGN.md`, `VFX_DESIGN.md` and the relevant `LEARNINGS.md` sections
(render isolation, visual playback, UI animation, shared visual resources).
Current code and AGENTS.md override stale square-runtime descriptions and the
obsolete single-cycle/branch instructions in `docs/plans/README.md`.

Inspect `references/square-battle/source.zip` read-only. Its useful donors are
`src/systems/BattlePresentationController.gd`,
`src/presentation/GodotVisualAdapter.gd`, and their referenced UI/effect files.
Use `references/square-battle/README.md` and `acceptance.json` for the runnable
baseline. Never import the archive into the active runtime. Reuse retained
components unchanged; copy missing presentation glue into the owned hex paths.
Do not edit donor effects, shared theme tokens, shaders, factories or timelines.
No item below claims a shared-contract migration.

## Coordination and execution contract

The open First hex battle cycle owns overlapping controller, adapter, camera
and board paths in FHB-7 and again in its FHB-9 validation. **HPR-1 and HPR-3
must wait for FHB-9's successful closing commit**, not merely FHB-7's commit.
This is an explicit sequential ownership lane, not a requirement for a clean
tree or an idle repository. HPR-2 has disjoint paths and can run immediately.
Do not edit the other cycle or inherit its unrelated championship-variety gate
as work in this cycle. If its closure is delayed, an earlier transfer of the
overlapping paths requires explicit user coordination; do not assume one.

Use the current branch. At authorship it is `plan/first-hex-battle`; this plan
does not create or switch a branch or change the older cycle's branch intent.
Recheck the branch when executing, since the other cycle may close first.

Each item owns exactly its Touches list. New `.gd` files include their `.uid`
sidecars; an existing script's unchanged sidecar is not an additional claim.
`scripts/hex_battle/restoration/` is a new directory of bounded probes, not a
new test framework. Probe fixtures must be in memory or under `user://`; they
must not rewrite shipping scenarios or generated terrain. Rendering captures,
logs and temporary extracted references belong in scratch storage.

Check and announce the item's model against the running model before execution,
without blocking on a mismatch. Terra items below are exact specifications;
Sol items leave bounded integration decisions to the executor and require the
reasoning in the commit body. No subagent or task creation is implicit.

One explicit-path commit per item. Record implementation, false assumptions,
deliberate exclusions and self-contained evidence in its body, ending with
`Plan-Item: HPR-N`. The cycle file freezes at execution; only HPR-8 may delete
it on successful closure. Resume using:

```powershell
git log --grep="Plan-Item: HPR-" --format="%h %s"
git log --grep="Plan-Item: FHB-9" -1
```

Every item also runs `git diff --check -- <its explicit owned paths>` and
reviews `git diff HEAD -- <its explicit owned paths>` before committing.
Run probes using the existing waited Windows runner with the exact marker,
not direct-process exit code alone. Self-contained probes prove structure,
event ordering and state consistency; they never count as visual acceptance.
Deferred checks below all belong to the single standalone HPR-8 gate.

## Items

### HPR-1 — Restore element-colored unit bodies

**Model:** Sonnet 5 / GPT Terra.

**Model rationale:** The donor establishes the exact three-argument factory
call and the missing data is already on the authoritative monster; no material
design or factory change is needed.

**Depends on:** FHB-9 successful closure (external ownership release).

**Touches:**
- `src/presentation/battle/HexBattleVisualAdapter.gd`
- `scripts/hex_battle/restoration/probe_unit_colors.gd` and `.uid` (new)

**End state:** Spawn uses the monster's actual `elements` for the existing
factory. Team-colored base, ascension tier, neutral/single/dual-element body
and initial cell placement agree with the predecessor's factory contract.

**Implementation:** In `_on_monster_spawned`, read
`_state.getMonster(monsterID)` when `_state != null`. Set local `elements:
Array` to that monster's `elements`, otherwise `[]`. Pass `elements` as the
third argument to `MonsterModelFactoryScript.build`; preserve the name, team
color, parenting, position and `_models` entry. Mirror the archived
`GodotVisualAdapter._on_monster_spawned` data lookup. Do not modify factory,
registry, palette, geometry, materials, gameplay data or any other handler.

The probe uses neutral, one-element and two-element in-memory monsters with
distinct IDs and both team colors. Compare returned model materials and split
bounds against direct `MonsterModelFactory.build` results with the same inputs,
check one model per ID and world positions, then dispose both sets. Exercise
the adapter's null-state fallback too. Marker `HPR_UNIT_COLORS_OK`.

**Risk:** Passing the wrong object's elements can make a plausible but false
body color; compare materials by inputs/properties, not node count alone.

**Validation:**
- Self-contained: `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script scripts/hex_battle/restoration/probe_unit_colors.gd -Marker HPR_UNIT_COLORS_OK`.
- Deferred: HPR-8 compares neutral, single and split bodies and both team bases under the restored light at several camera angles.

### HPR-2 — Make setup validation explicit and reviewable

**Model:** Sonnet 5 / GPT Terra.

**Model rationale:** This is a local form correction with fixed failure cases,
existing scenario validation and an exact public error API for later wiring.

**Depends on:** Nothing.

**Touches:**
- `src/presentation/battle/HexBattleSetupUI.gd`
- `scripts/hex_battle/restoration/probe_setup_validation.gd` and `.uid` (new)

**End state:** A blank or non-integer seed never emits `battle_requested`;
valid integer input emits its exact parsed value once. No selected or invalid
scenario emits a request. Start failures can be shown without losing the form.

**Implementation:** Add `showError(message: String) -> void`, displaying the
message in a dedicated `Label` named `SetupError` below `ScenarioSummary`.
Keep summary and error independent. In `_onStartPressed`, validate the trimmed
seed with `is_valid_int()` before calling `selectedSeed()`. Invalid seed text:
`Enter a whole-number seed.` Empty selection: `Choose a scenario first.` Load
the selected scenario through `BattleScenarioFactoryScript.loadFromPath`; on
failure display its returned error and return. Clear `SetupError` before a
valid emission and when selection changes. Preserve sorted scenario discovery,
seed default `1`, the existing signal signature and scenario-owned rosters.
No controller edits, skin redesign, persistence or new scenario data.

The probe observes emitted requests for blank, `abc`, `1.5`, `0`, `42`, and
`-1`, plus an invalid scenario and empty list using scratch fixtures. The first
three seed values emit nothing; the last three retain their integer values.
Assert `showError` preserves selection and seed. Marker `HPR_SETUP_OK`.

**Risk:** A malformed form must not accidentally start a different seed-zero
battle; test the signal payload rather than the label alone.

**Validation:**
- Self-contained: `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script scripts/hex_battle/restoration/probe_setup_validation.gd -Marker HPR_SETUP_OK`.
- Deferred: HPR-8 reads errors at both target resolutions and confirms recovery by correcting the form.

### HPR-3 — Restore the battle render stage and camera contract

**Model:** Opus 5 / GPT Sol.

**Model rationale:** Moving the world into a render viewport changes picking,
projection, lifetime and native-resolution UI simultaneously; the integration
boundary needs judgment even though the visual baseline already exists.

**Depends on:** FHB-9 successful closure. May run alongside HPR-1.

**Touches:**
- `src/systems/hex_battle/HexBattleController.gd`
- `src/presentation/battle/HexBattleCamera.gd`
- `src/presentation/battle/HexBattleStage.gd` and `.uid` (new)
- `src/presentation/battle/ui/HexGraphicsPanel.gd` and `.uid` (new)
- `scripts/hex_battle/restoration/probe_stage.gd` and `.uid` (new)

**End state:** Authored terrain and units share one lit world, with the
predecessor's sky and render options; UI remains native resolution. Mouse
picking, six-neighbour navigation, orbit, pitch, zoom and camera framing remain
correct under resize, letterboxing and render presets. Graphics controls can
open, change the existing supported settings and reset them.

**Implementation brief:** Integrate retained `RetroRenderController`,
`BattleEnvironmentFactory`, render catalogs and sky shader without changing
them. The archived `_setup_camera_and_lighting` establishes the baseline key:
rotation `Vector3(-45, 45, 0)`, white, energy `1.0`, shadows disabled. Preserve
those values; no new lighting art direction. Preserve the terrain/fallback
behavior accepted by the preceding cycle.

Decide the smallest stage-owned composition that can survive setup/battle
transitions and dispose all render resources. Own the screen/world conversion
boundary here, using the renderer's conversion APIs; no duplicated letterbox
math in future badges or readouts. Preserve `HexBattleLayout` as cell/world
authority and existing camera navigation entry points. Expose a documented
projection/picking API in the new stage file for downstream items. Wire the
graphics panel here so this item is operational on its own. Existing shared
graphics builders may be consumed unchanged; copy incompatible glue into the
new panel. Do not transplant the archived square controller or speed loop.
Record the chosen lifetime and conversion contract in the commit body.

**Risk:** A scene can look correct while every click targets a displaced hex;
also avoid orphan cameras/environments and double tone mapping.

**Validation:**
- Self-contained: add and run `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script scripts/hex_battle/restoration/probe_stage.gd -Marker HPR_STAGE_OK`; assert one active world/camera, light constants, projection round trips at centre/edges across presets and two sizes, and teardown/restart resource counts. Inspect all callers of retained render dependencies; record the caller inventory for HPR-8.
- Deferred: HPR-8 judges terrain/model light, sky, preset parity, UI sharpness and picking through the live graphics controls, including the donor/caller render sweep.

### HPR-4 — Reconnect combat events to ordered visible consequences

**Model:** Opus 5 / GPT Sol.

**Model rationale:** Simulation runs ahead of playback; attacks, multi-target
spells, status ticks and removal must preserve causal order without creating a
second scheduler or changing already-shipped effects.

**Depends on:** HPR-1, HPR-3.

**Touches:**
- `src/presentation/battle/HexBattleVisualAdapter.gd`
- `src/presentation/battle/HexBattleCombatFeedback.gd` and `.uid` (new)
- `src/presentation/battle/HexBattleDisplayState.gd` and `.uid` (new)
- `scripts/hex_battle/restoration/probe_feedback.gd` and `.uid` (new)

**End state:** Basic attacks, spell casts, damage/healing, status damage,
passive damage, defeat and withdrawal produce their existing visual feedback
once and in order. Displayed HP/status does not jump to a future simulation
state before its impact. Lethal targets remain renderable until their final
impact; withdrawn units are distinguished from dead ones. Cancellation and
queue recovery converge to authoritative state without hanging.

**Implementation brief:** Audit every `IBattleVisualAdapter` event against the
archived adapter and classify it as feedback, displayed-state update or an
intentional no-op with justification. Restore the missing subscriptions via
overrides. `VisualActionQueue` remains the action queue and `HexBattlePlayback`
the scheduling gate. Use their existing public contracts unchanged; an owned
helper may hold additional typed presentation payloads without expanding shared
action types. Capture IDs, positions, damage and post-event HP at event time.
Use a read-only presentation snapshot for what has actually been shown.

Use retained `DamageNumberBillboard`, `BattleVisualEffects`,
`SpellVfxCatalog`, `HexBattleVfxBridge` and `VfxCastContext` where compatible.
Bridge real cast events into supported catalog playback rather than invoking
`playSpell` only from probes. Deduplicate cast-area playback versus per-target
damage events. Preserve impact timing, multi-line damage, heal semantics and
event-time footprints. Do not retune any effect or shared helper. A missing
required event field or unrepresentable effect is an explicit defect, not
permission to guess geometry or silently drop it. Record the event mapping,
ordering decisions and reused-dependency caller inventory in the commit body.

**Risk:** Future-state reads erase dead models before hits, double casts play
one effect per victim, and unmanaged tweens outlive teardown.

**Validation:**
- Self-contained: `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script scripts/hex_battle/restoration/probe_feedback.gd -Marker HPR_FEEDBACK_OK`; bounded synthetic event sequences cover move/attack/lethal removal, multi-target cast, heal, status tick, passive, withdrawal, skip/recovery/dispose. Assert ordering, displayed HP, one cast carrier, final positions/removals and unchanged authoritative state. Run existing `probe_playthrough.gd` using its declared marker through `run_probe.ps1`.
- Deferred: HPR-8 observes each feedback category, impact synchronization and the full donor/effect-dependency caller sweep in rendered windows.

### HPR-5 — Restore projected status badges above units

**Model:** Opus 5 / GPT Sol.

**Model rationale:** Badge drawing already exists, but correct projection,
occlusion, overlap and event-time refresh cross the new render and playback
boundaries; copying a per-frame authoritative-state poll would be incorrect.

**Depends on:** HPR-4.

**Touches:**
- `src/presentation/battle/HexBattleVisualAdapter.gd`
- `src/presentation/battle/HexBattleUnitBadges.gd` and `.uid` (new)
- `scripts/hex_battle/restoration/probe_badges.gd` and `.uid` (new)

**End state:** Units with active effects show the predecessor's status chips,
hover-expanded icons and durations above their actual visual bounds. Effects
apply, tick and disappear when their feedback is presented. Rows follow moving
models at native resolution and disappear on removal/teardown.

**Implementation brief:** Reuse `StatusBadgeRow` and icon registries unchanged;
the archived adapter's `_refresh_status_icons`, `update_status_badges` and
decluttering helpers establish intended behavior. Integrate them through the
stage projection API and displayed-state contract from earlier items. Decide
the owned row manager's update/lifetime seam without adding a second game-state
cache. Handle camera-behind/offscreen anchors, adjacent units and HUD occlusion.
Do not invent commander icon art or replace the approved hover animation.
Record how overlap and removal are handled in the commit body.

**Risk:** Rows detached from model motion, unreadable low-resolution durations,
or badges exposing simulation updates before their queued impact.

**Validation:**
- Self-contained: `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script scripts/hex_battle/restoration/probe_badges.gd -Marker HPR_BADGES_OK`; assert apply/tick/remove and teardown counts, projection from moving model bounds, and no rows for dead/withdrawn units after playback.
- Deferred: HPR-8 checks duration legibility, hover expansion, crowded rows, offscreen handling and rotation/zoom at both resolutions and a low-resolution preset; render the unchanged donor badge behavior for comparison.

### HPR-6 — Restore tactical inspection and a truthful party HUD

**Model:** Opus 5 / GPT Sol.

**Model rationale:** Actor/target information must be restored while translating
the old individual rail to party activation; input precedence and information
density need judgment within the existing UI language.

**Depends on:** HPR-5.

**Touches:**
- `src/presentation/battle/HexBattleHud.gd`
- `src/presentation/battle/ui/HexPartyPanel.gd`
- `src/presentation/battle/ui/HexCommandMenu.gd`
- `src/presentation/battle/ui/HexInspectionPanel.gd` and `.uid` (new)
- `src/presentation/battle/ui/HexPartyOrderPanel.gd` and `.uid` (new)
- `src/systems/hex_battle/HexBattleController.gd`
- `src/systems/hex_battle/HexBattleMemberInput.gd`
- `src/systems/hex_battle/HexBattleMemberTurn.gd`
- `scripts/hex_battle/restoration/probe_inspection.gd` and `.uid` (new)

**End state:** Actor and hovered/aimed target can be inspected for identity,
team, commander/party, level, HP/max HP, combat stats, elements, effects and
resonance. Spell rows convey cost/cooldown and disabled reasons where applicable
to actual rules. Aim shows authoritative legality and the existing damage
forecast, including conditional/reactive uncertainty. The HUD exposes round,
active party, pending party order, and eligible/spent/dead/withdrawn members.

**Implementation brief:** Reuse retained Nogg window, portrait, icon and
resonance primitives unchanged. Mirror the archived actor/target readout and
hover-versus-committed-selection behavior, but obtain ordering exclusively from
`partyOrder`, `pendingPartyIDs` and current activation. Never derive ordinary
member order from speed or equate every ineligible member with spent.

Decide the smallest set of view models and panel boundaries that keeps this
information readable without covering the battlefield. Read legality from the
simulator and forecast from the existing adapter methods; do not duplicate
rules. Use displayed state for animated HP/effects and authoritative state for
command availability at the input gate. Hover must not replace committed actor
selection, cancel an aim, or erase another tactical overlay. Preserve mouse,
keyboard and gamepad paths; GUI consumption must stop click-through. Document
the information and input precedence decisions in the commit body.

**Risk:** An attractive HUD can misreport eligibility, reveal future HP, or
make commands unreachable at 720p. No invented accuracy percentages or costs.

**Validation:**
- Self-contained: `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script scripts/hex_battle/restoration/probe_inspection.gd -Marker HPR_INSPECTION_OK`; compare view models with known party/monster fixtures, verify hover does not mutate selection or battle state, conditional forecast labels, and disabled actions. Run the existing playthrough probe through its runner and declared marker.
- Deferred: HPR-8 exercises inspect/select/aim/cancel/confirm from mouse, keyboard and available gamepad, verifies actor/target readouts and all overlay layers on terrain, and judges panel placement at both sizes.

### HPR-7 — Finish the playable and watchable battle lifecycle

**Model:** Opus 5 / GPT Sol.

**Model rationale:** Pause, queued effects, CPU deliberation, result timing and
restart share ownership boundaries; a second clock or partial teardown can
silently change battle behavior despite correct buttons.

**Depends on:** HPR-2, HPR-6. Take as the next item in the HPR-6 session lane.

**Touches:**
- `src/systems/hex_battle/HexBattleController.gd`
- `src/presentation/battle/HexBattlePlayback.gd`
- `src/presentation/battle/HexBattleVisualAdapter.gd`
- `src/presentation/battle/HexBattleCombatFeedback.gd`
- `src/presentation/battle/HexBattleHud.gd`
- `src/presentation/battle/ui/HexBattleSessionPanel.gd` and `.uid` (new)
- `scripts/hex_battle/restoration/probe_session.gd` and `.uid` (new)

**End state:** Start refusals call `setupUI.showError` with useful cause text.
Pause/resume, playback speed and skip-current-animation work during CPU and
player battles. Controls show their current state and input help. Completion
waits for the final consequence, distinguishes draw from winning team, and
offers same-scenario/same-seed restart and return to setup. Repeated transitions
leave no old callbacks, models, effects or UI behind.

**Implementation brief:** Restore the predecessor's supported playback
controls using existing queue APIs and constants; do not introduce simulation
fast-forward or a second scheduling owner. Decide how the gate freezes CPU
deliberation and input while rendering UI remains responsive. Speed/skip must
reach the live VFX carriers as well as movement tweens. Keep camera/inspection
usable while paused, without admitting commands. Preserve reproducibility on
restart and handle starting another battle during queued work. Record pause,
skip, final-drain and disposal semantics in the commit body.

**Risk:** A visually paused game that still submits CPU commands, a winner
banner before the lethal impact, or callbacks into a new simulator.

**Validation:**
- Self-contained: `powershell -NoProfile -File scripts/hex_battle/run_probe.ps1 -Script scripts/hex_battle/restoration/probe_session.gd -Marker HPR_SESSION_OK`; assert paused command count is stable, resumed/skip flow drains, draw text is correct, seed/scenario survive restart, and three start/return cycles leave one set of live resources. Compare final state/command ledger for an identical scripted command sequence under normal versus altered presentation speed.
- Deferred: HPR-8 completes player and CPU battles through these controls, including pause/skip during cast, end-of-battle playback and repeated restart.

### HPR-8 — Visually accept the restored battle and close the cycle

**Model:** Opus 5 / GPT Sol, in a fresh standalone session.

**Model rationale:** Acceptance spans several owners and requires an independent
judgment of readability and parity with a rendered predecessor, not merely
passing structural assertions.

**Depends on:** HPR-1 through HPR-7.

**Touches:**
- Exact union of HPR-1 through HPR-7 Touches, for observed integration defects.
- `docs/HEX_BATTLE.md`
- `docs/ARCHITECTURE.md`
- `docs/UI_DESIGN.md`
- `docs/DEVELOPMENT.md`
- `BACKLOG_CRITICAL.md`, `BACKLOG_LONGTERM.md` (actionable residuals only)
- `docs/plans/hex-battle-playability-restoration.md` (delete on success only)

**End state:** Every deferred check above has rendered evidence and passes.
Player-vs-CPU and CPU-vs-CPU both reach a correct result with visible causal
feedback. Documentation describes the actual hex runtime and controls, and
this file is deleted in the validation commit. A failing playable/visual
criterion cannot be reclassified as backlog to close the cycle.

**Implementation brief:** Record `git rev-parse HEAD`, inspect the owned diff,
and record unrelated in-flight changes that can affect the observation. Use
the actual game through its setup and controls. Existing `probe_playthrough`
is supporting evidence, never a substitute for looking at the rendered scene.
Launch a scratch extraction of the frozen reference, following its manifest
and acceptance configuration; do not rebuild or rewrite the committed archive.

Capture comparable predecessor/current views for bodies, team bases, light,
sky, badges, actor/target windows, damage/healing and representative casts.
Compare semantics adapted to hex, not square coordinates or obsolete speed
order. Use proving-ground and hexmap scenarios at seed 42. Exercise neutral,
single and dual elements, an attack, a multi-target spell, a heal, an applied
and expired status, a passive, defeat and commander withdrawal. If shipping
scenarios do not naturally expose a category, use an owned scratch probe
fixture for that category and still complete real scenarios independently.

At 1280x720 and 1920x1080, cover initial deployment, crowded melee, camera yaw
0/90/180, zoom limits, resize, native and reduced rendering, hover, aiming,
forecast, undo-before-action, move-then-act, act-then-move, Wait, End Party,
pause/speed/skip, result, restart and return. Verify no badge/panel clipping,
click-through, black/unlit units, terrain overlap or input softlock. Verify
missing generated terrain still produces the documented playable fallback.

Render the donor and **every existing caller of each reused VFX/animation
dependency**, using the caller inventories from HPR-3/4 and the repository's
effect/debug harnesses. Compare stored goldens where present. Any existing
effect appearance, timing, playback or lifecycle change fails acceptance;
move fixes into owned hex glue, never the donor/shared dependency. No claim of
visual parity based solely on unchanged source hashes or headless rendering.

Fix defects only inside the union; rerun the relevant checks. Out-of-ownership
defects require a handoff, not an opportunistic patch. Update the owning docs
without references to disposable item IDs. Record evidence paths, checks,
actual revisions and residual limitations in the commit body. Pure proof
captures remain scratch artifacts; no sketch promotion is pre-authorized by
this plan because no new visual design is being commissioned.

**Risk:** Calling a battle restored after looking only at spawn, or accepting
an attractive static scene whose command/result flow fails.

**Validation:**
- Self-contained: rerun only changed-item probes after fixes; verify documentation paths and controls against source; focused diff and explicit-path staging audit. Earlier passing probes need not be repeated without a relevant change.
- Deferred: the consolidated rendered acceptance above; record one pass/fail result with revision and concurrent-tree context. If capture or gamepad hardware is unavailable, state exactly what remains unverified rather than claiming a pass.

## Deliberately excluded

- New monster meshes, art, sound design, lore, palette changes or spell effects.
- Reintroducing square movement, individual speed turns or a square/hex toggle.
- Championship diversity, AI training, terrain authoring and export redesign.
- New party/roster editing, campaign systems or gameplay balance.
- Changes to shared effects, rendering factories or theme contracts. A required
  shared migration needs its own complete caller inventory and ownership scope.

## Waves

| Wave | Items and suggested tier | Why disjoint / dispatch condition |
|---|---|---|
| 1 | HPR-2 — GPT Terra; exact form-validation changes | Setup UI and its new probe only; can run alongside the existing cycle |
| 2 | HPR-1 — GPT Terra; exact factory input fix. HPR-3 — GPT Sol; viewport/picking integration | After FHB-9 closes: adapter vs controller/camera/new stage; disjoint probes |
| 3 | HPR-4 — GPT Sol; event/playback causality | Adapter ownership follows HPR-1; consumes HPR-3 stage contract |
| 4 | HPR-5 — GPT Sol; projected badges and event-time updates | Sequential adapter ownership after feedback |
| 5 | HPR-6 then HPR-7 — GPT Sol, one lane; HUD/input then lifecycle integration | Commit HPR-6 before HPR-7; shared controller/HUD paths stay in one session |
| 6 | HPR-8 — GPT Sol; independent visual/playability judgment | **validation: standalone**; one consolidated gate across all implementations |
