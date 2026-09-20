## Renders one hit number's whole life to PNGs, a frame per PNG, so the
## animation can be looked at rather than reasoned about. The probe beside this
## file checks that the arc obeys its constants; only this shows whether the
## result reads as pixel art, which is the half that kept being wrong.
##
## Needs a renderer, so it is not registered in a probe manifest and is not part
## of the sweep -- run it directly, without --headless:
##
##   ./Godot_v4.4-stable_win64.exe --path . \
##       --script scripts/hex_battle/side_turn/capture_damage_number.gd
##
## Frames land in `battle_output/damage_number/`, which is gitignored.

extends SceneTree

const BillboardScript = preload("res://src/presentation/effects/DamageNumberBillboard.gd")
const OUT_DIR := "res://battle_output/damage_number"


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var view := Vector2i(300, 420)
	root.size = view

	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.17, 0.20)
	bg.size = Vector2(view)
	root.add_child(bg)

	var layer := Control.new()
	layer.size = Vector2(view)
	root.add_child(layer)

	var tween: Tween = BillboardScript.spawn(layer, Vector2(170.0, 360.0), 7, false)
	tween.pause()

	var frame := 1.0 / 60.0
	var frames := int(BillboardScript.DAMAGE_VISIBLE_DURATION / frame)
	for index in range(frames):
		if index > 0:
			tween.custom_step(frame)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("%s/f%03d.png" % [ProjectSettings.globalize_path(OUT_DIR), index])
	print("CAPTURED %d frames" % frames)
	quit(0)
