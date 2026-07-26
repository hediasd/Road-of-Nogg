# Game Design Baseline

Status: confirmed rules and approved first-playable direction as of 2026-07-25.
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
- Facing, variable movement costs, special traversal, and manual deployment
  remain future extensions.

## Entities and elements

Entities have deterministic IDs and currently expose level, HP, ATK, DEF, SPD, MOVE, JUMP,
team, position, spell sets, passive data, and elemental affinities. Current
standard element keys are `fire`, `ice`, `wood`, `steel`, `darkness`, `light`,
`earth`, `water`, `thunder`, and `none`.

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
