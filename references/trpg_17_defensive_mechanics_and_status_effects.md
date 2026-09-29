# Aspect 17: Defensive Mechanics & Status Effects

A comparative breakdown of weaknesses, resistances, and status ailments used to mitigate damage or cripple opponents across TRPGs.

---

## 1. Weakness & Resistance Paradigms

Rules defining how defensive elemental affinities modify incoming damage.

### Approach 1.1: Multiplicative Modifiers (The x2 / x0.5 System)
Elemental interactions act as direct multipliers to final damage. Hitting a weakness doubles damage; hitting a resistance halves it.
* **Games Following This Approach:** *Pokémon Series, Persona / Shin Megami Tensei, Triangle Strategy, Octopath Traveler*
* **Detailed Variations:**
  - *Pokémon Series:* 18 types with strict x2, x0.5, and x0 multipliers. Dual types can stack this to x4 or x0.25.
  - *Octopath Traveler:* Weaknesses are tied to the "Shield Break" system, lowering shields, and dealing bonus damage when broken.

### Approach 1.2: Flat Damage Reduction (Armor & Resistance Stats)
Elemental defense is a flat stat subtracted from the incoming magic attack, rather than a multiplier.
* **Games Following This Approach:** *Fire Emblem Series, Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn*
* **Detailed Variations:**
  - *Fire Emblem Series:* Resistance (Res) directly mitigates Magical attack damage point-for-point.
  - *Tactics Ogre:* Elemental resistances on armor reduce damage from specific spell elements by a flat percentage or stat threshold.

### Approach 1.3: Fractional or Step-Based Scaling
Spells do 1.5x damage on weak, 0.5x on resist, or use specific fractions.
* **Games Following This Approach:** *Dragon Quest 9, MapleStory*
* **Detailed Variations:**
  - *MapleStory:* 1.5x for Strong, 1.0x for Normal, 0.5x for Weak, and 0x for Immune.

---

## 2. Comprehensive Status Effects

Status effects are a core tenet of defensive and utility play. Below is a categorized compendium of common status ailments across the analyzed TRPGs.

### 2.1: Action-Denial & Turn-Skipping
Effects that completely remove a unit's ability to act on their turn.
* **Stun / Flinch:** Skips the immediate next turn. Usually clears automatically.
* **Paralysis:** Chance to skip a turn, often severely reduces Speed/Evasion (e.g., *Pokémon Series*, *Final Fantasy Tactics*).
* **Sleep:** Unit cannot act until awoken by damage or passing time (e.g., *Chrono Trigger*, *Dragon Quest 9*).
* **Freeze / Petrify (Stone):** Unit becomes an obstacle. Petrify often counts as a "Death" if the whole party is petrified (e.g., *Final Fantasy Tactics*).
* **Stop / Time Stop:** Halts the ATB/CT gauge completely for a duration.

### 2.2: Damage-Over-Time (DoT)
Effects that sap HP/MP progressively.
* **Poison:** Deals a flat amount or percentage of max HP every turn (e.g., *Tactics Ogre*, *Pokémon Series*).
* **Burn / Ignite:** Deals damage and often lowers physical attack stats.
* **Bleed / Lacerate:** Deals damage when the unit moves or takes actions (e.g., *Dofus & Wakfu*).
* **Doom / Death Sentence:** A counter above the unit's head. When it hits 0, they instantly die (e.g., *Final Fantasy Tactics*).

### 2.3: Stat Mitigation & Crippling
Debuffs that lower combat effectiveness without fully preventing actions.
* **Blind / Darkness:** Drastically reduces physical accuracy (e.g., *Final Fantasy Tactics*).
* **Silence / Mute:** Prevents the casting of magic or skills.
* **Slow:** Reduces Speed, CT charge rate, or Move distance.
* **Curse:** Often prevents healing, or causes damage dealt to reflect onto the attacker.
* **Confusion / Charm:** Unit attacks randomly or attacks allies (e.g., *Fire Emblem Series*, *Shining Force Series*).

---

## Implementation Takeaways for Road of Nogg

- Keep affinities and timed effects in authoritative battle state and deterministic history.
- Generalize stat modifiers before adding many one-off buff or debuff branches.

[Back to Master Index](./tactical_rpg_turn_systems.md)
