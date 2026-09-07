# Frozen square battle reference

This directory preserves the last merged square battle as an independently
runnable Godot project. It is a reference artifact, not a second maintained
runtime. Active code must never load files from this directory or from the
extracted package.

## Baseline

- Source commit: `0c101e16f6dd26062cb6c76d0b74b46d6dc73361`
- Local annotated tag: `reference/square-battle-v1`
- Godot: `4.4-stable`, matching `config/features=PackedStringArray("4.4")`
- Main scene: `res://scenes/debug/BattleDebugScene.tscn`

The selected commit was the tip of merged `main` before the hex battle cycle
opened. A path audit found no battle-runtime differences between it and the
world-map cycle snapshot from which the hex cycle branched. This avoids
capturing an unfinished editor cycle while preserving the same square battle.

`source.zip` contains only committed files from that source commit. It includes
`project.godot`, `export_presets.cfg`, `assets/`, `data/`, `scenes/`, `src/`,
the headless battle demo, and the documentation directory required for its log.
It excludes `.godot`, import caches, engine binaries, credentials, generated
diagnostics, and the live working tree. `PACKAGE_MANIFEST.json` records every
entry hash, the package hash, and resolved static `res://` dependencies.

## Reconstruct and verify

From the active repository root, choose a new extraction path. The script
refuses to remove or overwrite an existing extraction directory.

```powershell
powershell -NoProfile -File scripts/preserve_square_battle.ps1 `
  -SourceCommit 0c101e16f6dd26062cb6c76d0b74b46d6dc73361 `
  -ExtractionDirectory builds/square-reference/hxb2-verification
```

The command rebuilds the archive from Git, validates its inventory, rejects
forbidden files and active absolute paths, resolves literal static resources,
checks the committed archive hash, writes the manifest, and extracts a fresh
copy with its own `.gdignore`.

## Launch

Use a Godot 4.4-stable executable outside the package:

```powershell
Godot_v4.4-stable_win64.exe --path builds/square-reference/hxb2-verification
```

The initial import is expected because `.godot` is deliberately absent. Use
the values in `acceptance.json` for representative CPU vs CPU and Player vs CPU
battles. To exercise the preserved console configuration from the extracted
directory:

```powershell
Godot_v4.4-stable_win64.exe --headless --path . --script res://scripts/demo_battle.gd
```

The demo uses Forest, seed 42, the recorded default rosters, and a 30-round cap;
it writes `docs/battle_log.txt` inside the extracted project.

## Replay and visual acceptance

`acceptance.json` fixes the setup, replay operations, and representative VFX
profiles for final regression. The preserved runtime exposes snapshot creation,
restoration, and command replay through `BattleSimulator` and
`BattleReplayRunner`; it does not include a recorded replay fixture or a
standalone replay command. Final acceptance must create a snapshot from the
specified setup, restore it, replay its commands, and compare the final state
and ledger.

No automated suite existed at this baseline. Source closure and hashes are
verified here; opening the extracted project, completing battles, replaying a
snapshot, and rendering the listed effects remain deferred to the hex cycle's
standalone validation item.
