# Aspect 09: Algorithms & Mathematical Models

A technical reference detailing algorithms, pathfinding models, line-of-sight formulas, and AI decision systems used across Tactical & Turn-Based RPGs.

---

## 1. Grid Pathfinding Algorithms

Standard graph search algorithms used to calculate shortest path movement across square, hex, or free-form terrain grids.

### Approach 1.1: 2D Square Grid A* Pathfinding
Finds the shortest path on a weighted 2D grid array using heuristic evaluation $f(n) = g(n) + h(n)$ with Manhattan distance heuristics.
* **Reference:** [Red Blob Games: Introduction to A* Pathfinding](https://www.redblobgames.com/pathfinding/a-star/introduction.html)
* **Games Following This Approach:** *Dofus & Wakfu, Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Fire Emblem Series, Pokémon Series (Mystery Dungeon), Ragnarok Online, Sakura Wars, Road of Nogg (current baseline)*
* **Detailed Variations:**
  - *Dofus / FFT / Fire Emblem / Sakura Wars / Road of Nogg:* Evaluates node cost $f(n) = g(n) + h(n)$ using Manhattan distance heuristics on 2D square grids.
  - *Ragnarok Online:* Server-side A* pathfinding determines optimal movement vectors across static 2D cell grids for players and mobs, ensuring shortest routes around obstacles.

### Approach 1.2: Hexagonal Grid Axial/Cube Coordinate A*
Converts screen $(x,y)$ to cube $(x,y,z)$ coordinates ($x+y+z=0$) to evaluate hex neighbor paths.
* **Games Following This Approach:** *Wild Arms XF, Master of Monsters / Nectaris*
* **Detailed Variations:**
  - *Wild Arms XF / Master of Monsters:* Evaluates hex grid neighbor paths using axial coordinate distances.

### Approach 1.3: Free-Form Continuous Radius Pathing
Evaluates continuous 2D circle movement radii rather than discrete grid tiles.
* **Games Following This Approach:** *Phantom Brave / Makai Kingdom*
* **Detailed Variations:**
  - *Phantom Brave:* Moves characters across continuous 2D floor radii.

### Not Applicable / Absent
No pathfinding algorithm is used; units move along fixed lines, card paths, or preset battle slots.
* **Games:** *Shining Force Series, TearRing Saga & Berwick Saga, Triangle Strategy, Disgaea Series, Grandia Series & Octopath Traveler, Into the Breach, Breath of Fire Series, Treasure of the Rudras, Langrisser Series, Vandal Hearts Series, Knights in the Nightmare, Yggdra Union, Stella Deus: The Gate of Eternity, Energy Breaker & Feda: Emblem of Justice, Pokémon Series (Mainline), Chrono Trigger, Digimon World 3, Dragon Quest 9, MapleStory, Panzer Dragoon Saga*

---

## 2. Line-of-Sight & Raycasting Algorithms

Mathematical algorithms projecting rays or parabolic vectors between source and target cells to test obstacle collisions.

### Approach 2.1: Discrete 1D Rasterized Raycasting (Bresenham’s)
Rasterizes 1D grid cell rays between source and target; any obstacle in the cell array breaks Line of Sight.
* **Games Following This Approach:** *Dofus & Wakfu, Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Wild Arms XF, Knights in the Nightmare, Ragnarok Online*
* **Detailed Variations:**
  - *Dofus / FFT:* Discrete cell raycast checks if intermediate tiles contain line-of-sight blocking obstacles.
  - *Ragnarok Online:* Raycasting checks if a straight line between caster and target intersects any non-walkable/non-shootable cell (like a wall), canceling the spell if blocked.

### Approach 2.2: 3D Parabolic Arc Trajectories
Calculates archer arrow trajectories $z(t) = z_0 + v_z t - \frac{1}{2}gt^2$ over 3D terrain heightmaps.
* **Games Following This Approach:** *Tactics Ogre: Let Us Cling Together / Reborn, Final Fantasy Tactics*
* **Detailed Variations:**
  - *Tactics Ogre / FFT:* Parabolic arrow trajectory collides with terrain if obstacle height exceeds arc height.

### Not Applicable / Absent
No line-of-sight or raycasting algorithms exist; attacks target grid cells directly without ray testing.
* **Games:** *Fire Emblem Series, Disgaea Series, Shining Force Series, TearRing Saga & Berwick Saga, Triangle Strategy, Grandia Series & Octopath Traveler, Into the Breach, Breath of Fire Series, Treasure of the Rudras, Langrisser Series, Vandal Hearts Series, Phantom Brave / Makai Kingdom, Yggdra Union, Stella Deus: The Gate of Eternity, Master of Monsters / Nectaris, Energy Breaker & Feda: Emblem of Justice, Pokémon Series, Chrono Trigger, Digimon World 3, Dragon Quest 9, MapleStory, Panzer Dragoon Saga, Sakura Wars, Road of Nogg (current baseline)*

---

## 3. AI Decision-Making & Probability Models

Mathematical scoring models used by enemy AI to evaluate candidate actions per turn and probability curves for hit resolution.

### Approach 3.1: Utility AI Weighted Scoring Systems
Evaluates all legal candidate moves (Move + Action) and selects the move with the highest weighted score.
* **Games Following This Approach:** *Dofus & Wakfu, Triangle Strategy, Tactics Ogre: Let Us Cling Together / Reborn, Into the Breach, Fire Emblem Series, Disgaea Series, Pokémon Series (Trainer AI), Dragon Quest 9, Digimon World 3*
* **Detailed Variations:**
  - *Dofus / Triangle Strategy:* Evaluates weighted utility score:
    $$\text{Utility Score} = w_1 \cdot \text{Damage} + w_2 \cdot \text{KillBonus} - w_3 \cdot \text{APSpent} - w_4 \cdot \text{Risk}$$
  - *Pokémon Trainer AI:* Scores moves based on damage output, type effectiveness, status conditions, and switch risks.
  - *Dragon Quest 9:* AI evaluates spells and attacks based on current target weaknesses, HP thresholds, and preset behaviors ("Show No Mercy", "Focus on Healing").

### Approach 3.2: 1-RN vs 2-RN Probability Distribution Curves
Probability models translating displayed hit percentages into true combat outcomes.
* **Reference:** [Serenes Forest: True Hit (2-RN) Explanation](https://serenesforest.net/general/true-hit/)
* **Games Following This Approach:** *Fire Emblem Series, Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Disgaea Series*
* **Detailed Variations:**
  - *1-RN System (FFT, Tactics Ogre, Disgaea):* Generates 1 random number (1–100); displayed hit % equals true hit %.
  - *2-RN System (Fire Emblem FE6–FE13):* Averages 2 random numbers (1–100), creating an S-curve hit probability distribution.

### Approach 3.3: Influence Maps & Threat Heatmaps (Spatial AI)
AI generates a 2D grid heatmap assigning danger or utility scores to every tile based on overlapping enemy attack ranges, guiding squishy units to safe zones.
* **Games Following This Approach:** *Triangle Strategy, Into the Breach, Tactics Ogre: Let Us Cling Together / Reborn, Road of Nogg (current baseline)*
* **Detailed Variations:**
  - *Triangle Strategy / Road of Nogg:* AI iterates over all enemy units, calculates their max move + attack range, and increments the "threat score" of those tiles. Healer AI pathfinding strictly avoids tiles with threat scores $> 0$.


### Approach 3.4: Deterministic Lock vs Dodge Ratio Math
Calculates remaining AP/MP percentages when escaping adjacent enemies on a grid.
* **Reference:** [Dofus Wiki: Tackle and Dodge mechanics](https://dofuswiki.fandom.com/wiki/Tackle)
* **Games Following This Approach:** *Dofus & Wakfu*
* **Detailed Variations:**
  - *Dofus Tackle Formula:* Evaluates `Dodge / Lock` ratio:
    $$\text{AP/MP Ratio Remaining} = \frac{\text{Dodge} + 2}{2 \times (\text{Lock} + 2)}$$

### Approach 3.5: MMO Threat & Aggro Tables
Mathematical models determining enemy AI targets based on accumulated threat rather than static utility scoring.
* **Games Following This Approach:** *Ragnarok Online, MapleStory*
* **Detailed Variations:**
  - *Ragnarok Online:* AI heavily relies on simple state machines (Idle, Chase, Attack) targeting whichever entity generated the most threat (e.g. Provoke or whoever hit them last), combined with specific mob aggro modes (Looter, Assist, Aggressive).

### Not Applicable / Absent
Simpler deterministic rules or flat lookup tables without complex AI scoring or probability curves.
* **Games:** *Shining Force Series, TearRing Saga & Berwick Saga, Grandia Series & Octopath Traveler, Breath of Fire Series, Treasure of the Rudras, Langrisser Series, Vandal Hearts Series, Knights in the Nightmare, Phantom Brave / Makai Kingdom, Wild Arms XF, Yggdra Union, Stella Deus: The Gate of Eternity, Master of Monsters / Nectaris, Energy Breaker & Feda: Emblem of Justice, Chrono Trigger, Panzer Dragoon Saga, Sakura Wars*

---

## 4. Damage Calculation Models

Mathematical formulas governing how offensive and defensive stats interact to produce final HP loss.

### Approach 4.1: Flat Subtractive Damage Math ($ATK - DEF$)
The simplest and most transparent formula. Damage is a flat subtraction of Defense from Attack.
* **Games Following This Approach:** *Fire Emblem Series, Shining Force Series, Advance Wars, Road of Nogg (current baseline)*
* **Detailed Variations:**
  - *Fire Emblem:* $Damage = (Strength + Weapon Might) - (Defense + Terrain Bonus)$. Ensures players can easily calculate lethal damage in their head.

### Approach 4.2: Fractional & Multiplicative Scaling
Damage scales logarithmically or fractionally based on attacker and defender level ratios, preventing impenetrable armor walls where 0 damage is dealt.
* **References:** 
  - [Bulbapedia: Pokemon Damage Formula](https://bulbapedia.bulbagarden.net/wiki/Damage)
  - [iRO Wiki: Ragnarok Online Attack/Damage Calculation](https://irowiki.org/wiki/ATK)
* **Games Following This Approach:** *Pokémon Series, Final Fantasy Tactics, Tactics Ogre, Ragnarok Online, MapleStory*
* **Detailed Variations:**
  - *Pokémon Series:* Fractional level-based multiplier step function:
    $$Damage = \left(\frac{(\frac{2 \times Level}{5}) + 2 \times Power \times (\frac{A}{D})}{50} + 2\right) \times STAB \times Type \times RNG$$
  - *Ragnarok Online:* (Renewal Formula) $Damage = (WeaponATK \times SizeMod \times ElemMod) \times \frac{4000 + DEF}{4000 + (DEF \times 10)}$. Uses hard and soft DEF to create diminishing returns on armor stacking.
  - *MapleStory:* Main Stat + Sub Stat multiplier formula $(4 \times Main Stat + Sub Stat) \times \frac{Weapon Attack}{100}$ multiplied by skill %, crit %, and enemy PDR (Physical Damage Reduction) %.

### Approach 4.3: Fixed & Deterministic Damage (No Scaling)
Damage is an absolute flat number dictated entirely by the weapon, attack, or card used, with zero stat scaling or randomness.
* **Games Following This Approach:** *Into the Breach, Yggdra Union*
* **Detailed Variations:**
  - *Into the Breach:* 100% deterministic. A Mech Cannon always deals exactly 2 damage. Bumping into a mountain always deals exactly 1 damage.

### Approach 4.4: Weak-Point Positional Multipliers (3D ATB)
Damage calculation is multiplied significantly depending on the attacker's 3D positioning relative to the target's exposed weak points or armored sections.
* **Games Following This Approach:** *Panzer Dragoon Saga*
* **Detailed Variations:**
  - *Panzer Dragoon Saga:* The player can move in 360 degrees around enemies. Attacks from the front (armored) might deal 0 or 1 damage, while attacks from a designated safe/weak spot quadrant deal exponentially higher damage.

### Not Applicable / Absent
*(None — all games analyzed require a mathematical model for HP resolution).*

---

[Back to Master Index](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/tactical_rpg_turn_systems.md)

## Implementation Takeaways for Road of Nogg

- **To Decide / To Avoid:** (TBD)
### Master List Checklist Validation
*(Ensuring all 26 analyzed reference games + Road of Nogg baseline are accounted for in the sections above)*
- Fire Emblem Series (TBD)
- Final Fantasy Tactics (FFT) (TBD)
- Tactics Ogre (TBD)
- Disgaea Series (TBD)
- Shining Force Series (TBD)
- TearRing Saga & Berwick Saga (TBD)
- XCOM / XCOM 2 (TBD)
- Divinity: Original Sin 1 & 2 (TBD)
- Mario + Rabbids Kingdom Battle (TBD)
- Triangle Strategy (TBD)
- Dofus & Wakfu (TBD)
- Hoshigami: Ruining Blue Earth (TBD)
- Stella Deus: The Gate of Eternity (TBD)
- Energy Breaker (TBD)
- Breath of Fire Series (TBD)
- Treasure of the Rudras (TBD)
- Vandal Hearts Series (TBD)
- Feda: Emblem of Justice (TBD)
- Pokemon Series (TBD)
- Chrono Trigger (TBD)
- Digimon World 3 (TBD)
- Dragon Quest 9 (TBD)
- Ragnarok Online (TBD)
- MapleStory (TBD)
- World of Warcraft (TBD)
- Panzer Dragoon Saga (TBD)
- Sakura Wars (TBD)
- Road of Nogg (TBD)