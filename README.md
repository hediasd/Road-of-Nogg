# Road of Nogg

A tactical RPG project built with Godot 4.4.

## Runtime

- Default scene: `scenes/Battle25D.tscn`
- Canonical simulation: `src/battle_sim/BattleSimulator.gd`
- Presentation controller: `src/systems/BattlePresentationController.gd`
- Legacy rollback scene: `scenes/main.tscn`
- Playable setup: CPU vs CPU or Player vs CPU, map/team dropdowns, seeded defaults

## Documentation

Start with the [documentation index](./docs/README.md). It links the current
architecture, game design, active playable-battle plan, development commands,
backlog, durable learnings, and comparative game references.

## Verification

Run checks according to the change risk described in
[`docs/POLICIES.md`](./docs/POLICIES.md). Verified commands and Windows-specific
safeguards are in [`docs/DEVELOPMENT.md`](./docs/DEVELOPMENT.md).

Common focused checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 -Script res://run_playable_battle_check.gd -ExpectedMarker PLAYABLE_BATTLE_CORE_OK -TimeoutSeconds 45 -QuitAfter 45 -LogStem playable_core
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 -Script res://run_setup_ui_check.gd -ExpectedMarker PLAYABLE_BATTLE_UI_OK -TimeoutSeconds 45 -QuitAfter 45 -LogStem setup_ui
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_docs.ps1
```

GUT remains intentionally isolated pending the investigation tracked in the
[backlog](./docs/BACKLOG.md).
