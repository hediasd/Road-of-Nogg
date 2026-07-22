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

## Board
- Square grid (default 8×8 for testing).
- All tiles uniform for now.
- Future tile types: mud (slows movement), high ground (bonus), water, etc.

## Teams
- Team 1: Player-controlled (later; AI-controlled for testing).
- Team 2: Computer-controlled.
- Each entity has a "brain" (AI module) that decides actions.

## Entities
- Identified by unique ID.
- Stats: HP, ATK, DEF, SPD, MOVE.
- Can have multiple spell sets (loadouts).

## References & Inspiration
- See [tactical_rpg_turn_systems.md](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/tactical_rpg_turn_systems.md) for a detailed comparative study of turn paradigms, speed sorting, CT/WT systems, and action economy across Fire Emblem, Final Fantasy Tactics, Hoshigami, Tactics Ogre, Disgaea, and more.

---

*Last updated: 2026-07-20*
