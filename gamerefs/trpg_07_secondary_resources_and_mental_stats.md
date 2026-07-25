# Aspect 07: Secondary Resource Gauges & Mental Stats

A comparative reference on morale stats, fatigue gauges, TP points, and mental resilience across TRPGs.

---

## 1. Psychological, Morale & Alignment Attributes

Character mental or alignment attributes governing reaction proc chance, magic damage amplification, panic, or army survival.

### Approach 1.1: Psychological Reaction & Faith Scales
Hidden or explicit mental attributes controlling physical reaction chance, magic damage amplification, or desertion.
* **Games Following This Approach:** *Final Fantasy Tactics (Brave & Faith)*
* **Detailed Variations:**
  - *FFT:* **Brave** controls physical reaction proc % and physical damage. **Faith** boosts magic power and magic damage taken; permanent high Faith causes desertion.

### Approach 1.2: Army Morale Meters (Vitality Loss)
Morale replaces HP as army health. Losing a combat exchange drains Morale until the unit permanently dies.
* **Games Following This Approach:** *Yggdra Union (Morale Meter)*
* **Detailed Variations:**
  - *Yggdra Union:* Losing combat drains card-scaled Morale; reaching 0 Morale permanently kills the unit.

### Approach 1.3: Moral Alignment Scales (Law vs. Chaos)
Alignment meter shifts based on tactical story choices, altering mission objectives and party recruits.
* **Games Following This Approach:** *Feda: Emblem of Justice (Alignment)*
* **Detailed Variations:**
  - *Feda:* Moral Alignment (Law vs Chaos) shifts based on mission execution, changing recruit availability.

### Not Applicable / Absent
No psychological, morale, or alignment attributes exist.
* **Games:** *Fire Emblem Series, Tactics Ogre: Let Us Cling Together / Reborn, Hoshigami: Ruining Blue Earth, Triangle Strategy, Disgaea Series, Shining Force Series, TearRing Saga & Berwick Saga, Grandia Series & Octopath Traveler, Into the Breach, Dofus & Wakfu, Breath of Fire Series, Treasure of the Rudras, Langrisser Series, Vandal Hearts Series, Knights in the Nightmare, Phantom Brave / Makai Kingdom, Wild Arms XF, Stella Deus: The Gate of Eternity, Master of Monsters / Nectaris, Energy Breaker, Pokémon Series, Chrono Trigger, Digimon World 3, Dragon Quest 9, Ragnarok Online, MapleStory, Road of Nogg (current baseline)*

---

## 2. Secondary Combat Resources & Heat Gauges

Secondary resource pools powering special maneuvers or gating action frequency beyond standard HP/MP.

### Approach 2.1: Turn-Refreshing Skill & Tactical Points
Units gain +1 TP/SP/BP at the start of every turn to fuel special skills, replacing traditional consumable MP pools.
* **Games Following This Approach:** *Triangle Strategy (TP), Octopath Traveler (BP)*
* **Detailed Variations:**
  - *Triangle Strategy:* Gain +1 Tactical Point (TP) per turn (max 5 TP) to cast spells/skills.


### Approach 2.3: Shield Points & Stun Break Gauges
Enemies possess Shield Points. Hitting elemental or weapon weaknesses reduces Shield Points; reaching 0 triggers a Break/Stun state.
* **Games Following This Approach:** *Octopath Traveler*
* **Detailed Variations:**
  - *Octopath:* Shield Points drop by 1 per weakness hit. Reaching 0 Shield triggers **Break**, delaying enemy turns to the next round.

### Approach 2.4: Move PP Caps & Battle Form Transformations
Move PP (Power Points) limit each individual move slot, while single-battle form transformations boost stats.
* **Games Following This Approach:** *Pokémon Series (Move PP & Form Transformations), Breath of Fire Series, Disgaea Series*
* **Detailed Variations:**
  - *Pokémon Mainline:* Move PP limit each move slot (5 to 40 uses). Form transformations (Mega Evolution, Terastallization, Gigantamax) alter stats and typing once per battle.
  - *Breath of Fire:* AP fuels spellcasting, Master skill usage, and Dragon Gene transformations.

### Approach 2.5: Tension & Limit Break Gauges
Taking damage or spending turns charging builds a secondary gauge that unleashes massive damage or auto-triggers transformations.
* **Games Following This Approach:** *Dragon Quest 9, Digimon World 3*
* **Detailed Variations:**
  - *Dragon Quest 9:* Tension System allows characters to skip turns "Psyching Up", multiplying their next attack damage drastically (up to 100x tension). Taking damage randomly fills a separate Coup de Grâce meter for powerful ultimate moves.
  - *Digimon World 3:* Taking damage fills a **Blast Gauge**; when full, the Digimon auto-transforms into a powerful Blast Evolution for several turns.

### Not Applicable / Absent
No secondary skill points, fatigue heat, shield break, or form transformation gauges exist beyond standard HP/MP.
* **Games:** *Fire Emblem Series, Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Hoshigami: Ruining Blue Earth, Shining Force Series, TearRing Saga & Berwick Saga, Into the Breach, Dofus & Wakfu, Treasure of the Rudras, Langrisser Series, Vandal Hearts Series, Knights in the Nightmare, Phantom Brave / Makai Kingdom, Wild Arms XF, Yggdra Union, Stella Deus: The Gate of Eternity, Master of Monsters / Nectaris, Energy Breaker & Feda: Emblem of Justice, Chrono Trigger, Ragnarok Online, MapleStory, Road of Nogg (current baseline)*

---

## Implementation Takeaways for Road of Nogg

- No secondary combat gauge is currently confirmed.
- Add a gauge only with a distinct tactical purpose, serialization, AI valuation, and readable UI.

[Back to Master Index](./tactical_rpg_turn_systems.md)
