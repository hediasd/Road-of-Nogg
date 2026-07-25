# Road of Nogg — Learnings & Patterns

This document tracks learned patterns, gotchas, and specific implementations regarding the Road of Nogg game, engine, and AI workflows.

## GDScript Patterns & Nuances
- **Global Classes**: `class_name` makes a class globally available without `preload()`. This is used extensively for structural classes (e.g. `BattleEvents`, `BattleState`).
- **Signal-Only Classes**: Scripts that use `class_name` but don't extend `Node` cannot emit Godot engine-level tree signals natively, but they CAN define custom signals. `BattleEvents` works as a pure logic class because signals are just declared/emitted in memory.
- **Pathing (A*)**: Dictionary-based open/closed sets work extremely well for pathfinding. The engine relies on Manhattan distance for grid heuristics.
- **Sorting**: For turn queues, use inline lambdas: `sort_custom(func(a, b): return a.speed > b.speed)`.

## Architecture & Code Defenses
- **Data vs Logic**: `GameBoardLogic` and `GameBoardThinker` were previously `Node` extensions despite having zero visual code. The current `src/battle_sim/` layer corrects this by remaining 100% headless and decoupled from the Godot Node tree.
- **Factory Paths**: The `preload()` paths in factories previously contained misleading directory structures (`res://scripts/...` instead of `src/factories/`). Godot resolves `class_name` globally, so it didn't crash, but strict file-path hygiene is required to avoid deployment errors.
- **State Consolidation**: Entity position was previously tracked both in `BattleBoard` and the `Monster` object. The `BattleState` now consolidates this as the Single Source of Truth to prevent desyncs.

## Tactical UI & Console Formatting
- **Cursor Represents Intent, Not Animation**: The tactical cursor is a discrete cell marker. It snaps to a movement destination, then to an attack, spell, or heal target as soon as that intent is committed. It must never interpolate alongside a model or infer action targets from animation state.
- **ASCII/Emoji Grid Alignment**: Mixing emojis (like 🔵, 🔴, 🌲) with standard ASCII box-drawing characters (─, │) causes severe alignment issues across different operating systems and text editors because emojis render as 1, 1.5, or 2 columns wide depending on the environment.
- **Pure ASCII Solution**: Dropping emojis in the grid and using standard 1-byte monospace ASCII (`.`, `#`, `1`, `A`) guarantees mathematical precision in every terminal.
- **Dynamic Legends**: Assigning a unique `A-Z` / `a-z` character identifier per entity creates a perfectly aligned, readable tactical map when paired with a side-by-side 2-column legend.
- **Open-Ended Borders**: Removing the closing right border (`│`) from UI panels (like the Round Highlights) creates a "Comic Book Frame" aesthetic that is 100% immune to internal character-width inconsistencies.

## Console Tooling
- **Godot Headless CLI**: To test the engine rapidly without the Godot editor, use: `& "Godot_v4.4-stable_win64.exe" --path "<project>" --quit-after <s> "res://scenes/<scene>.tscn"`
- Windows non-console builds still write to `stderr`, which can be captured cleanly in PowerShell using `2>&1`.

## Automated Test Lifecycle
- **GUT 9.4 CLI Ownership**: Run GUT through
  `res://addons/gut/gut_cmdln.gd` with `-gexit`. The supported runner owns test
  startup, JUnit export, shutdown, and failure exit codes. A custom per-frame
  poll of `GutMain` is unsafe because GUT 9.4 removed `get_is_running()` and the
  old `set_junit_xml_file()` method.
- **Godot/GUT Crash Boundary**: Godot 4.4 completes both a minimal-project
  startup and a fresh-cache Road of Nogg import with exit code 0. Starting GUT's
  supported CLI still exits with Windows access violation `0xC0000005`, before
  stdout or stderr, even with compatibility rendering, dummy audio, a dedicated
  user-data directory, and a populated 51-entry global class cache.
- **Temporary Isolation**: GUT execution is intentionally opt-in through
  `run_headless_tests.ps1 -ForceGut`. Normal invocation exits immediately and
  points to the backlog. Future diagnostics retain a temporary shadow project
  and 120-second watchdog to avoid editor contention and indefinite hangs.

## Codex / Windows Execution Playbook
- **Stop Early on Tool Stalls**: If a filesystem patch or helper produces no useful result within the first bounded attempt, stop it and change methods. Do not repeat the same hanging operation. Keep Godot launches under a 30-second watchdog and report progress before 60 seconds.
- **Patch Helper Fallback**: On this Windows workspace, `apply_patch` can fail with `helper_unknown_error` or hang after already writing a file. After a failure, inspect `git status` and the target before retrying. For small existing-file changes, use exact anchored replacements with `[System.IO.File]`, assert every anchor exists, then run `git diff --check` and review the diff.
- **Preserve Document Line Endings**: Several Markdown files contain historical CRLF/LF mixtures. Never normalize an entire document incidentally. Prefer new standalone files or byte-preserving, line-scoped edits; check `git diff --stat` immediately for unexpected whole-file rewrites.
- **Recover From Partial Writes Safely**: Restore only files changed by the current operation from a verified Git blob. Hash the temporary blob against `git rev-parse HEAD:<path>` before copying it over the target, and confirm the restored file has no diff.
- **Godot Paths With Spaces**: Older Windows PowerShell can split `Start-Process -ArgumentList` values containing the project path. Run from the repository working directory and pass `--path .`.
- **Prefer Direct Godot Exit Codes**: Redirected `Start-Process` objects can expose a null or stale `ExitCode`. For short checks, invoke Godot directly and use `$LASTEXITCODE`; use an explicit success marker for custom smoke scripts.
- **Editor Import Is Not the Primary Smoke Test**: `--editor --quit` may hit Godot's progress-dialog/message-queue error while importing. Use a focused headless script plus a default-scene launch to verify runtime parsing. Inspect for newly generated `.gd.uid` files before retrying an import.
- **GUT Remains Isolated**: Do not use GUT as a routine validation step until its Windows access violation is re-evaluated. Use focused headless smoke scripts and deterministic replay checks instead.
- **Local Image Viewer Fallback**: If direct image inspection fails with a sandbox refresh error, read the image as base64 inside an orchestrated command and emit it as an image result. Remove any temporary inspection copies afterward.
- **Permission Expectations**: Workspace edit approval does not automatically authorize external executables or Git index writes. Batch external checks into one request, reuse saved Git approvals, and never promise that mandatory safety prompts can be globally disabled.
