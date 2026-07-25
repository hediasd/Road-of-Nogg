# Road of Nogg

A tactical RPG project built with Godot 4.4.

## Runtime

- Default scene: `scenes/Battle25D.tscn`
- Canonical simulation: `src/battle_sim/BattleSimulator.gd`
- Presentation controller: `src/systems/BattlePresentationController.gd`
- Legacy rollback scene: `scenes/main.tscn`

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
.\Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --rendering-method gl_compatibility --audio-driver Dummy -s res://run_determinism_check.gd
.\Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --rendering-method gl_compatibility --audio-driver Dummy -s res://run_cursor_check.gd
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_docs.ps1
```

GUT remains intentionally isolated pending the investigation tracked in the
[backlog](./docs/BACKLOG.md).
