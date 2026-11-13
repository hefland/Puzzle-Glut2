extends Node
## AudioSynth — 100% procedural audio.
##
## Every sound effect is synthesised once at startup into a cached
## AudioStreamWAV (no AudioStreamGenerator, so no buffer underflow or
## latency). Music is two looping stems built on a background thread:
##   * "base"      — bass, pads and hats (menus + battle)
##   * "intensity" — lead arpeggio and drums, faded in during battle and
##                   pushed harder when the board is in danger or a chain hits.

const RATE := 22050
const NOTE_C5 := 523.25
const CHAIN_NOTES := [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]  # C5 D5 E5 G5 A5 C6

enum Wave { SINE, SQUARE, SAW, TRI, NOISE }

var sounds: Dictionary = {}
var _players: Array = []
var _next_player := 0
var _music_base: AudioStreamPlayer
var _music_layer: AudioStreamPlayer
var _music_thread: Thread
var _music_ready := false
var _want_music := ""
var _layer_target := -40.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 777
	_setup_buses()
	for i in 16:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_music_base = AudioStreamPlayer.new()
	_music_base.bus = "Music"
	_music_layer = AudioStreamPlayer.new()
	_music_layer.bus = "Music"
	_music_layer.volume_db = -40.0
	add_child(_music_base)
	add_child(_music_layer)
	_build_sfx()
	apply_volume()
	_music_thread = Thread.new()
	_music_thread.start(_build_music_threaded)


func _exit_tree() -> void:
	if _music_thread and _music_thread.is_started():
		_music_thread.wait_to_finish()


func _process(delta: float) -> void:
	if _music_layer and _music_layer.playing:
		_music_layer.volume_db = lerpf(_music_layer.volume_db, _layer_target, clampf(delta * 3.0, 0.0, 1.0))


# --- Public API -----------------------------------------------------------

func play(sound: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not sounds.has(sound):
		return
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = sounds[sound]
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	p.volume_db = volume_db
	p.play()


## Ascending chime for cascade step `n` (1-based); keeps climbing octaves.
func play_chain(n: int) -> void:
	var idx := clampi(n - 1, 0, 30)
	var octave := idx / CHAIN_NOTES.size()
	var note := idx % CHAIN_NOTES.size()
	play("chime%d" % note, pow(2.0, octave), -2.0)


## mode: "menu" (base stem only) or "battle" (base + intensity layer).
func play_music(mode: String) -> void:
	_want_music = mode
	if not _music_ready:
		return
	if not _music_base.playing:
		_music_base.play()
		_music_layer.play()
	set_intensity(0.0 if mode == "menu" else 0.5)


func set_intensity(v: float) -> void:
	if _want_music == "menu":
		_layer_target = -40.0
	else:
		_layer_target = lerpf(-14.0, 0.0, clampf(v, 0.0, 1.0))


func set_music_speed(s: float) -> void:
	if _music_base:
		_music_base.pitch_scale = s
		_music_layer.pitch_scale = s


func toggle_mute() -> bool:
	SaveManager.data["muted"] = not bool(SaveManager.data.get("muted", false))
	SaveManager.save_game()
	apply_volume()
	return bool(SaveManager.data["muted"])


func set_volume(v: float) -> void:
	SaveManager.data["volume"] = clampf(v, 0.0, 1.0)
	SaveManager.save_game()
	apply_volume()


func apply_volume() -> void:
	var muted := bool(SaveManager.data.get("muted", false))
	var vol := float(SaveManager.data.get("volume", 0.8))
	AudioServer.set_bus_mute(0, muted or vol <= 0.001)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.001)))


func is_muted() -> bool:
	return bool(SaveManager.data.get("muted", false))


# --- Bus setup ------------------------------------------------------------

func _setup_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -7.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), -2.0)


# --- Synthesis primitives -------------------------------------------------

func _osc(w: int, ph: float) -> float:
	var f := ph - floorf(ph)
	match w:
		Wave.SINE:
			return sin(TAU * f)
		Wave.SQUARE:
			return 0.6 if f < 0.5 else -0.6
		Wave.SAW:
			return (2.0 * f - 1.0) * 0.7
		Wave.TRI:
			return 4.0 * absf(f - 0.5) - 1.0
		_:
			return _rng.randf_range(-1.0, 1.0)


## Generic swept tone with attack and exponential-ish decay.
func _tone(dur: float, f0: float, f1: float, w: int, vol: float = 0.6, attack: float = 0.005, decay_pow: float = 2.0, vibrato: float = 0.0, vib_rate: float = 6.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := float(i) / n
		var f := lerpf(f0, f1, k) * (1.0 + vibrato * sin(TAU * vib_rate * t))
		ph += f / RATE
		var env := minf(t / maxf(attack, 0.0001), 1.0) * pow(1.0 - k, decay_pow)
		buf[i] = _osc(w, ph) * env * vol
	return buf


## Noise through a one-pole low-pass whose cutoff sweeps from c0 to c1 (0..1).
func _noise(dur: float, c0: float, c1: float, vol: float = 0.5, decay_pow: float = 2.0, attack: float = 0.002) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var y := 0.0
	for i in n:
		var k := float(i) / n
		var c := lerpf(c0, c1, k)
		y += (_rng.randf_range(-1.0, 1.0) - y) * c
		var env := minf(float(i) / RATE / attack, 1.0) * pow(1.0 - k, decay_pow)
		buf[i] = y * env * vol
	return buf


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, offset_sec: float = 0.0) -> PackedFloat32Array:
	var off := int(offset_sec * RATE)
	var n := maxi(a.size(), b.size() + off)
	var out := a.duplicate()
	out.resize(n)
	for i in range(a.size(), n):
		out[i] = 0.0
	for i in b.size():
		out[i + off] += b[i]
	return out


func _bell(freq: float, dur: float, vol: float = 0.4) -> PackedFloat32Array:
	var b := _tone(dur, freq, freq, Wave.SINE, vol, 0.002, 2.5)
	b = _mix(b, _tone(dur * 0.7, freq * 2.0, freq * 2.0, Wave.SINE, vol * 0.35, 0.002, 3.0))
	b = _mix(b, _tone(dur * 0.4, freq * 3.01, freq * 3.01, Wave.SINE, vol * 0.18, 0.001, 3.0))
	return b


func _brass(freqs: Array, dur: float, vol: float = 0.18) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f in freqs:
		out = _mix(out, _tone(dur, f, f, Wave.SAW, vol, 0.04, 0.7, 0.008, 5.5))
		out = _mix(out, _tone(dur, f * 1.003, f * 1.003, Wave.SQUARE, vol * 0.35, 0.05, 0.8))
	return out


func _to_wav(buf: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


# --- Sound effect bank ----------------------------------------------------

func _build_sfx() -> void:
	# Woody / glassy move tick.
	sounds["tick"] = _to_wav(_mix(_tone(0.05, 1900, 1500, Wave.SINE, 0.35, 0.001, 4.0), _noise(0.02, 0.6, 0.2, 0.25, 3.0)))
	sounds["ui_move"] = _to_wav(_tone(0.04, 2300, 2600, Wave.SINE, 0.25, 0.001, 3.0))
	sounds["ui_click"] = _to_wav(_mix(_tone(0.07, 700, 1100, Wave.SQUARE, 0.25, 0.001, 2.0), _tone(0.07, 1400, 2200, Wave.SINE, 0.2, 0.001, 2.0)))
	# Rotation whoosh.
	sounds["whoosh"] = _to_wav(_noise(0.2, 0.05, 0.5, 0.55, 1.5, 0.05))
	# Heavy hard-drop thud.
	sounds["thud"] = _to_wav(_mix(_tone(0.32, 120, 38, Wave.SINE, 0.95, 0.001, 2.2), _noise(0.08, 0.5, 0.05, 0.5, 2.0)))
	sounds["land"] = _to_wav(_mix(_tone(0.12, 260, 140, Wave.SINE, 0.5, 0.001, 2.5), _noise(0.04, 0.4, 0.1, 0.2)))
	# Chain chimes C5 D5 E5 G5 A5 C6.
	for i in CHAIN_NOTES.size():
		sounds["chime%d" % i] = _to_wav(_bell(CHAIN_NOTES[i], 0.6, 0.42))
	# Block pop.
	sounds["pop"] = _to_wav(_mix(_tone(0.08, 380, 980, Wave.SINE, 0.5, 0.001, 1.5), _noise(0.03, 0.8, 0.3, 0.15)))
	# Cartoon boing.
	sounds["boing"] = _to_wav(_tone(0.45, 330, 160, Wave.SINE, 0.55, 0.002, 1.2, 0.12, 14.0))
	# Laser zap.
	sounds["zap"] = _to_wav(_mix(_tone(0.22, 1600, 180, Wave.SQUARE, 0.32, 0.001, 1.2), _tone(0.22, 1610, 190, Wave.SAW, 0.2, 0.001, 1.2)))
	# Explosion boom.
	sounds["boom"] = _to_wav(_mix(_noise(0.75, 0.35, 0.02, 0.85, 1.6), _tone(0.6, 80, 32, Wave.SINE, 0.8, 0.001, 1.8)))
	# Boss impact squeak.
	var sq := _tone(0.09, 900, 1600, Wave.SINE, 0.45, 0.002, 0.6)
	sq = _mix(sq, _tone(0.12, 1600, 1050, Wave.SINE, 0.45, 0.002, 1.5), 0.09)
	sounds["squeak"] = _to_wav(sq)
	sounds["hit"] = _to_wav(_mix(_noise(0.18, 0.7, 0.1, 0.6, 2.0), _tone(0.2, 220, 70, Wave.TRI, 0.7, 0.001, 2.0)))
	# Coin / gem pickups.
	var coin := _tone(0.07, 988, 988, Wave.SQUARE, 0.22, 0.001, 0.5)
	coin = _mix(coin, _tone(0.22, 1319, 1319, Wave.SQUARE, 0.22, 0.001, 2.0), 0.07)
	sounds["coin"] = _to_wav(coin)
	sounds["gem"] = _to_wav(_mix(_bell(1568, 0.35, 0.3), _bell(2093, 0.4, 0.25), 0.06))
	# Triumphant brass fanfare: G -> C major.
	var fan := _brass([392.0, 493.88, 587.33], 0.28, 0.16)
	fan = _mix(fan, _brass([392.0, 493.88, 587.33], 0.16, 0.16), 0.3)
	fan = _mix(fan, _brass([523.25, 659.25, 783.99, 1046.5], 1.1, 0.15), 0.48)
	fan = _mix(fan, _tone(1.0, 130.81, 130.81, Wave.SAW, 0.25, 0.02, 1.0), 0.48)
	sounds["fanfare"] = _to_wav(fan)
	# Sad trombone defeat (wah wah wahhh).
	var lose := _tone(0.35, 311.13, 300, Wave.SAW, 0.3, 0.03, 0.6, 0.02, 5.0)
	lose = _mix(lose, _tone(0.35, 293.66, 285, Wave.SAW, 0.3, 0.03, 0.6, 0.02, 5.0), 0.38)
	lose = _mix(lose, _tone(0.9, 277.18, 250, Wave.SAW, 0.3, 0.03, 0.8, 0.04, 6.0), 0.76)
	sounds["lose"] = _to_wav(lose)
	# Draft card shimmer arpeggio.
	var arp := PackedFloat32Array()
	var notes := [783.99, 987.77, 1174.66, 1567.98]
	for i in notes.size():
		arp = _mix(arp, _bell(notes[i], 0.4, 0.25), i * 0.06)
	sounds["card"] = _to_wav(arp)
	var lvl := PackedFloat32Array()
	var notes2 := [523.25, 659.25, 783.99, 1046.5, 1318.5]
	for i in notes2.size():
		lvl = _mix(lvl, _tone(0.18, notes2[i], notes2[i], Wave.SQUARE, 0.18, 0.002, 1.5), i * 0.07)
	sounds["level_up"] = _to_wav(lvl)
	# Boss warning klaxon.
	var warn := _tone(0.16, 740, 740, Wave.SQUARE, 0.22, 0.005, 0.3)
	warn = _mix(warn, _tone(0.16, 554, 554, Wave.SQUARE, 0.22, 0.005, 0.3), 0.18)
	sounds["warn"] = _to_wav(warn)
	# Ice freeze shimmer.
	var ice := _noise(0.5, 0.9, 0.6, 0.12, 1.5)
	for i in 5:
		ice = _mix(ice, _bell(2000 + i * 330, 0.25, 0.12), i * 0.05)
	sounds["freeze"] = _to_wav(ice)
	# Chest rumble.
	sounds["rumble"] = _to_wav(_mix(_noise(0.5, 0.05, 0.02, 0.6, 0.5, 0.05), _tone(0.5, 60, 55, Wave.TRI, 0.4, 0.05, 0.5)))
	sounds["shield"] = _to_wav(_mix(_tone(0.25, 600, 1200, Wave.TRI, 0.35, 0.002, 1.5), _bell(1800, 0.3, 0.2)))


# --- Music (background thread) --------------------------------------------

func _build_music_threaded() -> void:
	var bpm := 118.0
	var beat := 60.0 / bpm
	var bars := 8
	var total := int(bars * 4 * beat * RATE)
	var base := PackedFloat32Array()
	base.resize(total)
	var layer := PackedFloat32Array()
	layer.resize(total)
	# I - vi - IV - V in C, one bar each, twice.
	var chords := [
		[130.81, 164.81, 196.0], [110.0, 130.81, 164.81], [87.31, 110.0, 130.81], [98.0, 123.47, 146.83],
		[130.81, 164.81, 196.0], [110.0, 130.81, 164.81], [87.31, 110.0, 130.81], [98.0, 123.47, 146.83],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for bar in bars:
		var chord: Array = chords[bar]
		var bar_start := bar * 4 * beat
		# Pad: soft sine triad an octave up.
		for f in chord:
			_add_note(base, bar_start, beat * 4.0, f * 2.0, Wave.SINE, 0.045, 0.15, 0.3)
		# Bouncy bass: root / octave eighths.
		for e in 8:
			var f2: float = chord[0] * (1.0 if e % 2 == 0 else 2.0) * 0.5
			_add_note(base, bar_start + e * beat * 0.5, beat * 0.45, f2, Wave.TRI, 0.32, 0.005, 1.6)
		# Hats on the off-beats.
		for e in 8:
			if e % 2 == 1:
				_add_noise(base, bar_start + e * beat * 0.5, 0.05, 0.08, rng)
		# Lead arpeggio (16ths) in the intensity layer.
		var arp := [chord[0] * 4.0, chord[1] * 4.0, chord[2] * 4.0, chord[1] * 4.0]
		for s in 16:
			var f3: float = arp[s % 4] * (2.0 if (s >= 12 and bar % 2 == 1) else 1.0)
			_add_note(layer, bar_start + s * beat * 0.25, beat * 0.22, f3, Wave.SQUARE, 0.07, 0.003, 2.0)
		# Drums: kick on 1 & 3 (+ syncopation), snare on 2 & 4.
		for b in 4:
			var t: float = bar_start + b * beat
			if b % 2 == 0:
				_add_kick(layer, t)
			else:
				_add_snare(layer, t, rng)
		_add_kick(layer, bar_start + 3.5 * beat)
	var base_stream := _to_wav(base, true)
	var layer_stream := _to_wav(layer, true)
	call_deferred("_on_music_built", base_stream, layer_stream)


func _on_music_built(base_stream: AudioStreamWAV, layer_stream: AudioStreamWAV) -> void:
	_music_base.stream = base_stream
	_music_layer.stream = layer_stream
	_music_ready = true
	if _want_music != "":
		play_music(_want_music)


func _add_note(buf: PackedFloat32Array, start: float, dur: float, f: float, w: int, vol: float, attack: float, decay_pow: float) -> void:
	var s := int(start * RATE)
	var n := int(dur * RATE)
	var ph := 0.0
	for i in n:
		var idx := s + i
		if idx >= buf.size():
			idx -= buf.size()   # wrap so the loop stays seamless
		var t := float(i) / RATE
		var k := float(i) / n
		ph += f / RATE
		var env := minf(t / attack, 1.0) * pow(1.0 - k, decay_pow)
		var fr := ph - floorf(ph)
		var v := 0.0
		match w:
			Wave.SINE:
				v = sin(TAU * fr)
			Wave.TRI:
				v = 4.0 * absf(fr - 0.5) - 1.0
			_:
				v = 0.6 if fr < 0.5 else -0.6
		buf[idx] += v * env * vol


func _add_noise(buf: PackedFloat32Array, start: float, dur: float, vol: float, rng: RandomNumberGenerator) -> void:
	var s := int(start * RATE)
	var n := int(dur * RATE)
	var prev := 0.0
	for i in n:
		var idx := (s + i) % buf.size()
		var raw := rng.randf_range(-1.0, 1.0)
		var hp := raw - prev   # crude high-pass for crisp hats
		prev = raw
		buf[idx] += hp * pow(1.0 - float(i) / n, 3.0) * vol


func _add_kick(buf: PackedFloat32Array, start: float) -> void:
	var s := int(start * RATE)
	var n := int(0.22 * RATE)
	var ph := 0.0
	for i in n:
		var idx := (s + i) % buf.size()
		var k := float(i) / n
		ph += lerpf(150.0, 42.0, sqrt(k)) / RATE
		buf[idx] += sin(TAU * ph) * pow(1.0 - k, 2.0) * 0.55


func _add_snare(buf: PackedFloat32Array, start: float, rng: RandomNumberGenerator) -> void:
	var s := int(start * RATE)
	var n := int(0.16 * RATE)
	var ph := 0.0
	for i in n:
		var idx := (s + i) % buf.size()
		var k := float(i) / n
		ph += 190.0 / RATE
		buf[idx] += (rng.randf_range(-1.0, 1.0) * 0.22 + sin(TAU * ph) * 0.15) * pow(1.0 - k, 2.5)
