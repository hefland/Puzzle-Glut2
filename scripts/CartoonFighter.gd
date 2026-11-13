extends Node2D
## CartoonFighter — reusable procedural 2.5D character rig.
##
## An oversized spring-mounted head shows any face from the FaceManager
## (through face_avatar.gdshader), with cartoon brows, sweat drops, dizzy
## stars and cross-eyed spirals drawn on top. Gear renders on three anchors:
## HeadAnchor, FaceAnchor (right over the selfie) and HandAnchor.

const GearArt := preload("res://scripts/ProceduralGearArt.gd")
const INK := Color("1b0f2e")

@export var body_color: Color = Color("3fa9ff")
@export var facing: int = 1   # 1 = faces right, -1 = faces left

@onready var shadow: Polygon2D = $Shadow
@onready var body: Node2D = $Body
@onready var torso: Polygon2D = $Body/Torso
@onready var torso_outline: Line2D = $Body/TorsoOutline
@onready var belly: Polygon2D = $Body/Belly
@onready var belt: Polygon2D = $Body/Belt
@onready var left_arm: Line2D = $Body/LeftArm
@onready var right_arm: Line2D = $Body/RightArm
@onready var left_hand: Node2D = $Body/LeftHand
@onready var right_hand: Node2D = $Body/RightHand
@onready var left_foot: Polygon2D = $Body/LeftFoot
@onready var right_foot: Polygon2D = $Body/RightFoot
@onready var head_pivot: Node2D = $Body/HeadPivot
@onready var neck: Polygon2D = $Body/HeadPivot/Neck
@onready var head: Sprite2D = $Body/HeadPivot/Head
@onready var brows: Node2D = $Body/HeadPivot/Brows
@onready var brow_l: Line2D = $Body/HeadPivot/Brows/BrowL
@onready var brow_r: Line2D = $Body/HeadPivot/Brows/BrowR
@onready var overlay: Node2D = $Body/HeadPivot/Overlay
@onready var head_anchor: Marker2D = $Body/HeadPivot/HeadAnchor
@onready var face_anchor: Marker2D = $Body/HeadPivot/FaceAnchor
@onready var hand_anchor: Marker2D = $Body/RightHand/HandAnchor

var mood := "idle"          # idle, cheer, angry, hit, defeat, victory
var danger := false
var dizzy_time := 0.0
var brow_style := "neutral" # neutral, angry, worried, happy
var face_material: ShaderMaterial

var _t := 0.0
var _neck_rest := Vector2(0, -128)
var _head_off := Vector2.ZERO      # spring offset from rest
var _head_vel := Vector2.ZERO
var _head_rot := 0.0
var _head_rot_vel := 0.0
var _head_scale := Vector2.ONE
var _head_scale_vel := Vector2.ZERO
var _spin := 0.0
var _hand_l_target := Vector2(-58, -78)
var _hand_r_target := Vector2(58, -78)
var _sweat: Array = []
var _flash := 0.0
var _hop := 0.0
var _hop_vel := 0.0
var _lunge := 0.0
var _defeated := false


func _ready() -> void:
	face_material = FaceManager.make_face_material()
	head.material = face_material
	_build_body()
	body.scale.x = facing
	overlay.draw.connect(_draw_overlay)
	set_brows("neutral")


func _build_body() -> void:
	shadow.polygon = GearArt.ellipse(Vector2.ZERO, Vector2(62, 14), 24)
	var torso_pts := GearArt.rrect(-38, -132, 76, 112, 34)
	torso.polygon = torso_pts
	torso.color = body_color
	torso_outline.points = torso_pts
	belly.polygon = GearArt.ellipse(Vector2(-10, -104), Vector2(16, 22), 16)
	belt.polygon = GearArt.rrect(-38, -50, 76, 12, 4)
	belt.color = body_color.darkened(0.45)
	for f in [left_foot, right_foot]:
		f.polygon = GearArt.ellipse(Vector2.ZERO, Vector2(20, 11), 16)
		f.color = INK
	neck.polygon = GearArt.rrect(-14, -10, 28, 18, 6)
	neck.color = Color("ffcfa8").darkened(0.15)
	for h in [left_hand, right_hand]:
		var outline := Polygon2D.new()
		outline.polygon = GearArt.ellipse(Vector2.ZERO, Vector2(17, 17), 18)
		outline.color = INK
		h.add_child(outline)
		var fill := Polygon2D.new()
		fill.polygon = GearArt.ellipse(Vector2.ZERO, Vector2(13, 13), 18)
		fill.color = Color.WHITE
		h.add_child(fill)
		var g := Polygon2D.new()
		g.polygon = GearArt.ellipse(Vector2(-4, -5), Vector2(5, 3), 10)
		g.color = Color(1, 1, 1, 0.9)
		h.add_child(g)


func set_body_color(c: Color) -> void:
	body_color = c
	if is_inside_tree():
		torso.color = c
		belt.color = c.darkened(0.45)


func set_face(face_id: String) -> void:
	var tex := FaceManager.get_texture(face_id)
	head.texture = tex
	if tex:
		head.scale = Vector2.ONE * (128.0 / maxf(tex.get_width(), 1.0))


func set_facing(dir: int) -> void:
	facing = dir
	if is_inside_tree():
		body.scale.x = dir


# --- Gear -----------------------------------------------------------------

func clear_gear() -> void:
	for a in [head_anchor, face_anchor, hand_anchor]:
		for c in a.get_children():
			c.queue_free()


## Equips an item (by id) at its slot anchor.
func set_gear(item_id: int, level: int = 1) -> void:
	var item := GearDatabase.get_item(item_id)
	if item.is_empty():
		return
	var anchor: Marker2D = [head_anchor, face_anchor, hand_anchor][int(item["slot"])]
	for c in anchor.get_children():
		c.queue_free()
	var art := GearArt.build(item, level)
	if int(item["slot"]) == 2:
		art.scale = Vector2(0.85, 0.85)
	anchor.add_child(art)
	art.scale *= 0.2
	var tw := art.create_tween()
	tw.tween_property(art, "scale", art.scale * 5.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Equips the player's saved 3-slot loadout.
func equip_loadout_from_save() -> void:
	clear_gear()
	for slot in ["head", "face", "hand"]:
		var id := SaveManager.equipped(slot)
		if id >= 0 and SaveManager.owns(id):
			set_gear(id, SaveManager.item_level(id))


# --- Expressions ----------------------------------------------------------

func set_brows(style: String) -> void:
	brow_style = style
	var l := PackedVector2Array()
	var r := PackedVector2Array()
	match style:
		"angry":
			l = PackedVector2Array([Vector2(-34, -24), Vector2(-10, -14)])
			r = PackedVector2Array([Vector2(10, -14), Vector2(34, -24)])
		"worried":
			l = PackedVector2Array([Vector2(-34, -16), Vector2(-10, -26)])
			r = PackedVector2Array([Vector2(10, -26), Vector2(34, -16)])
		"happy":
			l = PackedVector2Array([Vector2(-34, -24), Vector2(-22, -32), Vector2(-10, -26)])
			r = PackedVector2Array([Vector2(10, -26), Vector2(22, -32), Vector2(34, -24)])
		_:
			l = PackedVector2Array([Vector2(-34, -22), Vector2(-10, -24)])
			r = PackedVector2Array([Vector2(10, -24), Vector2(34, -22)])
	brow_l.points = l
	brow_r.points = r


func set_danger(on: bool) -> void:
	if on == danger:
		return
	danger = on
	if not _defeated and mood != "cheer":
		set_brows("worried" if on else ("angry" if facing < 0 else "neutral"))


## Small head boing (used on every piece landing, etc).
func nudge(strength: float = 1.0) -> void:
	_head_vel += Vector2(0, 160 * strength)
	_head_scale_vel += Vector2(1.6, -1.6) * strength


func cheer(big: bool = false) -> void:
	if _defeated:
		return
	mood = "cheer"
	set_brows("happy")
	_hop_vel = -520.0 if big else -380.0
	_head_scale_vel += Vector2(-2.5, 3.0)
	_hand_l_target = Vector2(-62, -178)
	_hand_r_target = Vector2(62, -178)
	_reset_mood_later(0.9)


func attack_lunge() -> void:
	if _defeated:
		return
	_lunge = 1.0
	_hand_r_target = Vector2(110, -110)
	set_brows("angry")
	_head_rot_vel += 6.0
	_reset_mood_later(0.6)


## Boss wind-up telegraph: trembling + red flash.
func wind_up() -> void:
	set_brows("angry")
	_hand_r_target = Vector2(30, -170)
	var tw := create_tween()
	for i in 6:
		tw.tween_property(body, "position:x", 6.0 * (1 if i % 2 == 0 else -1), 0.05)
	tw.tween_property(body, "position:x", 0.0, 0.05)
	face_material.set_shader_parameter("flash_color", Color(1, 0.2, 0.2))
	_flash = 0.6


## Getting smacked: comic pancake squash, spin and cross-eyed dizziness.
func hit(big: bool = false) -> void:
	_head_scale = Vector2(1.5, 0.45) if big else Vector2(1.2, 0.75)
	_head_scale_vel = Vector2.ZERO
	_head_vel += Vector2(-facing * 260, -120)
	_head_rot_vel += -facing * 14.0
	face_material.set_shader_parameter("flash_color", Color.WHITE)
	_flash = 1.0
	if big:
		_spin = TAU
		dizzy_time = maxf(dizzy_time, 1.4)
	set_brows("worried")
	_reset_mood_later(0.8)


func stun(duration: float = 2.0) -> void:
	dizzy_time = maxf(dizzy_time, duration)
	_spin = TAU * 0.5
	set_brows("worried")


func defeat() -> void:
	_defeated = true
	mood = "defeat"
	dizzy_time = 999.0
	set_brows("worried")
	_head_scale = Vector2(1.7, 0.35)
	_spin = TAU * 2.0
	_hand_l_target = Vector2(-70, -40)
	_hand_r_target = Vector2(70, -40)
	var tw := create_tween()
	tw.tween_property(body, "rotation", -facing * 0.35, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(body, "position:y", 18.0, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func victory() -> void:
	_defeated = false
	mood = "victory"
	dizzy_time = 0.0
	set_brows("happy")
	_hand_l_target = Vector2(-62, -178)
	_hand_r_target = Vector2(62, -178)


func reset_pose() -> void:
	_defeated = false
	mood = "idle"
	dizzy_time = 0.0
	danger = false
	_spin = 0.0
	_head_off = Vector2.ZERO
	_head_vel = Vector2.ZERO
	_head_rot = 0.0
	_head_rot_vel = 0.0
	_head_scale = Vector2.ONE
	_head_scale_vel = Vector2.ZERO
	_hop = 0.0
	_hop_vel = 0.0
	body.rotation = 0.0
	body.position = Vector2.ZERO
	_hand_l_target = Vector2(-58, -78)
	_hand_r_target = Vector2(58, -78)
	set_brows("angry" if facing < 0 else "neutral")
	modulate = Color.WHITE


func _reset_mood_later(sec: float) -> void:
	get_tree().create_timer(sec, false).timeout.connect(_restore_mood.bind(mood))


func _restore_mood(my_mood: String) -> void:
	if _defeated or mood == "victory":
		return
	if mood == my_mood or mood == "cheer" or mood == "hit":
		mood = "idle"
	_hand_l_target = Vector2(-58, -78)
	_hand_r_target = Vector2(58, -78)
	set_brows("worried" if danger else ("angry" if facing < 0 else "neutral"))


# --- Simulation -----------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_t += delta
	# Idle breathing: faster and shakier when in danger.
	var breath_speed := 6.0 if danger else 2.6
	var breath := sin(_t * breath_speed)
	var squash := 0.03 * breath
	if mood == "victory":
		_hop_vel = -330.0 if _hop >= 0.0 and _hop_vel >= 0.0 else _hop_vel
	# Hop physics.
	_hop_vel += 1700.0 * delta
	_hop += _hop_vel * delta
	if _hop > 0.0:
		if _hop_vel > 300.0:
			_head_scale_vel += Vector2(2.2, -2.2)
		_hop = 0.0
		_hop_vel = 0.0
	_lunge = maxf(0.0, _lunge - delta * 2.5)
	var lunge_x := sin(_lunge * PI) * 50.0
	if not _defeated:
		body.position = Vector2(lunge_x, _hop)
		body.scale = Vector2(facing * (1.0 + squash), 1.0 - squash)
	# Spring head: offset, rotation and squash all spring back to rest.
	var target_off := Vector2(sin(_t * 1.3) * 3.0, breath * 2.0)
	var acc := (target_off - _head_off) * 170.0 - _head_vel * 11.0
	_head_vel += acc * delta
	_head_off += _head_vel * delta
	var rot_target := sin(_t * 1.7) * 0.05
	if dizzy_time > 0.0:
		rot_target = sin(_t * 9.0) * 0.18
	if danger:
		rot_target += sin(_t * 31.0) * 0.02
	_head_rot_vel += ((rot_target - _head_rot) * 140.0 - _head_rot_vel * 9.0) * delta
	_head_rot += _head_rot_vel * delta
	if _spin > 0.0:
		var step := minf(_spin, delta * 14.0)
		_spin -= step
		_head_rot += step
		if _spin <= 0.0:
			_head_rot = fmod(_head_rot, TAU)
			if _head_rot > PI:
				_head_rot -= TAU
	var stiff := 90.0 if _defeated else 220.0
	_head_scale_vel += ((Vector2.ONE - _head_scale) * stiff - _head_scale_vel * 10.0) * delta
	_head_scale += _head_scale_vel * delta
	if _defeated:
		_head_scale = _head_scale.lerp(Vector2(1.35, 0.6), delta * 2.0)
	head_pivot.position = _neck_rest + _head_off
	head_pivot.rotation = _head_rot
	head_pivot.scale = _head_scale
	# Arms & hands.
	var bob := Vector2(0, sin(_t * 2.6 + 1.0) * 4.0)
	left_hand.position = left_hand.position.lerp(_hand_l_target + bob, clampf(delta * 12.0, 0.0, 1.0))
	right_hand.position = right_hand.position.lerp(_hand_r_target - bob, clampf(delta * 12.0, 0.0, 1.0))
	left_arm.points = PackedVector2Array([Vector2(-30, -112), (Vector2(-30, -112) + left_hand.position) * 0.5 + Vector2(-8, 6), left_hand.position])
	right_arm.points = PackedVector2Array([Vector2(30, -112), (Vector2(30, -112) + right_hand.position) * 0.5 + Vector2(8, 6), right_hand.position])
	# Feet tap.
	left_foot.position.y = -10 + minf(0.0, sin(_t * 5.0)) * (2.0 if danger else 0.0)
	right_foot.position.y = -10 + minf(0.0, -sin(_t * 5.0)) * (2.0 if danger else 0.0)
	shadow.scale = Vector2.ONE * clampf(1.0 + _hop / 300.0, 0.5, 1.0)
	# Brows bounce with the head.
	brows.position.y = -66 + (-6.0 if brow_style == "happy" else 0.0) + sin(_t * 3.0) * 1.5
	# Shader feedback.
	_flash = maxf(0.0, _flash - delta * 3.0)
	face_material.set_shader_parameter("flash", _flash)
	face_material.set_shader_parameter("sick", 0.35 if danger else 0.0)
	dizzy_time = maxf(0.0, dizzy_time - delta)
	# Sweat drops.
	if danger and randf() < delta * 3.0:
		_sweat.append({"pos": Vector2(randf_range(36, 52) * (1 if randf() < 0.5 else -1), randf_range(-100, -70)), "life": 1.0})
	for s in _sweat:
		s["life"] -= delta * 1.4
		s["pos"].y += delta * 60.0
	_sweat = _sweat.filter(func(s): return s["life"] > 0.0)
	overlay.queue_redraw()


func _draw_overlay() -> void:
	# Sweat drops.
	for s in _sweat:
		var p: Vector2 = s["pos"]
		var a: float = clampf(s["life"], 0.0, 1.0)
		overlay.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -12), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0)]), Color(0.55, 0.85, 1.0, a))
		overlay.draw_circle(p + Vector2(0, 1), 5.5, Color(0.55, 0.85, 1.0, a))
		overlay.draw_circle(p + Vector2(-2, -1), 1.8, Color(1, 1, 1, a))
	# Dizzy: cross-eyed spirals over the eyes and orbiting stars.
	if dizzy_time > 0.0:
		for ex in [-20.0, 20.0]:
			var c := Vector2(ex, -66)
			overlay.draw_circle(c, 14, Color(1, 1, 1, 0.92))
			var pts := PackedVector2Array()
			for i in 26:
				var ang := i * 0.55 + _t * 10.0 * (1.0 if ex < 0 else -1.0)
				pts.append(c + Vector2(cos(ang), sin(ang)) * (i * 0.5))
			overlay.draw_polyline(pts, INK, 3.0, true)
		for i in 3:
			var ang := _t * 4.0 + i * TAU / 3.0
			var sp := Vector2(cos(ang) * 64, -130 + sin(ang) * 14)
			_draw_star(sp, 11.0, Color("ffd23f"))
	# Blush when cheering.
	if mood == "cheer" or mood == "victory":
		overlay.draw_circle(Vector2(-36, -44), 9, Color(1, 0.35, 0.5, 0.45))
		overlay.draw_circle(Vector2(36, -44), 9, Color(1, 0.35, 0.5, 0.45))


func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + PI * i / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	var outline := pts.duplicate()
	outline.append(pts[0])
	overlay.draw_colored_polygon(pts, col)
	overlay.draw_polyline(outline, INK, 2.5, true)
