## AuroraVeilEffect over a hex footprint. Owned by HXB-11; the donor is not modified.
##
## A SUBCLASS RATHER THAN A COPY. GDScript methods are virtual, so overriding the one function
## carrying the square assumption inherits every other line of AuroraVeilEffect unchanged -- its
## authored timing, its density curves, its layers, its whole lifecycle. That is not a shortcut: a
## copied effect is a second thing to keep in step with the original, and this cycle's instruction
## is that the donors keep their appearance and behaviour exactly.
##
## This effect draws no ground wash. Its footprint reaches only `_applyPanelSize`, which the donor
## runs from the radius handed to it above, so feeding that radius is the whole correction.

class_name HexAuroraVeilEffect
extends AuroraVeilEffect

const HexVfxFootprintAdapterScript = preload(
	"res://src/presentation/battle/effects/HexVfxFootprintAdapter.gd"
)

var _hexFootprint: HexVfxFootprint = null
var _hexGroundSpan := 0.0
var _hexAreaShape := "circle"


static func createHexPlayback(
	parent: Node3D,
	worldPosition: Vector3,
	_elementColor: Color,
	overrides: Dictionary = {}
) -> HexAuroraVeilEffect:
	var playback := HexAuroraVeilEffect.new()
	playback.name = "HexAuroraVeilEffect"
	playback.position = worldPosition
	parent.add_child(playback)
	# Same order as the donor factory, for the same reason: geometry and shader uniforms are
	# assembled in _buildLayers, so overrides arriving afterwards would reach nothing.
	playback.set_tunable_overrides(overrides)
	playback._buildLayers()
	return playback


## The resolved cells this cast affects. Set before play(); every extent below derives from it.
func setHexFootprint(
	footprint: HexVfxFootprint, groundSpan := 0.0, areaShape := "circle"
) -> void:
	_hexFootprint = footprint
	_hexGroundSpan = groundSpan
	_hexAreaShape = areaShape
	if footprint == null or footprint.isEmpty():
		return
	setFootprint(
		HexVfxFootprintAdapterScript.equivalentSquareRadius(footprint), groundSpan, areaShape
	)


func hexFootprint() -> HexVfxFootprint:
	return _hexFootprint


## Feeds the donor the radius whose own diameter formula yields this footprint's true world span,
## then corrects what quantising a radius cannot express.
func setFootprint(radius: int, groundSpan: float, areaShape: String = "circle") -> void:
	super.setFootprint(radius, groundSpan, areaShape)
	if _hexFootprint == null or _hexFootprint.isEmpty():
		return
	# No ground wash on this effect: the donor's own _applyPanelSize has already run.
