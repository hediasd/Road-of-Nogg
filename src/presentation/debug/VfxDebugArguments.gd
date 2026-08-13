## Command-line argument parsing for the VFX debug scene.
##
## Every interactive control in that scene has a command-line equivalent, so a
## validation pass is scriptable rather than a sequence of clicks. These are the
## primitives that parity is built from; the flags themselves are documented
## beside the surfaces that own them.
##
## Static and stateless: the command line does not change during a run, and a
## parser instance would only be somewhere for a stale copy of it to live.

class_name VfxDebugArguments
extends RefCounted


## User args (after `--`) are appended to the engine's own, so both
## `--effect=x` and `-- --effect=x` reach the scene.
static func all() -> PackedStringArray:
	var arguments: PackedStringArray = OS.get_cmdline_args()
	arguments.append_array(OS.get_cmdline_user_args())
	return arguments


static func string(prefix: String) -> String:
	for argument: String in all():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


static func flag(name: String) -> bool:
	return all().has(name)


static func number(prefix: String, fallback: float) -> float:
	var raw := string(prefix)
	if raw.is_empty():
		return fallback
	if not raw.is_valid_float():
		push_warning("Invalid %s value: %s" % [prefix, raw])
		return fallback
	return raw.to_float()


static func integer(prefix: String, fallback: int) -> int:
	var raw := string(prefix)
	if raw.is_empty():
		return fallback
	if not raw.is_valid_int():
		push_warning("Invalid %s value: %s" % [prefix, raw])
		return fallback
	return raw.to_int()


## A comma-separated list of normalized times, each clamped to 0-1. Invalid
## entries warn and are dropped rather than failing the whole list, so one typo
## in a five-frame sweep still produces four usable frames.
static func normalizedTimes(prefix: String) -> PackedFloat32Array:
	var times := PackedFloat32Array()
	var raw := string(prefix)
	if raw.is_empty():
		return times
	for piece: String in raw.split(",", false):
		var trimmed := piece.strip_edges()
		if trimmed.is_valid_float():
			times.append(clampf(trimmed.to_float(), 0.0, 1.0))
		else:
			push_warning("Invalid %s value: %s" % [prefix, trimmed])
	return times
