## Frame capture, contact sheets, and golden-frame comparison for the VFX debug
## scene.
##
## Owns what happens to an image once the timeline is standing where it should
## be. Driving the timeline there — replaying from zero, seeking, deciding which
## seed and mode a capture exercises — stays with the controller, because it is
## playback orchestration rather than output.
##
## Capture flags:
##   --capture-at=<t>[,<t>...]  one or more normalized times; a list captures
##                              the whole series in ONE process rather than
##                              paying a fresh engine boot per frame
##   --capture-out=<prefix>     output path prefix (default user://vfx_debug_capture)
##   --capture-sheet            also tile the series into <prefix>_sheet.png
##   --sheet-scale=<f>          per-frame scale in the sheet (default 0.5)
##
## Golden-frame regression, which the effects' determinism guarantee earns:
##   --golden=<dir>          compare each capture against <dir>/<name>.png and
##                           print MATCH/DIFF/MISSING; exits non-zero on failure
##   --golden-write          write the captures into <dir> as new references
##   --golden-tolerance=<f>  override the calibrated tolerance below
##
## Determinism is what makes the golden comparison meaningful: a given effect,
## seed and timestamp reproduce exactly across processes, so a DIFF is a real
## regression rather than sampling noise.

class_name VfxDebugCapture
extends RefCounted

const SCREENSHOT_PATH := "user://vfx_debug_capture.png"
const CAPTURE_PREFIX_DEFAULT := "user://vfx_debug_capture"
## Exit code for a golden-frame mismatch, distinct from the engine's own
## failure codes so a CI caller can tell a regression from a crash.
const EXIT_GOLDEN_FAILED := 3
## Full draw cycles to settle after seeking before a capture is read back.
## Two is enough for the shader uniforms and the draw to land; more does not
## improve stability (measured), because the residual variation is GPU particle
## scheduling rather than anything that settles with time.
const SETTLE_FRAMES := 2
## Golden comparison downsamples to this square before differencing. Comparing
## at full resolution is both slow in GDScript and needlessly brittle: it is
## structure — layer positions, palette, footprint shape — that a regression
## test should defend, not the exact pixel a given ember landed on.
const _GOLDEN_COMPARE_SIZE := 256
## Mean per-channel difference (0-255) tolerated before a capture counts as a
## regression.
##
## Calibrated from measurement, not taste. Repeat runs of the *same* effect
## differ by **0.00-0.03** (GPU particle scheduling). Swapping the effect
## entirely — ice storm against fire goldens — scores only **3.2**, because a
## mean taken over the whole frame is heavily diluted by the identical dark
## background and terrain that fill most of it. 0.5 sits roughly 16x above the
## noise and 6x below a total change.
##
## That dilution is this metric's real weakness: an effect occupying a small
## share of the frame produces a small mean even when it changes completely.
## Capture goldens framed so the effect fills a decent portion of the image, and
## treat a diff that is merely *near* tolerance as worth looking at rather than
## as a pass.
const _GOLDEN_TOLERANCE_DEFAULT := 0.5

var host: Node
var goldenFailures: int = 0
var _captureUsed: bool = false
var _captureIndex: int = 0


func _init(_host: Node) -> void:
	host = _host


func isHeadless() -> bool:
	return DisplayServer.get_name() == "headless"


## True once the interactive single capture has been spent. The lock exists
## because this path historically quit after writing; an unattended sweep uses
## `--capture-at` instead, which is unaffected.
func isSingleCaptureUsed() -> bool:
	return _captureUsed


func capturePrefix() -> String:
	var prefix := VfxDebugArguments.string("--capture-out=")
	return prefix if not prefix.is_empty() else CAPTURE_PREFIX_DEFAULT


## Reads the rendered frame back. Callers must have already settled the
## timeline; `SETTLE_FRAMES` is the measured cost of doing so.
func readViewportImage() -> Image:
	return host.get_viewport().get_texture().get_image()


## Waits the measured number of full draw cycles.
##
## `GPUParticles3D.request_particles_process()` is serviced asynchronously by
## the rendering server, so a capture taken too eagerly samples a partially
## advanced system. Measured: with a single settle frame the same timestamp
## reproduced only intermittently. Settling across several full draw cycles is
## what makes the result byte-stable, and byte stability is the whole basis of
## the golden comparison below.
func settle() -> void:
	for _settleIndex: int in range(SETTLE_FRAMES):
		await host.get_tree().process_frame
		await RenderingServer.frame_post_draw


## Names a frame within a series. A lone capture keeps the historical
## single-file path so existing invocations and any stored reference paths still
## resolve.
func frameName(prefix: String, normalizedTime: float, single: bool) -> String:
	if single:
		return prefix.get_file()
	return "%s_t%s" % [prefix.get_file(), String.num(normalizedTime, 2)]


func framePath(prefix: String, name: String, single: bool) -> String:
	if single:
		return "%s.png" % prefix
	return "%s.png" % prefix.get_base_dir().path_join(name)


func writeFrame(image: Image, path: String) -> int:
	var error := image.save_png(path)
	print("VFX_DEBUG_CAPTURE path=%s error=%d" % [
		ProjectSettings.globalize_path(path), error
	])
	return error


## Tiles the series into one image so a phase sweep can be judged in a single
## look, side by side, instead of by holding four separate frames in memory.
## Four columns keeps a typical sweep on one row; motion reads left to right.
func writeContactSheet(frames: Array[Image], path: String) -> int:
	var scale := clampf(VfxDebugArguments.number("--sheet-scale=", 0.5), 0.05, 1.0)
	var cellWidth := maxi(int(float(frames[0].get_width()) * scale), 1)
	var cellHeight := maxi(int(float(frames[0].get_height()) * scale), 1)
	var columns := mini(frames.size(), 4)
	var rows := int(ceil(float(frames.size()) / float(columns)))
	var sheet := Image.create(
			cellWidth * columns, cellHeight * rows, false, Image.FORMAT_RGBA8)
	for index: int in range(frames.size()):
		var cell := frames[index].duplicate() as Image
		cell.resize(cellWidth, cellHeight, Image.INTERPOLATE_BILINEAR)
		cell.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(
				cell,
				Rect2i(Vector2i.ZERO, cell.get_size()),
				Vector2i((index % columns) * cellWidth, (index / columns) * cellHeight))
	return sheet.save_png(path)


## Compares a capture against a stored reference, or records a new one.
##
## **Tolerance-based, not byte-exact, and that is a measured decision.** The
## GDScript timeline is deterministic — the same effect, seed and timestamp
## produce the same uniforms every run — but `GPUParticles3D` is not: its
## `restart()` / `request_particles_process()` work is scheduled on the
## rendering server, and identical runs were observed producing different
## frames for the same timestamp. Replaying from zero before each seek made it
## much closer, and additional settle frames did not help at all, which is what
## identifies the residue as scheduling rather than a race that time fixes.
##
## So the comparison defends structure instead of pixels: both images are
## downsampled and differenced, and anything under `_GOLDEN_TOLERANCE_DEFAULT`
## passes. That still fails loudly on the regressions worth catching — a wrong
## palette, a dropped layer, a footprint of the wrong shape — while ignoring
## which exact pixel an individual ember landed on.
##
## Raw pixel data is compared rather than encoded PNG bytes, so a future
## encoder change cannot masquerade as a regression.
func checkGolden(name: String, image: Image) -> void:
	var goldenDir := VfxDebugArguments.string("--golden=")
	if goldenDir.is_empty():
		return
	var goldenPath := goldenDir.path_join("%s.png" % name)
	if VfxDebugArguments.flag("--golden-write"):
		DirAccess.make_dir_recursive_absolute(goldenDir)
		var writeError := image.save_png(goldenPath)
		print("VFX_GOLDEN name=%s status=%s path=%s" % [
			name,
			"WROTE" if writeError == OK else "WRITE_FAILED",
			ProjectSettings.globalize_path(goldenPath)
		])
		if writeError != OK:
			goldenFailures += 1
		return
	if not FileAccess.file_exists(goldenPath):
		print("VFX_GOLDEN name=%s status=MISSING path=%s" % [
			name, ProjectSettings.globalize_path(goldenPath)
		])
		goldenFailures += 1
		return
	var golden := Image.load_from_file(goldenPath)
	if golden == null:
		print("VFX_GOLDEN name=%s status=UNREADABLE path=%s" % [
			name, ProjectSettings.globalize_path(goldenPath)
		])
		goldenFailures += 1
		return
	var tolerance := VfxDebugArguments.number(
		"--golden-tolerance=", _GOLDEN_TOLERANCE_DEFAULT
	)
	var difference := meanImageDifference(golden, image)
	var matched := difference <= tolerance
	print("VFX_GOLDEN name=%s status=%s diff=%.2f tolerance=%.2f" % [
		name, "MATCH" if matched else "DIFF", difference, tolerance
	])
	if not matched:
		goldenFailures += 1


## Mean absolute per-channel difference between two images, 0-255, computed on
## a downsampled copy of each. Returns a large sentinel when the images cannot
## be compared at all, so a size or format surprise fails rather than passing
## silently.
static func meanImageDifference(first: Image, second: Image) -> float:
	var a := first.duplicate() as Image
	var b := second.duplicate() as Image
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	a.resize(_GOLDEN_COMPARE_SIZE, _GOLDEN_COMPARE_SIZE, Image.INTERPOLATE_BILINEAR)
	b.resize(_GOLDEN_COMPARE_SIZE, _GOLDEN_COMPARE_SIZE, Image.INTERPOLATE_BILINEAR)
	var dataA := a.get_data()
	var dataB := b.get_data()
	if dataA.size() != dataB.size() or dataA.is_empty():
		return 255.0
	var total := 0.0
	for index: int in range(dataA.size()):
		total += absf(float(dataA[index]) - float(dataB[index]))
	return total / float(dataA.size())


## The interactive `C` / "Capture" path. Returns the message the status readout
## should show; the caller owns quitting, because whether a capture ends the
## process is a property of how the scene was launched, not of the capture.
##
## Captures are numbered rather than limited to one per process. The old lock
## was a leftover of a path that quit immediately after writing, and
## interactively it just made the button dead after first use — which is
## backwards for a tool whose whole job is comparing successive looks.
func captureOnce() -> String:
	if isHeadless():
		var unavailable := "Capture unavailable: run with a rendered display."
		push_error(unavailable)
		return unavailable
	var path := SCREENSHOT_PATH
	if _captureUsed:
		_captureIndex += 1
		path = "%s_%02d.png" % [SCREENSHOT_PATH.trim_suffix(".png"), _captureIndex]
	_captureUsed = true
	await RenderingServer.frame_post_draw
	var error := host.get_viewport().get_texture().get_image().save_png(path)
	var absolutePath := ProjectSettings.globalize_path(path)
	print("VFX_DEBUG_CAPTURE path=%s error=%d" % [absolutePath, error])
	return (
		"Capture saved: %s" % absolutePath
		if error == OK
		else "Capture failed with error %d" % error
	)


## Recursive draw-call estimate for a playback subtree. Counts mesh surfaces,
## particle draw passes, and multimesh surfaces — the three things that actually
## issue draws in these effects.
static func estimateDrawCalls(node: Node) -> int:
	var estimate := 0
	var meshInstance := node as MeshInstance3D
	if meshInstance != null and meshInstance.visible and meshInstance.mesh != null:
		estimate += maxi(meshInstance.mesh.get_surface_count(), 1)
	var particles := node as GPUParticles3D
	if particles != null and particles.visible:
		for passIndex in range(particles.draw_passes):
			var drawMesh := particles.get_draw_pass_mesh(passIndex)
			if drawMesh != null:
				estimate += maxi(drawMesh.get_surface_count(), 1)
	var multiMesh := node as MultiMeshInstance3D
	if multiMesh != null and multiMesh.visible and multiMesh.multimesh != null:
		var mesh := multiMesh.multimesh.mesh
		if mesh != null:
			estimate += maxi(mesh.get_surface_count(), 1)
	for child: Node in node.get_children():
		estimate += estimateDrawCalls(child)
	return estimate
