# Development and Verification

Status: current for Godot 4.4 on Windows. Last verified: 2026-07-27.

This is the executable workflow reference. Start with a clean understanding of
the working tree, but preserve unrelated user changes.

## Reliable Godot check runner

Use `scripts/run_godot_check.ps1` rather than relying on an interactive
PowerShell launch of the non-console Godot executable. The helper starts one
hidden process, captures stdout/stderr and a Godot log under the system temp
directory, waits for the real exit code, enforces a timeout, and kills only the
process object it launched if that timeout expires. `-ScriptArgs` forwards
values after Godot's `--`, which is how the test tier is selected below.

```powershell
# Fast tier: every tests/unit/*.gd file, one shared process, target < 10s
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 `
  -Script res://tests/run_tests.gd -ScriptArgs unit `
  -ExpectedMarker TESTS_OK -TimeoutSeconds 30 -QuitAfter 30 `
  -LogStem tests_unit

# Heavier tier: tests/integration/*.gd (full BattleSimulator, seconds each)
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 `
  -Script res://tests/run_tests.gd -ScriptArgs integration `
  -ExpectedMarker TESTS_OK -TimeoutSeconds 60 -QuitAfter 60 `
  -LogStem tests_integration

# Scene tier: tests/scene/*.gd, needs a live SceneTree/presentation
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 `
  -Script res://tests/run_tests.gd -ScriptArgs scene `
  -ExpectedMarker TESTS_OK -TimeoutSeconds 60 -QuitAfter 60 `
  -LogStem tests_scene

# Everything (what scripts/hooks/pre-push runs)
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 `
  -Script res://tests/run_tests.gd -ScriptArgs all `
  -ExpectedMarker TESTS_OK -TimeoutSeconds 90 -QuitAfter 90 `
  -LogStem tests_all

# Default-scene parse/startup smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 `
  -QuitAfter 5 -TimeoutSeconds 30 -LogStem default_scene

# Seeded full-battle demo (not a test — prints a console battle log)
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_godot_check.ps1 `
  -Script res://scripts/demo_battle.gd -ExpectedMarker "Battle complete!" `
  -TimeoutSeconds 60 -QuitAfter 60 -LogStem battle

# Documentation integrity
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_docs.ps1
```

Choose checks from the risk matrix in [`POLICIES.md`](./POLICIES.md). A docs-only
change does not require starting Godot.

Every test is a `.gd` file under `tests/unit/`, `tests/integration/`, or
`tests/scene/`, named `test_<behavior>.gd`, with one behavior per file. See
`tests/TestCase.gd` for the assertion/fixture contract and
`tests/TestRunner.gd` for discovery and the naming/placement rules it enforces
on every run regardless of which tier is selected.

**Known limitation:** `tests/scene/test_capsule_features.gd` reports a missing
`TESTS_OK` marker on this Windows host even when every one of its assertions
passes, and — because `scene`-tier tests share one Godot process — can swallow
the other scene tests' output in the same run. This means `-ScriptArgs all`
(and therefore `scripts/hooks/pre-push`) currently fails on every run
regardless of real outcomes once that test executes. Corroborate with
`-ScriptArgs unit` and `-ScriptArgs integration` (both reliable) before
concluding there is a real regression. Full details and what has already been
ruled out are in [`BACKLOG_LONGTERM.md`](../BACKLOG_LONGTERM.md) under
"Tooling."

## Git hooks

Run once per clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install_hooks.ps1
```

This points `core.hooksPath` at the tracked hooks in `scripts/hooks/`:
`pre-commit` runs the `unit` tier, `pre-push` runs `all` (see the known
limitation above). Both skip with exit 0 and a clear message if the bundled
Godot binary is missing, so a docs-only contributor is never blocked. Bypass
intentionally with `git commit --no-verify` / `git push --no-verify`.

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