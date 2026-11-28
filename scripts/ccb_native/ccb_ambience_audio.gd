extends Node

# P1.1 Multi-Layer Real-Time Procedural Stereo Ambience Bed + P1.2 Material Footsteps & Spatial World Audio:
# - 8 seamlessly crossfaded 44.1 kHz stereo procedural ambience loops (synthesized on-demand in C++, 0 external assets!):
#   0=wind_open, 1=wind_forest, 2=rain_outdoor, 3=rain_indoor (muffled roof rain!),
#   4=night_crickets, 5=day_birds, 6=underground_cavern, 7=fire_crackle (spatial proximity!)
# - Physically delayed rolling thunder rumbles synchronized to thunderstorm lightning flashes (0.8..3.1s delay!)
# - Occasional cavernous water drips when underground
# - 8-material physical footsteps (grass, wood, metal, glass, water splash, stone/concrete, dirt, snow crunch!)
#   scaled dynamically by crouch/walk/run movement mode & indoor/outdoor/underground acoustics!

const BUS_NAME := &"CcbAmbience"
const SAMPLE_RATE := 22050
const LAYER_COUNT := 8
const SFX_POOL_SIZE := 8
const MAX_SFX_CACHE := 48
const LOOP_IDLE_UNLOAD_SEC := 45.0

const SFX_FOOTSTEP := 5
const SFX_VARIANT := 6
const VAR_DOOR := 8
const VAR_THUNDER := 11
const VAR_DRIP := 12
const VAR_GLASS_BREAK := 13

var muted := false
var active_in_world := false
var _engine: RefCounted
var _headless := false

var _loop_players: Array[AudioStreamPlayer] = []
var _loop_loaded: PackedByteArray = PackedByteArray()
var _loop_silent_sec: PackedFloat32Array = PackedFloat32Array()
var _cur_gains: PackedFloat32Array = PackedFloat32Array()
var _tgt_gains: PackedFloat32Array = PackedFloat32Array()

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_rr := 0
var _sfx_cache: Dictionary = {}
var _sfx_lru: Dictionary = {}
var _pending_oneshots: Array = []

var _clock := 0.0
var _drip_timer := 6.0
var _thunder_timer := 5.5
var _is_underground := false
var _is_thunder := false
var _player_indoors := false
var _last_player_pos := Vector2i(-99999, -99999)
var _last_player_z := -999
var _step_counter := 0

# Telemetry for verification
var footsteps_triggered := 0
var last_footstep_mat := -1
var active_layer_gains: Array[float] = []


func setup(ccb_engine: RefCounted) -> void:
	_engine = ccb_engine
	_headless = DisplayServer.get_name() == "headless"
	_ensure_bus()
	if _loop_players.is_empty():
		_loop_loaded.resize(LAYER_COUNT)
		_loop_loaded.fill(0)
		_loop_silent_sec.resize(LAYER_COUNT)
		_loop_silent_sec.fill(0.0)
		_cur_gains.resize(LAYER_COUNT)
		_cur_gains.fill(0.0)
		_tgt_gains.resize(LAYER_COUNT)
		_tgt_gains.fill(0.0)
		active_layer_gains.resize(LAYER_COUNT)
		active_layer_gains.fill(0.0)
		if not _headless:
			for i in range(LAYER_COUNT):
				var p := AudioStreamPlayer.new()
				p.bus = BUS_NAME
				p.volume_db = -80.0
				add_child(p)
				_loop_players.append(p)
			for i in range(SFX_POOL_SIZE):
				var sp := AudioStreamPlayer.new()
				sp.bus = BUS_NAME
				add_child(sp)
				_sfx_players.append(sp)
	set_process(true)


func set_muted(m: bool) -> void:
	muted = m
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)


func set_in_world(in_world: bool) -> void:
	active_in_world = in_world
	if not in_world:
		for i in range(LAYER_COUNT):
			_tgt_gains[i] = 0.0
		_last_player_pos = Vector2i(-99999, -99999)


func _ensure_bus() -> void:
	if _headless:
		return
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, BUS_NAME)
		AudioServer.set_bus_send(idx, &"Master")
		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -2.0
		lim.threshold_db = -4.0
		AudioServer.add_bus_effect(idx, lim)
	AudioServer.set_bus_mute(idx, muted)


func _ensure_layer_stream(layer_id: int) -> bool:
	if _headless or layer_id < 0 or layer_id >= LAYER_COUNT:
		return false
	if _loop_loaded[layer_id] != 0:
		_loop_silent_sec[layer_id] = 0.0
		return true
	if _engine == null:
		return false
	var pcm := PackedByteArray()
	var mix_rate := SAMPLE_RATE
	var is_stereo := true
	if _engine.has_method("synthesize_ambience_loop"):
		var spec: Dictionary = _engine.synthesize_ambience_loop(layer_id)
		pcm = spec.get("pcm", PackedByteArray())
		mix_rate = int(spec.get("mix_rate", SAMPLE_RATE))
		is_stereo = bool(spec.get("stereo", true))
	elif _engine.has_method("synthesize_ambience_loop_pcm"):
		pcm = _engine.synthesize_ambience_loop_pcm(layer_id)
		mix_rate = 44100
		is_stereo = true
	if pcm.is_empty():
		return false
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = is_stereo
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	var frame_bytes := 4 if is_stereo else 2
	@warning_ignore("integer_division")
	wav.loop_end = pcm.size() / frame_bytes
	wav.data = pcm
	_loop_players[layer_id].stream = wav
	_loop_loaded[layer_id] = 1
	_loop_silent_sec[layer_id] = 0.0
	return true


func _get_oneshot_wav(kind: int, subtype: int, variant: int, space_mode: int, distant: bool) -> AudioStreamWAV:
	var key := "%d|%d|%d|%d|%d" % [kind, subtype, variant, space_mode, 1 if distant else 0]
	var cached = _sfx_cache.get(key)
	if cached != null:
		_sfx_lru[key] = _clock
		return cached
	if _engine == null:
		return null
	var pcm := PackedByteArray()
	var mix_rate := SAMPLE_RATE
	var is_stereo := true
	if _engine.has_method("synthesize_combat_audio"):
		var spec: Dictionary = _engine.synthesize_combat_audio(kind, subtype, variant, space_mode, distant, 1.0)
		pcm = spec.get("pcm", PackedByteArray())
		mix_rate = int(spec.get("mix_rate", SAMPLE_RATE))
		is_stereo = bool(spec.get("stereo", true))
	elif _engine.has_method("synthesize_combat_pcm"):
		pcm = _engine.synthesize_combat_pcm(kind, subtype, variant, space_mode, distant, 1.0)
		mix_rate = 44100
		is_stereo = true
	if pcm.is_empty():
		return null
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = is_stereo
	wav.data = pcm
	if _sfx_cache.size() >= MAX_SFX_CACHE:
		var oldest_k := ""
		var oldest_t := 1e18
		for k in _sfx_cache:
			var t := float(_sfx_lru.get(k, -1.0))
			if t < oldest_t:
				oldest_t = t
				oldest_k = k
		if not oldest_k.is_empty():
			_sfx_cache.erase(oldest_k)
			_sfx_lru.erase(oldest_k)
	_sfx_cache[key] = wav
	_sfx_lru[key] = _clock
	return wav


func _play_oneshot(kind: int, subtype: int, vol: float, space_mode: int, distant := false, pitch_var := 0.08) -> void:
	if muted or _headless or _sfx_players.is_empty():
		return
	var variant := _sfx_rr % 3
	_sfx_rr += 1
	var wav := _get_oneshot_wav(kind, subtype, variant, space_mode, distant)
	if wav == null:
		return
	var p := _sfx_players[_sfx_rr % _sfx_players.size()]
	p.stream = wav
	p.volume_db = clampf(linear_to_db(clampf(vol, 0.02, 1.2)), -32.0, 1.0)
	p.pitch_scale = 1.0 + (fmod(float(_sfx_rr * 73 + int(_clock * 100.0)), 100.0) / 100.0 - 0.5) * pitch_var
	p.play()


func trigger_lightning_thunder(distance_norm := 0.5) -> void:
	if not active_in_world or _is_underground:
		return
	var d := clampf(distance_norm, 0.0, 1.0)
	var delay := lerpf(0.75, 3.1, d)
	var vol := lerpf(0.82, 0.34, d) * (0.58 if _player_indoors else 1.0)
	_pending_oneshots.append({
		"due": _clock + delay,
		"kind": SFX_VARIANT,
		"subtype": VAR_THUNDER,
		"vol": vol,
		"space_mode": 1 if _player_indoors else 0,
		"distant": d > 0.45,
	})


func on_world_snapshot(snap: Dictionary, bundle: Dictionary) -> void:
	if not bool(snap.get("valid", false)):
		set_in_world(false)
		return
	active_in_world = true

	var is_under := bool(snap.get("is_underground", false)) or int(snap.get("z", 0)) < 0
	var indoors := bool(snap.get("player_indoors", false))
	var wind_spd := clampf(float(snap.get("wind_speed", 4.0)), 0.0, 50.0)
	var tree_dens := clampf(float(snap.get("tree_density", 0.0)), 0.0, 1.0)
	var season_i := clampi(int(snap.get("season", 0)), 0, 3)
	var rain := clampf(float(bundle.get("rain", 0.0)), 0.0, 1.0)
	var snow := clampf(float(bundle.get("snow", 0.0)), 0.0, 1.0)
	var wetness := clampf(float(bundle.get("wetness", 0.0)), 0.0, 1.0)
	var snow_cov := clampf(float(bundle.get("snow_cover", 0.0)), 0.0, 1.0)
	var daylight := clampf(float(bundle.get("daylight", 0.8)), 0.0, 1.0)
	var wid := str(snap.get("weather", "")).to_lower()

	_is_underground = is_under
	_player_indoors = indoors
	_is_thunder = (not is_under) and (rain >= 0.85 or "thunder" in wid or "lightning" in wid)

	# Compute realistic target gains for all 8 procedural ambience beds!
	var wind_n := clampf(0.14 + (wind_spd / 28.0) * 0.86, 0.12, 1.0)
	if is_under:
		_tgt_gains[0] = 0.0
		_tgt_gains[1] = 0.0
		_tgt_gains[2] = 0.0
		_tgt_gains[3] = 0.0
		_tgt_gains[4] = 0.0
		_tgt_gains[5] = 0.0
		_tgt_gains[6] = 0.34 # Deep subterranean room tone & airflow
	else:
		# Open air wind (gently muffled when indoors)
		_tgt_gains[0] = wind_n * (0.11 if indoors else 0.30) * (1.0 + snow * 0.35 + rain * 0.25)
		# Forest tree canopy rustle (proportional to nearby tree density * wind!)
		_tgt_gains[1] = tree_dens * wind_n * (0.05 if indoors else 0.32)
		# Rain outdoor sheet vs cozy muffled indoor roof rain!
		_tgt_gains[2] = 0.0 if indoors else (rain * 0.44)
		_tgt_gains[3] = (rain * 0.34) if indoors else 0.0
		# Night crickets (warm seasons, outdoors/near-open, not heavy storm)
		var night_w := clampf((0.42 - daylight) / 0.35, 0.0, 1.0)
		var warm_season := 0.0 if season_i == 3 else (0.55 if season_i == 2 else 1.0)
		var storm_damp := clampf(1.0 - rain * 1.4 - snow * 1.5, 0.0, 1.0)
		_tgt_gains[4] = night_w * warm_season * storm_damp * (0.04 if indoors else 0.16)
		# Sparse distant daytime forest birds (clear/cloudy daylight in forest!)
		var day_w := clampf((daylight - 0.38) / 0.35, 0.0, 1.0)
		_tgt_gains[5] = day_w * maxf(tree_dens, 0.15) * warm_season * storm_damp * (0.03 if indoors else 0.22)
		_tgt_gains[6] = 0.0

	# Spatial proximity fire crackle from active fire emitters (campfires, braziers, burning houses!)
	var ppos: Vector2i = snap.get("player", Vector2i.ZERO)
	var best_fire := 0.0
	var lights: Array = snap.get("lights", [])
	for l_var in lights:
		var ld: Dictionary = l_var
		if (int(ld.get("flags", 0)) & 1) == 0:
			continue
		var dist := Vector2(float(int(ld.get("x", 0)) - ppos.x), float(int(ld.get("y", 0)) - ppos.y)).length()
		if dist < 13.0:
			var att := clampf(1.0 - dist / 13.0, 0.0, 1.0)
			best_fire = maxf(best_fire, att * att * clampf(float(ld.get("intensity", 6.0)) / 10.0, 0.45, 1.2))
	_tgt_gains[7] = clampf(best_fire * 0.46, 0.0, 0.50)

	# P1.2 Material-accurate Footsteps on every player step!
	var pz := int(snap.get("z", 0))
	if _last_player_pos.x > -90000 and pz == _last_player_z and ppos != _last_player_pos:
		var step_d := Vector2(ppos - _last_player_pos).length()
		if step_d >= 0.8 and step_d <= 2.2:
			_step_counter += 1
			var mat_id := clampi(int(snap.get("player_mat_id", 6)), 0, 6)
			if not indoors and not is_under:
				if snow_cov >= 0.45 and mat_id != 4:
					mat_id = 7 # Crisp snow crunch!
				elif wetness >= 0.72 and mat_id == 6 and (_step_counter % 3 == 0):
					mat_id = 4 # Rain puddle wet splash!
			var move_mode := clampi(int(snap.get("player_move_mode", 1)), 0, 2) # 0=crouch, 1=walk, 2=run
			var vol := 0.16 if move_mode == 0 else (0.58 if move_mode == 2 else 0.34)
			var space_mode := 2 if is_under else (1 if indoors else 0)
			footsteps_triggered += 1
			last_footstep_mat = mat_id
			_play_oneshot(SFX_FOOTSTEP, mat_id, vol, space_mode, false, 0.14)
	_last_player_pos = ppos
	_last_player_z = pz


func _process(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.05)
	_clock += dt

	# Smoothly crossfade all 8 stereo ambience layers (lazy-loads PCM only when a layer becomes audible!)
	var rate := 1.0 - exp(-2.8 * dt)
	for i in range(LAYER_COUNT):
		var tgt := _tgt_gains[i] if (active_in_world and not muted) else 0.0
		var cur := lerpf(_cur_gains[i], tgt, rate)
		if cur < 0.002 and tgt < 0.002:
			cur = 0.0
		_cur_gains[i] = cur
		active_layer_gains[i] = cur
		if not _headless and i < _loop_players.size():
			var pl := _loop_players[i]
			if cur > 0.004:
				if _ensure_layer_stream(i):
					if not pl.playing:
						pl.play(fmod(_clock * 1.3 + float(i) * 0.7, 3.2))
					pl.volume_db = clampf(linear_to_db(cur), -60.0, -2.0)
			else:
				if pl.playing:
					pl.stop()
				if _loop_loaded[i] != 0:
					_loop_silent_sec[i] += dt
					if _loop_silent_sec[i] >= LOOP_IDLE_UNLOAD_SEC:
						pl.stream = null
						_loop_loaded[i] = 0
						_loop_silent_sec[i] = 0.0

	# Periodic underground cavern water drips & standalone 2D thunderstorm rolling thunder
	if active_in_world and not muted:
		if _is_underground:
			_drip_timer -= dt
			if _drip_timer <= 0.0:
				_drip_timer = 7.0 + fmod(_clock * 3.7, 9.0)
				_play_oneshot(SFX_VARIANT, VAR_DRIP, 0.24, 2, false, 0.24)
		if _is_thunder:
			_thunder_timer -= dt
			if _thunder_timer <= 0.0:
				_thunder_timer = 7.5 + fmod(_clock * 4.3, 11.0)
				trigger_lightning_thunder(fmod(_clock * 0.37, 0.85))

	# Fire delayed one-shots (e.g. lightning -> delayed thunderclap!)
	if not _pending_oneshots.is_empty():
		var rem: Array = []
		for o_var in _pending_oneshots:
			var o: Dictionary = o_var
			if float(o["due"]) <= _clock:
				_play_oneshot(int(o["kind"]), int(o["subtype"]), float(o["vol"]), int(o["space_mode"]), bool(o["distant"]), 0.10)
			else:
				rem.append(o)
		_pending_oneshots = rem
