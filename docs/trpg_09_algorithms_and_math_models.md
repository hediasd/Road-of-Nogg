# Aspect 09: Algorithms & Mathematical Models

A technical reference detailing algorithms, pathfinding models, line-of-sight formulas, and AI decision systems used across Tactical & Turn-Based RPGs.

---

## 1. Grid Pathfinding Algorithms

Standard graph search algorithms used to calculate shortest path movement across square, hex, or free-form terrain grids.

### Approach 1.1: 2D Square Grid A* Pathfinding
Finds the shortest path on a weighted 2D grid array using heuristic evaluation $f(n) = g(n) + h(n)$ with Manhattan distance heuristics.
* **Games Following This Approach:** *Dofus & Wakfu, Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Fire Emblem Series, Pokémon Series (Mystery Dungeon), Road of Nogg (current baseline)*
* **Detailed Variations:**
  - *Dofus / FFT / Fire Emblem / PMD / Road of Nogg:* Evaluates node cost $f(n) = g(n) + h(n)$ using Manhattan distance heuristics on 2D square grids.

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
* **Games:** *Shining Force Series, TearRing Saga & Berwick Saga, Triangle Strategy, Disgaea Series, Grandia Series & Octopath Traveler, Vanguard Bandits, Into the Breach, Breath of Fire Series, Treasure of the Rudras, Langrisser Series, Vandal Hearts Series, Knights in the Nightmare, Front Mission Series, Yggdra Union, Stella Deus: The Gate of Eternity, Resonance of Fate, Energy Breaker & Feda: Emblem of Justice, Pokémon Series (Mainline)*

---

## 2. Line-of-Sight & Raycasting Algorithms

Mathematical algorithms projecting rays or parabolic vectors between source and target cells to test obstacle collisions.

### Approach 2.1: Discrete 1D Rasterized Raycasting (Bresenham’s)
Rasterizes 1D grid cell rays between source and target; any obstacle in the cell array breaks Line of Sight.
* **Games Following This Approach:** *Dofus & Wakfu, Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Wild Arms XF, Knights in the Nightmare*
* **Detailed Variations:**
  - *Dofus / FFT:* Discrete cell raycast checks if intermediate tiles contain line-of-sight blocking obstacles.

### Approach 2.2: 3D Parabolic Arc Trajectories
Calculates archer arrow trajectories $z(t) = z_0 + v_z t - \frac{1}{2}gt^2$ over 3D terrain heightmaps.
* **Games Following This Approach:** *Tactics Ogre: Let Us Cling Together / Reborn, Final Fantasy Tactics*
* **Detailed Variations:**
  - *Tactics Ogre / FFT:* Parabolic arrow trajectory collides with terrain if obstacle height exceeds arc height.

### Approach 2.3: Quadratic Bezier Curve Calculations
Calculates quadratic Bezier curves for Hero Action movement paths.
* **Games Following This Approach:** *Resonance of Fate*
* **Detailed Variations:**
  - *Resonance of Fate:* Calculates Bezier curves for running firing runs.

### Not Applicable / Absent
No line-of-sight or raycasting algorithms exist; attacks target grid cells directly without ray testing.
* **Games:** *Fire Emblem Series, Disgaea Series, Shining Force Series, TearRing Saga & Berwick Saga, Triangle Strategy, Grandia Series & Octopath Traveler, Vanguard Bandits, Into the Breach, Breath of Fire Series, Treasure of the Rudras, Langrisser Series, Vandal Hearts Series, Phantom Brave / Makai Kingdom, Front Mission Series, Yggdra Union, Stella Deus: The Gate of Eternity, Master of Monsters / Nectaris, Energy Breaker & Feda: Emblem of Justice, Pokémon Series, Road of Nogg (current baseline)*

---

## 3. AI Decision-Making & Probability Models

Mathematical scoring models used by enemy AI to evaluate candidate actions per turn and probability curves for hit resolution.

### Approach 3.1: Utility AI Weighted Scoring Systems
Evaluates all legal candidate moves (Move + Action) and selects the move with the highest weighted score.
* **Games Following This Approach:** *Dofus & Wakfu, Triangle Strategy, Tactics Ogre: Let Us Cling Together / Reborn, Into the Breach, Fire Emblem Series, Disgaea Series, Front Mission Series, Pokémon Series (Trainer AI)*
* **Detailed Variations:**
  - *Dofus / Triangle Strategy:* Evaluates weighted utility score:
    $$\text{Utility Score} = w_1 \cdot \text{Damage} + w_2 \cdot \text{KillBonus} - w_3 \cdot \text{APSpent} - w_4 \cdot \text{Risk}$$
  - *Pokémon Trainer AI:* Scores moves based on damage output, type effectiveness, status conditions, and switch risks.

### Approach 3.2: 1-RN vs 2-RN Probability Distribution Curves
Probability models translating displayed hit percentages into true combat outcomes.
* **Games Following This Approach:** *Fire Emblem Series, Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Disgaea Series*
* **Detailed Variations:**
  - *1-RN System (FFT, Tactics Ogre, Disgaea):* Generates 1 random number (1–100); displayed hit % equals true hit %.
  - *2-RN System (Fire Emblem FE6–FE13):* Averages 2 random numbers (1–100), creating an S-curve hit probability distribution.

### Approach 3.3: Multi-Variable Multiplicative Damage Math
Evaluates damage using fractional multiplication step-by-step with integer truncation.
* **Games Following This Approach:** *Pokémon Series*
* **Detailed Variations:**
  - *Pokémon Damage Formula:* Evaluates level, move power, stat ratios $(A/D)$, STAB (1.5x), type effectiveness, weather, and 85–100% random variance.

### Approach 3.4: Deterministic Lock vs Dodge Ratio Math
Calculates remaining AP/MP percentages when escaping adjacent enemies on a grid.
* **Games Following This Approach:** *Dofus & Wakfu*
* **Detailed Variations:**
  - *Dofus Tackle Formula:* Evaluates `Dodge / Lock` ratio:
    $$\text{AP/MP Ratio Remaining} = \frac{\text{Dodge} + 2}{2 \times (\text{Lock} + 2)}$$

### Not Applicable / Absent
Simpler deterministic rules or flat lookup tables without complex AI scoring or probability curves.
* **Games:** *Shining Force Series, TearRing Saga & Berwick Saga, Grandia Series & Octopath Traveler, Vanguard Bandits, Breath of Fire Series, Treasure of the Rudras, Langrisser Series, Vandal Hearts Series, Knights in the Nightmare, Phantom Brave / Makai Kingdom, Wild Arms XF, Yggdra Union, Stella Deus: The Gate of Eternity, Resonance of Fate, Master of Monsters / Nectaris, Energy Breaker & Feda: Emblem of Justice, Road of Nogg (current baseline)*

---

[Back to Master Index](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/tactical_rpg_turn_systems.md)
