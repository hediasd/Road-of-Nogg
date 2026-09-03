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

## One tile is one world unit. That convention is what makes every other number in the rig
## readable as a tile count: camera height, fog distances and region size all speak the same
## unit as the art.
##
## A tile's PIXEL size is a property of the art, not of the world, and it varies per region --
## some maps are drawn on an 8 px grid, some on 16. It therefore lives in
## `WorldMapRegionCatalog` and never reaches the camera: a 31 x 22 region of 8 px tiles and a
## 31 x 22 region of 16 px tiles occupy the same ground and frame identically, differing only
## in texel density. This constant is only the fallback for a region that omits it.
const DEFAULT_TILE_PIXELS := 16

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
const U_SHOW_SKY_BEYOND := "show_sky_beyond"
## The cast-shadow mask and how hard it bites. In map-pixel space, sampled with the region's
## own UV -- see `WorldMapShadowMask`.
const U_SHADOW_MASK := "shadow_mask"
const U_SHADOW_STRENGTH := "shadow_strength"
const U_LIGHT_TINT := "light_tint"
const U_LAMP_LIT := "lamp_lit"
const U_NIGHT_AMOUNT := "night_amount"
const U_SHADOW_COLOR_MODE := "shadow_color_mode"
const U_PALETTE := "palette"
const U_PALETTE_SIZE := "palette_size"

const REGION_SAMPLERS := [U_REGION_NEAREST, U_REGION_NEAREST_MIP, U_REGION_LINEAR_MIP]

## Colours a REGION owns rather than a framing. What lies beyond the map's edge, and the
## haze the map fades into, are properties of the place: temp's sea is deep blue, temp2's is
## teal, and one framing applied to both would give one of them the wrong void. They are
## deliberately absent from `DEFAULTS`, so `complete()` leaves them unset and
## `completeForRegion()` fills them -- which is what makes "region unless the framing says
## otherwise" expressible at all.
const REGION_COLOR_KEYS := [K_FOG_COLOR, K_VOID_COLOR]

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
## Backdrop keys. Not shader uniforms on the GROUND material -- they drive `WorldMapSky`,
## which is a separate quad. They live in the framing because changing them changes the
## framing's look, and because it gives them command-line parity for free.
const K_SKY := "sky"
const K_SKY_OFFSET := "sky_offset"
const K_SKY_SCALE := "sky_scale"
const K_SKY_TINT := "sky_tint"

const SKY_OFF := "off"

const K_RENDER_SCALE := "render_scale"
const K_SPRITE_MODE := "sprite_mode"

const SPRITE_FIXED := "fixed"
const SPRITE_WORLD := "world"

## How structures painted into a region's ground art are stood back up. Not a shader uniform
## -- it drives `WorldMapProps`, which owns its own sprites -- but it travels with a framing
## because it changes the framing's look and because that buys command-line parity for free.
##
## `off` leaves the region exactly as painted, which is what everything shipped before this
## key existed did, so it is the default and nothing changes until structures are asked for.
##
## The other three are the same rectangle on screen by two different routes, which was
## measured rather than assumed: at every pitch tested `face` and `gain` agree to 0.00 px.
## They differ only in what they claim about world space. `world` is the uncorrected
## baseline, kept because it is what the defect looks like.
const K_BILLBOARD := "billboard"

const BILLBOARD_OFF := "off"
const BILLBOARD_WORLD := "world"
const BILLBOARD_GAIN := "gain"
const BILLBOARD_FACE := "face"

const BILLBOARD_IDS := [BILLBOARD_OFF, BILLBOARD_WORLD, BILLBOARD_GAIN, BILLBOARD_FACE]

## Daylight. Not shader uniforms on the ground material in themselves -- they drive
## `WorldMapSun`, which turns them into a direction, a colour and a shadow shear -- but they
## live in the framing because changing them changes the framing's look, and because that
## buys command-line parity for free.
##
## Defaults are chosen so a framing naming none of them renders exactly as it did before the
## sun existed -- but WITHOUT making the day cycle a no-op, which is a trap this fell into once.
## `light_tint` at 0 blends the sun out entirely, so dragging Time of day in the debug console
## did nothing at all until a second, unrelated slider was raised: a control that silently
## depends on another is worse than one that is absent.
##
## Instead the tint is fully on and the clock starts at NOON, where the day's colour is exactly
## neutral (1, 1, 1). Existing framings therefore render identically, and moving the clock works
## immediately. Shadows and lamps stay off, so nothing appears that was not there before.
const K_TIME_OF_DAY := "time_of_day"
const K_SUN_HIGH := "sun_high"
const K_SUN_LOW := "sun_low"
const K_SUN_ARC := "sun_arc"
const K_SUN_REACH := "sun_reach"
const K_SHADOW_STRENGTH := "shadow_strength"
const K_SHADOW_SPREAD := "shadow_spread"
## How the shadow's edge is drawn, and how its colour is chosen. Both are the questions
## alignment does not answer: putting the mask in map space buys pixel-aligned edges, and says
## nothing about what colour a shadowed pixel should be or what happens at the boundary.
const K_SHADOW_EDGE := "shadow_edge"
const K_SHADOW_BAND := "shadow_band"
const K_SHADOW_COLOR_MODE := "shadow_color_mode"
## Discrete sun directions. A continuously rotating sun drags a hard pixel edge across the map
## one pixel at a time and the boundary flickers -- the shadow crawls. Quantising the azimuth
## makes the mask step between stable shapes instead. Zero disables it.
const K_SHADOW_STEPS := "shadow_steps"

const SHADOW_EDGE_HARD := "hard"
const SHADOW_EDGE_DITHER := "dither"
const SHADOW_EDGE_IDS := [SHADOW_EDGE_HARD, SHADOW_EDGE_DITHER]
const SHADOW_EDGE_LABELS := ["Hard", "Dithered"]

## `multiply` darkens arithmetically and invents colours the palette does not contain -- a
## darkened sand that is not any of temp2's seven. `palette` snaps the darkened result back to
## the nearest colour the region's art actually uses, so a shadowed pixel is always a colour
## somebody painted.
const SHADOW_COLOR_MULTIPLY := "multiply"
const SHADOW_COLOR_PALETTE := "palette"
const SHADOW_COLOR_IDS := [SHADOW_COLOR_MULTIPLY, SHADOW_COLOR_PALETTE]
const SHADOW_COLOR_LABELS := ["Multiply", "Palette-snapped"]
const K_LIGHT_TINT := "light_tint"
const K_LAMP_MODE := "lamp_mode"
const K_LAMP_STRENGTH := "lamp_strength"
const K_LAMP_REACH := "lamp_reach"
const K_LAMP_LEVELS := "lamp_levels"
const K_LAMP_CORE := "lamp_core"
const K_LAMP_DITHER := "lamp_dither"

## How a lamp shapes the region where the night is withheld. ALL of these are SUBTRACTIVE --
## they differ only in how the falloff is shaped, never in the mechanism. A lamp is a region
## where the night is not applied, so the ground under it keeps its daytime colours and nothing
## here can produce a colour the region's art does not already contain.
##
## THERE IS DELIBERATELY NO ADDITIVE MODE. The sketch keeps one as a comparison, because seeing
## warm light painted on top is what makes the subtractive choice legible; shipping one here
## would ship the thing this rejected. `smooth` is the unquantised falloff, which is the
## closest the engine gets and is still subtractive.
const LAMP_OFF := "off"
const LAMP_HARD := "hard"
const LAMP_BAND := "band"
const LAMP_DITHER := "dither"
const LAMP_SMOOTH := "smooth"

const LAMP_IDS := [LAMP_OFF, LAMP_HARD, LAMP_BAND, LAMP_DITHER, LAMP_SMOOTH]
const LAMP_LABELS := [
	"Off", "Hard circle", "Stepped rings", "Dithered rings", "Smooth falloff",
]
const BILLBOARD_LABELS := [
	"Off (as painted)", "World-vertical", "Proportion gain", "Face camera",
]

## Every framing key, in the order a readout or a control panel should present them.
const FRAMING_KEYS := [
	K_PITCH,
	K_FOV,
	K_HEIGHT,
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
	K_BILLBOARD,
	K_TIME_OF_DAY,
	K_SUN_HIGH,
	K_SUN_LOW,
	K_SUN_ARC,
	K_SUN_REACH,
	K_SHADOW_STRENGTH,
	K_SHADOW_SPREAD,
	K_SHADOW_EDGE,
	K_SHADOW_BAND,
	K_SHADOW_COLOR_MODE,
	K_SHADOW_STEPS,
	K_LIGHT_TINT,
	K_LAMP_MODE,
	K_LAMP_STRENGTH,
	K_LAMP_REACH,
	K_LAMP_LEVELS,
	K_LAMP_CORE,
	K_LAMP_DITHER,
	K_SKY,
	K_SKY_OFFSET,
	K_SKY_SCALE,
	K_SKY_TINT,
]

## The reference framing, derived in `debug/worldmap/worldmap-framing.html`. Presets vary
## camera height -- the zoom knob -- and scale the fog band with it; everything else is
## shared. Yaw is absent on purpose: it is pinned to 0 and is not a framing choice.
const DEFAULTS := {
	K_PITCH: 60.0,
	K_FOV: 25.0,
	K_HEIGHT: 66.0,
	K_FOG_START: 21.0,
	K_FOG_END: 116.0,
	K_FOG_CURVE: 1.4,
	K_CURVATURE: 0.0,
	K_CLOUD_STRENGTH: 0.0,
	K_CLOUD_SCALE: 12.0,
	K_CLOUD_SPEED: 1.2,
	K_FILTER_MODE: FILTER_NEAREST,
	K_RENDER_SCALE: 0.4,
	K_SPRITE_MODE: SPRITE_FIXED,
	K_BILLBOARD: BILLBOARD_OFF,
	K_TIME_OF_DAY: 12.0,
	K_SUN_HIGH: 62.0,
	K_SUN_LOW: 27.0,
	K_SUN_ARC: 52.0,
	K_SUN_REACH: 4.0,
	K_SHADOW_STRENGTH: 0.0,
	K_SHADOW_SPREAD: 1.7,
	K_SHADOW_EDGE: SHADOW_EDGE_HARD,
	K_SHADOW_BAND: 1.5,
	K_SHADOW_COLOR_MODE: SHADOW_COLOR_PALETTE,
	K_SHADOW_STEPS: 16.0,
	K_LIGHT_TINT: 1.0,
	K_LAMP_MODE: LAMP_OFF,
	K_LAMP_STRENGTH: 1.0,
	K_LAMP_REACH: 2.6,
	K_LAMP_LEVELS: 3.0,
	K_LAMP_CORE: 0.35,
	K_LAMP_DITHER: 0.5,
	K_SKY: SKY_OFF,
	K_SKY_OFFSET: 0.0,
	K_SKY_SCALE: 1.0,
	K_SKY_TINT: Color.WHITE,
}


## Fills in every key a partial framing omits. Callers should treat the result as the only
## valid thing to read from; a preset is authored as a diff against `DEFAULTS`, so indexing
## a raw preset will miss keys that were never written.
## Region colours first, then the framing over the top, so a preset that names a fog colour
## (the CRT one does) still wins while every other preset simply inherits the region's.
static func completeForRegion(framing: Dictionary, fogColor: Color, voidColor: Color) -> Dictionary:
	var result := complete(framing)
	if not framing.has(K_FOG_COLOR):
		result[K_FOG_COLOR] = fogColor
	if not framing.has(K_VOID_COLOR):
		result[K_VOID_COLOR] = voidColor
	return result


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
	# Defensive: a framing that never went through completeForRegion has no colours.
	material.set_shader_parameter(U_FOG_COLOR, f.get(K_FOG_COLOR, Color.WHITE))
	material.set_shader_parameter(U_VOID_COLOR, f.get(K_VOID_COLOR, Color.BLACK))
	material.set_shader_parameter(U_CURVATURE_K, f[K_CURVATURE])
	material.set_shader_parameter(U_CLOUD_STRENGTH, f[K_CLOUD_STRENGTH])
	material.set_shader_parameter(U_CLOUD_SCALE, f[K_CLOUD_SCALE])
	material.set_shader_parameter(U_CLOUD_SPEED, f[K_CLOUD_SPEED])
	material.set_shader_parameter(U_FILTER_MODE, f[K_FILTER_MODE])
	# A backdrop replaces the void: off-map fragments are discarded so the sky shows through.
	material.set_shader_parameter(U_SHOW_SKY_BEYOND, str(f[K_SKY]) != SKY_OFF)
