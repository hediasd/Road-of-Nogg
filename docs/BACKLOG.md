# Road of Nogg — Backlog & Suggestions

This file tracks feature ideas, architectural suggestions, and potential improvements identified during development. 
The AI will proactively add suggestions here when observing technical debt, missing systems, or gameplay opportunities.

## Gameplay & Design
- **Directional Facing**: Entities could have a "facing" direction, allowing for backstab damage multipliers or cone-based AoE attacks.
- **Terrain Modifiers**: Expand the `terrainBoard` to include varied terrain types (mud, high ground) that affect movement costs and line-of-sight.
- **Stat System Deep-Dive (docs)**: Expand `trpg_14_stats_and_attributes.md` with a per-game breakdown of how each individual stat feeds into derived values (e.g., how exactly RO's AGI feeds into ASPD and Flee formulas, how FFT's Brave stat interacts with the reaction ability system, how Pokémon IVs/EVs interact with base species values). This is a large research task best done per-game.
- **Additional OnEvent Triggers**: Once the trigger system is live, add `ON_DAMAGE_TAKEN` (counter-attack or reflect passives), `ON_SPELL_CAST` (mana drain on cast, combo triggers), and `ON_TILE_STEPPED` (trap tiles, elemental terrain surfaces).
- **General Stat Buff/Debuff System**: Expand beyond ATK-only buffs ("Empower") to a generalized stat modifier layer stored in `activeEffects` (e.g. `{stat: "def", bonus: -2, duration: 3}`). Apply modifiers in damage calculations dynamically rather than mutating base stats.

## Engine & Architecture
- **Event Sourcing / Action History Log**: The current approach of tracking turn history via state variables (like `lastTurnDamageLog`) works for simple use cases, but scaling into time-travel mechanics (like the "Ages Ago" spell), battle replays, or network synchronization requires a centralized **Event History Log**. We should implement an immutable, turn-by-turn event ledger that records all actions, movements, and damage. This completely eliminates the need to clean up temporary state variables and natively supports rewinding/replaying the battle state deterministically.
	- **Animation Queueing**: As the visual adapter gets more complex, implement an asynchronous visual action queue so events can play out sequentially in the UI without blocking the headless engine.
- **Screen-Space X-Ray Tactical Outlines**: Implement a true "Always On Top" X-Ray outline for selected/hovered monsters that renders cleanly over terrain but perfectly behind the monster's front faces. 
  - *Why do it:* Standard object-attached shaders using mesh expansion clip into the terrain (if depth tested) or obscure the model itself (if depth disabled). A tactical RPG needs outlines visible behind walls without breaking the character model.
  - *How to do it:* Requires migrating from a per-object shader to a **Screen-Space Post-Processing Pipeline**. We must use a secondary `SubViewport` or write to a custom data channel/stencil buffer, rendering only the silhoutte of the targeted monster, blurring it, and compositing it back over the main camera feed.
  - *Impacts & Risks:* Major architectural change to the visual rendering tree (`Battle25D.tscn` / `GodotVisualAdapter`). We must be careful about performance overhead (extra viewport rendering) and ensure we can dynamically mask specific IDs (via visual layers/cull masks) so only the selected unit gets the outline.

## Code Quality & Cleanup
- **Archived Retro3D Prototype Shells**: `scenes/prototypes/Retro3DMapPrototype.tscn` and `Retro3DVisualTest.tscn` are inert placeholders because their original scripts were already absent. Restore purpose-built scripts or remove the shells in a future explicitly approved cleanup.
- **Clean Up Factory Preloads**: Ensure all `preload()` references match the actual folder structure strictly, even though Godot's `class_name` currently masks path inaccuracies.
- **Data-Driven AI Brain Registry**: Replace `BattleSimulator._resolveBrainClass()`
  hardcoded class-name branches with a validated registry or factory. Monster
  reference data should select a registered brain without requiring simulator
  code changes for every new AI type.
- **Complete Simulation Regression Matrix**: Expand GUT coverage for seeded
  replay determinism, movement and occupied tiles, line of sight, elemental
  damage, turn order and status expiration, battle termination, and serialized
  continuation. Retain an intentional-failure smoke fixture to verify nonzero
  CLI exit-code propagation.
- **Future GUT 9.4 Re-evaluation**: Keep GUT isolated until a future maintenance
  pass. Its supported CLI currently crashes Godot 4.4 on Windows with
  `0xC0000005` before producing output, including in a shadow project with a
  valid global class cache and isolated user data. Re-test with another Godot
  patch version or GUT release, preserve the 120-second watchdog, and only then
  re-enable the default headless test command.

## Future Milestones
- **Visual Integration**: Connect the Battle Simulator and its events to the actual Godot Visuals/UI, rendering sprites, grid selection, and spell effects.
- **Shop & Economy Systems**: Implement the underlying logic and interfaces for the economy based on the `gamerefs/trpg_11_shop_and_economy_systems.md` documentation.
- **Roster Expansion**: Add additional Monsters, diverse Spells, and specialized AI Brains (e.g., assassins, buffers) to flesh out the game.
- **Documentation Refinement**: Continue to iterate and expand the `gamerefs/` game design specifications and AI architecture guidelines. Add analysis for *Threads of Fate*, *Suikoden*, *Vagrant Story*, and *Phantasy Star* across all 16 aspect reference modules and update `tactical_rpg_turn_systems.md`.
- **Parabolic Trajectory / Arcs**: Implement an algorithm to calculate height arcs for projectiles (arrows, items) crossing the `heightBoard` to verify vertical line-of-sight clearance over obstacles.
- **Player-Controlled Teams (PvE)**: Implement input-handling logic allowing real players to select movement paths, spells, and targets instead of relying purely on the AI Brains.
- **Online Multiplayer (PvP/Co-op)**: Expand the architecture to support networked battles (Player vs Player over the internet), ensuring the state machine can sync inputs and simulation deterministically across clients.
- **Savestates / Serialization**: Implement a system to serialize the entire `BattleState` into JSON (and deserialize back), allowing for battle replays, suspend-save, and mid-battle reloading.
