## Ported from run_status_icon_check.gd. Exercises standardized status badge
## palette/shape mapping, badge creation/prioritization (persistent > negative
## > overflow), and badge cleanup when effects are removed.
extends "res://tests/TestCase.gd"

const GodotVisualAdapterScript = preload("res://src/presentation/GodotVisualAdapter.gd")
const StatusEffectIconsScript = preload("res://src/presentation/StatusEffectIcons.gd")


func describe() -> String:
	return "status effect badges use the standardized palette and prioritize correctly"


func run() -> void:
	if not _has_standardized_status_styles():
		fail("status badge palette or stat-debuff icon mapping is incorrect")
		return
	var sim = makeSimulator(707, Vector2i(3, 3))
	var monster = sim.spawnMonster("Fireblood Lizard", 1, Vector2i(1, 1))
	var visualRoot = Node3D.new()
	root.add_child(visualRoot)
	var adapter = GodotVisualAdapterScript.new(sim.state, visualRoot)
	adapter._on_monster_spawned(monster.uniqueID, monster.name, monster.team, monster.position, {})

	sim.state.addEffect(monster.uniqueID, "guard", 4, monster.uniqueID, "check")
	sim.state.addEffect(monster.uniqueID, "focus", 3, monster.uniqueID, "check")
	sim.state.addEffect(monster.uniqueID, "atk_buff", 2, monster.uniqueID, "check")
	adapter._on_effect_applied(monster.uniqueID, "guard", 4, monster.uniqueID, "check")
	var row = _status_row(adapter, monster.uniqueID)
	if row == null or row.get_child_count() != 3:
		fail("status badges were not created for active effects")
		return
	var first_badge = row.get_child(0)
	if first_badge.name != "Badge_focus" and first_badge.name != "Badge_guard":
		fail("Guard and Focus were not prioritized as persistent status badges")
		return
	if first_badge.get_node_or_null("Icon") == null or first_badge.get_node_or_null("Duration") == null:
		fail("badge is missing its icon or duration indicator")
		return

	sim.state.addEffect(monster.uniqueID, "burn", 2, monster.uniqueID, "check")
	sim.state.addEffect(monster.uniqueID, "spd_debuff", 2, monster.uniqueID, "check")
	adapter._on_effect_applied(monster.uniqueID, "burn", 2, monster.uniqueID, "check")
	row = _status_row(adapter, monster.uniqueID)
	if row == null or row.get_child_count() != 4 or not row.get_child(0).name in ["Badge_burn", "Badge_spd_debuff"]:
		fail("negative effects were not prioritized or icon overflow was incorrect: %s" % _row_description(row))
		return

	sim.state.removeEffect(monster.uniqueID, "burn")
	sim.state.removeEffect(monster.uniqueID, "spd_debuff")
	sim.state.removeEffect(monster.uniqueID, "guard")
	sim.state.removeEffect(monster.uniqueID, "focus")
	sim.state.removeEffect(monster.uniqueID, "atk_buff")
	adapter._on_effect_removed(monster.uniqueID, "atk_buff")
	row = _status_row(adapter, monster.uniqueID)
	if row == null or row.get_child_count() != 0:
		fail("status badges did not clear after the effects were removed")
		return

	adapter.dispose()
	visualRoot.queue_free()


func _has_standardized_status_styles() -> bool:
	var blue = Color(0.05, 0.19, 0.34, 0.94)
	var red = Color(0.35, 0.04, 0.13, 0.94)
	var atk_buff = StatusEffectIconsScript._style_for({"name": "atk_buff"}, false)
	var atk_debuff = StatusEffectIconsScript._style_for({"name": "atk_debuff"}, false)
	var def_debuff = StatusEffectIconsScript._style_for({"name": "def_debuff"}, false)
	var speed_debuff = StatusEffectIconsScript._style_for({"name": "spd_debuff"}, false)
	var move_debuff = StatusEffectIconsScript._style_for({"name": "move_debuff"}, false)
	return (
		atk_buff["shape"] == "sword" and atk_buff["background"] == blue and
		atk_debuff["shape"] == "sword" and atk_debuff["background"] == red and
		def_debuff["shape"] == "shield" and def_debuff["background"] == red and
		speed_debuff["shape"] == "speed" and speed_debuff["background"] == red and
		move_debuff["shape"] == "move" and move_debuff["background"] == red
	)


func _row_description(row: Node3D) -> String:
	var names: Array[String] = []
	if row != null:
		for child in row.get_children():
			names.append(child.name)
	return "%d %s" % [row.get_child_count() if row != null else -1, names]


func _status_row(adapter: GodotVisualAdapter, monster_id: int) -> Node3D:
	var container = adapter._monster_visuals.get(monster_id) as Node3D
	return container.get_node_or_null("StatusEffectIcons") as Node3D if container != null else null
