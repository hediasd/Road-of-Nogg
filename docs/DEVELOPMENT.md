# Development and Verification

Status: current for Godot 4.4 on Windows. Last verified: 2026-07-29.

This is the executable workflow reference. Start with a clean understanding of
the working tree, but preserve unrelated user changes.

## No automated test suite right now

The previous test suite (unit/integration/scene tiers), the GUT addon, the
`scripts/run_godot_check.ps1` / `scripts/check_docs.ps1` runners, and the git
hooks that invoked them were all removed to be rebuilt fresh. There is
currently no automated way to verify a change — confirm behavior by launching
the game and exercising the affected path manually.

`scripts/demo_battle.gd` remains available as a manual, non-automated demo: a
seeded 4v4 console battle. Run it directly with Godot, e.g.:

```powershell
.\Godot_v4.4-stable_win64.exe --headless --path . -s res://scripts/demo_battle.gd
```

`scenes/prototypes/BattleSimPrototype.tscn` is the equivalent manual demo as a
runnable scene.

## Windows execution safeguards

These apply whenever you launch the bundled Godot binary manually, automated
suite or not:

- Do not treat `$LASTEXITCODE` from a direct interactive launch of the bundled
  Windows Godot binary as completion evidence. The host can return before the
  detached process finishes.
- Run from the repository root and pass `--path .`; PowerShell argument handling
  can split absolute paths containing spaces.
- Treat `--editor --quit` as an import diagnostic, not a runtime smoke test. It
  can hit progress-dialog or message-queue errors during import.
- If a patch helper fails or stalls, inspect the target before retrying. A failed
  helper can partially write a file. Use an exact, asserted replacement only
  after confirming the failure, then review the diff.
- Keep native process windows hidden unless the user needs to interact with
  them. Keep reusable logs in the temp directory rather than tracked source.
- Workspace edit permission does not imply permission for external executables
  or Git index writes; honor the permission boundary shown by the tool.

## Completion checklist

1. Inspect `git status` and the focused diff.
2. Launch the game manually and exercise the affected behavior.
3. Run `git diff --check`.
4. Stage only task-owned files and report any intentionally uncommitted work.