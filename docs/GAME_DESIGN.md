# Game Design Baseline

Status: confirmed rules and approved first-playable direction as of 2026-07-26.
Creative details and balance values not recorded here still require user input.

## Battle format

- Battles use a square grid and currently support two teams.
- The first playable slice is fixed 4v4 with automatic deployment.
- Setup offers CPU vs CPU by default and Player vs CPU as the interactive mode.
  Team 1 is the player side in the first slice.
- Meadow is the default map. The animated sky background loads before the setup
  overlay so configuration never opens onto a blank scene.
- Duplicate monsters are allowed but should be discouraged by the UI.
- Seeded random team presets must be reproducible.

The detailed setup, dropdown, controller, cursor, and delivery decisions are in
[`PLAYABLE_BATTLE_PLAN.md`](./PLAYABLE_BATTLE_PLAN.md).

## Turn and victory flow

1. A round queues all living entities by speed, highest first. Equal-speed ties
   use deterministic entity ID order.
2. On a turn, an entity may move and then optionally attack, cast, or wait.
3. End-of-turn status/passive processing runs for the acting entity.
4. When the queue is empty, living entities are sorted again for a new round.
5. Battle ends when only one team has living entities.

CPU decisions and player input converge on the same validated
command contract. A controller proposes a command; the simulator validates,
executes, and records it.

## Actions

- **Move:** Orthogonal grid pathfinding, limited by MOVE.
- **Basic attack:** Always available, currently adjacent/melee and based on ATK.
- **Spell:** Uses a monster’s spell set with range, area, effect, and element.
- **Wait:** Completes a turn without an attack or spell.
- **Items and defend:** Future systems, not first-slice blockers.

The current basic damage floor is expressed as
`max(1, attacker.atk + action_power - target.def)`. Resolver-specific elemental,
passive, multi-hit, healing, and status behavior may modify the result.

## Board and terrain

- `TERRAIN_CLEAR`: walkable and does not block line of sight.
- `TERRAIN_OBSTACLE`: unwalkable and blocks line of sight.
- `TERRAIN_ABYSS`: unwalkable but does not block line of sight.
- Tile elevations are integers from 0 through 8. Cardinal movement costs one,
  and each step must remain within the acting monster's JUMP value.
- Basic melee requires cardinal adjacency and at most one elevation step.
  Spells define their own maximum height delta; bypassing LoS never bypasses it.
- Direct damage gains 10% from higher ground and loses 10% from lower ground,
  using deterministic integer rounding before target-side reductions.
- Meadow rises around its central pond, Crossroads has a raised central bridge,
  and Forest climbs toward a broad wooded center. All three profiles use
  symmetric elevation steps from 0 through 2 and remain traversable at JUMP 1.
- Facing, variable movement costs, special traversal, and manual deployment
  remain future extensions.

## Entities and elements

Entities have deterministic IDs and currently expose level, HP, ATK, DEF, SPD, MOVE, JUMP,
team, position, spell sets, passive data, and elemental affinities. Current
standard element keys are `fire`, `ice`, `wood`, `steel`, `darkness`, `light`,
`earth`, `water`, `thunder`, `wind`, and `none`.

A monster's race defines its elemental matchups. A resisted element deals 80% of
its damage and a weak element deals 120%; every other element is neutral at
100%. The multiplier applies to elemental damage only, so basic attacks are
unaffected. Race matchups are the only source of these multipliers.


### Taxonomy and Resonance

Playable monster definitions use `race -> family -> species`. Ascended entries
remain independently selectable when present and record their immediate
`ascends_from` relationship.

Each monster owns a separate Resonance bar for each of its elements. Casting a
Level 1-3 spell raises that element's bar only when the spell level equals the
current charge plus one. Other casts do not reset progress. A Level 4 spell
requires three charge and depletes that element's bar when cast.


A monster owns one to four spell sets. Each set stays on a single element and
holds at most one spell per Level from 1 through 4. A set does not have to fill
every Level: partial sets are legal, so a monster may cover any subset of the
tiers it has been authored for.

#### Tier contract

Each Level has a fixed shape, enforced by
`tests/integration/test_reference_catalog.gd` so the ladder cannot drift as it
is extended to further elements:

| Level | Role | Required shape |
|---|---|---|
| 1 | Setup | Targets the caster at range 0. Self-centred AOE allowed when explicitly defined. |
| 2 | Engage | Single-target, range 1 or greater. |
| 3 | Commit | Area spell, cooldown 3 or greater. |
| 4 | Ascension | Area spell, radius 2 or greater, cooldown 6 or greater. Requires three charge and empties the bar. |

Wood is the reference implementation and the only complete ladder today:
`Gather` → `Thornlash` → `Bramble Crown` → `Roses at Summers End`, carried by
`Walker of the Woods`. The remaining nine elements are authoring work against
this contract.
The highest charged element grants a non-stacking 10%, 20%, or 30% bonus to ATK
and DEF. A critical hit or elemental weakness removes at most one charge from the target per resolved action.

Critical hits scale with Luck: each point grants 1% critical chance, capped at 15%. A critical hit deals 1.25x damage.
When several bars tie, decay uses alphabetical element order for deterministic resolution.

### Implementation status

The rules above are the confirmed target design. Some are fully reachable
through normal play today; others are implemented and tested but cannot yet
be reached because the authored content doesn't exist. This table exists so
"documented" is never mistaken for "playable" — remove a row once its
corresponding content lands.

| Mechanic | Status | Why |
|---|---|---|
| Resonance charge to 1 (+10% ATK/DEF) | Live | Any monster with a Level 1 spell for an owned element can reach charge 1 in normal play. |
| Resonance tiers 2-3 (+20%/+30%) and Level 4 ascension | Partial | Reachable since 2026-07-28, but only through the Wood ladder on `Walker of the Woods` — the only complete Level 1-4 set in the catalog. The other nine elements still stop at charge 1. |
| Elemental weakness/critical Resonance decay | Live | Fires correctly whenever a charge exists to decay. |
| Critical hits | Live | Implemented and tested. Luck (range 2–10 across the roster) drives critical chance via `min(luck * 1%, 15%)`. |
| Level-based stat growth | Designed, not yet live | Every monster's `HP_GROWTH`/`ATK_GROWTH`/`DEF_GROWTH` is 0, **and** no production code spawns a monster above level 1, so growth values would be inert even if assigned. |
| Race elemental resistance (±20%) | Live | Every monster now has a race, including the default preset, so a default CPU vs CPU battle exercises resistances and weakness-driven Resonance decay. |
| Resonance and critical UI | Designed, not yet live | Nothing in `src/presentation/` renders charge state, and crit/weakness hits look identical to normal ones. Tracked as P4-2. |

## Scalability constraints

- Simulation is headless and separate from presentation.
- Base reference data stays immutable during battle.
- Seeds, IDs, commands, effects, and state required for replay must remain
  serializable.
- Local Player vs Player, online play, inventory, and manual deployment follow
  the first Player vs CPU slice.

Comparative research is indexed in
[`gamerefs/tactical_rpg_turn_systems.md`](../gamerefs/tactical_rpg_turn_systems.md).
It informs design but does not override confirmed Road of Nogg decisions.
