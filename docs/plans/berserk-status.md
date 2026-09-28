# Berserk Status

2026-09-28. The user asked for Summit Fever, a Level 3 fire/ice spell that
"debuffs the target into a berserk state", and chose what berserk means: the
target **loses control**. For a few turns it acts on its own, charging and
attacking the nearest unit, friend or foe, the way the aggressive BerserkBrain
AI plays. Nothing like this exists: statuses today only shift stats or deal
damage over time, a basic attack cannot target an ally, and the player chooses
every action for their own units. This cycle builds that mechanic and then the
spell that applies it. It is not a stat buff or debuff (the user explicitly
chose loss of control over "attack up, defence down") and not new VFX.

This is a **single-session cycle**: the rules decisions in BERSERK-1 decide
which presentation and input files BERSERK-3 must change, so later write sets
are not knowable in advance. Run the items one at a time in one session; there
is no wave table.

## Outcome

A unit under `berserk` cannot be commanded by its controller, player or CPU.
On its side's turn it acts by itself, deterministically, against the nearest
unit of either team, and friendly fire is legal for it alone. The state has a
duration, shows on the HUD, survives save and replay, and is removed by
cleanse. Summit Fever applies it.

## Present-state facts an executing agent must not "fix"

- `CombatResolver` refuses basic attacks on allies (`occupant.team !=
  attacker.team`). That stays the rule for everyone who is not berserk; the
  exception is scoped to the berserk unit only.
- Summit Fever is **single target** although the Level 3 tier shape in
  `docs/GAME_DESIGN.md` requires an area spell. The user chose this
  explicitly; record it as an exception, don't "correct" the spell.
- No monster is fire/ice, so Summit Fever and Heat Drift (its Level 2
  companion, already in `data/spells.json`) have no caster. That is expected
  and is not this cycle's to change.
- `BerserkBrain` is a CPU personality chosen per monster in the catalog, not
  a status. The new status may borrow its behaviour but must not change how
  existing BerserkBrain monsters play.

## Items

### BERSERK-1 — Make berserk a simulator state that takes control of its unit

**Model:** Opus 5 / GPT Sol

**Model rationale:** This crosses the simulator's core boundaries (turn and
activation flow, action legality, AI policy, status lifecycle, replay), and
several rules calls are open: whether a berserk unit may cast or only strike,
where in its side's turn it acts, and how the CPU should value inflicting it.
Each call has balance and determinism consequences that need judgement, not a
recipe.

**Depends on:** —

**Touches:**
- `data/status_effects.json`
- `src/battle_sim/**`
- `src/entity_ai/**`
- `src/entities/Monster.gd`
- `docs/GAME_DESIGN.md`
- `scripts/battle/checks/probe_berserk.gd` and its `.uid` (new)
- `scripts/checks/probes/battle.json`

**End state:** A `berserk` status exists in the status catalog, negative (so
cleanse removes it), with a default duration. While it lasts, its unit is
excluded from its controller's choices and instead takes one automatic action
on its side's turn, chosen by a deterministic policy that targets the nearest
living unit of either team. Friendly fire is legal for that unit. The state
ticks down, expires, serializes, and replays identically. The rules, including
the calls below, are written into `docs/GAME_DESIGN.md`. A registered probe
proves control loss, ally targeting, determinism, expiry and cleanse.

**Implementation:** The session decides, and records its reasoning in the
commit body:
- whether the berserk action is a basic attack only, or may also use the
  unit's spells;
- when in the side turn it acts (before the player's choices, after them, or
  when its activation comes up), and whether it spends its activation;
- tie-breaking for "nearest", which must use deterministic identity (lowest
  `uniqueID`), never `get_instance_id()` or unrouted randomness;
- how the CPU values inflicting berserk on an enemy, since the evaluator
  scores effects by their stat fields and a pure control effect scores zero
  today.

Invariants: `src/battle_sim/` and `src/entity_ai/` stay headless;
presentation learns about the state only through `BattleEvents` (add events
if needed); any randomness goes through `BattleState.rng`; existing
BerserkBrain monsters and every non-berserk unit behave exactly as before.

**Risk:** Friendly fire leaking to non-berserk units; a player side that
stalls because its only eligible unit is berserk; replay divergence. The
probe and the full battle and hex-battle sweep catch these.

**Validation:**
- Self-contained: the new probe; the battle, hex_battle, ai_rework,
  invariants and fuzz manifests, compared against a baseline taken before the
  change (this is a cross-layer code change, so the sweep is warranted).

### BERSERK-2 — Add Summit Fever

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** A catalog entry plus two doc rows, fully specified once
BERSERK-1 has fixed the effect's name and fields; nothing is left to decide.

**Depends on:** BERSERK-1.

**Touches:**
- `data/spells.json`
- `docs/lore/magic_and_relics.md`
- `docs/GAME_DESIGN.md` (Tier contract only)

**End state:** `data/spells.json` has a spell named `Summit Fever`:
`ELEMENTS` `["fire", "ice"]`, `DAMAGE_LINES` 3 fire then 3 ice,
`TARGET_TYPE` `"single"`, `RANGE` 4, `MIN_RANGE` 1, `COOLDOWN` 4,
`SEQUENCE_LEVEL` 3, `CAN_TARGET_EMPTY` true, `MAX_HEIGHT_DELTA` 1, and
`EFFECTS` with the berserk effect exactly as BERSERK-1 defined it (its name
and duration fields). No `DESC`, no `VFX` block. The Reference Register in
`docs/lore/magic_and_relics.md` gains the row
`| Summit Fever | FIRE / ICE | 3 | TBC | TBC |`. The Tier contract in
`docs/GAME_DESIGN.md` gains one sentence recording Summit Fever as a
user-approved single-target exception to the Level 3 area shape.

**Implementation:** Mirror the `Heat Drift` entry's key order and formatting.
Numbers are defaults the user has not set; change none of them. Do not touch
any other spell, monster or doc section.

**Risk:** An effect name that does not match BERSERK-1's makes the spell do
damage only; the probe below catches it.

**Validation:**
- Self-contained: `probe_spell_elements.gd` and `probe_berserk.gd` pass (the
  latter should cover a catalog spell applying berserk if BERSERK-1 wrote it
  that way; otherwise cast Summit Fever from the probe's harness).

### BERSERK-3 — Show and honour berserk in the hex battle UI

**Model:** Opus 5 / GPT Sol

**Model rationale:** Integrating an auto-acting unit into the player's side
turn touches input gating, playback ownership and HUD feedback at once, and
how the player learns their unit is out of their hands is a UX judgement,
under the UI guardrails.

**Depends on:** BERSERK-1.

**Touches:**
- `src/systems/hex_battle/**`
- `src/presentation/battle/**`
- `src/presentation/StatusEffectIcons.gd`
- `src/presentation/StatusBadgeRow.gd`
- `scripts/hex_battle/side_turn/probe_ui_guardrails.gd`
- `docs/UI_DESIGN.md`

**End state:** On a player side, a berserk unit cannot be selected or
commanded and its automatic action plays through the normal playback
without stalling the turn. Its badge and unit readout show the berserk state
and why the unit is not selectable. CPU sides play it through unchanged.
`probe_ui_guardrails.gd` covers a state with a berserk unit and passes.

**Implementation:** Presentation observes only; it never decides the berserk
action. Treat existing VFX, badges and theme tokens as a compatibility
surface: add, don't retune.

**Risk:** A player turn that never ends, a selectable berserk unit, clipped
text in the new state.

**Validation:**
- Self-contained: `probe_ui_guardrails.gd`, the hex_battle manifest.
- Deferred: launch a player-vs-CPU battle, put a player unit under berserk
  (Summit Fever or a probe hook), and observe that it acts alone, can strike
  an ally, shows its badge, and the turn ends normally.

## Validation

Folded into the BERSERK-3 session by construction (single-session cycle):
after its commit, run its deferred check against that revision and commit
the result separately.

## Deliberately excluded

- Stat changes while berserk (attack up, defence down): the user chose loss
  of control alone.
- New VFX for berserk or Summit Fever.
- A fire/ice monster to cast Heat Drift and Summit Fever.
- Changing how BerserkBrain monsters behave.
