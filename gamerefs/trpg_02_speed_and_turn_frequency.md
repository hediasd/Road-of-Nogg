# Aspect 02: Speed Stat Behavior & Turn Frequency

A comparative analysis of how Speed and Agility stats govern turn order, action frequency, double-attacks, and grid movement steps across TRPGs.

---

## 1. Speed Influence on Turn Scheduling & Frequency

High-level rules defining whether character Speed/Agility grants extra turn activations or simply dictates queue position.

### Approach 1.1: Dynamic Turn Frequency (Fast Units Gain Multiple Turns)
High Speed accelerates CT/WT accumulation, enabling fast units to act multiple times before a slow unit gets a single turn.
* **Games Following This Approach:** *Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Hoshigami: Ruining Blue Earth, Triangle Strategy, Grandia Series, Octopath Traveler, Dofus & Wakfu, Stella Deus: The Gate of Eternity, Wild Arms XF, Chrono Trigger, Digimon World 3, Ragnarok Online*
* **Detailed Variations:**
  - *FFT / Tactics Ogre / Digimon World 3:* `CT += Speed` tick accumulation; fast units hit 100 CT sooner.
  - *Hoshigami:* DEX/Speed accelerates Ready Action Points (RAP) accumulation.
  - *Grandia / Octopath:* Speed increases icon movement velocity along the linear COM/ACT timeline.
  - *Chrono Trigger:* High speed rapidly fills the ATB gauge.
  - *Ragnarok Online:* Agility increases ASPD, reducing the delay between continuous real-time attacks.

### Approach 1.2: Round-End Extra Actions (EX-Turns via Agility Threshold)
In round-based RPGs, if a unit's Agility is double an enemy's, the unit gains a full extra turn at the end of the round.
* **Games Following This Approach:** *Breath of Fire Series (BoF3, BoF4)*
* **Detailed Variations:**
  - *Breath of Fire 3 & 4:* If `Agility >= 2 * Target Agility`, the character receives an extra **EX Turn** after all standard round turns resolve.

### Approach 1.3: Priority Bracket Tie-Breaking & Speed Order Reversal
Speed determines who moves first within a priority move tier during a round. Field effects can invert speed order entirely.
* **Games Following This Approach:** *Pokémon Series (Mainline)*
* **Detailed Variations:**
  - *Pokémon Mainline:* Speed breaks ties within the same move priority bracket. *Trick Room* reverses speed order for 5 turns (slowest move first); *Tailwind* doubles team speed.

### Approach 1.4: Fixed Intra-Round Turn Priority Only
Speed determines turn order rank within a round, but every unit acts strictly once per round regardless of Speed stat magnitude.
* **Games Following This Approach:** *Shining Force Series, Treasure of the Rudras, Langrisser Series, Energy Breaker, Dragon Quest 9, Road of Nogg (current baseline)*
* **Detailed Variations:**
  - *Shining Force / Road of Nogg:* Round start sorts units by Agility/Speed descending; no multi-turns.
  - *Dragon Quest 9:* Turn order varies within a range of the Agility stat, meaning strict order can sometimes shuffle.

### Not Applicable / Absent
Speed stat is absent, fixed, or has zero impact on turn scheduling or turn frequency.
* **Games:** *Disgaea Series, Into the Breach, Vandal Hearts Series, TearRing Saga & Berwick Saga, Knights in the Nightmare, Phantom Brave / Makai Kingdom, Yggdra Union, Master of Monsters / Nectaris, Feda: Emblem of Justice, MapleStory*

---

## 2. Speed Influence on Intra-Combat Multi-Hits & Doubling

Mechanics where Speed governs extra attacks or counter-strikes within a single combat engagement resolution.

### Approach 2.1: Combat Doubling Thresholds (Extra Strike per Encounter)
Speed does not alter turn queue order, but if a unit's Speed exceeds the defender's Speed by a specific threshold, the unit strikes a second time within single combat resolution.
* **Games Following This Approach:** *Fire Emblem Series*
* **Detailed Variations:**
  - *Fire Emblem:* If `Attacker Speed - Defender Speed >= 4` (or 5), attacker gets a second attack during combat resolution.

### Approach 2.2: Agility-Based Counter-Attack Proc Chance
Character Agility stat directly determines the percentage chance to retaliate with a counter-attack when struck by physical hits.
* **Games Following This Approach:** *Breath of Fire Series*
* **Detailed Variations:**
  - *Breath of Fire:* Counter-attack probability scales directly off character Agility minus target Agility.

### Approach 2.3: Attack Speed (ASPD) Continuous Strikes
High Agility reduces animation delay and skill cooldowns, allowing characters to land multiple hits per second in real-time.
* **Games Following This Approach:** *Ragnarok Online, MapleStory*
* **Detailed Variations:**
  - *Ragnarok Online:* ASPD formula scales heavily with AGI, capping at 190 (or 193) which allows for upwards of 5-7 attacks per second.

### Not Applicable / Absent
Speed stat does not grant extra strikes, doubling, or counter-attack chance during combat resolution.
* **Games:** *Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Hoshigami: Ruining Blue Earth, Triangle Strategy, Disgaea Series, Shining Force Series, TearRing Saga & Berwick Saga, Grandia Series & Octopath Traveler, Into the Breach, Dofus & Wakfu, Treasure of the Rudras, Langrisser Series, Vandal Hearts Series, Knights in the Nightmare, Phantom Brave / Makai Kingdom, Wild Arms XF, Yggdra Union, Stella Deus: The Gate of Eternity, Master of Monsters / Nectaris, Energy Breaker & Feda: Emblem of Justice, Pokémon Series, Chrono Trigger, Digimon World 3, Dragon Quest 9, Road of Nogg (current baseline)*

---

## 3. Speed & Agility Influence on Grid Traversal & Lock Evasion

Rules governing how Speed or Agility affects grid movement distance or escaping adjacent enemies.

### Approach 3.1: Movement Step Multipliers per Turn Cycle
Speed buffs grant 2x or 3x movement steps per turn cycle during grid dungeon exploration.
* **Games Following This Approach:** *Pokémon Series (Mystery Dungeon)*
* **Detailed Variations:**
  - *Pokémon Mystery Dungeon:* Speed boosts (+1, +2 stages) allow taking 2 or 3 movement/action steps per turn.

### Approach 3.2: Lock vs Dodge Ratio Calculations (Grid Pinning)
Agility feeds Dodge and Lock stats. Attempting to step away from an adjacent enemy evaluates `Dodge / Lock` ratio to determine if movement points are lost.
* **Games Following This Approach:** *Dofus & Wakfu*
* **Detailed Variations:**
  - *Dofus & Wakfu:* High enemy Lock pins low Dodge characters in place, draining AP and MP.

### Not Applicable / Absent
Speed and Agility have zero effect on grid movement distance or escaping adjacent enemies.
* **Games:** *Fire Emblem Series, Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Hoshigami: Ruining Blue Earth, Triangle Strategy, Disgaea Series, Shining Force Series, TearRing Saga & Berwick Saga, Grandia Series & Octopath Traveler, Into the Breach, Breath of Fire Series, Treasure of the Rudras, Langrisser Series, Vandal Hearts Series, Knights in the Nightmare, Phantom Brave / Makai Kingdom, Wild Arms XF, Yggdra Union, Stella Deus: The Gate of Eternity, Master of Monsters / Nectaris, Energy Breaker & Feda: Emblem of Justice, Pokémon Series (Mainline), Chrono Trigger, Digimon World 3, Dragon Quest 9, Ragnarok Online, MapleStory, Road of Nogg (current baseline)*

---

[Back to Master Index](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/tactical_rpg_turn_systems.md)
