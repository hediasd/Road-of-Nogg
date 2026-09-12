## Every editor-only action the workspace offers, and the one place a key event is turned into
## one of them.
##
## WHY A TABLE RATHER THAN A SWITCH IN THE CONTROLLER. The old shell bound its shortcuts inside
## `_unhandled_key_input` and drew its chrome somewhere else entirely, so a key could exist with
## no button and a button could exist with no key, and nothing could notice. Here a button and a
## shortcut are two readings of the same row: the chrome builds its buttons from `actions()` and
## the controller resolves keys through `resolve()`, so an action that is reachable one way is
## reachable both ways or neither.
##
## FOCUS IS PART OF RESOLUTION, NOT A CALLER'S AFTERTHOUGHT. `B` is Paint and `E` is Erase, which
## are also two letters an author types into a map name. Resolution therefore takes the focus
## state and refuses every shortcut while a text field or a modal owns the keyboard -- including
## the Ctrl combinations, because Ctrl+S inside a rename field is still a keystroke the field
## should see rather than a save of a document the author has not finished naming. The map having
## focus is the only state in which a shortcut means what the toolbar says it means.
##
## MODIFIERS MATCH EXACTLY. `E`, `Ctrl+E` and `Ctrl+Shift+E` are three different actions (Erase,
## export the scene, export the battle map), and so are `Ctrl+Z` and `Ctrl+Shift+Z`. A prefix or
## "contains" match would collapse pairs of those into one; every comparison here is on the exact
## triple of keycode, ctrl and shift.

class_name WorldMapWorkspaceActions
extends RefCounted

## Where the keyboard is pointing when a key arrives. See the class note.
const FOCUS_MAP := 0
const FOCUS_TEXT := 1
const FOCUS_MODAL := 2

const GROUP_DOCUMENT := "document"
const GROUP_EXPORT := "export"
const GROUP_HISTORY := "history"
const GROUP_TOOL := "tool"
const GROUP_BRUSH := "brush"
const GROUP_VIEW := "view"
const GROUP_BATTLEFIELD := "battlefield"

const NEW_DOCUMENT := "document.new"
const OPEN_DOCUMENT := "document.open"
const OPEN_RECENT := "document.openRecent"
const SAVE_DOCUMENT := "document.save"
const SAVE_DOCUMENT_AS := "document.saveAs"

const EXPORT_SCENE := "export.scene"
const EXPORT_BATTLE := "export.battle"

const UNDO := "history.undo"
const REDO := "history.redo"

## Tool actions carry the workspace's own id, not `WorldMapEditorController.TOOLS`' -- the
## controller maps one to the other. `TOOL_ERASE` is the case that makes the indirection worth
## having: it is not a tool of its own down in the brushes, it is the paint tool with the erase
## value selected, and the button says Erase because that is what an author is doing.
const TOOL_NAVIGATE := "tool.navigate"
const TOOL_INSPECT := "tool.inspect"
const TOOL_PAINT := "tool.paint"
const TOOL_ERASE := "tool.erase"
const TOOL_FILL := "tool.fill"
const TOOL_EYEDROPPER := "tool.eyedropper"

const BRUSH_SMALLER := "brush.smaller"
const BRUSH_LARGER := "brush.larger"
const CANCEL_STROKE := "edit.cancelStroke"

const VIEW_FRAME := "view.frame"
const VIEW_GRID := "view.grid"

## FHB-8. The battlefield is filled from the art and overridden by painting; these are the two
## whole-map verbs. Neither has a shortcut: both rewrite many cells at once, and a stray key should
## not be able to do that.
const TERRAIN_FILL := "battlefield.fillFromArt"
const TERRAIN_RESET := "battlefield.resetToArt"

## THE LEFT COLUMN'S MAP MENU, top to bottom. Everything that acts on the MAP lives here, under
## the tilesheet the author is choosing from; the top bar keeps only the actions that manage the
## DOCUMENT. Splitting it that way is what the single toolbar row could never express -- it had
## document commands, tools, history, brush size and view toggles all on one line in the order
## they happened to be added, and nothing on it said which of those changed the file and which
## changed the next stroke.
##
## `columns` is how many buttons share a row WITHIN a section; the sections themselves always
## stack. Two throughout, which is what makes the whole menu fit under the tilesheet at 1280x720
## without scrolling -- one per row needs about 150 px more than the column has. The pairs it
## produces are the ones already thought of in pairs anyway: smaller/larger, undo/redo,
## frame/grid, and the tools in the order an author reaches for them.
const MAP_MENU := [
	{"group": GROUP_TOOL, "heading": "Tools", "columns": 2},
	{"group": GROUP_BRUSH, "heading": "Brush", "columns": 2},
	{"group": GROUP_HISTORY, "heading": "History", "columns": 2},
	{"group": GROUP_VIEW, "heading": "View", "columns": 2},
	{"group": GROUP_BATTLEFIELD, "heading": "Battlefield", "columns": 2},
]

## The top bar's groups, in order. Document management only -- see `MAP_MENU`.
const TOP_BAR := [GROUP_DOCUMENT, GROUP_EXPORT]

const ACTIONS := [
	{"id": NEW_DOCUMENT, "label": "New", "group": GROUP_DOCUMENT,
		"tooltip": "Create a new hex map, choosing its size and tileset."},
	{"id": OPEN_DOCUMENT, "label": "Open", "group": GROUP_DOCUMENT,
		"tooltip": "Open an authored map from disk."},
	{"id": OPEN_RECENT, "label": "Open Recent", "short": "Recent", "group": GROUP_DOCUMENT,
		"tooltip": "Choose a previously opened map that still exists on disk."},
	{"id": SAVE_DOCUMENT, "label": "Save", "group": GROUP_DOCUMENT,
		"tooltip": "Write the open map's versioned source file."},
	{"id": SAVE_DOCUMENT_AS, "label": "Save As", "group": GROUP_DOCUMENT,
		"tooltip": "Write a copy to a chosen file and continue editing that copy."},

	{"id": EXPORT_SCENE, "label": "Export scene", "group": GROUP_EXPORT,
		"tooltip": "Export the open map as a gameplay scene."},
	{"id": EXPORT_BATTLE, "label": "Export battle", "group": GROUP_EXPORT,
		"tooltip": "Export the gameplay scene and the tactical map together."},

	{"id": UNDO, "label": "Undo", "group": GROUP_HISTORY, "tooltip": "Undo the last stroke."},
	{"id": REDO, "label": "Redo", "group": GROUP_HISTORY, "tooltip": "Redo the last undone stroke."},

	{"id": TOOL_NAVIGATE, "label": "Navigate", "group": GROUP_TOOL,
		"tooltip": "Move the camera; the map takes no edits."},
	{"id": TOOL_PAINT, "label": "Paint", "group": GROUP_TOOL,
		"tooltip": "Paint the selected tile onto the active layer."},
	{"id": TOOL_ERASE, "label": "Erase", "group": GROUP_TOOL,
		"tooltip": "Clear cells on the active layer."},
	{"id": TOOL_FILL, "label": "Fill", "group": GROUP_TOOL,
		"tooltip": "Flood fill from the clicked cell."},
	{"id": TOOL_EYEDROPPER, "label": "Pick", "group": GROUP_TOOL,
		"tooltip": "Select the tile already in the clicked cell."},
	{"id": TOOL_INSPECT, "label": "Inspect", "group": GROUP_TOOL,
		"tooltip": "Report what the clicked cell holds without changing it."},

	{"id": BRUSH_SMALLER, "label": "Smaller brush", "short": "-", "group": GROUP_BRUSH,
		"tooltip": "Shrink the paint and erase footprint by one hex ring."},
	{"id": BRUSH_LARGER, "label": "Larger brush", "short": "+", "group": GROUP_BRUSH,
		"tooltip": "Grow the paint and erase footprint by one hex ring."},
	{"id": CANCEL_STROKE, "label": "Cancel stroke", "short": "Cancel", "group": GROUP_BRUSH,
		"tooltip": "Abandon the stroke in progress and put back what it changed."},

	{"id": VIEW_FRAME, "label": "Frame", "short": "Frame", "group": GROUP_VIEW,
		"tooltip": "Frame the whole region in the map column."},
	{"id": VIEW_GRID, "label": "Hex grid", "short": "Grid", "group": GROUP_VIEW,
		"tooltip": "Show or hide the authoring grid."},

	{"id": TERRAIN_FILL, "label": "Fill from art", "short": "From art", "group": GROUP_BATTLEFIELD,
		"tooltip": "Give every battle cell the terrain its tile says. Cells you set by hand are kept."},
	{"id": TERRAIN_RESET, "label": "Reset to art", "short": "Reset", "group": GROUP_BATTLEFIELD,
		"tooltip": "Give every battle cell the terrain its tile says, including cells you set by hand."},
]


## The text a cramped row puts on the button, falling back to the full label. The tooltip always
## carries the full name, so shortening is a layout decision and never a loss of meaning -- the
## workspace has to fit 1280 x 720 with both side panels open.
static func buttonTextFor(actionID: String) -> String:
	for action in ACTIONS:
		var row: Dictionary = action
		if str(row["id"]) == actionID:
			return str(row.get("short", row["label"]))
	return actionID

## One row per binding rather than per action, because Redo legitimately has two and a table keyed
## by action could not hold both. `shift` is matched exactly -- see the class note.
const SHORTCUTS := [
	{"id": NEW_DOCUMENT, "key": KEY_N, "ctrl": true, "shift": false},
	{"id": OPEN_DOCUMENT, "key": KEY_O, "ctrl": true, "shift": false},
	{"id": SAVE_DOCUMENT, "key": KEY_S, "ctrl": true, "shift": false},
	{"id": SAVE_DOCUMENT_AS, "key": KEY_S, "ctrl": true, "shift": true},
	{"id": EXPORT_SCENE, "key": KEY_E, "ctrl": true, "shift": false},
	{"id": EXPORT_BATTLE, "key": KEY_E, "ctrl": true, "shift": true},
	{"id": UNDO, "key": KEY_Z, "ctrl": true, "shift": false},
	{"id": REDO, "key": KEY_Z, "ctrl": true, "shift": true},
	{"id": REDO, "key": KEY_Y, "ctrl": true, "shift": false},
	{"id": TOOL_PAINT, "key": KEY_B, "ctrl": false, "shift": false},
	{"id": TOOL_ERASE, "key": KEY_E, "ctrl": false, "shift": false},
	{"id": TOOL_FILL, "key": KEY_G, "ctrl": false, "shift": false},
	{"id": TOOL_EYEDROPPER, "key": KEY_I, "ctrl": false, "shift": false},
	{"id": VIEW_FRAME, "key": KEY_F, "ctrl": false, "shift": false},
	{"id": BRUSH_SMALLER, "key": KEY_BRACKETLEFT, "ctrl": false, "shift": false},
	{"id": BRUSH_LARGER, "key": KEY_BRACKETRIGHT, "ctrl": false, "shift": false},
	{"id": CANCEL_STROKE, "key": KEY_ESCAPE, "ctrl": false, "shift": false},
]


static func actions() -> Array:
	return ACTIONS


## Whether an action belongs on the top bar rather than in the left column's map menu. Asked
## rather than assumed, so a new group added to one table cannot quietly appear in both.
static func isTopBarAction(actionID: String) -> bool:
	for action in ACTIONS:
		var row: Dictionary = action
		if str(row["id"]) == actionID:
			return TOP_BAR.has(str(row["group"]))
	return false


static func actionsInGroup(group: String) -> Array:
	var result: Array = []
	for action in ACTIONS:
		if str((action as Dictionary)["group"]) == group:
			result.append(action)
	return result


static func has(actionID: String) -> bool:
	for action in ACTIONS:
		if str((action as Dictionary)["id"]) == actionID:
			return true
	return false


static func labelFor(actionID: String) -> String:
	for action in ACTIONS:
		if str((action as Dictionary)["id"]) == actionID:
			return str((action as Dictionary)["label"])
	return actionID


## The first binding for an action, as a person reads it -- what a button's tooltip appends and
## what the footer hint lists. "" when the action is reachable only by its button.
static func hintFor(actionID: String) -> String:
	for shortcut in SHORTCUTS:
		var row: Dictionary = shortcut
		if str(row["id"]) != actionID:
			continue
		var parts := PackedStringArray()
		if bool(row["ctrl"]):
			parts.append("Ctrl")
		if bool(row["shift"]):
			parts.append("Shift")
		parts.append(OS.get_keycode_string(int(row["key"])))
		return "+".join(parts)
	return ""


## The action a key press means, or "" for none. Refuses everything while a text field or a modal
## owns the keyboard -- see the class note on why that includes the Ctrl combinations.
static func resolve(keycode: int, ctrl: bool, shift: bool, focus: int) -> String:
	if focus != FOCUS_MAP:
		return ""
	for shortcut in SHORTCUTS:
		var row: Dictionary = shortcut
		if int(row["key"]) == keycode and bool(row["ctrl"]) == ctrl and bool(row["shift"]) == shift:
			return str(row["id"])
	return ""


## The footer's one-line reminder, built from the table so it cannot drift from the bindings.
static func hintLine() -> String:
	var parts := PackedStringArray()
	for actionID in [NEW_DOCUMENT, OPEN_DOCUMENT, SAVE_DOCUMENT, SAVE_DOCUMENT_AS,
			TOOL_PAINT, TOOL_ERASE, TOOL_FILL, TOOL_EYEDROPPER, VIEW_FRAME, UNDO]:
		var hint := hintFor(actionID)
		if not hint.is_empty():
			parts.append("%s %s" % [hint, labelFor(actionID)])
	return "  ·  ".join(parts)
