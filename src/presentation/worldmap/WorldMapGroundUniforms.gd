## Uniform and framing-key spellings for the world map ground rig.
##
## This file is the contract between four others that are written independently:
## `worldmap_ground.gdshader` declares the uniforms, `WorldMapFramingCatalog` supplies
## values for them, `WorldMapCameraRig` and `WorldMapGround` apply them, and the world
## map debug scene edits them. Spelling a key differently in any one of those is a silent
## failure -- `set_shader_parameter()` on a name the shader does not declare is a no-op,
## not an error -- so every one of them goes through the constants here.
##
## A framing is a plain Dictionary rather than a Resource because the debug scene builds
## one per frame from live controls, and because a preset that omits a key should inherit
## the default rather than carry a null. Merge over `DEFAULTS`; never index a raw framing.
##
## The rationale for the values, and for the tile convention below, is in
## `docs/WORLDMAP_DESIGN.md`.

class_name WorldMapGroundUniforms
extends RefCounted

## Map art is authored on a 16 px tile grid, and one tile is one world unit. That
## convention is what makes every other number in the rig readable as a tile count:
## camera height, fog distances, and region size all speak the same unit as the art.
const TILE_PIXELS := 16
const WORLD_UNITS_PER_MAP_PIXEL := 1.0 / float(TILE_PIXELS)

## Shader uniform names. The three region samplers all receive the same texture; see the
## `filter_mode` comment in the shader for why one sampler cannot serve all three modes.
const U_REGION_NEAREST := "region_nearest"
const U_REGION_NEAREST_MIP := "region_nearest_mip"
const U_REGION_LINEAR_MIP := "region_linear_mip"
const U_FILTER_MODE := "filter_mode"
const U_REGION_ORIGIN := "region_origin"
const U_REGION_SIZE := "region_size"
const U_FOG_START := "fog_start"
const U_FOG_END := "fog_end"
const U_FOG_CURVE := "fog_curve"
const U_FOG_COLOR := "fog_color"
const U_VOID_COLOR := "void_color"
const U_CURVATURE_K := "curvature_k"
const U_CLOUD_STRENGTH := "cloud_strength"
const U_CLOUD_SCALE := "cloud_scale"
const U_CLOUD_SPEED := "cloud_speed"

const REGION_SAMPLERS := [U_REGION_NEAREST, U_REGION_NEAREST_MIP, U_REGION_LINEAR_MIP]

## `filter_mode` values, matching the shader's branch order.
const FILTER_NEAREST := 0
const FILTER_NEAREST_MIPMAP := 1
const FILTER_LINEAR_MIPMAP := 2

## Framing dictionary keys. Camera keys first, then ground, then the presentation keys
## that are not shader uniforms at all but travel with a framing because changing them
## changes the framing's look.
const K_PITCH := "pitch"
const K_FOV := "fov"
const K_HEIGHT := "height"
const K_UNITS_PER_MAP_PIXEL := "units_per_map_pixel"
const K_FOG_START := "fog_start"
const K_FOG_END := "fog_end"
const K_FOG_CURVE := "fog_curve"
const K_FOG_COLOR := "fog_color"
const K_VOID_COLOR := "void_color"
const K_CURVATURE := "curvature"
const K_CLOUD_STRENGTH := "cloud_strength"
const K_CLOUD_SCALE := "cloud_scale"
const K_CLOUD_SPEED := "cloud_speed"
const K_FILTER_MODE := "filter_mode"

## Not shader uniforms. `render_scale` is the world map's own internal buffer scale and is
## deliberately NOT wired to `RetroRenderController`'s retro preset: on the battle side a
## low-resolution buffer is an opt-in retro treatment, here it is a framing decision that
## decides how many buffer pixels a tile gets. `sprite_mode` picks whether map sprites are
## blitted at fixed screen size (what the reference does) or billboarded in world space.
const K_RENDER_SCALE := "render_scale"
const K_SPRITE_MODE := "sprite_mode"

const SPRITE_FIXED := "fixed"
const SPRITE_WORLD := "world"

## Every framing key, in the order a readout or a control panel should present them.
const FRAMING_KEYS := [
	K_PITCH,
	K_FOV,
	K_HEIGHT,
	K_UNITS_PER_MAP_PIXEL,
	K_FOG_START,
	K_FOG_END,
	K_FOG_CURVE,
	K_FOG_COLOR,
	K_VOID_COLOR,
	K_CURVATURE,
	K_CLOUD_STRENGTH,
	K_CLOUD_SCALE,
	K_CLOUD_SPEED,
	K_FILTER_MODE,
	K_RENDER_SCALE,
	K_SPRITE_MODE,
]

## The reference framing, derived in `debug/worldmap/worldmap-framing.html`. Presets vary
## camera height -- the zoom knob -- and scale the fog band with it; everything else is
## shared. Yaw is absent on purpose: it is pinned to 0 and is not a framing choice.
const DEFAULTS := {
	K_PITCH: 60.0,
	K_FOV: 25.0,
	K_HEIGHT: 66.0,
	K_UNITS_PER_MAP_PIXEL: WORLD_UNITS_PER_MAP_PIXEL,
	K_FOG_START: 21.0,
	K_FOG_END: 116.0,
	K_FOG_CURVE: 1.4,
	K_FOG_COLOR: Color("cfe9f5"),
	K_VOID_COLOR: Color.BLACK,
	K_CURVATURE: 0.0,
	K_CLOUD_STRENGTH: 0.0,
	K_CLOUD_SCALE: 12.0,
	K_CLOUD_SPEED: 1.2,
	K_FILTER_MODE: FILTER_NEAREST,
	K_RENDER_SCALE: 0.4,
	K_SPRITE_MODE: SPRITE_FIXED,
}


## Fills in every key a partial framing omits. Callers should treat the result as the only
## valid thing to read from; a preset is authored as a diff against `DEFAULTS`, so indexing
## a raw preset will miss keys that were never written.
static func complete(framing: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate(true)
	for key in framing:
		result[key] = framing[key]
	return result


## Applies the ground half of a framing to a material. The camera half is
## `WorldMapCameraRig`'s; splitting them is what lets the rig be driven without a material
## and the material be previewed without a camera.
static func applyToMaterial(
	material: ShaderMaterial, framing: Dictionary, region_origin: Vector2, region_size: Vector2
) -> void:
	var f := complete(framing)
	material.set_shader_parameter(U_REGION_ORIGIN, region_origin)
	material.set_shader_parameter(U_REGION_SIZE, region_size)
	material.set_shader_parameter(U_FOG_START, f[K_FOG_START])
	material.set_shader_parameter(U_FOG_END, f[K_FOG_END])
	material.set_shader_parameter(U_FOG_CURVE, f[K_FOG_CURVE])
	material.set_shader_parameter(U_FOG_COLOR, f[K_FOG_COLOR])
	material.set_shader_parameter(U_VOID_COLOR, f[K_VOID_COLOR])
	material.set_shader_parameter(U_CURVATURE_K, f[K_CURVATURE])
	material.set_shader_parameter(U_CLOUD_STRENGTH, f[K_CLOUD_STRENGTH])
	material.set_shader_parameter(U_CLOUD_SCALE, f[K_CLOUD_SCALE])
	material.set_shader_parameter(U_CLOUD_SPEED, f[K_CLOUD_SPEED])
	material.set_shader_parameter(U_FILTER_MODE, f[K_FILTER_MODE])
