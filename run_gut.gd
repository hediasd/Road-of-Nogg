extends SceneTree

var gut

func _init():
	gut = load("res://addons/gut/gut.gd").new()
	get_root().add_child(gut)
	gut.add_directory("res://tests")
	gut.set_junit_xml_file("res://gut_report.xml")
	gut.set_junit_xml_export_enabled(true)
	gut.test_scripts()

func _process(delta):
	if gut and gut.get_is_running():
		return false
	else:
		quit(0)
		return true
