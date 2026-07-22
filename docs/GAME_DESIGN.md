# Road of Nogg — Game Design Notes

## Genre
Turn-based Tactical RPG (TRPG), inspired by Final Fantasy Tactics, Fire Emblem, Hoshigami.

## Battle Flow
1. Battle starts with 2 teams (can eventually support more).
2. Each team has ~5 entities placed on a grid board.
3. Entities take turns based on speed (highest speed goes first).
4. On their turn, an entity can: **move first**, then **optionally act** (attack, spell, item).
5. After the entity finishes, a **TurnWheel** function:
   - Passes the turn to the next entity.
   - Any active status effects on the previous entity lose 1 turn of duration.
   - If an effect reaches 0 remaining turns, it is removed.
6. When all entities have acted in a round, a new round begins (re-sorted by speed).
7. Battle ends when all entities of one team are defeated.

## Actions
- **Move**: A* pathfinding across the board. Movement range depends on entity MOVE stat.
- **Basic Attack**: Always available. Range 1 (melee/adjacent). Uses ATK stat.
- **Spell**: Uses the entity's spell set. Each spell has range, radius, damage, element.
- **Item**: (Future) Use consumable items.
- **Wait/Defend**: (Future) End turn early, possibly with a defense bonus.

## Damage Formula
- Basic: `max(1, attacker.atk + spell.damage - target.def)`
- To be iterated on.

## Board, Terrain & Obstacles
- Square grid.
- **Clear Tiles (`TERRAIN_CLEAR`)**: Standard walkable tiles that do not block Line of Sight (LoS).
- **Hard Obstacles (`TERRAIN_OBSTACLE`)**: Things like Trees, Walls, and Pillars. These tiles cannot be walked on (unwalkable) AND they completely block Line of Sight for ranged spells.
- **Soft Obstacles (`TERRAIN_ABYSS`)**: Things like Water, Pits, or Chasms. These tiles cannot be walked on (unwalkable), but they DO NOT block Line of Sight. Units can fire ranged attacks directly over them.
- Future additions may include move-cost modifiers (e.g. mud) and elevation (e.g. high ground).

## Teams
- Team 1: Player-controlled (later; AI-controlled for testing).
- Team 2: Computer-controlled.
- Each entity has a "brain" (AI module) that decides actions.

## Entities
- Identified by unique ID.
- Stats: HP, ATK, DEF, SPD, MOVE.
- Can have multiple spell sets (loadouts).

## References & Inspiration
- See [tactical_rpg_turn_systems.md](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/tactical_rpg_turn_systems.md) for a detailed comparative study of turn paradigms, speed sorting, CT/WT systems, and action economy across Fire Emblem, Final Fantasy Tactics, Hoshigami, Tactics Ogre, Disgaea, and more.

---

## Future Scalability & Engine Architecture
To ensure the engine can support advanced future features, the architectural foundation strictly follows these constraints:
- **Pure Logic Decoupling**: The battle engine (BattleSimulator, BattleState, and Resolvers) has zero dependencies on Godot's `Node` tree or visual representation, operating purely on data structures.
- **Serialization (Savestates)**: All `BattleState` data (including logs, effect durations, and stats) must be strictly serializable (e.g., to JSON). This guarantees that we can implement suspend-saves, replay viewers, and mid-battle reloading flawlessly in the future.
- **Input Abstraction**: Instead of hardcoding AI execution, `BattleSimulator.executeTurn()` queries an abstracted `Brain` interface. In the future, we will swap `EntityBrain` out with a `PlayerInputBrain` to allow real players to control teams, and a `NetworkBrain` to support PvP over the internet using deterministic input syncing.

*Last updated: 2026-07-22*
