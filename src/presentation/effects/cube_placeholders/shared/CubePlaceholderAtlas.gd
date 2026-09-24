## Paints the fake-3D cube sprite atlas: twelve quarter-turn frames across, one
## row per palette down. Several elements therefore share one texture and one
## draw call; a cube picks its palette by row.
##
## The frame construction is COPIED from `ElementalCubeRitualEffect` (the exact
## source pose, then eleven reconstructed rotation frames using the same three
## palette roles). It is a copy by design: the rituals are a protected surface.

class_name CubePlaceholderAtlas
extends RefCounted

const Profile = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderProfile.gd")


## One atlas row per palette, in the order given. Built once per playback,
## before play; the caller owns the returned texture and frees it with itself.
static func build(palettes: Array) -> ImageTexture:
	var frameSize := Profile.SPRITE_FRAME_SIZE_PX
	var frameCount := Profile.SPRITE_ROTATION_FRAMES
	var rows := maxi(palettes.size(), 1)
	var atlas := Image.create(frameSize * frameCount, frameSize * rows, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for row: int in range(palettes.size()):
		var palette: Array[Color] = []
		palette.assign(palettes[row])
		var offsetY := row * frameSize
		_paintSourceFrame(atlas, offsetY, palette)
		for frameIndex in range(1, frameCount):
			_paintRotationFrame(atlas, frameIndex, offsetY, palette)
	return ImageTexture.create_from_image(atlas)


## The quarter-turn frame a yaw shows. A cube is symmetric under a quarter
## turn, so twelve frames cover every yaw.
static func frameForYaw(yaw: float) -> int:
	var quarterTurn := PI * 0.5
	var quarterProgress := fposmod(yaw, quarterTurn) / quarterTurn
	return mini(
		int(floor(quarterProgress * float(Profile.SPRITE_ROTATION_FRAMES))),
		Profile.SPRITE_ROTATION_FRAMES - 1
	)


static func _paintSourceFrame(atlas: Image, offsetY: int, palette: Array[Color]) -> void:
	for y in range(Profile.SOURCE_FRAME_ROWS.size()):
		var row: String = Profile.SOURCE_FRAME_ROWS[y]
		for x in range(row.length()):
			match row.substr(x, 1):
				"D": atlas.set_pixel(x, offsetY + y, palette[0])
				"M": atlas.set_pixel(x, offsetY + y, palette[1])
				"S": atlas.set_pixel(x, offsetY + y, palette[2])


static func _paintRotationFrame(
		atlas: Image, frameIndex: int, offsetY: int, palette: Array[Color]) -> void:
	var angle := float(frameIndex) / float(Profile.SPRITE_ROTATION_FRAMES) * PI * 0.5
	var vertices: Array[Vector3] = [
		Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5),
		Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5),
		Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5),
		Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5),
	]
	for vertexIndex in range(vertices.size()):
		vertices[vertexIndex] = _rotateVertex(vertices[vertexIndex], angle)
	var projected: Array[Vector2] = []
	for vertex: Vector3 in vertices:
		projected.append(_projectVertex(vertex))
	var faceSpecs: Array[Dictionary] = [
		{"indices": PackedInt32Array([3, 2, 6, 7]), "normal": Vector3.UP},
		{"indices": PackedInt32Array([1, 5, 6, 2]), "normal": Vector3.RIGHT},
		{"indices": PackedInt32Array([0, 3, 7, 4]), "normal": Vector3.LEFT},
		{"indices": PackedInt32Array([4, 7, 6, 5]), "normal": Vector3.BACK},
		{"indices": PackedInt32Array([0, 1, 2, 3]), "normal": Vector3.FORWARD},
	]
	var cameraDirection := Vector3(-1.0, 1.0, -1.0).normalized()
	var topFace: Array[Vector2] = []
	var offsetX := frameIndex * Profile.SPRITE_FRAME_SIZE_PX
	for faceSpec: Dictionary in faceSpecs:
		var normal: Vector3 = _rotateVertex(faceSpec["normal"], angle)
		if normal.dot(cameraDirection) <= 0.001:
			continue
		var points: Array[Vector2] = []
		for vertexIndex: int in faceSpec["indices"]:
			points.append(projected[vertexIndex])
		if normal.y > 0.5:
			topFace = points
			continue
		var centroidX := 0.0
		for point: Vector2 in points:
			centroidX += point.x
		centroidX /= float(points.size())
		_fillPolygon(atlas, offsetX, offsetY, points, palette[2] if centroidX < 15.5 else palette[1])
	if not topFace.is_empty():
		_fillPolygon(atlas, offsetX, offsetY, topFace, palette[0])


static func _rotateVertex(vertex: Vector3, angle: float) -> Vector3:
	var cosine := cos(angle)
	var sine := sin(angle)
	return Vector3(
		vertex.x * cosine + vertex.z * sine,
		vertex.y,
		-vertex.x * sine + vertex.z * cosine
	)


static func _projectVertex(vertex: Vector3) -> Vector2:
	return Vector2(
		15.5 + (vertex.x - vertex.z) * 15.5,
		15.5 - (vertex.x + vertex.z) * 7.0 - vertex.y * 14.0
	)


static func _fillPolygon(
		atlas: Image, offsetX: int, offsetY: int, points: Array[Vector2], color: Color) -> void:
	var size := Profile.SPRITE_FRAME_SIZE_PX
	var minimumX := size - 1
	var maximumX := 0
	var minimumY := size - 1
	var maximumY := 0
	for point: Vector2 in points:
		minimumX = mini(minimumX, floori(point.x))
		maximumX = maxi(maximumX, ceili(point.x))
		minimumY = mini(minimumY, floori(point.y))
		maximumY = maxi(maximumY, ceili(point.y))
	minimumX = clampi(minimumX, 0, size - 1)
	maximumX = clampi(maximumX, 0, size - 1)
	minimumY = clampi(minimumY, 0, size - 1)
	maximumY = clampi(maximumY, 0, size - 1)
	for y in range(minimumY, maximumY + 1):
		for x in range(minimumX, maximumX + 1):
			if _pointInside(Vector2(float(x) + 0.5, float(y) + 0.5), points):
				atlas.set_pixel(offsetX + x, offsetY + y, color)


static func _pointInside(point: Vector2, polygon: Array[Vector2]) -> bool:
	var inside := false
	var previous := polygon.size() - 1
	for current in range(polygon.size()):
		var a: Vector2 = polygon[current]
		var b: Vector2 = polygon[previous]
		if (a.y > point.y) != (b.y > point.y):
			var boundaryX := (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
			if point.x < boundaryX:
				inside = not inside
		previous = current
	return inside
