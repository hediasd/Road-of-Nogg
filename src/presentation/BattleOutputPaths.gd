## BattleOutputPaths — the one place a battle's generated output is allowed to land.
##
## Every battle output goes under `battle_output/` at the project root: human logs, machine
## records, championship corpora and their summaries, and anything a played battle writes later.
## A new writer asks this file for a path rather than choosing its own, so outputs never scatter
## across `docs/`, `user://` and scratch folders again.
##
## One folder per kind of run, so a person can find a thing without knowing which script made it:
##
##     battle_output/battles/        one battle at one seed (`run_battle.gd`): record + log
##     battle_output/championships/  many seeds (`run_championship.gd`): corpus + summary
##     battle_output/demo/           the fixed console demo (`demo_battle.gd`)
##     battle_output/played/         anything the playable scene writes about a battle
##
## THE FOLDER IS GITIGNORED AND GODOT-IGNORED. `.gitignore` keeps its contents out of version
## control, and a committed `battle_output/.gdignore` stops the editor scanning and importing
## thousands of `.jsonl` and `.txt` files. Only that marker file is tracked.
##
## AN EXPORTED BUILD CANNOT WRITE TO `res://`, so there the same layout lives under
## `user://battle_output/` instead. Running from the project (editor, headless scripts, probes)
## always uses the root folder.

const PROJECT_ROOT := "res://battle_output"
const EXPORT_ROOT := "user://battle_output"

const BATTLES := "battles"
const CHAMPIONSHIPS := "championships"
## Declared policy experiments: one directory per run, shards and logs inside.
const TOURNAMENTS := "tournaments"
const DEMO := "demo"
const PLAYED := "played"


static func root() -> String:
	return EXPORT_ROOT if OS.has_feature("template") else PROJECT_ROOT


## `kind` is one of the constants above; `fileName` is a bare name, not a path.
static func pathFor(kind: String, fileName: String) -> String:
	return "%s/%s/%s" % [root(), kind, fileName]


## Creates the folder a path will be written into. Safe to call when it already exists.
static func ensureParent(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
