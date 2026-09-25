## The cubes one sample of a playback emits, in emission order.
##
## Preallocated to the playback's capacity when it is prepared and only
## overwritten afterwards, so sampling a timeline allocates nothing. A cube
## past capacity is counted in `overflow` rather than written: the capacity is
## the composition's declared peak, so an overflow is a composition that under-
## declared, which the substrate probe fails on. It is never a budget cut.

class_name CubePlaceholderPoseBuffer
extends RefCounted

var capacity: int = 0
var count: int = 0
var overflow: int = 0
## World-space cube centres.
var positions: PackedVector3Array = PackedVector3Array()
## World-space cube edge length.
var sizes: PackedFloat32Array = PackedFloat32Array()
var yaws: PackedFloat32Array = PackedFloat32Array()
## Index into the composition's `roles()`.
var roles: PackedInt32Array = PackedInt32Array()
## Stable per-composition cube identity; picks the palette row.
var ids: PackedInt32Array = PackedInt32Array()
var opacities: PackedFloat32Array = PackedFloat32Array()
## Which anchor's frame emitted the cube.
var anchors: PackedInt32Array = PackedInt32Array()


func _init(initialCapacity: int = 0) -> void:
	reserve(initialCapacity)


## Grows only. Called while preparing a playback, never while sampling.
func reserve(newCapacity: int) -> void:
	if newCapacity <= capacity:
		return
	capacity = newCapacity
	positions.resize(capacity)
	sizes.resize(capacity)
	yaws.resize(capacity)
	roles.resize(capacity)
	ids.resize(capacity)
	opacities.resize(capacity)
	anchors.resize(capacity)


func clear() -> void:
	count = 0
	overflow = 0


func push(
		id: int, position: Vector3, size: float, yaw: float, role: int,
		opacity: float, anchor: int) -> void:
	if count >= capacity:
		overflow += 1
		return
	positions[count] = position
	sizes[count] = size
	yaws[count] = yaw
	roles[count] = role
	ids[count] = id
	opacities[count] = opacity
	anchors[count] = anchor
	count += 1
