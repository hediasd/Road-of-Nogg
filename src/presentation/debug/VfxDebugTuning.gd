## Live parameter editing for whichever effect the VFX debug scene has open.
##
## Builds its controls entirely from the effect's own `tunables()` descriptor,
## so it holds no per-effect knowledge and a new effect gets an editor by
## declaring a roster. Profiles keep their `AUTHORED` / `DERIVED` labels and
## supply the defaults; this only ever carries the differences.
##
## Flags:
##   --tune=NAME=value[,NAME=value...]  apply overrides before any capture
##   --tune-load=<path>                 load a saved tuning set (JSON)
##
## Values that leave here have to be able to reach a profile, or a tuning
## session ends with numbers read off sliders and transcribed by hand, and the
## constant-labelling discipline in `docs/VFX_DESIGN.md` §4 rots. `exportText()`
## emits paste-ready GDScript for exactly the constants that changed.

class_name VfxDebugTuning
extends RefCounted

const SAVE_DIR := "res://debug/vfx_tuning"

## Overrides by tunable id, for the effect currently open. Only ids that differ
## from their descriptor default are kept, so "what did I change" is the
## dictionary itself rather than a diff computed later.
var overrides: Dictionary = {}

var _descriptor: Array[Dictionary] = []
var _profileId: String = ""
var _container: VBoxContainer
var _onChanged: Callable
var _controls: Dictionary = {}
var _suppress: bool = false


func _init(container: VBoxContainer, onChanged: Callable) -> void:
	_container = container
	_onChanged = onChanged


func profileId() -> String:
	return _profileId


## Swaps in a new effect's roster, dropping overrides from the previous one.
## Tuning is per effect: carrying a ray count across to an ice storm that
## happens to name a constant the same way would be a silent surprise.
func setEffect(profileId: String, descriptor: Array[Dictionary]) -> void:
	_profileId = profileId
	_descriptor = descriptor
	overrides.clear()
	_rebuildControls()


func hasOverrides() -> bool:
	return not overrides.is_empty()


func describe() -> String:
	if _descriptor.is_empty():
		return "effect exposes none"
	if overrides.is_empty():
		return "%d parameters, defaults" % _descriptor.size()
	return "%d parameters, %d changed" % [_descriptor.size(), overrides.size()]


func rowFor(id: String) -> Dictionary:
	for row: Dictionary in _descriptor:
		if str(row["id"]) == id:
			return row
	return {}


## True when the id names a parameter that shapes geometry built in `play()`,
## so the caller must replay rather than expect a live uniform to follow.
func requiresRebuild(id: String) -> bool:
	var row := rowFor(id)
	return row.is_empty() or bool(row.get("rebuild", true))


func setOverride(id: String, value: float) -> void:
	var row := rowFor(id)
	if row.is_empty():
		push_warning("Unknown tunable '%s' for effect '%s'." % [id, _profileId])
		return
	if is_equal_approx(value, float(row["default"])):
		overrides.erase(id)
	else:
		overrides[id] = value
	_syncControl(id, value)


func clearOverrides() -> void:
	overrides.clear()
	for row: Dictionary in _descriptor:
		_syncControl(str(row["id"]), float(row["default"]))


## `--tune=NAME=value,NAME=value`. Unknown names warn and are skipped rather
## than failing the run: a sweep with one stale name should still produce the
## frames its other names asked for.
func applyArgument(raw: String) -> void:
	if raw.is_empty():
		return
	for piece: String in raw.split(",", false):
		var pair := piece.strip_edges().split("=", false, 1)
		if pair.size() != 2 or not pair[1].strip_edges().is_valid_float():
			push_warning("Invalid --tune entry: %s" % piece)
			continue
		setOverride(pair[0].strip_edges(), pair[1].strip_edges().to_float())


## Paste-ready GDScript for the changed constants only.
func exportText() -> String:
	if overrides.is_empty():
		return "# %s: no changes from the profile defaults." % _profileId
	var lines: Array[String] = [
		"# %s — paste into the profile, keeping its AUTHORED/DERIVED labels." % _profileId
	]
	for row: Dictionary in _descriptor:
		var id := str(row["id"])
		if not overrides.has(id):
			continue
		var value := float(overrides[id])
		# Whole-number tunables are counts; emitting `18.0` for a blade count
		# would not survive a paste into an `int` constant.
		if is_equal_approx(float(row["step"]), roundf(float(row["step"]))) \
				and is_equal_approx(value, roundf(value)):
			lines.append("const %s := %d" % [id, int(value)])
		else:
			lines.append("const %s := %s" % [id, String.num(value, 4)])
	return "\n".join(lines)


func savePath() -> String:
	return SAVE_DIR.path_join("%s.json" % (_profileId if not _profileId.is_empty() else "default"))


func save() -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(savePath(), FileAccess.WRITE)
	if file == null:
		return "Tuning save failed: %s" % savePath()
	file.store_string(JSON.stringify({
		"profile_id": _profileId,
		"overrides": overrides,
	}, "\t"))
	file.close()
	return "Tuning saved: %s" % ProjectSettings.globalize_path(savePath())


func load(path: String = "") -> String:
	var target := path if not path.is_empty() else savePath()
	if not FileAccess.file_exists(target):
		return "No tuning file at %s" % ProjectSettings.globalize_path(target)
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null:
		return "Tuning load failed: %s" % target
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("overrides"):
		return "Tuning file is not a tuning set: %s" % target
	clearOverrides()
	for id: String in parsed["overrides"]:
		setOverride(id, float(parsed["overrides"][id]))
	return "Tuning loaded: %s" % ProjectSettings.globalize_path(target)


func _rebuildControls() -> void:
	for child: Node in _container.get_children():
		_container.remove_child(child)
		child.queue_free()
	_controls.clear()
	if _descriptor.is_empty():
		var empty := Label.new()
		empty.text = "This effect exposes no tunables."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_container.add_child(empty)
		return

	var currentGroup := ""
	for row: Dictionary in _descriptor:
		var group := str(row.get("group", ""))
		if group != currentGroup:
			currentGroup = group
			var heading := Label.new()
			heading.text = group
			_container.add_child(heading)
		_container.add_child(_buildRow(row))


func _buildRow(row: Dictionary) -> Control:
	var id := str(row["id"])
	var line := HBoxContainer.new()
	var name := Label.new()
	name.text = str(row["label"])
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(name)
	var field := SpinBox.new()
	field.min_value = float(row["min"])
	field.max_value = float(row["max"])
	field.step = float(row["step"])
	field.set_value_no_signal(float(row["default"]))
	field.value_changed.connect(_onFieldChanged.bind(id))
	line.add_child(field)
	_controls[id] = field
	return line


func _onFieldChanged(value: float, id: String) -> void:
	if _suppress:
		return
	setOverride(id, value)
	_onChanged.call(id)


func _syncControl(id: String, value: float) -> void:
	var field: SpinBox = _controls.get(id)
	if field == null:
		return
	_suppress = true
	field.set_value_no_signal(value)
	_suppress = false
