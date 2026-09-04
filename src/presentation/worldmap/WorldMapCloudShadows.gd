## The clouds' shadows, drawn as coverage in MAP-PIXEL space.
##
## A `SubViewport` the size of the region in map pixels, holding one `Node2D` that blits each
## shadow piece at its whole-pixel position. The ground shader then samples the result with the
## region's own UV, exactly as it samples the cast-shadow mask.
##
## WHY MAP SPACE AND NOT A QUAD ON THE GROUND. A ground-level quad is what a 3D engine makes
## easy: fewer pixels, no extra texture, no viewport. It is also why procedural shadows do not
## look painted. Its edge lands at arbitrary sub-pixel positions and angles that do not align to
## the map's grid, and it crawls under camera motion; no edge treatment repairs that. Map space
## buys pixel-aligned edges, free fog and curvature and filtering -- because the shadow rides
## the ground's own sample, it IS the ground -- and one thing more that the cast shadows did not
## need: clouds MOVE and can overlap, and two alpha-blended quads that overlap make a darker
## patch where a mask unions.
##
## THE COST ARGUMENT DOES NOT APPLY HERE. temp2 is 248x176 map pixels. A viewport at that size
## is smaller than a thumbnail, and no reasoning that begins with its expense is about anything
## real.
##
## The art's own colours are deliberately thrown away. The artist painted the shadows in temp2's
## shadowed sea and shadowed sand -- shadowed TERRAIN rather than a translucent overlay, which
## is the same answer the standing structures' shadows reached -- and a fixed-colour shadow is
## only right over the terrain it was painted for. So this writes COVERAGE, white on black, and
## the ground derives the colour by darkening itself and snapping to its own palette.

class_name WorldMapCloudShadows
extends SubViewport

const CloudCatalog = preload("res://src/presentation/worldmap/WorldMapCloudCatalog.gd")

var _painter: Node2D
var _setID := ""
var _pieces: Array = []
var _silhouette: ImageTexture
var _field: Array = []
var _size := Vector2i(2, 2)


func _init() -> void:
	# The layer is redrawn every time the field moves, which is every frame the wind blows, so
	# it updates always rather than once. Its cost is one 248x176 clear and a handful of blits.
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Coverage, not colour: black is "no shadow" and the ground's sampler reads the red channel.
	transparent_bg = false
	disable_3d = true
	# The mask is read at its own resolution by a nearest sampler; nothing here is ever
	# magnified by the viewport itself.
	canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST


func _ready() -> void:
	if _painter == null:
		_painter = Node2D.new()
		_painter.draw.connect(_onDraw)
		add_child(_painter)


## Points the layer at a region and a cloud set. Safe to call again.
func configure(mapPixels: Vector2i, setID: String) -> void:
	_ready()
	_size = Vector2i(maxi(2, mapPixels.x), maxi(2, mapPixels.y))
	if size != _size:
		size = _size
	if setID != _setID:
		_setID = setID
		_pieces = CloudCatalog.pieces(setID)
		_silhouette = _buildSilhouette(CloudCatalog.textureFor(setID))
	_painter.queue_redraw()


## Takes the field WorldMapClouds already placed, rather than recomputing it. Two derivations of
## the same positions is two chances for a shadow to sit under nothing.
func setField(field: Array) -> void:
	_field = field
	if _painter != null:
		_painter.queue_redraw()


func shadowTexture() -> ViewportTexture:
	return get_texture()


func mapSize() -> Vector2i:
	return _size


func _onDraw() -> void:
	_painter.draw_rect(Rect2(Vector2.ZERO, Vector2(_size)), Color.BLACK)
	if _silhouette == null or _pieces.is_empty():
		return
	for entry in _field:
		var record: Dictionary = entry
		if not bool(record.get("cast", false)):
			continue
		var piece: Dictionary = _pieces[int(record["piece"]) % _pieces.size()]
		var rect: Rect2i = piece["shadow"]
		var at: Vector2i = record["shadow"]
		var drawn := Vector2(rect.size)
		# WRAPPED IN BOTH AXES, up to four copies. A shadow straddling the map's edge has to
		# appear on both sides or it is clipped away as its cloud crosses the coast -- and that
		# only shows when one is straddling, which is exactly when nobody is looking.
		for dx in [-_size.x, 0, _size.x]:
			for dy in [-_size.y, 0, _size.y]:
				var corner := Vector2(float(at.x + dx), float(at.y + dy))
				if corner.x > float(_size.x) or corner.y > float(_size.y):
					continue
				if corner.x + drawn.x < 0.0 or corner.y + drawn.y < 0.0:
					continue
				_painter.draw_texture_rect_region(
					_silhouette, Rect2(corner, drawn), Rect2(rect), Color.WHITE
				)


## A white copy of the sheet, keeping only its alpha.
##
## The layer carries COVERAGE, and the art carries colour -- blitting the sheet directly would
## write the artist's shadowed-sea teal into a mask the ground reads as "how much shadow", which
## would then be darkest where the art happened to be brightest. Built once per set, from a
## 256x256 image.
func _buildSilhouette(sheet: Texture2D) -> ImageTexture:
	if sheet == null:
		return null
	var source := sheet.get_image()
	if source == null:
		return null
	var white := Image.create_empty(
		source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8
	)
	for y in source.get_height():
		for x in source.get_width():
			var opaque := source.get_pixel(x, y).a > 0.5
			white.set_pixel(x, y, Color.WHITE if opaque else Color(1.0, 1.0, 1.0, 0.0))
	return ImageTexture.create_from_image(white)
