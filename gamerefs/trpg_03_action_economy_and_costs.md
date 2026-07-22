# Aspect 03: Action Economy & Turn Cost Refunds

A comparative breakdown of action budgets, point pools, movement constraints, and turn cost refunds across TRPGs.

---

## 1. Action Budgeting & Point Pool Architecture

Core architecture defining how movement, attacks, spells, and items are budgeted during a unit turn.

### Approach 1.1: Fixed Unit Budget (1 Move + 1 Action / Swap)
A unit turn provides a fixed budget of up to 1 Movement + 1 Action (Attack, Spell, Item, or Swap). Unused movement is lost once an action resolves.
* **Games Following This Approach:** *Fire Emblem Series, Shining Force Series, TearRing Saga & Berwick Saga, Triangle Strategy, Breath of Fire Series, Treasure of the Rudras, Vandal Hearts Series, Feda: Emblem of Justice, Pokémon Series (Mainline & Spinoffs), Chrono Trigger, Digimon World 3, Dragon Quest 9, Road of Nogg (current baseline)*
* **Detailed Variations:**
  - *Fire Emblem:* Standard Move $\rightarrow$ Act per unit; unused movement is lost after acting unless *Canto* is active.
  - *Pokémon / Digimon World 3:* Select 1 move, item, or switch per turn.
  - *Chrono Trigger / Dragon Quest 9:* Classic JRPG structure where 1 turn = 1 action (Attack, Tech/Spell, Item).

### Approach 1.2: Dual Resource Pools (Separate AP and MP)
Movement and Actions draw from two separate resource pools per turn: Movement Points (MP) for tile traversal, and Action Points (AP) for spells and attacks.
* **Games Following This Approach:** *Dofus & Wakfu, Energy Breaker, Stella Deus: The Gate of Eternity*
* **Detailed Variations:**
  - *Dofus & Wakfu:* AP fuels spells/attacks; MP fuels tile moves (1 MP = 1 tile). Neither carries over to next turn.
  - *Stella Deus:* AP is shared, but movement and skill actions consume AP in separate sub-segments.

### Approach 1.3: Unified Action Point (AP / RAP) Pools
All actions (moving per tile, attacking, casting spells, defending) consume points from a single AP/RAP pool.
* **Games Following This Approach:** *Hoshigami: Ruining Blue Earth*
* **Detailed Variations:**
  - *Hoshigami:* RAP pool (0–100%). Moving tiles, attacking, or using Coins spends RAP %.

### Approach 1.4: Variable Action Costs & Turn Delay Refunds
Ending a turn early without performing a Move or Action refunds turn delay penalty, allowing the unit's next turn to arrive faster.
* **Games Following This Approach:** *Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn*
* **Detailed Variations:**
  - *FFT / Tactics Ogre:* Full turn (Move + Act) resets CT to 0. Move OR Act (only one) resets CT to 20. Wait (neither) resets CT to 40.

### Approach 1.5: Card & Skill-Gated Action Budgets
Action budgets and movement allowances are gated by selected cards or phase timers.
* **Games Following This Approach:** *Yggdra Union, Knights in the Nightmare*
* **Detailed Variations:**
  - *Yggdra Union:* Selected card dictates total movement points for all units on that turn.
  - *Knights in the Nightmare:* Real-time phase clock limits how many souls/weapon skills can be charged by the Wisp cursor.

### Approach 1.6: Commander & Multi-Unit Troop Budgets
Commanders move alongside multi-unit mercenary troop stacks, managing combined movement and attack budgets.
* **Games Following This Approach:** *Langrisser Series, Master of Monsters / Nectaris*
* **Detailed Variations:**
  - *Langrisser:* Commanders and up to 4–6 mercenary troops take individual actions during the commander's phase turn slot.

### Approach 1.7: Real-Time Skill Cooldowns & Animation Locks
Combat has no distinct "turn" pauses; action economy is strictly gated by skill cooldown timers, cast times, global cooldowns (GCD), and MP/SP costs.
* **Games Following This Approach:** *Ragnarok Online, MapleStory*
* **Detailed Variations:**
  - *Ragnarok Online:* Heavy reliance on SP pots and cast delay (After-Cast Delay) which gates how rapidly a player can spam actions.

### Not Applicable / Absent
* **Games:** *(None — all 28 analyzed games feature an action budgeting architecture).*

---

## 2. Turn Execution & Movement Flow

Rules governing whether units can move, act, and continue moving or re-organize commands.

### Approach 2.1: Strict Action Lock (Acting Ends Turn Immediately)
Taking an action (Attack, Spell, Item) immediately ends the unit's turn, forfeiting any remaining movement range.
* **Games Following This Approach:** *Shining Force Series, TearRing Saga & Berwick Saga, Triangle Strategy, Breath of Fire Series, Treasure of the Rudras, Vandal Hearts Series, Stella Deus: The Gate of Eternity, Master of Monsters / Nectaris, Energy Breaker & Feda: Emblem of Justice, Pokémon Series, Chrono Trigger, Digimon World 3, Dragon Quest 9, Road of Nogg (current baseline)*
* **Detailed Variations:**
  - *Shining Force / Road of Nogg:* Turn ends immediately upon confirming an attack.

### Approach 2.2: Post-Action Residual Movement (Canto Skills)
Specific units or skills allow resuming movement after taking a non-combat or combat action if movement points remain.
* **Games Following This Approach:** *Fire Emblem Series*
* **Detailed Variations:**
  - *Fire Emblem:* Mounted units with *Canto* can spend remaining movement tiles after attacking, healing, or trading.

### Approach 2.3: Free Command Stacking & Mid-Phase Re-Movement
Units can move, queue actions, execute attacks, and continue moving if movement range remains, without ending their phase turn.
* **Games Following This Approach:** *Disgaea Series, Into the Breach*
* **Detailed Variations:**
  - *Disgaea:* Players can move units, register attack commands, hit "Execute", and move unactivated units again before ending phase.
  - *Into the Breach:* Free grid movement per mech + 1 primary action.

### Approach 2.4: Real-Time Free Movement & Kiting
Characters can move freely around the map in real-time, interrupting their own movement instantly to attack or cast, then immediately resume moving (kiting).
* **Games Following This Approach:** *Ragnarok Online, MapleStory*
* **Detailed Variations:**
  - *Ragnarok Online:* "Hit-and-run" (kiting) is heavily utilized by archer/mage classes to avoid damage while attacking.

### Not Applicable / Absent
Turn movement flow is non-standard, driven by card decks, Wisp cursors, or turn timers.
* **Games:** *Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together / Reborn, Hoshigami: Ruining Blue Earth, Grandia Series & Octopath Traveler, Dofus & Wakfu, Langrisser Series, Knights in the Nightmare, Phantom Brave / Makai Kingdom, Wild Arms XF, Yggdra Union*

---

## 3. Multi-Turn Action Charging & Field Presence Limits

Rules governing actions that charge across multiple turns or units that expire from the map.

### Approach 3.1: Multi-Turn Charging & Cast Times
High-power actions require a charge turn or cast time before executing, or force a recharge rest turn after resolving.
* **Games Following This Approach:** *Pokémon Series, Final Fantasy Tactics, Ragnarok Online*
* **Detailed Variations:**
  - *Pokémon Series:* **Recharge moves** (*Hyper Beam*) force skipping the next turn; **Charging moves** (*Solar Beam*) require 1 turn of preparation before attacking.
  - *FFT:* High-level spells require multiple global CT ticks to channel before resolving on a target cell.
  - *Ragnarok Online:* Massive spells (e.g., Storm Gust, Asura Strike) require cast times that can take seconds. If the caster is hit during this window, the cast is interrupted and fails (unless they have Phenomenon Card / uninterruptible buffs).

### Approach 3.2: Confine Turn Expiration (Temporary Field Despawn)
Summoned units have a fixed turn presence limit on the field before automatically despawning.
* **Games Following This Approach:** *Phantom Brave / Makai Kingdom*
* **Detailed Variations:**
  - *Phantom Brave:* Units confined into objects stay active for 3 to 8 turns before returning to the netherworld.

### Not Applicable / Absent
No actions require multi-turn charging/recharging, and units remain on the battlefield until defeated.
* **Games:** *Fire Emblem Series, Tactics Ogre: Let Us Cling Together / Reborn, Hoshigami: Ruining Blue Earth, Triangle Strategy, Disgaea Series, Shining Force Series, TearRing Saga & Berwick Saga, Grandia Series & Octopath Traveler, Into the Breach, Dofus & Wakfu, Breath of Fire Series, Treasure of the Rudras, Langrisser Series, Vandal Hearts Series, Knights in the Nightmare, Wild Arms XF, Yggdra Union, Stella Deus: The Gate of Eternity, Master of Monsters / Nectaris, Energy Breaker & Feda: Emblem of Justice, Chrono Trigger, Digimon World 3, Dragon Quest 9, MapleStory, Road of Nogg (current baseline)*

---

[Back to Master Index](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/tactical_rpg_turn_systems.md)
