# Playable Battle and Setup Flow Plan

Status: implemented and verified on 2026-07-25.

## Goal and defaults

Launching the battle scene first loads the existing animated sky background, then
opens the setup overlay above it. No map or monsters are spawned until Confirm is
pressed, so configuration starts quickly without an empty or visually plain screen.

The immediately playable defaults are:

| Setting | Default |
|---|---|
| Battle mode | CPU vs CPU |
| Map | Meadow |
| Team size | Four monsters per team |
| Team 1 | Envoy of Lightning, Gigasaurus, Healer Mage, Mage Dragon |
| Team 2 | Smoke Cloud, Megidos, Oracle of Ages, Snowzilla |
| Seed | 42 |

The setup overlay contains dropdowns for battle mode, map, each team preset,
and each of the four monster slots per team. Presets include the default team,
Random Balanced, and Custom. Selecting a preset fills the slot dropdowns, which
remain editable.

Confirm validates the setup, hides the overlay, creates a fresh simulator,
loads the selected map, assigns team controllers, spawns monsters and their
visuals, and starts round one.

## Runtime design

### Configuration and deployment

`BattleSetupConfig` is the pure-data boundary containing mode, map, seed, team
rosters, and controller type per team. UI produces it and simulation consumes
it through `BattleSetupFactory`.

`MapReferences` and `MonsterReferences` expose display-name catalogs. Every map
owns explicit Team 1 and Team 2 deployment slots; deployment coordinates are
not hardcoded in the presentation controller.

### Controller-neutral commands

AI decision generation and command execution are separated:

1. Start a unit turn.
2. Ask its team controller for a command.
3. Validate the command against authoritative state.
4. Execute it and record it in deterministic history.
5. End the turn.

AI and player controllers use the same command fields: move_path, action,
target_id, spell_set_index, and spell_index. Existing brains are the CPU
controller. The player controller waits for UI input.

### Player turn states

The initial interaction flow is:

UNIT_SELECTED -> MOVE_PREVIEW -> ACTION_MENU -> TARGETING -> CONFIRM

Cancel returns to the preceding state. The UI must show reachable tiles,
movement paths, valid targets, spell cooldown/range information, confirm,
cancel, wait, and end-turn actions.

### Cursor ownership

BattleCursorController owns a discrete grid intent with distinct modes for AI
turn indication, movement destination, player tile selection, and action
targeting. It never follows a model continuously between cells: movement snaps
it to the destination cell, while attack, spell, or heal intent snaps it to the
target cell.

Mouse is the first input target, but cursor APIs should remain compatible with
keyboard and gamepad navigation.

### Models

`MonsterVisualRegistry` maps monster references to authored scenes or models.
The Godot adapter creates a procedural placeholder when no authored mapping
exists.

## Delivery phases

1. Complete: setup configuration, presets, catalog accessors, and deployment slots.
2. Complete: dropdown setup overlay and deferred battle creation.
3. Complete: validated command execution shared by CPU and player controllers.
4. Complete: player movement, actions, spells, targets, confirm/cancel, and wait.
5. Complete: model registry, return-to-setup flow, and keyboard/gamepad-compatible
   cursor APIs.
6. Complete: map/preset, deterministic CPU, invalid-command, JSON replay,
   snapshot-restoration, and setup/UI lifecycle checks.

## Implemented first-slice decisions

- Duplicate monsters on one team: allowed, but discouraged in the UI.
- Player side: Team 1 only.
- Deployment: automatic.
- Team size: fixed 4v4.
- Random teams: generated from the battle seed.
- Models: placeholders allowed until authored mappings exist.
- Input: mouse first; keyboard/gamepad next.

Inventory, items, facing, manual deployment, local Player vs Player, and online
play are follow-up features rather than blockers for Player vs CPU.
