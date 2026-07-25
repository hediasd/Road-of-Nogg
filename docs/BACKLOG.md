# Backlog

Status: durable work outside the current task. Last reviewed: 2026-07-25.

Items belong here only when they are actionable, still relevant, and not already
covered by an active implementation task.

## Active direction

- **Playable battle setup and Player vs CPU:** Execute the phases in
  [`PLAYABLE_BATTLE_PLAN.md`](./PLAYABLE_BATTLE_PLAN.md), beginning with setup
  configuration, catalogs, deployment slots, and controller-neutral commands.
- **Player-ready cursor/input:** Preserve discrete tile intent and player
  ownership while adding movement preview, targeting, confirm/cancel, keyboard,
  and gamepad navigation.

## Simulation and architecture

- **Validated command executor:** Separate AI decision generation from command
  validation/execution. Record CPU and player commands in the same deterministic
  history format.
- **Replay continuation:** Add snapshot deserialization, state restoration,
  command playback, and resume verification. Serialization and replay snapshots
  already exist; loading does not.
- **Immutable command/event ledger:** Define a stable schema suitable for replay,
  debugging, and eventual network synchronization without ad hoc turn fields.
- **AI brain registry:** Replace `_resolveBrainClass()` branches with a validated,
  data-driven registry.
- **General stat modifiers:** Expand active effects beyond special-case bonuses
  so buffs/debuffs target named stats without mutating reference data.
- **Additional passive triggers:** Consider damage-taken, spell-cast, and
  tile-entered triggers after the command/effect contracts stabilize.
- **Terrain and trajectory:** Add movement costs, elevation rules, and parabolic
  projectile clearance using `heightBoard`.

## Presentation

- **Visual action queue:** Sequence animations without blocking the headless
  simulator and define cancellation/restart behavior.
- **Model registry:** Map monster references to authored scenes/models with the
  procedural placeholder as fallback.
- **Range and target overlays:** Visualize reachable tiles, paths, action ranges,
  valid targets, cooldowns, and invalid selections.
- **Screen-space tactical outline:** Investigate a secondary viewport or mask
  pipeline for silhouettes visible through terrain without drawing over a
  monster’s front faces. Treat this as a performance-sensitive rendering change.
- **Prototype shell decision:** Restore purpose-built scripts for
  `scenes/prototypes/Retro3DMapPrototype.tscn` and `Retro3DVisualTest.tscn`, or
  remove the inert shells in an explicitly approved cleanup.

## Testing and maintenance

- **Future GUT re-evaluation:** Keep GUT isolated until a later Godot or GUT
  release. Re-test the current Windows `0xC0000005` failure with the shadow
  project and 120-second watchdog before making it routine again.
- **Regression expansion:** Cover invalid player commands, map/preset catalogs,
  deployment validation, replay restoration, and intentional failure exit-code
  propagation with focused checks.
- **Factory path audit:** Verify explicit `preload()`/`load()` paths when scripts
  move; `class_name` does not repair an invalid resource path.

## Later gameplay

- Directional facing and backstab/cone rules.
- Inventory, consumable items, defend, and economy/shop systems.
- Manual deployment, local Player vs Player, and online PvP/co-op.
- Roster, spell, passive, and AI-behavior expansion after player controls work.

## Research

- Deepen the stats reference only when a concrete design question requires it.
- Add missing games to relevant aspect studies rather than duplicating the full
  game roster across every module.
