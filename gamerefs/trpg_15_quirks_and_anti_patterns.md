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

## 3. Implementation Takeaways for Road of Nogg

- **To Avoid**: Infinite grind loops (EXP/JP should ideally be tied to battle victory or unique actions, not infinitely spammable actions). 
- **To Decide**: The 1-Damage Buff quirk. Currently, Road of Nogg's `calculateSpellDamage` enforces `max(1, dmg)`. Spells with `0` base damage (like "Empower") deal 1 damage to the caster. This is functionally identical to the RO quirk. We can keep it for flavor, or filter out damage for spells specifically marked as "buffs" in a future patch.

---
[Back to Master Index](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/tactical_rpg_turn_systems.md)
