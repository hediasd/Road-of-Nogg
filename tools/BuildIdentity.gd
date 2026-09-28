## What actually ran, hashed rather than declared.
##
## An experiment launched from a working tree that somebody is editing can have
## half its matches played by one version of the simulator and half by another,
## and nothing in the results would say so. Recording the commit is not enough,
## because a dirty tree has no commit that describes it.
##
## So each row carries a hash of the files whose behaviour could change a
## result: the simulator, the algorithms it uses, the AI, and the content
## catalogs. Two rows that disagree here were not produced by the same program,
## whatever the branch was called.
##
## This is identity, not integrity. It says whether two runs match; it is not a
## defence against anyone deliberately altering files to collide.

class_name BuildIdentity
extends RefCounted

## Directories whose contents decide a match. Presentation is deliberately
## absent: a headless match never draws anything, so a change there cannot move
## a result and including it would make every VFX commit look like a new build.
const HASHED_DIRECTORIES: Array[String] = [
	"res://simulation",
	"res://ai",
	"res://content",
]
## These two tools also determine the recorded outcome of a match.
const HASHED_RUNNER_FILES: Array[String] = [
	"res://tools/BuildIdentity.gd",
	"res://tools/run_policy_tournament.gd",
]
const HASHED_DATA: Array[String] = [
	"res://data",
]


static func capture() -> Dictionary:
	return {
		"engine": "%s.%s" % [Engine.get_version_info()["string"],
			Engine.get_version_info()["build"]],
		"simulation": _hashOf(HASHED_DIRECTORIES, HASHED_RUNNER_FILES),
		"content": _hashOf(HASHED_DATA),
	}


## True when two rows could have been produced by the same program.
static func agrees(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("engine", "")) == str(b.get("engine", "")) \
		and str(a.get("simulation", "")) == str(b.get("simulation", "")) \
		and str(a.get("content", "")) == str(b.get("content", ""))


static func _hashOf(roots: Array, individualFiles: Array = []) -> String:
	var paths: Array[String] = []
	for root: String in roots:
		_collect(root, paths)
	for path: String in individualFiles:
		assert(FileAccess.file_exists(path), "build identity file missing: %s" % path)
		paths.append(path)
	paths.sort()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for path: String in paths:
		context.update(path.to_utf8_buffer())
		var bytes := FileAccess.get_file_as_bytes(path)
		## The path already distinguishes an empty file; Godot rejects a hash
		## update with a zero-length buffer (data/.gitkeep is one such file).
		if not bytes.is_empty():
			context.update(bytes)
	return "sha256:%s" % context.finish().hex_encode().substr(0, 32)


static func _collect(root: String, out: Array[String]) -> void:
	var directory := DirAccess.open(root)
	assert(directory != null, "build identity directory missing: %s" % root)
	for fileName in directory.get_files():
		## Godot's own bookkeeping files change without the program changing.
		if fileName.ends_with(".uid") or fileName.ends_with(".import"):
			continue
		out.append("%s/%s" % [root, fileName])
	for directoryName in directory.get_directories():
		_collect("%s/%s" % [root, directoryName], out)
