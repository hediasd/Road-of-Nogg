# Audit Remediation — Completed Items

Archive of items from the 2026-07-27 code and design audit that are done and
verified. Split out of [`AUDIT_REMEDIATION_PLAN.md`](../AUDIT_REMEDIATION_PLAN.md)
on 2026-07-28 so the live plan stays short enough to read in one pass.

Nothing here is actionable. It exists so a later session can find out *why* a
decision was made without re-deriving it.

---

## Phase 1 — Correctness (all DONE 2026-07-27)

| Item | Issue | Resolution |
|---|---|---|
| **P1-1** | `ON_DEATH` passives never fired for most deaths — two competing `_handleDefeat` implementations | `PassiveSkillResolver.handleDefeat()` is now the single path for every kill source (direct damage, status ticks, retaliation, death-chain AOE), with a `_resolvingDeaths` re-entrancy guard. `CombatResolver._handleDefeat` deleted. |
| **P1-2** | Healing spells silently dropped `INFLICTS_STATUS`/`BUFFS_ATK` payloads | `applySpellEffects()` restructured so the heal/revert/damage branch governs only the HP change; every payload runs on one shared path afterward. |
| **P1-3** | On an AOE, only the first target saw the `focus`/`guard` multiplier | Split into `consumeCasterDamageEffects` (once per cast) and `consumeTargetDamageEffects` (per damaged target). The plan originally said "call it once", which would have been wrong for `guard`. |
| **P1-4** | Re-applying a stronger ATK buff kept the weaker one | `BattleState.addEffect()` takes an `effectData` dictionary; `_mergedEffectValue()` keeps whichever numeric value has greater `absf()` while preserving sign, so `spd_bonus -3` correctly beats `-1`. |
| **P1-5** | `spd_debuff` applied twice, second time at a hardcoded duration `99` | `_applySpeedDebuff` deleted; `Timeoff` expresses the debuff as data in `EFFECTS`. |
| **P1-6** | `move_buff` gave the CPU no extra reach | `MovementResolver.getEffectiveMove()` made public and used for `findPath`'s `maxSteps`. |
| **P1-7** | Spell LoS preview disagreed with validation | `canSpellReachPositionFrom` passes the real occupant ID to `_hasLoS`. **Note:** the stated root cause was wrong — `LineOfSight.hasLoS()` never tests endpoints, so the target could not have blocked itself. The fix is still correct and harmless. Recorded in `LEARNINGS.md`. |
| **P1-8** | Every `Spell` shared one `damage_lines` array with the static catalog | `.duplicate(true)` on assignment. Also fixed `name`'s integer `1` default. |
| **P1-9** | Revert event hardcoded the spell name `"Ages Ago"` | Uses `spell.name`. |
| **P1-10** | `ASCENDS_FROM` validation was order-dependent | Two-pass name collection. |

## Phase 2 — Doc/code cohesion (all DONE 2026-07-27)

- **P2-1** — `resonance_changed` now reaches adapters; `ConsoleVisualAdapter`
  logs it. The orphaned `monster_damaged` signal was deleted rather than given
  an emitter (zero emit sites existed; damage already reaches adapters through
  three other signals).
- **P2-2** — `src/factories/StatusEffectReferences.gd` replaces the hardcoded
  `match` statements and the cleanse allow-list that had omitted `poison`.
  `cleanse`/`cooldown_reduction` stay an explicit `META_EFFECT_NAMES` list in the
  validator: `_applyDeclaredEffects` intercepts them before any status effect is
  created, so they are meta-effects, not catalog entries.
- **P2-3** — `src/factories/CatalogValidator.gd` is the single authoritative
  monster validator. Verified the disagreement bug is closed by planting a
  wood-only monster holding a darkness spell and confirming all three call sites
  reported the identical error.
- **P2-4** — `docs/GAME_DESIGN.md` gained the implementation-status table.

## Phase 3 — Test restructure (all DONE 2026-07-27)

Every root `run_*_check.gd` and the three unrunnable GUT suites became one test
case per file under `tests/{unit,integration,scene}/`, behind the single entry
point `tests/run_tests.gd`, enforced by git hooks in `scripts/hooks/`.

- **P3-1** — `TestCase.gd` (accumulating assertions, `makeMonster`/`makeSimulator`
  fixtures) and `TestRunner.gd` (sorted discovery, naming and placement
  enforcement).
- **P3-2** — hooks via `core.hooksPath`; `pre-commit` runs `unit`, `pre-push`
  runs every tier; both skip cleanly when the Godot binary is absent.
- **P3-3 / P3-4** — migration and the split of `run_resonance_check.gd` into
  one-behaviour files.
- **P3-5** — a named regression test per Phase 1 fix.
- **P3-6** — `test_event_contract.gd` reflects over
  `BattleEvents.get_script().get_script_signal_list()` and asserts every signal
  has a symmetrically connected `IBattleVisualAdapter` handler. Using the plain
  `get_signal_list()` was a real trap: it also returns inherited engine signals.

## Phase 4 — Content and balance (DONE 2026-07-28, decisions by Henri)

Decisions were taken against the proposals in
[`PHASE4_DECISIONS.md`](../PHASE4_DECISIONS.md).

- **P4-1** — `Walker of the Woods` gained `wind` so it can cast `Stroll`.
- **P4-3** — *Pilot one element end to end.* Wood chosen. Authored `Thornlash`
  (L2), `Bramble Crown` (L3), and `Roses at Summers End` (L4), assigned as a
  complete vertical set to `Walker of the Woods` alongside the existing `Gather`
  (L1). **This is the first time Resonance can exceed one charge in normal
  play**, which makes the +20%/+30% tiers and Level 4 depletion reachable.
  The tier contract is now enforced mechanically in
  `tests/integration/test_reference_catalog.gd`, the way Level 1's convention
  always was — verified by temporarily making `Thornlash` an area spell at
  range 0 and confirming both tier-2 guards fired.
- **P4-4 (Luck only)** — *Luck as an archetype signature.* 19 monsters given
  Luck, ceiling 10 (=10%, under the engine's 15% cap); assassins and glass
  cannons high, bruisers/walls/dedicated support pinned at 0. The temporary
  dormancy guard was replaced by
  `test_roster_luck_matches_archetypes.gd`, which holds the archetype contract
  permanently instead of holding the mechanic shut.
  **Growth values remain deferred** — every `*_GROWTH` is still 0 and no
  production code spawns a monster above level 1, so any value assigned now
  would be unverifiable.
- **P4-5** — *Targeted patch.* Nine entries swapped. Every element now nets
  −2..+2 (was thunder +6, wind −5). Ring-based restructuring was not adopted.
- **P4-6 + P4-9 + P4-10** — *Promote the legacy roster.* All 13 race-less
  monsters received races, families, and stats on the authored curve. Two new
  races were added for coverage: **Frostkin** (ice/water) and **Stormborn**
  (thunder/wind). The sub-curve outliers were raised to the roster floor of 28
  HP (`Dump` 1→28, `Magemornus` 8→28, `Defaultgon` 10→30), which closes P4-10's
  60x HP spread. The default preset now exercises the race system.
- **P4-7** — *Add a cooldown.* `Closing of the Third Sanctuary` gained
  `COOLDOWN = 5`. Radius left at 3; the resistance-roll option was rejected
  because no save mechanic exists anywhere in the codebase.
- **P4-8** — *No change needed.* The decision (4-turn duration, `guard` consumed
  on first hit absorbed, `focus` on first hit dealt) is exactly the behavior
  already implemented and locked in by
  `tests/integration/test_level_one_spells.gd`. The catalog data was never
  lying; the audit's reading of it was.

## Phase 5

- **P5-1** — DONE 2026-07-27. `BattleCommandEvaluator` now scores
  `spell.effects`, which all 25 Level 1 self-spells rely on exclusively.
  `cleanse`/`cooldown_reduction` score conditionally against real state rather
  than a flat bonus; `inflicts_status` weights by
  `duration * (damagePerTurn + 2)` instead of a flat `+10`. Verified by a
  regression test that picks the *weaker* buff when the scoring call is removed.

---

## Expected verification drift

Determinism check outcomes changed several times, each legitimately:

| After | Result |
|---|---|
| Phase 1 fixes | `winner=1 events=604` (was `winner=2 events=541`) |
| Legacy roster promotion | `winner=1 events=506` — races now apply resistances |
| Luck introduction | `winner=1 events=512` — criticals fire, changing RNG consumption |

The determinism test compares two identical runs; it never asserts specific
values, so these shifts are correct rather than failures.
