## Control references, collapsible sections, and readout formatting for the VFX
## debug scene's panel.
##
## Holds every control the scene drives and knows how to render the status
## block; it does not decide what any of them mean. Handlers stay with the
## controller, because a control's behaviour is playback or render policy rather
## than a property of the panel.
##
## Resolving the paths once here is the point: thirty `@onready` lookups spread
## through a controller make the panel's structure something you reconstruct by
## grepping, and every scene-tree rename silently breaks a different file.

class_name VfxDebugHud
extends RefCounted

## Rows of the status block, in order: id, label. Ids match the keys
## `setStatus()` is handed, so adding a readout is one row here and one key
## there rather than a new positional argument in a twenty-slot format string.
const STATUS_ROWS := [
	["effect", "Effect"],
	["timeline", "Timeline"],
	["budget", "Budget"],
	["context", "Context"],
	["camera", "Camera"],
	["render", "Render"],
	["tuning", "Tuning"],
	["specimen", "Text"],
	["capture", "Capture"],
]

var root: CanvasLayer
var statusPanel: GridContainer

var effectOption: OptionButton
var elementOption: OptionButton
var modeToggle: CheckButton
var scaleSetting: SpinBox
var seedPin: CheckButton
var seedSetting: SpinBox
var cycleSeedButton: Button

var playButton: Button
var pauseButton: Button
var settleButton: Button
var overlapButton: Button
var screenshotButton: Button
var scrub: HSlider
var layerToggles: GridContainer

var radiusSetting: SpinBox
var shapeOption: OptionButton
var targetBodyOption: OptionButton
var sourceDistanceSetting: SpinBox

var cameraYawSetting: SpinBox
var cameraPitchSetting: SpinBox
var cameraZoomSetting: SpinBox
var cameraResetButton: Button

var presetOption: OptionButton
var resolutionOption: OptionButton
var retroToggle: CheckButton
var crtToggle: CheckButton
var paneAspectOption: OptionButton

var tuningControls: VBoxContainer
var tuningExportButton: Button
var tuningSaveButton: Button
var tuningLoadButton: Button
var tuningResetButton: Button

var textToggle: CheckButton
var textFontOption: OptionButton
var textSampleOption: OptionButton
var textScaleSetting: SpinBox
var textEdgeOption: OptionButton
var textEdgeSizeSetting: SpinBox
var textBackdropOption: OptionButton
var textFillOption: OptionButton
var stretchOption: OptionButton
var reloadGlyphsButton: Button

var _statusValues: Dictionary = {}


func _init(hudRoot: CanvasLayer) -> void:
	root = hudRoot
	var column := root.get_node(
		"PanelContainer/Scroll/VBoxContainer"
	) as VBoxContainer
	statusPanel = column.get_node("StatusPanel")

	var playback := column.get_node("PlaybackSection/PlaybackGrid")
	effectOption = playback.get_node("EffectOption")
	elementOption = playback.get_node("ElementOption")
	modeToggle = playback.get_node("ModeToggle")
	scaleSetting = playback.get_node("ScaleSetting")
	seedPin = playback.get_node("SeedRow/SeedPin")
	seedSetting = playback.get_node("SeedRow/SeedSetting")
	cycleSeedButton = playback.get_node("SeedRow/CycleSeedButton")

	var core := column.get_node("PlaybackSection/CoreButtons")
	playButton = core.get_node("PlayButton")
	pauseButton = core.get_node("PauseButton")
	settleButton = core.get_node("SettleButton")
	overlapButton = core.get_node("OverlapButton")
	screenshotButton = core.get_node("ScreenshotButton")
	scrub = column.get_node("PlaybackSection/Scrub")
	layerToggles = column.get_node("LayersSection/LayerToggles")

	var context := column.get_node("ContextSection/ContextGrid")
	radiusSetting = context.get_node("RadiusSetting")
	shapeOption = context.get_node("ShapeOption")
	targetBodyOption = context.get_node("TargetBodyOption")
	sourceDistanceSetting = context.get_node("SourceDistanceSetting")

	var camera := column.get_node("CameraSection/CameraGrid")
	cameraYawSetting = camera.get_node("CameraYawSetting")
	cameraPitchSetting = camera.get_node("CameraPitchSetting")
	cameraZoomSetting = camera.get_node("CameraZoomSetting")
	cameraResetButton = camera.get_node("CameraResetButton")

	var render := column.get_node("RenderSection/RenderGrid")
	presetOption = render.get_node("PresetOption")
	resolutionOption = render.get_node("ResolutionOption")
	retroToggle = render.get_node("RetroToggle")
	crtToggle = render.get_node("CRTToggle")
	paneAspectOption = render.get_node("PaneAspectOption")

	tuningControls = column.get_node("TuningSection/TuningControls")
	var tuningButtons := column.get_node("TuningSection/TuningButtons")
	tuningExportButton = tuningButtons.get_node("TuningExportButton")
	tuningSaveButton = tuningButtons.get_node("TuningSaveButton")
	tuningLoadButton = tuningButtons.get_node("TuningLoadButton")
	tuningResetButton = tuningButtons.get_node("TuningResetButton")

	var text := column.get_node("TextSection/TextControls")
	textToggle = text.get_node("TextToggle")
	textFontOption = text.get_node("TextFontOption")
	textSampleOption = text.get_node("TextSampleOption")
	textScaleSetting = text.get_node("TextScaleSetting")
	textEdgeOption = text.get_node("TextEdgeOption")
	textEdgeSizeSetting = text.get_node("TextEdgeSizeSetting")
	textBackdropOption = text.get_node("TextBackdropOption")
	textFillOption = text.get_node("TextFillOption")
	stretchOption = text.get_node("StretchOption")
	reloadGlyphsButton = column.get_node("TextSection/TextButtons/ReloadGlyphsButton")

	_buildStatusRows()
	_installSections(column)


## One label pair per row. Values wrap rather than clip, because the column is
## narrow and a truncated particle count is worse than a two-line one.
func _buildStatusRows() -> void:
	for row: Array in STATUS_ROWS:
		var name := Label.new()
		name.text = str(row[1])
		name.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		statusPanel.add_child(name)
		var value := Label.new()
		value.text = "-"
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		statusPanel.add_child(value)
		_statusValues[str(row[0])] = value


## Wraps each `*Section` container in a toggle header.
##
## Built at runtime rather than authored per section, so the panel's sections
## are a list here instead of a repeated four-node pattern in the scene that
## drifts the moment one section is edited and the others are not.
func _installSections(column: VBoxContainer) -> void:
	var sections := [
		["PlaybackSection", "Playback", true],
		["LayersSection", "Layers", true],
		["ContextSection", "Cast context", true],
		["CameraSection", "Camera", true],
		["RenderSection", "Render", true],
		["TuningSection", "Tuning", true],
		# Font authoring, not VFX. Present because this is the one place the
		# shipping render stack and arbitrary sample copy meet, collapsed
		# because it is not what the scene is opened for.
		["TextSection", "Text specimen", false],
	]
	for entry: Array in sections:
		var section := column.get_node_or_null(str(entry[0])) as Control
		if section == null:
			continue
		var header := Button.new()
		header.name = "%sHeader" % entry[0]
		header.toggle_mode = true
		header.button_pressed = bool(entry[2])
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.text = _sectionTitle(str(entry[1]), bool(entry[2]))
		header.toggled.connect(_onSectionToggled.bind(section, str(entry[1])))
		column.add_child(header)
		column.move_child(header, section.get_index())
		section.visible = bool(entry[2])


static func _sectionTitle(title: String, expanded: bool) -> String:
	return "%s  %s" % ["v" if expanded else ">", title]


func _onSectionToggled(expanded: bool, section: Control, title: String) -> void:
	section.visible = expanded
	var header := section.get_parent().get_node_or_null(
		"%sHeader" % section.name
	) as Button
	if header != null:
		header.text = _sectionTitle(title, expanded)


func isVisible() -> bool:
	return root.visible


func setVisible(visible: bool) -> void:
	root.visible = visible


## Selects the entry whose metadata equals `id` and runs the same handler the
## user's click would have run. Returns false when nothing matches.
##
## Command-line overrides route through this rather than straight at the target,
## so a scripted run and a hand-driven one cannot diverge: whatever the flags set
## is visible in the panel, and whatever the panel shows is what a flag would
## have produced.
static func selectOptionByMetadata(
		option: OptionButton, id: String, handler: Callable) -> bool:
	for index: int in range(option.item_count):
		if str(option.get_item_metadata(index)) == id:
			option.select(index)
			handler.call(index)
			return true
	return false


## Fills an OptionButton from `{id, label}` rows, preserving order.
static func fillOptions(option: OptionButton, rows: Array) -> void:
	for row: Dictionary in rows:
		option.add_item(str(row["label"]))
		option.set_item_metadata(option.item_count - 1, row["id"])


## Rebuilds the layer row from a playback's own layer list, restoring each
## toggle's remembered state. `visibility` is read and written by the caller, so
## a layer hidden for one effect stays hidden when a later effect declares the
## same layer name.
func rebuildLayerToggles(
		layerNames: Array[String],
		visibility: Dictionary,
		onToggled: Callable) -> void:
	for child: Node in layerToggles.get_children():
		layerToggles.remove_child(child)
		child.queue_free()
	for layerName: String in layerNames:
		if not visibility.has(layerName):
			visibility[layerName] = true
		var toggle := CheckButton.new()
		toggle.text = layerName.capitalize()
		toggle.button_pressed = bool(visibility[layerName])
		toggle.toggled.connect(onToggled.bind(layerName))
		layerToggles.add_child(toggle)


## The status block, built from a snapshot rather than by reaching back into the
## controller's state. Keyed rather than positional: this readout has grown a
## field almost every cycle, and a twenty-argument call is where the wrong value
## silently lands in the wrong column.
func setStatus(snapshot: Dictionary) -> void:
	var bounds: Vector3 = snapshot["target_bounds"]
	var values := {
		"effect": "%s / %s" % [snapshot["effect"], snapshot["state"]],
		"timeline": "%s @ %.2fx | t %.2f | %.2f / %.2fs" % [
			snapshot["mode"], snapshot["scale"], snapshot["normalized"],
			snapshot["elapsed"], snapshot["total"]
		],
		"budget": "seed %d | nodes %d | particles %d | instances %d | draws ~%d | overlaps %d | seek %s" % [
			snapshot["seed"], snapshot["nodes"], snapshot["particles"],
			snapshot["instances"], snapshot["draw_calls"], snapshot["overlaps"],
			"exact" if snapshot["seek_exact"] else "approx"
		],
		"context": "%s | %.2f x %.2f x %.2f | radius %d %s | separation %.2f" % [
			snapshot["target_body"], bounds.x, bounds.y, bounds.z,
			snapshot["radius"], snapshot["shape"], snapshot["separation"]
		],
		"camera": "yaw %.0f | pitch %.0f | zoom %.2f | %s" % [
			snapshot["yaw"], snapshot["pitch"], snapshot["zoom"],
			snapshot["pane_aspect"]
		],
		"render": "%s | %s | Retro %s | CRT %s" % [
			snapshot["preset"], snapshot["render"],
			"ON" if snapshot["retro"] else "OFF",
			"ON" if snapshot["crt"] else "OFF"
		],
		"tuning": snapshot.get("tuning", "defaults"),
		"specimen": snapshot.get("specimen", ""),
		"capture": snapshot.get("capture_message", ""),
	}
	for id: String in values:
		var label: Label = _statusValues.get(id)
		if label == null:
			continue
		var text := str(values[id])
		label.text = text if not text.is_empty() else "-"
