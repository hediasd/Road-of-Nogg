# Implementation Plan — Live Items

Derived from the 2026-07-27 code and design audit. **Completed items are
archived in [`docs/AUDIT_COMPLETED.md`](./docs/AUDIT_COMPLETED.md)** — 24 of 27
audit items plus every Phase 4 decision are done. This file holds only what is
still open, so it stays readable in one pass.

Read [`AGENTS.md`](./AGENTS.md) and [`docs/POLICIES.md`](./docs/POLICIES.md)
before starting.

## Conventions

- **Verify** lists the checks that must pass before the item is done.
- **Risk** is the blast radius if the change is wrong.
- **Model** is the smallest model that can safely execute the item. It is a
  **gate, not a note**: if the running model is more capable than the item
  needs, say so and stop. See `AGENTS.md` § Executing a plan item.

## Running the checks

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 -Script res://tests/run_tests.gd -ScriptArgs unit -ExpectedMarker TESTS_OK -TimeoutSeconds 30 -QuitAfter 30 -LogStem tests_unit
```

Swap `unit` for `integration` or `scene` (raise the timeouts to 60). Append
`verbose` to `-ScriptArgs` to list the reference-catalog warnings, which are
otherwise reported as a count only.

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_docs.ps1
```

A check is green only when the **expected marker printed** and the **waited exit
code was 0**. `resources still in use at exit` is a known benign shutdown
warning. The `scene` tier has a known Windows output-capture defect (see
`BACKLOG_LONGTERM.md`) that makes a red `scene`/`all` run inconclusive on its
own — corroborate with `unit` and `integration`, both reliable.

**Run tests once per item, not once per edit.** See `AGENTS.md` § Running the
checks — this is the single largest avoidable cost in a session.

---

# P5-2 — Split the two oversized presentation files

`src/systems/BattlePresentationController.gd` (876 lines) and
`src/presentation/GodotVisualAdapter.gd` (793) are where new features keep
landing. Do this **before P4-2**, which adds resonance rendering to exactly
these two files.

## P5-2a — Wire the extracted visual-action queue — IN PROGRESS

`src/presentation/VisualActionQueue.gd` **already exists** (written 2026-07-28)
and is complete, but `GodotVisualAdapter` has not been changed to use it yet.
The adapter still holds its own copy of the queue logic. This item is only the
wiring.

**Fix:** In `GodotVisualAdapter`, replace the inlined queue with an owned
`VisualActionQueue`, constructed with four callables:

| Constructor argument | Adapter method to pass |
|---|---|
| `startAction` | `_start_queued_animation` |
| `finalizeAction` | `_finalize_animation` |
| `recoverState` | `_synchronize_visual_occupancy` |
| `treeProvider` | a small lambda returning `root_node.get_tree()` when `root_node` is valid, else `null` |

Then delete from the adapter: `MAX_QUEUED_ANIMATIONS`,
`ANIMATION_WATCHDOG_MARGIN`, `anim_queue`, `is_animating`, `anim_tween`,
`_active_animation`, `_animation_serial`, `_enqueue_animation`,
`_start_next_animation`, `_activate_tween`, `_complete_active_animation`, and
`_recover_animation_queue`.

Redirect the survivors:

- `_enqueue_animation(action)` call sites → `_queue.enqueue(action)`
- `_activate_tween(tween, action, d)` inside `_start_move_animation`,
  `_start_bump_animation`, `_start_defeat_animation` → `_queue.activate(...)`
- `isAnimationBusy()` → `_queue.isBusy()`
- `activeAnimationKind()` → `_queue.activeActionKind()`
- `queuedAnimationCount()` → `_queue.queuedCount()`
- `dispose()` → call `_queue.dispose()` in place of the queue-clearing lines,
  keeping every other line of `dispose()` as it is
- `_disposed` stays on the adapter **only** if something outside the queue reads
  it; check before deleting it

The `animation_queue_drained` signal must keep working. Re-emit it from the
adapter by connecting `VisualActionQueue.drained` in `_init`, so external
listeners are unaffected.

**Do not change any behaviour.** The queue class was written to preserve every
invariant exactly: single active action, exactly-once completion via the serial
guard, watchdog recovery, overflow recovery, and no scheduling after disposal.

**Files:** `src/presentation/GodotVisualAdapter.gd`

**Verify:** `unit` and `integration` must stay green. `scene` is the tier that
would actually exercise this and is unreliable on this host — run it, and treat
a red result as inconclusive rather than as proof either way. Then launch a real
battle and confirm movement, attacks, spell casts, and defeats all animate.

**Risk:** Medium. Cross-layer, and the tier that would catch a regression is the
unreliable one. Manual confirmation in a real battle is not optional here.

**Model:** Sonnet 5. The architectural decision is already made and the class is
already written; this is a mechanical redirection against a stated end state.

## P5-2b — Extract the player-turn state machine

`BattlePresentationController.gd` mixes the player state machine
(`UNIT_SELECTED → MOVE_PREVIEW → ACTION_MENU → TARGETING → CONFIRM`, per
`ARCHITECTURE.md`) with scene lifecycle, input routing, pacing, and adapter
wiring. Extract the state machine into its own class.

**Files:** `src/systems/BattlePresentationController.gd`, new class alongside it

**Verify:** as P5-2a, plus a manual player-vs-CPU turn end to end.

**Risk:** Medium-high — this is the interactive path, and it has the least
automated coverage of anything in the repo.

**Model:** Opus 5. Unlike P5-2a the seam is not yet drawn; deciding what the
state machine owns versus what stays with the controller is the actual work.

---

# P4-2 — Minimal Resonance and critical UI

Nothing in `src/presentation/` references resonance or criticals, so players
cannot see charge state and crit/weakness hits look identical to normal ones.
`resonance_changed` reaches adapters (P2-1) and `ConsoleVisualAdapter` logs it,
so the data is available — only the 3D presentation is missing.

Decision taken: **build it now, minimally.** Do this **after P5-2a**.

**Fix:** Extend the existing `StatusEffectIcons` badge row with a small charge
indicator, following that file's existing construction and anchoring pattern
rather than inventing a second one.

1. `GodotVisualAdapter._on_resonance_changed(monsterID, element, oldCharge, newCharge, reason)` — currently the inherited no-op — should refresh the badge row for that monster.
2. Show the **highest** charged element and its charge (0-3), matching the rule
   in `GAME_DESIGN.md` that the highest bar is what grants the ATK/DEF bonus.
   Charge 0 shows nothing.
3. Tint by element using `BattleMeshFactoryScript.elementColor()`, which already
   maps every element to a colour.
4. Criticals: `monster_cast_spell`'s `damageLines` entries already carry
   `critical` and `weakness` booleans, and `_on_monster_attacked` has the damage
   figure. Distinguish a crit in the right-hand UI text at minimum.

**Now genuinely reachable:** P4-3 landed the first complete Wood ladder, so
`Walker of the Woods` can actually climb to charge 3 and show every state. Use
it to check the display by hand — this was untestable before 2026-07-28.

**Files:** `src/presentation/GodotVisualAdapter.gd`,
`src/presentation/StatusEffectIcons.gd`

**Verify:** `unit`, then a real battle with `Walker of the Woods` deployed,
casting `Gather → Thornlash → Bramble Crown → Roses at Summers End` and
confirming the indicator tracks 0→1→2→3→0.

**Risk:** Low. Additive presentation; no simulation code changes.

**Model:** Sonnet 5. The design decision is made and the data path already
exists.

**Note:** a dedicated element-coloured charge bar under the HP bar, plus
crit/weakness damage-number styling, remains the richer option. It was
explicitly deferred, not rejected — record it in `BACKLOG_LONGTERM.md` if this
minimal version proves insufficient in play.

---

# Backlogged

- **Scene-tier output capture** — `tests/scene/test_capsule_features.gd` loses
  its success marker on this Windows host even when every assertion passes, and
  takes the other three scene tests' output down with it because the tier shares
  one Godot process. Moved to `BACKLOG_LONGTERM.md` by decision on 2026-07-28.
  Containment (isolating that one test in its own process) is the worthwhile
  half and is Sonnet-tier; root-causing is Opus-tier with an uncertain payoff
  and is not recommended.
- **Growth values** — every `*_GROWTH` is 0 and no production code spawns a
  monster above level 1. Blocked on deciding where level comes from, which is a
  product question rather than a balance table.
- **`Kickatoo` has `MOVE = 8`** — the sole authored-roster outlier, next highest
  is 5. Never confirmed as intentional. Plausible as a high-mobility scout,
  plausible as a typo for 5.
- **`Purple Dungeon Slime`'s description claims "immune to physical crits"** —
  no such mechanic exists. Now that Luck is live (P4-4) this is a visible
  inconsistency rather than a dormant one. Either implement the immunity or
  reword the description.

---

# Preventing future drift

The audit's core finding was a gap between documented and executing behaviour.
Four mechanical guards, in order of value:

1. **Event-contract check** (P3-6) — the `BattleEvents` / `IBattleVisualAdapter`
   rule cannot be skipped silently.
2. **Single validator** (P2-3) — a check script and the runtime cannot disagree
   about catalog truth.
3. **Tier contract enforcement** (P4-3) — Levels 2-4 now have validator-enforced
   shape rules, as Level 1 always did, so the spell ladder cannot drift as it is
   extended to the remaining nine elements.
4. **Implementation-status table** (P2-4) — the honest fallback for mechanics
   that are designed but not yet reachable.

Rule for `docs/POLICIES.md`: a mechanic may only appear in `GAME_DESIGN.md` as a
confirmed rule when a check exercises it end to end on real catalog data.
Otherwise it belongs in the status table as `designed, not yet live`.
