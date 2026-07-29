# Implementation Plan

Consolidated from `AUDIT_REMEDIATION_PLAN.md` and `PHASE4_DECISIONS.md` on
2026-07-29, when both were deleted along with `docs/AUDIT_COMPLETED.md`,
`docs/CAPSULE_MONSTERS_PLAN.md`, `docs/PLAYABLE_BATTLE_PLAN.md`, and
`docs/archive/BATTLE_RUNTIME_MIGRATION.md` as completed/superseded planning
documents. This file holds only what was still genuinely open at that point,
cross-checked against `docs/AUDIT_COMPLETED.md`'s resolution log so nothing
already-decided carried forward by mistake. Several `PHASE4_DECISIONS.md`
proposals (legacy roster promotion, race matchup rebalance, LUCK values,
Petrify's cooldown, guard/focus duration) were already decided and implemented
before deletion and are not repeated here.

There is no automated test suite in this repository right now (see
`docs/DEVELOPMENT.md`). Every item below must be verified manually by
launching the game and exercising the affected behavior.

## Conventions

- **Verify** lists what must be manually exercised before the item is done.
- **Risk** is the blast radius if the change is wrong.
- **Model** is the smallest model that can safely execute the item.

---

## P5-2b — Extract the player-turn state machine

`src/systems/BattlePresentationController.gd` mixes the player state machine
(`UNIT_SELECTED -> MOVE_PREVIEW -> ACTION_MENU -> TARGETING -> CONFIRM`, per
`docs/ARCHITECTURE.md`) with scene lifecycle, input routing, pacing, and
adapter wiring. Extract the state machine into its own class.

A related file, `src/presentation/GodotVisualAdapter.gd`, was already split
out via its own `VisualActionQueue` extraction; this item is the matching
extraction on the controller side.

**Outstanding from the adapter extraction:** manual in-game confirmation that
movement, attacks, spell casts, and defeats still animate correctly in a real
battle was never performed (no native GUI automation was available in the
session that did that extraction). Do this check before or alongside P5-2b,
since both touch the same presentation surface.

**Files:** `src/systems/BattlePresentationController.gd`, new class alongside it

**Verify:** Manually play a full CPU vs CPU battle and a Player vs CPU battle,
confirming movement, action menu, targeting, confirm/cancel, wait, and
end-turn all behave identically to before the extraction, plus the
outstanding animation confirmation above.

**Risk:** Medium-high — this is the interactive path, and there is no
automated coverage for it at all right now.

**Model:** Opus 5. The seam is not yet drawn; deciding what the state machine
owns versus what stays with the controller is the actual work.

---

## P4-2 — Minimal Resonance and critical UI

Nothing in `src/presentation/` references Resonance or criticals, so players
cannot see charge state, and crit/weakness hits look identical to normal ones.
`resonance_changed` reaches adapters and `ConsoleVisualAdapter` logs it, so the
data is available — only the 3D presentation is missing. Decision already
taken (recorded in the deleted `AUDIT_REMEDIATION_PLAN.md`): build it now,
minimally, by extending the existing `StatusEffectIcons` badge row rather than
inventing a new display.

1. `GodotVisualAdapter._on_resonance_changed(monsterID, element, oldCharge, newCharge, reason)`
   — currently the inherited no-op — should refresh the badge row for that
   monster.
2. Show the **highest** charged element and its charge (0-3), matching the
   rule in `GAME_DESIGN.md` that the highest bar grants the ATK/DEF bonus.
   Charge 0 shows nothing.
3. Tint by element using `BattleMeshFactoryScript.elementColor()`, which
   already maps every element to a colour.
4. Criticals: `monster_cast_spell`'s `damageLines` entries already carry
   `critical` and `weakness` booleans, and `_on_monster_attacked` has the
   damage figure. Distinguish a crit in the right-hand UI text at minimum.

`Walker of the Woods` has the only complete Wood ladder (`Gather` -> `Thornlash`
-> `Bramble Crown` -> `Roses at Summers End`), so it is the one monster that
can currently reach charge 3 and exercise every display state.

**Files:** `src/presentation/GodotVisualAdapter.gd`,
`src/presentation/StatusEffectIcons.gd`

**Verify:** A real battle with `Walker of the Woods` deployed, casting through
its full spell ladder and confirming the indicator tracks 0->1->2->3->0.

**Risk:** Low. Additive presentation; no simulation code changes.

**Model:** Sonnet 5. The design decision is made and the data path already
exists.

**Note:** a dedicated element-coloured charge bar under the HP bar, plus
crit/weakness damage-number styling, remains a richer option, explicitly
deferred rather than rejected. Reconsider if the minimal version proves
insufficient in play.

---

## Author the Level 2-4 spell pool for the remaining nine elements

Wood is the only element with a complete Level 1-4 ladder (piloted first to
validate the ladder end to end before committing further). The other nine
elements (fire, ice, water, darkness, earth, steel, thunder, light, wind) stop
at Level 1, so Resonance can never exceed charge 1 for any monster that isn't
Wood-affiliated.

The tier design contract that was an open question when the pilot started is
now settled and documented in `docs/GAME_DESIGN.md` under "Tier contract":

| Level | Role | Required shape |
|---|---|---|
| 1 | Setup | Targets the caster at range 0. Self-centred AOE allowed when explicitly defined. |
| 2 | Engage | Single-target, range 1 or greater. |
| 3 | Commit | Area spell, cooldown 3 or greater. |
| 4 | Ascension | Area spell, radius 2 or greater, cooldown 6 or greater. Requires three charge and empties the bar. |

Remaining work is repeatable authoring against this contract: author L2/L3/L4
spells per element, assign a complete vertical set to a monster with the right
element(s), and verify the ladder in real play.

**Files:** `data/monsters.json`, `src/factories/SpellReferences.gd`

**Verify:** Manually play a battle with the newly-completed element's monster
and confirm the ladder advances 0->1->2->3->0 as designed.

**Risk:** Medium — content/balance work without automated catalog validation
right now (see `docs/MONSTER_CATALOG_SCHEMA.md`), so a malformed spell set
will only surface at runtime.

**Model:** Sonnet 5 per element, given the contract above is fixed. Flag any
case that seems to need a contract exception rather than resolving it
unilaterally.

---

## Growth values — blocked on a prerequisite

Every monster's `HP_GROWTH`/`ATK_GROWTH`/`DEF_GROWTH` is `0`, and no
production code ever spawns a monster above level 1 — `BattleSetupFactory`
calls `spawnMonster(name, team, pos)` with the default `level = 1`. Growth
values are doubly inert: even non-zero growth would change nothing until
something varies level.

**Recommendation: keep deferring** until there's a reason for level to vary
(campaign progression, a level control in setup, or an ascension system).
Assigning growth numbers now would be unverifiable and untestable.

**Blocking decision needed from the user:** where does monster level come
from? This is a product question, not a balance table, and nothing below it
can proceed without an answer.

---

## Kickatoo's MOVE = 8 — unconfirmed outlier

`Kickatoo` is the sole authored-roster outlier at `MOVE = 8`; the next highest
is 5. Never confirmed as intentional — plausible as a deliberate
high-mobility scout, plausible as a typo for 5.

**Blocking decision needed from the user:** intentional, or should it be
corrected to 5 (or some other value)?

**Files:** `data/monsters.json`

**Risk:** Low — a single data value.

**Model:** Haiku 4.5, once the value is confirmed.

---

## Purple Dungeon Slime's description is inconsistent with implemented mechanics

`Purple Dungeon Slime`'s description claims "immune to physical crits," but no
such immunity mechanic exists anywhere in the codebase. This was a dormant
inconsistency before Luck/criticals went live; now that critical hits are
live, it is a visible one.

**Blocking decision needed from the user:** implement the immunity as a real
mechanic, or reword the description to match actual behavior?

**Files:** `data/monsters.json`, and `src/battle_sim/CombatResolver.gd` only if
the immunity option is chosen.

**Risk:** Low if reworded; Medium if implemented as a new mechanic (touches
crit resolution).

**Model:** Haiku 4.5 for a reword; Sonnet 5 if implementing real immunity.
