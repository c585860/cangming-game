extends RefCounted

# Living, Bustling Jiangnan Water-Town Ecosystem for Cangling City (沧灵城)
# Matches user reference imagery (Image 1 & Image 3):
# 1. 12 WATER-LOCKED HIGH-DETAIL BOATS in 3 classic Yangzhou classes:
#    - imperial_huafang (金瓦画舫): Imperial yellow-gold glazed curved tile roof with upturned eaves,
#      vermilion lacquered pillars, gold-trimmed dark timber hull, interior seated passengers, foam wakes!
#    - red_canopy (红篷游船): Warm terracotta-crimson arched canopy, crimson pillars, seated passengers,
#      straw-hat boatman sculling at stern, bow lantern!
#    - wupeng (江南乌篷船): Dark planked cedar hull, 3D woven bamboo hood, indigo-robed sculling boatman!
#    ALWAYS validated against world.terrain_at_level() so boats NEVER touch land and glide cleanly under bridges!
# 2. GOLDEN-GLAZED FIVE-PAVILION BRIDGE ROOFS (五亭桥重檐金瓦五亭 — Image 1!):
#    - 5 ornate upturned imperial-gold glazed pavilions linked by crimson-pillared covered corridors right
#      above Five-Pavilion Bridge (fading smoothly when the player walks onto the bridge!).
# 3. LIVING CITY BIRD ECOSYSTEM (NO meaningless floating screen dots!):
#    - Periodic wild geese flocks (大雁人字阵) arriving naturally every 30-55s.
#    - 6 autonomous sparrow flocks (麻雀群) perching/pecking on landmarks, flushing when player nears.
#    - 2 waterfront egrets (白鹭) gliding between willow riverbanks.
# 4. GOLDEN WATERFRONT LANTERN REFLECTIONS (Image 3) + Shop Banners, Plaques, Smoke & Forge Sparks.

const JADE_LOOP_PTS := [
	Vector2(84, 58), Vector2(100, 69), Vector2(120, 72), Vector2(144, 70), Vector2(164, 80),
	Vector2(172, 98), Vector2(166, 120), Vector2(154, 138), Vector2(155, 158), Vector2(162, 174),
	Vector2(156, 192), Vector2(135, 196), Vector2(120, 193), Vector2(98, 196), Vector2(74, 188),
	Vector2(62, 168), Vector2(54, 144), Vector2(65, 120), Vector2(58, 96), Vector2(61, 70),
]

# Quiet moored wooden rowboats gently bobbing beside residential water-steps on the 3 clean creeks
const MOORED_SKIFFS := [
	{"pos": Vector2(130.0, 174.5), "dir": Vector2(1.0, 0.05), "phase": 0.4}, # 南水弄 south of 醉仙楼
	{"pos": Vector2(106.0, 174.5), "dir": Vector2(-1.0, 0.0), "phase": 1.7}, # 南水弄 south of 王记铁匠铺
	{"pos": Vector2(84.0, 174.5),  "dir": Vector2(1.0, 0.08), "phase": 2.9}, # 西南南水弄
	{"pos": Vector2(46.0, 145.5),  "dir": Vector2(-1.0, 0.1), "phase": 4.1}, # 西水弄
	{"pos": Vector2(193.5, 108.0), "dir": Vector2(0.0, 1.0),  "phase": 0.9}, # 仁丰里东水弄
	{"pos": Vector2(194.0, 134.0), "dir": Vector2(0.0, -1.0), "phase": 3.3}, # 东水弄 behind 春风茶馆
	{"pos": Vector2(193.5, 165.0), "dir": Vector2(0.0, 1.0),  "phase": 5.0}, # 东关水市东水弄
	{"pos": Vector2(40.0, 62.0),   "dir": Vector2(0.8, -0.5), "phase": 2.2}, # 翠微湖 lotus cove
]

const SPARROW_PERCHES := [
	Vector2(120.0, 120.5),
	Vector2(120.0, 193.0),
	Vector2(126.0, 157.0),
	Vector2(167.0, 166.0),
	Vector2(130.0, 113.0),
	Vector2(100.0, 126.0),
	Vector2(166.0, 120.0),
	Vector2(61.0, 51.5),
	Vector2(120.0, 88.0),
	Vector2(178.0, 126.0),
]

const EGRET_SHORES := [
	Vector2(86.0, 60.0), Vector2(150.0, 154.0), Vector2(162.0, 188.0),
	Vector2(60.0, 166.0), Vector2(56.0, 98.0), Vector2(42.0, 42.0),
]

const SHOP_BANNERS := [
	{"pos": Vector2(121.6, 157.0), "char": "酒", "bg": Color("8e221b"), "trim": Color("e8c468")},
	{"pos": Vector2(117.4, 157.0), "char": "铁", "bg": Color("32363d"), "trim": Color("de9c50")},
	{"pos": Vector2(117.4, 130.0), "char": "当", "bg": Color("243856"), "trim": Color("e4c26a")},
	{"pos": Vector2(130.0, 117.6), "char": "药", "bg": Color("1f5843"), "trim": Color("e0ca7c")},
	{"pos": Vector2(138.0, 117.6), "char": "钱", "bg": Color("5e451e"), "trim": Color("f0cf72")},
	{"pos": Vector2(136.0, 121.6), "char": "杂", "bg": Color("4a4035"), "trim": Color("dfc584")},
	{"pos": Vector2(100.0, 121.6), "char": "武", "bg": Color("74271e"), "trim": Color("edc86e")},
	{"pos": Vector2(101.0, 117.6), "char": "镖", "bg": Color("5b2421"), "trim": Color("e8c468")},
	{"pos": Vector2(117.4, 109.0), "char": "宿", "bg": Color("7d3821"), "trim": Color("ecc974")},
	{"pos": Vector2(177.0, 121.6), "char": "茶", "bg": Color("2c5c35"), "trim": Color("e7d084")},
]

const LANDMARK_PLAQUES := [
	{"pos": Vector2(127.0, 157.0), "title": "醉 仙 楼"},
	{"pos": Vector2(110.0, 157.0), "title": "王记铁匠铺"},
	{"pos": Vector2(113.0, 130.0), "title": "利 源 当 铺"},
	{"pos": Vector2(126.0, 130.0), "title": "英 雄 祠"},
	{"pos": Vector2(130.0, 113.0), "title": "回春堂药铺"},
	{"pos": Vector2(138.5, 113.0), "title": "通 济 钱 庄"},
	{"pos": Vector2(136.0, 125.5), "title": "福兴杂货铺"},
	{"pos": Vector2(105.0, 126.5), "title": "扬 威 武 馆"},
	{"pos": Vector2(101.5, 112.5), "title": "镇 远 镖 局"},
	{"pos": Vector2(112.5, 108.5), "title": "悦 来 客 栈"},
	{"pos": Vector2(120.0, 88.0),  "title": "文 昌 阁"},
	{"pos": Vector2(130.5, 89.0),  "title": "文 昌 书 院"},
	{"pos": Vector2(177.5, 126.0), "title": "春 风 茶 馆"},
	{"pos": Vector2(120.0, 38.0),  "title": "沧 灵 府 衙"},
	{"pos": Vector2(61.0, 48.0),   "title": "五 亭 桥"},
]

const SMOKE_VENTS := [
	{"pos": Vector2(129.5, 154.2), "kind": "smoke"},
	{"pos": Vector2(110.5, 106.2), "kind": "smoke"},
	{"pos": Vector2(180.5, 124.2), "kind": "smoke"},
	{"pos": Vector2(114.5, 153.4), "kind": "forge"},
	{"pos": Vector2(114.5, 160.4), "kind": "forge"},
]

const NPC_LABELS := {
	&"innkeeper": "冼老板 · 醉仙楼",
	&"blacksmith": "王铁匠 · 铁匠铺",
	&"herbalist": "平大夫 · 回春堂",
	&"martial_master": "陈馆主 · 扬威武馆",
	&"weapon_coach": "周教头 · 兵器堂",
	&"scholar": "顾夫子 · 文昌书院",
	&"pawnbroker": "唐掌柜 · 利源当铺",
	&"boatman": "老船夫 · 码头",
	&"storyteller": "说书先生 · 茶馆",
}

var time := 0.0
var _rng := RandomNumberGenerator.new()
var _spline_samples: PackedVector2Array = PackedVector2Array()
var _spline_cumlen: PackedFloat32Array = PackedFloat32Array()
var _spline_total_len := 1.0

var boats: Array[Dictionary] = []
var geese_flocks: Array[Dictionary] = []
var _next_geese_timer := 12.0
var sparrow_flocks: Array[Dictionary] = []
var egrets: Array[Dictionary] = []


func _init() -> void:
	_rng.seed = 20261126
	_build_jade_spline()
	_setup_boats()
	_setup_sparrows()
	_setup_egrets()


func _build_jade_spline() -> void:
	_spline_samples.clear()
	_spline_cumlen.clear()
	var n := JADE_LOOP_PTS.size()
	var steps_per_seg := 20
	var total := 0.0
	var prev := Vector2.ZERO
	var has_prev := false
	for s in range(n):
		var p0: Vector2 = JADE_LOOP_PTS[(s - 1 + n) % n]
		var p1: Vector2 = JADE_LOOP_PTS[s]
		var p2: Vector2 = JADE_LOOP_PTS[(s + 1) % n]
		var p3: Vector2 = JADE_LOOP_PTS[(s + 2) % n]
		for k in range(steps_per_seg):
			var t := float(k) / float(steps_per_seg)
			var t2 := t * t
			var t3 := t2 * t
			var pt := 0.5 * ((2.0 * p1) + (-p0 + p2) * t +
				(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
				(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			if has_prev:
				total += prev.distance_to(pt)
			_spline_samples.append(pt)
			_spline_cumlen.append(total)
			prev = pt
			has_prev = true
	_spline_total_len = maxf(1.0, total + prev.distance_to(_spline_samples[0]))


func _sample_jade_spline(dist: float) -> Dictionary:
	var d := fposmod(dist, _spline_total_len)
	var count := _spline_samples.size()
	var lo := 0
	var hi := count - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _spline_cumlen[mid] <= d:
			lo = mid
		else:
			hi = mid - 1
	var nxt := (lo + 1) % count
	var a := _spline_samples[lo]
	var b := _spline_samples[nxt]
	var seg_len := maxf(0.001, a.distance_to(b))
	var frac := clampf((d - _spline_cumlen[lo]) / seg_len, 0.0, 1.0)
	var pos := a.lerp(b, frac)
	var tan_dir := (b - a).normalized()
	return {"pos": pos, "dir": tan_dir}


func _setup_boats() -> void:
	boats.clear()
	# 8 bustling boats cruising the winding Jade Belt River loop (imperial gold, red-canopy & wupeng!)
	var specs := [
		{"style": "imperial_huafang", "frac": 0.585, "dir": 1.0,  "speed": 1.30, "lane": -0.75, "phase": 0.3}, # Right near 南门石拱桥!
		{"style": "red_canopy",       "frac": 0.545, "dir": -1.0, "speed": 1.45, "lane":  0.75, "phase": 1.2}, # Approaching 南门石拱桥 from east!
		{"style": "wupeng",           "frac": 0.435, "dir": 1.0,  "speed": 1.60, "lane": -0.70, "phase": 2.4}, # Passing 虹桥 & 醉仙楼!
		{"style": "imperial_huafang", "frac": 0.355, "dir": -1.0, "speed": 1.25, "lane":  0.75, "phase": 3.5}, # Passing 青莲桥!
		{"style": "red_canopy",       "frac": 0.245, "dir": 1.0,  "speed": 1.50, "lane": -0.70, "phase": 4.1}, # Passing 东关石拱桥!
		{"style": "wupeng",           "frac": 0.115, "dir": -1.0, "speed": 1.55, "lane":  0.70, "phase": 5.0}, # Passing 府前石拱桥!
		{"style": "red_canopy",       "frac": 0.745, "dir": 1.0,  "speed": 1.42, "lane": -0.70, "phase": 1.9}, # Passing 柳荫桥!
		{"style": "imperial_huafang", "frac": 0.895, "dir": -1.0, "speed": 1.28, "lane":  0.75, "phase": 0.8}, # Passing 西市石拱桥!
	]
	for sp: Dictionary in specs:
		var dist := float(sp["frac"]) * _spline_total_len
		var smp := _sample_jade_spline(dist)
		var dir_v: Vector2 = (smp["dir"] as Vector2) * float(sp["dir"])
		var right := Vector2(-dir_v.y, dir_v.x)
		boats.append({
			"route": "jade", "style": sp["style"], "dist": dist, "dir": float(sp["dir"]),
			"speed": float(sp["speed"]), "lane": float(sp["lane"]), "phase": float(sp["phase"]),
			"pos": (smp["pos"] as Vector2) + right * float(sp["lane"]),
			"heading": dir_v,
		})
	# 4 bustling pleasure boats on Cuiwei Lake around Five-Pavilion Bridge (directly matching Image 1!)
	boats.append({
		"route": "lake_ew", "style": "imperial_huafang", "dir": 1.0, "speed": 1.10,
		"base_y": 42.5, "min_x": 42.0, "max_x": 79.0, "phase": 0.9,
		"pos": Vector2(52.0, 42.5), "heading": Vector2(1.0, 0.0),
	})
	boats.append({
		"route": "lake_ew", "style": "red_canopy", "dir": -1.0, "speed": 1.25,
		"base_y": 60.5, "min_x": 41.0, "max_x": 80.0, "phase": 2.7,
		"pos": Vector2(67.0, 60.5), "heading": Vector2(-1.0, 0.0),
	})
	boats.append({
		"route": "lake_ns", "style": "red_canopy", "dir": 1.0, "speed": 1.22,
		"base_x": 47.5, "min_y": 39.0, "max_y": 64.5, "phase": 3.7,
		"pos": Vector2(47.5, 58.2), "heading": Vector2(0.0, 1.0),
	})
	boats.append({
		"route": "lake_ns", "style": "wupeng", "dir": -1.0, "speed": 1.32,
		"base_x": 65.5, "min_y": 39.0, "max_y": 64.5, "phase": 5.1,
		"pos": Vector2(65.5, 57.5), "heading": Vector2(0.0, -1.0),
	})


func _setup_sparrows() -> void:
	sparrow_flocks.clear()
	for i in range(6):
		var perch_idx := (i * 2) % SPARROW_PERCHES.size()
		var center: Vector2 = SPARROW_PERCHES[perch_idx]
		var birds: Array[Dictionary] = []
		var cnt := 6 + (i % 3)
		for b in range(cnt):
			var ang := float(b) * (TAU / float(cnt)) + float(i) * 0.4
			var rad := 0.35 + float(b % 3) * 0.42
			birds.append({
				"off": Vector2(cos(ang) * rad, sin(ang) * rad * 0.75),
				"phase": _rng.randf_range(0.0, TAU),
				"facing": 1.0 if (b % 2 == 0) else -1.0,
			})
		sparrow_flocks.append({
			"state": "perched",
			"pos": center, "start": center, "target": center, "perch_idx": perch_idx,
			"timer": _rng.randf_range(10.0, 24.0),
			"flight_t": 0.0, "flight_dur": 6.0, "alt": 0.0, "birds": birds,
		})


func _setup_egrets() -> void:
	egrets.clear()
	for i in range(2):
		var idx := (i * 3) % EGRET_SHORES.size()
		var p: Vector2 = EGRET_SHORES[idx]
		egrets.append({
			"state": "perched",
			"pos": p, "start": p, "target": p, "shore_idx": idx,
			"timer": _rng.randf_range(12.0, 26.0),
			"flight_t": 0.0, "flight_dur": 9.0, "alt": 0.0, "phase": float(i) * 2.1,
		})


func spawn_geese_flock(target_hint := Vector2(120.0, 160.0)) -> void:
	var from_left := _rng.randf() < 0.5
	var start_pos := Vector2(target_hint.x - 42.0 if from_left else target_hint.x + 42.0,
		clampf(target_hint.y + _rng.randf_range(18.0, 36.0), 20.0, 235.0))
	var vx := _rng.randf_range(4.4, 5.6) * (1.0 if from_left else -1.0)
	var vy := -_rng.randf_range(2.2, 3.3)
	geese_flocks.append({
		"pos": start_pos, "vel": Vector2(vx, vy),
		"count": _rng.randi_range(5, 9), "phase": _rng.randf_range(0.0, TAU),
		"scale": _rng.randf_range(0.92, 1.08), "age": 0.0,
	})


func tick(delta: float, player_pos := Vector2(120.0, 209.0), world: RefCounted = null) -> void:
	time += delta
	# 1. Boats (strictly water-locked)
	for b: Dictionary in boats:
		var route: String = b["route"]
		if route == "jade":
			var nd := fposmod(float(b["dist"]) + float(b["dir"]) * float(b["speed"]) * delta, _spline_total_len)
			b["dist"] = nd
			var smp := _sample_jade_spline(nd)
			var dir_v: Vector2 = (smp["dir"] as Vector2) * float(b["dir"])
			var right := Vector2(-dir_v.y, dir_v.x)
			b["pos"] = _clamp_to_water((smp["pos"] as Vector2) + right * float(b["lane"]), smp["pos"], world)
			b["heading"] = dir_v
		elif route == "lake_ew":
			var pos: Vector2 = b["pos"]
			var nx := pos.x + float(b["dir"]) * float(b["speed"]) * delta
			if nx >= float(b["max_x"]):
				nx = float(b["max_x"]); b["dir"] = -1.0
			elif nx <= float(b["min_x"]):
				nx = float(b["min_x"]); b["dir"] = 1.0
			var ny := float(b["base_y"]) + sin(nx * 0.14) * 0.65
			b["pos"] = _clamp_to_water(Vector2(nx, ny), Vector2(nx, float(b["base_y"])), world)
			b["heading"] = Vector2(float(b["dir"]), cos(nx * 0.14) * 0.14 * 0.65 * float(b["dir"])).normalized()
		elif route == "lake_ns":
			var pos: Vector2 = b["pos"]
			var ny := pos.y + float(b["dir"]) * float(b["speed"]) * delta
			if ny >= float(b["max_y"]):
				ny = float(b["max_y"]); b["dir"] = -1.0
			elif ny <= float(b["min_y"]):
				ny = float(b["min_y"]); b["dir"] = 1.0
			var nx := float(b["base_x"]) + sin(ny * 0.16) * 0.45
			b["pos"] = _clamp_to_water(Vector2(nx, ny), Vector2(float(b["base_x"]), ny), world)
			b["heading"] = Vector2(cos(ny * 0.16) * 0.16 * 0.45 * float(b["dir"]), float(b["dir"])).normalized()

	# 2. Periodic Wild Geese Flocks
	_next_geese_timer -= delta
	if _next_geese_timer <= 0.0:
		spawn_geese_flock(player_pos)
		_next_geese_timer = _rng.randf_range(30.0, 56.0)
	var keep_geese: Array[Dictionary] = []
	for f: Dictionary in geese_flocks:
		var pos: Vector2 = (f["pos"] as Vector2) + (f["vel"] as Vector2) * delta
		f["pos"] = pos
		f["age"] = float(f["age"]) + delta
		if pos.x >= -24.0 and pos.x <= 264.0 and pos.y >= -24.0 and pos.y <= 264.0 and float(f["age"]) < 75.0:
			keep_geese.append(f)
	geese_flocks = keep_geese

	# 4. Autonomous Sparrow Flocks
	for sf: Dictionary in sparrow_flocks:
		if str(sf["state"]) == "perched":
			sf["alt"] = 0.0
			sf["timer"] = float(sf["timer"]) - delta
			if (sf["pos"] as Vector2).distance_to(player_pos) < 4.4 or float(sf["timer"]) <= 0.0:
				var cur_idx: int = int(sf["perch_idx"])
				var nxt_idx := (cur_idx + _rng.randi_range(1, SPARROW_PERCHES.size() - 1)) % SPARROW_PERCHES.size()
				var dest: Vector2 = SPARROW_PERCHES[nxt_idx]
				sf["state"] = "flying"
				sf["start"] = sf["pos"]
				sf["target"] = dest
				sf["perch_idx"] = nxt_idx
				sf["flight_t"] = 0.0
				sf["flight_dur"] = clampf((sf["pos"] as Vector2).distance_to(dest) / 9.5, 3.2, 11.0)
		else:
			var ft := float(sf["flight_t"]) + delta / maxf(0.1, float(sf["flight_dur"]))
			if ft >= 1.0:
				sf["pos"] = sf["target"]; sf["state"] = "perched"; sf["alt"] = 0.0
				sf["timer"] = _rng.randf_range(14.0, 30.0)
			else:
				sf["flight_t"] = ft
				var s_pos: Vector2 = sf["start"]
				var e_pos: Vector2 = sf["target"]
				var dir_n := (e_pos - s_pos).normalized()
				var perp := Vector2(-dir_n.y, dir_n.x)
				sf["pos"] = s_pos.lerp(e_pos, ft) + perp * (sin(ft * PI) * 3.8)
				sf["alt"] = sin(ft * PI) * 2.2

	# 5. Waterfront Egrets
	for eg: Dictionary in egrets:
		if str(eg["state"]) == "perched":
			eg["alt"] = 0.0
			eg["timer"] = float(eg["timer"]) - delta
			if (eg["pos"] as Vector2).distance_to(player_pos) < 5.0 or float(eg["timer"]) <= 0.0:
				var nxt := (int(eg["shore_idx"]) + _rng.randi_range(1, EGRET_SHORES.size() - 1)) % EGRET_SHORES.size()
				eg["state"] = "flying"; eg["start"] = eg["pos"]; eg["target"] = EGRET_SHORES[nxt]
				eg["shore_idx"] = nxt; eg["flight_t"] = 0.0
				eg["flight_dur"] = clampf((eg["pos"] as Vector2).distance_to(EGRET_SHORES[nxt]) / 7.0, 4.5, 14.0)
		else:
			var ft := float(eg["flight_t"]) + delta / maxf(0.1, float(eg["flight_dur"]))
			if ft >= 1.0:
				eg["pos"] = eg["target"]; eg["state"] = "perched"; eg["alt"] = 0.0
				eg["timer"] = _rng.randf_range(16.0, 32.0)
			else:
				eg["flight_t"] = ft
				eg["pos"] = (eg["start"] as Vector2).lerp(eg["target"] as Vector2, ft)
				eg["alt"] = sin(ft * PI) * 2.4


static func _is_water_or_bridge(world: RefCounted, p: Vector2i) -> bool:
	if world == null:
		return true
	var t: String = str(world.terrain_at_level(p, 0))
	return t == "W" or t == "~" or t == "="


static func _clamp_to_water(pos: Vector2, fallback_center: Vector2, world: RefCounted) -> Vector2:
	if world == null:
		return pos
	if _is_water_or_bridge(world, Vector2i(roundi(pos.x), roundi(pos.y))):
		return pos
	if _is_water_or_bridge(world, Vector2i(roundi(fallback_center.x), roundi(fallback_center.y))):
		return fallback_center
	return pos


static func _world_to_screen(board: Control, world_pos: Vector2) -> Vector2:
	return (world_pos - Vector2(board.view_origin)) * float(board.cell) + board.cam_px_offset


static func _boat_bridge_alpha(board: Control, pos: Vector2, fwd: Vector2) -> float:
	var w: RefCounted = board.world
	var c_tile: String = str(w.terrain_at_level(Vector2i(roundi(pos.x), roundi(pos.y)), 0))
	if c_tile != "W" and c_tile != "~":
		return 0.0
	var bow_t: String = str(w.terrain_at_level(Vector2i(roundi(pos.x + fwd.x * 1.15), roundi(pos.y + fwd.y * 1.15)), 0))
	var stern_t: String = str(w.terrain_at_level(Vector2i(roundi(pos.x - fwd.x * 1.15), roundi(pos.y - fwd.y * 1.15)), 0))
	if bow_t == "=" or stern_t == "=":
		return 0.42
	return 1.0


func draw_water_layer(layer: Control, board: Control, daylight: float, lamp_power: float) -> void:
	if board.world == null or board.world.floor != 0:
		return
	var visible := Rect2i(board.view_origin, board.view_size).intersection(board.bounds)
	var s := float(board.cell)
	var ambient_tint := Color(0.32, 0.38, 0.48).lerp(Color(1.0, 0.98, 0.94), clampf(daylight, 0.0, 1.0))

	# 1. Natural water ripples + Warm Golden Waterfront Reflections at dusk/night (Image 3!)
	var water_alpha := 0.14 + 0.10 * clampf(daylight, 0.0, 1.0)
	var ripple_col := Color(0.84, 0.93, 0.96, water_alpha)
	var y0 := maxi(visible.position.y, 8)
	var y1 := mini(visible.end.y, 232)
	var x0 := maxi(visible.position.x, 8)
	var x1 := mini(visible.end.x, 232)
	for wy in range(y0, y1, 2):
		for wx in range(x0 + ((wy * 3) % 4), x1, 4):
			var p := Vector2i(wx, wy)
			var cell_data: Array = board.cells.get(p, [])
			if cell_data.is_empty():
				continue
			var ct: String = cell_data[0]
			if ct == "W":
				var drift := sin(time * 1.3 + float(wx) * 0.4 + float(wy) * 0.7) * 0.35
				var sp := _world_to_screen(board, Vector2(float(wx) + 0.5 + drift, float(wy) + 0.5))
				var wlen := s * (0.30 + 0.12 * sin(time * 2.0 + float(wx + wy)))
				layer.draw_line(sp - Vector2(wlen * 0.5, 0.0), sp + Vector2(wlen * 0.5, 0.0), ripple_col, maxf(1.0, s * 0.036))
			elif ct == "~" and lamp_power > 0.12:
				# Shimmering warm golden waterfront lantern reflections along shallow canal edges (Image 3!)
				var sp := _world_to_screen(board, Vector2(float(wx) + 0.5, float(wy) + 0.5))
				var shimmer := 0.55 + 0.45 * sin(time * 3.2 + float(wx) * 1.3 + float(wy) * 0.9)
				var rw := s * (0.35 + 0.20 * shimmer)
				layer.draw_line(sp - Vector2(rw, 0.0), sp + Vector2(rw, 0.0),
					Color(1.0, 0.72, 0.28, 0.24 * lamp_power * shimmer), maxf(1.4, s * 0.065))

	# 2. 12 High-Detail Painterly Cruising Boats (Image 1!) — Cangming Jiangnan pack only!
	if board.world.has_method("is_cataclysm_pack") and board.world.is_cataclysm_pack():
		return
	for b: Dictionary in boats:
		var pos: Vector2 = b["pos"]
		var ip := Vector2i(roundi(pos.x), roundi(pos.y))
		if not visible.grow(3).has_point(ip):
			continue
		var vis := _boat_bridge_alpha(board, pos, b["heading"])
		if vis <= 0.02:
			continue
		_draw_realistic_boat(layer, board, b, vis, ambient_tint, lamp_power)

	# 3. Quiet moored open wooden rowboats gently bobbing on tributary creeks (Photo 3!)
	for sk: Dictionary in MOORED_SKIFFS:
		var spos: Vector2 = sk["pos"]
		var sip := Vector2i(roundi(spos.x), roundi(spos.y))
		if not visible.grow(2).has_point(sip):
			continue
		var t_under: String = str(board.world.terrain_at_level(sip, 0))
		if t_under != "W" and t_under != "~":
			continue
		_draw_moored_skiff(layer, board, spos, sk["dir"], float(sk["phase"]), ambient_tint)


func _draw_moored_skiff(layer: Control, board: Control, pos: Vector2, dir: Vector2, phase: float, tint: Color) -> void:
	var s := float(board.cell)
	var fwd := dir.normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var sway := sin(time * 1.4 + phase) * 0.04
	var center := _world_to_screen(board, pos + right * sway)
	var hl := s * 0.88
	var hw := s * 0.28
	var hull := PackedVector2Array([
		center + fwd * hl,
		center + fwd * (hl * 0.50) + right * hw,
		center - fwd * (hl * 0.50) + right * (hw * 0.92),
		center - fwd * hl,
		center - fwd * (hl * 0.50) - right * (hw * 0.92),
		center + fwd * (hl * 0.50) - right * hw,
	])
	var sh := PackedVector2Array()
	for pt: Vector2 in hull:
		sh.append(pt + Vector2(s * 0.07, s * 0.10))
	layer.draw_colored_polygon(sh, Color(0.02, 0.05, 0.08, 0.36))
	layer.draw_colored_polygon(hull, Color("443328") * tint)
	var inner := PackedVector2Array()
	for pt: Vector2 in hull:
		inner.append(center.lerp(pt, 0.76))
	layer.draw_colored_polygon(inner, Color("725842") * tint)
	# Wooden cross-thwart benches & resting oar inside open skiff (Photo 3!)
	var bench_col := Color("947456") * tint
	for bf: float in [-0.35, 0.0, 0.35]:
		var bp := center + fwd * (hl * bf)
		layer.draw_line(bp - right * (hw * 0.68), bp + right * (hw * 0.68), bench_col, maxf(1.5, s * 0.06))
	layer.draw_line(center - fwd * (hl * 0.48) - right * (hw * 0.30), center + fwd * (hl * 0.65) + right * (hw * 0.15), Color("b08a58") * tint, maxf(1.2, s * 0.045))


func _draw_realistic_boat(layer: Control, board: Control, b: Dictionary, alpha: float, tint: Color, lamp_power: float) -> void:
	var s := float(board.cell)
	var pos: Vector2 = b["pos"]
	var fwd: Vector2 = (b["heading"] as Vector2).normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var style: String = b["style"]
	var is_imperial := (style == "imperial_huafang")
	var is_red := (style == "red_canopy")
	var phase := float(b["phase"])

	var bob := sin(time * 2.5 + phase) * 0.032
	var center := _world_to_screen(board, pos + right * bob)
	var half_len := s * (1.58 if is_imperial else (1.32 if is_red else 1.12))
	var half_w := s * (0.50 if is_imperial else (0.42 if is_red else 0.34))

	# 1. Churning foaming multi-layered wake behind stern (matching Image 1's lively wakes!)
	for k in range(5):
		var wt := fmod(time * 0.88 + float(k) * 0.20 + phase * 0.1, 1.0)
		var back := center - fwd * (half_len * (0.85 + wt * 1.75))
		var spread := half_w * (0.62 + wt * 1.90)
		var wa := (1.0 - wt) * (1.0 - wt) * 0.44 * alpha
		var wcol := Color(0.90, 0.97, 0.99, wa)
		layer.draw_line(back - right * (spread * 0.25), back - right * spread - fwd * (s * 0.28), wcol, maxf(1.2, s * 0.045))
		layer.draw_line(back + right * (spread * 0.25), back + right * spread - fwd * (s * 0.28), wcol, maxf(1.2, s * 0.045))
		if k < 3:
			layer.draw_circle(back, maxf(1.4, s * (0.09 + wt * 0.12)), Color(0.92, 0.98, 1.0, wa * 0.55))

	# 2. Tapered 10-point realistic wooden hull + water shadow reflection
	var hull_pts := PackedVector2Array([
		center + fwd * half_len,
		center + fwd * (half_len * 0.72) + right * (half_w * 0.74),
		center + fwd * (half_len * 0.26) + right * half_w,
		center - fwd * (half_len * 0.38) + right * (half_w * 0.95),
		center - fwd * (half_len * 0.80) + right * (half_w * 0.62),
		center - fwd * half_len,
		center - fwd * (half_len * 0.80) - right * (half_w * 0.62),
		center - fwd * (half_len * 0.38) - right * (half_w * 0.95),
		center + fwd * (half_len * 0.26) - right * half_w,
		center + fwd * (half_len * 0.72) - right * (half_w * 0.74),
	])
	var sh_pts := PackedVector2Array()
	for pt: Vector2 in hull_pts:
		sh_pts.append(pt + Vector2(s * 0.10, s * 0.15))
	layer.draw_colored_polygon(sh_pts, Color(0.02, 0.06, 0.09, 0.42 * alpha))

	# Dark lacquered / cedar hull gunwale
	var hull_col := (Color("232528") if is_imperial else (Color("5a2e1e") if is_red else Color("3b2416"))) * tint
	hull_col.a = alpha
	layer.draw_colored_polygon(hull_pts, hull_col)
	# Gold filigree side stripe on Imperial Pleasure Boat (Image 1 left!)
	if is_imperial:
		var gold_trim := Color("e2ba52") * tint
		gold_trim.a = alpha * 0.92
		layer.draw_line(center + fwd * (half_len * 0.62) - right * (half_w * 0.84),
			center - fwd * (half_len * 0.62) - right * (half_w * 0.84), gold_trim, maxf(1.4, s * 0.055))
		layer.draw_line(center + fwd * (half_len * 0.62) + right * (half_w * 0.84),
			center - fwd * (half_len * 0.62) + right * (half_w * 0.84), gold_trim, maxf(1.4, s * 0.055))

	# Weathered cedar deck planks & visible cabin passengers
	var deck_pts := PackedVector2Array()
	for pt: Vector2 in hull_pts:
		deck_pts.append(center.lerp(pt, 0.80))
	var deck_col := Color("946e46") * tint
	deck_col.a = alpha
	layer.draw_colored_polygon(deck_pts, deck_col)
	var seam_col := Color("593f26") * tint
	seam_col.a = alpha * 0.65
	for frac: float in [0.60, 0.76, -0.56, -0.72]:
		var dp := center + fwd * (half_len * frac)
		var span := half_w * (0.58 if absf(frac) < 0.66 else 0.40)
		layer.draw_line(dp - right * span, dp + right * span, seam_col, maxf(1.0, s * 0.03))

	# Dark interior cabin opening with seated passengers visible through bow entrance (Image 1!)
	var cab_front := center + fwd * (half_len * 0.56)
	var cab_pts := PackedVector2Array([
		cab_front + right * (half_w * 0.66),
		center + fwd * (half_len * 0.34) + right * (half_w * 0.72),
		center + fwd * (half_len * 0.34) - right * (half_w * 0.72),
		cab_front - right * (half_w * 0.66),
	])
	layer.draw_colored_polygon(cab_pts, Color(0.08, 0.06, 0.05, 0.86 * alpha))
	if is_imperial or is_red:
		# Tiny seated passengers peeking inside the open-sided cabin
		var p1 := center + fwd * (half_len * 0.44) - right * (half_w * 0.25)
		var p2 := center + fwd * (half_len * 0.44) + right * (half_w * 0.25)
		layer.draw_circle(p1, maxf(1.5, s * 0.08), Color("88a6b8", alpha) * tint)
		layer.draw_circle(p2, maxf(1.5, s * 0.08), Color("c47d64", alpha) * tint)

	# 3. 3D Shaded Roof / Canopy (Imperial Gold Glazed Tile vs Terracotta Red Canopy vs Dark Bamboo Wupeng)
	var awn_f := center + fwd * (half_len * 0.44)
	var awn_b := center - fwd * (half_len * 0.36)
	var awn_w := half_w * (1.02 if is_imperial else (0.94 if is_red else 0.88))
	var awn_hi: Color
	var awn_lo: Color
	var rib_col: Color
	if is_imperial:
		# Bright imperial yellow-gold glazed ceramic tiles (Image 1 left boat!)
		awn_hi = Color("f0c43c") * tint
		awn_lo = Color("c28e1e") * tint
		rib_col = Color("ffe680") * tint
	elif is_red:
		# Warm terracotta-vermilion pleasure boat canopy (Image 1 center/right boats!)
		awn_hi = Color("b64a38") * tint
		awn_lo = Color("822e22") * tint
		rib_col = Color("d87d62") * tint
	else:
		# Classic dark woven bamboo Wupeng canopy
		awn_hi = Color("3b3e44") * tint
		awn_lo = Color("23252a") * tint
		rib_col = Color("625e56") * tint
	awn_hi.a = alpha; awn_lo.a = alpha; rib_col.a = alpha
	layer.draw_colored_polygon(PackedVector2Array([awn_f, awn_b, awn_b - right * awn_w, awn_f - right * awn_w]), awn_hi)
	layer.draw_colored_polygon(PackedVector2Array([awn_f, awn_f + right * awn_w, awn_b + right * awn_w, awn_b]), awn_lo)

	# Roof ridge & barrel-tile / bamboo ribs
	layer.draw_line(awn_f, awn_b, rib_col, maxf(1.6, s * 0.075))
	for r_off: float in [-0.28, -0.14, 0.0, 0.14, 0.28]:
		var rp := center + fwd * (half_len * r_off)
		layer.draw_line(rp - right * (awn_w * 0.96), rp + right * (awn_w * 0.96), rib_col, maxf(1.0, s * 0.036))

	# Vermilion lacquered corner cabin pillars (Image 1!)
	if is_imperial or is_red:
		var pil := Color("a8241c") * tint
		pil.a = alpha
		for corner_p: Vector2 in [
			awn_f - right * (awn_w * 0.92), awn_f + right * (awn_w * 0.92),
			awn_b - right * (awn_w * 0.92), awn_b + right * (awn_w * 0.92),
		]:
			layer.draw_circle(corner_p, maxf(1.5, s * 0.07), pil)

	# 4. Detailed Rowing Boatman & Sculling Oar (摇橹)
	var row_cycle := sin(time * 3.0 + phase)
	var stern := center - fwd * (half_len * 0.62)
	var pivot := stern + right * (half_w * 0.54)
	var oar_blade := pivot - fwd * (s * 0.76) + right * (s * (0.30 + row_cycle * 0.28))
	var oar_handle := pivot + fwd * (s * 0.16) - right * (s * (0.20 + row_cycle * 0.10))
	var oar_col := Color("a8814e") * tint
	oar_col.a = alpha
	layer.draw_line(oar_handle, oar_blade, oar_col, maxf(1.5, s * 0.055))
	layer.draw_line(oar_blade, oar_blade - fwd * (s * 0.18) + right * (s * 0.06), oar_col.darkened(0.20), maxf(2.6, s * 0.095))
	layer.draw_arc(oar_blade, s * (0.11 + 0.07 * absf(row_cycle)), 0.0, TAU, 12, Color(0.90, 0.97, 1.0, 0.42 * alpha), maxf(1.0, s * 0.032))

	var man := stern + fwd * (row_cycle * s * 0.04)
	var tunic := (Color("304b62") if not is_red else Color("d0c8b4")) * tint
	tunic.a = alpha
	layer.draw_circle(man, maxf(2.6, s * 0.16), tunic)
	layer.draw_line(man + right * (s * 0.06), oar_handle, tunic, maxf(1.5, s * 0.06))
	var hat_pos := man + Vector2(0.0, -s * 0.04)
	layer.draw_circle(hat_pos, maxf(2.6, s * 0.175), Color("8b6e3f", alpha) * tint)
	layer.draw_circle(hat_pos + Vector2(-s * 0.015, -s * 0.015), maxf(2.2, s * 0.145), Color("d8be84", alpha) * tint)
	layer.draw_circle(hat_pos, maxf(0.9, s * 0.05), Color("5e4522", alpha))

	# 5. Bow red palace lantern with water glow reflection
	var bow := center + fwd * (half_len * 0.85)
	var glow := clampf(lamp_power, 0.0, 1.0)
	if glow > 0.08:
		layer.draw_circle(bow, s * (0.90 if is_imperial else 0.62), Color(1.0, 0.70, 0.26, 0.24 * glow * alpha))
		layer.draw_circle(bow + Vector2(0.0, s * 0.18), s * 0.34, Color(1.0, 0.74, 0.32, 0.30 * glow * alpha))
	var lan_col := Color("b82a20").lerp(Color("ffd87a"), 0.22 + 0.78 * glow)
	lan_col.a = alpha
	layer.draw_circle(bow, maxf(2.0, s * 0.105), lan_col)
	layer.draw_circle(bow, maxf(0.9, s * 0.05), Color(1.0, 0.94, 0.76, (0.55 + 0.45 * glow) * alpha))


func draw_sky_layer(layer: Control, board: Control, _season: String, daylight: float, lamp_power: float) -> void:
	if board.world == null:
		return
	var visible := Rect2i(board.view_origin, board.view_size).intersection(board.bounds)
	var s := float(board.cell)
	var z: int = board.world.floor
	var font := board.get_theme_default_font()

	if z == 0:
		if board.world.has_method("is_cataclysm_pack") and board.world.is_cataclysm_pack():
			_draw_cataclysm_signs(layer, board, visible, s, daylight, font)
			_draw_geese_flocks(layer, board, visible, s, daylight)
			return
		# 0. Iconic Golden-Glazed Five-Pavilion Bridge Roofs (五亭桥重檐金瓦五亭 — Image 1!)
		_draw_five_pavilion_bridge_roofs(layer, board, visible, s, daylight, lamp_power)
		# 1. Swaying Wuxia cloth shop banners (酒旗/幡幌)
		_draw_shop_banners(layer, board, visible, s, daylight, font)
		# 2. Curling kitchen smoke & blacksmith forge sparks
		_draw_smoke_and_sparks(layer, board, visible, s, daylight)
		# 3. Carved gold-on-ink landmark plaques (牌匾) & roof-aware NPC nameplates
		_draw_landmark_plaques(layer, board, visible, s, daylight, font)
		_draw_npc_nameplates(layer, board, visible, s, font)
		# 4. Autonomous sparrow flocks (hopping/pecking on perches & wheeling across rooftops)
		_draw_sparrows(layer, board, visible, s, daylight)
		# 5. Waterfront egrets
		_draw_egrets(layer, board, visible, s, daylight)
		# 6. Periodic V-formation wild geese flocks (大雁人字阵)
		_draw_geese_flocks(layer, board, visible, s, daylight)


func _draw_cataclysm_signs(layer: Control, board: Control, visible: Rect2i, s: float, daylight: float, font: Font) -> void:
	if font == null or s < 18.0:
		return
	const CCB_SIGNS := [
		{"pos": Vector2(120.0, 200.0), "title": "EVAC SHELTER · 应急避难所", "col": Color("57d1d6")},
		{"pos": Vector2(133.0, 164.0), "title": "GROCERY · 城镇超市", "col": Color("8ef5a8")},
		{"pos": Vector2(105.0, 162.0), "title": "PHARMACY · 社区药房", "col": Color("7ed4ff")},
		{"pos": Vector2(133.0, 116.0), "title": "HARDWARE · 五金工具店", "col": Color("f0d86c")},
		{"pos": Vector2(105.0, 116.0), "title": "POLICE · 城镇警局", "col": Color("6ca4f2")},
		{"pos": Vector2(133.0, 66.0),  "title": "LIBRARY · 市立图书馆", "col": Color("d384e8")},
		{"pos": Vector2(105.0, 66.0),  "title": "CLINIC · 街区诊所", "col": Color("8ef5a8")},
		{"pos": Vector2(182.0, 128.0), "title": "☢ 核废料泄漏区 (高辐射)", "col": Color("ff785c")},
	]
	var fsize := clampi(int(s * 0.38), 11, 13)
	for sg: Dictionary in CCB_SIGNS:
		var wp: Vector2 = sg["pos"]
		var ip := Vector2i(int(wp.x), int(wp.y))
		if not visible.grow(2).has_point(ip):
			continue
		if board.roof_system.has_roof_at(ip) and board.roof_system.alpha_at(ip) < 0.35:
			continue
		var sp := _world_to_screen(board, wp)
		var txt: String = sg["title"]
		var col: Color = sg["col"]
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var r := Rect2(sp.x - tw * 0.5 - 6.0, sp.y - 10.0, tw + 12.0, 18.0)
		layer.draw_rect(r, Color(0.03, 0.05, 0.07, 0.86))
		layer.draw_rect(r, Color(col.r, col.g, col.b, 0.78), false, 1.0)
		layer.draw_string(font, r.position + Vector2(6.0, 13.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col.lerp(Color.WHITE, 0.25))


func _draw_five_pavilion_bridge_roofs(layer: Control, board: Control, visible: Rect2i, s: float, daylight: float, lamp_power: float) -> void:
	# Directly recreates Image 1: 5 ornate imperial-gold glazed pavilions linked by crimson corridors over Five-Pavilion Bridge!
	if not visible.intersects(Rect2i(36, 46, 50, 14)):
		return
	# Fade smoothly when the player steps right onto Five-Pavilion Bridge so the deck stays readable!
	var ppos: Vector2 = board.motion.visual_pos
	var on_bridge_dist := 99.0
	if ppos.x >= 38.0 and ppos.x <= 84.0:
		on_bridge_dist = absf(ppos.y - 52.0)
	var alpha := clampf(smoothstep(1.6, 5.2, on_bridge_dist), 0.14, 1.0)
	if not board.roofs_enabled:
		alpha = 0.14
	var tint := Color(0.38, 0.42, 0.50).lerp(Color(1.0, 0.98, 0.94), clampf(daylight, 0.0, 1.0))

	# 4 Linking Crimson-Pillared Covered Corridors between the 5 pavilions
	var gold_dark := Color("a87a1c") * tint
	var gold_mid := Color("dfb034") * tint
	var gold_hi := Color("ffe378") * tint
	var ridge_col := Color("3b3e42") * tint
	var red_col := Color("a2241c") * tint
	gold_dark.a = alpha; gold_mid.a = alpha; gold_hi.a = alpha; ridge_col.a = alpha; red_col.a = alpha

	for cx_pair in [[43.5, 52.5], [52.5, 61.5], [61.5, 70.5], [70.5, 79.5]]:
		var p_a := _world_to_screen(board, Vector2(float(cx_pair[0]), 52.5))
		var p_b := _world_to_screen(board, Vector2(float(cx_pair[1]), 52.5))
		var corr_r := Rect2(p_a.x, p_a.y - s * 1.15, p_b.x - p_a.x, s * 2.15)
		layer.draw_rect(corr_r, gold_dark)
		layer.draw_rect(Rect2(corr_r.position.x, corr_r.position.y + corr_r.size.y * 0.45, corr_r.size.x, corr_r.size.y * 0.50), gold_mid)
		layer.draw_line(Vector2(corr_r.position.x, corr_r.position.y + corr_r.size.y * 0.45),
			Vector2(corr_r.end.x, corr_r.position.y + corr_r.size.y * 0.45), ridge_col, maxf(1.8, s * 0.08))

	# 5 Ornate Golden-Glazed Upturned Pavilions (center main pavilion is taller & double-tiered — Image 1!)
	var pav_xs := [43.5, 52.5, 61.5, 70.5, 79.5]
	for idx in range(pav_xs.size()):
		var is_center := (idx == 2)
		var is_mid := (idx == 1 or idx == 3)
		var half_w := s * (2.65 if is_center else (2.15 if is_mid else 2.25))
		var half_h := s * (2.55 if is_center else (2.10 if is_mid else 2.18))
		var c := _world_to_screen(board, Vector2(float(pav_xs[idx]), 52.5))
		var r := Rect2(c.x - half_w, c.y - half_h - (s * 0.35 if is_center else 0.0), half_w * 2.0, half_h * 2.0)
		# Drop shadow onto stone bridge
		layer.draw_rect(Rect2(r.position + Vector2(s * 0.16, s * 0.22), r.size), Color(0.02, 0.04, 0.06, 0.40 * alpha))
		# Four crimson pavilion pillars at corners
		for cp: Vector2 in [r.position + Vector2(3, 3), Vector2(r.end.x - 3, r.position.y + 3),
				Vector2(r.position.x + 3, r.end.y - 3), r.end - Vector2(3, 3)]:
			layer.draw_circle(cp, maxf(2.2, s * 0.11), red_col)
		# Golden glazed hip-and-gable roof body (shaded north/south slopes + barrel-tile ribs!)
		layer.draw_rect(r, gold_dark)
		layer.draw_rect(Rect2(r.position.x, c.y - (s * 0.35 if is_center else 0.0), r.size.x, r.end.y - (c.y - (s * 0.35 if is_center else 0.0))), gold_mid)
		var ribs := 8 if is_center else 6
		for k in range(1, ribs):
			var rx := r.position.x + r.size.x * float(k) / float(ribs)
			layer.draw_line(Vector2(rx, r.position.y), Vector2(rx, r.end.y), gold_hi, 1.0)
		# Upturned dark-slate diagonal hip ridges & flying eaves (飞檐翘角!)
		var top_mid := Vector2(c.x, r.position.y + r.size.y * 0.44)
		var fl := maxf(4.5, s * 0.28)
		layer.draw_line(top_mid, r.position + Vector2(-fl, -fl * 0.6), ridge_col, maxf(2.2, s * 0.09))
		layer.draw_line(top_mid, Vector2(r.end.x + fl, r.position.y - fl * 0.6), ridge_col, maxf(2.2, s * 0.09))
		layer.draw_line(top_mid, Vector2(r.position.x - fl, r.end.y + fl * 0.4), ridge_col, maxf(2.2, s * 0.09))
		layer.draw_line(top_mid, r.end + Vector2(fl, fl * 0.4), ridge_col, maxf(2.2, s * 0.09))
		# Golden roof finial spire (宝顶) & night illumination
		if is_center:
			var r2 := r.grow(-s * 0.72)
			layer.draw_rect(r2, gold_mid)
			layer.draw_rect(r2, ridge_col, false, maxf(1.8, s * 0.07))
		layer.draw_circle(top_mid, maxf(3.2, s * 0.16), gold_hi)
		layer.draw_circle(top_mid, maxf(1.8, s * 0.08), ridge_col)
		if lamp_power > 0.12:
			layer.draw_rect(r.grow(2.0), Color(1.0, 0.78, 0.30, 0.16 * lamp_power * alpha), false, 2.0)


func _draw_shop_banners(layer: Control, board: Control, visible: Rect2i, s: float, daylight: float, font: Font) -> void:
	var tint := Color(0.45, 0.48, 0.56).lerp(Color.WHITE, clampf(daylight, 0.0, 1.0))
	for i in range(SHOP_BANNERS.size()):
		var b: Dictionary = SHOP_BANNERS[i]
		var wp: Vector2 = b["pos"]
		if not visible.grow(2).has_point(Vector2i(int(wp.x), int(wp.y))):
			continue
		var base := _world_to_screen(board, wp)
		var sway := sin(time * 2.5 + float(i) * 1.3) * (s * 0.14)
		var pole_top := base + Vector2(0.0, -s * 1.05)
		var arm_end := pole_top + Vector2(s * 0.54, -s * 0.06)
		layer.draw_line(base, pole_top, Color("5a3b24") * tint, maxf(1.8, s * 0.08))
		layer.draw_line(pole_top, arm_end, Color("6c482c") * tint, maxf(1.4, s * 0.06))
		var fw := s * 0.44
		var fh := s * 0.68
		var top_l := pole_top + Vector2(s * 0.10, s * 0.02)
		var top_r := top_l + Vector2(fw, -s * 0.03)
		var bot_r := top_r + Vector2(sway, fh)
		var bot_l := top_l + Vector2(sway * 0.82, fh * 0.96)
		var bg: Color = b["bg"] * tint
		var trim: Color = b["trim"] * tint
		layer.draw_colored_polygon(PackedVector2Array([top_l, top_r, bot_r, bot_l]), bg)
		layer.draw_polyline(PackedVector2Array([top_l, top_r, bot_r, bot_l, top_l]), trim, maxf(1.2, s * 0.048))
		if font != null and s >= 18.0:
			var fsize := maxi(11, int(s * 0.42))
			var ch: String = b["char"]
			var mid := (top_l + top_r + bot_l + bot_r) * 0.25
			layer.draw_string(font, mid + Vector2(-float(fsize) * 0.5, float(fsize) * 0.36), ch,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color("fdf0c8") * tint)


func _draw_landmark_plaques(layer: Control, board: Control, visible: Rect2i, s: float, daylight: float, font: Font) -> void:
	if font == null or s < 20.0:
		return
	var fsize := clampi(int(s * 0.42), 12, 15)
	var tint := Color(0.58, 0.60, 0.68).lerp(Color.WHITE, clampf(daylight, 0.0, 1.0))
	for pl: Dictionary in LANDMARK_PLAQUES:
		var wp: Vector2 = pl["pos"]
		var ip := Vector2i(int(wp.x), int(wp.y))
		if not visible.grow(2).has_point(ip):
			continue
		if board.roof_system.alpha_at(ip) < 0.35:
			continue
		var txt: String = pl["title"]
		var sp := _world_to_screen(board, wp)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var pad_x := 8.0
		var box_h := float(fsize) + 8.0
		var rect := Rect2(sp.x - tw * 0.5 - pad_x, sp.y - box_h * 0.5, tw + pad_x * 2.0, box_h)
		var bg := Color(0.08, 0.06, 0.05, 0.86)
		var border := Color("d9b25a") * tint
		border.a = 0.90
		layer.draw_rect(rect, bg)
		layer.draw_rect(rect, border, false, 1.4)
		layer.draw_string(font, Vector2(rect.position.x + pad_x, rect.end.y - 5.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color("f8e29c") * tint)


func _draw_smoke_and_sparks(layer: Control, board: Control, visible: Rect2i, s: float, daylight: float) -> void:
	for i in range(SMOKE_VENTS.size()):
		var v: Dictionary = SMOKE_VENTS[i]
		var wp: Vector2 = v["pos"]
		if not visible.grow(3).has_point(Vector2i(int(wp.x), int(wp.y))):
			continue
		var origin := _world_to_screen(board, wp)
		if str(v["kind"]) == "forge":
			for k in range(6):
				var p_t := fmod(time * 1.15 + float(k) * 0.167 + float(i) * 0.31, 1.0)
				var sx := origin.x + sin(p_t * 6.2 + float(k) * 2.1) * s * 0.30 + p_t * s * 0.20
				var sy := origin.y - p_t * s * 1.40 - sin(p_t * PI) * s * 0.22
				layer.draw_circle(Vector2(sx, sy), maxf(1.2, s * (0.06 - p_t * 0.032)), Color(1.0, 0.82 - p_t * 0.45, 0.20, (1.0 - p_t) * 0.92))
		else:
			var smoke_base := Color(0.74, 0.78, 0.82).lerp(Color(0.92, 0.93, 0.95), clampf(daylight, 0.0, 1.0))
			for k in range(5):
				var p_t := fmod(time * 0.36 + float(k) * 0.20 + float(i) * 0.27, 1.0)
				var sx := origin.x + sin(p_t * 4.0 + float(k) * 1.4) * s * 0.24 + p_t * s * 0.62
				var sy := origin.y - p_t * s * 1.90
				layer.draw_circle(Vector2(sx, sy), s * (0.14 + p_t * 0.30), Color(smoke_base.r, smoke_base.g, smoke_base.b, sin(p_t * PI) * 0.24))


func _draw_npc_nameplates(layer: Control, board: Control, visible: Rect2i, s: float, font: Font) -> void:
	if font == null or s < 20.0:
		return
	var sites: Dictionary = board.world.active_sites_in_rect(visible.grow(1))
	var fsize := clampi(int(s * 0.36), 11, 14)
	for wp: Vector2i in sites:
		var sid: StringName = sites[wp]
		if not NPC_LABELS.has(sid):
			continue
		if board.roof_system.has_roof_at(wp) and board.roof_system.alpha_at(wp) > 0.45:
			continue
		var label_txt: String = NPC_LABELS[sid]
		var sp := _world_to_screen(board, Vector2(wp) + Vector2(0.5, -0.18))
		var tw := font.get_string_size(label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var pad_x := 6.0
		var box_h := float(fsize) + 6.0
		var rect := Rect2(sp.x - tw * 0.5 - pad_x, sp.y - box_h, tw + pad_x * 2.0, box_h)
		layer.draw_rect(rect, Color(0.06, 0.08, 0.07, 0.80))
		layer.draw_rect(rect, Color(0.78, 0.65, 0.34, 0.75), false, 1.0)
		layer.draw_string(font, Vector2(rect.position.x + pad_x, rect.end.y - 4.0), label_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color("f6e3a8"))


func _draw_sparrows(layer: Control, board: Control, visible: Rect2i, s: float, daylight: float) -> void:
	var vis_a := clampf(daylight * 1.15 + 0.18, 0.25, 1.0)
	var body_col := Color(0.46, 0.34, 0.24, 0.95 * vis_a)
	var wing_col := Color(0.28, 0.21, 0.16, 0.95 * vis_a)
	var belly_col := Color(0.76, 0.70, 0.60, 0.90 * vis_a)
	var sh_col := Color(0.02, 0.04, 0.04, 0.24 * clampf(daylight, 0.0, 1.0))
	for sf: Dictionary in sparrow_flocks:
		var center: Vector2 = sf["pos"]
		if not visible.grow(6).has_point(Vector2i(int(center.x), int(center.y))):
			continue
		var flying := (str(sf["state"]) == "flying")
		var alt := float(sf["alt"])
		var birds: Array = sf["birds"]
		var fly_dir := ((sf["target"] as Vector2) - (sf["start"] as Vector2)).normalized()
		if fly_dir.length_squared() < 0.01:
			fly_dir = Vector2.RIGHT
		var fly_right := Vector2(-fly_dir.y, fly_dir.x)
		for b: Dictionary in birds:
			var ph := float(b["phase"])
			var off: Vector2 = b["off"]
			if flying:
				var swoop := Vector2(sin(time * 4.0 + ph) * 0.35, cos(time * 3.4 + ph) * 0.28)
				var bp := center + off * 1.55 + swoop
				var sp := _world_to_screen(board, bp) + Vector2(0.0, -alt * s * 0.65)
				var ground_sp := _world_to_screen(board, bp) + Vector2(alt * s * 0.35, alt * s * 0.45)
				var flap := sin(time * 16.0 + ph)
				var span := maxf(2.4, s * 0.14)
				if daylight > 0.15:
					layer.draw_circle(ground_sp, maxf(1.2, s * 0.05), sh_col)
				layer.draw_polyline(PackedVector2Array([
					sp - fly_right * span + fly_dir * (flap * span * 0.45), sp,
					sp + fly_right * span + fly_dir * (flap * span * 0.45)]), wing_col, maxf(1.3, s * 0.055))
				layer.draw_circle(sp, maxf(1.4, s * 0.055), body_col)
			else:
				var hop_cycle := fmod(time * 1.1 + ph, 2.8)
				var hop_y := -sin(hop_cycle * PI / 0.32) * s * 0.12 if hop_cycle < 0.32 else 0.0
				var hop_x := sin(ph * 3.0 + floor(time * 0.4)) * 0.18
				var sp := _world_to_screen(board, center + off + Vector2(hop_x, 0.0))
				var face := float(b["facing"])
				if daylight > 0.15:
					layer.draw_circle(sp + Vector2(0.0, s * 0.04), maxf(1.4, s * 0.065), sh_col)
				var p_draw := sp + Vector2(0.0, hop_y)
				layer.draw_circle(p_draw, maxf(1.8, s * 0.075), body_col)
				layer.draw_circle(p_draw + Vector2(face * s * 0.04, -s * 0.03), maxf(1.2, s * 0.052), wing_col)
				layer.draw_circle(p_draw + Vector2(-face * s * 0.02, s * 0.02), maxf(1.0, s * 0.042), belly_col)
				layer.draw_line(p_draw - Vector2(face * s * 0.06, 0.0), p_draw - Vector2(face * s * 0.13, s * 0.04), wing_col, maxf(1.0, s * 0.04))


func _draw_egrets(layer: Control, board: Control, visible: Rect2i, s: float, daylight: float) -> void:
	var vis_a := clampf(daylight * 1.15 + 0.16, 0.25, 1.0)
	var white_col := Color(0.95, 0.96, 0.94, 0.94 * vis_a)
	var sh_col := Color(0.02, 0.05, 0.06, 0.22 * clampf(daylight, 0.0, 1.0))
	for eg: Dictionary in egrets:
		var pos: Vector2 = eg["pos"]
		if not visible.grow(8).has_point(Vector2i(int(pos.x), int(pos.y))):
			continue
		var flying := (str(eg["state"]) == "flying")
		var alt := float(eg["alt"])
		var sp := _world_to_screen(board, pos) + Vector2(0.0, -alt * s * 0.7)
		if flying:
			var fwd := ((eg["target"] as Vector2) - (eg["start"] as Vector2)).normalized()
			var right := Vector2(-fwd.y, fwd.x)
			var flap := sin(time * 5.2 + float(eg["phase"]))
			var span := s * 0.40
			if daylight > 0.12:
				var gsp := _world_to_screen(board, pos) + Vector2(s * 0.9, s * 1.2)
				layer.draw_polyline(PackedVector2Array([gsp - right * span * 0.8, gsp, gsp + right * span * 0.8]), sh_col, maxf(1.5, s * 0.07))
			layer.draw_polyline(PackedVector2Array([
				sp - right * span + fwd * (flap * s * 0.14 - s * 0.08), sp,
				sp + right * span + fwd * (flap * s * 0.14 - s * 0.08)]), white_col, maxf(1.8, s * 0.085))
			layer.draw_line(sp - fwd * (s * 0.16), sp + fwd * (s * 0.24), white_col, maxf(1.5, s * 0.07))
		else:
			if daylight > 0.12:
				layer.draw_circle(sp + Vector2(s * 0.04, s * 0.08), maxf(2.0, s * 0.09), sh_col)
			layer.draw_circle(sp, maxf(2.6, s * 0.11), white_col)
			layer.draw_line(sp, sp + Vector2(s * 0.08, -s * 0.16), white_col, maxf(1.4, s * 0.06))
			layer.draw_line(sp + Vector2(s * 0.08, -s * 0.16), sp + Vector2(s * 0.16, -s * 0.14), Color("c89836", vis_a), maxf(1.1, s * 0.04))


func _draw_geese_flocks(layer: Control, board: Control, visible: Rect2i, s: float, daylight: float) -> void:
	var vis_alpha := clampf(daylight * 1.15 + 0.15, 0.22, 1.0)
	var goose_col := Color(0.18, 0.20, 0.22, 0.92 * vis_alpha)
	var wing_hi := Color(0.84, 0.82, 0.76, 0.78 * vis_alpha)
	var shadow_col := Color(0.02, 0.05, 0.04, 0.20 * clampf(daylight, 0.0, 1.0))
	for f: Dictionary in geese_flocks:
		var leader: Vector2 = f["pos"]
		if not visible.grow(16).has_point(Vector2i(int(leader.x), int(leader.y))):
			continue
		var fwd: Vector2 = (f["vel"] as Vector2).normalized()
		var right := Vector2(-fwd.y, fwd.x)
		var count: int = int(f["count"])
		var fscale: float = float(f["scale"])
		var base_phase: float = float(f["phase"])
		for idx in range(count):
			var rank := (idx + 1) >> 1
			var side := 0.0 if idx == 0 else (-1.0 if idx % 2 == 1 else 1.0)
			var bpos := leader - fwd * (float(rank) * 1.50) + right * (side * float(rank) * 1.18)
			var sp := _world_to_screen(board, bpos)
			var flap := sin(time * 6.5 + base_phase + float(idx) * 0.52)
			var span := s * 0.44 * fscale
			var mid_l := sp - right * (span * 0.52) + fwd * (flap * s * 0.09 * fscale)
			var mid_r := sp + right * (span * 0.52) + fwd * (flap * s * 0.09 * fscale)
			var tip_l := sp - right * span + fwd * (flap * s * 0.18 * fscale - s * 0.14 * fscale)
			var tip_r := sp + right * span + fwd * (flap * s * 0.18 * fscale - s * 0.14 * fscale)
			if daylight > 0.12:
				var sh := Vector2(s * 1.65, s * 2.15)
				layer.draw_polyline(PackedVector2Array([tip_l + sh, mid_l + sh, sp + sh, mid_r + sh, tip_r + sh]), shadow_col, maxf(1.6, s * 0.085))
			layer.draw_polyline(PackedVector2Array([tip_l, mid_l, sp, mid_r, tip_r]), goose_col, maxf(1.9, s * 0.092))
			layer.draw_polyline(PackedVector2Array([mid_l, sp, mid_r]), wing_hi, maxf(1.1, s * 0.042))
			layer.draw_line(sp - fwd * (s * 0.18 * fscale), sp + fwd * (s * 0.24 * fscale), goose_col, maxf(1.6, s * 0.078))
