## WME-2's self-contained validation: the editor camera adds freedoms without moving the
## shipping contract, and hands the camera back to it exactly.
##
##  1. CONTRACT IDENTITY. For every framing preset, a plain `WorldMapCameraRig` and a
##     `WorldMapEditorCamera` in contract mode place the camera identically and report the same
##     framing readout. This is the assertion the subclassing exists to make checkable: if the
##     editor rig reimplemented placement it could only ever be asserted "close".
##  2. SNAP RESTORES. After orbiting, dollying, panning and dropping to orthographic, one call to
##     `snapToContract()` returns every field -- position, rotation, FOV and projection -- to what
##     the preset specifies. Restoring all but one field is the failure this catches.
##  3. FOCUS STABLE UNDER ORBIT. Through a full 360 degrees, at three curvatures, the camera keeps
##     looking at the focus AS THE SHADER DRAWS IT. Orbiting around y = 0 instead leaves an error
##     that grows with the square of distance -- invisible close in, gross far out -- and it looks
##     like the map sliding under the cursor.

extends SceneTree

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const FramingCatalog = preload("res://src/presentation/worldmap/WorldMapFramingCatalog.gd")
const EditorCamera = preload("res://src/presentation/worldmap/editor/WorldMapEditorCamera.gd")

const EPSILON := 0.0005

var _failures := 0


func _initialize() -> void:
	var pristine := WorldMapCameraRig.new()
	var editor: EditorCamera = EditorCamera.new()
	root.add_child(pristine)
	root.add_child(editor)

	_checkContractIdentity(pristine, editor)
	_checkSnapRestores(pristine, editor)
	_checkFocusUnderOrbit(editor)
	_checkContractToFreeIsContinuous(editor)
	_checkSkyUnderFreeLook(editor)

	print("")
	print("probe_editor_camera: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	if _failures == 0:
		print("WORLD MAP EDITOR CAMERA OK")
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _presets() -> Array:
	return FramingCatalog.values()


## Every field that decides what the camera sees, so "identical" means identical rather than
## "identical in the two properties this probe happened to compare".
func _snapshot(camera: Camera3D) -> Dictionary:
	return {
		"position": camera.position,
		"rotation": camera.rotation_degrees,
		"fov": camera.fov,
		"projection": camera.projection,
		"keep_aspect": camera.keep_aspect,
	}


func _sameSnapshot(a: Dictionary, b: Dictionary) -> String:
	for key in a:
		var left = a[key]
		var right = b[key]
		if left is Vector3:
			if not (left as Vector3).is_equal_approx(right as Vector3):
				return "%s %s vs %s" % [key, left, right]
		elif left is float:
			if absf(float(left) - float(right)) > EPSILON:
				return "%s %f vs %f" % [key, left, right]
		elif left != right:
			return "%s %s vs %s" % [key, left, right]
	return ""


func _sameReadout(a: Dictionary, b: Dictionary) -> String:
	for key in a:
		var left = a[key]
		var right = b[key]
		if left is float and absf(float(left) - float(right)) > EPSILON:
			return "%s %f vs %f" % [key, left, right]
		if left is Vector2 and not (left as Vector2).is_equal_approx(right as Vector2):
			return "%s %s vs %s" % [key, left, right]
		if left is bool and left != right:
			return "%s %s vs %s" % [key, left, right]
	return ""


func _checkContractIdentity(pristine: WorldMapCameraRig, editor: EditorCamera) -> void:
	print("-- contract mode is the shipping rig --")
	var window := Vector2i(1152, 648)
	for id in _presets():
		var framing: Dictionary = FramingCatalog.framingFor(id)
		pristine.applyFraming(framing)
		pristine.panTo(Vector2(12.0, 20.0))
		editor.snapToContract()
		editor.applyFraming(framing)
		editor.panTo(Vector2(12.0, 20.0))
		var diff := _sameSnapshot(_snapshot(pristine), _snapshot(editor))
		if not diff.is_empty():
			_fail("%s placement differs: %s" % [id, diff])
			continue
		var readoutDiff := _sameReadout(
			pristine.framingReadout(window), editor.framingReadout(window)
		)
		if not readoutDiff.is_empty():
			_fail("%s readout differs: %s" % [id, readoutDiff])
			continue
		print("  ok    %-16s identical placement and readout" % id)


func _checkSnapRestores(pristine: WorldMapCameraRig, editor: EditorCamera) -> void:
	print("-- snap to contract restores every field --")
	for id in _presets():
		var framing: Dictionary = FramingCatalog.framingFor(id)
		pristine.applyFraming(framing)
		pristine.panTo(Vector2(12.0, 20.0))

		editor.snapToContract()
		editor.applyFraming(framing)
		editor.panTo(Vector2(12.0, 20.0))
		# Leave nothing at its contract value: yaw, pitch, distance, focus and projection.
		editor.orbitBy(137.0, -21.0)
		editor.dollyBy(4.0)
		editor.panBy(Vector2(220.0, -140.0))
		editor.toggleOrtho()
		editor.dollyBy(-2.0)
		if editor.offContractReason().is_empty():
			_fail("%s reports on-contract while orthographic and orbited" % id)

		editor.snapToContract()
		editor.panTo(Vector2(12.0, 20.0))
		var diff := _sameSnapshot(_snapshot(pristine), _snapshot(editor))
		if not diff.is_empty():
			_fail("%s not restored: %s" % [id, diff])
			continue
		if not editor.offContractReason().is_empty():
			_fail("%s still reports off-contract after the snap" % id)
			continue
		print("  ok    %-16s restored, and reports on-contract" % id)


## The camera must look at the focus as the SHADER draws it: fallen by `k * d^2` at its own view
## depth, which under an orbit is the orbit distance itself.
func _checkFocusUnderOrbit(editor: EditorCamera) -> void:
	print("-- focus holds through a full orbit --")
	var framing: Dictionary = FramingCatalog.framingFor(FramingCatalog.OVERLAND).duplicate(true)
	for k: float in [0.0, 0.003, 0.02]:
		framing[Uniforms.K_CURVATURE] = k
		editor.snapToContract()
		editor.applyFraming(framing)
		editor.panTo(Vector2(24.0, 32.0))
		editor.setFree()
		var worstAim := 0.0
		var worstFocus := 0.0
		var start: Vector2 = editor.focus
		for step in range(72):
			editor.orbitBy(5.0, 0.0)
			var dist: float = editor.distance
			# The camera's OWN settled drop, not `k * distance^2`. An earlier version of this
			# probe used the latter and so confirmed the same mistake the camera was making --
			# see `WorldMapEditorCamera._drawnFocus`. Cross-checked below against the shipping
			# rig's independent solve, so this is not self-confirming a second time.
			var drop: float = editor.curveDropAt(dist, k)
			var expected := Vector3(start.x, -drop, start.y)
			# Where the camera is actually looking, one orbit distance along its own forward axis.
			var forward: Vector3 = -editor.transform.basis.z.normalized()
			var aimed: Vector3 = editor.position + forward * editor.distance
			worstAim = maxf(worstAim, (aimed - expected).length())
			worstFocus = maxf(worstFocus, (editor.focus - start).length())
		if worstAim > 0.01:
			_fail("k=%s: aim drifts %.4f units off the drawn focus" % [k, worstAim])
			continue
		if worstFocus > EPSILON:
			_fail("k=%s: orbit moved the focus by %.4f units" % [k, worstFocus])
			continue
		print("  ok    k=%-6s aim within %.5f units over 360 degrees" % [k, worstAim])


## Engaging free look must not MOVE the camera -- it should pick up exactly where the contract
## placement left off. This is what caught `_drawnFocus`'s fixed-point bug being wrong at high
## curvature: the two placements are derived completely independently (the parent solves from a
## height, the editor from an orbit distance) and must still land in the same place, so agreement
## here is real evidence rather than one formula checking itself.
func _checkContractToFreeIsContinuous(editor: EditorCamera) -> void:
	print("-- engaging free look does not move the camera --")
	var framing: Dictionary = FramingCatalog.framingFor(FramingCatalog.CURVED_CLOSE).duplicate(true)
	for k: float in [0.0, 0.0039, 0.02]:
		framing[Uniforms.K_CURVATURE] = k
		editor.snapToContract()
		editor.applyFraming(framing)
		editor.panTo(Vector2(24.0, 32.0))
		var contractPosition := editor.position
		editor.setFree()
		var freePosition := editor.position
		var moved := (freePosition - contractPosition).length()
		if moved > 0.01:
			_fail("k=%s: engaging free look moved the camera %.3f units" % [k, moved])
			continue
		print("  ok    k=%-6s free look picks up within %.5f units" % [k, moved])


## The backdrop is a quad parented to the camera, so it follows an orbit for free. Orthographic is
## the case worth checking: the quad is sized from `camera.fov`, which an orthographic projection
## does not use.
func _checkSkyUnderFreeLook(editor: EditorCamera) -> void:
	print("-- backdrop under free look --")
	var framing: Dictionary = FramingCatalog.framingFor(FramingCatalog.OVERLAND).duplicate(true)
	# The case worth testing is the backdrop ON. With it off `applyFraming` returns before it
	# places anything, so an "is it still camera-local" assertion there would pass vacuously.
	framing[Uniforms.K_SKY] = WorldMapSkyCatalog.TEMP2_SUNSET
	editor.snapToContract()
	editor.applyFraming(framing)
	var sky := WorldMapSky.new()
	editor.add_child(sky)
	sky.applyFraming(framing, editor, Vector2(1152.0, 648.0))
	if not sky.visible:
		_fail("backdrop did not become visible for sky '%s'" % WorldMapSkyCatalog.TEMP2_SUNSET)
	editor.orbitBy(90.0, 0.0)
	editor.panBy(Vector2(180.0, 90.0))
	if sky.position != Vector3(0.0, 0.0, -WorldMapSky.DISTANCE) or sky.rotation != Vector3.ZERO:
		_fail("backdrop left camera-local placement under orbit: %s %s" % [
			sky.position, sky.rotation
		])
	else:
		print("  ok    stays camera-local through orbit and pan, so it cannot swim")
	editor.toggleOrtho()
	var quadHeight: float = 2.0 * WorldMapSky.DISTANCE * tan(deg_to_rad(editor.fov) * 0.5)
	if quadHeight <= editor.size:
		_fail("orthographic frame is %.1f units tall but the backdrop quad is %.1f" % [
			editor.size, quadHeight
		])
	else:
		print("  ok    orthographic frame %.0f units vs a %.0f unit quad -- over-covers, safe" % [
			editor.size, quadHeight
		])
	sky.queue_free()
	editor.snapToContract()
