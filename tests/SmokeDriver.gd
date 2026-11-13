extends Node

var shots := "user://shots"
var failures: Array = []
var _ai_on := false
var _ai_cd := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	DirAccess.make_dir_recursive_absolute(shots)
	_run()


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		push_error("SMOKE FAIL: " + msg)
	else:
		print("ok - ", msg)


func wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots + "/" + name + ".png")


func accept() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var ev2 := InputEventAction.new()
	ev2.action = "ui_accept"
	ev2.pressed = false
	Input.parse_input_event(ev2)


func _run() -> void:
	# --- AppInfo title-from-filename rules.
	var AI = load("res://scripts/AppInfo.gd")
	check(AI.name_from_path("C:\\Games\\hefland.exe") == "hefland", "windows exe name")
	check(AI.name_from_path("/home/me/hefland.x86_64") == "hefland", "linux exe name")
	check(AI.name_from_path("/Applications/hefland.app/Contents/MacOS/BlockLoot") == "hefland", "macos bundle name")
	check(AI.name_from_path("/x/Super_Cool_Game.exe") == "Super Cool Game", "underscores to spaces")
	check(GearDatabase.items.size() == 150, "150 items generated")
	var combos := {}
	var names := {}
	for it in GearDatabase.items:
		combos[it["trigger"] + it["effect"]] = true
		names[it["name"]] = true
	check(combos.size() == 150, "all 150 trigger/effect combos unique")
	check(names.size() == 150, "all 150 item names unique")
	var rc := [0, 0, 0, 0]
	for it in GearDatabase.items:
		rc[int(it["rarity"])] += 1
	print("rarity counts: ", rc)

	# --- Main menu.
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	await wait(1.6)
	await shot("01_menu")
	check(get_tree().current_scene.name == "MainMenu", "main menu loaded")
	# Gamepad-style navigation: ui_down should move focus to the next button.
	var f0 = get_viewport().gui_get_focus_owner()
	var ev := InputEventAction.new()
	ev.action = "ui_down"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	var f1 = get_viewport().gui_get_focus_owner()
	check(f0 != null and f1 != null and f0 != f1, "gamepad ui_down moves menu focus")

	# --- Face studio + photo import.
	get_tree().change_scene_to_file("res://scenes/FaceStudio.tscn")
	await wait(1.0)
	await shot("02_face_studio")
	var photo := Image.create(640, 480, false, Image.FORMAT_RGB8)
	for y in 480:
		for x in 640:
			var d := Vector2(x - 320, y - 220).length()
			var skin := Color(0.95, 0.75, 0.6) if d < 150 else Color(0.2, 0.5, 0.9).lerp(Color(0.9, 0.9, 1.0), y / 480.0)
			if Vector2(x - 270, y - 190).length() < 18 or Vector2(x - 370, y - 190).length() < 18:
				skin = Color(0.1, 0.1, 0.15)
			if y > 260 and y < 275 and absf(x - 320) < 60:
				skin = Color(0.8, 0.2, 0.3)
			photo.set_pixel(x, y, skin)
	var jpg_path := OS.get_user_data_dir() + "/test_photo.jpg"
	photo.save_jpg(jpg_path)
	var studio = get_tree().current_scene
	var before := FaceManager.get_faces().size()
	studio._on_file_selected(jpg_path)
	await wait(0.6)
	await shot("03_cropper")
	studio._crop_role = "boss"
	studio._save_crop()
	await wait(0.8)
	check(FaceManager.get_faces().size() == before + 1, "uploaded face saved to gallery")
	check(FileAccess.file_exists("user://faces/faces_meta.json"), "faces_meta.json written")
	await shot("04_face_saved")

	# --- Gear locker & loot forge.
	get_tree().change_scene_to_file("res://scenes/GearLocker.tscn")
	await wait(1.0)
	var locker = get_tree().current_scene
	locker._show_tab(false)
	await wait(0.5)
	await shot("05_locker")
	locker._show_tab(true)
	SaveManager.add_gems(100)
	SaveManager.add_coins(1000)
	var owned_before := SaveManager.owned_count()
	var lv_sum_before := 0
	for k in SaveManager.data["items"]:
		lv_sum_before += int(SaveManager.data["items"][k])
	locker._open_chest("gem")
	await wait(0.5)
	await shot("06_chest_shake")
	await wait(1.2)
	await shot("07_chest_reveal")
	var lv_sum_after := 0
	for k in SaveManager.data["items"]:
		lv_sum_after += int(SaveManager.data["items"][k])
	check(SaveManager.owned_count() > owned_before or lv_sum_after > lv_sum_before or SaveManager.coins() > 0, "chest granted loot")
	locker._close_reveal()
	for i in 6:
		locker._opening = false
		locker._open_chest("coin")
		await wait(1.6)
		locker._close_reveal()
	await wait(0.4)
	locker._show_tab(false)
	await wait(0.4)
	await shot("08_locker_more")

	# --- Arena.
	get_tree().change_scene_to_file("res://scenes/Arena.tscn")
	await wait(1.2)
	var arena = get_tree().current_scene
	check(arena.board.state == arena.board.State.FALLING, "piece spawned in arena")
	await shot("09_arena_start")
	_ai_on = true
	await wait(10.0)
	await shot("10_arena_play")
	print("score after 10s: ", arena.score, " boss hp ", arena.boss_hp)
	check(arena.score > 0, "scoring works during auto-play")
	# Gear burst.
	arena.ability = 100.0
	await wait(0.2)
	arena._use_ability()
	await wait(0.4)
	await shot("11_gear_burst")
	await wait(1.5)
	# Force a boss defeat -> draft.
	arena.boss_hp = 0.5
	var floor_before: int = arena.floor_num
	var t := 0.0
	while arena.mode != "draft" and t < 20.0:
		await wait(0.1)
		t += 0.1
	await shot("12_draft")
	check(arena.mode == "draft", "draft shown after boss defeat")
	t = 0.0
	while arena.floor_num == floor_before and t < 10.0:
		await wait(0.1)
		t += 0.1
	check(arena.floor_num == floor_before + 1, "advanced to next floor")
	await wait(1.0)
	await shot("13_next_boss")
	# Let the boss attack a few times.
	await wait(12.0)
	await shot("14_arena_later")
	# Force a knockout.
	_ai_on = false
	for c in 7:
		for r in range(0, 12):
			if arena.board.grid[c][r] == null:
				arena.board.grid[c][r] = arena.board.make_cell(arena.board.T.GARBAGE, -1)
	arena.cards.erase("secondwind")
	t = 0.0
	while arena.mode != "over" and t < 15.0:
		if arena.board.state == arena.board.State.FALLING:
			arena.board.hard_drop()
		await wait(0.1)
		t += 0.1
	check(arena.mode == "over", "knockout triggered")
	await wait(1.6)
	await shot("15_game_over")
	var t0 := Time.get_ticks_usec()
	arena.start_run()
	var dt := (Time.get_ticks_usec() - t0) / 1000.0
	print("rematch reset took %.1f ms" % dt)
	check(dt < 200.0, "instant rematch under 200 ms")
	await wait(0.5)
	check(arena.mode == "playing" and arena.board.state == arena.board.State.FALLING, "rematch playable")
	await shot("16_rematch")
	# Touch layout.
	InputHub.device = InputHub.TOUCH
	arena._refresh_device_ui()
	await wait(0.3)
	await shot("18_touch")
	check(arena.touch_left.visible and not arena.hint_panel.visible, "touch controls shown for touch device")
	InputHub.device = InputHub.KBM
	arena._refresh_device_ui()
	# Pause menu.
	arena._toggle_pause()
	await wait(0.3)
	await shot("17_pause")
	arena._toggle_pause()
	check(not get_tree().paused, "unpaused")
	print("SMOKE DONE: %d failures %s" % [failures.size(), str(failures)])
	get_tree().quit(1 if failures.size() > 0 else 0)


var _draft_cd := 0.0


func _process(delta: float) -> void:
	var arena = get_tree().current_scene
	if arena == null or not ("board" in arena):
		return
	# Auto-pick draft cards so runs never stall.
	_draft_cd -= delta
	if arena.mode == "draft" and _draft_cd <= 0.0:
		_draft_cd = 0.8
		accept()
	if not _ai_on:
		return
	var b = arena.board
	if b.state != b.State.FALLING or b.piece.is_empty():
		return
	_ai_cd -= delta
	if _ai_cd > 0.0:
		return
	_ai_cd = 0.15
	# Greedy: try every column/rotation, prefer touching same colours, low stacks.
	var best_score := -INF
	var best := Vector2i(3, 0)
	for rot in 4:
		for col in 7:
			if not b._fits(col, b.piece["row"], rot):
				continue
			var r: int = b.piece["row"]
			while b._fits(col, r + 1, rot):
				r += 1
			var cells: Array = b._piece_cells(col, r, rot)
			var sc := 0.0
			var datas := [b.piece["a"], b.piece["b"]]
			for i in 2:
				var p: Vector2i = cells[i]
				sc -= (12 - p.y) * 0.4
				for d in b.OFFSETS:
					var n = b.cell_at(p.x + d.x, p.y + d.y)
					if n != null and int(n["c"]) == int(datas[i]["c"]) and int(n["c"]) >= 0:
						sc += 3.0
			sc += randf() * 0.5
			if sc > best_score:
				best_score = sc
				best = Vector2i(col, rot)
	b.piece["rot"] = best.y
	b.piece["col"] = best.x
	b.hard_drop()
