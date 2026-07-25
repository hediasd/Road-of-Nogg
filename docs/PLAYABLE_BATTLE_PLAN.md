# Playable Battle and Setup Flow Plan

Status: draft for approval on 2026-07-25.

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

Add a pure-data BattleSetupConfig containing mode, map, seed, team rosters, and
controller type per team. UI produces it and simulation consumes it.

MapReferences and MonsterReferences need display-name catalog methods. Every
map also needs explicit Team 1 and Team 2 deployment slots; coordinates must
not remain hardcoded in the presentation controller.

### Controller-neutral commands

Player control requires separating AI decision generation from command
execution:

1. Start a unit turn.
2. Ask its team controller for a command.
3. Validate the command against authoritative state.
4. Execute it and record it in deterministic history.
5. End the turn.

AI and player controllers use the same command fields: move_path, action,
target_id, spell_set_index, and spell_index. Existing brains become the CPU
controller. The player controller waits for UI input.

### Player turn states

The initial interaction flow is:

UNIT_SELECTED -> MOVE_PREVIEW -> ACTION_MENU -> TARGETING -> CONFIRM

Cancel returns to the preceding state. The UI must show reachable tiles,
movement paths, valid targets, spell cooldown/range information, confirm,
cancel, wait, and end-turn actions.

### Cursor ownership

BattleCursorController owns one cursor animation and distinct modes for AI turn
indication, player tile selection, and targeting. Changing owner or mode
cancels older animation. AI events may not move a player-owned cursor.

Mouse is the first input target, but cursor APIs should remain compatible with
keyboard and gamepad navigation.

### Models

Procedural placeholder monsters are sufficient for the first playable slice.
Authored models require a visual registry mapping each monster reference to a
scene or model resource, with the placeholder as fallback.

## Delivery phases

1. Add BattleSetupConfig, presets, catalog accessors, and map deployment slots.
2. Build the dropdown setup overlay and defer battle creation until Confirm.
3. Extract validated command execution from AI decision generation.
4. Implement player movement, actions, spells, targets, confirm/cancel, and wait.
5. Add the model registry, restart-to-setup flow, and input/accessibility polish.
6. Verify every map/preset, deterministic CPU play, invalid player commands,
   and replay snapshots containing setup plus player commands.

## Missing decisions

Recommended first-slice choices:

- Duplicate monsters on one team: allowed, but discouraged in the UI.
- Player side: Team 1 only.
- Deployment: automatic.
- Team size: fixed 4v4.
- Random teams: generated from the battle seed.
- Models: placeholders allowed until authored mappings exist.
- Input: mouse first; keyboard/gamepad next.

Inventory, items, facing, manual deployment, local Player vs Player, and online
play are follow-up features rather than blockers for Player vs CPU.
