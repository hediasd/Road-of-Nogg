# Aspect 08: Equipment Weight & Mobility Penalties

A comparative look at weight penalties, jump height stats, terrain traversal costs, and line-of-sight restrictions across TRPGs.

---

## 1. Equipment Weight Penalties

Rules defining how equipped gear or held items penalize turn initiative or combat speed.

### Approach 1.1: Gear Weight Increases Initiative Delay
Equipping heavier weapons, armor, and accessories directly increases unit Wait Time (WT), delaying turn frequency.
* **Games Following This Approach:** *Tactics Ogre: Let Us Cling Together / Reborn, Stella Deus: The Gate of Eternity*
* **Detailed Variations:**
  - *Tactics Ogre:* Base WT is determined by class; every piece of equipped armor and weapon adds directly to total WT penalty.

### Approach 1.2: Gear Weight Penalizes Combat Speed & Doubling
Equipped weapon weight subtracts from combat speed without directly delaying turn order queue timing.
* **Games Following This Approach:** *Fire Emblem Series, TearRing Saga & Berwick Saga, Breath of Fire Series*
* **Detailed Variations:**
  - *Fire Emblem:* If `Weapon Weight > Build/Constitution`, excess weight lowers effective Speed for doubling and evasion.
  - *Berwick Saga:* Heavy shields and lances reduce agility during combat rounds.

### Approach 1.3: Held Item Speed & Move Lock Modifiers
Equipping specific held items modifies Speed stats or restricts move selection.
* **Games Following This Approach:** *Pokémon Series (Mainline)*
* **Detailed Variations:**
  - *Pokémon Mainline:* Specific held items (*Iron Ball*, *Macho Brace*) halve speed or reduce priority; *Choice Scarf* boosts speed by 1.5x but locks move selection.

### Approach 1.4: Inventory Weight Capacity Penalties (MMOs)
Carrying excessive inventory weight disables passive recovery and eventually attacks.
* **Games Following This Approach:** *Ragnarok Online*
* **Detailed Variations:**
  - *Ragnarok Online:* Carrying inventory weight over 50% capacity disables natural HP/SP regeneration. Exceeding 90% disables attacking and skill usage entirely.

### Not Applicable / Absent
Equipment or held items have zero weight penalty or initiative delay.
* **Games:** *Final Fantasy Tactics, Hoshigami: Ruining Blue Earth, Triangle Strategy, Disgaea Series, Shining Force Series, Grandia Series & Octopath Traveler, Into the Breach, Dofus & Wakfu, Treasure of the Rudras, Langrisser Series, Vandal Hearts Series, Knights in the Nightmare, Phantom Brave / Makai Kingdom, Wild Arms XF, Yggdra Union, Master of Monsters / Nectaris, Energy Breaker & Feda: Emblem of Justice, Chrono Trigger, Digimon World 3, Dragon Quest 9, MapleStory, Road of Nogg (current baseline)*

---

## 2. Terrain Traversal & Verticality Gating

Rules governing how elevation, jump stats, grid terrain types, and line-of-sight restrict movement or damage.

### Approach 2.1: Jump Stat & Vertical Height Traversal
Move and Jump stats determine maximum height difference a unit can climb between adjacent tiles on 3D terrain grids.
* **Games Following This Approach:** *Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Triangle Strategy, Disgaea Series, Vandal Hearts Series, Wild Arms XF*
* **Detailed Variations:**
  - *FFT / Tactics Ogre / Disgaea:* Jump stat dictates max vertical height difference navigable per tile step.

### Approach 2.2: Elevation Damage & Range Modifiers
Attacking from higher ground grants physical attack damage bonuses and extended attack range.
* **Games Following This Approach:** *Vandal Hearts Series, Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Triangle Strategy*
* **Detailed Variations:**
  - *Vandal Hearts:* High elevation grants physical attack damage bonuses and extended bow/attack range.

### Approach 2.3: Special Grid Terrain Traversal Types
Grid movement types gate traversal through specific terrain tiles (Land, Water, Lava, Levitating/Ghost wall passing).
* **Games Following This Approach:** *Pokémon Series (Mystery Dungeon Grid Mobility), Langrisser Series, Master of Monsters / Nectaris*
* **Detailed Variations:**
  - *Pokémon Mystery Dungeon:* Grid movement types (Land, Water, Lava, Levitation/Ghost passing through walls).
  - *Langrisser / Master of Monsters:* Terrain movement costs penalize cavalry in forests/mountains while flying units ignore terrain.

### Approach 2.4: Line-of-Sight & Ballistic Arc Constraints
Ranged spells and arrows require clear Line of Sight (calculated via rasterized line raycasting). Obstacles or units block line of sight unless the spell bypasses LoS.
* **Games Following This Approach:** *Dofus & Wakfu, Tactics Ogre: Let Us Cling Together / Reborn, Final Fantasy Tactics, Wild Arms XF, Knights in the Nightmare, Ragnarok Online*
* **Detailed Variations:**
  - *Dofus & Wakfu:* Uses discrete raycasting; obstacles block spells unless the spell has "No Line of Sight".
  - *FFT / Tactics Ogre:* Archers fire along 3D parabolic arcs; high obstacles in the trajectory intercept arrows mid-flight.
  - *Ragnarok Online:* Line of Sight (LoS) is required for most ranged attacks and targeted spells; obstacles like walls explicitly prevent targeting.

### Approach 2.5: Real-Time Platforming & Vertical Navigation
Terrain relies heavily on vertical platforming physics.
* **Games Following This Approach:** *MapleStory*
* **Detailed Variations:**
  - *MapleStory:* Jump stats directly increase the height of real-time jumps; navigating platforms and ropes is a core environmental movement mechanic.

### Not Applicable / Absent
Board terrain is uniform and flat with no jump stat gating, elevation bonuses, or line-of-sight constraints.
* **Games:** *Fire Emblem Series, Shining Force Series, TearRing Saga & Berwick Saga, Hoshigami: Ruining Blue Earth, Grandia Series & Octopath Traveler, Into the Breach, Breath of Fire Series, Treasure of the Rudras, Phantom Brave / Makai Kingdom, Yggdra Union, Stella Deus: The Gate of Eternity, Energy Breaker & Feda: Emblem of Justice, Chrono Trigger, Digimon World 3, Dragon Quest 9, Road of Nogg (current baseline)*

---

[Back to Master Index](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/tactical_rpg_turn_systems.md)
