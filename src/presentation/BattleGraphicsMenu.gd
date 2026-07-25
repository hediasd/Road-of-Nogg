## Builds the translucent in-battle rendering controls.

class_name BattleGraphicsMenu
extends RefCounted


static func build(
		canvas: CanvasLayer,
		toggleButton: BaseButton,
		callbacks: Dictionary) -> Dictionary:
	var panel = PanelContainer.new()
	panel.name = "GraphicsPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -420
	panel.offset_top = 70
	panel.offset_right = -20
	panel.offset_bottom = 590
	panel.visible = false

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.035, 0.075, 0.78)
	style.border_color = Color(0.25, 0.68, 1.0, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)

	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)

	var header = HBoxContainer.new()
	column.add_child(header)
	var title = Label.new()
	title.text = "GRAPHICS"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var closeButton = Button.new()
	closeButton.text = "Close"
	closeButton.pressed.connect(func(): toggleButton.button_pressed = false)
	header.add_child(closeButton)

	var subtitle = Label.new()
	subtitle.text = "Changes apply live. The battle keeps running."
	subtitle.modulate = Color(0.76, 0.86, 0.98)
	column.add_child(subtitle)

	var options = GridContainer.new()
	options.columns = 2
	options.add_theme_constant_override("h_separation", 12)
	options.add_theme_constant_override("v_separation", 7)
	column.add_child(options)

	var lookOption = _add_option(
		options,
		"Look",
		["PS1 Soft", "Retro Light", "PS1 Classic", "CRT", "Clean"],
		["ps1_soft", "retro_light", "ps1_classic", "crt", "clean"]
	)
	lookOption.item_selected.connect(callbacks["preset_selected"])
	var geometryOption = _add_option(
		options,
		"Geometry",
		["Vertex jitter", "Stable"],
		["jitter", "stable"]
	)
	geometryOption.item_selected.connect(callbacks["feature_selected"])
	var textureOption = _add_option(
		options,
		"Textures",
		["Affine", "Perspective"],
		["affine", "perspective"]
	)
	textureOption.item_selected.connect(callbacks["feature_selected"])

	var separator = HSeparator.new()
	column.add_child(separator)
	var crtTitle = Label.new()
	crtTitle.text = "CRT TUNING"
	crtTitle.add_theme_font_size_override("font_size", 16)
	column.add_child(crtTitle)

	var crtHint = Label.new()
	crtHint.text = "Select CRT above, then tune while watching the fight."
	crtHint.modulate = Color(0.72, 0.8, 0.92)
	crtHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(crtHint)

	var sliders: Dictionary = {}
	sliders["scanline"] = _add_slider(
		column, "Scanlines", 0.0, 0.5, 0.01, 0.22,
		callbacks["crt_parameter_changed"], "scanline"
	)
	sliders["mask"] = _add_slider(
		column, "RGB mask", 0.0, 0.3, 0.01, 0.1,
		callbacks["crt_parameter_changed"], "mask"
	)
	sliders["vignette"] = _add_slider(
		column, "Vignette", 0.0, 0.6, 0.01, 0.2,
		callbacks["crt_parameter_changed"], "vignette"
	)
	sliders["flicker"] = _add_slider(
		column, "Flicker", 0.0, 0.1, 0.002, 0.02,
		callbacks["crt_parameter_changed"], "flicker"
	)
	sliders["color_bleed"] = _add_slider(
		column, "Color bleed", 0.0, 4.0, 0.1, 0.8,
		callbacks["crt_parameter_changed"], "color_bleed"
	)

	return {
		"panel": panel,
		"look_option": lookOption,
		"geometry_option": geometryOption,
		"texture_option": textureOption,
		"crt_hint": crtHint,
		"crt_sliders": sliders
	}


static func _add_option(
		grid: GridContainer,
		labelText: String,
		labels: Array[String],
		values: Array[String]) -> OptionButton:
	var label = Label.new()
	label.text = labelText
	grid.add_child(label)
	var option = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in range(labels.size()):
		option.add_item(labels[index])
		option.set_item_metadata(index, values[index])
	grid.add_child(option)
	return option


static func _add_slider(
		parent: Control,
		labelText: String,
		minimum: float,
		maximum: float,
		step: float,
		initialValue: float,
		callback: Callable,
		parameter: String) -> Dictionary:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label = Label.new()
	label.text = labelText
	label.custom_minimum_size.x = 92
	row.add_child(label)

	var slider = HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initialValue
	slider.value_changed.connect(callback.bind(parameter))
	row.add_child(slider)

	var valueLabel = Label.new()
	valueLabel.custom_minimum_size.x = 48
	valueLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(valueLabel)
	return {"slider": slider, "value_label": valueLabel}