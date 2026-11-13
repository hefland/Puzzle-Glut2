extends RefCounted
## ProceduralGearArt — builds every gear item as layered Polygon2D + Line2D
## vector art. 10 silhouettes per slot x 5 colour/material palettes, plus
## animated sparkles for Lv.4+ / Legendary gear and a glow aura at Lv.5.
##
## Coordinates (for a head about 120 px wide):
##   HEAD: origin = top of the head; art sits on/above y = 0.
##   FACE: origin = between the eyes (eyes at x = +-24).
##   HAND: origin = the palm; props extend upward.

const SparkleScript := preload("res://scripts/GearSparkle.gd")
const INK := Color("1b0f2e")
const OUTLINE_W := 4.0


## Returns a Node2D with the item's art. `level` drives sparkles / glow.
static func build(item: Dictionary, level: int = 1) -> Node2D:
	var root := Node2D.new()
	root.name = "GearArt"
	if item.is_empty():
		return root
	var pal: Array = GearDatabase.PALETTES[int(item["palette"])]
	var main: Color = pal[0]
	var sec: Color = pal[1]
	var acc: Color = pal[2]
	var rarity := int(item["rarity"])
	if level >= 5:
		var aura := Polygon2D.new()
		aura.polygon = ellipse(Vector2(0, -20 if item["slot"] != 1 else 0), Vector2(78, 62), 28)
		aura.color = Color(acc.r, acc.g, acc.b, 0.28)
		root.add_child(aura)
	match int(item["slot"]):
		0:
			_head(root, int(item["silhouette"]), main, sec, acc)
		1:
			_face(root, int(item["silhouette"]), main, sec, acc)
		_:
			_hand(root, int(item["silhouette"]), main, sec, acc)
	if level >= 4 or rarity == 3:
		var sp: Node2D = SparkleScript.new()
		sp.radius = 56.0
		sp.center = Vector2(0, -30) if item["slot"] != 1 else Vector2.ZERO
		sp.tint = acc.lerp(Color.WHITE, 0.4)
		sp.count = 4 + level
		root.add_child(sp)
	return root


## A square Control showing the item's art centred inside it (for slots,
## cards and the locker grid). `locked` draws a dark mystery silhouette.
static func build_icon(item_id: int, level: int, size: float, locked: bool = false) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var item := GearDatabase.get_item(item_id)
	if item.is_empty():
		return holder
	var art := build(item, 1 if locked else level)
	var k := size / 140.0
	art.scale = Vector2(k, k)
	var y_off: float = [0.39, -0.06, 0.38][int(item["slot"])]
	art.position = Vector2(size * 0.5, size * (0.5 + y_off))
	if locked:
		art.modulate = Color(0.05, 0.02, 0.12, 0.75)
		for c in art.get_children():
			if c.get_script() == SparkleScript:
				c.queue_free()
	holder.add_child(art)
	return holder


# --- Shape helpers --------------------------------------------------------

static func ellipse(c: Vector2, r: Vector2, n: int = 24, a0: float = 0.0, a1: float = TAU) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var full := is_equal_approx(a1 - a0, TAU)
	var steps := n if full else n + 1
	for i in steps:
		var a := a0 + (a1 - a0) * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts


static func rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


static func rrect(x: float, y: float, w: float, h: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	r = minf(r, minf(w, h) * 0.5)
	var corners := [Vector2(x + w - r, y + r), Vector2(x + w - r, y + h - r), Vector2(x + r, y + h - r), Vector2(x + r, y + r)]
	var starts := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for i in 4:
		for s in 5:
			var a: float = starts[i] + (PI * 0.5) * s / 4.0
			pts.append(corners[i] + Vector2(cos(a), sin(a)) * r)
	return pts


static func star(c: Vector2, ro: float, ri: float, n: int = 5, rot: float = -PI * 0.5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n * 2:
		var a := rot + PI * i / n
		var r := ro if i % 2 == 0 else ri
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func poly(parent: Node, pts: PackedVector2Array, fill: Color, outline: bool = true, width: float = OUTLINE_W) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = fill
	p.antialiased = true
	parent.add_child(p)
	if outline:
		var l := Line2D.new()
		l.points = pts
		l.closed = true
		l.width = width
		l.default_color = INK
		l.joint_mode = Line2D.LINE_JOINT_ROUND
		l.antialiased = true
		parent.add_child(l)
	return p


static func line(parent: Node, pts: PackedVector2Array, color: Color, width: float, outlined: bool = true) -> void:
	if outlined:
		var o := Line2D.new()
		o.points = pts
		o.width = width + OUTLINE_W * 1.6
		o.default_color = INK
		o.begin_cap_mode = Line2D.LINE_CAP_ROUND
		o.end_cap_mode = Line2D.LINE_CAP_ROUND
		o.joint_mode = Line2D.LINE_JOINT_ROUND
		o.antialiased = true
		parent.add_child(o)
	var l := Line2D.new()
	l.points = pts
	l.width = width
	l.default_color = color
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.antialiased = true
	parent.add_child(l)


static func gloss(parent: Node, c: Vector2, r: Vector2, alpha: float = 0.45) -> void:
	poly(parent, ellipse(c, r, 16), Color(1, 1, 1, alpha), false)


# --- HEAD silhouettes -----------------------------------------------------

static func _head(p: Node2D, s: int, m: Color, sec: Color, acc: Color) -> void:
	match s:
		0:  # Viking Helmet
			var horn_l := PackedVector2Array([Vector2(-44, -20), Vector2(-62, -40), Vector2(-74, -72), Vector2(-66, -78), Vector2(-50, -54), Vector2(-34, -36)])
			var horn_r := PackedVector2Array()
			for v in horn_l:
				horn_r.append(Vector2(-v.x, v.y))
			poly(p, horn_l, sec.lerp(Color.WHITE, 0.6))
			poly(p, horn_r, sec.lerp(Color.WHITE, 0.6))
			poly(p, ellipse(Vector2(0, -6), Vector2(52, 46), 20, PI, TAU), m)
			poly(p, rrect(-56, -12, 112, 18, 8), sec)
			for i in 5:
				poly(p, ellipse(Vector2(-40 + i * 20, -3), Vector2(4, 4), 8), acc, false)
			gloss(p, Vector2(-16, -36), Vector2(16, 7))
		1:  # Wizard Cone
			poly(p, PackedVector2Array([Vector2(-44, 0), Vector2(-6, -100), Vector2(14, -118), Vector2(30, -104), Vector2(12, -98), Vector2(44, 0)]), m)
			poly(p, ellipse(Vector2(0, -2), Vector2(66, 14), 24), sec)
			poly(p, star(Vector2(-8, -46), 12, 5), acc)
			poly(p, star(Vector2(14, -20), 8, 3.5), acc)
			poly(p, star(Vector2(28, -116), 9, 4), acc)
			gloss(p, Vector2(-14, -60), Vector2(6, 18), 0.3)
		2:  # Top Hat
			poly(p, rrect(-34, -86, 68, 84, 6), m)
			poly(p, rect(-34, -26, 68, 14), sec)
			poly(p, ellipse(Vector2(0, -2), Vector2(62, 12), 24), m.darkened(0.2))
			poly(p, rrect(-8, -26, 16, 14, 3), acc)
			gloss(p, Vector2(-18, -66), Vector2(6, 16), 0.35)
		3:  # Propeller Beanie
			poly(p, ellipse(Vector2(0, -4), Vector2(54, 44), 20, PI, TAU), m)
			poly(p, PackedVector2Array([Vector2(-18, -44), Vector2(-6, -48), Vector2(-14, -4), Vector2(-30, -4)]), sec, false)
			poly(p, PackedVector2Array([Vector2(6, -48), Vector2(18, -44), Vector2(30, -4), Vector2(14, -4)]), acc, false)
			poly(p, rrect(-56, -10, 112, 14, 7), sec)
			line(p, PackedVector2Array([Vector2(0, -46), Vector2(0, -62)]), INK, 4, false)
			poly(p, ellipse(Vector2(-22, -64), Vector2(22, 7), 14), acc)
			poly(p, ellipse(Vector2(22, -64), Vector2(22, 7), 14), sec)
			poly(p, ellipse(Vector2(0, -64), Vector2(6, 6), 10), m)
		4:  # Royal Crown
			poly(p, PackedVector2Array([Vector2(-48, 0), Vector2(-52, -56), Vector2(-28, -30), Vector2(-12, -70), Vector2(0, -36), Vector2(12, -70), Vector2(28, -30), Vector2(52, -56), Vector2(48, 0)]), m)
			poly(p, rect(-48, -14, 96, 14), sec)
			for x in [-30, 0, 30]:
				poly(p, ellipse(Vector2(x, -7), Vector2(6, 6), 10), acc)
			for v in [Vector2(-52, -60), Vector2(-12, -74), Vector2(12, -74), Vector2(52, -60)]:
				poly(p, ellipse(v, Vector2(6, 6), 10), acc)
			gloss(p, Vector2(-26, -26), Vector2(10, 5))
		5:  # Chef Toque
			poly(p, rrect(-36, -36, 72, 38, 6), sec.lerp(Color.WHITE, 0.7))
			for c in [Vector2(-28, -54), Vector2(0, -70), Vector2(28, -54), Vector2(-12, -44), Vector2(14, -44)]:
				poly(p, ellipse(c, Vector2(26, 24), 16), Color.WHITE.lerp(m, 0.15))
			poly(p, rect(-36, -14, 72, 12), m)
			gloss(p, Vector2(-10, -78), Vector2(10, 5))
		6:  # Traffic Cone
			poly(p, PackedVector2Array([Vector2(-34, -4), Vector2(-8, -96), Vector2(8, -96), Vector2(34, -4)]), m)
			poly(p, PackedVector2Array([Vector2(-25, -36), Vector2(-17, -64), Vector2(17, -64), Vector2(25, -36)]), sec.lerp(Color.WHITE, 0.7), false)
			poly(p, rrect(-50, -10, 100, 14, 4), m.darkened(0.2))
			gloss(p, Vector2(-10, -76), Vector2(3, 10), 0.4)
		7:  # Pirate Tricorn
			poly(p, PackedVector2Array([Vector2(-70, -6), Vector2(-40, -58), Vector2(0, -40), Vector2(40, -58), Vector2(70, -6), Vector2(0, 8)]), m.darkened(0.35))
			line(p, PackedVector2Array([Vector2(-66, -8), Vector2(0, 4), Vector2(66, -8)]), acc, 4, false)
			poly(p, ellipse(Vector2(0, -26), Vector2(12, 11), 14), Color.WHITE)
			poly(p, ellipse(Vector2(-4, -27), Vector2(3, 3), 8), INK, false)
			poly(p, ellipse(Vector2(4, -27), Vector2(3, 3), 8), INK, false)
			line(p, PackedVector2Array([Vector2(-14, -10), Vector2(14, -2)]), Color.WHITE, 3, false)
			line(p, PackedVector2Array([Vector2(14, -10), Vector2(-14, -2)]), Color.WHITE, 3, false)
		8:  # Bunny Ears
			for sx in [-1, 1]:
				var c := Vector2(22 * sx, -54)
				var ear := ellipse(c, Vector2(15, 48), 22)
				var rot := Transform2D(0.22 * sx, Vector2.ZERO)
				var ear_r := PackedVector2Array()
				for v in ear:
					ear_r.append(rot * (v - c) + c)
				poly(p, ear_r, m)
				var inner := ellipse(c, Vector2(7, 34), 18)
				var inner_r := PackedVector2Array()
				for v in inner:
					inner_r.append(rot * (v - c) + c)
				poly(p, inner_r, acc.lerp(Color("ff9ccf"), 0.6), false)
			poly(p, ellipse(Vector2(0, -4), Vector2(50, 10), 20, PI, TAU), sec)
		_:  # Angel Halo
			poly(p, ellipse(Vector2(0, -40), Vector2(48, 14), 28), Color(acc.r, acc.g, acc.b, 0.35), false)
			var ring := ellipse(Vector2(0, -40), Vector2(42, 11), 28)
			ring.append(ring[0])
			line(p, ring, m.lerp(Color("fff27a"), 0.5), 8)
			gloss(p, Vector2(-18, -48), Vector2(10, 3), 0.7)


# --- FACE silhouettes -----------------------------------------------------

static func _face(p: Node2D, s: int, m: Color, sec: Color, acc: Color) -> void:
	match s:
		0:  # Groucho Glasses
			for sx in [-1, 1]:
				var ring := ellipse(Vector2(24 * sx, 0), Vector2(18, 18), 20)
				ring.append(ring[0])
				line(p, ring, m, 5)
				poly(p, PackedVector2Array([Vector2(8 * sx, -22), Vector2(42 * sx, -28), Vector2(44 * sx, -18), Vector2(10 * sx, -14)]), INK, false)
			line(p, PackedVector2Array([Vector2(-6, 0), Vector2(6, 0)]), m, 4)
			poly(p, ellipse(Vector2(0, 22), Vector2(12, 16), 16), Color("ffb08a"))
			poly(p, PackedVector2Array([Vector2(-32, 42), Vector2(-14, 32), Vector2(0, 38), Vector2(14, 32), Vector2(32, 42), Vector2(10, 46), Vector2(0, 42), Vector2(-10, 46)]), INK, false)
		1:  # Neon Cyber-Visor
			poly(p, rrect(-56, -16, 112, 30, 14), Color(m.r, m.g, m.b, 0.85))
			for i in 4:
				line(p, PackedVector2Array([Vector2(-48, -8 + i * 6), Vector2(48, -8 + i * 6)]), Color(acc.r, acc.g, acc.b, 0.5), 1.5, false)
			poly(p, rrect(-58, -18, 10, 34, 4), sec)
			poly(p, rrect(48, -18, 10, 34, 4), sec)
			gloss(p, Vector2(-20, -8), Vector2(22, 4), 0.55)
		2:  # Laser Monocle
			var ring2 := ellipse(Vector2(24, 0), Vector2(20, 20), 22)
			ring2.append(ring2[0])
			poly(p, ellipse(Vector2(24, 0), Vector2(18, 18), 20), Color(sec.r, sec.g, sec.b, 0.35), false)
			line(p, ring2, m, 6)
			line(p, PackedVector2Array([Vector2(40, 12), Vector2(46, 40), Vector2(36, 70)]), acc, 2.5, false)
			poly(p, ellipse(Vector2(30, -6), Vector2(5, 5), 10), Color("ff2a4a"), false)
			gloss(p, Vector2(16, -8), Vector2(6, 3), 0.7)
		3:  # Pirate Eyepatch
			line(p, PackedVector2Array([Vector2(-60, -24), Vector2(-24, -6), Vector2(20, 14), Vector2(60, 22)]), m.darkened(0.5), 4, false)
			poly(p, ellipse(Vector2(-24, 2), Vector2(19, 16), 18), m.darkened(0.45))
			poly(p, star(Vector2(-24, 2), 7, 3), acc, false)
		4:  # Handlebar Mustache
			var pts := PackedVector2Array([Vector2(0, 30), Vector2(14, 28), Vector2(30, 32), Vector2(42, 28), Vector2(48, 18), Vector2(54, 24), Vector2(48, 36), Vector2(30, 42), Vector2(12, 40), Vector2(0, 36),
				Vector2(-12, 40), Vector2(-30, 42), Vector2(-48, 36), Vector2(-54, 24), Vector2(-48, 18), Vector2(-42, 28), Vector2(-30, 32), Vector2(-14, 28)])
			poly(p, pts, m.darkened(0.25))
			gloss(p, Vector2(-20, 32), Vector2(8, 2), 0.35)
		5:  # Star Shades
			for sx in [-1, 1]:
				poly(p, star(Vector2(25 * sx, 0), 22, 11), m)
				gloss(p, Vector2(20 * sx, -6), Vector2(5, 3), 0.6)
			line(p, PackedVector2Array([Vector2(-6, -2), Vector2(6, -2)]), sec, 4)
		6:  # Clown Nose
			poly(p, ellipse(Vector2(0, 20), Vector2(17, 16), 20), m)
			gloss(p, Vector2(-6, 13), Vector2(5, 3), 0.75)
		7:  # Ski Goggles
			line(p, PackedVector2Array([Vector2(-64, -2), Vector2(64, -2)]), sec, 10)
			poly(p, rrect(-50, -20, 100, 38, 18), m.darkened(0.3))
			poly(p, rrect(-44, -15, 88, 28, 14), m.lerp(acc, 0.5), false)
			poly(p, PackedVector2Array([Vector2(-30, -15), Vector2(-10, -15), Vector2(-28, 13), Vector2(-40, 13)]), Color(1, 1, 1, 0.35), false)
		8:  # 3D Glasses
			poly(p, rrect(-52, -16, 104, 32, 6), m.lerp(Color.WHITE, 0.5))
			poly(p, rrect(-44, -10, 34, 20, 4), Color(1.0, 0.15, 0.25, 0.85), false)
			poly(p, rrect(10, -10, 34, 20, 4), Color(0.1, 0.85, 1.0, 0.85), false)
		_:  # Hero Mask
			var mask := PackedVector2Array([Vector2(-58, -10), Vector2(-40, -22), Vector2(-10, -16), Vector2(0, -10), Vector2(10, -16), Vector2(40, -22), Vector2(58, -10), Vector2(52, 12), Vector2(30, 18), Vector2(8, 10), Vector2(0, 14), Vector2(-8, 10), Vector2(-30, 18), Vector2(-52, 12)])
			poly(p, mask, m)
			poly(p, ellipse(Vector2(-25, -1), Vector2(11, 8), 14), Color(1, 1, 1, 0.85))
			poly(p, ellipse(Vector2(25, -1), Vector2(11, 8), 14), Color(1, 1, 1, 0.85))
			poly(p, ellipse(Vector2(-25, 0), Vector2(4, 4), 8), INK, false)
			poly(p, ellipse(Vector2(25, 0), Vector2(4, 4), 8), INK, false)


# --- HAND silhouettes -----------------------------------------------------

static func _hand(p: Node2D, s: int, m: Color, sec: Color, acc: Color) -> void:
	match s:
		0:  # Giant Foam Finger
			poly(p, rrect(-12, -110, 26, 70, 13), m)
			poly(p, rrect(-30, -52, 62, 60, 18), m)
			poly(p, rrect(-36, -40, 14, 28, 7), m.darkened(0.1))
			var lbl := Label.new()
			lbl.text = "#1"
			lbl.add_theme_font_size_override("font_size", 22)
			lbl.add_theme_color_override("font_color", sec.lerp(Color.WHITE, 0.6))
			lbl.add_theme_color_override("font_outline_color", INK)
			lbl.add_theme_constant_override("outline_size", 6)
			lbl.position = Vector2(-16, -40)
			p.add_child(lbl)
			gloss(p, Vector2(-4, -96), Vector2(4, 10), 0.4)
		1:  # Rubber Chicken
			var body := PackedVector2Array([Vector2(-6, 6), Vector2(-14, -40), Vector2(-10, -78), Vector2(4, -100), Vector2(14, -96), Vector2(10, -70), Vector2(14, -40), Vector2(8, 6)])
			poly(p, body, m.lerp(Color("ffe14d"), 0.6))
			poly(p, PackedVector2Array([Vector2(4, -100), Vector2(18, -108), Vector2(24, -100), Vector2(12, -94)]), Color("ff9f1c"))
			poly(p, PackedVector2Array([Vector2(-2, -104), Vector2(2, -116), Vector2(8, -108), Vector2(12, -118), Vector2(14, -104)]), Color("ff3355"))
			poly(p, ellipse(Vector2(6, -92), Vector2(3, 3), 6), INK, false)
			gloss(p, Vector2(-6, -60), Vector2(3, 14), 0.4)
		2:  # Magic Wand
			line(p, PackedVector2Array([Vector2(0, 10), Vector2(0, -80)]), sec.darkened(0.3), 8)
			poly(p, star(Vector2(0, -92), 26, 11), m)
			gloss(p, Vector2(-6, -100), Vector2(6, 3), 0.6)
			for v in [Vector2(-26, -112), Vector2(24, -70), Vector2(20, -118)]:
				poly(p, star(v, 6, 2.5, 4), acc, false)
		3:  # Squeaky Hammer
			line(p, PackedVector2Array([Vector2(0, 10), Vector2(0, -70)]), sec, 10)
			poly(p, rrect(-40, -104, 80, 40, 16), m)
			poly(p, rrect(-46, -98, 10, 28, 4), acc)
			poly(p, rrect(36, -98, 10, 28, 4), acc)
			gloss(p, Vector2(-14, -94), Vector2(16, 5))
		4:  # Lollipop Sword
			line(p, PackedVector2Array([Vector2(0, 10), Vector2(0, -60)]), Color.WHITE, 8)
			poly(p, ellipse(Vector2(0, -88), Vector2(32, 32), 28), m)
			var sw := PackedVector2Array()
			for i in 40:
				var a := i * 0.45
				sw.append(Vector2(0, -88) + Vector2(cos(a), sin(a)) * (i * 0.72))
			line(p, sw, sec, 5, false)
			gloss(p, Vector2(-12, -104), Vector2(8, 4), 0.55)
		5:  # Fish Slapper
			var fish := PackedVector2Array([Vector2(0, -2), Vector2(-16, -30), Vector2(-18, -70), Vector2(-8, -100), Vector2(0, -108), Vector2(8, -100), Vector2(18, -70), Vector2(16, -30)])
			poly(p, fish, m)
			poly(p, PackedVector2Array([Vector2(0, -4), Vector2(-16, 14), Vector2(16, 14)]), sec)
			poly(p, ellipse(Vector2(-5, -88), Vector2(4, 4), 8), Color.WHITE)
			poly(p, ellipse(Vector2(-5, -88), Vector2(2, 2), 6), INK, false)
			for y in [-40, -56, -72]:
				line(p, PackedVector2Array([Vector2(-10, y), Vector2(0, y - 6), Vector2(10, y)]), acc, 2.5, false)
		6:  # Golden Plunger
			line(p, PackedVector2Array([Vector2(0, 10), Vector2(0, -70)]), sec, 8)
			poly(p, ellipse(Vector2(0, -78), Vector2(30, 24), 22, PI, TAU), m)
			poly(p, rrect(-32, -80, 64, 10, 5), m.darkened(0.2))
			gloss(p, Vector2(-10, -92), Vector2(8, 4), 0.55)
		7:  # Bubble Blaster
			poly(p, rrect(-14, -20, 22, 34, 6), sec)
			poly(p, rrect(-20, -58, 62, 38, 14), m)
			poly(p, rrect(38, -48, 20, 16, 5), acc)
			for v in [Vector2(72, -60), Vector2(90, -80), Vector2(70, -96)]:
				var b := ellipse(v, Vector2(9, 9), 16)
				b.append(b[0])
				line(p, b, Color(0.8, 0.95, 1.0, 0.8), 2.5, false)
			gloss(p, Vector2(4, -48), Vector2(14, 4))
		8:  # Battle Baguette
			poly(p, rrect(-14, -120, 28, 132, 14), m.lerp(Color("e8a24a"), 0.7))
			for y in [-100, -76, -52, -28]:
				line(p, PackedVector2Array([Vector2(-8, y + 6), Vector2(8, y - 6)]), Color("fff0c0"), 3, false)
			gloss(p, Vector2(-6, -90), Vector2(3, 18), 0.3)
		_:  # Banana Phone
			var ban := PackedVector2Array()
			for i in 13:
				var a := lerpf(PI * 0.75, PI * 1.25, i / 12.0)
				ban.append(Vector2(70, -50) + Vector2(cos(a), sin(a)) * 80)
			for i in 13:
				var a := lerpf(PI * 1.25, PI * 0.75, i / 12.0)
				ban.append(Vector2(78, -50) + Vector2(cos(a), sin(a)) * 64)
			poly(p, ban, m.lerp(Color("ffe14d"), 0.7))
			poly(p, ellipse(Vector2(14, -6), Vector2(8, 6), 10), Color("6b4a2a"), false)
			poly(p, rrect(-4, -66, 16, 26, 4), sec)
