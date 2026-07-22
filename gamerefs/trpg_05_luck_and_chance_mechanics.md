# Aspect 05: Luck & Chance Mechanics

A comparative look at Luck attributes, critical hits, evasion formulas, and RNG vs. determinism across TRPGs.

---

## 1. Luck Attribute Implementation & Scope

Architectural presence and functional scope of Luck or dedicated accuracy/evasion attributes.

### Approach 1.1: Multi-Purpose Luck Attribute
Luck is an explicit character attribute boosting Hit Rate, Evasion, Critical Hit Chance, Critical Avoidance, item drop rates, and passive skill activation rates.
* **Games Following This Approach:** *Fire Emblem Series, Tactics Ogre: Let Us Cling Together / Reborn, Hoshigami: Ruining Blue Earth, Breath of Fire Series, Treasure of the Rudras, Berwick Saga, Wild Arms XF, Energy Breaker, Ragnarok Online, MapleStory*
* **Detailed Variations:**
  - *Fire Emblem:* Luck adds to Hit Rate (`Luck * 0.5`), Avoidance (`Luck * 1`), and directly subtracts from enemy Critical Chance (`Crit Avoid = Luck`).
  - *Tactics Ogre:* Luck scales critical hits, rare loot drops from slain enemies, and tarot card proc rates.
  - *Ragnarok Online:* LUK increases Crit rate, Perfect Dodge, Blacksmith forging success rates, and status ailment resistance.
  - *MapleStory:* LUK acts as the primary damage stat for Thief classes, while globally increasing Avoidability and dropping less EXP upon death.

### Approach 1.2: Dedicated Critical Stages & Accuracy/Evasion Stage Modifiers
Luck is replaced by explicit `Critical`, `Dexterity`, `Deftness`, or `Accuracy` attributes dedicated strictly to hit rates and critical strikes.
* **Games Following This Approach:** *Pokémon Series (Mainline & Spinoffs), Triangle Strategy, Octopath Traveler, Dofus & Wakfu, Stella Deus: The Gate of Eternity, Dragon Quest 9*
* **Detailed Variations:**
  - *Pokémon Mainline:* Base Crit Chance is 1/24 (4.17%). Crit stages (+1: 1/8, +2: 1/2, +3: 100%) scale with moves (*Slash*, *Stone Edge*) or items (*Scope Lens*). Accuracy/Evasion stages range from -6 to +6.
  - *Triangle Strategy / Octopath:* Critical stat dictates probability of landing 1.5x critical damage on non-backstab attacks.
  - *Dragon Quest 9:* Deftness acts as a dedicated stat for Critical Hit chance, Pre-emptive strikes, and Steal success rate.

### Approach 1.3: Pure Determinism & Zero RNG Resolution
Zero randomness in combat. 100% hit chance, no critical hits, no Luck stat. Outcomes are completely predictable.
* **Games Following This Approach:** *Into the Breach*
* **Detailed Variations:**
  - *Into the Breach:* Attacks always hit and deal telegraphed damage; zero dice rolls.

### Not Applicable / Absent
No explicit Luck or Critical stat exists; chance mechanics rely on flat weapon accuracy formulas, skill percentages, or cover stats.
* **Games:** *Disgaea Series, Shining Force Series, Knights in the Nightmare, Phantom Brave / Makai Kingdom, Master of Monsters / Nectaris, Langrisser Series, Vandal Hearts Series, Yggdra Union, Feda: Emblem of Justice, Chrono Trigger, Digimon World 3, Road of Nogg (current baseline)*

---

## 2. Critical Hit Mechanics & Defensive Mitigation

Rules defining how critical hits deal extra damage and interact with defender defensive stats or positioning.

### Approach 2.1: Multiplicative Damage & Armor Bypassing Crits
Critical hits double or triple total combat damage, or bypass defender armor ratings.
* **Games Following This Approach:** *Fire Emblem Series, Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Shining Force Series, Breath of Fire Series, Chrono Trigger, Digimon World 3, Dragon Quest 9, Ragnarok Online, MapleStory*
* **Detailed Variations:**
  - *Fire Emblem:* Critical hit multiplies total damage output by 3x (`Damage = (ATK - DEF) * 3`).
  - *Dragon Quest 9:* Crits deal massive damage ignoring enemy defense, essential for hunting Metal Slimes.
  - *Ragnarok Online:* Crits deal 1.4x damage and guarantee a 100% hit rate, completely bypassing enemy Flee (evasion).
  - *MapleStory:* Crits deal a base of 120%-150% damage, scaling up massively with Critical Damage % stats.

### Approach 2.2: Stage-Based Crit Chance (Ignoring Defense Buffs)
Critical hits deal 1.5x damage and bypass all target Stat Stage Buffs (e.g. ignoring enemy +6 Defense buffs).
* **Games Following This Approach:** *Pokémon Series*
* **Detailed Variations:**
  - *Pokémon Mainline:* Crits deal 1.5x damage, ignore target Defense stage boosts, and ignore attacker Attack stage debuffs.

### Approach 2.3: Guaranteed Directional Crits (100% Backstab Crit)
Attacking an enemy from behind (rear tile) guarantees a 100% Critical Hit chance regardless of Luck stat.
* **Games Following This Approach:** *Triangle Strategy, Vandal Hearts Series*
* **Detailed Variations:**
  - *Triangle Strategy:* Backstabs always land as 100% Critical Hits.

### Not Applicable / Absent
No critical hit mechanics exist in combat resolution.
* **Games:** *Into the Breach, Hoshigami: Ruining Blue Earth, Disgaea Series, TearRing Saga & Berwick Saga, Grandia Series & Octopath Traveler, Dofus & Wakfu, Treasure of the Rudras, Langrisser Series, Knights in the Nightmare, Phantom Brave / Makai Kingdom, Wild Arms XF, Yggdra Union, Stella Deus: The Gate of Eternity, Master of Monsters / Nectaris, Energy Breaker & Feda: Emblem of Justice, Road of Nogg (current baseline)*

---

[Back to Master Index](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/tactical_rpg_turn_systems.md)
