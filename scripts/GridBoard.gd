extends Node2D
## GridBoard — the 7x12 combo grid.
##
## Falling 2-block dominos, match-3 flood fill (wildcards match anything),
## gravity cascades, special blocks (Bomb, Shield, Wood/Stone/Gem resources,
## Rainbow Wildcards), cracked garbage, frozen (iced) blocks, ghost landing
## preview, lock delay, wall kicks, DAS auto-repeat and touch gestures.
##
## The board never decides game rules beyond the grid: it emits signals and
## the Arena reacts (damage, gear triggers, boss attacks, turns).

signal piece_spawned
signal piece_locked(info: Dictionary)
signal blocks_popped(info: Dictionary)
signal chain_finished(chain: int)
signal piece_resolved
signal danger_changed(on: bool)
signal topped_out
signal moved
signal rotated

const COLS := 7
const ROWS := 12
const CELL := 50.0
const DANGER_ROWS := 3          # stack reaching the top 3 rows (>75%) = danger
const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 12
const DAS_DELAY := 0.16
const DAS_REPEAT := 0.045
const INK := Color("1b0f2e")

enum T { NORMAL, WILD, GARBAGE, BOMB, SHIELD, WOOD, STONE, GEM }
enum State { IDLE, FALLING, RESOLVING, DEAD }

const OFFSETS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var grid: Array = []                 # grid[c][r] -> Dictionary or null
var state: int = State.IDLE
var piece: Dictionary = {}           # {col, row, rot, a, b}
var next_pieces: Array = []
var num_colors := 4
var fall_interval := 0.75
var input_enabled := true
var wild_queue := 0                  # next N pieces carry a wildcard
var wild_every := 0                  # card: every Nth piece is wild (0 = off)
var danger := false

var _rng := RandomNumberGenerator.new()
var _fall_t := 0.0
var _lock_t := 0.0
var _lock_resets := 0
var _on_ground := false
var _das_t := 0.0
var _rotations := 0
var _pieces_spawned := 0
var _soft_dropping := false
var _touch_soft := false
var _ops: Array = []                 # queued Callables (gear / card effects)
var _pops: Array = []                # visual pop flashes
var _trails: Array = []              # hard-drop streaks
var _piece_vis := Vector2.ZERO       # smoothed piece pivot (pixels)
var _piece_rot_vis := 0.0            # smoothed rotation angle
var _time := 0.0
var _land_sound_cd := 0.0
var _styles: Dictionary = {}
var _touch_start := Vector2.ZERO
var _touch_last := Vector2.ZERO
var _touch_time := 0.0
var _touch_dragged := false
var _touch_index := -1
var _gen := 0                        # bumps on reset so stale coroutines bail out


func _ready() -> void:
	_rng.randomize()
	reset()


func reset() -> void:
	_gen += 1
	grid.clear()
	for c in COLS:
		var col: Array = []
		col.resize(ROWS)
		grid.append(col)
	piece = {}
	next_pieces.clear()
	_ops.clear()
	_pops.clear()
	_trails.clear()
	state = State.IDLE
	wild_queue = 0
	wild_every = 0
	_pieces_spawned = 0
	danger = false
	num_colors = 4
	queue_redraw()


# --- Cells ----------------------------------------------------------------

func make_cell(t: int, color: int) -> Dictionary:
	return {"t": t, "c": color, "ice": 0, "oy": 0.0, "vy": 0.0, "sq": 0.0, "pop": -1.0, "blink": _rng.randf_range(1.0, 6.0)}


func _random_half() -> Dictionary:
	var c := _rng.randi_range(0, num_colors - 1)
	var roll := _rng.randf()
	if roll < 0.035:
		return make_cell(T.WOOD, c)
	elif roll < 0.055:
		return make_cell(T.STONE, c)
	elif roll < 0.075:
		return make_cell(T.GEM, c)
	return make_cell(T.NORMAL, c)


func _make_piece_data() -> Dictionary:
	var a := _random_half()
	var b := _random_half()
	return {"a": a, "b": b}


func cell_at(c: int, r: int):
	if c < 0 or c >= COLS or r < 0 or r >= ROWS:
		return null
	return grid[c][r]


func is_free(c: int, r: int) -> bool:
	if c < 0 or c >= COLS or r >= ROWS:
		return false
	if r < 0:
		return true
	return grid[c][r] == null


func cell_center(c: int, r: float) -> Vector2:
	return Vector2((c + 0.5) * CELL, (r + 0.5) * CELL)


func cell_global(c: int, r: float) -> Vector2:
	return to_global(cell_center(c, r))


func matchable(cell) -> bool:
	return cell != null and cell["t"] != T.GARBAGE and int(cell["ice"]) <= 0 and cell["pop"] < 0.0


func occupied_count() -> int:
	var n := 0
	for c in COLS:
		for r in ROWS:
			if grid[c][r] != null:
				n += 1
	return n


func column_height(c: int) -> int:
	for r in ROWS:
		if grid[c][r] != null:
			return ROWS - r
	return 0


func max_height() -> int:
	var h := 0
	for c in COLS:
		h = maxi(h, column_height(c))
	return h


func fill_ratio() -> float:
	return float(max_height()) / ROWS


# --- Piece control --------------------------------------------------------

func spawn_next() -> void:
	if state == State.DEAD:
		return
	while next_pieces.size() < 2:
		next_pieces.append(_make_piece_data())
	var data: Dictionary = next_pieces.pop_front()
	next_pieces.append(_make_piece_data())
	_pieces_spawned += 1
	var force_wild := wild_queue > 0 or (wild_every > 0 and _pieces_spawned % wild_every == 0)
	if force_wild:
		if wild_queue > 0:
			wild_queue -= 1
		data["b"] = make_cell(T.WILD, -1)
	piece = {"col": 3, "row": 0, "rot": 0, "a": data["a"], "b": data["b"]}
	if not is_free(3, 0):
		piece = {}
		state = State.DEAD
		topped_out.emit()
		return
	_piece_vis = cell_center(3, -1.0)
	_piece_rot_vis = 0.0
	_fall_t = 0.0
	_lock_t = 0.0
	_lock_resets = 0
	_rotations = 0
	_on_ground = false
	state = State.FALLING
	piece_spawned.emit()
	queue_redraw()


func _piece_cells(col: int, row: int, rot: int) -> Array:
	var off: Vector2i = OFFSETS[rot]
	return [Vector2i(col, row), Vector2i(col + off.x, row + off.y)]


func _fits(col: int, row: int, rot: int) -> bool:
	for p in _piece_cells(col, row, rot):
		if not is_free(p.x, p.y):
			return false
	return true


func try_move(dx: int) -> bool:
	if state != State.FALLING or piece.is_empty():
		return false
	if _fits(piece["col"] + dx, piece["row"], piece["rot"]):
		piece["col"] += dx
		_after_successful_action()
		AudioSynth.play("tick", _rng.randf_range(0.95, 1.08), -4.0)
		moved.emit()
		return true
	return false


func move_to_column(target: int) -> void:
	target = clampi(target, 0, COLS - 1)
	var guard := 0
	while piece.size() > 0 and int(piece["col"]) != target and guard < COLS:
		guard += 1
		if not try_move(signi(target - int(piece["col"]))):
			break


func try_rotate(dir: int) -> bool:
	if state != State.FALLING or piece.is_empty():
		return false
	var col: int = piece["col"]
	var row: int = piece["row"]
	var nr: int = (int(piece["rot"]) + dir + 4) % 4
	var off: Vector2i = OFFSETS[nr]
	var candidates := [Vector2i(col, row), Vector2i(col - off.x, row - maxi(off.y, 0)), Vector2i(col, row - 1)]
	for cand in candidates:
		if _fits(cand.x, cand.y, nr):
			piece["col"] = cand.x
			piece["row"] = cand.y
			piece["rot"] = nr
			_finish_rotate(dir)
			return true
	# Boxed in on both sides: quick 180 flip (swap the two halves in place).
	var tmp = piece["a"]
	piece["a"] = piece["b"]
	piece["b"] = tmp
	_finish_rotate(dir)
	return true


func _finish_rotate(_dir: int) -> void:
	_rotations += 1
	_after_successful_action()
	AudioSynth.play("whoosh", 1.25 + _rng.randf_range(0.0, 0.15), -6.0)
	var a = piece["a"]
	var b = piece["b"]
	a["sq"] = -0.6
	b["sq"] = -0.6
	rotated.emit()


func _after_successful_action() -> void:
	if _on_ground and _lock_resets < MAX_LOCK_RESETS:
		_lock_t = 0.0
		_lock_resets += 1
	queue_redraw()


func hard_drop() -> void:
	if state != State.FALLING or piece.is_empty():
		return
	var start_row: int = piece["row"]
	while _fits(piece["col"], piece["row"] + 1, piece["rot"]):
		piece["row"] += 1
	var dist: int = piece["row"] - start_row
	for p in _piece_cells(piece["col"], piece["row"], piece["rot"]):
		_trails.append({"c": p.x, "from": float(p.y - dist - 1), "to": float(p.y), "life": 1.0})
	AudioSynth.play("thud", 1.0, 0.0)
	_lock_piece(true)


func set_touch_soft_drop(on: bool) -> void:
	_touch_soft = on


func _step_down() -> bool:
	if _fits(piece["col"], piece["row"] + 1, piece["rot"]):
		piece["row"] += 1
		return true
	return false


# --- Frame update ---------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_land_sound_cd = maxf(0.0, _land_sound_cd - delta)
	if state == State.FALLING and not piece.is_empty():
		_handle_input(delta)
		if state == State.FALLING and not piece.is_empty():
			_handle_gravity(delta)
	_animate_cells(delta)
	_update_piece_visual(delta)
	for p in _pops:
		p["t"] += delta * 2.4
	_pops = _pops.filter(func(p): return p["t"] < 1.0)
	for t in _trails:
		t["life"] -= delta * 4.0
	_trails = _trails.filter(func(t): return t["life"] > 0.0)
	queue_redraw()


func _handle_input(delta: float) -> void:
	if not input_enabled:
		return
	if Input.is_action_just_pressed("hard_drop"):
		hard_drop()
		return
	if Input.is_action_just_pressed("rotate_cw"):
		try_rotate(1)
	if Input.is_action_just_pressed("rotate_ccw"):
		try_rotate(-1)
	var dir := 0
	if Input.is_action_pressed("move_right"):
		dir = 1
	elif Input.is_action_pressed("move_left"):
		dir = -1
	if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_right"):
		try_move(dir)
		_das_t = DAS_DELAY
	elif dir != 0:
		_das_t -= delta
		if _das_t <= 0.0:
			try_move(dir)
			_das_t = DAS_REPEAT
	_soft_dropping = Input.is_action_pressed("soft_drop") or _touch_soft


func _handle_gravity(delta: float) -> void:
	var interval := fall_interval
	if _soft_dropping:
		interval = minf(0.035, fall_interval)
	_on_ground = not _fits(piece["col"], piece["row"] + 1, piece["rot"])
	if _on_ground:
		_lock_t += delta
		if _lock_t >= (0.12 if _soft_dropping else LOCK_DELAY):
			_lock_piece(false)
		return
	_fall_t += delta
	while _fall_t >= interval and state == State.FALLING:
		_fall_t -= interval
		if not _step_down():
			break


func _update_piece_visual(delta: float) -> void:
	if piece.is_empty():
		return
	var target := cell_center(piece["col"], piece["row"])
	_piece_vis = _piece_vis.lerp(target, clampf(delta * 26.0, 0.0, 1.0))
	var target_ang := float(piece["rot"]) * PI * 0.5
	var diff := wrapf(target_ang - _piece_rot_vis, -PI, PI)
	_piece_rot_vis += diff * clampf(delta * 22.0, 0.0, 1.0)


func _animate_cells(delta: float) -> void:
	var landed_any := false
	for c in COLS:
		for r in ROWS:
			var cell = grid[c][r]
			if cell == null:
				continue
			if cell["oy"] < 0.0:
				cell["vy"] += 3400.0 * delta
				cell["oy"] += cell["vy"] * delta
				if cell["oy"] >= 0.0:
					cell["oy"] = 0.0
					cell["vy"] = 0.0
					cell["sq"] = 1.0
					landed_any = true
			if absf(cell["sq"]) > 0.001:
				cell["sq"] = move_toward(cell["sq"], 0.0, delta * 5.0)
			if cell["pop"] >= 0.0:
				cell["pop"] = minf(cell["pop"] + delta * 5.0, 1.0)
			cell["blink"] -= delta
			if cell["blink"] < -0.12:
				cell["blink"] = _rng.randf_range(2.0, 7.0)
	if not piece.is_empty():
		for k in ["a", "b"]:
			var pc = piece[k]
			pc["sq"] = move_toward(pc["sq"], 0.0, delta * 5.0)
	if landed_any and _land_sound_cd <= 0.0:
		_land_sound_cd = 0.06
		AudioSynth.play("land", _rng.randf_range(0.9, 1.15), -6.0)


# --- Locking & resolution -------------------------------------------------

func _lock_piece(hard: bool) -> void:
	state = State.RESOLVING
	var cells := _piece_cells(piece["col"], piece["row"], piece["rot"])
	var datas := [piece["a"], piece["b"]]
	var overflow := false
	for i in 2:
		var p: Vector2i = cells[i]
		var d: Dictionary = datas[i]
		d["oy"] = 0.0
		d["sq"] = 1.0
		if p.y < 0:
			overflow = true
			continue
		grid[p.x][p.y] = d
	var info := {"hard_drop": hard, "rotations": _rotations, "col": piece["col"]}
	piece = {}
	if not hard:
		AudioSynth.play("land", 1.0, -2.0)
	piece_locked.emit(info)
	if overflow:
		state = State.DEAD
		topped_out.emit()
		# A "Second Wind" revive flips the state back; otherwise stop here.
		if state == State.DEAD:
			return
	_resolve_after_lock()


func _resolve_after_lock() -> void:
	var g := _gen
	await settle()
	if g != _gen:
		return
	await resolve_chains(false)
	if g != _gen:
		return
	await process_ops()
	if g != _gen:
		return
	_update_danger()
	if state != State.DEAD:
		piece_resolved.emit()


## Collapses every column, animating blocks falling into place.
func settle() -> void:
	var moved_any := false
	for c in COLS:
		var write := ROWS - 1
		for r in range(ROWS - 1, -1, -1):
			var cell = grid[c][r]
			if cell == null:
				continue
			if r != write:
				grid[c][write] = cell
				grid[c][r] = null
				cell["oy"] = float(cell["oy"]) - (write - r) * CELL
				moved_any = true
			write -= 1
	if moved_any:
		var guard := 0.0
		while _any_falling() and guard < 1.2:
			await get_tree().process_frame
			guard += get_process_delta_time()


func _any_falling() -> bool:
	for c in COLS:
		for r in ROWS:
			var cell = grid[c][r]
			if cell != null and cell["oy"] < 0.0:
				return true
	return false


## Finds and pops matches repeatedly until the board is stable.
func resolve_chains(from_gear: bool) -> int:
	var chain := 0
	var g := _gen
	while state != State.DEAD and g == _gen:
		var groups := find_matches()
		if groups.is_empty():
			break
		chain += 1
		var to_pop := {}
		var bonus := false
		var largest := 0
		for grp in groups:
			largest = maxi(largest, grp.size())
			for p in grp:
				to_pop[p] = true
			if grp.size() >= 4 and _has_square_or_line(grp):
				bonus = true
		await _pop_set(to_pop, chain, from_gear, bonus, largest)
		if g != _gen:
			return chain
		await settle()
	if chain > 0 and g == _gen:
		chain_finished.emit(chain)
	return chain


func find_matches() -> Array:
	var groups: Array = []
	var seen_groups := {}
	for color in num_colors_max():
		var visited := {}
		for c in COLS:
			for r in ROWS:
				var start := Vector2i(c, r)
				if visited.has(start):
					continue
				var cell = grid[c][r]
				if not _matches_color(cell, color):
					continue
				var group: Array = []
				var stack: Array = [start]
				visited[start] = true
				var has_real := false
				while not stack.is_empty():
					var p: Vector2i = stack.pop_back()
					group.append(p)
					if grid[p.x][p.y]["t"] != T.WILD:
						has_real = true
					for d in OFFSETS:
						var q: Vector2i = p + d
						if q.x < 0 or q.x >= COLS or q.y < 0 or q.y >= ROWS or visited.has(q):
							continue
						if _matches_color(grid[q.x][q.y], color):
							visited[q] = true
							stack.append(q)
				if group.size() >= 3 and (has_real or color == 0):
					group.sort()
					var key := str(group)
					if not seen_groups.has(key):
						seen_groups[key] = true
						groups.append(group)
	return groups


func num_colors_max() -> int:
	return 5


func _matches_color(cell, color: int) -> bool:
	if not matchable(cell):
		return false
	return cell["t"] == T.WILD or int(cell["c"]) == color


func _has_square_or_line(group: Array) -> bool:
	var s := {}
	for p in group:
		s[p] = true
	for p in group:
		if s.has(p + Vector2i(1, 0)) and s.has(p + Vector2i(0, 1)) and s.has(p + Vector2i(1, 1)):
			return true
		if s.has(p + Vector2i(1, 0)) and s.has(p + Vector2i(2, 0)) and s.has(p + Vector2i(3, 0)):
			return true
		if s.has(p + Vector2i(0, 1)) and s.has(p + Vector2i(0, 2)) and s.has(p + Vector2i(0, 3)):
			return true
	return false


## Pops a set of cells (Dictionary of Vector2i -> true) with full juice and
## reports everything that happened via `blocks_popped`.
func _pop_set(to_pop: Dictionary, chain: int, from_gear: bool, bonus: bool = false, largest: int = 0) -> void:
	# Bombs explode 3x3 (and can chain into other bombs).
	var bombs_done := {}
	var changed := true
	while changed:
		changed = false
		for p in to_pop.keys():
			var cell = grid[p.x][p.y]
			if cell != null and cell["t"] == T.BOMB and not bombs_done.has(p):
				bombs_done[p] = true
				for dx in [-1, 0, 1]:
					for dy in [-1, 0, 1]:
						var q := Vector2i(p.x + dx, p.y + dy)
						if cell_at(q.x, q.y) != null and not to_pop.has(q):
							to_pop[q] = true
							changed = true
	# Neighbouring garbage cracks apart; neighbouring ice thaws.
	var garbage_cleared := 0
	var thawed := 0
	for p in to_pop.keys():
		for d in OFFSETS:
			var q: Vector2i = p + d
			var n = cell_at(q.x, q.y)
			if n == null or to_pop.has(q):
				continue
			if n["t"] == T.GARBAGE:
				to_pop[q] = true
			elif int(n["ice"]) > 0:
				n["ice"] = 0
				thawed += 1
	var colors := [0, 0, 0, 0, 0]
	var res := {"wood": 0, "stone": 0, "gem": 0}
	var center := Vector2.ZERO
	var count := 0
	var pop_color := -1
	for p in to_pop.keys():
		var cell = grid[p.x][p.y]
		if cell == null:
			continue
		cell["pop"] = 0.0
		center += cell_global(p.x, p.y)
		match int(cell["t"]):
			T.GARBAGE:
				garbage_cleared += 1
				continue
			T.WOOD:
				res["wood"] += 1
			T.STONE:
				res["stone"] += 1
			T.GEM:
				res["gem"] += 1
		count += 1
		if int(cell["c"]) >= 0:
			colors[int(cell["c"])] += 1
			pop_color = int(cell["c"])
	var total := to_pop.size()
	if total == 0:
		return
	center /= float(total)
	AudioSynth.play("pop", 1.0 + chain * 0.06, -1.0)
	if not bombs_done.is_empty():
		AudioSynth.play("boom", 1.0, -1.0)
	# Swell + flash...
	var g := _gen
	await get_tree().create_timer(0.16, false).timeout
	if state == State.DEAD or g != _gen:
		return
	# ...then burst.
	for p in to_pop.keys():
		var cell = grid[p.x][p.y]
		if cell == null:
			continue
		var col := _cell_color(cell)
		_pops.append({"pos": cell_center(p.x, p.y), "color": col, "t": 0.0})
		UIKit.burst(self, cell_center(p.x, p.y), col, 10 if cell["t"] != T.BOMB else 30, 280.0 if not bonus else 420.0, 1.0 if not bonus else 1.4)
		grid[p.x][p.y] = null
	blocks_popped.emit({
		"count": count, "colors": colors, "chain": chain, "bonus": bonus, "largest": largest,
		"resources": res, "garbage": garbage_cleared, "thawed": thawed, "bombs": bombs_done.size(),
		"center": center, "from_gear": from_gear, "color": pop_color,
	})
	await get_tree().create_timer(0.06, false).timeout


func _cell_color(cell) -> Color:
	if cell == null:
		return Color.WHITE
	match int(cell["t"]):
		T.GARBAGE:
			return Color("9a8fa8")
		T.WILD:
			return Color.from_hsv(fmod(_time * 0.6, 1.0), 0.6, 1.0)
	return UIKit.BLOCK_COLORS[clampi(int(cell["c"]), 0, 4)]


func _update_danger() -> void:
	var d := max_height() >= ROWS - DANGER_ROWS
	if d != danger:
		danger = d
		danger_changed.emit(d)


# --- Queued effect operations --------------------------------------------

func queue_op(op: Callable) -> void:
	_ops.append(op)


func has_ops() -> bool:
	return not _ops.is_empty()


## Runs queued gear/card ops, settling and resolving cascades after each.
func process_ops() -> void:
	var guard := 0
	var g := _gen
	while not _ops.is_empty() and guard < 16 and state != State.DEAD and g == _gen:
		guard += 1
		var op: Callable = _ops.pop_front()
		var removed: Dictionary = op.call()
		if removed is Dictionary and not removed.is_empty():
			await _pop_set(removed, 1, true)
		await settle()
		await resolve_chains(true)
	_ops.clear()
	_update_danger()


## Runs queued ops while a piece is falling (e.g. Gear Burst ability).
func run_ops_now() -> void:
	if state != State.FALLING:
		return
	state = State.RESOLVING
	await process_ops()
	if state != State.DEAD:
		state = State.FALLING


func _cells_where(pred: Callable) -> Array:
	var out: Array = []
	for c in COLS:
		for r in ROWS:
			var cell = grid[c][r]
			if cell != null and cell["pop"] < 0.0 and pred.call(cell, c, r):
				out.append(Vector2i(c, r))
	return out


func _pick(list: Array, n: int) -> Dictionary:
	list.shuffle()
	var out := {}
	for i in mini(n, list.size()):
		out[list[i]] = true
	return out


func op_zap_bottom(n: int) -> Dictionary:
	AudioSynth.play("zap")
	return _pick(_cells_where(func(_cell, _c, r): return r == ROWS - 1), n)


func op_crush_garbage(n: int) -> Dictionary:
	return _pick(_cells_where(func(cell, _c, _r): return cell["t"] == T.GARBAGE), n)


func op_twin_pop(color: int, n: int) -> Dictionary:
	var list := _cells_where(func(cell, _c, _r): return int(cell["c"]) == color and cell["t"] != T.GARBAGE)
	if list.is_empty():
		list = _cells_where(func(cell, _c, _r): return cell["t"] != T.GARBAGE)
	return _pick(list, n)


func op_clear_edge(n: int) -> Dictionary:
	var out := {}
	for i in n:
		var best := -1
		var best_h := 0
		for c in [0, COLS - 1]:
			var h := column_height(c)
			for p in out.keys():
				if p.x == c:
					h -= 1
			if h > best_h:
				best_h = h
				best = c
		if best == -1:
			break
		for r in ROWS:
			var p := Vector2i(best, r)
			if grid[best][r] != null and not out.has(p):
				out[p] = true
				break
	return out


func op_heal_overflow(n: int) -> Dictionary:
	var list := _cells_where(func(_cell, _c, _r): return true)
	list.sort_custom(func(a, b): return a.y < b.y)
	var out := {}
	for i in mini(n, list.size()):
		out[list[i]] = true
	return out


func op_clear_rows(from_row: int, to_row: int) -> Dictionary:
	return _pick(_cells_where(func(_cell, _c, r): return r >= from_row and r <= to_row), 999)


func op_clear_all_garbage() -> Dictionary:
	return _pick(_cells_where(func(cell, _c, _r): return cell["t"] == T.GARBAGE), 999)


## Converts n random blocks into the most common colour (no pop).
func op_convert(n: int) -> Dictionary:
	var counts := [0, 0, 0, 0, 0]
	for c in COLS:
		for r in ROWS:
			var cell = grid[c][r]
			if cell != null and cell["t"] != T.GARBAGE and int(cell["c"]) >= 0:
				counts[int(cell["c"])] += 1
	var best := 0
	for i in 5:
		if counts[i] > counts[best]:
			best = i
	var list := _cells_where(func(cell, _c, _r): return cell["t"] in [T.NORMAL, T.WOOD, T.STONE, T.GEM] and int(cell["c"]) != best)
	list.shuffle()
	for i in mini(n, list.size()):
		var p: Vector2i = list[i]
		grid[p.x][p.y]["c"] = best
		grid[p.x][p.y]["sq"] = -1.0
		UIKit.burst(self, cell_center(p.x, p.y), UIKit.BLOCK_COLORS[best], 12, 200.0)
	AudioSynth.play("card", 1.2, -4.0)
	return {}


## Turns n random normal blocks into a special type (Bomb / Shield).
func op_make_special(t: int, n: int) -> Dictionary:
	var list := _cells_where(func(cell, _c, _r): return cell["t"] == T.NORMAL)
	list.shuffle()
	for i in mini(n, list.size()):
		var p: Vector2i = list[i]
		grid[p.x][p.y]["t"] = t
		grid[p.x][p.y]["sq"] = -1.0
		UIKit.burst(self, cell_center(p.x, p.y), Color.WHITE, 14, 220.0)
	AudioSynth.play("shield" if t == T.SHIELD else "level_up", 1.0, -4.0)
	return {}


# --- Boss attacks ---------------------------------------------------------

## Drops `n` garbage blocks. Shields on the board absorb one each first.
## Returns the number that actually landed.
func drop_garbage(n: int) -> int:
	var shields := _cells_where(func(cell, _c, _r): return cell["t"] == T.SHIELD)
	shields.shuffle()
	var absorbed := 0
	while n > 0 and absorbed < shields.size():
		var p: Vector2i = shields[absorbed]
		grid[p.x][p.y]["t"] = T.NORMAL
		grid[p.x][p.y]["sq"] = -1.0
		UIKit.burst(self, cell_center(p.x, p.y), Color("bff6ff"), 20, 300.0)
		absorbed += 1
		n -= 1
	if absorbed > 0:
		AudioSynth.play("shield")
	var cols: Array = []
	for c in COLS:
		cols.append(c)
	cols.shuffle()
	var landed := 0
	var i := 0
	while n > 0 and i < COLS * 3:
		var c: int = cols[i % COLS]
		i += 1
		var top := -1
		for r in range(ROWS - 1, -1, -1):
			if grid[c][r] == null:
				top = r
				break
		if top < 0:
			continue
		var g := make_cell(T.GARBAGE, -1)
		g["oy"] = -(top + 2 + landed % 3) * CELL
		grid[c][top] = g
		landed += 1
		n -= 1
	if landed > 0:
		var guard := 0.0
		while _any_falling() and guard < 1.5:
			await get_tree().process_frame
			guard += get_process_delta_time()
		AudioSynth.play("thud", 0.8, -2.0)
	_update_danger()
	return landed


## Pushes a garbage row (with one gap) up from the bottom. Returns true if
## blocks were pushed off the top (instant knockout).
func push_junk_row() -> bool:
	var overflow := false
	for c in COLS:
		if grid[c][0] != null:
			overflow = true
	for c in COLS:
		for r in range(0, ROWS - 1):
			grid[c][r] = grid[c][r + 1]
		grid[c][ROWS - 1] = null
	var gap := _rng.randi_range(0, COLS - 1)
	for c in COLS:
		if c != gap:
			var g := make_cell(T.GARBAGE, -1)
			g["sq"] = 1.0
			grid[c][ROWS - 1] = g
	AudioSynth.play("rumble")
	await settle()
	_update_danger()
	if overflow:
		state = State.DEAD
		topped_out.emit()
	return overflow


## Encases the tallest column in ice for `drops` drops.
func freeze_column(drops: int) -> int:
	var best := 0
	for c in COLS:
		if column_height(c) > column_height(best):
			best = c
	for r in ROWS:
		var cell = grid[best][r]
		if cell != null and cell["t"] != T.GARBAGE:
			cell["ice"] = drops
	AudioSynth.play("freeze")
	return best


func tick_ice() -> void:
	for c in COLS:
		for r in ROWS:
			var cell = grid[c][r]
			if cell != null and int(cell["ice"]) > 0:
				cell["ice"] = int(cell["ice"]) - 1


func scramble_colors(n: int) -> void:
	var list := _cells_where(func(cell, _c, _r): return cell["t"] == T.NORMAL)
	list.shuffle()
	for i in mini(n, list.size()):
		var p: Vector2i = list[i]
		grid[p.x][p.y]["c"] = _rng.randi_range(0, num_colors - 1)
		grid[p.x][p.y]["sq"] = -1.0
	AudioSynth.play("boing", 1.3)


# --- Touch gestures -------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state != State.FALLING or not input_enabled:
		return
	if event is InputEventScreenTouch:
		var local := _to_local_screen(event.position)
		var inside := Rect2(Vector2(-20, -CELL * 2), Vector2(COLS * CELL + 40, (ROWS + 2) * CELL)).has_point(local)
		if event.pressed and inside and _touch_index == -1:
			_touch_index = event.index
			_touch_start = local
			_touch_last = local
			_touch_time = 0.0
			_touch_dragged = false
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			_touch_soft = false
			if not _touch_dragged:
				# Tap a column: slide the piece there.
				move_to_column(int(floor(local.x / CELL)))
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		var local := _to_local_screen(event.position)
		var dx := local.x - _touch_last.x
		if absf(dx) >= CELL * 0.75:
			try_move(signi(int(dx)))
			_touch_last.x = local.x
			_touch_dragged = true
		var dy := local.y - _touch_start.y
		if event.velocity.y > 1600.0 and dy > CELL:
			_touch_index = -1
			_touch_soft = false
			hard_drop()
		elif dy > CELL * 1.2:
			_touch_soft = true
			_touch_dragged = true
		get_viewport().set_input_as_handled()


func _to_local_screen(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


# --- Drawing --------------------------------------------------------------

## Returns a cached StyleBoxFlat for this shape, recoloured for this draw.
## (StyleBoxFlat bakes its colours into the canvas commands at draw time, so
## one instance per shape can be safely reused with different colours.)
func _style(key: String, fill: Color, radius: int, border: int, border_col: Color = INK) -> StyleBoxFlat:
	var k := "%s_%d_%d" % [key, radius, border]
	var sb: StyleBoxFlat = _styles.get(k)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.set_corner_radius_all(radius)
		sb.set_border_width_all(border)
		sb.anti_aliasing = true
		_styles[k] = sb
	sb.bg_color = fill
	sb.border_color = border_col
	return sb


func _draw() -> void:
	var w := COLS * CELL
	var h := ROWS * CELL
	# Board frame + well.
	draw_style_box(_style("frame", Color("2a1747"), 26, 6), Rect2(-14, -14, w + 28, h + 28))
	draw_style_box(_style("well", Color("1d1036"), 16, 0), Rect2(-4, -4, w + 8, h + 8))
	for c in COLS:
		for r in ROWS:
			if (c + r) % 2 == 0:
				draw_rect(Rect2(c * CELL, r * CELL, CELL, CELL), Color(1, 1, 1, 0.025))
	# Danger line.
	var dy := DANGER_ROWS * CELL
	var dcol := Color(1, 0.25, 0.35, 0.55 + 0.35 * sin(_time * 8.0)) if danger else Color(1, 1, 1, 0.12)
	var x := 0.0
	while x < w:
		draw_line(Vector2(x, dy), Vector2(minf(x + 14, w), dy), dcol, 3.0)
		x += 24.0
	# Hard-drop trails.
	for t in _trails:
		var top := cell_center(t["c"], t["from"])
		var bot := cell_center(t["c"], t["to"])
		draw_rect(Rect2(top.x - CELL * 0.4, top.y, CELL * 0.8, bot.y - top.y), Color(1, 1, 1, 0.25 * t["life"]))
	# Settled blocks.
	for c in COLS:
		for r in ROWS:
			var cell = grid[c][r]
			if cell != null:
				_draw_block(cell_center(c, r) + Vector2(0, cell["oy"]), cell, 1.0)
	# Ghost + active piece.
	if state == State.FALLING and not piece.is_empty():
		_draw_ghost()
		var off := Vector2(cos(_piece_rot_vis - PI * 0.5), sin(_piece_rot_vis - PI * 0.5)) * CELL
		_draw_block(_piece_vis, piece["a"], 1.0)
		_draw_block(_piece_vis + off, piece["b"], 1.0)
	# Pop flashes.
	for p in _pops:
		var k: float = p["t"]
		draw_arc(p["pos"], CELL * (0.3 + k * 0.7), 0, TAU, 24, Color(1, 1, 1, 1.0 - k), 6.0 * (1.0 - k) + 1.0, true)
	_draw_next(Vector2(w + 26, 0))


func _draw_ghost() -> void:
	var col: int = piece["col"]
	var row: int = piece["row"]
	var rot: int = piece["rot"]
	var cells := _piece_cells(col, row, rot)
	var land: Array = []
	if rot == 0 or rot == 2:
		var r := row
		while _fits(col, r + 1, rot):
			r += 1
		land = _piece_cells(col, r, rot)
	else:
		for p in cells:
			var rr: int = p.y
			while is_free(p.x, rr + 1):
				rr += 1
			land.append(Vector2i(p.x, rr))
	var datas := [piece["a"], piece["b"]]
	for i in 2:
		var p: Vector2i = land[i]
		var colr := _cell_color(datas[i])
		var rect := Rect2(p.x * CELL + 5, p.y * CELL + 5, CELL - 10, CELL - 10)
		draw_style_box(_style("ghost", Color(colr.r, colr.g, colr.b, 0.22), 12, 3, Color(colr.r, colr.g, colr.b, 0.75)), rect)


func _draw_block(center: Vector2, cell: Dictionary, alpha: float) -> void:
	var t := int(cell["t"])
	var sq: float = cell["sq"]
	var pop: float = cell["pop"]
	var s := CELL - 4.0
	var sx := s * (1.0 + 0.16 * sq)
	var sy := s * (1.0 - 0.16 * sq)
	if pop >= 0.0:
		sx *= 1.0 + 0.3 * pop
		sy *= 1.0 + 0.3 * pop
	var rect := Rect2(center.x - sx * 0.5, center.y + s * 0.5 - sy, sx, sy)
	var base := _cell_color(cell)
	if pop >= 0.0:
		base = base.lerp(Color.WHITE, pop)
	var radius := 13
	# Body, bottom shade and glossy top highlight.
	draw_style_box(_style("blk", base, radius, 4), rect)
	if t != T.GARBAGE:
		draw_style_box(_style("shade", base.darkened(0.18), radius - 4, 0), Rect2(rect.position.x + 4, rect.position.y + rect.size.y * 0.58, rect.size.x - 8, rect.size.y * 0.42 - 4))
		draw_style_box(_style("gloss", Color(1, 1, 1, 0.42), 8, 0), Rect2(rect.position.x + 7, rect.position.y + 5, rect.size.x - 14, rect.size.y * 0.26))
	var c := rect.get_center()
	match t:
		T.GARBAGE:
			draw_polyline(PackedVector2Array([c + Vector2(-14, -12), c + Vector2(-3, -2), c + Vector2(-9, 6), c + Vector2(4, 14)]), INK, 3.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(12, -14), c + Vector2(5, -4), c + Vector2(14, 4)]), INK, 3.0, true)
			for v in [Vector2(-14, 14), Vector2(14, -14), Vector2(14, 14), Vector2(-14, -14)]:
				draw_circle(c + v * 0.85, 2.5, Color(0, 0, 0, 0.35))
		T.WILD:
			_draw_star(c, 14.0, Color.WHITE)
		T.BOMB:
			draw_circle(c + Vector2(0, 3), 12, INK)
			draw_circle(c + Vector2(-4, -1), 3.5, Color(1, 1, 1, 0.6))
			draw_line(c + Vector2(6, -7), c + Vector2(11, -14), Color("ffd23f"), 3.0)
			draw_circle(c + Vector2(12, -15), 3.0 + sin(_time * 20.0) * 1.5, Color("ff9f1c"))
		T.SHIELD:
			var sh := PackedVector2Array([c + Vector2(-11, -12), c + Vector2(11, -12), c + Vector2(11, 0), c + Vector2(0, 13), c + Vector2(-11, 0)])
			draw_colored_polygon(sh, Color(1, 1, 1, 0.9))
			sh.append(sh[0])
			draw_polyline(sh, INK, 3.0, true)
		T.WOOD:
			draw_style_box(_style("log", Color("a0642d"), 6, 3), Rect2(c.x - 13, c.y - 6, 26, 13))
			draw_circle(c + Vector2(9, 0), 4, Color("e5b47a"))
		T.STONE:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-12, 6), c + Vector2(-8, -7), c + Vector2(4, -10), c + Vector2(12, -2), c + Vector2(9, 9), c + Vector2(-6, 10)]), Color("8d8fa3"))
			draw_polyline(PackedVector2Array([c + Vector2(-12, 6), c + Vector2(-8, -7), c + Vector2(4, -10), c + Vector2(12, -2), c + Vector2(9, 9), c + Vector2(-6, 10), c + Vector2(-12, 6)]), INK, 2.5, true)
		T.GEM:
			var gem := PackedVector2Array([c + Vector2(0, -12), c + Vector2(11, -2), c + Vector2(0, 12), c + Vector2(-11, -2)])
			draw_colored_polygon(gem, Color("7af0ff"))
			gem.append(gem[0])
			draw_polyline(gem, INK, 2.5, true)
			draw_circle(c + Vector2(-3, -4), 2.5, Color.WHITE)
		_:
			# Cute candy eyes.
			var blink: bool = cell["blink"] < 0.0
			var look := Vector2(0, 1.5) if danger else Vector2(0.0, 0.0)
			for ex in [-7.0, 7.0]:
				var e := c + Vector2(ex, 1)
				if blink:
					draw_line(e + Vector2(-4, 0), e + Vector2(4, 0), INK, 2.5)
				else:
					draw_circle(e, 5.0, Color.WHITE)
					draw_circle(e + look + Vector2(0, 1), 2.6, INK)
	if int(cell["ice"]) > 0:
		draw_style_box(_style("ice", Color(0.75, 0.95, 1.0, 0.55), radius, 3, Color("e8fbff")), rect.grow(1))
		draw_line(rect.position + Vector2(8, 10), rect.position + Vector2(18, 4), Color(1, 1, 1, 0.9), 3.0)


func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + PI * i / 5.0 + _time * 1.5
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, INK, 2.5, true)


func _draw_next(origin: Vector2) -> void:
	var box := Rect2(origin, Vector2(84, 132))
	draw_style_box(_style("nextbox", Color("2a1747"), 18, 5), box)
	var font := UIKit.font_bold
	draw_string_outline(font, origin + Vector2(10, 26), "NEXT", HORIZONTAL_ALIGNMENT_CENTER, 64, 20, 6, INK)
	draw_string(font, origin + Vector2(10, 26), "NEXT", HORIZONTAL_ALIGNMENT_CENTER, 64, 20, Color("ffd23f"))
	if next_pieces.is_empty():
		return
	var n: Dictionary = next_pieces[0]
	var mid := origin + Vector2(42, 84)
	var bob := sin(_time * 3.0) * 3.0
	_draw_block(mid + Vector2(0, 22 + bob), n["a"], 1.0)
	_draw_block(mid + Vector2(0, -26 + bob), n["b"], 1.0)
