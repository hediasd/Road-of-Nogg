## Uniform lifecycle and timeline contract for previewable visual effects.

class_name VfxPlayback
extends Node3D

const MODE_REFERENCE := "reference"
const MODE_BATTLE := "battle"

## Live-authoring overrides, keyed by tunable id. Empty means every value comes
## from the effect's profile constants, which is what every non-debug caller
## gets: `apply_tunables()` is only ever called by the VFX debug scene.
var _tunableOverrides: Dictionary = {}


## Parameters this effect exposes for live authoring, as data the debug panel
## builds controls from. Declaring a roster is what gives an effect an editor;
## the panel holds no effect-specific code.
##
## Each row:
##   `id`       stable key, named after the profile constant it defaults to
##   `label`    panel text
##   `group`    section heading, for keeping a long roster navigable
##   `min`/`max`/`step`  control range
##   `default`  the profile constant — profiles stay the documented source of
##              truth for authored values, and become the defaults rather than
##              the only possible values
##   `rebuild`  true when the value shapes geometry built in `play()`, so the
##              panel must replay rather than nudge a live uniform
##
## Effects that declare nothing behave exactly as they did before this existed.
static func tunables() -> Array[Dictionary]:
	return []


## Seeds the override set **before the effect builds itself**.
##
## This is the only correct moment for a rebuild-class value: an effect's
## geometry and shader uniforms are assembled inside its own `createPlayback`,
## so overrides handed over afterwards are consumed by nothing and the panel
## reports changes that never reached the screen. Factories call this between
## constructing the playback and building its layers; `SpellVfxCatalog.create()`
## routes the dictionary through for them.
func set_tunable_overrides(overrides: Dictionary) -> void:
	_tunableOverrides = overrides.duplicate()


## Replaces the override set on an already-built effect. Only meaningful for
## values the effect can apply without rebuilding — a descriptor row marked
## `rebuild: true` needs a fresh playback, which is what the debug panel does.
func apply_tunables(overrides: Dictionary) -> void:
	_tunableOverrides = overrides.duplicate()
	_on_tunables_applied()


## Hook for effects that can apply a live-class change without replaying.
func _on_tunables_applied() -> void:
	pass


## Reads a tunable, falling back to the profile constant the caller names.
##
## Effects call this once per value at build time and keep the result in a
## field. Reading through a dictionary inside a per-particle or per-frame path
## would cost real performance in the one tool used to judge performance.
func tunable(id: String, fallback: float) -> float:
	return float(_tunableOverrides.get(id, fallback))


func tunable_int(id: String, fallback: int) -> int:
	return int(round(tunable(id, float(fallback))))


## All profiles receive the same presentation-only cast snapshot. Profiles
## without source- or target-bound geometry intentionally ignore it.
func configure_cast_context(_context: VfxCastContext) -> void:
	pass


func play(_seed: int, _mode: String) -> void:
	assert(false, "VfxPlayback.play() must be implemented by the effect.")


func set_playback_scale(_scale: float) -> void:
	assert(false, "VfxPlayback.set_playback_scale() must be implemented by the effect.")


func seek_normalized(_time: float) -> void:
	assert(false, "VfxPlayback.seek_normalized() must be implemented by the effect.")


func skip_to_settle() -> void:
	assert(false, "VfxPlayback.skip_to_settle() must be implemented by the effect.")


func get_normalized_time() -> float:
	return 0.0


func get_elapsed_time() -> float:
	return 0.0


func get_total_duration() -> float:
	return 0.0


func is_finished() -> bool:
	return true


func dispose() -> void:
	assert(false, "VfxPlayback.dispose() must be implemented by the effect.")


func get_layer_names() -> Array[String]:
	return []


func set_layer_visible(_layer_name: String, _visible: bool) -> void:
	pass


func get_live_particle_count() -> int:
	return 0


func get_live_instance_count() -> int:
	return 0


func get_live_node_count() -> int:
	return 0


func is_particle_seek_exact() -> bool:
	return false
