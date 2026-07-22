# Aspect 04: Offensive Stat Scaling & Damage Calculation

A comparative guide on how stats, limbs, facing angles, and mathematical formulas calculate damage across TRPGs.

---

## 1. Stat Pairing & Primary Attribute Damage Architecture

High-level architectural model defining how character offensive stats scale into combat damage and compare against defender stats.

### Approach 1.1: Dual Stat Split (Physical vs. Special / Magic)
Physical attacks compare Physical Attack/Strength against Armor Defense (`Str/Atk vs Def`); Special/Magical attacks compare Magic Power against Magic Resistance (`Mag/SpAtk vs Res/SpDef`).
* **Games Following This Approach:** *Pokémon Series (Mainline & Spinoffs), Fire Emblem Series, Triangle Strategy, Octopath Traveler, Final Fantasy Tactics (PA/MA), Stella Deus: The Gate of Eternity, Breath of Fire Series, Treasure of the Rudras, Hoshigami: Ruining Blue Earth, Wild Arms XF, Energy Breaker*
* **Detailed Variations:**
  - *Pokémon Mainline:* Splits Physical moves (`Atk vs Def`) and Special moves (`SpAtk vs SpDef`). Multiplicative formula includes Move Power, STAB (1.5x), and 18-Type Effectiveness.
  - *Fire Emblem:* Flat subtraction: `Physical Damage = Str + WeaponMight - EnemyDef`; `Magic Damage = Mag + SpellMight - EnemyRes`.
  - *FFT:* PA scales melee weapons; MA scales magic spells. Back and side attacks bypass shield block chance.

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
* **Games:** *(None — all 26 analyzed games feature a primary damage stat architecture).*

---

## 2. Target Anatomy & Damage Conversion Mechanics

Mechanics targeting specific body parts or converting non-lethal temporary damage into permanent HP loss.

### Approach 2.1: Anatomical & Limb-Specific Target Systems
Entity HP is split across individual anatomical body parts (Body, Arms, Legs), each with separate HP meters and mechanical degradation penalties.
* **Games Following This Approach:** *Front Mission Series (FM 1–5)*
* **Detailed Variations:**
  - *Front Mission:* Destroying Body kills the Wanzer mech; destroying Arms disables weapons; destroying Legs halves movement range.

### Approach 2.2: Multi-Stage Damage & Health Conversion
Attacks deal non-lethal temporary damage first, which must be converted into permanent lethal damage by follow-up attacks.
* **Games Following This Approach:** *Resonance of Fate*
* **Detailed Variations:**
  - *Resonance of Fate:* Submachine guns deal "Scratch Damage" (blue HP), which inflates rapidly but cannot kill. Handguns deal "Direct Damage" (red HP), converting all accumulated Scratch Damage into actual permanent HP loss.

### Not Applicable / Absent
Attacks deal direct damage to a single global HP pool without anatomical limb targeting or scratch health conversion.
* **Games:** *Fire Emblem Series, Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Hoshigami: Ruining Blue Earth, Triangle Strategy, Disgaea Series, Shining Force Series, TearRing Saga & Berwick Saga, Grandia Series & Octopath Traveler, Vanguard Bandits, Into the Breach, Dofus & Wakfu, Breath of Fire Series, Treasure of the Rudras, Langrisser Series, Vandal Hearts Series, Knights in the Nightmare, Phantom Brave / Makai Kingdom, Wild Arms XF, Yggdra Union, Stella Deus: The Gate of Eternity, Master of Monsters / Nectaris, Energy Breaker & Feda: Emblem of Justice, Pokémon Series, Road of Nogg (current baseline)*

---

[Back to Master Index](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/tactical_rpg_turn_systems.md)
