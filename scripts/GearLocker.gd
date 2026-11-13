extends Control
## GearLocker — 3-slot loadout picker, the filterable 150-item grid with
## Trigger/Effect badges, and the Loot Forge: a shaking, glowing treasure
## chest that bursts open with confetti (with a pity timer and a free daily).

const FighterScene := preload("res://scenes/CartoonFighter.tscn")
const GearArt := preload("res://scripts/ProceduralGearArt.gd")

const COIN_COST := 150
const GEM_COST := 15
const PITY_LIMIT := 10

var stage: Control
var back_btn: Button
var tab_loadout: Button
var tab_forge: Button
var loadout_view: Control
var forge_view: Control
var currency_label: Label
var hero: Node2D
var slot_buttons: Array = []
var filter_buttons: Array = []
var owned_toggle: Button
var grid: GridContainer
var scroll: ScrollContainer
var item_buttons: Array = []
var detail_name: Label
var detail_meta: Label
var detail_desc: Label
var detail_icon_holder: Control
var equip_btn: Button
var filter_slot := -1
var owned_only := false
var selected_item := -1

# Forge
var chest: Node2D
var chest_lid: Node2D
var chest_glow: ColorRect
var coin_btn: Button
var gem_btn: Button
var daily_btn: Button
var pity_label: Label
var _opening := false
var _reveal: Control


func _ready() -> void:
	add_child(UIKit.make_background(Color("2b1060"), Color("c24dff"), Color("ffd23f")))
	stage = Control.new()
	stage.set_anchors_preset(Control.PRESET_CENTER)
	stage.size = Vector2(1280, 720)
	stage.position = -stage.size * 0.5
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	_build_header()
	_build_loadout()
	_build_forge()
	SaveManager.currency_changed.connect(_refresh_currency)
	_refresh_currency()
	_show_tab(false)
	AudioSynth.play_music("menu")
	if SaveManager.daily_available():
		_show_tab(true)


# --- Header ---------------------------------------------------------------

func _build_header() -> void:
	back_btn = UIKit.make_button("◀ BACK", UIKit.ORANGE, Vector2(140, 54), 22)
	back_btn.position = Vector2(20, 16)
	back_btn.pressed.connect(_go_back)
	stage.add_child(back_btn)
	tab_loadout = UIKit.make_button("LOADOUT", UIKit.BLUE, Vector2(200, 54), 24)
	tab_loadout.position = Vector2(420, 16)
	tab_loadout.pressed.connect(func(): _show_tab(false))
	stage.add_child(tab_loadout)
	tab_forge = UIKit.make_button("LOOT FORGE", UIKit.PINK, Vector2(220, 54), 24)
	tab_forge.position = Vector2(640, 16)
	tab_forge.pressed.connect(func(): _show_tab(true))
	stage.add_child(tab_forge)
	var cp := PanelContainer.new()
	cp.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.1, 0.05, 0.2, 0.85), 16, 4))
	cp.position = Vector2(950, 18)
	stage.add_child(cp)
	currency_label = UIKit.make_label("", 22, Color.WHITE, 6)
	cp.add_child(currency_label)
	back_btn.focus_neighbor_right = tab_loadout.get_path()
	tab_loadout.focus_neighbor_left = back_btn.get_path()
	tab_loadout.focus_neighbor_right = tab_forge.get_path()
	tab_forge.focus_neighbor_left = tab_loadout.get_path()


func _refresh_currency() -> void:
	currency_label.text = "● %d    ◆ %d    %d/150" % [SaveManager.coins(), SaveManager.gems(), SaveManager.owned_count()]
	if coin_btn:
		coin_btn.disabled = SaveManager.coins() < COIN_COST or _opening
		gem_btn.disabled = SaveManager.gems() < GEM_COST or _opening
		daily_btn.visible = SaveManager.daily_available()
		daily_btn.disabled = _opening
		var pity := PITY_LIMIT - int(SaveManager.data.get("pity", 0))
		pity_label.text = "EPIC+ GUARANTEED IN %d PULL%s" % [pity, "" if pity == 1 else "S"]


func _show_tab(forge: bool) -> void:
	loadout_view.visible = not forge
	forge_view.visible = forge
	UIKit.style_button(tab_loadout, UIKit.BLUE if not forge else UIKit.PANEL_LIGHT)
	UIKit.style_button(tab_forge, UIKit.PINK if forge else UIKit.PANEL_LIGHT)
	var below: Control = (daily_btn if daily_btn.visible else coin_btn) if forge else slot_buttons[0]
	for b in [back_btn, tab_loadout, tab_forge]:
		b.focus_neighbor_bottom = below.get_path()
	await get_tree().process_frame
	if forge:
		(daily_btn if daily_btn.visible else coin_btn).grab_focus()
	else:
		slot_buttons[0].grab_focus()


func _go_back() -> void:
	SaveManager.save_game()
	UIKit.change_scene("res://scenes/MainMenu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if is_instance_valid(_reveal):
			_close_reveal()
		elif not _opening:
			_go_back()


# --- Loadout tab ----------------------------------------------------------

func _build_loadout() -> void:
	loadout_view = Control.new()
	loadout_view.size = Vector2(1280, 720)
	loadout_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(loadout_view)
	# Hero preview.
	var hp := UIKit.make_panel(Color(0.12, 0.06, 0.25, 0.85), 26)
	hp.position = Vector2(20, 86)
	hp.size = Vector2(330, 614)
	loadout_view.add_child(hp)
	var glow := UIKit.make_glow(Color(1, 0.9, 0.5, 0.5), 340, 10)
	glow.position = Vector2(185 - 170, 300 - 170)
	loadout_view.add_child(glow)
	var holder := Node2D.new()
	holder.position = Vector2(185, 418)
	holder.scale = Vector2(0.88, 0.88)
	loadout_view.add_child(holder)
	hero = FighterScene.instantiate()
	holder.add_child(hero)
	hero.set_face(FaceManager.hero_face_id())
	hero.equip_loadout_from_save()
	var slots := VBoxContainer.new()
	slots.position = Vector2(36, 436)
	slots.add_theme_constant_override("separation", 8)
	loadout_view.add_child(slots)
	for i in 3:
		var b := UIKit.make_button("", UIKit.PANEL_LIGHT, Vector2(298, 76), 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		slots.add_child(b)
		slot_buttons.append(b)
		var slot := i
		b.pressed.connect(func(): _set_filter(slot))
	# Filters.
	var fr := HBoxContainer.new()
	fr.position = Vector2(370, 86)
	fr.add_theme_constant_override("separation", 8)
	loadout_view.add_child(fr)
	var names := ["ALL", "HEAD", "FACE", "HAND"]
	for i in names.size():
		var fb := UIKit.make_button(names[i], UIKit.CYAN.darkened(0.2), Vector2(120, 48), 20)
		fr.add_child(fb)
		filter_buttons.append(fb)
		var f := i - 1
		fb.pressed.connect(func(): _set_filter(f))
	owned_toggle = UIKit.make_button("OWNED ONLY", UIKit.PANEL_LIGHT, Vector2(170, 48), 18)
	owned_toggle.pressed.connect(func():
		owned_only = not owned_only
		_apply_filter())
	fr.add_child(owned_toggle)
	# Grid.
	var gp := UIKit.make_panel(Color(0.12, 0.06, 0.25, 0.85), 22)
	gp.position = Vector2(370, 146)
	gp.size = Vector2(890, 384)
	loadout_view.add_child(gp)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(856, 356)
	gp.add_child(scroll)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	scroll.add_child(margin)
	grid = GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	margin.add_child(grid)
	for item in GearDatabase.items:
		var b := _make_item_button(item)
		grid.add_child(b)
		item_buttons.append(b)
	# Detail panel.
	var dp := UIKit.make_panel(Color(0.12, 0.06, 0.25, 0.9), 22)
	dp.position = Vector2(370, 542)
	dp.size = Vector2(890, 158)
	loadout_view.add_child(dp)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 18)
	dp.add_child(dh)
	detail_icon_holder = Control.new()
	detail_icon_holder.custom_minimum_size = Vector2(124, 124)
	dh.add_child(detail_icon_holder)
	var dv := VBoxContainer.new()
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv.add_theme_constant_override("separation", 2)
	dh.add_child(dv)
	detail_name = UIKit.make_label("Pick an item", 26, UIKit.GOLD, 8)
	dv.add_child(detail_name)
	detail_meta = UIKit.make_label("", 16, Color.WHITE, 5)
	dv.add_child(detail_meta)
	detail_desc = UIKit.make_label("", 17, Color.WHITE, 5)
	dv.add_child(detail_desc)
	equip_btn = UIKit.make_button("EQUIP", UIKit.LIME.darkened(0.15), Vector2(170, 64), 24)
	equip_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	equip_btn.pressed.connect(_equip_selected)
	dh.add_child(equip_btn)
	_refresh_slots()
	_apply_filter()
	_select_item(SaveManager.equipped("head"))


func _make_item_button(item: Dictionary) -> Button:
	var id: int = item["id"]
	var b := Button.new()
	b.custom_minimum_size = Vector2(96, 96)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("item_id", id)
	UIKit.juice(b)
	b.pressed.connect(func(): _select_item(id))
	b.focus_entered.connect(func(): _select_item(id))
	_style_item_button(b)
	return b


func _style_item_button(b: Button) -> void:
	var id: int = b.get_meta("item_id")
	var item := GearDatabase.get_item(id)
	var owned := SaveManager.owns(id)
	var rc: Color = UIKit.RARITY_COLORS[int(item["rarity"])]
	for c in b.get_children():
		c.queue_free()
	var base := UIKit.panel_style(Color(0.2, 0.12, 0.36) if owned else Color(0.1, 0.06, 0.18), 16, 4, false)
	base.border_color = rc if owned else Color(0.3, 0.25, 0.4)
	var focus := base.duplicate()
	focus.border_color = UIKit.GOLD
	focus.set_border_width_all(6)
	focus.bg_color = base.bg_color.lightened(0.15)
	b.add_theme_stylebox_override("normal", base)
	b.add_theme_stylebox_override("hover", focus)
	b.add_theme_stylebox_override("pressed", focus)
	b.add_theme_stylebox_override("focus", focus)
	var icon := GearArt.build_icon(id, SaveManager.item_level(id), 84, not owned)
	icon.position = Vector2(6, 2)
	b.add_child(icon)
	if owned:
		var lv := SaveManager.item_level(id)
		var stars := UIKit.make_label("★".repeat(lv), 12, UIKit.GOLD, 4)
		stars.position = Vector2(6, 74)
		b.add_child(stars)
		var tb := UIKit.make_label(GearDatabase.TRIGGER_BADGE[item["trigger"]], 11, GearDatabase.TRIGGER_COLOR[item["trigger"]], 4)
		tb.position = Vector2(6, 2)
		b.add_child(tb)
		var slot_key: String = item["slot_key"]
		if SaveManager.equipped(slot_key) == id:
			var eq := UIKit.make_label("E", 16, UIKit.LIME, 5)
			eq.position = Vector2(78, 0)
			b.add_child(eq)
	else:
		var q := UIKit.make_label("?", 30, Color(1, 1, 1, 0.45), 5)
		q.position = Vector2(38, 26)
		b.add_child(q)


func _set_filter(slot: int) -> void:
	filter_slot = slot
	for i in filter_buttons.size():
		UIKit.style_button(filter_buttons[i], UIKit.CYAN.darkened(0.2) if i - 1 == slot else UIKit.PANEL_LIGHT)
	_apply_filter()
	if slot >= 0:
		await get_tree().process_frame
		for b in item_buttons:
			if b.visible:
				b.grab_focus()
				break


func _apply_filter() -> void:
	UIKit.style_button(owned_toggle, UIKit.LIME.darkened(0.25) if owned_only else UIKit.PANEL_LIGHT)
	for i in filter_buttons.size():
		UIKit.style_button(filter_buttons[i], UIKit.CYAN.darkened(0.2) if i - 1 == filter_slot else UIKit.PANEL_LIGHT)
	for b in item_buttons:
		var item := GearDatabase.get_item(b.get_meta("item_id"))
		var show := (filter_slot < 0 or int(item["slot"]) == filter_slot) and (not owned_only or SaveManager.owns(item["id"]))
		b.visible = show
	scroll.scroll_vertical = 0


func _select_item(id: int) -> void:
	var item := GearDatabase.get_item(id)
	if item.is_empty():
		return
	selected_item = id
	for c in detail_icon_holder.get_children():
		c.queue_free()
	var owned := SaveManager.owns(id)
	var lv := SaveManager.item_level(id)
	var icon := GearArt.build_icon(id, lv, 124, not owned)
	detail_icon_holder.add_child(icon)
	var rarity := int(item["rarity"])
	if owned:
		detail_name.text = item["name"]
		detail_name.add_theme_color_override("font_color", UIKit.RARITY_COLORS[rarity])
		detail_meta.text = "%s  ·  %s SLOT  ·  Lv.%d %s" % [GearDatabase.rarity_name(rarity).to_upper(), GearDatabase.SLOT_NAMES[int(item["slot"])].to_upper(), lv, "(MAX)" if lv >= 5 else ""]
		detail_desc.text = GearDatabase.describe(item, lv)
		var equipped := SaveManager.equipped(item["slot_key"]) == id
		equip_btn.disabled = equipped
		equip_btn.text = "EQUIPPED" if equipped else "EQUIP"
	else:
		detail_name.text = "??? %s" % GearDatabase.rarity_name(rarity)
		detail_name.add_theme_color_override("font_color", UIKit.RARITY_COLORS[rarity])
		detail_meta.text = "LOCKED  ·  %s SLOT" % GearDatabase.SLOT_NAMES[int(item["slot"])].to_upper()
		detail_desc.text = "WHEN: %s\nWin it in the Loot Forge!" % GearDatabase.TRIGGER_TEXT[item["trigger"]]
		equip_btn.disabled = true
		equip_btn.text = "LOCKED"


func _equip_selected() -> void:
	if selected_item < 0 or not SaveManager.owns(selected_item):
		return
	var item := GearDatabase.get_item(selected_item)
	SaveManager.equip(item["slot_key"], selected_item)
	hero.set_gear(selected_item, SaveManager.item_level(selected_item))
	hero.cheer(true)
	AudioSynth.play("level_up")
	_refresh_slots()
	for b in item_buttons:
		if int(GearDatabase.get_item(b.get_meta("item_id"))["slot"]) == int(item["slot"]):
			_style_item_button(b)
	_select_item(selected_item)


func _refresh_slots() -> void:
	var keys := ["head", "face", "hand"]
	for i in 3:
		var b: Button = slot_buttons[i]
		for c in b.get_children():
			if c.name != "Gloss":
				c.queue_free()
		var id := SaveManager.equipped(keys[i])
		var item := GearDatabase.get_item(id)
		var icon := GearArt.build_icon(id, SaveManager.item_level(id), 64)
		icon.position = Vector2(8, 6)
		b.add_child(icon)
		var l := UIKit.make_label("%s\n%s" % [GearDatabase.SLOT_NAMES[i].to_upper(), item.get("name", "— empty —")], 16, Color.WHITE, 5)
		l.position = Vector2(80, 10)
		l.size = Vector2(210, 56)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.clip_text = true
		b.add_child(l)
		if not item.is_empty():
			UIKit.style_button(b, UIKit.RARITY_COLORS[int(item["rarity"])].darkened(0.35))


# --- Loot Forge tab -------------------------------------------------------

func _build_forge() -> void:
	forge_view = Control.new()
	forge_view.size = Vector2(1280, 720)
	forge_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(forge_view)
	var title := UIKit.make_label("LOOT FORGE", 54, UIKit.GOLD, 12)
	title.add_theme_font_override("font", UIKit.font_bold)
	title.position = Vector2(0, 86)
	title.size = Vector2(1280, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forge_view.add_child(title)
	chest_glow = UIKit.make_glow(Color(1, 0.85, 0.35, 0.8), 520, 14)
	chest_glow.position = Vector2(640 - 260, 380 - 260)
	forge_view.add_child(chest_glow)
	chest = Node2D.new()
	chest.position = Vector2(640, 470)
	forge_view.add_child(chest)
	_build_chest()
	var row := HBoxContainer.new()
	row.position = Vector2(140, 590)
	row.size = Vector2(1000, 80)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	forge_view.add_child(row)
	daily_btn = UIKit.make_button("★ FREE DAILY", UIKit.LIME.darkened(0.15), Vector2(250, 76), 26)
	coin_btn = UIKit.make_button("OPEN  %d ●" % COIN_COST, UIKit.ORANGE, Vector2(270, 76), 26)
	gem_btn = UIKit.make_button("PREMIUM  %d ◆" % GEM_COST, UIKit.CYAN.darkened(0.25), Vector2(290, 76), 26)
	row.add_child(daily_btn)
	row.add_child(coin_btn)
	row.add_child(gem_btn)
	daily_btn.pressed.connect(func(): _open_chest("daily"))
	coin_btn.pressed.connect(func(): _open_chest("coin"))
	gem_btn.pressed.connect(func(): _open_chest("gem"))
	var btns := [daily_btn, coin_btn, gem_btn]
	for i in 3:
		btns[i].focus_neighbor_left = btns[(i + 2) % 3].get_path()
		btns[i].focus_neighbor_right = btns[(i + 1) % 3].get_path()
		btns[i].focus_neighbor_top = tab_forge.get_path()
	pity_label = UIKit.make_label("", 18, UIKit.CYAN, 6)
	pity_label.position = Vector2(0, 676)
	pity_label.size = Vector2(1280, 30)
	pity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forge_view.add_child(pity_label)
	var odds := UIKit.make_label("Coin chest: 62% Common · 28% Rare · 8% Epic · 2% Legendary      Premium: 35 · 40 · 18 · 7%", 14, Color(1, 1, 1, 0.75), 4)
	odds.position = Vector2(0, 150)
	odds.size = Vector2(1280, 24)
	odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forge_view.add_child(odds)


func _build_chest() -> void:
	var ink := Color("1b0f2e")
	# Body.
	GearArt.poly(chest, GearArt.rrect(-130, -110, 260, 120, 18), Color("a0522d"), true, 7)
	GearArt.poly(chest, GearArt.rrect(-130, -70, 260, 22, 6), Color("ffc93c"), true, 5)
	for x in [-118, 96]:
		GearArt.poly(chest, GearArt.rrect(x, -110, 22, 120, 6), Color("ffc93c"), true, 5)
	GearArt.poly(chest, GearArt.rrect(-26, -86, 52, 52, 10), Color("ffd23f"), true, 5)
	GearArt.poly(chest, GearArt.ellipse(Vector2(0, -62), Vector2(8, 10), 12), ink, false)
	GearArt.gloss(chest, Vector2(-70, -96), Vector2(30, 6), 0.3)
	# Lid (separate node so it can flip open).
	chest_lid = Node2D.new()
	chest_lid.position = Vector2(0, -110)
	chest.add_child(chest_lid)
	GearArt.poly(chest_lid, GearArt.ellipse(Vector2(0, 0), Vector2(132, 70), 28, PI, TAU), Color("b5652f"), true, 7)
	GearArt.poly(chest_lid, GearArt.rrect(-132, -8, 264, 16, 6), Color("ffc93c"), true, 5)
	for x in [-118, 96]:
		GearArt.poly(chest_lid, GearArt.rrect(x, -64, 22, 64, 6), Color("ffc93c"), true, 5)
	GearArt.gloss(chest_lid, Vector2(-50, -46), Vector2(36, 10), 0.35)
	var tw := chest.create_tween().set_loops()
	tw.tween_property(chest, "scale", Vector2(1.03, 0.97), 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(chest, "scale", Vector2(0.98, 1.02), 0.7).set_trans(Tween.TRANS_SINE)


func _open_chest(kind: String) -> void:
	if _opening:
		return
	match kind:
		"daily":
			if not SaveManager.daily_available():
				return
			SaveManager.claim_daily()
		"coin":
			if not SaveManager.spend(COIN_COST, 0):
				AudioSynth.play("warn")
				return
		"gem":
			if not SaveManager.spend(0, GEM_COST):
				AudioSynth.play("warn")
				return
	_opening = true
	_refresh_currency()
	# Roll first so the glow can hint at the rarity.
	var pity := int(SaveManager.data.get("pity", 0))
	var force := pity >= PITY_LIMIT - 1
	var id := GearDatabase.roll_item(kind != "coin", force)
	var item := GearDatabase.get_item(id)
	var rarity := int(item["rarity"])
	SaveManager.data["pity"] = 0 if rarity >= GearDatabase.Rarity.EPIC else pity + 1
	SaveManager.data["total_pulls"] = int(SaveManager.data.get("total_pulls", 0)) + 1
	var result := SaveManager.grant_item(id)
	if result["maxed"]:
		SaveManager.add_coins(60)
	SaveManager.save_game()
	# Shake, rumble, glow…
	var rc: Color = UIKit.RARITY_COLORS[rarity]
	var gm := chest_glow.material as ShaderMaterial
	gm.set_shader_parameter("glow_color", Color(rc.r, rc.g, rc.b, 0.9))
	var tw := create_tween()
	for i in 10:
		var amp := 0.04 + i * 0.012
		tw.tween_property(chest, "rotation", amp * (1 if i % 2 == 0 else -1), 0.06)
		if i % 3 == 0:
			tw.tween_callback(func(): AudioSynth.play("rumble", 1.0 + i * 0.05, -4.0))
	tw.tween_property(chest, "rotation", 0.0, 0.05)
	tw.parallel().tween_property(chest_glow, "scale", Vector2(1.5, 1.5), 0.6)
	await tw.finished
	# …burst!
	AudioSynth.play("boom", 1.3, -4.0)
	AudioSynth.play("fanfare")
	var lid_tw := create_tween()
	lid_tw.tween_property(chest_lid, "position", Vector2(420, -620), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lid_tw.parallel().tween_property(chest_lid, "rotation", 3.2, 0.5)
	for i in 3:
		UIKit.burst(forge_view, Vector2(640, 380), Color.WHITE, 45, 620.0, 1.5, true)
	UIKit.burst(forge_view, Vector2(640, 380), rc, 30, 420.0, 2.0)
	await get_tree().create_timer(0.35).timeout
	_show_reveal(id, result)


func _show_reveal(id: int, result: Dictionary) -> void:
	var item := GearDatabase.get_item(id)
	var rarity := int(item["rarity"])
	var rc: Color = UIKit.RARITY_COLORS[rarity]
	_reveal = UIKit.make_overlay(self, 0.55)
	_reveal.z_index = 60
	var glow := UIKit.make_glow(Color(rc.r, rc.g, rc.b, 0.85), 700, 18)
	glow.position = get_viewport_rect().size * 0.5 - Vector2(350, 350)
	_reveal.add_child(glow)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reveal.add_child(center)
	var panel := UIKit.make_panel(UIKit.PANEL, 30)
	var ps := UIKit.panel_style(UIKit.PANEL, 30, 7)
	ps.border_color = rc
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var tag := "NEW!" if result["new"] else ("MAXED! +60 ●" if result["maxed"] else "LEVEL UP!  Lv.%d" % result["level"])
	var tl := UIKit.make_label(tag, 30, UIKit.LIME if result["new"] else UIKit.GOLD, 8)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tl)
	var ic := CenterContainer.new()
	v.add_child(ic)
	ic.add_child(GearArt.build_icon(id, SaveManager.item_level(id), 190))
	var nm := UIKit.make_label(item["name"], 34, rc, 9)
	nm.add_theme_font_override("font", UIKit.font_bold)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var rl := UIKit.make_label("%s  ·  %s" % [GearDatabase.rarity_name(rarity).to_upper(), GearDatabase.SLOT_NAMES[int(item["slot"])].to_upper()], 20, Color.WHITE, 6)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rl)
	var dl := UIKit.make_label(GearDatabase.describe(item, SaveManager.item_level(id)), 18, Color.WHITE, 5)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(dl)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)
	var equip := UIKit.make_button("EQUIP NOW", UIKit.LIME.darkened(0.15), Vector2(220, 62), 24)
	var ok := UIKit.make_button("COLLECT", UIKit.PINK, Vector2(200, 62), 24)
	h.add_child(equip)
	h.add_child(ok)
	equip.focus_neighbor_right = ok.get_path()
	ok.focus_neighbor_left = equip.get_path()
	equip.pressed.connect(func():
		selected_item = id
		_equip_selected()
		_close_reveal())
	ok.pressed.connect(_close_reveal)
	panel.pivot_offset = Vector2(260, 260)
	panel.scale = Vector2(0.2, 0.2)
	var tw := panel.create_tween()
	tw.tween_property(panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if rarity >= GearDatabase.Rarity.EPIC:
		AudioSynth.play("level_up", 0.8)
	equip.grab_focus()


func _close_reveal() -> void:
	if is_instance_valid(_reveal):
		_reveal.queue_free()
	_reveal = null
	# Reset the chest for another pull.
	chest_lid.position = Vector2(0, -110)
	chest_lid.rotation = 0.0
	chest_glow.scale = Vector2.ONE
	(chest_glow.material as ShaderMaterial).set_shader_parameter("glow_color", Color(1, 0.85, 0.35, 0.8))
	_opening = false
	_refresh_currency()
	_refresh_slots()
	for b in item_buttons:
		_style_item_button(b)
	_apply_filter()
	await get_tree().process_frame
	if forge_view.visible:
		(daily_btn if daily_btn.visible else coin_btn).grab_focus()
