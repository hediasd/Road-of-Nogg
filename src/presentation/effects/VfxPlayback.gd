## Uniform lifecycle and timeline contract for previewable visual effects.

class_name VfxPlayback
extends Node3D

const MODE_REFERENCE := "reference"
const MODE_BATTLE := "battle"


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
