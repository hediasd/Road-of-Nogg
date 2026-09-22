## Plays a real battle with the renderer on, so the reworked CPU can be looked
## at rather than reasoned about, and times every frame while it does.
##
## The probes beside it prove the policy decides the same thing however it is
## sliced and that a restore rebuilds the board. Neither can say whether a side
## turn *reads* right or whether the screen keeps up, which is the half this is
## for.
##
## Needs a renderer, so it is not in a probe manifest and not part of the sweep.
## Run it directly, without --headless:
##
##   ./Godot_v4.4-stable_win64.exe --path . \
##       --script scripts/battle/capture_ai_session.gd
##
## Frames land in `battle_output/ai_session/`, which is gitignored, and the
## timings print as one line at the end.

extends SceneTree

const HexBattleControllerScript = preload("res://src/systems/hex_battle/HexBattleController.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")

const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_cpu_cpu.json"
const SEED := 4242
const OUT_DIR := "res://battle_output/ai_session"
const SCREEN := Vector2i(1280, 720)
## Long enough to see several side turns resolve, short enough to sit through.
const FRAME_LIMIT := 5400
const SHOT_EVERY := 45

var _controller
var _frameTimes: Array[int] = []
var _deliberationFrames: Array[int] = []
var _shots := 0


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	root.size = SCREEN
	_controller = HexBattleControllerScript.new()
	root.add_child(_controller)
	await process_frame

	var started: Dictionary = _controller.startBattle(SCENARIO, SEED)
	if not bool(started.get("ok", false)):
		printerr("AI_SESSION_FAILED: %s" % str(started.get("error", "")))
		quit(1)
		return

	var simulator = _controller.sim
	var frames := 0
	var restored := false
	var restoreFrame := -1
	var previous := Time.get_ticks_usec()
	while frames < FRAME_LIMIT and simulator.state.battleOutcome == -1:
		await process_frame
		frames += 1
		var now := Time.get_ticks_usec()
		_frameTimes.append(now - previous)
		previous = now
		## Frames spent while a decision is in flight are the ones that matter:
		## everything else is playback, which was already paced.
		if _controller._deliberation != null:
			_deliberationFrames.append(_frameTimes[_frameTimes.size() - 1])
		if frames % SHOT_EVERY == 0:
			_shoot("play_%04d" % frames)
		## One technical restore, once the battle has real work to abandon, so
		## the rebuild can be seen rather than only asserted.
		if not restored and simulator.state.history.size() > 40:
			_shoot("restore_00_before")
			var outcome: Dictionary = simulator.restoreSideTurn()
			if bool(outcome.get("success", false)):
				restored = true
				restoreFrame = frames
				await process_frame
				await process_frame
				_shoot("restore_01_after")
			else:
				print("AI_SESSION restore refused: %s" % str(outcome))
				restored = true

	_shoot("final")
	_report(frames, restoreFrame, simulator)
	_controller.teardownBattle()
	quit(0)


func _shoot(name: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [ProjectSettings.globalize_path(OUT_DIR), name])
	_shots += 1


func _report(frames: int, restoreFrame: int, simulator) -> void:
	print("AI_SESSION frames=%d shots=%d outcome=%d rounds=%d restore_frame=%d" % [
		frames, _shots, simulator.state.battleOutcome,
		simulator.state.roundCount, restoreFrame])
	print("AI_SESSION all_frames %s" % _summarise(_frameTimes))
	print("AI_SESSION deliberating_frames %s" % _summarise(_deliberationFrames))
	print("AI_SESSION invariant_violations=%s" % str(simulator.invariantViolations()))


## Percentiles rather than an average: a mean hides exactly the occasional long
## frame that a person notices as a hitch.
func _summarise(samples: Array[int]) -> String:
	if samples.is_empty():
		return "none"
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0
	for sample: int in sorted:
		total += sample
	var over := 0
	for sample: int in sorted:
		if sample > 16667:
			over += 1
	return "n=%d mean=%.1fms p50=%.1fms p95=%.1fms max=%.1fms over_16.7ms=%d (%.1f%%)" % [
		sorted.size(), float(total) / float(sorted.size()) / 1000.0,
		float(sorted[int(sorted.size() * 0.50)]) / 1000.0,
		float(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))]) / 1000.0,
		float(sorted[sorted.size() - 1]) / 1000.0,
		over, 100.0 * float(over) / float(sorted.size())]
