# Development and Verification

Status: current for Godot 4.4 on Windows. Last verified: 2026-07-25.

This is the executable workflow reference. Start with a clean understanding of
the working tree, but preserve unrelated user changes.

## Reliable Godot check runner

Use `scripts/run_godot_check.ps1` rather than relying on an interactive
PowerShell launch of the non-console Godot executable. The helper starts one
hidden process, captures stdout/stderr and a Godot log under the system temp
directory, waits for the real exit code, enforces a timeout, and kills only the
process object it launched if that timeout expires.

```powershell
# Playable setup, all map/preset combinations, commands, JSON replay and restore
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 `
  -Script res://run_playable_battle_check.gd `
  -ExpectedMarker PLAYABLE_BATTLE_CORE_OK -TimeoutSeconds 45 -QuitAfter 45 `
  -LogStem playable_core

# Setup overlay, deferred loading, Player vs CPU, cursor ownership, return to setup
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 `
  -Script res://run_setup_ui_check.gd `
  -ExpectedMarker PLAYABLE_BATTLE_UI_OK -TimeoutSeconds 45 -QuitAfter 45 `
  -LogStem setup_ui

# Deterministic simulation and replay snapshot
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 `
  -Script res://run_determinism_check.gd `
  -ExpectedMarker DETERMINISM_OK -TimeoutSeconds 60 -QuitAfter 60 `
  -LogStem determinism

# Tactical cursor ownership and placement
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 `
  -Script res://run_cursor_check.gd `
  -ExpectedMarker CURSOR_CONTROLLER_OK -TimeoutSeconds 45 -QuitAfter 45 `
  -LogStem cursor

# Default-scene parse/startup smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 `
  -QuitAfter 5 -TimeoutSeconds 30 -LogStem default_scene

# Seeded full-battle smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 `
  -Script res://run_battle.gd -ExpectedMarker "Battle complete!" `
  -TimeoutSeconds 60 -QuitAfter 60 -LogStem battle

# Documentation integrity
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_docs.ps1
```

Choose checks from the risk matrix in [`POLICIES.md`](./POLICIES.md). A docs-only
change does not require starting Godot.

## GUT isolation

GUT 9.4 currently reaches a reproducible Windows access violation before useful
runner output in this project. Routine verification must not invoke it.

Use `run_headless_tests.ps1 -ForceGut` only when deliberately re-evaluating the
GUT issue. Keep the shadow-project isolation and a 120-second watchdog. The
follow-up is tracked in [`BACKLOG.md`](./BACKLOG.md).

## Windows execution safeguards

- Bound every Godot/helper process. `run_godot_check.ps1` defaults to 60 seconds
  and terminates only its own process object after a timeout.
- Do not treat `$LASTEXITCODE` from a direct interactive launch of the bundled
  Windows Godot binary as completion evidence. The host can return before the
  detached process finishes. Require the helper's waited exit code and expected
  success marker for script checks.
- Run from the repository root and pass `--path .`; PowerShell argument handling
  can split absolute paths containing spaces.
- Give every script check a unique success marker. A fail-safe `--quit-after`
  prevents a parser error from leaving its `SceneTree` alive, but the marker is
  what proves the test body completed.
- Focused `SceneTree` scripts on this Godot build can report resource-cache
  warnings during immediate engine shutdown after their success marker. The
  helper still prints them but ignores only the known
  `resources still in use at exit` error for pass/fail classification.
- Treat `--editor --quit` as an import diagnostic, not the primary runtime
  smoke. It can hit progress-dialog or message-queue errors during import.
- If a patch helper fails or stalls, inspect the target before retrying. A failed
  helper can partially write a file. Use an exact, asserted replacement only
  after confirming the failure, then review the diff.
- Keep native process windows hidden unless the user needs to interact with
  them. Keep reusable logs in the temp directory rather than tracked source.
- Workspace edit permission does not imply permission for external executables
  or Git index writes; honor the permission boundary shown by the tool.

## Completion checklist

1. Inspect `git status` and the focused diff.
2. Run the checks required by the affected risk through the reliable helper.
3. Confirm the waited exit code, expected marker, and captured log contain no
   parser errors, failed assertions, unexpected runtime errors, or timeouts.
4. Run `git diff --check` and the documentation audit.
5. Stage only task-owned files and report any intentionally uncommitted work.