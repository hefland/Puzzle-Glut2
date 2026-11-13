extends Node
## Dev-only smoke test (excluded from exports). Run with:
##   godot --path . res://tests/SmokeTest.tscn -- --shots=/some/dir
## Visits every screen, imports a photo, opens a chest, auto-plays the
## Arena (boss defeat, draft, knockout, instant rematch) and saves screenshots.

func _ready() -> void:
	var driver := Node.new()
	driver.set_script(load("res://tests/SmokeDriver.gd"))
	get_tree().root.add_child.call_deferred(driver)
