## How a donor area effect is told the truth about a hex footprint without being rewritten.
##
## THE PROBLEM, EXACTLY. Every donor area effect takes `setFootprint(radiusInTiles, ...)` and
## turns it into a world extent with `diameter := radius * 2 + 1` -- the bounding box of a
## Manhattan diamond of that radius, which is what a square board's circle spell was. On a hex
## board the resolved set is a hex disc, and its bounding box is neither that size nor square: a
## disc of radius R spans `3R + 2` world units across the columns, against the donors' `2R + 1`.
## At radius 4 that is 14 units of affected ground drawn as 9.
##
## WHAT THIS DOES INSTEAD OF COPYING EIGHT HUNDRED LINES. The donors' extent maths is correct
## *given* a diameter; only the diameter is wrong. So the hex subclasses feed the donor the radius
## whose own formula yields the true hex extent, and let every line of authored geometry, timing
## and density downstream of it run exactly as it always has. Nothing is duplicated, so nothing can
## drift, which is the same reason `WorldMapSceneExport` keeps one `configureGround` for both the
## preview and the export.
##
## The quantisation is real and is bounded at half a cell: `2R' + 1` lands on odd integers, so a
## hex extent between two of them takes the nearer. That is a sub-cell error in a wash whose own
## rim is softer than that, and it is the price of not maintaining a second copy of five effects.
## Where the error would be VISIBLE -- the ground silhouette, which is the thing a player reads
## cells off -- it is not paid at all: `applyGroundWash` sets the exact extent and the exact
## affected-cell mask afterwards.

class_name HexVfxFootprintAdapter
extends RefCounted

const HexVfxGroundWashScript = preload("res://src/presentation/battle/effects/HexVfxGroundWash.gd")


## The donor radius whose `2R + 1` diameter best matches this footprint's real world span.
##
## Never below 1: every donor clamps its own radius there, and a zero would collapse geometry the
## profiles assume is present.
static func equivalentSquareRadius(footprint: HexVfxFootprint) -> int:
	if footprint == null or footprint.isEmpty():
		return 1
	var diameter := footprint.worldDiameter()
	return maxi(int(round((diameter - 1.0) * 0.5)), 1)


## Replaces a donor's ground wash with the footprint's own silhouette, at its exact extent.
##
## Called AFTER the donor's `setFootprint` has run, so it overwrites the quantised radial mesh and
## the shared diamond mask with the real thing. `groundMesh` keeps whatever height the donor gave
## it -- that is the wash's thickness above the floor, an authored value this item does not touch.
static func applyGroundWash(
	groundMesh: CylinderMesh, groundMaterial: StandardMaterial3D, footprint: HexVfxFootprint
) -> void:
	if footprint == null or footprint.isEmpty():
		return
	if groundMesh != null:
		var radius := footprint.worldDiameter() * 0.5
		groundMesh.top_radius = radius
		groundMesh.bottom_radius = radius
	if groundMaterial != null:
		var texture := HexVfxGroundWashScript.forFootprint(footprint)
		groundMaterial.albedo_texture = texture
		groundMaterial.emission_texture = texture
