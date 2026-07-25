# Road of Nogg

A Tactical RPG project built with the Godot Engine.

## Overview
This repository contains the source code, game design documents, and assets for **Road of Nogg**. It features custom battle simulations, entity AI, A* pathfinding, line-of-sight algorithms, and various tactical RPG systems.

## Documentation
You can find detailed design documents outlining the game's mechanics, turn systems, elemental affinities, economy, and more in the `gamerefs/` directory.

## Built With
- [Godot Engine](https://godotengine.org/) 
- GDScript

## Runtime
- Default scene: `scenes/Battle25D.tscn`
- Canonical simulation: `src/battle_sim/BattleSimulator.gd`
- Presentation controller: `src/systems/BattlePresentationController.gd`
- Legacy rollback scene: `scenes/main.tscn`

## Verification
- Determinism: `.\Godot_v4.4-stable_win64.exe --headless --path . -s res://run_determinism_check.gd`
- Seeded battle smoke: `.\Godot_v4.4-stable_win64.exe --headless --path . -s res://run_battle.gd`

The GUT 9.4 command-line runner remains intentionally isolated after a reproducible Windows crash. See `docs/BACKLOG.md` before opting into another GUT investigation.
