extends Node

# Zero-dependency procedural Jiangnan ambient soundscape & crisp SFX synthesizer.
# Generates filtered rain (muffled when indoors), river murmur, footsteps (stone/puddle),
# door creak, smithy anvil clink, cooking sizzle, sparring clash, coin clink, and meditation chime.

const MIX_RATE := 22050.0

var muted := false
var master_vol := 0.28
var _rain_level := 0.0
var _water_level := 0.0
var _indoors := false
var _amb_player: AudioStreamPlayer
var _amb_playback: AudioStreamGeneratorPlayback
var _sfx_player: AudioStreamPlayer
var _sfx_playback: AudioStreamGeneratorPlayback
var _lp_rain := 0.0
var _lp_water := 0.0
var _noise_seed := 1337
var _phase := 0.0
var _sfx_queue: Array[Dictionary] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	var amb_gen := AudioStreamGenerator.new()
	amb_gen.mix_rate = MIX_RATE
	amb_gen.buffer_length = 0.16
	_amb_player = AudioStreamPlayer.new()
	_amb_player.stream = amb_gen
	_amb_player.volume_db = -6.0
	add_child(_amb_player)
	_amb_player.play()
	_amb_playback = _amb_player.get_stream_playback() as AudioStreamGeneratorPlayback

	var sfx_gen := AudioStreamGenerator.new()
	sfx_gen.mix_rate = MIX_RATE
	sfx_gen.buffer_length = 0.20
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.stream = sfx_gen
	_sfx_player.volume_db = -4.0
	add_child(_sfx_player)
	_sfx_player.play()
	_sfx_playback = _sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback
	set_process(true)


func toggle_mute() -> bool:
	muted = not muted
	return muted


func set_environment(rain: float, near_water: float, indoors: bool) -> void:
	_rain_level = clampf(rain, 0.0, 1.0)
	_water_level = clampf(near_water, 0.0, 1.0)
	_indoors = indoors


func play_sfx(kind: String) -> void:
	if muted or _sfx_playback == null:
		return
	if _sfx_queue.size() > 5:
		_sfx_queue.pop_front()
	match kind:
		"step_stone":
			_sfx_queue.append({"freq": 150.0, "freq2": 95.0, "noise": 0.45, "dur": 0.055, "gain": 0.24, "t": 0.0})
		"step_puddle":
			_sfx_queue.append({"freq": 320.0, "freq2": 180.0, "noise": 0.85, "dur": 0.085, "gain": 0.28, "t": 0.0})
		"door":
			_sfx_queue.append({"freq": 210.0, "freq2": 145.0, "noise": 0.25, "dur": 0.13, "gain": 0.30, "t": 0.0})
		"coin":
			_sfx_queue.append({"freq": 1480.0, "freq2": 1960.0, "noise": 0.04, "dur": 0.12, "gain": 0.24, "t": 0.0})
		"hit":
			_sfx_queue.append({"freq": 190.0, "freq2": 80.0, "noise": 0.60, "dur": 0.11, "gain": 0.38, "t": 0.0})
		"clash":
			_sfx_queue.append({"freq": 980.0, "freq2": 620.0, "noise": 0.35, "dur": 0.16, "gain": 0.32, "t": 0.0})
		"meditate":
			_sfx_queue.append({"freq": 528.0, "freq2": 528.0, "noise": 0.0, "dur": 0.36, "gain": 0.22, "t": 0.0})
		"book":
			_sfx_queue.append({"freq": 420.0, "freq2": 290.0, "noise": 0.72, "dur": 0.09, "gain": 0.20, "t": 0.0})
		"work":
			_sfx_queue.append({"freq": 360.0, "freq2": 240.0, "noise": 0.42, "dur": 0.12, "gain": 0.26, "t": 0.0})
		_:
			_sfx_queue.append({"freq": 440.0, "freq2": 330.0, "noise": 0.20, "dur": 0.08, "gain": 0.20, "t": 0.0})


func _randf_fast() -> float:
	_noise_seed = (_noise_seed * 1664525 + 1013904223) & 0x7fffffff
	return (float(_noise_seed & 0xffff) / 32768.0) - 1.0


func _process(_delta: float) -> void:
	if _amb_playback != null:
		var frames := mini(_amb_playback.get_frames_available(), 512)
		var rain_cut := 0.08 if _indoors else 0.24
		var rain_gain := _rain_level * (0.09 if _indoors else 0.18) * master_vol
		var water_gain := _water_level * (0.05 if _indoors else 0.13) * master_vol
		for _i in range(frames):
			var sample := 0.0
			if not muted and (rain_gain > 0.001 or water_gain > 0.001):
				var n := _randf_fast()
				_lp_rain += (n - _lp_rain) * rain_cut
				_lp_water += (n - _lp_water) * 0.045
				_phase += 0.00035
				var wave := 0.75 + 0.25 * sin(_phase)
				sample = _lp_rain * rain_gain + _lp_water * water_gain * wave
			_amb_playback.push_frame(Vector2(sample, sample))

	if _sfx_playback != null:
		var sframes := mini(_sfx_playback.get_frames_available(), 512)
		var dt := 1.0 / MIX_RATE
		for _i in range(sframes):
			var out := 0.0
			if not muted and not _sfx_queue.is_empty():
				var kept: Array[Dictionary] = []
				for s: Dictionary in _sfx_queue:
					var t: float = float(s["t"])
					var dur: float = float(s["dur"])
					if t >= dur:
						continue
					var env := (1.0 - t / dur)
					env = env * env
					var f: float = lerpf(float(s["freq"]), float(s["freq2"]), t / dur)
					var tone := sin(TAU * f * t)
					var n := _randf_fast()
					var mix: float = lerpf(tone, n, float(s["noise"]))
					out += mix * env * float(s["gain"]) * master_vol
					s["t"] = t + dt
					kept.append(s)
				_sfx_queue = kept
			out = clampf(out, -0.75, 0.75)
			_sfx_playback.push_frame(Vector2(out, out))
