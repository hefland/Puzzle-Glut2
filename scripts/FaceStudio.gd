extends Control
## FaceStudio — upload photos, crop them into cartoon ovals, tag them as
## Hero (Me) / Rival Boss / Both, and pick the face your fighter wears.
## Fully navigable with mouse, touch or gamepad. On desktop you can also
## drag & drop image files straight onto the window.

const FighterScene := preload("res://scenes/CartoonFighter.tscn")
const IMAGE_FILTERS := ["*.png, *.jpg, *.jpeg, *.webp ; Images"]

var stage: Control
var grid: GridContainer
var scroll: ScrollContainer
var upload_btn: Button
var back_btn: Button
var preview_fighter: Node2D
var name_label: Label
var role_btn: Button
var hero_btn: Button
var delete_btn: Button
var status_label: Label
var selected_id := ""
var face_buttons: Array = []
var _file_dialog: FileDialog
var _cropper: Control
var _crop_src: Image
var _crop_preview: TextureRect
var _crop_zoom: HSlider
var _crop_x: HSlider
var _crop_y: HSlider
var _crop_role := "both"
var _delete_armed := false


func _ready() -> void:
	add_child(UIKit.make_background(Color("1f5fbf"), Color("7af0ff"), Color("ffd23f")))
	stage = Control.new()
	stage.set_anchors_preset(Control.PRESET_CENTER)
	stage.size = Vector2(1280, 720)
	stage.position = -stage.size * 0.5
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	_build_header()
	_build_gallery()
	_build_detail()
	selected_id = FaceManager.hero_face_id()
	_rebuild_gallery()
	FaceManager.faces_changed.connect(_rebuild_gallery)
	get_window().files_dropped.connect(_on_files_dropped)
	AudioSynth.play_music("menu")
	await get_tree().process_frame
	upload_btn.grab_focus()


func _exit_tree() -> void:
	if get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)


# --- Layout ---------------------------------------------------------------

func _build_header() -> void:
	back_btn = UIKit.make_button("◀ BACK", UIKit.ORANGE, Vector2(150, 56), 22)
	back_btn.position = Vector2(24, 20)
	back_btn.pressed.connect(_go_back)
	stage.add_child(back_btn)
	var title := UIKit.make_label("FACE STUDIO", 56, UIKit.GOLD, 12)
	title.add_theme_font_override("font", UIKit.font_bold)
	title.position = Vector2(0, 14)
	title.size = Vector2(1280, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(title)
	var sub := UIKit.make_label("Upload straight-on photos of you, friends or pets — they become fighters!", 19, Color.WHITE, 6)
	sub.position = Vector2(0, 82)
	sub.size = Vector2(1280, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(sub)


func _build_gallery() -> void:
	var panel := UIKit.make_panel(Color(0.12, 0.06, 0.25, 0.85), 26)
	panel.position = Vector2(24, 124)
	panel.size = Vector2(760, 576)
	stage.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	upload_btn = UIKit.make_button("＋  UPLOAD FACE PHOTO", UIKit.LIME.darkened(0.15), Vector2(720, 66), 28)
	upload_btn.pressed.connect(_open_file_dialog)
	v.add_child(upload_btn)
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	margin.add_child(grid)


func _build_detail() -> void:
	var panel := UIKit.make_panel(Color(0.12, 0.06, 0.25, 0.85), 26)
	panel.position = Vector2(804, 124)
	panel.size = Vector2(452, 576)
	stage.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_END
	panel.add_child(v)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 250)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	var holder := Node2D.new()
	holder.position = Vector2(226, 292)
	holder.scale = Vector2(0.82, 0.82)
	panel.add_child(holder)
	preview_fighter = FighterScene.instantiate()
	holder.add_child(preview_fighter)
	preview_fighter.equip_loadout_from_save()
	name_label = UIKit.make_label("", 28, UIKit.GOLD, 8)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_label)
	hero_btn = UIKit.make_button("★ SET AS MY HERO", UIKit.PINK, Vector2(400, 56), 24)
	hero_btn.pressed.connect(_set_hero)
	v.add_child(hero_btn)
	role_btn = UIKit.make_button("ROLE: Both", UIKit.PURPLE, Vector2(400, 56), 22)
	role_btn.pressed.connect(_cycle_role)
	v.add_child(role_btn)
	delete_btn = UIKit.make_button("DELETE FACE", UIKit.RED.darkened(0.15), Vector2(400, 50), 20)
	delete_btn.pressed.connect(_delete_selected)
	v.add_child(delete_btn)
	status_label = UIKit.make_label("", 16, Color(1, 1, 1, 0.8), 5)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(400, 0)
	v.add_child(status_label)


func _rebuild_gallery() -> void:
	for c in grid.get_children():
		c.queue_free()
	face_buttons.clear()
	var hero_id := FaceManager.hero_face_id()
	for f in FaceManager.get_faces():
		var b := _make_face_card(f, f["id"] == hero_id)
		grid.add_child(b)
		face_buttons.append(b)
	if FaceManager.get_face(selected_id).is_empty():
		selected_id = hero_id
	_wire_focus()
	_show_selected()


func _make_face_card(f: Dictionary, is_hero: bool) -> Button:
	var role_color := {"hero": UIKit.BLUE, "boss": UIKit.RED, "both": UIKit.PURPLE}
	var b := UIKit.make_button("", role_color.get(f["role"], UIKit.PURPLE), Vector2(160, 196), 16)
	b.set_meta("face_id", f["id"])
	var tex := TextureRect.new()
	tex.texture = FaceManager.get_texture(f["id"])
	tex.material = FaceManager.make_face_material()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.position = Vector2(20, 12)
	tex.size = Vector2(120, 120)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tex)
	var nm := UIKit.make_label(str(f["name"]), 16, Color.WHITE, 5)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.position = Vector2(4, 136)
	nm.size = Vector2(152, 22)
	nm.clip_text = true
	b.add_child(nm)
	var rl := UIKit.make_label(FaceManager.ROLE_LABELS.get(f["role"], "Both"), 14, UIKit.GOLD, 5)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.position = Vector2(4, 160)
	rl.size = Vector2(152, 20)
	b.add_child(rl)
	if is_hero:
		var star := UIKit.make_label("★ ME", 16, Color.WHITE, 5)
		var sp := PanelContainer.new()
		sp.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.PINK, 12, 3, false))
		sp.position = Vector2(92, -8)
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp.add_child(star)
		b.add_child(sp)
	b.pressed.connect(func(): _select(str(f["id"])))
	b.focus_entered.connect(func(): _select(str(f["id"]), false))
	return b


func _wire_focus() -> void:
	var cols := grid.columns
	for i in face_buttons.size():
		var b: Button = face_buttons[i]
		if i < cols:
			b.focus_neighbor_top = upload_btn.get_path()
		b.focus_neighbor_right = (face_buttons[i + 1] if i % cols != cols - 1 and i + 1 < face_buttons.size() else hero_btn).get_path()
	if not face_buttons.is_empty():
		upload_btn.focus_neighbor_bottom = face_buttons[0].get_path()
	upload_btn.focus_neighbor_top = back_btn.get_path()
	back_btn.focus_neighbor_bottom = upload_btn.get_path()
	upload_btn.focus_neighbor_right = hero_btn.get_path()
	for b in [hero_btn, role_btn, delete_btn]:
		b.focus_neighbor_left = (face_buttons[0] if not face_buttons.is_empty() else upload_btn).get_path()


# --- Selection & editing --------------------------------------------------

func _select(id: String, sound: bool = true) -> void:
	selected_id = id
	_delete_armed = false
	_show_selected()
	if sound:
		preview_fighter.cheer()


func _show_selected() -> void:
	var f := FaceManager.get_face(selected_id)
	if f.is_empty():
		return
	preview_fighter.set_face(selected_id)
	name_label.text = str(f["name"])
	role_btn.text = "ROLE: %s" % FaceManager.ROLE_LABELS.get(f["role"], "Both")
	var is_hero := FaceManager.hero_face_id() == selected_id
	hero_btn.text = "★ THIS IS ME!" if is_hero else "★ SET AS MY HERO"
	hero_btn.disabled = is_hero
	delete_btn.visible = not bool(f["builtin"])
	delete_btn.text = "DELETE FACE"
	status_label.text = "Rival Bosses wear faces tagged Rival Boss or Both." if not is_hero else "Your fighter wears this face in battle."


func _set_hero() -> void:
	FaceManager.set_hero(selected_id)
	AudioSynth.play("level_up")
	preview_fighter.cheer(true)
	UIKit.burst(self, hero_btn.get_global_rect().get_center(), UIKit.PINK, 24, 300.0, 1.0, true)


func _cycle_role() -> void:
	var f := FaceManager.get_face(selected_id)
	if f.is_empty():
		return
	var next := FaceManager.next_role(str(f["role"]))
	FaceManager.set_role(selected_id, next)
	await get_tree().process_frame
	role_btn.grab_focus()


func _delete_selected() -> void:
	if not _delete_armed:
		_delete_armed = true
		delete_btn.text = "PRESS AGAIN TO DELETE"
		AudioSynth.play("warn", 1.0, -6.0)
		return
	FaceManager.delete_face(selected_id)
	selected_id = FaceManager.hero_face_id()
	AudioSynth.play("boom", 1.4, -6.0)
	await get_tree().process_frame
	upload_btn.grab_focus()


func _go_back() -> void:
	UIKit.change_scene("res://scenes/MainMenu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if is_instance_valid(_cropper):
			_close_cropper()
		else:
			_go_back()


# --- Upload & crop --------------------------------------------------------

func _open_file_dialog() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = PackedStringArray(IMAGE_FILTERS)
		_file_dialog.title = "Choose a face photo"
		_file_dialog.size = Vector2i(900, 560)
		_file_dialog.file_selected.connect(_on_file_selected)
		add_child(_file_dialog)
	# Native pickers on mobile and for mouse users; Godot's own dialog
	# (fully gamepad-navigable) when a controller is in use.
	_file_dialog.use_native_dialog = OS.has_feature("mobile") or not InputHub.is_pad()
	var pictures := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pictures != "" and not OS.has_feature("mobile"):
		_file_dialog.current_dir = pictures
	_file_dialog.popup_centered()


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		var ext := f.get_extension().to_lower()
		if ext in ["png", "jpg", "jpeg", "webp"]:
			_on_file_selected(f)
			return


func _on_file_selected(path: String) -> void:
	var img := FaceManager.load_source_image(path)
	if img == null:
		status_label.text = "Couldn't read that image. Try a PNG, JPG or WEBP photo."
		AudioSynth.play("warn")
		return
	_crop_src = img
	_open_cropper()


func _open_cropper() -> void:
	if is_instance_valid(_cropper):
		_cropper.queue_free()
	_crop_role = "both"
	_cropper = UIKit.make_overlay(self, 0.7)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cropper.add_child(center)
	var panel := UIKit.make_panel(UIKit.PANEL, 28)
	center.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 28)
	panel.add_child(h)
	# Live oval preview.
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(left)
	var title := UIKit.make_label("CROP YOUR FACE", 34, UIKit.GOLD, 9)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(title)
	_crop_preview = TextureRect.new()
	_crop_preview.custom_minimum_size = Vector2(300, 300)
	_crop_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crop_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_crop_preview.material = FaceManager.make_face_material()
	left.add_child(_crop_preview)
	var tip := UIKit.make_label("Center the eyes a little above the middle.", 16, Color(1, 1, 1, 0.8), 5)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(tip)
	# Controls.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(right)
	_crop_zoom = _slider(right, "ZOOM", 1.0, 3.0, 1.15)
	_crop_x = _slider(right, "LEFT  ◀ ▶  RIGHT", -1.0, 1.0, 0.0)
	_crop_y = _slider(right, "UP  ▲ ▼  DOWN", -1.0, 1.0, -0.25)
	right.add_child(UIKit.make_label("WHO IS THIS?", 20, Color.WHITE, 6))
	var roles := HBoxContainer.new()
	roles.add_theme_constant_override("separation", 8)
	right.add_child(roles)
	var role_buttons: Array = []
	for r in FaceManager.ROLES:
		var rb := UIKit.make_button(FaceManager.ROLE_LABELS[r], UIKit.PURPLE, Vector2(130, 50), 17)
		rb.set_meta("role", r)
		roles.add_child(rb)
		role_buttons.append(rb)
	var refresh_roles := func():
		for rb in role_buttons:
			UIKit.style_button(rb, UIKit.PINK if rb.get_meta("role") == _crop_role else UIKit.PANEL_LIGHT)
	for rb in role_buttons:
		rb.pressed.connect(func():
			_crop_role = rb.get_meta("role")
			refresh_roles.call())
	refresh_roles.call()
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	right.add_child(actions)
	var save := UIKit.make_button("✔ SAVE FACE", UIKit.LIME.darkened(0.15), Vector2(200, 60), 24)
	var cancel := UIKit.make_button("CANCEL", UIKit.ORANGE, Vector2(150, 60), 22)
	actions.add_child(save)
	actions.add_child(cancel)
	save.pressed.connect(_save_crop)
	cancel.pressed.connect(_close_cropper)
	# Gamepad focus chain.
	var chain: Array = [_crop_zoom, _crop_x, _crop_y, role_buttons[0], save]
	for i in chain.size():
		chain[i].focus_neighbor_top = chain[(i - 1 + chain.size()) % chain.size()].get_path()
		chain[i].focus_neighbor_bottom = chain[(i + 1) % chain.size()].get_path()
	for i in role_buttons.size():
		role_buttons[i].focus_neighbor_top = _crop_y.get_path()
		role_buttons[i].focus_neighbor_bottom = save.get_path()
	save.focus_neighbor_right = cancel.get_path()
	cancel.focus_neighbor_left = save.get_path()
	cancel.focus_neighbor_top = role_buttons[0].get_path()
	_update_crop_preview()
	panel.pivot_offset = Vector2(400, 220)
	panel.scale = Vector2(0.5, 0.5)
	var tw := panel.create_tween()
	tw.tween_property(panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_crop_zoom.grab_focus()


func _slider(parent: Control, label: String, lo: float, hi: float, value: float) -> HSlider:
	parent.add_child(UIKit.make_label(label, 18, Color.WHITE, 6))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = value
	s.custom_minimum_size = Vector2(400, 34)
	s.focus_mode = Control.FOCUS_ALL
	s.value_changed.connect(func(_v): _update_crop_preview())
	parent.add_child(s)
	return s


func _update_crop_preview() -> void:
	if _crop_src == null or _crop_preview == null:
		return
	var img := FaceManager.crop_face(_crop_src, _crop_zoom.value, _crop_x.value, _crop_y.value, false)
	_crop_preview.texture = ImageTexture.create_from_image(img)


func _save_crop() -> void:
	var avatar := FaceManager.crop_face(_crop_src, _crop_zoom.value, _crop_x.value, _crop_y.value, true)
	var id := FaceManager.add_face(avatar, _crop_role)
	if id == "":
		status_label.text = "Couldn't save that face (storage full?)."
		return
	if _crop_role == "hero":
		FaceManager.set_hero(id)
	selected_id = id
	AudioSynth.play("fanfare", 1.2, -4.0)
	UIKit.burst(self, get_viewport_rect().size * 0.5, Color.WHITE, 50, 500.0, 1.2, true)
	_close_cropper()
	_show_selected()
	preview_fighter.cheer(true)


func _close_cropper() -> void:
	if is_instance_valid(_cropper):
		_cropper.queue_free()
	_cropper = null
	_crop_preview = null
	await get_tree().process_frame
	upload_btn.grab_focus()
