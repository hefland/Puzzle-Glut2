extends Node2D
## Twinkling 4-point sparkles that orbit high-level / legendary gear.

var radius := 56.0
var center := Vector2.ZERO
var tint := Color(1, 1, 0.8)
var count := 6

var _sparks: Array = []


func _ready() -> void:
	for i in count:
		_sparks.append({"pos": _rand_pos(), "phase": randf() * TAU, "speed": randf_range(2.5, 5.0), "size": randf_range(4.0, 8.0)})


func _rand_pos() -> Vector2:
	var a := randf() * TAU
	return center + Vector2(cos(a), sin(a)) * radius * sqrt(randf())


func _process(delta: float) -> void:
	for s in _sparks:
		s["phase"] += delta * s["speed"]
		if s["phase"] > TAU:
			s["phase"] -= TAU
			s["pos"] = _rand_pos()
	queue_redraw()


func _draw() -> void:
	for s in _sparks:
		var k := maxf(0.0, sin(s["phase"]))
		if k <= 0.01:
			continue
		var sz: float = s["size"] * k
		var p: Vector2 = s["pos"]
		var c := Color(tint.r, tint.g, tint.b, k)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -sz * 1.6), p + Vector2(sz * 0.35, 0), p + Vector2(0, sz * 1.6), p + Vector2(-sz * 0.35, 0)]), c)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-sz * 1.6, 0), p + Vector2(0, sz * 0.35), p + Vector2(sz * 1.6, 0), p + Vector2(0, -sz * 0.35)]), c)
