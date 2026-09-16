# Battle action pacing

Opened 2026-09-13. This cycle gives the hex battle a readable handoff between
movement and combat without introducing the broader battle-director system.
It changes presentation timing only; simulation order, gameplay state, authored
VFX timing, camera direction, and existing unit presentation remain unchanged.

## Outcome

At normal playback speed, movement is legible, reaches its destination, settles,
and only then yields to an attack or spell. A strike or defeat also finishes with
a short recovery before the next queued visual action begins. Pause, speed changes,
skip, recovery, and watchdog completion continue to treat each paced sequence as
one action.

## Present-state facts an executing agent must not "fix"

- The queue is already FIFO and runs only one tween at a time. The defect is the
  absence of authored transition time, not concurrent animation ownership.
- The live adapter's `MOVE_STEP_SECONDS` remains `0.16`; movement pacing is applied
  at the queue boundary because that path is currently owned by another active
  item.
- Cast VFX keep their authored durations and hold fractions. This first pass does
  not retime effects or insert a pause between a cast carrier and each target hit.

## Items

### PAC-1 — Add movement settle and combat recovery to the visual queue

**Model:** Opus 5 / GPT Sol

**Model rationale:** The code change is compact, but the queue is the shared
completion boundary for movement, combat feedback, pause, speed, skip, and watchdog
recovery. The implementation must choose one ownership point that preserves all of
those contracts and avoids multiplying delays across instant status updates.

**Depends on:** None.

**Touches:**
- `src/presentation/VisualActionQueue.gd`
- `scripts/hex_battle/restoration/probe_action_pacing.gd` and generated `.uid`
- `docs/UI_DESIGN.md`

**End state:** At 1x presentation speed, a movement tween runs at 75% of its former
speed and holds for 0.18 seconds after reaching its destination. `BUMP` actions hold
for 0.16 seconds after their existing feedback, and `DEFEAT` actions hold for 0.20
seconds. These intervals scale with the action tween, freeze under pause, disappear
under skip, and are included in watchdog duration. `FOCUS`, `MESSAGE`, and
`CAST_AREA` receive no automatic tail interval.

**Implementation:** Decide how `VisualActionQueue.activate()` should extend the
owner-created tween while preserving the duration units callers already provide.
Keep all pacing presentation-only. Record why the queue owns this first pass and
why cast/message actions are excluded in the commit body.

**Risk:** Incorrect duration conversion can make the watchdog cut off slow movement,
or can make high playback speeds retain full-length pauses. Applying recovery to
instant display actions would accumulate large delays on area spells.

**Validation:**
- Self-contained: run `powershell -ExecutionPolicy Bypass -File scripts/hex_battle/run_probe.ps1 -Script res://scripts/hex_battle/restoration/probe_action_pacing.gd -Marker HPR_ACTION_PACING_OK`; run the existing queue-pause probe and the non-interactive Godot code check from `AGENTS.md`; inspect the focused diff and run `git diff --check`.
- Deferred: user plays a move-then-attack sequence at 1x and judges that movement, settlement, contact, recovery, and the next action read as distinct beats without feeling sluggish.

### PAC-V — Validate pacing in the interactive battle

**Model:** Opus 5 / GPT Sol

**Model rationale:** Acceptance is a timing and feel judgement in the real battle,
and tuning one interval affects movement, attacks, defeats, and the perceived speed
of party activation. It needs the user's observation rather than another mechanical
probe.

**Depends on:** PAC-1.

**Touches:**
- `src/presentation/VisualActionQueue.gd`
- `docs/UI_DESIGN.md`
- `docs/plans/battle-action-pacing.md` (delete on successful closure)

**End state:** The user accepts the normal-speed move-to-attack handoff and ordinary
combat recovery in the interactive hex battle. Any tuning correction is committed
with the validation evidence, and this cycle file is removed.

**Implementation:** Exercise a short move followed by a basic attack, a stationary
basic attack followed by another action, a lethal hit, pause/resume during the
settle, 2x playback, and skip during movement. Tune only the three pacing values.

**Risk:** A value that reads well for a one-cell move may drag on a long route or
become imperceptible at 2x.

**Validation:**
- Deferred: consolidated interactive acceptance of the sequence above.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | PAC-1 | implementation and self-contained timing proof |
| 2 | PAC-V | standalone user judgement and cycle closure |

## Deliberately excluded

Camera direction, sound, animation replacement, cast-profile retiming, action
grouping, critical/weakness emphasis, and other battle-director features are outside
this first pacing pass.
