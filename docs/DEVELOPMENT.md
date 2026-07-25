# Development and Verification

Status: current for Godot 4.4 on Windows. Last verified: 2026-07-25.

This is the executable workflow reference. Start with a clean understanding of
the working tree, but preserve unrelated user changes.

## Common checks

Run from the repository root with the bundled Godot executable:

```powershell
# Deterministic simulation and replay snapshot
.\Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --rendering-method gl_compatibility --audio-driver Dummy -s res://run_determinism_check.gd

# Tactical cursor ownership and placement
.\Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --rendering-method gl_compatibility --audio-driver Dummy -s res://run_cursor_check.gd

# Seeded battle smoke
.\Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --rendering-method gl_compatibility --audio-driver Dummy -s res://run_battle.gd

# Default-scene parse/startup smoke
.\Godot_v4.4-stable_win64.exe --headless --disable-crash-handler --path . --quit-after 5 --rendering-method gl_compatibility --audio-driver Dummy

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

- Bound Godot and helper processes; do not allow a diagnostic to wait forever.
- Prefer direct Godot invocation and `$LASTEXITCODE` for short checks.
  Redirected `Start-Process` objects can expose a null or stale exit code.
- Run from the repository root and pass `--path .`; older PowerShell handling of
  `Start-Process -ArgumentList` can split paths containing spaces.
- Treat `--editor --quit` as an import diagnostic, not the primary runtime
  smoke test. It can hit progress-dialog or message-queue errors during import.
- If a patch helper fails or stalls, inspect the target before retrying. On this
  workspace a failed helper can have partially written the file. Use an exact,
  asserted replacement only after confirming the failure, then review the diff.
- Keep native process windows hidden unless the user needs to interact with
  them. Read captured stdout, stderr, and the final exit code.
- Workspace edit permission does not imply permission for external executables
  or Git index writes; honor the permission boundary shown by the tool.

## Completion checklist

1. Inspect `git status` and the focused diff.
2. Run the checks required by the affected risk.
3. Confirm output contains no parser errors, failed assertions, or timeouts.
4. Run `git diff --check`.
5. Stage only task-owned files and report any intentionally uncommitted work.
