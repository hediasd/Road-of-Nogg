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
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 -Script res://tests/run_tests.gd -ScriptArgs unit -ExpectedMarker TESTS_OK -TimeoutSeconds 30 -QuitAfter 30 -LogStem tests_unit
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 -Script res://tests/run_tests.gd -ScriptArgs integration -ExpectedMarker TESTS_OK -TimeoutSeconds 60 -QuitAfter 60 -LogStem tests_integration
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_docs.ps1
```

Run `scripts/install_hooks.ps1` once per clone to run the `unit` tier
automatically before each commit and the full suite before each push. Every
test lives under `tests/unit/`, `tests/integration/`, or `tests/scene/`; see
[`docs/DEVELOPMENT.md`](./docs/DEVELOPMENT.md) for the full command set, the
tier definitions, and a known Windows output-capture limitation affecting the
`scene` tier.

GUT remains intentionally isolated pending the investigation tracked in the
[backlog](./docs/BACKLOG.md).
