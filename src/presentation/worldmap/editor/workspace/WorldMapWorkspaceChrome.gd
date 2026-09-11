## The workspace frame: header, toolbar, the three-column body, the view bar and the footer, plus
## the dialogs the document actions open.
##
## WHAT THIS OWNS AND WHAT IT DOES NOT. This builds the SHAPE of the editor and every button on
## it, and it reports where the map column actually landed. It owns no document, no camera, no
## layer state and no tool state: a press turns into an action id handed straight back to the
## controller, which is the only thing that decides what an action means. `WorldMapEditorHud`
## fills the palette and inspector columns this builds; the split is frame versus contents.
##
## INPUT OWNERSHIP IS THE LAYOUT'S JOB, NOT A GUARD'S. The old shell drew panels over a full-rect
## `Display` and then had to reason about whether a click had been on chrome. Here every panel is
## `MOUSE_FILTER_STOP` and every structural container between them is `MOUSE_FILTER_IGNORE`, so a
## press on a button, a field, the tilesheet or the footer is consumed by that control and never
## reaches the controller's `_unhandled_input` at all -- while a press on the stage, which
## deliberately ignores the mouse, falls through to it. Painting behind a panel is not prevented
## by a check; it is unrepresentable.
##
## THE STAGE IS AN EMPTY HOLE. `Display` is a sibling of this CanvasLayer and draws BEHIND it, so
## the map is not a child of the layout -- the stage is a transparent Control whose measured rect
## the controller copies onto `Display` every time layout settles. That is why `stageResized` is a
## signal rather than a one-time read: a collapse, a window resize and the first frames of layout
## all move it, and a rect measured once freezes the map at whatever the layout happened to be
## mid-build.

class_name WorldMapWorkspaceChrome
extends RefCounted

const Actions = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceActions.gd")

const PALETTE_WIDTH := 248.0
const INSPECTOR_WIDTH := 214.0
const COLLAPSED_WIDTH := 26.0

var root: CanvasLayer
var stage: Control
var paletteColumn: VBoxContainer
var inspectorColumn: VBoxContainer

var _onAction: Callable
var _onExtraTool: Callable
var _buttons: Dictionary = {}
var _extraToolOption: OptionButton
var _extraToolIDs: Array[String] = []
var _documentLabel: Label
var _dirtyLabel: Label
var _viewLabel: Label
var _brushLabel: Label
var _status: Label
var _paletteScroll: ScrollContainer
var _inspectorScroll: ScrollContainer
var _modalDepth := 0
var _stageCallback: Callable


## `extraTools` is every controller tool that does not get its own toolbar button -- the
## layer-specific ones. They stay reachable in a named dropdown rather than being dropped: the
## workspace is button-first, not button-only.
func build(
	uiRoot: CanvasLayer, onAction: Callable, onExtraTool: Callable, extraTools: Array
) -> void:
	root = uiRoot
	_onAction = onAction
	_onExtraTool = onExtraTool

	var frame := VBoxContainer.new()
	frame.name = "Workspace"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_constant_override("separation", 0)
	# ADDED TO THE TREE BEFORE IT IS ANCHORED, and anchored with offsets rather than anchors
	# alone. A preset applied to a Control that is not yet in a tree resolves against a zero-sized
	# parent and sticks there, which produced a workspace a few pixels tall with the map squeezed
	# out of it entirely.
	root.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	frame.add_child(_buildHeader())
	frame.add_child(_buildToolbar())

	var body := HBoxContainer.new()
	body.name = "WorkspaceBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 0)
	frame.add_child(body)

	body.add_child(_buildPalette())
	body.add_child(_buildMapColumn(extraTools))
	body.add_child(_buildInspector())

	frame.add_child(_buildFooter())


func _buildHeader() -> Control:
	var panel := _panel("WorkspaceHeader")
	var row := HBoxContainer.new()
	panel.add_child(row)

	var title := Label.new()
	title.text = "World map editor"
	row.add_child(title)

	row.add_child(_separator())

	_documentLabel = Label.new()
	_documentLabel.name = "DocumentName"
	_documentLabel.text = "No document"
	row.add_child(_documentLabel)

	_dirtyLabel = Label.new()
	_dirtyLabel.name = "DocumentDirty"
	_dirtyLabel.text = "●  unsaved"
	_dirtyLabel.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	_dirtyLabel.visible = false
	row.add_child(_dirtyLabel)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	for action in Actions.actionsInGroup(Actions.GROUP_DOCUMENT):
		row.add_child(_actionButton(str((action as Dictionary)["id"])))
	row.add_child(_separator())
	for action in Actions.actionsInGroup(Actions.GROUP_EXPORT):
		row.add_child(_actionButton(str((action as Dictionary)["id"])))
	return panel


func _buildToolbar() -> Control:
	var panel := _panel("WorkspaceToolbar")
	var row := HBoxContainer.new()
	panel.add_child(row)

	for action in Actions.actionsInGroup(Actions.GROUP_TOOL):
		row.add_child(_actionButton(str((action as Dictionary)["id"]), true))
	row.add_child(_separator())
	for action in Actions.actionsInGroup(Actions.GROUP_HISTORY):
		row.add_child(_actionButton(str((action as Dictionary)["id"])))

	row.add_child(_separator())
	var brushLabel := Label.new()
	brushLabel.text = "Brush"
	row.add_child(brushLabel)
	row.add_child(_actionButton(Actions.BRUSH_SMALLER))
	_brushLabel = Label.new()
	_brushLabel.name = "BrushSize"
	_brushLabel.text = "1 hex"
	_brushLabel.custom_minimum_size = Vector2(72.0, 0.0)
	_brushLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_brushLabel.tooltip_text = "How many hexes one paint or erase stamp covers."
	row.add_child(_brushLabel)
	row.add_child(_actionButton(Actions.BRUSH_LARGER))
	row.add_child(_actionButton(Actions.CANCEL_STROKE))
	return panel


func _buildPalette() -> Control:
	var panel := _panel("PalettePanel")
	panel.custom_minimum_size = Vector2(PALETTE_WIDTH, 0.0)
	var column := VBoxContainer.new()
	panel.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Tileset"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_collapseButton("PaletteCollapse", panel, PALETTE_WIDTH, func() -> ScrollContainer:
		return _paletteScroll
	))

	_paletteScroll = ScrollContainer.new()
	_paletteScroll.name = "PaletteScroll"
	_paletteScroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_paletteScroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_paletteScroll)

	paletteColumn = VBoxContainer.new()
	paletteColumn.name = "PaletteColumn"
	paletteColumn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paletteScroll.add_child(paletteColumn)
	return panel


func _buildMapColumn(extraTools: Array) -> Control:
	var column := VBoxContainer.new()
	column.name = "MapColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)

	var bar := _panel("ViewBar")
	var row := HBoxContainer.new()
	bar.add_child(row)
	_viewLabel = Label.new()
	_viewLabel.name = "ViewMode"
	_viewLabel.text = "Shipping view"
	_viewLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewLabel.clip_text = true
	_viewLabel.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_viewLabel)

	_extraToolOption = OptionButton.new()
	_extraToolOption.name = "ExtraTools"
	_extraToolOption.clip_text = true
	_extraToolOption.tooltip_text = "Layer-specific tools: rectangle, line, stamp, scatter, replace, sculpt, place and triangle paint."
	_extraToolOption.add_item("More tools")
	_extraToolIDs.append("")
	for tool in extraTools:
		var entry: Dictionary = tool
		_extraToolOption.add_item(str(entry["label"]))
		_extraToolIDs.append(str(entry["id"]))
	_extraToolOption.item_selected.connect(_onExtraToolSelected)
	row.add_child(_extraToolOption)

	row.add_child(_separator())
	for action in [Actions.VIEW_EDITING, Actions.VIEW_SHIPPING]:
		row.add_child(_actionButton(action))
	row.add_child(_actionButton(Actions.VIEW_PROJECTION))
	row.add_child(_actionButton(Actions.VIEW_FRAME))
	row.add_child(_actionButton(Actions.VIEW_GRID, true))
	column.add_child(bar)

	stage = Control.new()
	stage.name = "Stage"
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The hole the map shows through -- see the class note. Ignoring the mouse is what routes a
	# map click to the controller instead of consuming it here.
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.resized.connect(_emitStageResized)
	stage.item_rect_changed.connect(_emitStageResized)
	column.add_child(stage)
	return column


func _buildInspector() -> Control:
	var panel := _panel("InspectorPanel")
	panel.custom_minimum_size = Vector2(INSPECTOR_WIDTH, 0.0)
	var column := VBoxContainer.new()
	panel.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Layers"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_collapseButton("InspectorCollapse", panel, INSPECTOR_WIDTH, func() -> ScrollContainer:
		return _inspectorScroll
	))

	_inspectorScroll = ScrollContainer.new()
	_inspectorScroll.name = "InspectorScroll"
	_inspectorScroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inspectorScroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_inspectorScroll)

	inspectorColumn = VBoxContainer.new()
	inspectorColumn.name = "InspectorColumn"
	inspectorColumn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspectorScroll.add_child(inspectorColumn)
	return panel


func _buildFooter() -> Control:
	var panel := _panel("WorkspaceFooter")
	var row := HBoxContainer.new()
	panel.add_child(row)
	_status = Label.new()
	_status.name = "StatusLine"
	_status.text = "Choose a tile, then paint the map."
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# TRIMMED, NEVER WRAPPED. An autowrapping Label in an HBox next to a long sibling is squeezed
	# to a sliver of width while minimum sizes are computed, wraps its text to one word per line,
	# and reports a minimum HEIGHT of several hundred pixels -- which the footer then takes out of
	# the map. The measured stage was four pixels tall until this stopped wrapping.
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.tooltip_text = "The editor's most recent result."
	row.add_child(_status)
	var hint := Label.new()
	hint.name = "ShortcutHint"
	hint.text = Actions.hintLine()
	hint.clip_text = true
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(hint)
	return panel


func _panel(nodeName: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = nodeName
	# Every panel consumes the mouse; the containers between them do not. See the class note.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.12, 0.14, 0.94)
	style.border_color = Color(0.22, 0.27, 0.30, 1.0)
	style.set_border_width_all(1)
	style.set_content_margin_all(6.0)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _separator() -> Control:
	var line := VSeparator.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Buttons keep ordinary keyboard focus: Tab traversal is a requirement of this workspace, and the
## shortcuts that used to need `FOCUS_NONE` to survive are now gated on focus STATE instead (see
## `WorldMapWorkspaceActions`), which is the fix that lets both work at once.
func _actionButton(actionID: String, toggle := false) -> Button:
	var button := Button.new()
	button.name = actionID
	button.text = Actions.buttonTextFor(actionID)
	# `clip_text` removes the label's natural minimum width. Without an explicit floor the
	# HBoxContainers assign actions zero width, so the 1280x720 toolbar renders as blank slivers
	# even though the combined-minimum-size probe claims the workspace fits.
	button.custom_minimum_size.x = maxf(40.0, 20.0 + float(button.text.length()) * 9.0)
	button.clip_text = true
	button.toggle_mode = toggle
	button.focus_mode = Control.FOCUS_ALL
	var hint := Actions.hintFor(actionID)
	var tooltip := ""
	for action in Actions.actions():
		if str((action as Dictionary)["id"]) == actionID:
			tooltip = str((action as Dictionary).get("tooltip", ""))
			break
	button.tooltip_text = tooltip if hint.is_empty() else "%s  (%s)" % [tooltip, hint]
	button.pressed.connect(func() -> void: _onAction.call(actionID))
	_buttons[actionID] = button
	return button


func _collapseButton(
	nodeName: String, panel: PanelContainer, width: float, scrollOf: Callable
) -> Button:
	var button := Button.new()
	button.name = nodeName
	button.text = "«"
	button.toggle_mode = true
	button.tooltip_text = "Collapse this panel"
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(func() -> void:
		var collapsed := button.button_pressed
		var scroll: ScrollContainer = scrollOf.call()
		if scroll != null:
			scroll.visible = not collapsed
		panel.custom_minimum_size = Vector2(COLLAPSED_WIDTH if collapsed else width, 0.0)
		panel.size_flags_horizontal = (
			Control.SIZE_SHRINK_BEGIN if collapsed else Control.SIZE_FILL
		)
		button.text = "»" if collapsed else "«"
		button.tooltip_text = "Expand this panel" if collapsed else "Collapse this panel"
	)
	return button


func _onExtraToolSelected(index: int) -> void:
	if index <= 0 or index >= _extraToolIDs.size():
		return
	_onExtraTool.call(_extraToolIDs[index])


func connectStageResized(callback: Callable) -> void:
	_stageCallback = callback


func _emitStageResized() -> void:
	if _stageCallback.is_valid():
		_stageCallback.call()


func stageRect() -> Rect2:
	return stage.get_global_rect() if stage != null else Rect2()


## Which of the toolbar's tool buttons reads as selected. Passing an id that has no button -- one
## of the layer-specific tools from the dropdown -- clears them all, which is the honest reading:
## none of the six named tools is the active one.
func setToolActive(actionID: String) -> void:
	for action in Actions.actionsInGroup(Actions.GROUP_TOOL):
		var id := str((action as Dictionary)["id"])
		var button: Button = _buttons.get(id)
		if button != null:
			button.set_pressed_no_signal(id == actionID)
	if _extraToolOption != null and Actions.has(actionID):
		_extraToolOption.select(0)


func setActionEnabled(actionID: String, enabled: bool) -> void:
	var button: Button = _buttons.get(actionID)
	if button != null:
		button.disabled = not enabled


func setActionPressed(actionID: String, pressed: bool) -> void:
	var button: Button = _buttons.get(actionID)
	if button != null and button.toggle_mode:
		button.set_pressed_no_signal(pressed)


func buttonFor(actionID: String) -> Button:
	return _buttons.get(actionID)


func setDocumentLabel(documentName: String, neverSaved: bool, dirty: bool) -> void:
	if _documentLabel != null:
		_documentLabel.text = (
			"No document" if documentName.is_empty()
			else ("%s  (never saved)" % documentName if neverSaved else documentName)
		)
	if _dirtyLabel != null:
		_dirtyLabel.visible = dirty


func setViewLabel(text: String) -> void:
	if _viewLabel != null:
		_viewLabel.text = text


## The brush readout says how many hexes a stamp covers, and greys out for the tools and layers
## where a radius has no meaning -- rather than showing a size that silently does not apply.
func setBrushLabel(text: String, applies: bool) -> void:
	if _brushLabel != null:
		_brushLabel.text = text
		_brushLabel.modulate = Color(1.0, 1.0, 1.0, 1.0 if applies else 0.45)
	setActionEnabled(Actions.BRUSH_SMALLER, applies)
	setActionEnabled(Actions.BRUSH_LARGER, applies)


func setStatus(message: String) -> void:
	if _status != null:
		_status.text = message


## Where the keyboard is pointing, in `WorldMapWorkspaceActions`' own terms. A dialog counts as
## modal for as long as it is up, which is what stops Space from snapping the camera while the
## author is deciding whether to discard their work.
func focusState() -> int:
	if _modalDepth > 0:
		return Actions.FOCUS_MODAL
	if root == null:
		return Actions.FOCUS_MAP
	var viewport := root.get_viewport()
	if viewport == null:
		return Actions.FOCUS_MAP
	var focused := viewport.gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit or focused is SpinBox:
		return Actions.FOCUS_TEXT
	return Actions.FOCUS_MAP


func isModalOpen() -> bool:
	return _modalDepth > 0


## Dialogs. Each returns false under the headless dummy display server -- a `Window` never enters
## a display-backed tree there, so popping one errors -- and the caller's own accessor path is
## what a probe drives instead. See `WorldMapEditorController`'s request* accessors.
func promptNewDocument(
	lattices: Array[Vector2i], latticeLabels: Array[String], tilesets: Array[String],
	defaultTileset: String, defaultName: String, onAccept: Callable
) -> bool:
	if not _canPopup():
		return false
	var dialog := ConfirmationDialog.new()
	dialog.title = "New hex map"
	dialog.get_ok_button().text = "Create"
	var column := VBoxContainer.new()
	column.add_child(_dialogLabel("Name"))
	var nameEdit := LineEdit.new()
	nameEdit.text = defaultName
	nameEdit.placeholder_text = "map name"
	column.add_child(nameEdit)
	column.add_child(_dialogLabel("Size"))
	var latticeOption := OptionButton.new()
	for label in latticeLabels:
		latticeOption.add_item(label)
	column.add_child(latticeOption)
	column.add_child(_dialogLabel("Tileset"))
	var tilesetOption := OptionButton.new()
	for id in tilesets:
		tilesetOption.add_item(id)
	var defaultIndex := tilesets.find(defaultTileset)
	if defaultIndex >= 0:
		tilesetOption.select(defaultIndex)
	column.add_child(tilesetOption)
	dialog.add_child(column)
	dialog.confirmed.connect(func() -> void:
		var lattice := (
			lattices[latticeOption.selected]
			if latticeOption.selected >= 0 and latticeOption.selected < lattices.size()
			else Vector2i.ZERO
		)
		var chosen := (
			tilesets[tilesetOption.selected]
			if tilesetOption.selected >= 0 and tilesetOption.selected < tilesets.size()
			else defaultTileset
		)
		onAccept.call(lattice, nameEdit.text.strip_edges(), chosen)
	)
	return _popup(dialog)


func promptOpenDocument(names: Array[String], onAccept: Callable) -> bool:
	if not _canPopup():
		return false
	var dialog := ConfirmationDialog.new()
	dialog.title = "Open map"
	dialog.get_ok_button().text = "Open"
	var column := VBoxContainer.new()
	column.add_child(_dialogLabel("Authored maps"))
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(280.0, 220.0)
	for name in names:
		list.add_item(name)
	if not names.is_empty():
		list.select(0)
	column.add_child(list)
	dialog.add_child(column)
	dialog.confirmed.connect(func() -> void:
		var selected := list.get_selected_items()
		if not selected.is_empty():
			onAccept.call(names[selected[0]])
	)
	return _popup(dialog)


func promptOpenFile(onAccept: Callable) -> bool:
	if not _canPopup():
		return false
	var dialog := FileDialog.new()
	dialog.title = "Open hex map"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.noggmap.json ; Road of Nogg hex maps"])
	dialog.file_selected.connect(func(path: String) -> void: onAccept.call(path))
	return _popup(dialog)


func promptOpenRecent(paths: Array[String], onAccept: Callable) -> bool:
	if not _canPopup() or paths.is_empty():
		return false
	var dialog := ConfirmationDialog.new()
	dialog.title = "Open recent map"
	dialog.get_ok_button().text = "Open"
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(420.0, 220.0)
	for path in paths:
		list.add_item(path)
	list.select(0)
	dialog.add_child(list)
	dialog.confirmed.connect(func() -> void:
		var selected := list.get_selected_items()
		if not selected.is_empty():
			onAccept.call(paths[selected[0]])
	)
	return _popup(dialog)


func promptSaveAs(defaultName: String, onAccept: Callable) -> bool:
	if not _canPopup():
		return false
	var dialog := ConfirmationDialog.new()
	dialog.title = "Save map as"
	dialog.get_ok_button().text = "Save"
	var column := VBoxContainer.new()
	column.add_child(_dialogLabel("Name"))
	var nameEdit := LineEdit.new()
	nameEdit.text = defaultName
	column.add_child(nameEdit)
	dialog.add_child(column)
	dialog.confirmed.connect(func() -> void: onAccept.call(nameEdit.text.strip_edges()))
	return _popup(dialog)


func promptSaveFile(defaultName: String, onAccept: Callable) -> bool:
	if not _canPopup():
		return false
	var dialog := FileDialog.new()
	dialog.title = "Save hex map as"
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.noggmap.json ; Road of Nogg hex maps"])
	dialog.current_file = "%s.noggmap.json" % defaultName
	dialog.file_selected.connect(func(path: String) -> void: onAccept.call(path))
	return _popup(dialog)


## THREE answers, not two. "Discard or cancel" makes an author who simply forgot to save choose
## between losing work and abandoning what they were trying to do; Save is the answer they
## actually want, so it is offered here rather than being a thing they have to go and do first.
## Save is the default action.
func promptDiscard(onSave: Callable, onDiscard: Callable, onCancel: Callable) -> bool:
	if not _canPopup():
		return false
	var dialog := ConfirmationDialog.new()
	dialog.title = "Unsaved changes"
	dialog.dialog_text = "This document has unsaved changes."
	dialog.get_ok_button().text = "Save and continue"
	var discardButton := dialog.add_button("Discard changes", true, "discard")
	dialog.get_cancel_button().text = "Cancel"
	dialog.confirmed.connect(func() -> void: onSave.call())
	dialog.canceled.connect(func() -> void: onCancel.call())
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			dialog.hide()
			onDiscard.call()
	)
	discardButton.tooltip_text = "Throw away the unsaved edits. This cannot be undone."
	return _popup(dialog)


## Lists the unsaved work found on disk and lets the author recover or discard ONE of them.
## Nothing is applied by opening this -- see `WorldMapWorkspaceRecovery`'s class note.
func promptRecovery(labels: Array[String], onRecover: Callable, onDiscard: Callable) -> bool:
	if not _canPopup() or labels.is_empty():
		return false
	var dialog := ConfirmationDialog.new()
	dialog.title = "Recover unsaved work"
	dialog.get_ok_button().text = "Recover selected"
	var column := VBoxContainer.new()
	var explanation := Label.new()
	explanation.text = (
		"The editor closed with unsaved edits. Recovering opens them as a NEW unsaved document; "
		+ "your saved maps are not touched either way."
	)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.custom_minimum_size = Vector2(420.0, 0.0)
	column.add_child(explanation)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(420.0, 200.0)
	for label in labels:
		list.add_item(label)
	list.select(0)
	column.add_child(list)
	dialog.add_child(column)
	var discardButton := dialog.add_button("Discard selected", true, "discardRecovery")
	discardButton.tooltip_text = "Delete only the selected snapshot. Other recoveries are kept."
	dialog.get_cancel_button().text = "Keep for next launch"
	dialog.confirmed.connect(func() -> void:
		var selected := list.get_selected_items()
		if not selected.is_empty():
			onRecover.call(selected[0])
	)
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action != &"discardRecovery":
			return
		var selected := list.get_selected_items()
		if not selected.is_empty():
			onDiscard.call(selected[0])
		dialog.hide()
	)
	return _popup(dialog)


func _dialogLabel(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _canPopup() -> bool:
	return root != null and DisplayServer.get_name() != "headless"


func _popup(dialog: AcceptDialog) -> bool:
	_modalDepth += 1
	# Every exit path -- confirm, cancel, window close, or a custom Discard button -- hides the
	# dialog. Releasing modal ownership from that one fact avoids leaving shortcuts disabled after
	# custom actions, and avoids double-decrementing when a platform emits more than one close
	# signal for the same dialog.
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			_modalDepth = maxi(0, _modalDepth - 1)
			dialog.queue_free()
	)
	root.add_child(dialog)
	dialog.popup_centered()
	return true
