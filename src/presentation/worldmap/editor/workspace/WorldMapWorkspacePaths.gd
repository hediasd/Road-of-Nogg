## What a map may be called, and where its files are allowed to land.
##
## A MAP NAME IS NOT A PATH. `WorldMapTileData.pathFor` builds a path by interpolating the name
## straight into one -- `"%s/%s.json"` -- so a name containing a separator or a `..` is not a
## badly-named map, it is a write outside the authored directory. The New and Save As dialogs take
## free text from a person, which is exactly the input that has to be checked before it reaches
## that interpolation. Nothing here is about tidiness; it is about a save landing where the author
## believes it landed.
##
## CONTAINMENT IS CHECKED ON THE RESULT TOO, not only on the name. Validating the input and then
## trusting the constructed path would miss anything a future `pathFor` change introduced, so the
## final path is confirmed to sit under the expected root before a write is attempted.

class_name WorldMapWorkspacePaths
extends RefCounted

const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const BakerScript = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")
const FileDocument = preload("res://src/presentation/worldmap/editor/document/WorldMapFileDocument.gd")

const MAX_NAME_LENGTH := 64

## Letters, digits, underscore and hyphen. Deliberately narrow: every character outside this set
## is either a path construct, a shell hazard or something that behaves differently on one of the
## platforms this project builds for.
const NAME_PATTERN := "^[A-Za-z0-9_-]+$"


static func isValidName(name: String) -> bool:
	return describeInvalidName(name).is_empty()


## Why a name is refused, phrased as something the author can act on, or "" when it is fine. The
## dialog shows this instead of failing silently or -- worse -- writing somewhere unexpected.
static func describeInvalidName(name: String) -> String:
	if name.is_empty():
		return "Give the map a name."
	if name.length() > MAX_NAME_LENGTH:
		return "Map names are at most %d characters." % MAX_NAME_LENGTH
	if name != name.strip_edges():
		return "Map names cannot start or end with spaces."
	var expression := RegEx.new()
	expression.compile(NAME_PATTERN)
	if expression.search(name) == null:
		return (
			"Use only letters, digits, underscore and hyphen -- a map name becomes a file name, "
			+ "so separators and dots would write outside the authored folder."
		)
	return ""


static func sourceRoot() -> String:
	return MapDataScript.AUTHORED_DIR


static func generatedRoot() -> String:
	return BakerScript.GENERATED_DIR


## Whether `path` really sits directly under `root`. Compared on the normalised base directory
## rather than with `begins_with`, so `res://data/worldmap/authored_elsewhere/x.json` cannot pass
## a prefix test against `res://data/worldmap/authored`.
static func isContained(path: String, root: String) -> bool:
	if path.is_empty():
		return false
	if path.contains(".."):
		return false
	return path.get_base_dir().simplify_path() == root.simplify_path()


## The source path for a valid name, or "" when the name is refused or the constructed path would
## escape the authored root. "" is the single refusal signal every caller checks.
static func sourcePathFor(name: String) -> String:
	if not isValidName(name):
		return ""
	var path := "%s/%s%s" % [sourceRoot(), name, FileDocument.EXTENSION]
	return path if isContained(path, sourceRoot()) else ""


static func generatedPathFor(name: String) -> String:
	if not isValidName(name):
		return ""
	var path := BakerScript.generatedPathFor(name)
	return path if isContained(path, generatedRoot()) else ""
