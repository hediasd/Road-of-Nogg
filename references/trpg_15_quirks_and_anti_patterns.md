# TRPG Quirks & Anti-Patterns

## 1. Introduction
This document collects unique, unintended, or poorly scaling mechanics observed in classic Turn-Based and Tactical RPGs. By identifying these "quirks," we can decide whether to embrace them as nostalgic features (like buff spells dealing 1 damage) or avoid them as design flaws (like infinite grind loops).

## 2. Quirks by Game

### 2.1 Final Fantasy Tactics (PS1)
- **The "Accumulate" Grind**: JP (Job Points) were awarded per action taken, not per enemy defeated. This led to a meta where players would leave one enemy alive, surround it, and endlessly cast "Accumulate" (Focus) or hit their own teammates to max out job levels in the first battle.
- **Calculator Math Breaks**: The Arithmetician (Calculator) class could target the entire map instantly without MP by finding mathematical overlaps (e.g., CT multiple of 5 + Holy). It completely broke the action economy and rendering the game trivial.
- **Zodiac Compatibility**: Highly opaque. Characters dealt drastically different damage or had wildly different success rates on spells based on astrological signs, often forcing players to consult out-of-game charts to understand why an attack missed.

### 2.2 Tactics Ogre (Various Versions)
- **Friendly Fire Training**: Similar to FFT, units gained experience per action. Players frequently abused this by having healers perpetually heal allies who were attacking each other to grind levels safely.
- **The Archer High Ground**: Bow range extended downwards infinitely. An archer on the highest peak could hit the entire map, rendering melee units obsolete on maps with steep verticality.

### 2.3 Fire Emblem (GBA Era)
- **Boss Abuse**: Bosses on Thrones healed every turn. Players would park a low-strength unit next to the boss, hitting them for minimal damage over hundreds of turns just to farm Weapon EXP and level up weak units.
- **True Hit vs. Displayed Hit**: The game rolled 2 RNs (Random Numbers) and averaged them. This meant a displayed 90% hit rate was actually 98%, and a 20% hit rate was actually 8%. This made reliable attacks feel mathematically perfect, but completely hid the actual math from the player.

### 2.4 Ragnarok Online
- **The 1-Damage Buff/Debuff**: Many supportive or utility spells in the older engine inherently required a "hit" state to apply their effect. As a result, casting a buff or a hex might deal 1 point of base damage because the damage formula couldn't process an offensive spell type as 0.

### 2.5 Panzer Dragoon Saga
- **Constant 360-Degree Kiting**: The optimal way to play often devolves into endlessly spinning the camera around the enemy to stay in the "Safe Zone" while waiting for gauges to fill, which can make some encounters feel like a dizzying merry-go-round rather than a tactical duel.

### 2.6 Sakura Wars
- **Dating Sim as Combat Prep**: Your performance in visual novel dialogue choices (LIPS) directly and strictly dictates your stats in the TRPG grid combat. Failing to flirt or respond correctly to a heroine in the downtime means her mech is significantly weaker on the battlefield, completely bypassing traditional RPG leveling.

## 3. Systemic Limitations & AI Edge Cases

### 3.1 Infinite Loops and Action Stagnation
High-level architecture governing how the battle engine prevents combat from deadlocking when units are incapable of harming one another.
- **The "Loop Detector" Pattern (e.g. Early Access / Roguelike TRPGs)**
  - *Architecture:* The battle orchestrator tracks the number of meaningful actions taken each round (e.g., attacks, spells, or movements).
  - *Execution:* If a complete round passes (all units cycle their turns) and the aggregate action count is 0, the game detects an infinite loop and forcefully terminates the battle (often declaring a draw or victory to the defending team).
  - *Use Case:* Used primarily in fully automated combat (auto-battlers) or AI testing simulations to prevent the engine from freezing.

- **The Hard Turn Limit (e.g. Fire Emblem Heroes, Langrisser Mobile)**
  - *Architecture:* Battles have a globally enforced maximum round count (e.g., 15, 30, or 50 rounds).
  - *Execution:* If the battle is not resolved before the round counter expires, the match immediately ends. The win condition is typically evaluated based on total remaining HP, number of surviving units, or defaults to a Defender Victory.
  - *Use Case:* Ensures PvP and PvE matches do not drag on indefinitely due to overly defensive AI or unreachable terrain.

### 3.2 Pathfinding Deadlocks (The "Traffic Jam")
How pathfinding algorithms handle scenarios where a unit's optimal destination is occupied, or the only path forward is blocked by allies.
- **Partial Path Execution (e.g. Final Fantasy Tactics)**
  - *Architecture:* If a unit's absolute target tile is unreachable or occupied, the AI calculates a full path, but truncates it to their maximum movement range and stopping just before the obstacle.
  - *Execution:* Even if the destination is completely walled off by allies, the unit will step forward as much as possible to form a tighter formation.
  - *Drawback:* Can lead to units clustering uselessly behind chokepoints.

- **Fallback Idle State (e.g. Disgaea - certain AI)**
  - *Architecture:* If the pathing fails completely (e.g., target is out of range AND path is blocked), the unit simply defaults to passing its turn to save computing time.
  - *Execution:* Results in AI units occasionally appearing "brain dead" when faced with complex terrain they cannot navigate.

---

## Implementation Takeaways for Road of Nogg

- Preserve maximum-round and no-action guards for automated battles.
- Buffs and status effects must use explicit effect paths, never artificial minimum damage to trigger them.

[Back to Master Index](./tactical_rpg_turn_systems.md)
