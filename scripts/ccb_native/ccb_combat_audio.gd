extends Node

# Realistic 44.1 kHz Stereo Polyphonic Combat Audio Engine for embedded real CCB:
# - Dedicated "CcbCombat" AudioServer bus with Compressor + Soft Limiter (ZERO clipping on 30-round full-auto / chain blasts!)
# - 28-voice polyphonic AudioStreamPlayer pool (never cuts off decay tails of preceding rounds!)
# - High-precision burst/full-auto timeline scheduler keyed on CCB's exact burst_id, shot_index & cyclic RPM:
#   * Seamless continuous cyclic firing cadence with subtle ±3.5ms organic bolt-cycle jitter
#   * Tightened mid-burst body tails (0.58x) while letting the FINAL round of every burst ring out naturally!
#   * 3 unique synthesized acoustic variations round-robined per firearm + pitch micro-drift (zero machine-gun roboticism!)
#   * Delayed stereo brass shell-casing clinks (+280..410ms)

const BUS_NAME := &"CcbCombat"
const SAMPLE_RATE := 44100
const VOICE_POOL_SIZE := 28
const MAX_WAV_CACHE := 96

const SFX_GUNSHOT := 1
const SFX_VARIANT := 6

const VAR_SHELL_CASING := 10
const AUDIO_FLAG_INDOORS := 0x01
const AUDIO_FLAG_DISTANT := 0x02
const AUDIO_FLAG_SUPPRESSED := 0x04
const AUDIO_FLAG_HAS_CASING := 0x08

var muted := false
var _engine: RefCounted
var _headless := false
var _voices: Array[AudioStreamPlayer] = []
var _voice_start_time: PackedFloat64Array = PackedFloat64Array()
var _wav_cache: Dictionary = {} # "k|sub|var|ind|tail" -> AudioStreamWAV
var _wav_lru: Dictionary = {}   # key -> last used _clock (LRU eviction!)
var _pending: Array = []        # Scheduled future audio events (burst rounds, casings, impacts)
var _burst_t0: Dictionary = {}  # burst_id -> float wall_time_sec
var _burst_max_shot: Dictionary = {} # burst_id -> highest shot_index queued in this burst
var _last_audio_id := 0
var _last_single_gun_t := -10.0
var _clock := 0.0
var _rr_counter := 0

# Telemetry for automated & visual verification
var total_events_received := 0
var total_gunshots_played := 0
var last_burst_shot_times: Array[float] = []
var last_burst_id_seen := 0


func setup(ccb_engine: RefCounted) -> void:
	_engine = ccb_engine
	_headless = DisplayServer.get_name() == "headless"
	_ensure_combat_bus()
	if _voices.is_empty() and not _headless:
		_voice_start_time.resize(VOICE_POOL_SIZE)
		for i in range(VOICE_POOL_SIZE):
			var p := AudioStreamPlayer.new()
			p.bus = BUS_NAME
			p.max_polyphony = 1
			add_child(p)
			_voices.append(p)
			_voice_start_time[i] = -100.0
	set_process(true)


func toggle_mute() -> bool:
	muted = not muted
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)
	return muted


func _ensure_combat_bus() -> void:
	if _headless:
		return
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, BUS_NAME)
		AudioServer.set_bus_send(idx, &"Master")
		# Glue rapid full-auto bursts smoothly & prevent any digital clipping on simultaneous explosions
		var comp := AudioEffectCompressor.new()
		comp.threshold = -9.0
		comp.ratio = 4.2
		comp.attack_us = 600.0
		comp.release_ms = 85.0
		comp.gain = 2.2
		AudioServer.add_bus_effect(idx, comp)

		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -0.8
		lim.threshold_db = -2.2
		lim.soft_clip_db = 2.5
		AudioServer.add_bus_effect(idx, lim)
	AudioServer.set_bus_mute(idx, muted)


func _get_or_build_wav(kind: int, subtype: int, variant: int, space_mode: int, distant: bool, tail_scale: float) -> AudioStreamWAV:
	var tbucket := int(round(clampf(tail_scale, 0.4, 1.1) * 10.0))
	var key := "%d|%d|%d|%d|%d|%d" % [kind, subtype, variant, space_mode, 1 if distant else 0, tbucket]
	var cached = _wav_cache.get(key)
	if cached != null:
		_wav_lru[key] = _clock
		return cached
	if _engine == null:
		return null
	var pcm := PackedByteArray()
	var mix_rate := SAMPLE_RATE
	var is_stereo := true
	if _engine.has_method("synthesize_combat_audio"):
		var spec: Dictionary = _engine.synthesize_combat_audio(kind, subtype, variant, space_mode, distant, float(tbucket) * 0.1)
		pcm = spec.get("pcm", PackedByteArray())
		mix_rate = int(spec.get("mix_rate", SAMPLE_RATE))
		is_stereo = bool(spec.get("stereo", true))
	elif _engine.has_method("synthesize_combat_pcm"):
		pcm = _engine.synthesize_combat_pcm(kind, subtype, variant, space_mode, distant, float(tbucket) * 0.1)
	if pcm.is_empty():
		return null
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = is_stereo
	wav.data = pcm
	if _wav_cache.size() >= MAX_WAV_CACHE:
		var oldest_k := ""
		var oldest_t := 1e18
		for k in _wav_cache:
			var t := float(_wav_lru.get(k, -1.0))
			if t < oldest_t:
				oldest_t = t
				oldest_k = k
		if not oldest_k.is_empty():
			_wav_cache.erase(oldest_k)
			_wav_lru.erase(oldest_k)
	_wav_cache[key] = wav
	_wav_lru[key] = _clock
	return wav


func ingest_events(events: Array) -> void:
	if events.is_empty():
		return
	for e_var in events:
		var ev: Dictionary = e_var
		var eid := int(ev.get("id", 0))
		if eid <= _last_audio_id:
			continue
		_last_audio_id = eid
		total_events_received += 1

		var kind := int(ev.get("kind", 0))
		if kind != SFX_GUNSHOT:
			continue
		var subtype := int(ev.get("subtype", 1))
		var burst_id := int(ev.get("burst_id", 0))
		var shot_index := int(ev.get("shot_index", 0))
		var delay_s := float(int(ev.get("delay_ms", 0))) * 0.001
		var vol := clampf(float(ev.get("volume", 0.9)), 0.05, 1.25)
		var pan := clampf(float(ev.get("pan", 0.0)), -1.0, 1.0)
		var flags := int(ev.get("flags", 0))
		var z_lvl := int(ev.get("z", 0))
		var space_mode := 2 if z_lvl < 0 else (1 if (flags & AUDIO_FLAG_INDOORS) != 0 else 0)

		var due_t := _clock + delay_s
		if kind == SFX_GUNSHOT:
			if burst_id > 0:
				if not _burst_t0.has(burst_id):
					# Anchor burst origin to current clock (or slightly after last single tap to avoid collision)
					var anchor := maxf(_clock, _last_single_gun_t + 0.048)
					_burst_t0[burst_id] = anchor
					_burst_max_shot[burst_id] = shot_index
					if _burst_t0.size() > 32:
						_burst_t0.clear()
						_burst_max_shot.clear()
						_burst_t0[burst_id] = anchor
						_burst_max_shot[burst_id] = shot_index
				else:
					_burst_max_shot[burst_id] = maxi(int(_burst_max_shot.get(burst_id, 0)), shot_index)
				# Organic ±3.5ms gas-piston jitter so bursts sound like real mechanical firearms!
				var jitter := (float(((eid * 2654435761) >> 8) & 255) / 255.0 - 0.5) * 0.007
				due_t = float(_burst_t0[burst_id]) + delay_s + (jitter if shot_index > 0 else 0.0)
			else:
				due_t = maxf(_clock, _last_single_gun_t + 0.048)
				_last_single_gun_t = due_t

			# Schedule dry brass shell casing drop ~310..420ms after the shot (quieter outdoors on soil/grass!)
			if (flags & AUDIO_FLAG_HAS_CASING) != 0:
				var casing_delay := 0.30 + float((eid * 1103515245 + 12345) & 127) / 127.0 * 0.13
				_pending.append({
					"due": due_t + casing_delay,
					"kind": SFX_VARIANT,
					"subtype": VAR_SHELL_CASING,
					"volume": vol * (0.22 if space_mode == 0 else 0.34),
					"pan": clampf(pan + 0.35, -1.0, 1.0),
					"flags": flags,
					"space_mode": space_mode,
					"burst_id": 0,
					"shot_index": shot_index,
					"eid": eid + 100000,
				})

		_pending.append({
			"due": due_t,
			"kind": kind,
			"subtype": subtype,
			"volume": vol,
			"pan": pan,
			"flags": flags,
			"space_mode": space_mode,
			"burst_id": burst_id,
			"shot_index": shot_index,
			"eid": eid,
		})

	while _pending.size() > 160:
		_pending.pop_front()


func _process(delta: float) -> void:
	_clock += clampf(delta, 0.0, 0.05)
	if _pending.is_empty():
		return
	var remaining: Array = []
	for item_var in _pending:
		var item: Dictionary = item_var
		if float(item["due"]) <= _clock + 0.002:
			_fire_voice(item)
		else:
			remaining.append(item)
	_pending = remaining


func _fire_voice(item: Dictionary) -> void:
	var kind := int(item["kind"])
	var subtype := int(item["subtype"])
	var flags := int(item["flags"])
	var space_mode := int(item.get("space_mode", 1 if (flags & AUDIO_FLAG_INDOORS) != 0 else 0))
	var distant := (flags & AUDIO_FLAG_DISTANT) != 0
	var vol := float(item["volume"])
	var burst_id := int(item["burst_id"])
	var shot_index := int(item["shot_index"])
	var eid := int(item["eid"])

	if kind == SFX_GUNSHOT:
		total_gunshots_played += 1
		_last_single_gun_t = maxf(_last_single_gun_t, _clock)
		if burst_id > 0:
			if burst_id != last_burst_id_seen:
				last_burst_id_seen = burst_id
				last_burst_shot_times.clear()
			last_burst_shot_times.append(_clock)

	if muted or _headless or _voices.is_empty():
		return

	# Burst tail continuity: tighten mid-burst tails slightly (0.60x) so rapid full-auto stays crisp & punchy
	# while STILL overlapping smoothly, and let the FINAL round of every burst ring out with full space tail!
	var tail_scale := 1.0
	var gain_db_offset := 0.0
	if kind == SFX_GUNSHOT and burst_id > 0:
		var max_shot := int(_burst_max_shot.get(burst_id, shot_index))
		var is_mid_burst := shot_index < max_shot
		if is_mid_burst:
			tail_scale = 0.60
			if shot_index > 0:
				gain_db_offset = -1.1
		else:
			tail_scale = 1.0

	_rr_counter = (_rr_counter + 1) % 3
	var variant := _rr_counter
	var wav := _get_or_build_wav(kind, subtype, variant, space_mode, distant, tail_scale)
	if wav == null:
		return

	# Pick a free voice (NEVER cut off an active attack; only steal the oldest decay tail if all 28 are busy!)
	var chosen := -1
	var oldest_idx := 0
	var oldest_t := 1e18
	for i in range(_voices.size()):
		if not _voices[i].playing:
			chosen = i
			break
		if _voice_start_time[i] < oldest_t:
			oldest_t = _voice_start_time[i]
			oldest_idx = i
	if chosen < 0:
		chosen = oldest_idx

	var player := _voices[chosen]
	player.stream = wav
	var dist_db := -3.5 if distant else 0.0
	var base_db := linear_to_db(clampf(vol * 0.92, 0.03, 1.25)) + gain_db_offset + dist_db
	player.volume_db = clampf(base_db, -30.0, 2.5)
	# Organic per-shot pitch micro-variation (±3%) prevents robotic phasing during rapid bursts
	var p_hash := float(((eid * 1664525 + 1013904223) >> 8) & 255) / 255.0
	player.pitch_scale = (0.97 + p_hash * 0.06) if kind == SFX_GUNSHOT else (0.95 + p_hash * 0.10)
	_voice_start_time[chosen] = _clock
	player.play()
