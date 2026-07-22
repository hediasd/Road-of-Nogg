# Aspect 04: Offensive Stat Scaling & Damage Calculation

A comparative guide on how stats, limbs, facing angles, and mathematical formulas calculate damage across TRPGs.

---

## 1. Stat Pairing & Primary Attribute Damage Architecture

High-level architectural model defining how character offensive stats scale into combat damage and compare against defender stats.

### Approach 1.1: Dual Stat Split (Physical vs. Special / Magic)
Physical attacks compare Physical Attack/Strength against Armor Defense (`Str/Atk vs Def`); Special/Magical attacks compare Magic Power against Magic Resistance (`Mag/SpAtk vs Res/SpDef`).
* **Games Following This Approach:** *Pokémon Series (Mainline & Spinoffs), Fire Emblem Series, Triangle Strategy, Octopath Traveler, Final Fantasy Tactics (PA/MA), Stella Deus: The Gate of Eternity, Breath of Fire Series, Treasure of the Rudras, Hoshigami: Ruining Blue Earth, Wild Arms XF, Energy Breaker, Chrono Trigger, Digimon World 3, Dragon Quest 9, Ragnarok Online, MapleStory*
* **Detailed Variations:**
  - *Pokémon Mainline:* Splits Physical moves (`Atk vs Def`) and Special moves (`SpAtk vs SpDef`). Multiplicative formula includes Move Power, STAB (1.5x), and 18-Type Effectiveness.
  - *Fire Emblem:* Flat subtraction: `Physical Damage = Str + WeaponMight - EnemyDef`; `Magic Damage = Mag + SpellMight - EnemyRes`.
  - *FFT:* PA scales melee weapons; MA scales magic spells. Back and side attacks bypass shield block chance.
  - *Dragon Quest 9:* Uses fractional base stats `(Atk/2) - (Def/4)` for physical, and caps magic damage based on Magical Might/Mending thresholds.
  - *Digimon World 3:* Direct subtraction between `Str vs Def` (Physical) and `Spt vs Wis` (Magic).
  - *Ragnarok Online:* Dual ATK/MATK pools. Physical damage heavily scales off Weapon ATK modifiers based on target Size (Small/Medium/Large).
  - *MapleStory:* Main Stat + Sub Stat multiplier formula `(4 * Main Stat + Sub Stat) * Weapon Attack` compared against flat or % Enemy Defense.

### Approach 1.2: Single Offense & Defense Subtraction (`ATK - DEF`)
A single Attack stat is compared directly against a single Defense stat for all combat calculations regardless of weapon or spell type.
* **Games Following This Approach:** *Shining Force Series, Vandal Hearts Series, Feda: Emblem of Justice, Langrisser Series, Master of Monsters / Nectaris, Phantom Brave / Makai Kingdom, Road of Nogg (current baseline)*
* **Detailed Variations:**
  - *Shining Force / Road of Nogg:* `Damage = Attacker ATK - Target DEF`. Simple, transparent damage math.
  - *Vandal Hearts:* Single ATK vs DEF subtraction, modified by 1.5x backstab multipliers and elevation bonuses.

### Approach 1.3: Weapon-Specific Primary Stat Scaling
Different weapon classes scale off entirely different primary character attributes.
* **Games Following This Approach:** *Disgaea Series*
* **Detailed Variations:**
  - *Disgaea:* Swords/Axes scale on `ATK`; Guns scale on `HIT`; Bows scale on `(ATK+HIT)/2`; Fists scale on `(ATK+SPD)/2`; Staves scale on `INT`.

### Approach 1.4: Weapon Proficiency & Skill Rank Scaling
Base stats are heavily modified by specialized Weapon Skill Ranks (Sword Rank, Spear Rank, Shield Rank) acquired through combat usage.
* **Games Following This Approach:** *Berwick Saga, Tactics Ogre: Let Us Cling Together / Reborn, Knights in the Nightmare*
* **Detailed Variations:**
  - *Berwick Saga:* High weapon skill rank increases hit rate, critical chance, and unlocks weapon-specific combat maneuvers.

### Approach 1.5: Deterministic & Fixed Numerical Damage
Zero offensive stats exist. Attacks deal fixed numerical values or scale strictly on card power vs morale.
* **Games Following This Approach:** *Into the Breach, Yggdra Union*
* **Detailed Variations:**
  - *Into the Breach:* 100% deterministic (e.g., Mech Cannon deals exactly 2 Damage; pushing unit into a wall deals 1 collision damage).
  - *Yggdra Union:* Card Power vs target Morale meter.

### Not Applicable / Absent
* **Games:** *(None — all 28 analyzed games feature a primary damage stat architecture).*

[Back to Master Index](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/tactical_rpg_turn_systems.md)
