## The arithmetic between three rectangles the workspace has to keep agreeing: the stage Control
## the layout hands the map, the `Display` TextureRect that shows the rendered buffer, and the
## buffer's own pixels that a pick has to land in.
##
## WHY THIS IS NOT IN THE CONTROLLER. `Display` is a sibling of the `Ui` CanvasLayer, not a child
## of the layout, so nothing positions it automatically: the layout measures where the map column
## actually ended up and the controller copies that onto `Display`. That copy plus the
## letterboxing inside it was previously inline arithmetic in two places, which is exactly the
## shape of thing that drifts when a panel changes width. Pure statics here instead, so a probe
## can assert the mapping without a window, a camera or a document.
##
## THE STAGE IS MEASURED, NEVER ASSUMED. `stageToDisplay` takes the rect layout actually produced.
## A collapsed panel, a narrow window or a frame before layout has settled can all report a
## degenerate stage, and a zero-or-negative viewport is not a smaller map, it is a render target
## that cannot be built -- so the result is floored at `MINIMUM` rather than passed through.

class_name WorldMapWorkspaceGeometry
extends RefCounted

## Small enough never to fight a real layout, large enough that the buffer, the framing aspect and
## the sky quad all stay computable during a collapse or a resize.
const MINIMUM := Vector2(160.0, 120.0)


## Where `Display` must sit to cover exactly the stage the layout produced. Returned in the same
## global coordinates `Control.get_global_rect()` reports, which is what `Display`'s offsets take.
static func stageToDisplay(stageRect: Rect2) -> Rect2:
	return Rect2(stageRect.position, Vector2(
		maxf(stageRect.size.x, MINIMUM.x),
		maxf(stageRect.size.y, MINIMUM.y),
	))


## The part of `Display` the buffer is actually drawn into. `Display` keeps aspect (its stretch
## mode letterboxes), so the drawn image is centred and is generally smaller than the control.
## Returns an empty rect for a degenerate input rather than dividing by zero.
static func drawnRect(displayRect: Rect2, bufferSize: Vector2) -> Rect2:
	if displayRect.size.x <= 0.0 or displayRect.size.y <= 0.0:
		return Rect2()
	if bufferSize.x <= 0.0 or bufferSize.y <= 0.0:
		return Rect2()
	var scale := minf(displayRect.size.x / bufferSize.x, displayRect.size.y / bufferSize.y)
	var drawnSize := bufferSize * scale
	return Rect2(displayRect.position + (displayRect.size - drawnSize) * 0.5, drawnSize)


## Where a screen position lands in buffer pixels, or null when it lands outside the drawn image.
## Null rather than a clamped edge pixel on purpose: a click in the letterbox margin is not a
## click on the map, and answering with the nearest cell is how an edit lands somewhere the author
## did not point at.
static func bufferPoint(
	screenPosition: Vector2, displayRect: Rect2, bufferSize: Vector2
) -> Variant:
	var drawn := drawnRect(displayRect, bufferSize)
	if drawn.size.x <= 0.0 or drawn.size.y <= 0.0:
		return null
	if not drawn.has_point(screenPosition):
		return null
	var scale := drawn.size.x / bufferSize.x
	return (screenPosition - drawn.position) / scale
