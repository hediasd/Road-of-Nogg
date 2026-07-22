# Aspect 01: Turn Flow & Initiative Order

A comparative architectural analysis of how turn progression, turn ordering, and initiative cycles are structured across Tactical & Turn-Based RPGs.

---

## 1. Primary Turn Flow & Activation Structure

High-level architecture governing how the overall battle engine sequences turns across teams and individual units.

### Approach 1.1: Army-Wide Team Phases (Player Phase $\rightarrow$ Enemy Phase)
Entire armies act sequentially in designated team phases. During a team's phase, player or enemy units can act in any desired order.
* **Games Following This Approach:** *Fire Emblem Series, Disgaea Series, Langrisser Series, Vandal Hearts Series, Front Mission Series, Feda: Emblem of Justice*
* **Detailed Variations:**
  - *Fire Emblem / Vandal Hearts:* Move + Act per unit; once all units finish or player ends phase, turn passes to Enemy Phase.
  - *Disgaea Series:* Allows free movement and command queuing. Players can hit "Execute" mid-phase to resolve actions while keeping the phase active.
  - *Langrisser Series:* Phase-based, but commanders and their hired troop units take actions together during the commander's phase slot.

### Approach 1.2: Continuous Tick-Based Individual Initiative (CT / WT Timeline)
A global initiative clock ticks continuously (`CT += Speed` or `WT -= 1`). When an individual unit reaches the activation threshold (e.g. 100 CT or 0 WT), it acts immediately.
* **Games Following This Approach:** *Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Triangle Strategy, Dofus & Wakfu, Stella Deus: The Gate of Eternity, Wild Arms XF*
* **Detailed Variations:**
  - *Final Fantasy Tactics / Tactics Ogre:* Units accumulate CT based on Speed. Skipping move or action refunds CT/WT delay.
  - *Dofus & Wakfu:* Timeline queue where initiative stat sorts individual unit turns in real-time online grid encounters.
  - *Triangle Strategy:* Displays a visible linear turn bar at the bottom of the screen showing upcoming unit turns.

### Approach 1.3: Round-Based Speed & Agility Queueing
At the start of a combat round, all active entities are sorted into a fixed turn queue based on their Speed/Agility stat. Each entity acts once per round in sorted order.
* **Games Following This Approach:** *Shining Force Series, Breath of Fire Series, Treasure of the Rudras, Vanguard Bandits, Energy Breaker, Road of Nogg (current baseline)*
* **Detailed Variations:**
  - *Shining Force / Road of Nogg:* Strictly 1 action per unit per round in sorted order.
  - *Breath of Fire Series:* Uses round-based speed sorting, but extremely fast units gain an extra **EX-Turn** at the very end of the round.

### Approach 1.4: Dynamic Action Point Accumulation & Delay
Units accumulate action points dynamically. Taking actions consumes points from a pool, directly delaying the arrival of the unit's next turn.
* **Games Following This Approach:** *Hoshigami: Ruining Blue Earth*
* **Detailed Variations:**
  - *Hoshigami:* Uses Ready Action Points (RAP). Moving 1 tile or casting a spell costs a percentage of RAP; ending turns early lets the next turn arrive much faster.

### Approach 1.5: Alternating Unit Movements & Ratio Phase
Player and enemy sides alternate moving 1 unit at a time until all units have taken their turn.
* **Games Following This Approach:** *Berwick Saga, Master of Monsters / Nectaris*
* **Detailed Variations:**
  - *Berwick Saga:* Calculates a unit ratio based on total army sizes (e.g., if player has 10 units and enemy has 5, player moves 2 units for every 1 enemy unit).

### Approach 1.6: Action Timeline Command Queues (COM $\rightarrow$ ACT)
Units move along a linear timeline divided into a Wait phase, Command selection (COM) node, and Action execution (ACT) node.
* **Games Following This Approach:** *Grandia Series, Octopath Traveler*
* **Detailed Variations:**
  - *Grandia / Octopath:* Attacks landing while a unit is between COM and ACT can delay or cancel the unit's upcoming action.

### Approach 1.7: Priority Tier & Speed-Bracketed Resolution
Units select actions simultaneously (or individually), which are sorted and resolved during the turn cycle by **Action Priority Brackets** first, then by **Speed Stat**, with tie-breakers resolved by random rolls.
* **Games Following This Approach:** *Pokémon Series (Mainline & Mystery Dungeon)*
* **Detailed Variations:**
  - *Pokémon Mainline:* Each selected move belongs to a Priority Bracket (e.g. +5 Protect, +4 Pursuit, +1 Quick Attack, 0 Normal, -6 Roar). Higher priority moves resolve first; within the same priority tier, higher Speed acts first.
  - *Pokémon Mystery Dungeon:* In grid dungeon exploration, movement and moves resolve step-by-step; Speed boosts grant 2x or 3x movement steps per turn.

### Approach 1.8: Real-Time Action-Oriented Clocks & Bezier Runs
Incorporates real-time cursor movement, phase clocks, or real-time path running to dictate when actions resolve.
* **Games Following This Approach:** *Knights in the Nightmare, Resonance of Fate*
* **Detailed Variations:**
  - *Knights in the Nightmare:* A real-time phase clock counts down while the player controls a Wisp cursor over the grid to charge souls and cast weapon skills.
  - *Resonance of Fate:* Characters spend Hero Points to run along Bezier paths in real-time while firing weapons.

### Approach 1.9: Object Summoning & Temporary Field Presence
Units are summoned into environmental objects on the map and remain active on the field for a fixed number of turns before disappearing.
* **Games Following This Approach:** *Phantom Brave / Makai Kingdom*
* **Detailed Variations:**
  - *Phantom Brave:* Units are "Confined" into items (trees, rocks, weeds) for 3–8 turns based on class properties.

### Approach 1.10: Deterministic & Card-Gated Telegraphed Initiatives
Turn order and enemy actions are telegraphed at the start of the turn or gated by selected cards.
* **Games Following This Approach:** *Into the Breach, Yggdra Union*
* **Detailed Variations:**
  - *Into the Breach:* Enemies telegraph attacks at round start; player acts freely to manipulate enemy positions before attacks resolve.
  - *Yggdra Union:* The card selected at turn start dictates movement budget and combat skill availability for that turn.

### Not Applicable / Absent
* **Games:** *(None — all 26 analyzed games feature a primary turn flow paradigm).*

---

## 2. Mid-Turn Queue Interruption & Delay Mechanics

Mechanics that modify, delay, advance, or cancel an entity's position in the turn queue mid-encounter.

### Approach 2.1: Action Conserved CT/WT Turn Refunds
Skipping movement or actions during a turn refunds a percentage of turn delay, advancing the unit's next turn on the queue.
* **Games Following This Approach:** *Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn*
* **Detailed Variations:**
  - *FFT / Tactics Ogre:* Skipping move or action refunds 20% to 40% CT/WT.

### Approach 2.2: Action Cancellation & Timeline Pushback
Attacks landing on an enemy while they are channeling an action cancel the action or push their turn icon backward along the queue.
* **Games Following This Approach:** *Grandia Series, Octopath Traveler*
* **Detailed Variations:**
  - *Grandia:* Critical attacks landing between COM and ACT cancel the enemy action.
  - *Octopath:* Shield Break stuns the enemy and pushes their turn to the end of the next round.

### Approach 2.3: Stun & Fatigue Overheat Turn Skips
Taking heavy hits or accumulating heat/fatigue forces a unit to skip its upcoming turn cycle entirely.
* **Games Following This Approach:** *Vanguard Bandits, Octopath Traveler, Pokémon Series (Flinch / Freeze / Sleep / Recharge)*
* **Detailed Variations:**
  - *Vanguard Bandits:* 100 Fatigue Points (FP) causes Overheat Stun.
  - *Pokémon Series:* Moves like *Hyper Beam* force skipping next turn; status conditions (*Sleep*, *Freeze*) or flinches skip turn actions.

### Not Applicable / Absent
No mechanics exist to interrupt, refund, or delay turn queue positions mid-battle; turn sequence strictly follows phase or round order.
* **Games:** *Fire Emblem Series, Shining Force Series, Disgaea Series, TearRing Saga & Berwick Saga, Into the Breach, Hoshigami: Ruining Blue Earth, Dofus & Wakfu, Breath of Fire Series, Treasure of the Rudras, Langrisser Series, Vandal Hearts Series, Knights in the Nightmare, Phantom Brave / Makai Kingdom, Front Mission Series, Wild Arms XF, Yggdra Union, Stella Deus: The Gate of Eternity, Resonance of Fate, Master of Monsters / Nectaris, Energy Breaker & Feda: Emblem of Justice, Road of Nogg (current baseline)*

---

[Back to Master Index](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/tactical_rpg_turn_systems.md)
