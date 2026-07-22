# Aspect 14: Base Stats, Attributes & Characteristics

A comparative breakdown of primary attributes (STR, DEX, INT), derived statistics, stat allocation, and character sheet architecture across TRPGs and JRPGs.

---

## 1. Primary Attribute Architecture

Rules defining how a character's core offensive and defensive power is measured.

### Approach 1.1: Classic D&D 6-Stat Spread (STR, AGI, VIT, INT, DEX, LUK)
Characters possess a comprehensive array of primary attributes, each feeding into multiple derived statistics (e.g., AGI increases dodge and attack speed; VIT increases Max HP and physical defense).
* **Games Following This Approach:** *Tactics Ogre: Let Us Cling Together / Reborn, Ragnarok Online, MapleStory, Digimon World 3, Dragon Quest 9*
* **Detailed Variations:**
  - *Digimon World 3:* Features 6 primary stats (Strength, Defense, Spirit, Wisdom, Speed, Charisma). Physical attacks use Str vs Def; Magic uses Spt vs Wis. Charisma dictates whether you can battle certain NPCs and effects specific Digivolutions.
  - *Dragon Quest 9:* Features primary attributes like Strength, Resilience (Def), Agility, Deftness (Crit/Steal rate), Charm (Chance to enthrall enemies), Magical Might, and Magical Mending. Stats are tied directly to Vocation (Class) and seeds.
  - *Ragnarok Online:* The classic 6 (STR/AGI/VIT/INT/DEX/LUK). Every point of AGI increases Flee and ASPD; LUK increases Perfect Dodge and Crit rate.
  - *MapleStory:* 4 Main Stats (STR/DEX/INT/LUK). Classes scale primarily off one Main Stat (e.g. Mages use INT) and require a sub-stat for gear equip requirements (historically).

### Approach 1.2: Condensed Combat Stats (ATK, DEF, MAG, RES, SPD)
Primary attributes are abstracted directly into their combat output equivalents. Characters do not have an underlying "Strength" score, but rather a direct "Attack" score.
* **Games Following This Approach:** *Triangle Strategy, Pokémon Series, Into the Breach, Shining Force Series, Master of Monsters / Nectaris, Road of Nogg (current baseline)*
* **Detailed Variations:**
  - *Pokémon Series:* 6 core combat stats (HP, Attack, Defense, Sp. Atk, Sp. Def, Speed) dictated by base species values, IVs, and EVs.
  - *Road of Nogg:* Highly condensed to HP, ATK, DEF, SPD, MOVE.

### Approach 1.3: Dual Physical & Magical Splits
Stats are split symmetrically down Physical and Magical lines, often determining class viability and hybrid potential.
* **Games Following This Approach:** *Final Fantasy Tactics, Fire Emblem Series, Stella Deus: The Gate of Eternity*
* **Detailed Variations:**
  - *FFT:* PA (Physical Attack) and MA (Magical Attack) dictate all offensive scaling.

### Approach 1.4: Massive Inflation & Exponential Scaling
Base stats start in the tens and reach the tens of millions as the game progresses, requiring logarithmic stat presentation.
* **Games Following This Approach:** *Disgaea Series, Phantom Brave / Makai Kingdom*
* **Detailed Variations:**
  - *Disgaea:* Stats undergo reincarnation multipliers, item world boosts, and evility % stacking, resulting in billions of ATK.

### Not Applicable / Absent
The game avoids traditional stat arrays in favor of fixed loadouts or pure card/item power.
* **Games:** *Yggdra Union (Uses Card Power vs Morale), Into the Breach (Mech HP and Move only, damage is fixed)*

---

## 2. Stat Allocation & Progression

How characters acquire permanent stat growth over time.

### Approach 2.1: Manual Point Allocation
Players receive a pool of blank stat points upon leveling up and must distribute them manually, allowing for specialized builds (e.g., Pure AGI assassins).
* **Games Following This Approach:** *Ragnarok Online, MapleStory, Dofus & Wakfu*

### Approach 2.2: Class-Based Growth Rates (RNG Growths)
Upon leveling up, characters have a percentage chance (e.g., 40% chance for STR) to gain a point in each stat, heavily influenced by their current class.
* **Games Following This Approach:** *Fire Emblem Series, Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Dragon Quest 9*

### Approach 2.3: Fixed Linear Progression
Characters gain predefined, deterministic stats at every level-up.
* **Games Following This Approach:** *Chrono Trigger, Triangle Strategy, Shining Force Series (mostly fixed)*

### Approach 2.4: Hidden Effort Values (EVs)
Defeating specific enemies grants invisible micro-stats that slowly raise primary attributes, rewarding specialized grinding.
* **Games Following This Approach:** *Pokémon Series*

---

## 3. Comprehensive Stat Compendium

A complete listing of the core primary and secondary attributes utilized by the 28 games referenced in this design document.

### 3.1: Classic Base Stat Arrays (STR, AGI, VIT, INT, DEX, LUK)
* **Tactics Ogre (Let Us Cling Together / Reborn):** HP, MP, STR (Strength), VIT (Vitality), DEX (Dexterity), AGI (Agility), AVD (Avoidance), INT (Intelligence), MND (Mind), RES (Resistance).
* **Ragnarok Online:** HP, SP, STR (Melee ATK/Weight), AGI (Attack Speed/Flee), VIT (HP/Def), INT (SP/M.ATK/M.DEF), DEX (Hit/Cast Speed), LUK (Crit/Perfect Dodge).
* **MapleStory:** HP, MP, STR, DEX, INT, LUK.
* **Digimon World 3:** HP, MP, Strength, Defense, Spirit, Wisdom, Speed, Charisma.
* **Dragon Quest 9:** HP, MP, Strength, Agility, Resilience, Deftness (Crit/Steal), Charm, Magical Might, Magical Mending.
* **Dofus & Wakfu:** HP, AP (Action Points), MP (Movement Points), Initiative, Prospecting, Range, Vitality, Wisdom, Strength (Earth), Intelligence (Fire), Chance (Water), Agility (Air).
* **Wild Arms XF:** HP, MP, STR, VIT, SOR (Sorcery), RES (Resistance), AIM (Accuracy), PRY (Parry), WGT (Weight), RFX (Reflex).
* **Knights in the Nightmare:** HP, VIT, TEC, AGI (Weapon durability acts as MP).
* **Energy Breaker / Feda:** HP, MP, Str, Def, Int, Agi.
* **Chrono Trigger:** HP, MP, Power, Stamina, Speed, Magic, Hit, Evade, Magic Defense.
* **Grandia Series:** HP, SP, MP, STR, VIT, WIT (Speed/Action gauge fill rate), AGI (Movement speed on field).
* **Breath of Fire Series (1-4):** HP, AP, Pwr (Power), Def (Defense), Agi (Agility), Wis (Wisdom).
* **Treasure of the Rudras:** HP, MP, STR, DEF, INT, MDEF, SPD, M_SPD (Magic Speed).

### 3.2: Condensed Combat Stats (ATK, DEF, MAG, RES, SPD)
* **Triangle Strategy:** HP, Str, Phys Def, Magic, Magic Def, Luck, Speed, Move, Jump.
* **Pokémon Series:** HP, Attack, Defense, Sp. Atk (Special Attack), Sp. Def (Special Defense), Speed.
* **Shining Force Series:** HP, MP, Attack, Defense, Agility, Move.
* **Master of Monsters / Nectaris:** HP, ATK, DEF, Move.
* **Langrisser Series:** HP, ATK, DEF, MP, A (Commander Attack Modifier), D (Commander Defense Modifier), MV (Move).
* **Vandal Hearts Series:** HP, MP, ATK, DEF, AGI (Agility).
* **Hoshigami: Ruining Blue Earth:** HP, MP, STR (Strength), DEF (Defense), AGI (Agility), plus Coin Deity Affinities.

### 3.3: Dual Physical & Magical Splits
* **Final Fantasy Tactics:** HP, MP, PA (Physical Attack), MA (Magical Attack), Speed, Brave, Faith, Move, Jump, C-EV/S-EV/A-EV.
* **Fire Emblem Series:** HP, Str (Strength), Mag (Magic), Skl (Skill/Dexterity), Spd (Speed), Lck (Luck), Def (Defense), Res (Resistance), Con (Constitution/Build), Mov (Movement).
* **TearRing Saga / Berwick Saga:** HP, Str, Mag, Skl, Spd, Lck, Def, Wlv (Weapon Level), Mov.
* **Octopath Traveler:** HP, SP, Phys. Atk, Phys. Def, Elem. Atk, Elem. Def, Accuracy, Speed, Critical, Evasion.
* **Stella Deus: The Gate of Eternity:** HP, MP, SP (Skill Points/AP), STR, DEF, INT, RES, AGI, LUK, MOV, JMP.

### 3.4: Massive Inflation & Exponential Scaling
* **Disgaea Series:** HP, SP, ATK (Attack), DEF (Defense), INT (Intelligence), RES (Resistance), HIT (Accuracy), SPD (Speed/Evasion).
* **Phantom Brave / Makai Kingdom:** HP, SP, ATK, DEF, INT, RES, SPD.

### 3.5: Not Applicable / Absent / Fixed Loadouts
* **Yggdra Union:** GEN (General/Defense), ATK (Attack), TEC (Technique), LUK (Luck), Morale (Functions as Army HP).
* **Into the Breach:** HP, Move (Grid-based, damage is fixed to weapons, no RNG stats).

---

[Back to Master Index](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/tactical_rpg_turn_systems.md)
