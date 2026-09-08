# Game Design Baseline

Status: confirmed rules and approved first-playable direction as of 2026-09-07.
Creative details and balance values not recorded here still require user input.

The sections labeled **current square baseline** describe the implementation
being preserved for reference. The approved hex rules are the product direction;
they remain a target until the migration is implemented and validated.

## Approved initial hex battle target

Brigandine: The Legend of Forsena is the principal reference for commander-led
troops, grouped activation, hex battle layout, and commander-driven outcomes.
Brigandine: The Legend of Runersia also informs terrain and zone of control.
These sources guide the structure; the exact Road of Nogg rules below are the
approved project contract. See the [Forsena manual](https://www.videogamemanual.com/ps1/Brigandine%20-%20The%20Legend%20of%20Forsena%20%28USA%29.pdf)
and [Runersia game-system reference](https://brigandine.happinet-games.com/gamesystem/?lang=en).

### Parties, rounds, and member turns

- A party has exactly one commander, a deterministic party ID, and zero or more
  other members. Initial test scenarios may designate existing monsters as
  commanders; the migration does not require new characters, names, classes,
  or artwork.
- Each surviving party receives one activation per round. At round start,
  parties are ordered by commander level descending, effective commander SPD
  descending, then deterministic party ID ascending. The queue is rebuilt only
  at the next round unless battle termination makes its remainder irrelevant.
- During a player party activation, the player may choose any living, eligible,
  unspent member in any order. CPU parties choose dynamically through the same
  eligibility and command rules. Each eligible member receives at most one turn
  during that activation.
- **Wait** consumes the selected member's turn. **End Party** converts every
  remaining eligible member turn into a wait in deterministic member-ID order.
  Dead or withdrawn members receive no turn and no timing tick.
- A member may move then act or act then move where the command permits it.
  Casting after movement is allowed unless the spell says otherwise. Movement
  may be undone only before an action and before any irreversible reaction or
  effect has occurred.
- Status durations, cooldowns, and end-turn passives advance once when their
  member acts, waits, is skipped, or is consumed by End Party. An effect created
  during an activation follows the same rule; one member's turn never advances
  another party member's clocks. Victory is checked after each fully resolved
  command and timing step, before another member is selected.

Free member choice removes ordinary-member SPD from turn scheduling. Commander
SPD remains a party-order tiebreaker. A later balance decision may give ordinary
member SPD another use, such as accuracy or evasion; no replacement benefit is
part of this migration.

Examples make the scheduling edge cases explicit:

- If two commanders share level and effective SPD, the lower deterministic
  party ID activates first.
- If member 12 waits, member 12 is spent while another eligible member remains
  selectable. If End Party is then chosen with members 9 and 20 eligible, their
  waits resolve in ID order: 9, then 20.
- If only one eligible member remains, that member may act or wait normally;
  resolving it ends the party activation exactly once.

### Defeat, withdrawal, and battle outcome

- Defeating an ordinary member does not end its party. Defeating a commander
  forces every surviving member of that party to withdraw; withdrawal does not
  kill those members.
- A team loses when all of its commanders are defeated or withdrawn. If one
  fully resolved effect removes every team's last commander simultaneously,
  the result is a draw.
- For example, defeating the last commander on Team 2 withdraws that
  commander's surviving members and ends the battle before another member is
  selected. If the same resolved effect also removes Team 1's last commander,
  neither side wins.

### Hex board, movement, and targeting

- The initial board permits one unit per valid flat-top hex. Occupied cells
  block both passage and stopping. Traversable terrain initially costs one
  movement point; obstacles and abyss remain blocked according to their terrain
  contracts. Integer height and JUMP limit traversal.
- The movement API is weighted even while production costs are uniform. It
  distinguishes traversal, stopping, cost, and movement termination so later
  terrain and movement types do not require replacement pathfinding.
- Zone of control is part of the first playable battle. Entering a hex adjacent
  to a living hostile unit ends the mover's movement.
- Range uses hex distance. A circle is a hex disc, and a minimum range cuts a
  ring from it. A cross is the center plus six axial rays. A line follows the
  selected axial direction and excludes the caster. Self-centered and passive
  radial effects use hex discs. Every existing area shape must receive a
  supported mapping or an explicit unsupported result; square geometry must not
  survive silently.
- Line of sight uses symmetric supercover. Intervening cells touched by the
  line can block it; source and target cells are excluded. A ray exactly on a
  cell edge or vertex includes every touched intervening cell, producing a
  conservative deterministic result rather than an angle-dependent gap.

### Presentation and deferred systems

The battlefield keeps the retro 2.5D direction with an oblique view over a
flat-top hex layout. Mouse remains the primary pointer. Keyboard and gamepad
navigation must reach all six neighbours under the camera transform. A
party/member display replaces the individual speed portrait rail.

The initial migration does not include voluntary retreat, command-radius
penalties, enclosure bonuses, allied pass-through, flying or aquatic traversal,
terrain defence/evasion, capture, resurrection, turn limits, reinforcements,
campaign consequences, or additional victory objectives. They are optional
follow-on systems rather than implied parts of the first playable.

## Current square baseline: battle format

- Battles use a square grid and currently support two teams.
- The first playable slice is fixed 4v4 with automatic deployment.
- Setup offers CPU vs CPU by default and Player vs CPU as the interactive mode.
  Team 1 is the player side in the first slice.
- Meadow is the default map. The animated sky background loads before the setup
  overlay so configuration never opens onto a blank scene.
- Duplicate monsters are allowed but should be discouraged by the UI.
- Seeded random team presets must be reproducible.

The detailed setup, dropdown, controller, and cursor contracts are in
[`ARCHITECTURE.md`](./ARCHITECTURE.md).

## Current square baseline: turn and victory flow

1. A round queues all living entities by speed, highest first. Equal-speed ties
   use deterministic entity ID order.
2. On a turn, an entity may move and then optionally attack, cast, or wait.
3. End-of-turn status/passive processing runs for the acting entity.
4. When the queue is empty, living entities are sorted again for a new round.
5. Battle ends when only one team has living entities.

CPU decisions and player input converge on the same validated
command contract. A controller proposes a command; the simulator validates,
executes, and records it.

## Current square baseline: actions

- **Move:** Orthogonal grid pathfinding, limited by MOVE.
- **Basic attack:** Always available, currently adjacent/melee and based on ATK.
- **Spell:** Uses a monster’s spell set with range, area, effect, and element.
- **Wait:** Completes a turn without an attack or spell.
- **Items and defend:** Future systems, not first-slice blockers.

The current basic damage floor is expressed as
`max(1, attacker.atk + action_power - target.def)`. Resolver-specific elemental,
passive, multi-hit, healing, and status behavior may modify the result.

## Current square baseline: board and terrain

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

Each Level has a fixed shape so the ladder does not drift as it is extended to
further elements. This is currently a design contract only — there is no
automated check enforcing it (see [`MONSTER_CATALOG_SCHEMA.md`](./MONSTER_CATALOG_SCHEMA.md)):

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
| Resonance charge UI | Live | Docked status windows show each owned element's catalog code and a three-cell charge bar. In-world critical and weakness feedback remains deferred. |

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
