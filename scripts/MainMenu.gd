extends Control
## MainMenu — animated title (taken from the game's file name via AppInfo),
## live hero preview wearing the equipped gear, and the main navigation.

const FighterScene := preload("res://scenes/CartoonFighter.tscn")

const LETTER_COLORS := [Color("ff4d6d"), Color("ffd23f"), Color("4cd964"), Color("3fa9ff"), Color("b76cff"), Color("ff9f1c")]

var stage: Control
var hero: Node2D
var buttons: Array = []
var letters: Array = []
var _t := 0.0


func _ready() -> void:
	add_child(UIKit.make_background(Color("4b1fa0"), Color("ff6fb5"), Color("7af0ff")))
	stage = Control.new()
	stage.set_anchors_preset(Control.PRESET_CENTER)
	stage.size = Vector2(1280, 720)
	stage.position = -stage.size * 0.5
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	_build_title()
	_build_hero()
	_build_buttons()
	_build_footer()
	AudioSynth.play_music("menu")
	await get_tree().process_frame
	if buttons.size() > 0:
		buttons[0].grab_focus()


func _build_title() -> void:
	var full := AppInfo.title
	var main := full
	var sub := "PUZZLE FACE-OFF"
	if full.contains(":"):
		main = full.get_slice(":", 0).strip_edges()
		sub = full.get_slice(":", 1).strip_edges()
	main = main.to_upper()
	var size := int(clampf(1000.0 / maxf(main.length(), 1) / 0.68, 44.0, 118.0))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(size * 0.02))
	row.position = Vector2(0, 26)
	row.size = Vector2(1280, size + 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(row)
	for i in main.length():
		var ch := main.substr(i, 1)
		var l := UIKit.make_label(ch, size, LETTER_COLORS[i % LETTER_COLORS.size()], int(size * 0.16))
		l.add_theme_font_override("font", UIKit.font_bold)
		l.add_theme_constant_override("shadow_offset_y", 8)
		l.add_theme_color_override("font_shadow_color", Color(0.1, 0.03, 0.2, 0.6))
		if ch == " ":
			l.custom_minimum_size.x = size * 0.35
		row.add_child(l)
		letters.append(l)
		# Drop-in entrance.
		l.modulate.a = 0.0
		var tw := l.create_tween()
		tw.tween_interval(0.04 * i)
		tw.tween_property(l, "modulate:a", 1.0, 0.15)
	var subl := UIKit.make_label("★ " + sub.to_upper() + " ★", 30, Color.WHITE, 9)
	subl.add_theme_font_override("font", UIKit.font_bold)
	subl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subl.position = Vector2(0, 40 + size)
	subl.size = Vector2(1280, 40)
	stage.add_child(subl)
	var tw2 := subl.create_tween().set_loops()
	tw2.tween_property(subl, "modulate", Color(1, 0.9, 0.5), 0.8).set_trans(Tween.TRANS_SINE)
	tw2.tween_property(subl, "modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_SINE)


func _build_hero() -> void:
	var glow := UIKit.make_glow(Color(1.0, 0.9, 0.5, 0.65), 520, 12)
	glow.position = Vector2(340 - 260, 470 - 260)
	stage.add_child(glow)
	var pedestal := Panel.new()
	var ps := UIKit.panel_style(Color("2a1747"), 60, 6)
	pedestal.add_theme_stylebox_override("panel", ps)
	pedestal.position = Vector2(200, 600)
	pedestal.size = Vector2(280, 56)
	pedestal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(pedestal)
	var holder := Node2D.new()
	holder.position = Vector2(340, 616)
	holder.scale = Vector2(1.25, 1.25)
	stage.add_child(holder)
	hero = FighterScene.instantiate()
	holder.add_child(hero)
	hero.set_face(FaceManager.hero_face_id())
	hero.equip_loadout_from_save()
	# Click / tap the hero for a cheer.
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.position = Vector2(230, 260)
	hit.size = Vector2(220, 360)
	hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	hit.pressed.connect(func():
		hero.cheer(true)
		AudioSynth.play("boing", randf_range(0.9, 1.3)))
	stage.add_child(hit)


func _build_buttons() -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(740, 250)
	v.size = Vector2(420, 360)
	v.add_theme_constant_override("separation", 18)
	stage.add_child(v)
	var play := UIKit.make_button("▶  PLAY", UIKit.LIME.darkened(0.12), Vector2(420, 84), 38)
	var studio := UIKit.make_button("☺  FACE STUDIO", UIKit.BLUE, Vector2(420, 70), 28)
	var locker := UIKit.make_button("⚙  GEAR & LOOT", UIKit.PURPLE, Vector2(420, 70), 28)
	buttons = [play, studio, locker]
	play.pressed.connect(func(): UIKit.change_scene("res://scenes/Arena.tscn"))
	studio.pressed.connect(func(): UIKit.change_scene("res://scenes/FaceStudio.tscn"))
	locker.pressed.connect(func(): UIKit.change_scene("res://scenes/GearLocker.tscn"))
	for b in buttons:
		v.add_child(b)
	if SaveManager.daily_available():
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.RED, 14, 4))
		badge.position = Vector2(330, -12)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bl := UIKit.make_label("FREE CHEST!", 15, Color.WHITE, 5)
		badge.add_child(bl)
		locker.add_child(badge)
		var tw := badge.create_tween().set_loops()
		tw.tween_property(badge, "rotation", 0.1, 0.25)
		tw.tween_property(badge, "rotation", -0.1, 0.25)
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		var quit := UIKit.make_button("QUIT", UIKit.ORANGE.darkened(0.2), Vector2(420, 54), 22)
		quit.pressed.connect(func(): get_tree().quit())
		v.add_child(quit)
		buttons.append(quit)
	for i in buttons.size():
		var b: Button = buttons[i]
		b.focus_neighbor_top = buttons[(i - 1 + buttons.size()) % buttons.size()].get_path()
		b.focus_neighbor_bottom = buttons[(i + 1) % buttons.size()].get_path()
		b.focus_neighbor_left = b.get_path()
		b.focus_neighbor_right = b.get_path()
		# Slide in from the right.
		b.modulate.a = 0.0
		var tw2 := b.create_tween()
		tw2.tween_interval(0.25 + i * 0.08)
		tw2.tween_property(b, "modulate:a", 1.0, 0.2)


func _build_footer() -> void:
	var d := SaveManager.data
	var stats := UIKit.make_label("BEST %d   ·   FLOOR %d   ·   BOSSES BEATEN %d   ·   ● %d   ◆ %d" % [
		int(d["high_score"]), int(d["best_floor"]), int(d["boss_wins"]), SaveManager.coins(), SaveManager.gems()], 20, Color.WHITE, 6)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.position = Vector2(560, 668)
	stats.size = Vector2(720, 30)
	stage.add_child(stats)
	var mute := UIKit.make_button("✕" if AudioSynth.is_muted() else "♪", UIKit.CYAN, Vector2(60, 52), 24)
	mute.focus_mode = Control.FOCUS_NONE
	mute.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mute.position = Vector2(-80, 16)
	add_child(mute)
	mute.pressed.connect(func(): mute.text = "✕" if AudioSynth.toggle_mute() else "♪")


func _process(delta: float) -> void:
	_t += delta
	for i in letters.size():
		var l: Label = letters[i]
		var k := sin(_t * 3.2 - i * 0.45)
		l.position.y = k * 9.0
		l.rotation = sin(_t * 2.0 - i * 0.6) * 0.06
		l.pivot_offset = l.size * 0.5
		l.scale = Vector2(1.0 + 0.04 * k, 1.0 - 0.04 * k)

