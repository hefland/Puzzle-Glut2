extends Node
## FaceManager — the persistent face gallery.
##
## * 4 built-in goofy cartoon faces are drawn procedurally at startup so the
##   game is playable before any photo is uploaded.
## * Uploaded photos are cropped to an oval, scaled to 256x256 and saved as
##   PNG files in user://faces/ with metadata in user://faces/faces_meta.json.
## * Every face has a role: "hero" (Me), "boss" (Rival Boss) or "both".

signal faces_changed

const FACE_DIR := "user://faces"
const META_PATH := "user://faces/faces_meta.json"
const FACE_SIZE := 256
const OVAL_X := 0.88   # must match face_avatar.gdshader defaults
const OVAL_Y := 1.0
const ROLES := ["hero", "boss", "both"]
const ROLE_LABELS := {"hero": "Hero (Me)", "boss": "Rival Boss", "both": "Both"}

const BUILTIN := [
	{"id": "builtin_0", "name": "Blobby Bob", "role": "hero"},
	{"id": "builtin_1", "name": "Pickle Pete", "role": "both"},
	{"id": "builtin_2", "name": "Cap'n Whiskers", "role": "both"},
	{"id": "builtin_3", "name": "Grumpy Moon", "role": "boss"},
]

var _meta: Dictionary = {"faces": [], "builtin_roles": {}}
var _cache: Dictionary = {}   # id -> Texture2D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(FACE_DIR)
	_load_meta()
	for i in BUILTIN.size():
		_cache[BUILTIN[i]["id"]] = ImageTexture.create_from_image(_draw_builtin(i))


# --- Queries --------------------------------------------------------------

## All faces (built-in first). Each entry: {id, name, role, builtin}.
func get_faces() -> Array:
	var out: Array = []
	for b in BUILTIN:
		var role := str(_meta["builtin_roles"].get(b["id"], b["role"]))
		out.append({"id": b["id"], "name": b["name"], "role": role, "builtin": true})
	for f in _meta["faces"]:
		out.append({"id": str(f["id"]), "name": str(f.get("name", "Face")), "role": str(f.get("role", "both")), "builtin": false})
	return out


func get_face(id: String) -> Dictionary:
	for f in get_faces():
		if f["id"] == id:
			return f
	return {}


func get_texture(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	for f in _meta["faces"]:
		if str(f["id"]) == id:
			var img := Image.load_from_file(FACE_DIR + "/" + str(f["file"]))
			if img:
				var tex := ImageTexture.create_from_image(img)
				_cache[id] = tex
				return tex
	return _cache["builtin_0"]


func hero_face_id() -> String:
	var id := str(SaveManager.data.get("hero_face", "builtin_0"))
	if get_face(id).is_empty():
		id = "builtin_0"
	return id


func set_hero(id: String) -> void:
	SaveManager.data["hero_face"] = id
	SaveManager.save_game()
	faces_changed.emit()


## Picks a random rival face (role boss/both), avoiding the hero when possible.
func random_boss_face(rng: RandomNumberGenerator = null) -> String:
	var hero := hero_face_id()
	var pool: Array = []
	for f in get_faces():
		if (f["role"] == "boss" or f["role"] == "both") and f["id"] != hero:
			pool.append(f["id"])
	if pool.is_empty():
		for f in get_faces():
			if f["id"] != hero:
				pool.append(f["id"])
	if pool.is_empty():
		return "builtin_3"
	var idx := rng.randi_range(0, pool.size() - 1) if rng else randi() % pool.size()
	return str(pool[idx])


# --- Editing --------------------------------------------------------------

func set_role(id: String, role: String) -> void:
	if not ROLES.has(role):
		return
	if id.begins_with("builtin_"):
		_meta["builtin_roles"][id] = role
	else:
		for f in _meta["faces"]:
			if str(f["id"]) == id:
				f["role"] = role
	_save_meta()
	faces_changed.emit()


func next_role(role: String) -> String:
	var i := ROLES.find(role)
	return ROLES[(i + 1) % ROLES.size()]


func delete_face(id: String) -> void:
	if id.begins_with("builtin_"):
		return
	for i in range(_meta["faces"].size() - 1, -1, -1):
		var f: Dictionary = _meta["faces"][i]
		if str(f["id"]) == id:
			DirAccess.remove_absolute(FACE_DIR + "/" + str(f["file"]))
			_meta["faces"].remove_at(i)
	_cache.erase(id)
	if str(SaveManager.data.get("hero_face", "")) == id:
		SaveManager.data["hero_face"] = "builtin_0"
		SaveManager.save_game()
	_save_meta()
	faces_changed.emit()


# --- Import pipeline ------------------------------------------------------

## Loads a photo from disk (or an Android content URI) regardless of its
## extension by sniffing the file header. Returns null on failure.
func load_source_image(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		var img_direct := Image.load_from_file(path)
		return img_direct
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes.size() > 12:
		if bytes[0] == 0x89 and bytes[1] == 0x50:
			err = img.load_png_from_buffer(bytes)
		elif bytes[0] == 0xFF and bytes[1] == 0xD8:
			err = img.load_jpg_from_buffer(bytes)
		elif bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[8] == 0x57 and bytes[9] == 0x45:
			err = img.load_webp_from_buffer(bytes)
	if err != OK:
		# Last resort: try every decoder.
		for loader in [img.load_png_from_buffer, img.load_jpg_from_buffer, img.load_webp_from_buffer]:
			if loader.call(bytes) == OK:
				err = OK
				break
	if err != OK or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	# Keep huge phone photos manageable.
	var longest := maxi(img.get_width(), img.get_height())
	if longest > 1400:
		var s := 1400.0 / longest
		img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_BILINEAR)
	return img


## Crops a square region around (offset_x, offset_y) in -1..1 with the given
## zoom (1 = largest square that fits) and returns a 256x256 oval avatar.
func crop_face(src: Image, zoom: float, offset_x: float, offset_y: float, bake_mask: bool = true) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var side := int(mini(w, h) / maxf(zoom, 1.0))
	side = maxi(side, 8)
	var cx := w * 0.5 + offset_x * (w - side) * 0.5
	var cy := h * 0.5 + offset_y * (h - side) * 0.5
	var x0 := clampi(int(cx - side * 0.5), 0, w - side)
	var y0 := clampi(int(cy - side * 0.5), 0, h - side)
	var out := src.get_region(Rect2i(x0, y0, side, side))
	out.resize(FACE_SIZE, FACE_SIZE, Image.INTERPOLATE_CUBIC)
	out.convert(Image.FORMAT_RGBA8)
	if bake_mask:
		var c := FACE_SIZE * 0.5
		for y in FACE_SIZE:
			for x in FACE_SIZE:
				var dx := (x + 0.5 - c) / (c * OVAL_X)
				var dy := (y + 0.5 - c) / (c * OVAL_Y)
				var r := sqrt(dx * dx + dy * dy)
				if r > 0.97:
					var px := out.get_pixel(x, y)
					px.a = clampf((1.02 - r) / 0.05, 0.0, 1.0)
					out.set_pixel(x, y, px)
	return out


## Saves a cropped avatar into the gallery. Returns the new face id.
func add_face(avatar: Image, role: String, display_name: String = "") -> String:
	var id := "face_%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	var file := id + ".png"
	var err := avatar.save_png(FACE_DIR + "/" + file)
	if err != OK:
		push_warning("Could not save face: %s" % error_string(err))
		return ""
	if display_name.strip_edges() == "":
		display_name = "Face #%d" % (_meta["faces"].size() + 1)
	_meta["faces"].append({"id": id, "name": display_name, "role": role if ROLES.has(role) else "both", "file": file})
	_cache[id] = ImageTexture.create_from_image(avatar)
	_save_meta()
	faces_changed.emit()
	return id


func rename_face(id: String, display_name: String) -> void:
	for f in _meta["faces"]:
		if str(f["id"]) == id:
			f["name"] = display_name
	_save_meta()
	faces_changed.emit()


## A ShaderMaterial for showing a face with the cartoon rim-light oval.
func make_face_material(rim: Color = Color(1.0, 0.86, 0.45)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/face_avatar.gdshader")
	m.set_shader_parameter("rim_color", rim)
	return m


# --- Persistence ----------------------------------------------------------

func _load_meta() -> void:
	if not FileAccess.file_exists(META_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	if parsed is Dictionary:
		if parsed.get("faces") is Array:
			var clean: Array = []
			for f in parsed["faces"]:
				if f is Dictionary and f.has("id") and f.has("file") and FileAccess.file_exists(FACE_DIR + "/" + str(f["file"])):
					clean.append(f)
			_meta["faces"] = clean
		if parsed.get("builtin_roles") is Dictionary:
			_meta["builtin_roles"] = parsed["builtin_roles"]


func _save_meta() -> void:
	var f := FileAccess.open(META_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_meta, "\t"))
		f.close()


# --- Procedural cartoon faces ---------------------------------------------

func _draw_builtin(index: int) -> Image:
	var s := FACE_SIZE
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var ink := Color("1b0f2e")
	match index:
		0:  # Blobby Bob — sunny orange, huge grin, freckles
			img.fill(Color("ffb070"))
			_ellipse(img, Vector2(128, 210), Vector2(150, 60), Color("ff9a5a"))
			_ellipse(img, Vector2(64, 150), Vector2(22, 14), Color("ff7a7a", 0.55))
			_ellipse(img, Vector2(192, 150), Vector2(22, 14), Color("ff7a7a", 0.55))
			_eye(img, Vector2(90, 108), 26, Vector2(4, 4))
			_eye(img, Vector2(166, 108), 26, Vector2(-2, 4))
			_arc(img, Vector2(128, 140), 52, 0.15 * PI, 0.85 * PI, 9, ink)
			_ellipse(img, Vector2(128, 182), Vector2(30, 14), Color("e8455f"))
			for p in [Vector2(70, 132), Vector2(80, 140), Vector2(60, 140), Vector2(186, 132), Vector2(176, 140), Vector2(196, 140)]:
				_ellipse(img, p, Vector2(3, 3), Color("c0602a"))
			_line(img, Vector2(66, 72), Vector2(110, 66), 7, ink)
			_line(img, Vector2(146, 66), Vector2(190, 72), 7, ink)
		1:  # Pickle Pete — green, unibrow, buck teeth
			img.fill(Color("8fdc5a"))
			for i in 9:
				_ellipse(img, Vector2(30 + i * 26, 40 + (i % 3) * 70), Vector2(6, 9), Color("6cbf3c"))
			_eye(img, Vector2(94, 112), 22, Vector2(6, -2))
			_eye(img, Vector2(162, 112), 30, Vector2(-6, 2))
			_line(img, Vector2(64, 80), Vector2(128, 90), 10, ink)
			_line(img, Vector2(128, 90), Vector2(196, 74), 10, ink)
			_arc(img, Vector2(128, 150), 40, 0.2 * PI, 0.8 * PI, 8, ink)
			_rect(img, Rect2(114, 182, 13, 18), Color.WHITE)
			_rect(img, Rect2(129, 182, 13, 18), Color.WHITE)
		2:  # Cap'n Whiskers — cat face
			img.fill(Color("d9d4e8"))
			_ellipse(img, Vector2(128, 176), Vector2(64, 46), Color("fffaf0"))
			_cat_eye(img, Vector2(88, 108))
			_cat_eye(img, Vector2(168, 108))
			_tri(img, Vector2(116, 150), Vector2(140, 150), Vector2(128, 164), Color("ff7aa8"))
			_arc(img, Vector2(116, 166), 12, 0.0, PI, 5, ink)
			_arc(img, Vector2(140, 166), 12, 0.0, PI, 5, ink)
			for dy in [-8, 6, 20]:
				_line(img, Vector2(80, 158 + dy * 0.3), Vector2(26, 150 + dy), 3, ink)
				_line(img, Vector2(176, 158 + dy * 0.3), Vector2(230, 150 + dy), 3, ink)
			_ellipse(img, Vector2(52, 36), Vector2(30, 30), Color("b9b2d0"))
			_ellipse(img, Vector2(204, 36), Vector2(30, 30), Color("b9b2d0"))
		_:  # Grumpy Moon — purple-blue, angry brows, frown, craters
			img.fill(Color("8f8cf0"))
			_ellipse(img, Vector2(60, 60), Vector2(18, 14), Color("7a77d8"))
			_ellipse(img, Vector2(196, 190), Vector2(22, 16), Color("7a77d8"))
			_ellipse(img, Vector2(210, 70), Vector2(10, 8), Color("7a77d8"))
			_eye(img, Vector2(92, 118), 22, Vector2(3, 6))
			_eye(img, Vector2(164, 118), 22, Vector2(-3, 6))
			_line(img, Vector2(60, 82), Vector2(116, 102), 11, ink)
			_line(img, Vector2(140, 102), Vector2(196, 82), 11, ink)
			_arc(img, Vector2(128, 206), 40, 1.2 * PI, 1.8 * PI, 9, ink)
			_ellipse(img, Vector2(196, 150), Vector2(6, 9), Color("5ad1ff"))
	return img


func _eye(img: Image, c: Vector2, r: float, look: Vector2) -> void:
	var ink := Color("1b0f2e")
	_ellipse(img, c, Vector2(r + 4, r * 1.1 + 4), ink)
	_ellipse(img, c, Vector2(r, r * 1.1), Color.WHITE)
	_ellipse(img, c + look + Vector2(0, 2), Vector2(r * 0.5, r * 0.55), ink)
	_ellipse(img, c + look + Vector2(-r * 0.18, -r * 0.2), Vector2(r * 0.16, r * 0.16), Color.WHITE)


func _cat_eye(img: Image, c: Vector2) -> void:
	var ink := Color("1b0f2e")
	_ellipse(img, c, Vector2(26, 22), ink)
	_ellipse(img, c, Vector2(22, 18), Color("ffd23f"))
	_ellipse(img, c, Vector2(5, 16), ink)
	_ellipse(img, c + Vector2(-8, -7), Vector2(4, 4), Color.WHITE)


func _blend(img: Image, x: int, y: int, col: Color, cov: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height() or cov <= 0.0:
		return
	var a := clampf(cov, 0.0, 1.0) * col.a
	var dst := img.get_pixel(x, y)
	img.set_pixel(x, y, Color(lerpf(dst.r, col.r, a), lerpf(dst.g, col.g, a), lerpf(dst.b, col.b, a), maxf(dst.a, a)))


func _ellipse(img: Image, c: Vector2, r: Vector2, col: Color) -> void:
	for y in range(int(c.y - r.y - 2), int(c.y + r.y + 3)):
		for x in range(int(c.x - r.x - 2), int(c.x + r.x + 3)):
			var dx := (x + 0.5 - c.x) / r.x
			var dy := (y + 0.5 - c.y) / r.y
			var d := sqrt(dx * dx + dy * dy)
			var edge := (1.0 - d) * minf(r.x, r.y)
			_blend(img, x, y, col, edge + 0.5)


func _line(img: Image, a: Vector2, b: Vector2, width: float, col: Color) -> void:
	var hw := width * 0.5
	var minp := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(hw + 2, hw + 2)
	var maxp := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(hw + 2, hw + 2)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	for y in range(int(minp.y), int(maxp.y) + 1):
		for x in range(int(minp.x), int(maxp.x) + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			_blend(img, x, y, col, hw - d + 0.5)


func _arc(img: Image, c: Vector2, r: float, a0: float, a1: float, width: float, col: Color) -> void:
	var steps := 18
	var prev := c + Vector2(cos(a0), sin(a0)) * r
	for i in range(1, steps + 1):
		var a := lerpf(a0, a1, float(i) / steps)
		var p := c + Vector2(cos(a), sin(a)) * r
		_line(img, prev, p, width, col)
		prev = p


func _rect(img: Image, r: Rect2, col: Color) -> void:
	var ink := Color("1b0f2e")
	for y in range(int(r.position.y) - 2, int(r.end.y) + 2):
		for x in range(int(r.position.x) - 2, int(r.end.x) + 2):
			var inside := x >= r.position.x and x < r.end.x and y >= r.position.y and y < r.end.y
			_blend(img, x, y, col if inside else ink, 1.0)


func _tri(img: Image, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	var minp := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)))
	var maxp := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)))
	var poly := PackedVector2Array([a, b, c])
	for y in range(int(minp.y), int(maxp.y) + 1):
		for x in range(int(minp.x), int(maxp.x) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
				_blend(img, x, y, col, 1.0)
