extends Node2D
## Arena — the battle screen.
##
## Wires together the GridBoard, TurnManager, the hero and the rival boss
## (both CartoonFighter rigs), the gear Trigger -> Effect engine, boss
## attacks with telegraphs, the endless boss ladder, Tactical Draft cards,
## the Gear Burst ability, juice (hit-stop, shake, slow-mo, popups) and the
## pause / knockout / instant-rematch overlays.

signal _draft_done

const FighterScene := preload("res://scenes/CartoonFighter.tscn")
const BoardScript := preload("res://scripts/GridBoard.gd")
const TurnScript := preload("res://scripts/TurnManager.gd")
const GearArt := preload("res://scripts/ProceduralGearArt.gd")
const T := BoardScript.T

const BOARD_POS := Vector2(465, 92)
const HERO_POS := Vector2(215, 440)
const BOSS_POS := Vector2(1080, 440)

const CARDS := [
	{"id": "pyro", "name": "Pyromaniac", "desc": "Red matches deal +50% boss damage.", "icon": "🔥", "color": Color("ff4d6d")},
	{"id": "ice", "name": "Cold Snap", "desc": "Blue matches deal +50% boss damage.", "icon": "❄", "color": Color("3fa9ff")},
	{"id": "verdant", "name": "Garden Party", "desc": "Green & Yellow matches deal +35% damage.", "icon": "✿", "color": Color("4cd964")},
	{"id": "miner", "name": "Greedy Miner", "desc": "+2 Gems for every 2x+ cascade.", "icon": "◆", "color": Color("2ee6d6")},
	{"id": "purge", "name": "Emergency Purge", "desc": "Clear the bottom 2 rows right now.", "icon": "✖", "color": Color("ff9f1c")},
	{"id": "feather", "name": "Featherweight", "desc": "Pieces fall 20% slower for the whole run.", "icon": "☁", "color": Color("bfe9ff")},
	{"id": "thick", "name": "Thick Skin", "desc": "Boss garbage -1 per attack. Gain 2 Shields now.", "icon": "⛨", "color": Color("8a8fff")},
	{"id": "lightning", "name": "Chain Lightning", "desc": "Each cascade step adds +25% more damage.", "icon": "⚡", "color": Color("ffd23f")},
	{"id": "junkie", "name": "Gear Junkie", "desc": "All gear gets +15% trigger chance.", "icon": "⚙", "color": Color("c06bff")},
	{"id": "wildclub", "name": "Wild Card Club", "desc": "Every 8th piece carries a Rainbow Wildcard.", "icon": "✦", "color": Color("ff6fb5")},
	{"id": "demo", "name": "Demolition Expert", "desc": "Turn 2 random blocks into Bombs now.", "icon": "✹", "color": Color("ff7a3d")},
	{"id": "magnet", "name": "Coin Magnet", "desc": "+50% Coins from every pop.", "icon": "●", "color": Color("ffc93c")},
	{"id": "secondwind", "name": "Second Wind", "desc": "Once per run: survive a knockout and clear the top 5 rows.", "icon": "♥", "color": Color("ff5f8f")},
	{"id": "overcharge", "name": "Overcharge", "desc": "Gear Burst meter fills 50% faster.", "icon": "★", "color": Color("7cf06b")},
	{"id": "hunter", "name": "Big Game Hunter", "desc": "+25% damage to every boss.", "icon": "➶", "color": Color("ff4da6")},
	{"id": "tactical", "name": "Tactical Delay", "desc": "Boss attacks come 1 drop later.", "icon": "⏳", "color": Color("9be15d")},
]
const BOSS_NAMES := ["Baron Von Wobble", "Duke Sogbottom", "Lady Grumblesnout", "Sir Snorts-a-Lot", "Count Crankypants",
	"Professor Pickles", "Captain Noodlearm", "Madame Meltdown", "The Grand Gloop", "Lord Fumblethumbs", "Auntie Avalanche", "King Kerfuffle"]
const BOSS_COLORS := [Color("b44dff"), Color("ff4d6d"), Color("ff9f1c"), Color("2ec4b6"), Color("6a4dff"), Color("e84393")]
const POP_WORDS := ["SWEET!", "TASTY!", "NICE!", "YUM!", "JUICY!", "POP!"]

# --- Nodes ----------------------------------------------------------------
var world: Node2D
var camera: Camera2D
var board: Node2D
var turns: Node
var hero: Node2D
var boss: Node2D
var bg: ColorRect
var hud: CanvasLayer
var overlay_layer: CanvasLayer
var fx_layer: Node2D

var score_label: Label
var floor_label: Label
var coins_label: Label
var gems_label: Label
var turn_label: Label
var draft_label: Label
var pips: Array = []
var mute_btn: Button
var pause_btn: Button
var ability_btn: Button
var ability_fill: Panel
var ability_glow: ColorRect
var hint_label: Label
var hint_panel: PanelContainer
var touch_left: Control
var touch_right: Control
var slot_boxes: Array = []
var boss_name_label: Label
var boss_hp_fill: Panel
var boss_hp_label: Label
var quirk_label: Label
var quirk_panel: PanelContainer
var countdown_panel: PanelContainer
var countdown_label: Label

# --- Run state ------------------------------------------------------------
var mode := "playing"     # playing, transition, draft, over, paused
var floor_num := 1
var score := 0
var shown_score := 0.0
var run_coins := 0
var run_gems := 0
var bosses_beaten := 0
var cards: Dictionary = {}
var equipped: Array = []        # [{item, level, slot}]
var fired_this_drop: Dictionary = {}
var gem_turn: Dictionary = {}       # item id -> turn its gem effect last paid
var combo_boost := 0.0
var slow_timer := 0.0
var rush_drops := 0
var ability := 0.0
var second_wind_used := false
var revive_needed := false
var danger_trigger_used := false
var boss_data: Dictionary = {}
var boss_hp := 100.0
var boss_max := 100.0
var boss_stunned := false
var last_pop_color := 0
var max_chain_run := 0
var _shake := 0.0
var _hitstop_id := 0
var _overlay: Control
var _rng := RandomNumberGenerator.new()
var _miner_paid := false
var _run_id := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_build_world()
	_build_hud()
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 20
	add_child(overlay_layer)
	InputHub.device_changed.connect(func(_d): _refresh_device_ui())
	SaveManager.currency_changed.connect(_refresh_currency)
	AudioSynth.play_music("battle")
	start_run()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# =========================================================================
# Construction
# =========================================================================

func _build_world() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	bg = UIKit.make_background(Color("3a1c7a"), Color("ff6f91"), Color("6ff7ff"))
	bg_layer.add_child(bg)

	world = Node2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	camera = Camera2D.new()
	camera.position = Vector2(640, 360)
	world.add_child(camera)
	camera.make_current()

	# Floor stripe behind the fighters.
	for x in [HERO_POS.x, BOSS_POS.x]:
		var stage := Polygon2D.new()
		stage.polygon = GearArt.ellipse(Vector2(x, HERO_POS.y + 6), Vector2(150, 34), 32)
		stage.color = Color(0.1, 0.04, 0.2, 0.35)
		world.add_child(stage)

	hero = FighterScene.instantiate()
	hero.position = HERO_POS
	hero.facing = 1
	world.add_child(hero)
	boss = FighterScene.instantiate()
	boss.position = BOSS_POS
	boss.facing = -1
	boss.scale = Vector2(1.05, 1.05)
	world.add_child(boss)

	board = BoardScript.new()
	board.position = BOARD_POS
	world.add_child(board)
	board.piece_locked.connect(_on_piece_locked)
	board.blocks_popped.connect(_on_blocks_popped)
	board.chain_finished.connect(_on_chain_finished)
	board.piece_resolved.connect(_on_piece_resolved)
	board.danger_changed.connect(_on_danger_changed)
	board.topped_out.connect(_on_topped_out)

	turns = TurnScript.new()
	add_child(turns)
	turns.changed.connect(_refresh_turn_ui)

	fx_layer = Node2D.new()
	fx_layer.z_index = 30
	world.add_child(fx_layer)

	_build_hero_panel()
	_build_boss_panel()


func _build_hero_panel() -> void:
	# Three equipped gear slots under the hero.
	var names := ["HEAD", "FACE", "HAND"]
	for i in 3:
		var box := Panel.new()
		box.size = Vector2(62, 62)
		box.position = Vector2(HERO_POS.x - 103 + i * 72, HERO_POS.y + 12)
		box.pivot_offset = box.size * 0.5
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.PANEL_LIGHT, 14, 4, false))
		world.add_child(box)
		var tag := UIKit.make_label(names[i], 11, Color(1, 1, 1, 0.7), 4)
		tag.position = Vector2(4, 44)
		tag.size = Vector2(54, 16)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(tag)
		slot_boxes.append(box)
	# Gear Burst ability button with meter.
	ability_btn = UIKit.make_button("★ GEAR BURST", UIKit.PURPLE, Vector2(226, 58), 21)
	ability_btn.position = Vector2(HERO_POS.x - 113, HERO_POS.y + 84)
	ability_btn.size = Vector2(226, 58)
	ability_btn.focus_mode = Control.FOCUS_NONE
	ability_glow = UIKit.make_glow(Color(1.0, 0.85, 0.3, 0.9), 300, 10)
	ability_glow.position = Vector2(HERO_POS.x - 150, HERO_POS.y + 113 - 150)
	ability_glow.visible = false
	world.add_child(ability_glow)
	world.add_child(ability_btn)
	ability_fill = Panel.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(1.0, 0.85, 0.3, 0.45)
	fs.set_corner_radius_all(14)
	ability_fill.add_theme_stylebox_override("panel", fs)
	ability_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ability_fill.position = Vector2(6, 6)
	ability_fill.size = Vector2(0, 46)
	ability_btn.add_child(ability_fill)
	ability_btn.move_child(ability_fill, 0)
	ability_btn.pressed.connect(_use_ability)


func _build_boss_panel() -> void:
	var panel := UIKit.make_panel(Color(0.12, 0.06, 0.22, 0.88), 18)
	panel.position = Vector2(BOSS_POS.x - 150, BOSS_POS.y + 14)
	panel.custom_minimum_size = Vector2(300, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	boss_name_label = UIKit.make_label("Boss", 20, UIKit.GOLD, 6)
	boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(boss_name_label)
	var bar_bg := Panel.new()
	bar_bg.custom_minimum_size = Vector2(268, 24)
	bar_bg.add_theme_stylebox_override("panel", UIKit.panel_style(Color("1b0f2e"), 12, 3, false))
	v.add_child(bar_bg)
	boss_hp_fill = Panel.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color("ff4d6d")
	hs.set_corner_radius_all(9)
	boss_hp_fill.add_theme_stylebox_override("panel", hs)
	boss_hp_fill.position = Vector2(3, 3)
	boss_hp_fill.size = Vector2(262, 18)
	bar_bg.add_child(boss_hp_fill)
	boss_hp_label = UIKit.make_label("100 / 100", 14, Color.WHITE, 5)
	boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_hp_label.size = Vector2(268, 24)
	bar_bg.add_child(boss_hp_label)
	quirk_panel = UIKit.make_panel(Color("ff9f1c"), 12)
	quirk_panel.add_theme_stylebox_override("panel", _chip_style(Color("ff9f1c")))
	v.add_child(quirk_panel)
	quirk_label = UIKit.make_label("Weak to ...", 14, Color.WHITE, 5)
	quirk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quirk_panel.add_child(quirk_label)
	# Attack countdown chip.
	countdown_panel = PanelContainer.new()
	countdown_panel.add_theme_stylebox_override("panel", _chip_style(Color("ff3355"), 22))
	countdown_panel.pivot_offset = Vector2(134, 16)
	v.add_child(countdown_panel)
	countdown_label = UIKit.make_label("⚔ 5", 20, Color.WHITE, 6)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_panel.add_child(countdown_label)


func _chip_style(c: Color, radius: int = 14) -> StyleBoxFlat:
	var sb := UIKit.panel_style(c, radius, 4, true)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _chip(parent: Control, text: String, color: Color, size: int = 22) -> Label:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _chip_style(color))
	parent.add_child(p)
	var l := UIKit.make_label(text, size, Color.WHITE, 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return l


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 5
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	# Top-left: floor + score.
	var tl := HBoxContainer.new()
	tl.position = Vector2(14, 10)
	tl.add_theme_constant_override("separation", 8)
	root.add_child(tl)
	floor_label = _chip(tl, "FLOOR 1", Color("8a4dff"))
	score_label = _chip(tl, "0", Color("ff6fb5"))
	score_label.custom_minimum_size = Vector2(120, 0)
	# Top-centre: turn pips.
	var tc := PanelContainer.new()
	tc.add_theme_stylebox_override("panel", _chip_style(Color(0.12, 0.06, 0.22, 0.9), 18))
	tc.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tc.position = Vector2(-150, 8)
	tc.custom_minimum_size = Vector2(300, 0)
	root.add_child(tc)
	var th := HBoxContainer.new()
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	th.add_theme_constant_override("separation", 8)
	tc.add_child(th)
	turn_label = UIKit.make_label("TURN 1", 18, UIKit.GOLD, 6)
	th.add_child(turn_label)
	for i in TurnScript.DROPS_PER_TURN:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(20, 20)
		pip.pivot_offset = Vector2(10, 10)
		th.add_child(pip)
		pips.append(pip)
	draft_label = UIKit.make_label("DRAFT 3", 14, UIKit.CYAN, 5)
	th.add_child(draft_label)
	# Top-right: currencies + mute + pause.
	var tr := HBoxContainer.new()
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.position = Vector2(-14, 10)
	tr.alignment = BoxContainer.ALIGNMENT_END
	tr.add_theme_constant_override("separation", 8)
	root.add_child(tr)
	coins_label = _chip(tr, "● 0", Color("e0a400"))
	gems_label = _chip(tr, "◆ 0", Color("17b8c9"))
	mute_btn = UIKit.make_button("♪", UIKit.CYAN, Vector2(52, 46), 22)
	mute_btn.focus_mode = Control.FOCUS_NONE
	mute_btn.pressed.connect(func():
		AudioSynth.toggle_mute()
		_refresh_mute())
	tr.add_child(mute_btn)
	pause_btn = UIKit.make_button("Ⅱ", UIKit.ORANGE, Vector2(52, 46), 22)
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.pressed.connect(_toggle_pause)
	tr.add_child(pause_btn)
	tr.position.x = -14 - 400
	tr.size.x = 400
	# Bottom-left control hints.
	hint_panel = PanelContainer.new()
	hint_panel.add_theme_stylebox_override("panel", _chip_style(Color(0.1, 0.05, 0.2, 0.8), 14))
	hint_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint_panel.position = Vector2(14, -78)
	root.add_child(hint_panel)
	hint_label = UIKit.make_label("", 14, Color.WHITE, 4)
	hint_panel.add_child(hint_label)
	# Touch controls (TouchScreenButtons drive the same input actions).
	touch_left = Control.new()
	touch_left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	touch_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(touch_left)
	_touch_button(touch_left, Vector2(66, -66), "◀", "move_left", UIKit.BLUE)
	_touch_button(touch_left, Vector2(172, -66), "▶", "move_right", UIKit.BLUE)
	touch_right = Control.new()
	touch_right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	touch_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(touch_right)
	_touch_button(touch_right, Vector2(-282, -66), "▼", "soft_drop", UIKit.CYAN)
	_touch_button(touch_right, Vector2(-174, -66), "⟳", "rotate_cw", UIKit.PINK)
	_touch_button(touch_right, Vector2(-66, -66), "⤓", "hard_drop", UIKit.ORANGE)
	_refresh_device_ui()
	_refresh_mute()


func _touch_button(parent: Control, pos: Vector2, glyph: String, action: String, color: Color) -> void:
	var b := TouchScreenButton.new()
	var tex := UIKit.circle_texture(92, color, 5.0)
	b.texture_normal = tex
	b.texture_pressed = UIKit.circle_texture(92, color.lightened(0.25), 5.0)
	b.action = action
	var shape := CircleShape2D.new()
	shape.radius = 50
	b.shape = shape
	b.shape_centered = true
	b.position = pos - Vector2(46, 46)
	b.passby_press = true
	parent.add_child(b)
	var l := UIKit.make_label(glyph, 38, Color.WHITE, 8)
	l.size = Vector2(92, 92)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)


# =========================================================================
# Run lifecycle
# =========================================================================

func start_run() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	get_tree().paused = false
	Engine.time_scale = 1.0
	_run_id += 1
	mode = "playing"
	floor_num = 1
	score = 0
	shown_score = 0.0
	run_coins = 0
	run_gems = 0
	bosses_beaten = 0
	cards.clear()
	combo_boost = 0.0
	slow_timer = 0.0
	rush_drops = 0
	ability = 0.0
	second_wind_used = false
	revive_needed = false
	danger_trigger_used = false
	max_chain_run = 0
	fired_this_drop.clear()
	gem_turn.clear()
	board.reset()
	board.input_enabled = true
	hero.reset_pose()
	hero.set_face(FaceManager.hero_face_id())
	hero.equip_loadout_from_save()
	_load_loadout()
	_spawn_boss(false)
	turns.reset(int(boss_data["interval"]))
	_on_danger_changed(false)
	AudioSynth.set_music_speed(1.0)
	AudioSynth.play_music("battle")
	_refresh_hud()
	_spawn_piece()
	if SaveManager.data.get("runs", 0) == 0:
		_banner("FACE-OFF!", "Match 3+ colors to blast %s" % boss_data["name"], UIKit.PINK, 1.6)
	else:
		_banner("FLOOR 1", "%s  —  %s" % [boss_data["name"], _quirk_text()], UIKit.PURPLE, 1.4)


func _load_loadout() -> void:
	equipped.clear()
	var keys := ["head", "face", "hand"]
	for i in 3:
		for c in slot_boxes[i].get_children():
			if c is Control and not (c is Label):
				c.queue_free()
		var id := SaveManager.equipped(keys[i])
		if id < 0 or not SaveManager.owns(id):
			continue
		var item := GearDatabase.get_item(id)
		var lv := SaveManager.item_level(id)
		equipped.append({"item": item, "level": lv, "slot": i})
		var icon := GearArt.build_icon(id, lv, 56)
		icon.position = Vector2(3, 0)
		slot_boxes[i].add_child(icon)
		slot_boxes[i].add_theme_stylebox_override("panel", _slot_style(int(item["rarity"])))


func _slot_style(rarity: int) -> StyleBoxFlat:
	var sb := UIKit.panel_style(UIKit.PANEL_LIGHT, 14, 4, false)
	sb.border_color = UIKit.RARITY_COLORS[rarity]
	return sb


func _spawn_boss(animate: bool) -> void:
	var name_idx := _rng.randi_range(0, BOSS_NAMES.size() - 1)
	var title: String = BOSS_NAMES[name_idx]
	if floor_num >= 6:
		title += " " + ["II", "III", "IV", "the Mighty", "the Unbeatable", "Supreme"][mini((floor_num - 6) / 2, 5)]
	var attacks := ["garbage"]
	if floor_num >= 2:
		attacks.append("freeze")
	if floor_num >= 3:
		attacks.append("junk")
	if floor_num >= 4:
		attacks.append("rush")
	if floor_num >= 5:
		attacks.append("scramble")
	var weak: String = GearDatabase.TRIGGERS[_rng.randi_range(0, GearDatabase.TRIGGERS.size() - 1)]
	# Prefer a weakness the player can actually exploit some of the time.
	if _rng.randf() < 0.6 and not equipped.is_empty():
		weak = equipped[_rng.randi_range(0, equipped.size() - 1)]["item"]["trigger"]
	boss_data = {
		"name": title,
		"face": FaceManager.random_boss_face(_rng),
		"interval": maxi(3, 6 - (floor_num - 1) / 2),
		"attacks": attacks,
		"weak": weak,
		"color": BOSS_COLORS[(floor_num - 1) % BOSS_COLORS.size()],
	}
	boss_max = 150.0 + 70.0 * (floor_num - 1)
	boss_hp = boss_max
	boss_stunned = false
	board.num_colors = 4 if floor_num < 3 else 5
	boss.reset_pose()
	boss.set_face(boss_data["face"])
	boss.set_body_color(boss_data["color"])
	boss.clear_gear()
	var gear_level := clampi(1 + floor_num / 2, 1, 5)
	for slot in 3:
		var pool := GearDatabase.items_for_slot(slot)
		boss.set_gear(int(pool[_rng.randi_range(0, pool.size() - 1)]["id"]), gear_level)
	boss_name_label.text = title
	quirk_label.text = _quirk_text()
	quirk_panel.add_theme_stylebox_override("panel", _chip_style(GearDatabase.TRIGGER_COLOR[weak]))
	_refresh_boss_hp(true)
	if animate:
		boss.position = BOSS_POS + Vector2(420, 0)
		var tw := create_tween()
		tw.tween_property(boss, "position", BOSS_POS, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_update_speed()


func _quirk_text() -> String:
	var w: String = boss_data.get("weak", "ON_HARD_DROP")
	return "WEAK TO %s GEAR  ×2" % GearDatabase.TRIGGER_BADGE[w]


# =========================================================================
# Frame update
# =========================================================================

func _process(delta: float) -> void:
	if mode == "paused":
		return
	# Camera shake (trauma model).
	_shake = maxf(0.0, _shake - delta * 2.2)
	var s := _shake * _shake
	camera.offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 22.0 * s
	camera.rotation = _rng.randf_range(-1, 1) * 0.02 * s
	if slow_timer > 0.0:
		slow_timer = maxf(0.0, slow_timer - delta)
		if slow_timer == 0.0:
			_update_speed()
	# Score count-up.
	if shown_score < score:
		shown_score = minf(score, shown_score + maxf(40.0, (score - shown_score) * 8.0) * delta)
		score_label.text = str(int(shown_score))
	# Ability meter.
	ability_fill.size.x = lerpf(ability_fill.size.x, 214.0 * ability / 100.0, clampf(delta * 10.0, 0.0, 1.0))
	var ready := ability >= 100.0
	ability_glow.visible = ready
	if ready:
		ability_btn.scale = Vector2.ONE * (1.0 + 0.05 * sin(Time.get_ticks_msec() * 0.012))
	if mode == "playing" and Input.is_action_just_pressed("active_ability"):
		_use_ability()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if mode == "playing" or mode == "paused":
			_toggle_pause()
			get_viewport().set_input_as_handled()


func _update_speed() -> void:
	var base := maxf(0.16, 0.78 - 0.055 * (floor_num - 1))
	if slow_timer > 0.0:
		base *= 1.33
	if rush_drops > 0:
		base *= 0.5
	base *= pow(1.2, int(cards.get("feather", 0)))
	board.fall_interval = base
	AudioSynth.set_music_speed(1.0 + minf(0.02 * (floor_num - 1), 0.12) + (0.06 if rush_drops > 0 else 0.0))


# =========================================================================
# Board events
# =========================================================================

func _on_piece_locked(info: Dictionary) -> void:
	hero.nudge(1.5 if info["hard_drop"] else 0.7)
	if info["hard_drop"]:
		add_shake(0.38)
		score += 2
		_fire_trigger("ON_HARD_DROP")
	if int(info["rotations"]) >= 3:
		_fire_trigger("ON_MULTI_ROTATE")


func _on_blocks_popped(info: Dictionary) -> void:
	var chain: int = info["chain"]
	var count: int = info["count"]
	var colors: Array = info["colors"]
	var center: Vector2 = info["center"]
	max_chain_run = maxi(max_chain_run, chain)
	if info["color"] >= 0:
		last_pop_color = info["color"]
	# Damage.
	var dmg := float(count) * 3.0
	var chain_mult := 1.0 + (chain - 1) * (0.5 + 0.25 * int(cards.get("lightning", 0)))
	dmg *= chain_mult
	if info["bonus"]:
		dmg *= 1.5
	var color_bonus := 0.0
	if count > 0:
		color_bonus += 0.5 * int(cards.get("pyro", 0)) * float(colors[0]) / count
		color_bonus += 0.5 * int(cards.get("ice", 0)) * float(colors[1]) / count
		color_bonus += 0.35 * int(cards.get("verdant", 0)) * float(colors[2] + colors[3]) / count
	dmg *= 1.0 + color_bonus + combo_boost
	dmg *= 1.0 + 0.25 * int(cards.get("hunter", 0))
	dmg += 6.0 * int(info["resources"]["stone"])
	dmg += 2.0 * int(info["garbage"])
	# Score & loot.
	score += int((count * 10 + int(info["garbage"]) * 5) * chain * (2 if info["bonus"] else 1))
	var coins := int(ceil(count / 2.0 * (1.0 + 0.5 * int(cards.get("magnet", 0)))))
	coins += 5 * int(info["resources"]["wood"])
	var gems := int(info["resources"]["gem"])
	_earn(coins, gems)
	ability = minf(100.0, ability + count * 2.6 * (1.5 if cards.has("overcharge") else 1.0))
	# Juice.
	var big: bool = chain >= 3 or count >= 7 or info["bonus"]
	_hitstop(0.04 if not big else 0.07, 0.05)
	add_shake(0.16 + 0.07 * chain + (0.2 if info["bonus"] else 0.0))
	AudioSynth.play_chain(chain)
	AudioSynth.set_intensity(clampf(0.5 + chain * 0.15, 0.0, 1.0))
	if chain >= 3:
		_slowmo()
	var word := ""
	var col := UIKit.GOLD
	if chain >= 5:
		word = "UNSTOPPABLE x%d!!" % chain
		col = UIKit.PINK
	elif chain >= 3:
		word = "MEGA CASCADE x%d!" % chain
		col = UIKit.CYAN
	elif chain == 2:
		word = "CASCADE x2!"
		col = UIKit.LIME
	elif info["bonus"]:
		word = "SQUARE BLAST!" if count >= 4 else "BLAST!"
		col = UIKit.ORANGE
	elif count >= 5:
		word = "MEGA!"
	else:
		word = POP_WORDS[_rng.randi_range(0, POP_WORDS.size() - 1)]
	if not info["from_gear"] or chain > 1 or count >= 3:
		UIKit.popup_text(fx_layer, center + Vector2(0, -20), word, col, 34 + mini(chain, 5) * 6)
	if info["resources"]["wood"] > 0:
		UIKit.popup_text(fx_layer, center + Vector2(-50, 30), "+%d COINS" % (5 * int(info["resources"]["wood"])), UIKit.GOLD, 22)
	if gems > 0:
		AudioSynth.play("gem")
		UIKit.popup_text(fx_layer, center + Vector2(50, 30), "+%d GEM" % gems, UIKit.CYAN, 22)
	hero.cheer(chain >= 2)
	_deal_damage(dmg, center, UIKit.BLOCK_COLORS[clampi(last_pop_color, 0, 4)], big)
	# Gear triggers (effects caused by gear never re-trigger gear).
	if not info["from_gear"]:
		if colors[0] > 0:
			_fire_trigger("ON_POP_RED")
		if colors[1] > 0:
			_fire_trigger("ON_POP_BLUE")
		if colors[2] + colors[3] > 0:
			_fire_trigger("ON_POP_GREEN_YELLOW")
		if count >= 4:
			_fire_trigger("ON_COMBO_4_PLUS")
		if chain >= 2:
			_fire_trigger("ON_CASCADE_2_PLUS")
	if chain >= 2 and cards.has("miner") and not _miner_paid:
		_miner_paid = true
		var g := 2 * int(cards["miner"])
		_earn(0, g)
		UIKit.popup_text(fx_layer, center + Vector2(0, 40), "MINER +%d ◆" % g, UIKit.CYAN, 24)


func _on_chain_finished(_chain: int) -> void:
	AudioSynth.set_intensity(0.85 if board.danger else 0.5)


func _on_danger_changed(on: bool) -> void:
	hero.set_danger(on)
	var m := bg.material as ShaderMaterial
	var tw := create_tween()
	tw.tween_method(func(v): m.set_shader_parameter("danger", v), 1.0 if not on else 0.0, 1.0 if on else 0.0, 0.5)
	AudioSynth.set_intensity(0.9 if on else 0.5)
	if on:
		AudioSynth.play("warn", 1.0, -6.0)
		if not danger_trigger_used:
			danger_trigger_used = true
			_fire_trigger("ON_DANGER_ZONE")


func _on_topped_out() -> void:
	if cards.has("secondwind") and not second_wind_used:
		second_wind_used = true
		revive_needed = true
		board.state = BoardScript.State.RESOLVING
		return
	_game_over()


func _spawn_piece() -> void:
	if mode == "over":
		return
	fired_this_drop.clear()
	_miner_paid = false
	board.spawn_next()
	if revive_needed:
		await _revive()
		if mode != "over":
			board.spawn_next()


func _revive() -> void:
	revive_needed = false
	AudioSynth.play("level_up")
	hero.cheer(true)
	_banner("SECOND WIND!", "Top 5 rows cleared", UIKit.PINK, 1.0)
	board.queue_op(func(): return board.op_clear_rows(0, 4))
	await board.process_ops()


## After every locked piece: turn bookkeeping, boss attacks, drafts.
func _on_piece_resolved() -> void:
	if mode == "over":
		return
	var rid := _run_id
	combo_boost = 0.0
	if revive_needed:
		await _revive()
		if rid != _run_id:
			return
	if boss_hp <= 0.0:
		await _boss_defeated()
		if rid != _run_id:
			return
		_spawn_piece()
		return
	var res: Dictionary = turns.register_drop()
	board.tick_ice()
	if rush_drops > 0:
		rush_drops -= 1
		if rush_drops == 0:
			_update_speed()
	if res["turn_end"]:
		danger_trigger_used = false
		_pulse_pips()
		_fire_trigger("ON_TURN_END")
		await board.process_ops()
		if rid != _run_id:
			return
	if mode == "over":
		return
	if boss_hp <= 0.0:
		await _boss_defeated()
		if rid != _run_id:
			return
		_spawn_piece()
		return
	if res["attack"]:
		if boss_stunned:
			boss_stunned = false
			UIKit.popup_text(fx_layer, BOSS_POS + Vector2(0, -300), "STUNNED — ATTACK SKIPPED!", UIKit.GOLD, 26)
			AudioSynth.play("boing", 1.4)
			_refresh_turn_ui()
		else:
			await _boss_attack()
			if rid != _run_id:
				return
	elif res["telegraph"] and not boss_stunned:
		boss.wind_up()
		AudioSynth.play("warn")
		UIKit.squash(countdown_panel, 0.3)
	if mode == "over" or board.state == BoardScript.State.DEAD and not revive_needed:
		return
	if revive_needed:
		await _revive()
		if rid != _run_id:
			return
	if boss_hp <= 0.0:
		await _boss_defeated()
		if rid != _run_id:
			return
		_spawn_piece()
		return
	if res["draft"]:
		await _run_draft()
		if rid != _run_id:
			return
	_update_speed()
	_spawn_piece()


# =========================================================================
# Gear Trigger -> Effect engine
# =========================================================================

func _fire_trigger(trigger: String) -> void:
	if mode == "over":
		return
	for e in equipped:
		var item: Dictionary = e["item"]
		if item["trigger"] != trigger or fired_this_drop.has(item["id"]):
			continue
		var weak: bool = boss_data.get("weak", "") == trigger
		var chance := GearDatabase.proc_chance(item, e["level"]) + 0.15 * int(cards.get("junkie", 0))
		if weak or _rng.randf() < chance:
			fired_this_drop[item["id"]] = true
			_apply_effect(item, int(e["level"]), weak, int(e["slot"]))


func _apply_effect(item: Dictionary, level: int, weak: bool, slot: int) -> void:
	var eff: String = item["effect"]
	var amt := GearDatabase.effect_amount(eff, level) * (2.0 if weak else 1.0)
	var n := maxi(1, int(amt))
	# Feedback: flash the slot, shout the effect over the hero.
	if slot >= 0 and slot < slot_boxes.size():
		UIKit.squash(slot_boxes[slot], 0.3)
		UIKit.burst(world, slot_boxes[slot].position + Vector2(31, 31), GearDatabase.TRIGGER_COLOR[item["trigger"]], 14, 200.0)
	var txt: String = GearDatabase.EFFECT_SHORT[eff]
	var py := -300.0 - 62.0 * maxi(slot, 0)
	UIKit.popup_text(fx_layer, HERO_POS + Vector2(_rng.randf_range(-20, 20), py), txt, GearDatabase.TRIGGER_COLOR[item["trigger"]], 30, 50.0, 1.1)
	UIKit.popup_text(fx_layer, HERO_POS + Vector2(0, py + 30), item["name"], Color.WHITE, 15, 50.0, 1.1)
	if weak:
		UIKit.popup_text(fx_layer, BOSS_POS + Vector2(0, -320), "WEAKNESS x2!", UIKit.ORANGE, 28)
	AudioSynth.play("level_up", 1.5, -8.0)
	match eff:
		"ZAP_BOTTOM_ROW":
			board.queue_op(func(): return board.op_zap_bottom(n))
		"COLOR_CONVERT":
			board.queue_op(func(): return board.op_convert(n))
		"CRUSH_GARBAGE":
			board.queue_op(func(): return board.op_crush_garbage(n))
		"SLOW_GRAVITY":
			slow_timer = maxf(slow_timer, amt)
			_update_speed()
		"DELAY_BOSS":
			turns.delay_attack(n)
		"SPAWN_GEMS":
			# Gem gear pays out at most once per turn per item to keep the
			# Loot Forge economy healthy.
			if int(gem_turn.get(item["id"], -1)) != turns.turn:
				gem_turn[item["id"]] = turns.turn
				var g := GearDatabase.potency(level) * (2 if weak else 1)
				_earn(0, g)
				AudioSynth.play("gem")
				UIKit.popup_text(fx_layer, HERO_POS + Vector2(70, -250), "+%d ◆" % g, UIKit.CYAN, 26)
		"BOOST_MULTIPLIER":
			combo_boost += amt
		"SPAWN_BOMB":
			board.queue_op(func(): return board.op_make_special(T.BOMB, n))
		"NEXT_WILDCARD":
			board.wild_queue += n
		"STUN_BOSS":
			boss_stunned = true
			boss.stun(3.0)
			AudioSynth.play("boing")
			_refresh_turn_ui()
		"CLEAR_COLUMN_EDGE":
			board.queue_op(func(): return board.op_clear_edge(n))
		"SHIELD_BLOCK":
			board.queue_op(func(): return board.op_make_special(T.SHIELD, n))
		"TWIN_POP":
			var c := last_pop_color
			board.queue_op(func(): return board.op_twin_pop(c, n))
		"HEAL_OVERFLOW":
			board.queue_op(func(): return board.op_heal_overflow(n))
		"MEGA_STRIKE":
			AudioSynth.play("zap")
			_deal_damage(amt, hero.global_position + Vector2(60, -90), UIKit.GOLD, true, 30.0)


func _use_ability() -> void:
	if mode != "playing" or ability < 100.0 or board.state != BoardScript.State.FALLING:
		return
	ability = 0.0
	AudioSynth.play("fanfare", 1.3, -4.0)
	add_shake(0.6)
	_hitstop(0.12, 0.1)
	hero.cheer(true)
	_banner("GEAR BURST!", "", UIKit.GOLD, 0.7)
	for e in equipped:
		_apply_effect(e["item"], int(e["level"]), false, int(e["slot"]))
	_deal_damage(20.0 + floor_num * 4.0, hero.global_position + Vector2(0, -170), UIKit.GOLD, true, 36.0)
	await board.run_ops_now()


# =========================================================================
# Damage & boss
# =========================================================================

func _deal_damage(amount: float, from_pos: Vector2, color: Color, big: bool, size: float = 18.0) -> void:
	if amount <= 0.0 or mode == "over":
		return
	boss_hp = maxf(0.0, boss_hp - amount)
	var target := boss.global_position + Vector2(0, -190)
	var orb := _make_orb(color, size + minf(amount, 60.0) * 0.25)
	orb.global_position = from_pos
	var ctrl := from_pos.lerp(target, 0.5) + Vector2(0, -180)
	var mover := func(t: float) -> void:
		var a := from_pos.lerp(ctrl, t)
		var b := ctrl.lerp(target, t)
		orb.global_position = a.lerp(b, t)
		orb.rotation = t * 8.0
	var tw := orb.create_tween()
	tw.tween_method(mover, 0.0, 1.0, 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		UIKit.burst(world, target, color, 18 if big else 10, 340.0, 1.3 if big else 1.0)
		UIKit.popup_text(fx_layer, target + Vector2(_rng.randf_range(-50, 50), -40), "-%d" % int(round(amount)), Color.WHITE, 30 if big else 24, 60.0, 0.8)
		boss.hit(big)
		AudioSynth.play("squeak" if not big else "hit", _rng.randf_range(0.9, 1.15), -2.0)
		add_shake(0.12 if not big else 0.3)
		_refresh_boss_hp(false)
		orb.queue_free())


func _make_orb(color: Color, r: float) -> Node2D:
	var orb := Node2D.new()
	var outer := Polygon2D.new()
	outer.polygon = GearArt.ellipse(Vector2.ZERO, Vector2(r + 5, r + 5), 20)
	outer.color = Color("1b0f2e")
	orb.add_child(outer)
	var inner := Polygon2D.new()
	inner.polygon = GearArt.star(Vector2.ZERO, r, r * 0.55, 6)
	inner.color = color
	orb.add_child(inner)
	var hl := Polygon2D.new()
	hl.polygon = GearArt.ellipse(Vector2(-r * 0.3, -r * 0.35), Vector2(r * 0.3, r * 0.2), 10)
	hl.color = Color(1, 1, 1, 0.8)
	orb.add_child(hl)
	fx_layer.add_child(orb)
	return orb


func _refresh_boss_hp(instant: bool) -> void:
	var ratio := clampf(boss_hp / maxf(boss_max, 1.0), 0.0, 1.0)
	var w := 262.0 * ratio
	if instant:
		boss_hp_fill.size.x = w
	else:
		var tw := boss_hp_fill.create_tween()
		tw.tween_property(boss_hp_fill, "size:x", w, 0.3).set_trans(Tween.TRANS_SINE)
	boss_hp_fill.visible = ratio > 0.0
	boss_hp_label.text = "%d / %d" % [int(ceil(boss_hp)), int(boss_max)]


func _boss_attack() -> void:
	var attacks: Array = boss_data["attacks"]
	var kind: String = attacks[_rng.randi_range(0, attacks.size() - 1)]
	boss.attack_lunge()
	AudioSynth.play("zap", 0.7)
	var from := boss.global_position + Vector2(-80, -150)
	var to := board.global_position + Vector2(BoardScript.COLS * BoardScript.CELL * 0.5, 40)
	var orb := _make_orb(Color("9a8fa8") if kind != "freeze" else Color("bff6ff"), 24)
	orb.global_position = from
	var tw := orb.create_tween()
	tw.tween_property(orb, "global_position", to, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	orb.queue_free()
	UIKit.burst(world, to, Color("9a8fa8"), 24, 360.0, 1.3)
	add_shake(0.45)
	hero.hit(kind == "junk")
	var label := ""
	match kind:
		"garbage":
			var n := maxi(1, 2 + floor_num / 2 - int(cards.get("thick", 0)))
			label = "GARBAGE x%d!" % n
			_shout(label, Color("c9bfd6"))
			var landed: int = await board.drop_garbage(n)
			if landed > 0:
				_fire_trigger("ON_GARBAGE_LAND")
			else:
				UIKit.popup_text(fx_layer, to + Vector2(0, 60), "SHIELDED!", UIKit.CYAN, 32)
		"freeze":
			board.freeze_column(8)
			_shout("FROZEN COLUMN!", Color("bff6ff"))
		"junk":
			_shout("JUNK ROW!", Color("c9bfd6"))
			await board.push_junk_row()
			_fire_trigger("ON_GARBAGE_LAND")
		"rush":
			rush_drops = 10
			_update_speed()
			_shout("GRAVITY RUSH!", UIKit.ORANGE)
			AudioSynth.play("warn")
		"scramble":
			board.scramble_colors(5)
			_shout("COLOR SCRAMBLE!", UIKit.PINK)
	if mode != "over" and board.state != BoardScript.State.DEAD:
		await board.process_ops()


func _shout(text: String, color: Color) -> void:
	UIKit.popup_text(fx_layer, BOARD_POS + Vector2(175, 260), text, color, 40, 80.0, 1.3)


func _boss_defeated() -> void:
	var rid := _run_id
	mode = "transition"
	bosses_beaten += 1
	boss.defeat()
	hero.victory()
	AudioSynth.play("fanfare")
	AudioSynth.play("boom", 0.8)
	add_shake(0.8)
	_slowmo()
	var glow := UIKit.make_glow(Color(1, 0.85, 0.3, 0.9), 520, 14)
	glow.position = BOSS_POS + Vector2(-260, -440)
	world.add_child(glow)
	world.move_child(glow, 2)
	for i in 4:
		UIKit.burst(world, BOSS_POS + Vector2(_rng.randf_range(-90, 90), _rng.randf_range(-260, -80)), Color.WHITE, 40, 520.0, 1.4, true)
	var coins := 40 + 20 * floor_num
	var gems := 3 + floor_num
	_earn(coins, gems)
	SaveManager.record_boss_win()
	_banner("BOSS DEFEATED!", "+%d ●   +%d ◆" % [coins, gems], UIKit.GOLD, 1.8)
	await get_tree().create_timer(1.9, false).timeout
	if rid != _run_id:
		return
	glow.queue_free()
	board.queue_op(func(): return board.op_clear_all_garbage())
	await board.process_ops()
	if rid != _run_id:
		return
	await _run_draft()
	if rid != _run_id:
		return
	# Next floor: the old boss tumbles away and a tougher one slides in.
	floor_num += 1
	floor_label.text = "FLOOR %d" % floor_num
	var tw := create_tween()
	tw.tween_property(boss, "position", BOSS_POS + Vector2(460, 80), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await tw.finished
	if rid != _run_id:
		return
	hero.reset_pose()
	hero.set_danger(board.danger)
	_spawn_boss(true)
	turns.set_interval(int(boss_data["interval"]))
	AudioSynth.play("boing", 0.8)
	_banner("FLOOR %d" % floor_num, "%s  —  %s" % [boss_data["name"], _quirk_text()], UIKit.PURPLE, 1.5)
	await get_tree().create_timer(0.9, false).timeout
	if rid != _run_id:
		return
	mode = "playing"


# =========================================================================
# Tactical Draft
# =========================================================================

func _run_draft() -> void:
	if mode == "over":
		return
	var prev_mode := mode
	mode = "draft"
	board.input_enabled = false
	var pool: Array = []
	for c in CARDS:
		if c["id"] == "secondwind" and cards.has("secondwind"):
			continue
		pool.append(c)
	pool.shuffle()
	var picks := pool.slice(0, 3)
	var root := UIKit.make_overlay(overlay_layer, 0.55)
	_overlay = root
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	center.add_child(v)
	var title := UIKit.make_label("TACTICAL DRAFT", 52, UIKit.GOLD, 12)
	title.add_theme_font_override("font", UIKit.font_bold)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UIKit.make_label("Pick one upgrade for this run", 22, Color.WHITE, 6)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 26)
	v.add_child(h)
	var buttons: Array = []
	for i in picks.size():
		var card: Dictionary = picks[i]
		var b := _make_card_button(card)
		h.add_child(b)
		buttons.append(b)
		b.pressed.connect(func(): _choose_card(card, root))
		b.scale = Vector2(0.1, 0.1)
		var tw := b.create_tween()
		tw.tween_interval(0.08 * i)
		tw.tween_property(b, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in buttons.size():
		var b: Button = buttons[i]
		b.focus_neighbor_left = buttons[(i - 1 + buttons.size()) % buttons.size()].get_path()
		b.focus_neighbor_right = buttons[(i + 1) % buttons.size()].get_path()
		b.focus_neighbor_top = b.get_path()
		b.focus_neighbor_bottom = b.get_path()
	AudioSynth.play("card")
	await get_tree().process_frame
	buttons[1 if buttons.size() > 1 else 0].grab_focus()
	await _draft_done
	board.input_enabled = true
	if mode == "draft":
		mode = prev_mode if prev_mode != "draft" else "playing"


func _make_card_button(card: Dictionary) -> Button:
	var b := UIKit.make_button("", card["color"], Vector2(250, 300), 20)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14
	v.offset_right = -14
	v.offset_top = 18
	v.offset_bottom = -14
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var icon := UIKit.make_label(card["icon"], 64, Color.WHITE, 10)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(icon)
	var nm := UIKit.make_label(card["name"], 26, Color.WHITE, 8)
	nm.add_theme_font_override("font", UIKit.font_bold)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nm)
	var d := UIKit.make_label(card["desc"], 18, Color.WHITE, 6)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(210, 0)
	v.add_child(d)
	var stacks := int(cards.get(card["id"], 0))
	if stacks > 0:
		var st := UIKit.make_label("OWNED x%d" % stacks, 16, UIKit.GOLD, 5)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(st)
	return b


func _choose_card(card: Dictionary, root: Control) -> void:
	if not is_instance_valid(root) or root.is_queued_for_deletion():
		return
	var id: String = card["id"]
	cards[id] = int(cards.get(id, 0)) + 1
	AudioSynth.play("level_up")
	match id:
		"purge":
			board.queue_op(func(): return board.op_clear_rows(BoardScript.ROWS - 2, BoardScript.ROWS - 1))
		"thick":
			board.queue_op(func(): return board.op_make_special(T.SHIELD, 2))
		"demo":
			board.queue_op(func(): return board.op_make_special(T.BOMB, 2))
		"wildclub":
			board.wild_every = maxi(4, 10 - 2 * int(cards[id]))
		"tactical":
			turns.bonus_interval += 1
			turns.delay_attack(1)
		"feather":
			_update_speed()
	UIKit.burst(overlay_layer, get_viewport().get_visible_rect().size * 0.5, Color.WHITE, 40, 500.0, 1.2, true)
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.2)
	tw.tween_callback(root.queue_free)
	await board.process_ops()
	_draft_done.emit()


# =========================================================================
# Game over, pause, rematch
# =========================================================================

func _game_over() -> void:
	if mode == "over":
		return
	mode = "over"
	board.state = BoardScript.State.DEAD
	board.input_enabled = false
	hero.defeat()
	boss.victory()
	AudioSynth.play("lose")
	AudioSynth.set_intensity(0.0)
	add_shake(0.7)
	_slowmo()
	var is_best := SaveManager.record_run(score, floor_num)
	var rid := _run_id
	await get_tree().create_timer(1.1, false).timeout
	if rid == _run_id:
		_show_game_over(is_best)


func _show_game_over(is_best: bool) -> void:
	var root := UIKit.make_overlay(overlay_layer, 0.6)
	_overlay = root
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := UIKit.make_panel(UIKit.PANEL, 30)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)
	var title := UIKit.make_label("KNOCKED OUT!", 56, UIKit.RED, 12)
	title.add_theme_font_override("font", UIKit.font_bold)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	v.add_child(row)
	var face := TextureRect.new()
	face.texture = FaceManager.get_texture(FaceManager.hero_face_id())
	face.custom_minimum_size = Vector2(130, 130)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.material = FaceManager.make_face_material()
	face.pivot_offset = Vector2(65, 65)
	face.scale = Vector2(1.3, 0.6)
	row.add_child(face)
	var ftw := face.create_tween().set_loops()
	ftw.tween_property(face, "rotation", 0.25, 0.5).set_trans(Tween.TRANS_SINE)
	ftw.tween_property(face, "rotation", -0.25, 0.5).set_trans(Tween.TRANS_SINE)
	var stats := VBoxContainer.new()
	row.add_child(stats)
	for line in [
		"Score: %d" % score,
		"Floor reached: %d   (best %d)" % [floor_num, int(SaveManager.data["best_floor"])],
		"Bosses beaten: %d   ·   Best chain: x%d" % [bosses_beaten, max_chain_run],
		"Loot: +%d ●   +%d ◆" % [run_coins, run_gems],
	]:
		stats.add_child(UIKit.make_label(line, 22, Color.WHITE, 6))
	if is_best:
		var nb := UIKit.make_label("★ NEW HIGH SCORE! ★", 30, UIKit.GOLD, 8)
		nb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nb)
		var ntw := nb.create_tween().set_loops()
		ntw.tween_property(nb, "modulate", Color(1, 1, 1, 0.5), 0.4)
		ntw.tween_property(nb, "modulate", Color.WHITE, 0.4)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	v.add_child(btns)
	var rematch := UIKit.make_button("⟲ INSTANT REMATCH", UIKit.LIME.darkened(0.15), Vector2(300, 70), 26)
	var locker := UIKit.make_button("GEAR & LOOT", UIKit.PURPLE, Vector2(200, 70), 22)
	var menu := UIKit.make_button("MENU", UIKit.ORANGE, Vector2(140, 70), 22)
	btns.add_child(rematch)
	btns.add_child(locker)
	btns.add_child(menu)
	rematch.pressed.connect(start_run)
	locker.pressed.connect(func(): UIKit.change_scene("res://scenes/GearLocker.tscn"))
	menu.pressed.connect(func(): UIKit.change_scene("res://scenes/MainMenu.tscn"))
	_link_row([rematch, locker, menu])
	panel.scale = Vector2(0.3, 0.3)
	panel.pivot_offset = Vector2(330, 200)
	var tw := panel.create_tween()
	tw.tween_property(panel, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rematch.grab_focus()


func _link_row(buttons: Array) -> void:
	for i in buttons.size():
		var b: Control = buttons[i]
		b.focus_neighbor_left = buttons[(i - 1 + buttons.size()) % buttons.size()].get_path()
		b.focus_neighbor_right = buttons[(i + 1) % buttons.size()].get_path()


func _toggle_pause() -> void:
	if mode == "paused":
		if is_instance_valid(_overlay):
			_overlay.queue_free()
		get_tree().paused = false
		mode = "playing"
		return
	if mode != "playing":
		return
	mode = "paused"
	get_tree().paused = true
	var root := UIKit.make_overlay(overlay_layer, 0.65)
	_overlay = root
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := UIKit.make_panel(UIKit.PANEL, 30)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var title := UIKit.make_label("PAUSED", 52, UIKit.GOLD, 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var resume := UIKit.make_button("RESUME", UIKit.LIME.darkened(0.15), Vector2(320, 64))
	var restart := UIKit.make_button("RESTART RUN", UIKit.ORANGE, Vector2(320, 64))
	var menu := UIKit.make_button("MAIN MENU", UIKit.PINK, Vector2(320, 64))
	var vol_row := HBoxContainer.new()
	vol_row.add_child(UIKit.make_label("VOLUME", 20))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(SaveManager.data.get("volume", 0.8))
	slider.custom_minimum_size = Vector2(200, 32)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(val): AudioSynth.set_volume(val))
	vol_row.add_child(slider)
	for c in [resume, restart, menu, vol_row]:
		v.add_child(c)
	resume.pressed.connect(_toggle_pause)
	restart.pressed.connect(start_run)
	menu.pressed.connect(func(): UIKit.change_scene("res://scenes/MainMenu.tscn"))
	var col := [resume, restart, menu, slider]
	for i in col.size():
		col[i].focus_neighbor_top = col[(i - 1 + col.size()) % col.size()].get_path()
		col[i].focus_neighbor_bottom = col[(i + 1) % col.size()].get_path()
	resume.grab_focus()


# =========================================================================
# HUD helpers & juice
# =========================================================================

func _earn(coins: int, gems: int) -> void:
	if coins > 0:
		run_coins += coins
		SaveManager.add_coins(coins)
	if gems > 0:
		run_gems += gems
		SaveManager.add_gems(gems)


func _refresh_hud() -> void:
	floor_label.text = "FLOOR %d" % floor_num
	score_label.text = str(score)
	_refresh_currency()
	_refresh_turn_ui()


func _refresh_currency() -> void:
	if coins_label:
		coins_label.text = "● %d" % SaveManager.coins()
		gems_label.text = "◆ %d" % SaveManager.gems()


func _refresh_turn_ui() -> void:
	if turn_label == null:
		return
	turn_label.text = "TURN %d" % turns.turn
	for i in pips.size():
		var on: bool = i < turns.drops_in_turn
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.border_color = Color("1b0f2e")
		sb.set_border_width_all(3)
		sb.bg_color = UIKit.GOLD if on else Color(1, 1, 1, 0.15)
		pips[i].add_theme_stylebox_override("panel", sb)
	var to_draft: int = TurnScript.TURNS_PER_DRAFT - ((turns.turn - 1) % TurnScript.TURNS_PER_DRAFT)
	draft_label.text = "DRAFT %d" % to_draft
	if boss_stunned:
		countdown_label.text = "★ STUNNED"
		countdown_panel.add_theme_stylebox_override("panel", _chip_style(Color("ffb31a"), 22))
	else:
		countdown_label.text = "⚔ ATTACK IN %d" % turns.attack_countdown
		countdown_panel.add_theme_stylebox_override("panel", _chip_style(Color("ff3355") if turns.attack_countdown <= 1 else Color("8a2be2"), 22))


func _pulse_pips() -> void:
	for i in pips.size():
		var p: Control = pips[i]
		var tw := p.create_tween()
		tw.tween_interval(i * 0.04)
		tw.tween_property(p, "scale", Vector2(1.5, 1.5), 0.1)
		tw.tween_property(p, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)


func _refresh_mute() -> void:
	mute_btn.text = "✕" if AudioSynth.is_muted() else "♪"


func _refresh_device_ui() -> void:
	var touch := InputHub.is_touch()
	touch_left.visible = touch
	touch_right.visible = touch
	hint_panel.visible = not touch
	if InputHub.is_pad():
		hint_label.text = "D-Pad Move   Ⓐ/Ⓑ Rotate   LT Soft   RT/▲ Slam\nⓍ/Ⓨ Gear Burst   Start Pause"
	else:
		hint_label.text = "←/→ Move   W/Z Rotate   S Soft   Space Slam\nE Gear Burst   Esc Pause   (tap a column with mouse/touch)"


func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount, 0.0, 1.0)


func _hitstop(duration: float, time_scale: float) -> void:
	_hitstop_id += 1
	var id := _hitstop_id
	Engine.time_scale = time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	if id == _hitstop_id:
		Engine.time_scale = 1.0


func _slowmo() -> void:
	_hitstop_id += 1
	var id := _hitstop_id
	Engine.time_scale = 0.45
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(camera, "zoom", Vector2(1.06, 1.06), 0.12).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.3)
	tw.tween_property(camera, "zoom", Vector2.ONE, 0.25).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(0.45, true, false, true).timeout
	if id == _hitstop_id:
		Engine.time_scale = 1.0


## Big centred banner with sunburst. Frees itself after `duration`.
func _banner(title: String, subtitle: String, color: Color, duration: float) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(root)
	var vs := get_viewport().get_visible_rect().size
	var glow := UIKit.make_glow(Color(color.r, color.g, color.b, 0.7), 640, 16)
	glow.position = vs * 0.5 - Vector2(320, 320)
	root.add_child(glow)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v)
	var t := UIKit.make_label(title, 72, Color.WHITE, 14)
	t.add_theme_font_override("font", UIKit.font_bold)
	t.add_theme_color_override("font_color", color.lightened(0.3))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if subtitle != "":
		var s := UIKit.make_label(subtitle, 26, Color.WHITE, 8)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(s)
	root.pivot_offset = vs * 0.5
	root.scale = Vector2(0.2, 0.2)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(duration)
	tw.tween_property(root, "modulate:a", 0.0, 0.3)
	tw.tween_callback(root.queue_free)
