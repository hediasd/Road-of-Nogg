## Builds the shared 3D Environment used by battle and presentation previews.

class_name BattleEnvironmentFactory
extends RefCounted


static func createBattleEnvironment() -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.background_canvas_max_layer = -1
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return environment
