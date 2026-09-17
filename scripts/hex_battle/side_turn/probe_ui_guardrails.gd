## UI guardrails for the hex battle: every player-facing window keeps the HUD's spacing, and every
## piece of text wears a game font and fits its frame.
##
## Four rules, checked in each HUD state a player meets -- turn start, a selected unit, a target
## preview, the spell list, End turn asking, the STATUS sheet -- at two window sizes:
##
## 1. SCREEN MARGIN. A screen-docked window stays at least `NoggTheme.HEX_SCREEN_MARGIN` from
##    every viewport edge. World-anchored cues (the icon arc, forecast boxes) follow their unit and
##    are exempt.
## 2. CONTENT INSET. Text inside a window stays at least `NoggTheme.CONTENT_INSET` from the
##    window's edges.
## 3. NO CLIPPED TEXT. A row's label is never wider than the space its window gives it.
## 4. GAME FONTS. Every label and button resolves to Nogg Terminal or Nogg Herald, never Godot's
##    fallback sans. The Debug drawer is developer UI and lives outside the walked layers.
##
## Both lengths are layout tokens that scale with the UI; a new window passes by using them, not
## by picking pixel values that happen to fit one resolution.

extends SceneTree

const SCENE := "res://scenes/battle/HexBattle.tscn"
const SCENARIO := "res://data/battle/scenarios/hexmap_player_cpu.json"
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const IconArcScript = preload("res://src/presentation/battle/ui/side_turn/SideTurnIconArc.gd")
const PreviewBoxScript = preload("res://src/presentation/battle/ui/side_turn/SideTurnPreviewBox.gd")

const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]
## Sub-pixel slack for rounding in centred layouts.
const TOLERANCE := 0.5
const SETTLE_SECONDS := 0.45

var failures: Array[String] = []
var controller
var _state := ""


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	for size: Vector2i in SIZES:
		await _checkSize(size)
	_report()


func _checkSize(size: Vector2i) -> void:
	root.size = size
	if controller != null:
		controller.queue_free()
		await process_frame
	controller = load(SCENE).instantiate()
	root.add_child(controller)
	await process_frame
	var started: Dictionary = controller.startBattle(SCENARIO, 42)
	if not bool(started.get("ok", false)):
		failures.append("%s: battle did not start" % size)
		return
	controller.playback.setSpeed(4.0)
	if not await _awaitPlayerTurn():
		failures.append("%s: the player's turn never opened" % size)
		return

	await _settle()
	_audit("%s turn start" % size)

	var ready: Array = controller.sim.eligibleSideUnitIDs()
	var unitID := int(ready[0])
	controller._onHudMemberSelected(unitID)
	await _settle()
	_audit("%s selected unit" % size)

	var enemyID := _anyEnemy()
	if enemyID != -1:
		var cell: Vector2i = controller.sim.state.getMonsterPosition(enemyID)
		controller.sideCues.showForecasts([{
			"monster_id": enemyID,
			"name": str(controller.sim.state.getMonster(enemyID).name),
			"world_anchor": controller.adapter.worldPositionOf(cell) + Vector3.UP * 1.2,
			"forecast": controller.adapter.forecastAttack(unitID, cell),
		}])
		await _settle()
		_audit("%s target preview" % size)
		controller.sideCues.clearForecasts()

	var caster := _unitWithSpells()
	if caster != -1:
		controller._onHudMemberSelected(caster)
		controller._onSideActionRequested("magic")
		await _settle()
		_audit("%s spell list" % size)
		controller._cancelPlayerSelection()

	controller.sideCues._endButton._onPressed()
	await _settle()
	_audit("%s end turn asking" % size)
	controller.sideCues.setEndTurnConfirming(false)

	controller.hud.openStatus(unitID)
	await _settle()
	_audit("%s status sheet" % size)
	controller.hud.statusSheet.close()


# --- the audit ---------------------------------------------------------------

func _audit(state: String) -> void:
	_state = state
	var viewport := Vector2(root.size)
	for layerRoot in [controller.hud, controller.sideCues]:
		if layerRoot == null:
			continue
		for node in layerRoot.find_children("*", "Control", true, false):
			var control := node as Control
			if not control.is_visible_in_tree():
				continue
			if control is NoggWindow:
				_checkScreenMargin(control, viewport)
			if control is Label or control is Button:
				_checkFont(control)
			if control is Label and not (control as Label).text.strip_edges().is_empty():
				_checkInset(control)
				_checkClip(control)


func _checkScreenMargin(window: Control, viewport: Vector2) -> void:
	if _isWorldAnchored(window):
		return
	var rect := window.get_global_rect()
	var margin := NoggThemeScript.HEX_SCREEN_MARGIN
	if rect.position.x < margin - TOLERANCE or rect.position.y < margin - TOLERANCE \
			or rect.end.x > viewport.x - margin + TOLERANCE \
			or rect.end.y > viewport.y - margin + TOLERANCE:
		_fail("%s sits closer than %.0f px to the screen edge: %s" % [
			_describe(window), margin, rect])


func _checkInset(label: Label) -> void:
	var frame := _frameOf(label)
	if frame == null:
		return
	var inset := float(NoggThemeScript.CONTENT_INSET)
	var allowed := frame.get_global_rect().grow(-inset).grow(TOLERANCE)
	var glyphs := _glyphRect(label)
	if not allowed.encloses(glyphs):
		_fail("text \"%s\" is closer than %d px to the edge of %s (text %s, frame %s)" % [
			label.text, int(inset), _describe(frame), glyphs, frame.get_global_rect()])


func _checkClip(label: Label) -> void:
	var clip := label.get_parent() as Control
	if clip == null or not clip.clip_contents:
		return
	var needed := _textWidth(label)
	if needed > clip.size.x + TOLERANCE:
		_fail("text \"%s\" is clipped: needs %.0f px, has %.0f px in %s" % [
			label.text, needed, clip.size.x, _describe(_frameOf(label))])


func _checkFont(control: Control) -> void:
	var font := control.get_theme_font("font")
	if not _isGameFont(font):
		_fail("%s \"%s\" does not use a game font (%s)" % [
			control.get_class(), str(control.get("text")), _fontName(font)])


# --- helpers -----------------------------------------------------------------

## The window whose edges the text must respect: its nearest NoggWindow ancestor, or, for text
## laid over a window as a sibling (the turn banner), a NoggWindow beside it that contains it.
func _frameOf(control: Control) -> Control:
	var node := control.get_parent()
	while node != null and node != root:
		if node is NoggWindow:
			return node
		node = node.get_parent()
	var parent := control.get_parent()
	if parent == null:
		return null
	var centre := control.get_global_rect().get_center()
	for sibling in parent.get_children():
		if sibling is NoggWindow and (sibling as Control).get_global_rect().has_point(centre):
			return sibling
	return null


## Where the label's glyphs actually are, from its alignment -- the Label rect itself is often
## stretched across the whole window.
func _glyphRect(label: Label) -> Rect2:
	var rect := label.get_global_rect()
	var font := label.get_theme_font("font")
	var fontSize := label.get_theme_font_size("font_size")
	var width := _textWidth(label)
	var height := font.get_height(fontSize)
	var x := rect.position.x
	match label.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			x += (rect.size.x - width) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			x += rect.size.x - width
	var y := rect.position.y
	match label.vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER:
			y += (rect.size.y - height) * 0.5
		VERTICAL_ALIGNMENT_BOTTOM:
			y += rect.size.y - height
	# A label inside a clip is only visible within it.
	var glyphs := Rect2(x, y, width, height)
	var clip := label.get_parent() as Control
	if clip != null and clip.clip_contents:
		glyphs = glyphs.intersection(clip.get_global_rect())
	return glyphs


func _textWidth(label: Label) -> float:
	var font := label.get_theme_font("font")
	var fontSize := label.get_theme_font_size("font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize).x


func _isGameFont(font: Font) -> bool:
	var paths := [NoggThemeScript.GAME_FONT_PATH, NoggThemeScript.BANNER_FONT_PATH]
	var current: Font = font
	while current != null:
		if paths.has(current.resource_path):
			return true
		current = (current as FontVariation).base_font if current is FontVariation else null
	return false


func _fontName(font: Font) -> String:
	if font == null:
		return "none"
	if not font.resource_path.is_empty():
		return font.resource_path
	return font.get_font_name() if not font.get_font_name().is_empty() else font.get_class()


func _isWorldAnchored(control: Control) -> bool:
	var node: Node = control
	while node != null and node != root:
		var script: Script = node.get_script()
		if script == IconArcScript or script == PreviewBoxScript:
			return true
		node = node.get_parent()
	return false


func _describe(control: Node) -> String:
	if control == null:
		return "?"
	var names: Array[String] = []
	var node := control
	for _depth in range(3):
		if node == null or node == root:
			break
		names.push_front(str(node.name))
		node = node.get_parent()
	return "/".join(names)


func _fail(text: String) -> void:
	var line := "%s: %s" % [_state, text]
	if not failures.has(line):
		failures.append(line)


func _anyEnemy() -> int:
	for value in controller.adapter.shownModelIDs():
		var monster = controller.sim.state.getMonster(int(value))
		if monster != null and monster.team != controller.sim.state.activeSideID:
			return int(value)
	return -1


func _unitWithSpells() -> int:
	for value in controller.sim.eligibleSideUnitIDs():
		var monster = controller.sim.state.getMonster(int(value))
		if monster != null and not monster.spellSets.is_empty():
			return int(value)
	return -1


func _awaitPlayerTurn() -> bool:
	for _frame in range(3000):
		await process_frame
		var side := int(controller.sim.state.activeSideID)
		if side != -1 and controller._sideController(side) == "player" \
				and controller.playback.isIdle() \
				and not controller.sim.eligibleSideUnitIDs().is_empty():
			return true
	return false


func _settle() -> void:
	await create_timer(SETTLE_SECONDS).timeout


func _report() -> void:
	if controller != null:
		controller.queue_free()
	await process_frame
	if failures.is_empty():
		print("STB_UI_GUARDRAILS_OK")
		quit(0)
		return
	for failure in failures:
		print("STB_UI_GUARDRAILS_FAILURE: ", failure)
	quit(1)
