extends Node
## UIKit — shared candy-styled UI factory: theme, juicy buttons, panels,
## floating text, particle bursts and the iris screen transition.

const OUTLINE := Color("1b0f2e")
const PANEL := Color("2a1747")
const PANEL_LIGHT := Color("3d2470")
const WHITE := Color("fffaf0")
const PINK := Color("ff6fb5")
const ORANGE := Color("ff9f1c")
const CYAN := Color("2ee6d6")
const GOLD := Color("ffd23f")
const LIME := Color("7cf06b")
const RED := Color("ff4d6d")
const BLUE := Color("3fa9ff")
const PURPLE := Color("a66cff")

## Block colours (index matches GridBoard colour ids).
const BLOCK_COLORS := [Color("ff4d6d"), Color("3fa9ff"), Color("4cd964"), Color("ffd23f"), Color("b76cff")]
const RARITY_COLORS := [Color("b8c4d6"), Color("3fa9ff"), Color("c06bff"), Color("ffb31a")]
const RARITY_NAMES := ["Common", "Rare", "Epic", "Legendary"]

var font: FontVariation
var font_bold: FontVariation
var theme: Theme
var dot_texture: Texture2D
var square_texture: Texture2D
var _transition_layer: CanvasLayer
var _transition_rect: ColorRect
var _transitioning := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.55
	font_bold = FontVariation.new()
	font_bold.base_font = ThemeDB.fallback_font
	font_bold.variation_embolden = 1.1
	font_bold.spacing_glyph = 1
	theme = _build_theme()
	get_tree().root.theme = theme
	dot_texture = _make_dot_texture(32)
	square_texture = _make_square_texture(12)
	_build_transition()


# --- Theme ----------------------------------------------------------------

func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 22
	t.set_color("font_color", "Label", WHITE)
	t.set_color("font_outline_color", "Label", OUTLINE)
	t.set_constant("outline_size", "Label", 8)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	t.set_constant("shadow_offset_y", "Label", 3)
	t.set_constant("shadow_offset_x", "Label", 0)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(state, "Button", WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.5))
	t.set_color("font_outline_color", "Button", OUTLINE)
	t.set_constant("outline_size", "Button", 7)
	t.set_font("font", "Button", font_bold)
	t.set_font_size("font_size", "Button", 24)
	var empty := StyleBoxEmpty.new()
	t.set_stylebox("focus", "Button", empty)
	# Scrollbars — chunky candy.
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = PINK
	grabber.set_corner_radius_all(8)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.25)
	track.set_corner_radius_all(8)
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("grabber", sb, grabber)
		t.set_stylebox("grabber_highlight", sb, grabber)
		t.set_stylebox("grabber_pressed", sb, grabber)
		t.set_stylebox("scroll", sb, track)
	# Sliders.
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0, 0, 0, 0.35)
	slider_bg.set_corner_radius_all(8)
	slider_bg.content_margin_top = 6
	slider_bg.content_margin_bottom = 6
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = CYAN
	slider_fill.set_corner_radius_all(8)
	slider_fill.content_margin_top = 6
	slider_fill.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	var slider_focus := StyleBoxFlat.new()
	slider_focus.draw_center = false
	slider_focus.border_color = GOLD
	slider_focus.set_border_width_all(3)
	slider_focus.set_corner_radius_all(10)
	slider_focus.expand_margin_left = 6
	slider_focus.expand_margin_right = 6
	slider_focus.expand_margin_top = 6
	slider_focus.expand_margin_bottom = 6
	t.set_stylebox("focus", "HSlider", slider_focus)
	t.set_icon("grabber", "HSlider", _make_knob_texture(28, WHITE))
	t.set_icon("grabber_highlight", "HSlider", _make_knob_texture(30, GOLD))
	# Tooltip / panels.
	t.set_stylebox("panel", "PanelContainer", panel_style(PANEL, 22))
	t.set_stylebox("panel", "Panel", panel_style(PANEL, 22))
	return t


func panel_style(color: Color, radius: int = 22, border: int = 5, shadow: bool = true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.border_color = OUTLINE
	sb.set_border_width_all(border)
	sb.anti_aliasing = true
	if shadow:
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 2
		sb.shadow_offset = Vector2(0, 7)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


func button_style(color: Color, pressed: bool = false, focused: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.12) if pressed else color
	sb.set_corner_radius_all(20)
	sb.border_color = GOLD if focused else OUTLINE
	sb.set_border_width_all(6 if focused else 5)
	sb.border_blend = false
	sb.anti_aliasing = true
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(0, 2 if pressed else 7)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	if focused:
		sb.expand_margin_left = 3
		sb.expand_margin_right = 3
		sb.expand_margin_top = 3
		sb.expand_margin_bottom = 3
	return sb


# --- Factories ------------------------------------------------------------

## A juicy candy button: rounded, outlined, glossy, squashes on press,
## grows on hover/focus and plays UI sounds.
func make_button(text: String, color: Color = PINK, min_size: Vector2 = Vector2(220, 64), font_size: int = 26) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", font_size)
	style_button(b, color)
	juice(b)
	return b


func style_button(b: Button, color: Color) -> void:
	b.add_theme_stylebox_override("normal", button_style(color))
	b.add_theme_stylebox_override("hover", button_style(color.lightened(0.1)))
	b.add_theme_stylebox_override("pressed", button_style(color, true))
	b.add_theme_stylebox_override("hover_pressed", button_style(color, true))
	b.add_theme_stylebox_override("focus", button_style(color.lightened(0.12), false, true))
	b.add_theme_stylebox_override("disabled", button_style(color.darkened(0.45)))
	var gloss := b.get_node_or_null("Gloss")
	if gloss == null:
		gloss = Panel.new()
		gloss.name = "Gloss"
		gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g := StyleBoxFlat.new()
		g.bg_color = Color(1, 1, 1, 0.22)
		g.set_corner_radius_all(14)
		g.anti_aliasing = true
		gloss.add_theme_stylebox_override("panel", g)
		gloss.anchor_right = 1.0
		gloss.anchor_bottom = 0.42
		gloss.offset_left = 12
		gloss.offset_right = -12
		gloss.offset_top = 8
		gloss.offset_bottom = 0
		b.add_child(gloss)
		b.move_child(gloss, 0)


## Adds hover/focus/press squash-and-stretch to any Control.
func juice(c: Control) -> void:
	c.resized.connect(func(): c.pivot_offset = c.size * 0.5)
	c.pivot_offset = c.size * 0.5
	var grow := func():
		if not c.is_inside_tree():
			return
		var tw := c.create_tween()
		tw.tween_property(c, "scale", Vector2(1.07, 1.07), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var shrink := func():
		if not c.is_inside_tree():
			return
		var tw := c.create_tween()
		tw.tween_property(c, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_SINE)
	c.mouse_entered.connect(grow)
	c.mouse_exited.connect(func():
		if not c.has_focus():
			shrink.call())
	c.focus_entered.connect(func():
		grow.call()
		AudioSynth.play("ui_move", 1.0, -8.0))
	c.focus_exited.connect(shrink)
	if c is BaseButton:
		(c as BaseButton).button_down.connect(func(): squash(c))
		(c as BaseButton).pressed.connect(func(): AudioSynth.play("ui_click"))


func squash(c: CanvasItem, amount: float = 0.18) -> void:
	if not c.is_inside_tree():
		return
	var base := Vector2.ONE
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(base.x + amount, base.y - amount), 0.06)
	tw.tween_property(c, "scale", Vector2(base.x - amount * 0.5, base.y + amount * 0.5), 0.08)
	tw.tween_property(c, "scale", base * (1.07 if (c is Control and (c as Control).has_focus()) else 1.0), 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func make_label(text: String, size: int = 24, color: Color = WHITE, outline: int = 8) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func make_panel(color: Color = PANEL, radius: int = 22) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(color, radius))
	return p


## Full-screen animated gradient background.
func make_background(top: Color, bottom: Color, accent: Color) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/bg_gradient.gdshader")
	m.set_shader_parameter("color_top", top)
	m.set_shader_parameter("color_bottom", bottom)
	m.set_shader_parameter("color_accent", accent)
	r.material = m
	return r


func make_glow(color: Color, size: float, rays: float = 12.0) -> ColorRect:
	var r := ColorRect.new()
	r.size = Vector2(size, size)
	r.position = Vector2(-size * 0.5, -size * 0.5)
	r.pivot_offset = r.size * 0.5
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/glow_rays.gdshader")
	m.set_shader_parameter("glow_color", color)
	m.set_shader_parameter("rays", rays)
	r.material = m
	return r


## Wraps a Control in a dark backdrop that eats input — used for modal overlays.
func make_overlay(parent: Node, dim: float = 0.6) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_to_group("modal_overlay")
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.05, 0.02, 0.1, dim)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dimmer)
	parent.add_child(root)
	return root


# --- Effects --------------------------------------------------------------

## Bouncy floating text that rises and fades. `parent` may be a Node2D or Control.
func popup_text(parent: Node, pos: Vector2, text: String, color: Color = GOLD, size: int = 40, rise: float = 90.0, duration: float = 1.0) -> Label:
	var l := make_label(text, size, color, 10)
	l.add_theme_font_override("font", font_bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_index = 50
	parent.add_child(l)
	l.reset_size()
	l.pivot_offset = l.size * 0.5
	l.position = pos - l.size * 0.5
	l.scale = Vector2(0.2, 0.2)
	l.rotation = randf_range(-0.12, 0.12)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.15, 1.15), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.1)
	tw.parallel().tween_property(l, "position:y", l.position.y - rise, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, duration * 0.35).set_delay(duration * 0.65)
	tw.tween_callback(l.queue_free)
	return l


## One-shot particle burst. Frees itself when done.
func burst(parent: Node, pos: Vector2, color: Color, amount: int = 18, speed: float = 260.0, scale_mul: float = 1.0, confetti: bool = false) -> void:
	var p := GPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.9 if confetti else 0.6
	p.texture = square_texture if confetti else dot_texture
	p.z_index = 40
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, -1, 0)
	m.spread = 180.0
	m.initial_velocity_min = speed * 0.45
	m.initial_velocity_max = speed
	m.gravity = Vector3(0, 620 if confetti else 420, 0)
	m.damping_min = 40.0
	m.damping_max = 90.0
	m.scale_min = 0.35 * scale_mul
	m.scale_max = 0.85 * scale_mul
	m.angular_velocity_min = -400.0 if confetti else 0.0
	m.angular_velocity_max = 400.0 if confetti else 0.0
	m.angle_min = 0.0
	m.angle_max = 360.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.7, Color(1, 1, 1, 1))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	m.color_ramp = ft
	if confetti:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
		g.colors = PackedColorArray([RED, GOLD, LIME, CYAN, PURPLE, PINK])
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		var gt := GradientTexture1D.new()
		gt.gradient = g
		m.color_initial_ramp = gt
	else:
		m.color = color
	p.process_material = m
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	# Fallback cleanup in case `finished` never fires (e.g. paused tree).
	var ref: WeakRef = weakref(p)
	get_tree().create_timer(p.lifetime + 1.5, true).timeout.connect(func():
		var node = ref.get_ref()
		if node:
			node.queue_free())


# --- Scene transitions ----------------------------------------------------

func _build_transition() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.layer = 100
	add_child(_transition_layer)
	_transition_rect = ColorRect.new()
	_transition_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/transition.gdshader")
	m.set_shader_parameter("progress", 0.0)
	_transition_rect.material = m
	_transition_layer.add_child(_transition_rect)


func _set_iris(v: float) -> void:
	var m := _transition_rect.material as ShaderMaterial
	m.set_shader_parameter("progress", v)
	m.set_shader_parameter("screen_size", get_viewport().get_visible_rect().size)


func change_scene(path: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	AudioSynth.play("whoosh", 0.8)
	var tw := create_tween()
	tw.tween_method(_set_iris, 0.0, 1.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_method(_set_iris, 1.0, 0.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw2.finished
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transitioning = false
	if InputHub.is_pad():
		InputHub.ensure_focus()


# --- Procedural textures --------------------------------------------------

func _make_dot_texture(s: int) -> Texture2D:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := (s - 1) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a * 2.2, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _make_square_texture(s: int) -> Texture2D:
	var img := Image.create(s, int(s * 0.6), false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _make_knob_texture(s: int, col: Color) -> Texture2D:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := (s - 1) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x - c, y - c).length()
			var col_px := Color(0, 0, 0, 0)
			if d <= c:
				col_px = OUTLINE
			if d <= c - 3.0:
				col_px = col
			if d > c - 1.0 and d <= c:
				col_px.a = clampf(c - d, 0.0, 1.0)
			img.set_pixel(x, y, col_px)
	return ImageTexture.create_from_image(img)


func circle_texture(s: int, col: Color, outline_px: float = 4.0) -> Texture2D:
	return _make_knob_texture_custom(s, col, outline_px)


func _make_knob_texture_custom(s: int, col: Color, outline_px: float) -> Texture2D:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := (s - 1) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x - c, y - c).length()
			var px := Color(0, 0, 0, 0)
			if d <= c:
				px = OUTLINE
				px.a = clampf(c - d + 0.5, 0.0, 1.0)
			if d <= c - outline_px:
				px = col
				# glossy top
				if y < c * 0.8 and Vector2(x - c * 0.85, y - c * 0.55).length() < c * 0.45:
					px = col.lerp(Color.WHITE, 0.35)
			img.set_pixel(x, y, px)
	return ImageTexture.create_from_image(img)
