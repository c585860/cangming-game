extends Control

signal lightning_flashed(distance_norm: float)

# Godot 4.5 Instanced 3D World Renderer driven by CCB's native multi-Z 3D logic (bridge_render3d.cpp).
# Features 1:1 parity with CCB src/render3d.cpp:
# - Multi-Z building stacking, dollhouse translucent upper roofs, clamped door/window sills & lintels
# - Instanced MultiMesh batches across all 6 CCB geometry modes + depth-write-off decal pass
# - Camera->player elliptical screen-door occlusion cutout + cursor-centered peek hole (Z) + same-level wall cut (z)
# - Real calendar sun disc/halo & wind-drifting clouds (ccb_sky3d.gdshader), night vision, map memory presets
# - Hostile/Neutral/Friendly creature silhouette outlines + 3D dynamic point lights + projected combat VFX/SCT/routes
# - Smooth 60fps right-drag orbit camera, scroll zoom, raycast tile picking, and compass-relative movement!

const Tiles = preload("res://scripts/undead_tiles.gd")
const WorldEffects = preload("res://scripts/ccb_native/ccb_world_effects.gd")
const Terrain3DShader = preload("res://shaders/ccb_terrain3d.gdshader")
const Terrain3DDecalShader = preload("res://shaders/ccb_terrain3d_decal.gdshader")
const Sky3DShader = preload("res://shaders/ccb_sky3d.gdshader")
const TiltShift3DShader = preload("res://shaders/ccb_tiltshift3d.gdshader")
const Weather3DShader = preload("res://shaders/ccb_weather3d.gdshader")

const WEATHER_PARTICLES := 720

const LEVEL_HEIGHT := 2.6
const WALL_HEIGHT := 2.55
const ITEM_STRIDE := 56

# CCB_3D_MODE_*
const MODE_BOX := 0
const MODE_XQUAD := 1
const MODE_BILLBOARD := 2
const MODE_BILLBOARD_SNAP := 3
const MODE_LINEQUAD := 4
const MODE_FLATQUAD := 5
const MODE_FLATQUAD_DECAL := 6
const MODE_LINEQUAD_DECAL := 7

# CCB_3D_PICK_*
const PICK_FG := 0
const PICK_BG := 1
const PICK_GROUND := 2
const PICK_FIELD := 3
const PICK_OVERLAY := 4
const PICK_SOLID := 5

# CCB_3D_FLAG_*
const FLAG_TEXTURED := 1 << 0
const FLAG_NO_DISCARD := 1 << 1
const FLAG_HALF_U := 1 << 14
const FLAG_FLIP_U := 1 << 15
const FLAG_BASE_DROP := 1 << 18
const FLAG_ASPECT_WIDTH := 1 << 19
const FLAG_PAPERDOLL_BODY := 1 << 20
const FLAG_PAPERDOLL_LAYER := 1 << 21
const FLAG_MALE := 1 << 22
const FLAG_VEH_FOOTPRINT := 1 << 23

# Exact CCB compass8 order clockwise from North (+X east, +Y south)
const COMPASS8 := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]

var yaw := 0.78539816 # 45 deg (exact CCB default)
var pitch := -0.96    # ~-55 deg looking down (exact CCB default)
var cam_dist := 14.0  # meters (exact CCB default, range 6..30)
var same_level_only := false
var cursor_dither_enabled := true

var _ui_font: Font
var _subvp: SubViewport
var _scene_root: Node3D
var _camera: Camera3D
var _world_env: WorldEnvironment
var _sky_mat: ShaderMaterial
var _view_rect: TextureRect
var _tilt_mat: ShaderMaterial
var _overlay_2d: Control
var _vfx_add_2d: Control
var _effects: WorldEffects

var _mesh_cube: ArrayMesh
var _mesh_xquad: ArrayMesh
var _mesh_quad: ArrayMesh
var _mesh_flatquad: ArrayMesh

# Pooled MultiMeshInstance3D batches keyed by "mode_id|tex_instance_id"
var _batch_pool: Array[MultiMeshInstance3D] = []
var _active_batch_count := 0
var _active_materials: Array[ShaderMaterial] = []
var _active_mat_modes: Array[int] = []

var _scene_snap: Dictionary = {}
var _world_snap: Dictionary = {}
var _has_scene := false
var _last_mouse_local := Vector2(-1.0, -1.0)
var _hover_tile := Vector2i(-99999, -99999)
var _hover_valid := false
var _orbit_dragging := false
var _wind_accum := Vector2.ZERO
var _cam_dirty := true
var _hover_dirty := false
var _last_eye := Vector3.ZERO
var _last_right := Vector3.RIGHT
var _last_up := Vector3.UP
var _last_fwd := Vector3.FORWARD
var _last_player_g := Vector3(0.5, 1.0, 0.5)
var _last_player_gy := 0.0
var _cached_lights_pos_rad: Array[Vector4] = []
var _cached_lights_col_int: Array[Vector4] = []
var _cached_light_count := 0

# Real-time PBR lighting & 3D weather precipitation state
var _light_bundle: Dictionary = {}
var _last_light_dispatch_id := -1
var _weather_mmi: MultiMeshInstance3D
var _weather_mat: ShaderMaterial
var _weather_time := 0.0
var _sky_wind_dt := 0.0
var _lightning_flash := 0.0
var _lightning_cooldown := 3.5
var _pending_subvp_frames := 0


func build(font: Font) -> void:
	_ui_font = font
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_static_meshes()

	# 1. Dedicated 3D SubViewport
	_subvp = SubViewport.new()
	_subvp.disable_3d = false
	_subvp.own_world_3d = true
	_subvp.transparent_bg = false
	_subvp.msaa_3d = Viewport.MSAA_DISABLED
	_subvp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_subvp)

	_scene_root = Node3D.new()
	_subvp.add_child(_scene_root)

	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.near = 0.5
	_camera.far = 360.0
	_camera.current = true
	_scene_root.add_child(_camera)

	# Procedural CCB Sky (gradient, calendar sun disc + halo, drifting fbm clouds, night vision)
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = Sky3DShader
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_world_env = WorldEnvironment.new()
	_world_env.environment = env
	_scene_root.add_child(_world_env)

	# Pure GPU-driven 3D rain streaks & drifting snow volume (0 ms CPU/frame, clipped against indoor roofs!)
	_build_weather_volume()

	# 2. Composite TextureRect with subtle CCB tilt-shift edge polish
	_view_rect = TextureRect.new()
	_view_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_view_rect.texture = _subvp.get_texture()
	_tilt_mat = ShaderMaterial.new()
	_tilt_mat.shader = TiltShift3DShader
	_view_rect.material = _tilt_mat
	add_child(_view_rect)

	# 3. 3D-projected routes, compass ring, SCT & combat smoke/debris overlay
	_effects = WorldEffects.new()
	_overlay_2d = Control.new()
	_overlay_2d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_2d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_2d.draw.connect(_draw_3d_overlay)
	add_child(_overlay_2d)

	# 4. Additive luminous combat VFX projected into 3D space (muzzle flashes, tracers, fireballs, beams!)
	_vfx_add_2d = Control.new()
	_vfx_add_2d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vfx_add_2d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_vfx_add_2d.material = add_mat
	_vfx_add_2d.draw.connect(_draw_3d_additive_vfx)
	add_child(_vfx_add_2d)

	resized.connect(_on_resized)
	_on_resized()
	set_process(true)


func _build_static_meshes() -> void:
	# Cube [0,1]^3 in Godot (X=East, Y=Up, Z=South)
	var cv := PackedVector3Array()
	var cn := PackedVector3Array()
	var faces := [
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)], # bottom
		[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(0, 1, 1), Vector3(0, 1, 0)],  # top
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)], # north
		[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],  # south
		[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)], # west
		[Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 0), Vector3(1, 0, 0)],  # east
	]
	for f in faces:
		var o: Vector3 = f[0]
		var e1: Vector3 = f[1] - o
		var e2: Vector3 = f[2] - o
		var n: Vector3 = f[3]
		var q := [o, o + e1, o + e1 + e2, o, o + e1 + e2, o + e2]
		for p: Vector3 in q:
			cv.append(p)
			cn.append(n)
	var ca := []
	ca.resize(Mesh.ARRAY_MAX)
	ca[Mesh.ARRAY_VERTEX] = cv
	ca[Mesh.ARRAY_NORMAL] = cn
	_mesh_cube = ArrayMesh.new()
	_mesh_cube.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ca)

	# Crossed X-quads (trees, shrubs) in [0,1]^3
	var xv := PackedVector3Array([
		Vector3(0, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1),
		Vector3(0, 1, 0), Vector3(1, 0, 1), Vector3(0, 0, 0),
		Vector3(0, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0),
		Vector3(0, 1, 1), Vector3(1, 0, 0), Vector3(0, 0, 1),
	])
	var xuv := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1),
		Vector2(0, 0), Vector2(1, 1), Vector2(0, 1),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1),
		Vector2(0, 0), Vector2(1, 1), Vector2(0, 1),
	])
	var xa := []
	xa.resize(Mesh.ARRAY_MAX)
	xa[Mesh.ARRAY_VERTEX] = xv
	xa[Mesh.ARRAY_TEX_UV] = xuv
	_mesh_xquad = ArrayMesh.new()
	_mesh_xquad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, xa)

	# Bottom-centered vertical unit quad: x in [-0.5, 0.5], y in [0, 1]
	var qv := PackedVector3Array([
		Vector3(-0.5, 1, 0), Vector3(0.5, 1, 0), Vector3(0.5, 0, 0),
		Vector3(-0.5, 1, 0), Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0),
	])
	var quv := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1),
		Vector2(0, 0), Vector2(1, 1), Vector2(0, 1),
	])
	var qa := []
	qa.resize(Mesh.ARRAY_MAX)
	qa[Mesh.ARRAY_VERTEX] = qv
	qa[Mesh.ARRAY_TEX_UV] = quv
	_mesh_quad = ArrayMesh.new()
	_mesh_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, qa)

	# Flat horizontal quad [0,1] x [0,1] at y=0
	var fv := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1),
		Vector3(0, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
	])
	var fuv := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1),
		Vector2(0, 0), Vector2(1, 1), Vector2(0, 1),
	])
	var fa := []
	fa.resize(Mesh.ARRAY_MAX)
	fa[Mesh.ARRAY_VERTEX] = fv
	fa[Mesh.ARRAY_TEX_UV] = fuv
	_mesh_flatquad = ArrayMesh.new()
	_mesh_flatquad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fa)


func _build_weather_volume() -> void:
	_weather_mmi = MultiMeshInstance3D.new()
	_weather_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh_quad
	mm.instance_count = WEATHER_PARTICLES
	mm.custom_aabb = AABB(Vector3(-48.0, -8.0, -48.0), Vector3(96.0, 32.0, 96.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261127
	for i in range(WEATHER_PARTICLES):
		var seed_pos := Vector3(rng.randf(), rng.randf(), rng.randf())
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, seed_pos))
		mm.set_instance_custom_data(i, Color(float(i) / float(WEATHER_PARTICLES), rng.randf(), 0.0, 0.0))
	_weather_mmi.multimesh = mm
	_weather_mat = ShaderMaterial.new()
	_weather_mat.shader = Weather3DShader
	_weather_mmi.material_override = _weather_mat
	_weather_mmi.visible = false
	_scene_root.add_child(_weather_mmi)


func _on_resized() -> void:
	var w := maxi(64, int(size.x))
	var h := maxi(64, int(size.y))
	if _subvp != null and _subvp.size != Vector2i(w, h):
		_subvp.size = Vector2i(w, h)
		_cam_dirty = true
		if visible and _has_scene:
			_subvp.render_target_update_mode = SubViewport.UPDATE_ONCE


func reset_camera() -> void:
	yaw = 0.78539816
	pitch = -0.96
	cam_dist = 14.0
	_cam_dirty = true
	_request_3d_render()


func note_mouse_look(dx: float, dy: float) -> void:
	# Exact CCB render3d.cpp orbit sensitivity & pitch clamp (~-4.6 deg .. -80 deg)
	yaw -= dx * 0.0042
	pitch = clampf(pitch - dy * 0.0042, -1.40, -0.10)
	_cam_dirty = true
	_request_3d_render()


func note_mouse_wheel(ticks: float) -> void:
	cam_dist = clampf(cam_dist - ticks * 1.5, 6.0, 30.0)
	_cam_dirty = true
	_request_3d_render()


func set_orbit_dragging(dragging: bool) -> void:
	if _orbit_dragging != dragging:
		_orbit_dragging = dragging
		_cam_dirty = true
		_request_3d_render()


func set_same_level_only(enabled: bool) -> void:
	same_level_only = enabled
	_cam_dirty = true
	_request_3d_render()


func set_cursor_dither(enabled: bool) -> void:
	cursor_dither_enabled = enabled
	_cam_dirty = true
	_request_3d_render()


func note_mouse_global(global_pos: Vector2) -> void:
	var lp := global_pos - get_global_rect().position
	if (lp - _last_mouse_local).length_squared() >= 1.0:
		_last_mouse_local = lp
		_hover_dirty = true
		var wt := screen_to_world_tile(global_pos)
		if wt != _hover_tile:
			_hover_tile = wt
			_hover_valid = (wt.x > -90000)
			if _overlay_2d != null:
				_overlay_2d.queue_redraw()
		if cursor_dither_enabled and visible and _has_scene:
			_update_camera_and_uniforms()
			_request_3d_render()


# Exact CCB camera_forward_octant(): compass octant (0=N, 1=NE, 2=E, ..., 7=NW) pointing toward top of screen
func camera_forward_octant() -> int:
	var bearing := atan2(cos(yaw), -sin(yaw))
	var k := int(round(bearing / (PI * 0.25))) % 8
	return k + 8 if k < 0 else k


# Rotates a screen-frame compass step (e.g. Up = (0,-1)) into CCB map coordinates!
func screen_delta_to_map_delta(d: Vector2i) -> Vector2i:
	var idx := COMPASS8.find(d)
	if idx < 0:
		return d
	var steps := camera_forward_octant()
	return COMPASS8[(idx + steps + 16) % 8]


func is_controlling_vehicle() -> bool:
	return bool(_scene_snap.get("controlling_vehicle", false))


func get_view_center_tile() -> Vector2i:
	return _scene_snap.get("center", _world_snap.get("center", Vector2i.ZERO))


# Exact 3D ground-plane raycast onto the current view level (y = 0 in Godot space)
func screen_to_world_tile(global_pos: Vector2) -> Vector2i:
	if not _has_scene or _camera == null or size.x <= 1.0 or size.y <= 1.0:
		return Vector2i(-99999, -99999)
	var lp := global_pos - get_global_rect().position
	var vp_pt := Vector2(
		lp.x * float(_subvp.size.x) / size.x,
		lp.y * float(_subvp.size.y) / size.y
	)
	var ro := _camera.project_ray_origin(vp_pt)
	var rd := _camera.project_ray_normal(vp_pt)
	if rd.y >= -0.0001:
		return Vector2i(-99999, -99999)
	var t := -ro.y / rd.y
	var hit := ro + rd * t
	var center: Vector2i = _scene_snap.get("center", Vector2i.ZERO)
	return Vector2i(center.x + int(floor(hit.x)), center.y + int(floor(hit.z)))


func _project_ccb_to_screen(ccb_rel_x: float, ccb_rel_y: float, ccb_rel_z: float) -> Vector2:
	if _camera == null or _subvp == null or _subvp.size.x <= 0 or _subvp.size.y <= 0:
		return Vector2(-9999.0, -9999.0)
	var wp := Vector3(ccb_rel_x, ccb_rel_z, ccb_rel_y)
	if _camera.is_position_behind(wp):
		return Vector2(-9999.0, -9999.0)
	var p := _camera.unproject_position(wp)
	return Vector2(p.x * size.x / float(_subvp.size.x), p.y * size.y / float(_subvp.size.y))


func get_active_vfx_lights() -> Array:
	return _effects.get_active_vfx_lights() if _effects != null else []


func update_snapshots(scene_snap: Dictionary, world_snap: Dictionary, light_bundle: Dictionary = {}) -> void:
	_world_snap = world_snap
	if not light_bundle.is_empty():
		_light_bundle = light_bundle
	if _effects != null and bool(world_snap.get("valid", false)):
		_effects.sync_snapshot(world_snap)
	if not bool(scene_snap.get("valid", false)):
		return
	_scene_snap = scene_snap
	_has_scene = true
	_rebuild_scene_batches()
	_cam_dirty = true
	_update_camera_and_uniforms()
	_apply_lighting_uniforms_to_all()
	# Render 2 consecutive frames so decoupled direct_viewport/blur_viewport UPDATE_ONCE outputs are always settled!
	_pending_subvp_frames = maxi(_pending_subvp_frames, 2)
	_request_3d_render()


func apply_lighting_bundle(bundle: Dictionary) -> void:
	if bundle.is_empty():
		return
	_light_bundle = bundle
	if not _has_scene:
		return
	var did := int(bundle.get("dispatch_id", -1))
	if did != _last_light_dispatch_id:
		_last_light_dispatch_id = did
		_apply_lighting_uniforms_to_all()
		_pending_subvp_frames = maxi(_pending_subvp_frames, 2)
		_request_3d_render()


func has_high_fps_activity() -> bool:
	if not visible or not _has_scene:
		return false
	if _orbit_dragging or _cam_dirty or _pending_subvp_frames > 0 or _lightning_flash > 0.005:
		return true
	if _weather_mmi != null and _weather_mmi.visible:
		return true
	if _effects != null and _effects.has_high_fps_activity():
		return true
	return false


func release_idle_resources() -> void:
	_has_scene = false
	_scene_snap = {}
	_active_materials.clear()
	_active_mat_modes.clear()
	_active_batch_count = 0
	for mmi in _batch_pool:
		if mmi != null:
			mmi.visible = false
			if mmi.multimesh != null:
				mmi.multimesh.instance_count = 0
	if _subvp != null:
		_subvp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _request_3d_render() -> void:
	if not visible or not _has_scene or _subvp == null:
		return
	_subvp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _overlay_2d != null:
		_overlay_2d.queue_redraw()
	if _vfx_add_2d != null:
		_vfx_add_2d.queue_redraw()


func _process(delta: float) -> void:
	if not visible or not _has_scene:
		return
	var need_render := false
	var wx: float = float(_scene_snap.get("wind_x", 0.0))
	var wy: float = float(_scene_snap.get("wind_y", 0.0))
	if absf(wx) + absf(wy) > 0.0001:
		_wind_accum += Vector2(wx, wy) * delta
		_sky_wind_dt += delta
		if _sky_wind_dt >= 0.08: # ~12 Hz sky cloud drift update instead of 60 Hz idle uniform churn
			_sky_wind_dt = 0.0
			if _sky_mat != null:
				_sky_mat.set_shader_parameter("u_wind_offset", _wind_accum)

	var rain := float(_light_bundle.get("rain", 0.0))
	var snow := float(_light_bundle.get("snow", 0.0))
	var wetness := float(_light_bundle.get("wetness", 0.0))
	var is_under := bool(_light_bundle.get("is_underground", false))
	var has_water := bool(_world_snap.get("has_water", false))
	var weather_anim := (not is_under) and (rain > 0.02 or snow > 0.02 or wetness > 0.05 or has_water)

	# Thunderstorm occasional lightning flash in 3D sky + outdoor terrain!
	var wid := str(_world_snap.get("weather", "")).to_lower()
	var is_thunder := (not is_under) and (rain >= 0.85 or "thunder" in wid or "lightning" in wid)
	if is_thunder:
		_lightning_cooldown -= delta
		if _lightning_cooldown <= 0.0:
			_lightning_flash = 0.92
			_lightning_cooldown = 4.2 + fmod(_weather_time * 3.17, 5.5)
			lightning_flashed.emit(fmod(_weather_time * 0.41, 0.85))
	if _lightning_flash > 0.005:
		_lightning_flash = maxf(0.0, _lightning_flash - delta * 3.8)
		weather_anim = true

	if weather_anim:
		_weather_time += delta
		if _tilt_mat != null:
			_tilt_mat.set_shader_parameter("u_time", _weather_time)
		var w_fx := Vector4(_weather_time, _lightning_flash, float(_light_bundle.get("moon_energy", 0.0)), 1.0 if is_under else 0.0)
		for mat in _active_materials:
			mat.set_shader_parameter("u_weather_fx", w_fx)
		if _weather_mat != null and _weather_mmi != null and _weather_mmi.visible:
			_weather_mat.set_shader_parameter("u_time", _weather_time)
			_weather_mat.set_shader_parameter("u_lightning", _lightning_flash)
		if _sky_mat != null:
			var sun_col_v: Vector3 = _light_bundle.get("sun_color", Vector3(1.0, 0.94, 0.84))
			_sky_mat.set_shader_parameter("u_sun_col_flash", Vector4(sun_col_v.x, sun_col_v.y, sun_col_v.z, _lightning_flash))
		need_render = true

	var vfx_active := false
	if _effects != null:
		var gliding := _effects.tick(delta)
		vfx_active = gliding or _effects.needs_continuous_redraw()
		if vfx_active:
			_overlay_2d.queue_redraw()
			_vfx_add_2d.queue_redraw()
			# Refresh dynamic 3D VFX point lights (muzzle flash / blast illumination on 3D walls!)
			var vlights := _effects.get_active_vfx_lights()
			if not vlights.is_empty():
				_push_dynamic_lights_to_materials(vlights)
				need_render = true

	if _cam_dirty:
		_update_camera_and_uniforms()
		need_render = true

	if _pending_subvp_frames > 0:
		_pending_subvp_frames -= 1
		need_render = true

	if need_render:
		if _tilt_mat != null and not weather_anim:
			_tilt_mat.set_shader_parameter("u_time", _weather_time)
		_subvp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_overlay_2d.queue_redraw()
	Tiles.finish_frame()


func _update_camera_and_uniforms() -> void:
	_cam_dirty = false
	if _camera == null or not _has_scene:
		return

	# Exact CCB orbit camera mapped to Godot right-handed space (X=East, Y=Up, Z=South)
	var target := Vector3(0.5, 1.0, 0.5)
	var dir := Vector3(cos(pitch) * cos(yaw), sin(pitch), cos(pitch) * sin(yaw)).normalized()
	var eye := target - dir * cam_dist
	_camera.look_at_from_position(eye, target, Vector3.UP)

	var basis := _camera.global_transform.basis
	_last_eye = eye
	_last_right = basis.x.normalized()
	_last_up = basis.y.normalized()
	_last_fwd = (-basis.z).normalized()

	var center: Vector2i = _scene_snap.get("center", Vector2i.ZERO)
	var player: Vector2i = _scene_snap.get("player", Vector2i.ZERO)
	var cz := int(_scene_snap.get("center_z", 0))
	var pz := int(_scene_snap.get("player_z", 0))
	_last_player_gy = float(pz - cz) * LEVEL_HEIGHT
	_last_player_g = Vector3(
		float(player.x - center.x) + 0.5,
		_last_player_gy + 1.0,
		float(player.y - center.y) + 0.5
	)

	var sun_g := Vector3(
		float(_scene_snap.get("sun_x", 0.4)),
		float(_scene_snap.get("sun_z", 0.85)),
		float(_scene_snap.get("sun_y", 0.3))
	)
	var sun_up := float(_scene_snap.get("sun_up", 1.0))
	var daylight := float(_scene_snap.get("daylight", 1.0))
	var cloudiness := float(_scene_snap.get("cloudiness", 0.25))
	var nv_active := float(_scene_snap.get("nv_active", 0.0))
	var nv_floor := float(_scene_snap.get("nv_floor", 0.55))
	var nv_over := float(_scene_snap.get("nv_overexpose", 0.85))
	var mem_preset := int(_scene_snap.get("memory_preset", 0))

	if bool(_light_bundle.get("valid", false)):
		var sr: Vector3 = _light_bundle.get("sun_ray", Vector3(0.4, 0.3, 0.85))
		sun_g = Vector3(sr.x, sr.z, sr.y).normalized()
		sun_up = 1.0 if float(_light_bundle.get("sun_energy", 0.0)) > 0.01 else 0.0
		daylight = clampf(float(_light_bundle.get("daylight", daylight)), 0.0, 1.0)
		cloudiness = maxf(cloudiness, float(_light_bundle.get("cloud", 0.0)))

	if _sky_mat != null:
		_sky_mat.set_shader_parameter("u_sun_dir", Vector4(sun_g.x, sun_g.y, sun_g.z, daylight))
		_sky_mat.set_shader_parameter("u_cloudiness", cloudiness)
		_sky_mat.set_shader_parameter("u_nv_active", nv_active)
		_sky_mat.set_shader_parameter("u_wind_offset", _wind_accum)

	if _weather_mat != null:
		_weather_mat.set_shader_parameter("u_cam_right", _last_right)

	var cx_uv := _last_mouse_local.x / maxf(1.0, size.x)
	var cy_uv := _last_mouse_local.y / maxf(1.0, size.y)
	var cursor_on := cursor_dither_enabled and (not _orbit_dragging) and cx_uv >= 0.0 and cx_uv <= 1.0 and cy_uv >= 0.0 and cy_uv <= 1.0
	var cursor_p := Vector4(cx_uv, cy_uv, 1.0 if cursor_on else 0.0, 0.0)
	var effect_p := Vector4(0.075, 0.10, 1.0 / WALL_HEIGHT, 1.0 if same_level_only else 0.0)
	var nv_p := Vector4(nv_active, nv_floor, nv_over, 0.0)
	var sun_p := Vector4(sun_g.x, sun_g.y, sun_g.z, sun_up)

	for i in range(_active_materials.size()):
		var mat := _active_materials[i]
		var md := _active_mat_modes[i]
		var mask_en := 1.0 if (md == MODE_BOX or md == MODE_LINEQUAD or md == MODE_FLATQUAD or md == MODE_LINEQUAD_DECAL) else 0.0
		mat.set_shader_parameter("u_cam_right", _last_right)
		mat.set_shader_parameter("u_cam_up", _last_up)
		mat.set_shader_parameter("u_cam_fwd", _last_fwd)
		mat.set_shader_parameter("u_sun_dir", sun_p)
		mat.set_shader_parameter("u_eye_pos", _last_eye)
		mat.set_shader_parameter("u_player_pos", _last_player_g)
		mat.set_shader_parameter("u_mask_params", Vector4(3.2, 2.2, _last_player_gy, mask_en))
		mat.set_shader_parameter("u_cursor_params", cursor_p)
		mat.set_shader_parameter("u_effect_params", effect_p)
		mat.set_shader_parameter("u_memory_preset", mem_preset)
		mat.set_shader_parameter("u_nv_params", nv_p)


func _apply_lighting_uniforms_to_all() -> void:
	if not _has_scene:
		return
	var has_lm := bool(_light_bundle.get("valid", false))
	var center: Vector2i = _scene_snap.get("center", Vector2i.ZERO)
	var center_xy := Vector2(float(center.x), float(center.y))

	var sun_col: Vector3 = _light_bundle.get("sun_color", Vector3(1.0, 0.94, 0.84))
	var sun_energy := float(_light_bundle.get("sun_energy", 0.85))
	var sky_col: Vector3 = _light_bundle.get("sky_color", Vector3(0.74, 0.86, 1.0))
	var sky_energy := float(_light_bundle.get("sky_energy", 0.75))
	var moon_energy := float(_light_bundle.get("moon_energy", 0.0))
	var daylight := clampf(float(_light_bundle.get("daylight", _scene_snap.get("daylight", 1.0))), 0.0, 1.0)
	var is_under := bool(_light_bundle.get("is_underground", false))
	var rain := float(_light_bundle.get("rain", 0.0))
	var snow := float(_light_bundle.get("snow", 0.0))
	var cloud := maxf(float(_scene_snap.get("cloudiness", 0.25)), float(_light_bundle.get("cloud", 0.0)))
	var wetness := float(_light_bundle.get("wetness", 0.0))
	var snow_cov := float(_light_bundle.get("snow_cover", 0.0))
	var mist := float(_light_bundle.get("mist", 0.16))
	var plight := float(_light_bundle.get("player_light", 0.0))
	var pworld: Vector2 = _light_bundle.get("player_world", Vector2(center))

	# Match 3D atmospheric distance fog smoothly to the sky shader horizon color!
	var night_horizon := Vector3(0.020, 0.026, 0.044)
	var day_horizon := Vector3(sky_col.x * 0.76, sky_col.y * 0.82, sky_col.z * 0.90)
	var base_fog := night_horizon.lerp(day_horizon, daylight)
	var mist_tint := Vector3(0.06, 0.075, 0.10).lerp(Vector3(0.68, 0.74, 0.80), daylight)
	var fog_rgb := base_fog.lerp(mist_tint, clampf(mist * 0.72, 0.0, 1.0))
	if snow > 0.25:
		fog_rgb = fog_rgb.lerp(Vector3(0.76, 0.82, 0.90) * maxf(0.15, daylight), snow * 0.45)

	var sun_ce := Vector4(sun_col.x, sun_col.y, sun_col.z, sun_energy)
	var sky_ce := Vector4(sky_col.x, sky_col.y, sky_col.z, sky_energy)
	var w_params := Vector4(wetness, rain, snow_cov, mist)
	var w_fx := Vector4(_weather_time, _lightning_flash, moon_energy, 1.0 if is_under else 0.0)
	var fog_v4 := Vector4(fog_rgb.x, fog_rgb.y, fog_rgb.z, 1.0)
	var p_light_v4 := Vector4(
		pworld.x + 0.5 - center_xy.x,
		_last_player_gy + 1.15,
		pworld.y + 0.5 - center_xy.y,
		plight
	)
	var p_cone_v4: Vector4 = _light_bundle.get("player_light_cone", Vector4(1.0, 0.0, -1.0, 0.0))
	if _effects != null:
		_effects.sync_environment(_light_bundle)

	var direct_tex: Texture2D = _light_bundle.get("direct_tex", null)
	var gi_tex: Texture2D = _light_bundle.get("gi_tex", null)
	var geom_tex: Texture2D = _light_bundle.get("geom_tex", null)
	var mat_tex: Texture2D = _light_bundle.get("mat_tex", null)
	var lmin: Vector2 = _light_bundle.get("light_min", Vector2.ZERO)
	var lspan: Vector2 = _light_bundle.get("light_span", Vector2(44.0, 36.0))
	var gorig: Vector2 = _light_bundle.get("grid_origin", Vector2.ZERO)
	var gsz: Vector2 = _light_bundle.get("grid_size", Vector2(61.0, 41.0))

	if _sky_mat != null:
		var sr: Vector3 = _light_bundle.get("sun_ray", Vector3(0.4, 0.3, 0.85))
		var sun_g := Vector3(sr.x, sr.z, sr.y).normalized()
		_sky_mat.set_shader_parameter("u_sun_dir", Vector4(sun_g.x, sun_g.y, sun_g.z, daylight))
		_sky_mat.set_shader_parameter("u_sky_col_mist", Vector4(sky_col.x, sky_col.y, sky_col.z, mist))
		_sky_mat.set_shader_parameter("u_sun_col_flash", Vector4(sun_col.x, sun_col.y, sun_col.z, _lightning_flash))
		_sky_mat.set_shader_parameter("u_cloudiness", cloud)

	if _weather_mmi != null and _weather_mat != null:
		var precip := (not is_under) and (maxf(rain, snow) > 0.02)
		_weather_mmi.visible = precip
		if precip:
			var wx := float(_scene_snap.get("wind_x", 0.0))
			var wy := float(_scene_snap.get("wind_y", 0.0))
			var wvec := Vector2(wx, wy)
			if wvec.length() < 0.05:
				wvec = Vector2(0.85, 0.25)
			else:
				wvec = wvec.normalized() * clampf(wvec.length() * 6.0, 0.5, 2.2)
			_weather_mat.set_shader_parameter("u_rain", rain)
			_weather_mat.set_shader_parameter("u_snow", snow)
			_weather_mat.set_shader_parameter("u_daylight", daylight)
			_weather_mat.set_shader_parameter("u_lightning", _lightning_flash)
			_weather_mat.set_shader_parameter("u_time", _weather_time)
			_weather_mat.set_shader_parameter("u_wind", wvec)
			_weather_mat.set_shader_parameter("u_cam_right", _last_right)
			_weather_mat.set_shader_parameter("u_has_geom", has_lm and geom_tex != null)
			if geom_tex != null:
				_weather_mat.set_shader_parameter("u_geom_tex", geom_tex)
			_weather_mat.set_shader_parameter("u_center_xy", center_xy)
			_weather_mat.set_shader_parameter("u_grid_origin", gorig)
			_weather_mat.set_shader_parameter("u_grid_size", gsz)

	for mat in _active_materials:
		mat.set_shader_parameter("u_has_lightmap", has_lm)
		if has_lm:
			if direct_tex != null:
				mat.set_shader_parameter("u_direct_tex", direct_tex)
			if gi_tex != null:
				mat.set_shader_parameter("u_gi_tex", gi_tex)
			if geom_tex != null:
				mat.set_shader_parameter("u_geom_tex", geom_tex)
			if mat_tex != null:
				mat.set_shader_parameter("u_mat_tex", mat_tex)
		mat.set_shader_parameter("u_center_xy", center_xy)
		mat.set_shader_parameter("u_light_min", lmin)
		mat.set_shader_parameter("u_light_span", lspan)
		mat.set_shader_parameter("u_grid_origin", gorig)
		mat.set_shader_parameter("u_grid_size", gsz)
		mat.set_shader_parameter("u_sun_col_energy", sun_ce)
		mat.set_shader_parameter("u_sky_col_energy", sky_ce)
		mat.set_shader_parameter("u_weather_params", w_params)
		mat.set_shader_parameter("u_weather_fx", w_fx)
		mat.set_shader_parameter("u_fog_color", fog_v4)
		mat.set_shader_parameter("u_player_light", p_light_v4)
		mat.set_shader_parameter("u_player_light_cone", p_cone_v4)


func _push_dynamic_lights_to_materials(vfx_lights: Array) -> void:
	var pos_rad: Array[Vector4] = _cached_lights_pos_rad.duplicate()
	var col_int: Array[Vector4] = _cached_lights_col_int.duplicate()
	var cnt := _cached_light_count
	var center: Vector2i = _scene_snap.get("center", Vector2i.ZERO)
	for vl in vfx_lights:
		if cnt >= 12:
			break
		var pos_w: Vector2 = vl.get("pos", Vector2.ZERO)
		var col: Color = vl.get("color", Color(1.0, 0.72, 0.35))
		var inten := float(vl.get("intensity", 1.5))
		pos_rad[cnt] = Vector4(pos_w.x - float(center.x), 1.15, pos_w.y - float(center.y), clampf(inten * 1.4 + 3.0, 3.5, 16.0))
		col_int[cnt] = Vector4(col.r, col.g, col.b, clampf(inten * 0.45, 0.3, 2.5))
		cnt += 1
	for mat in _active_materials:
		mat.set_shader_parameter("u_light_count", cnt)
		mat.set_shader_parameter("u_light_pos_rad", pos_rad)
		mat.set_shader_parameter("u_light_col_int", col_int)


func _acquire_batch(idx: int) -> MultiMeshInstance3D:
	while _batch_pool.size() <= idx:
		var mmi := MultiMeshInstance3D.new()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.custom_aabb = AABB(Vector3(-512.0, -128.0, -512.0), Vector3(1024.0, 256.0, 1024.0))
		mmi.multimesh = mm
		_scene_root.add_child(mmi)
		_batch_pool.append(mmi)
	return _batch_pool[idx]


func _rebuild_scene_batches() -> void:
	var items_bytes: PackedByteArray = _scene_snap.get("items", PackedByteArray())
	var item_count := int(_scene_snap.get("item_count", 0))
	var stride := int(_scene_snap.get("item_stride", ITEM_STRIDE))
	var strings: PackedStringArray = _scene_snap.get("strings", PackedStringArray())
	var s_len := strings.size()
	if item_count <= 0 or items_bytes.size() < item_count * stride:
		for b in _batch_pool:
			b.visible = false
		_active_batch_count = 0
		_active_materials.clear()
		_active_mat_modes.clear()
		return

	var season_names := ["spring", "summer", "autumn", "winter"]
	var season_key: String = season_names[clampi(int(_scene_snap.get("season", 0)), 0, 3)]
	var white_tex := Tiles.get_fallback_white_tex()

	# Cache world 3D dynamic lights from snapshot (max 12)
	_cached_lights_pos_rad.resize(12)
	_cached_lights_col_int.resize(12)
	for i in range(12):
		_cached_lights_pos_rad[i] = Vector4.ZERO
		_cached_lights_col_int[i] = Vector4.ZERO
	var snap_lights: Array = _scene_snap.get("lights", [])
	_cached_light_count = mini(snap_lights.size(), 12)
	for i in range(_cached_light_count):
		var ld: Dictionary = snap_lights[i]
		_cached_lights_pos_rad[i] = Vector4(float(ld["px"]), float(ld["pz"]), float(ld["py"]), float(ld["radius"]))
		_cached_lights_col_int[i] = Vector4(float(ld["r"]), float(ld["g"]), float(ld["b"]), float(ld["intensity"]))

	# Bucket instances by (mode, atlas_texture_id)
	# Each bucket holds: { "mode": int, "tex": Texture2D, "xforms": Array[Transform3D], "colors": Array[Color], "customs": Array[Color] }
	var buckets := {}
	var bucket_order: Array = []

	var add_inst := func(mode: int, tex: Texture2D, pos_g: Vector3, sx: float, sy: float, sz: float,
			col: Color, uv_rect: Color, flags: int, pad_f: float) -> void:
		var use_tex := tex if tex != null else white_tex
		var key := "%d|%d" % [mode, use_tex.get_instance_id()]
		var b: Dictionary
		if buckets.has(key):
			b = buckets[key]
		else:
			b = {"mode": mode, "tex": use_tex, "xforms": [], "colors": [], "customs": []}
			buckets[key] = b
			bucket_order.append(b)
		var bas := Basis(
			Vector3(sx, float(flags & 0x3FFF), pad_f),
			Vector3(0.0, sy, 0.0),
			Vector3(0.0, 0.0, sz)
		)
		(b["xforms"] as Array).append(Transform3D(bas, pos_g))
		(b["colors"] as Array).append(col)
		(b["customs"] as Array).append(uv_rect)

	# Track last paperdoll body sprite metrics so worn/wielded overlays align 1:1 with the body!
	var body_px_scale := 0.0
	var body_bottom_px := 0.0
	var body_zbase := 0.0
	var body_valid := false

	for i in range(item_count):
		var off := i * stride
		var px := items_bytes.decode_float(off + 0)
		var py := items_bytes.decode_float(off + 4)
		var pz := items_bytes.decode_float(off + 8)
		var sx := items_bytes.decode_float(off + 12)
		var sy := items_bytes.decode_float(off + 16)
		var sz := items_bytes.decode_float(off + 20)
		var cr := items_bytes.decode_float(off + 24)
		var cg := items_bytes.decode_float(off + 28)
		var cb := items_bytes.decode_float(off + 32)
		var csat := items_bytes.decode_float(off + 36)
		var flags := items_bytes.decode_u32(off + 40)
		var str_id := items_bytes.decode_u16(off + 44)
		var mode := items_bytes.decode_u8(off + 46)
		var pick := items_bytes.decode_u8(off + 47)
		var sub_raw := items_bytes.decode_u8(off + 48)
		var rot := items_bytes.decode_u8(off + 49)
		var v0_u8 := items_bytes.decode_u8(off + 50)
		var v1_u8 := items_bytes.decode_u8(off + 51)
		var seed_v := items_bytes.decode_u16(off + 52)
		var pad_f := float(items_bytes.decode_s16(off + 54)) * 0.001

		var sid := strings[str_id] if str_id > 0 and str_id < s_len else ""
		var tex: Texture2D = null
		var u0 := 0.0
		var v0 := 0.0
		var u1 := 1.0
		var v1 := 1.0
		var sh_flags := flags & 0x3FFF

		if pick != PICK_SOLID and not sid.is_empty():
			var sub_arg := -1
			var fld_int := 1
			if pick == PICK_FIELD:
				var lo := sub_raw & 0x0F
				sub_arg = -1 if lo >= 8 else lo
				fld_int = clampi((sub_raw >> 4) & 0x0F, 1, 3)
			else:
				sub_arg = -1 if sub_raw >= 8 else sub_raw
			var is_male := (flags & FLAG_MALE) != 0
			var sp := Tiles.resolve_3d_sprite(sid, season_key, seed_v, sub_arg, rot, pick, is_male, fld_int)
			if sp.is_empty():
				# Skip missing optional overlays/decals/items cleanly; keep fog/solid fallback for walls/floors
				if pick == PICK_OVERLAY or pick == PICK_FIELD or mode == MODE_FLATQUAD or mode == MODE_FLATQUAD_DECAL:
					continue
				if sid == "highlight_item":
					continue
				sh_flags &= ~FLAG_TEXTURED
			else:
				tex = sp["tex"]
				var rot4 := int(sp["rot4"])
				sh_flags = (sh_flags & ~(3 << 2)) | ((rot4 & 3) << 2)
				if pick == PICK_GROUND:
					# Plain floor with transparent cutout corners uses flatquad instead of opaque box!
					if mode == MODE_BOX and (not bool(sp["used_bg"])) and bool(sp["has_trans"]):
						mode = MODE_FLATQUAD
						pz += 0.1
						sh_flags &= ~FLAG_NO_DISCARD
						u0 = float(sp["u0"]); v0 = float(sp["v0"]); u1 = float(sp["u1"]); v1 = float(sp["v1"])
					else:
						u0 = float(sp["gu0"]); v0 = float(sp["gv0"]); u1 = float(sp["gu1"]); v1 = float(sp["gv1"])
				elif mode == MODE_FLATQUAD and pick == PICK_FG and (not bool(sp["has_bg"])):
					# Already drawn as ground slab when tile has no separate bg layer!
					continue
				else:
					u0 = float(sp["u0"]); v0 = float(sp["v0"]); u1 = float(sp["u1"]); v1 = float(sp["v1"])

				# Vertical UV slice (e.g. window sill & door/window wall lintel!)
				if v0_u8 > 0 or v1_u8 < 255:
					var dv := v1 - v0
					var nv0 := v0 + dv * (float(v0_u8) / 255.0)
					var nv1 := v0 + dv * (float(v1_u8) / 255.0)
					v0 = nv0
					v1 = nv1

				if (flags & FLAG_HALF_U) != 0:
					u1 = u0 + (u1 - u0) * 0.5
				if (flags & FLAG_FLIP_U) != 0:
					var tmp := u0; u0 = u1; u1 = tmp

				var aspect := clampf(float(sp["aspect"]), 0.4, 2.5)
				var base_drop := float(sp["base_drop"])
				var px_w := int(sp["px_w"])
				var px_h := int(sp["px_h"])
				var spr_off: Vector2i = sp["offset"]

				if (flags & FLAG_VEH_FOOTPRINT) != 0 and px_w > 0 and px_h > 0:
					px += float(spr_off.x) / 32.0
					py += float(spr_off.y) / 32.0
					sx = float(px_w) / 32.0
					sy = float(px_h) / 32.0
				elif (flags & FLAG_PAPERDOLL_BODY) != 0:
					sx = sy * aspect
					pz -= sy * base_drop
					body_valid = (px_h > 0 and px_w > 0)
					if body_valid:
						body_px_scale = sy / float(px_h)
						body_bottom_px = float(spr_off.y + px_h)
						body_zbase = pz
				elif (flags & FLAG_PAPERDOLL_LAYER) != 0:
					if not body_valid or px_h <= 0:
						continue
					var oh := float(px_h) * body_px_scale
					var ow := oh * aspect
					var zbot := body_zbase - (float(spr_off.y + px_h) - body_bottom_px) * body_px_scale
					sx = ow
					sy = oh
					pz = zbot
				else:
					if (flags & FLAG_ASPECT_WIDTH) != 0:
						sx = sy * aspect * sx
					if (flags & FLAG_BASE_DROP) != 0:
						var drop_h := sz if mode == MODE_XQUAD else sy
						pz -= drop_h * base_drop
		else:
			sh_flags &= ~FLAG_TEXTURED

		# Map CCB (px=East, py=South, pz=Up) -> Godot (X=East, Y=Up, Z=South)
		var pos_g := Vector3(px, pz, py)
		add_inst.call(mode, tex, pos_g, sx, sy, sz, Color(cr, cg, cb, csat), Color(u0, v0, u1, v1), sh_flags, pad_f)

	# Add CCB's vehicle direction indicator (forward step marker is drawn live at 60fps in _draw_3d_overlay!)
	var center: Vector2i = _scene_snap.get("center", Vector2i.ZERO)
	if bool(_scene_snap.get("controlling_vehicle", false)):
		var vx := int(_scene_snap.get("veh_ind_x", -2147483648))
		var vy := int(_scene_snap.get("veh_ind_y", -2147483648))
		if vx > -10000 and vy > -10000:
			var csp := Tiles.resolve_3d_sprite("cursor", season_key, 0, -1, 0, PICK_FG, true)
			if not csp.is_empty():
				add_inst.call(MODE_BOX, csp["tex"], Vector3(float(vx), 0.005, float(vy)), 1.0, 1.0, 0.05,
					Color(1, 1, 1, 1), Color(csp["u0"], csp["v0"], csp["u1"], csp["v1"]), FLAG_TEXTURED, 0.0)

	# Upload pooled MultiMeshInstance3D batches (zero per-frame node churn!)
	_active_materials.clear()
	_active_mat_modes.clear()
	_active_batch_count = bucket_order.size()

	for bi in range(bucket_order.size()):
		var b: Dictionary = bucket_order[bi]
		var mode := int(b["mode"])
		var tex: Texture2D = b["tex"]
		var xforms: Array = b["xforms"]
		var cols: Array = b["colors"]
		var custs: Array = b["customs"]
		var cnt := xforms.size()

		var mmi := _acquire_batch(bi)
		var mm := mmi.multimesh
		var want_mesh := _mesh_for_mode(mode)
		if mm.mesh != want_mesh:
			mm.mesh = want_mesh
		if mm.instance_count != cnt:
			mm.instance_count = cnt
		for k in range(cnt):
			mm.set_instance_transform(k, xforms[k])
			mm.set_instance_color(k, cols[k])
			mm.set_instance_custom_data(k, custs[k])

		var is_decal := (mode == MODE_FLATQUAD_DECAL or mode == MODE_LINEQUAD_DECAL)
		var shader_mode := MODE_FLATQUAD if mode == MODE_FLATQUAD_DECAL else (MODE_LINEQUAD if mode == MODE_LINEQUAD_DECAL else mode)
		var want_shader := Terrain3DDecalShader if is_decal else Terrain3DShader
		var mat: ShaderMaterial = mmi.material_override as ShaderMaterial
		if mat == null or mat.shader != want_shader:
			mat = ShaderMaterial.new()
			mat.shader = want_shader
			mmi.material_override = mat
		mat.set_shader_parameter("atlas_tex", tex)
		mat.set_shader_parameter("u_mode", shader_mode)
		mat.set_shader_parameter("u_light_count", _cached_light_count)
		mat.set_shader_parameter("u_light_pos_rad", _cached_lights_pos_rad)
		mat.set_shader_parameter("u_light_col_int", _cached_lights_col_int)
		mmi.visible = true
		_active_materials.append(mat)
		_active_mat_modes.append(mode)

	for bi in range(_active_batch_count, _batch_pool.size()):
		_batch_pool[bi].visible = false


func _mesh_for_mode(mode: int) -> ArrayMesh:
	match mode:
		MODE_XQUAD:
			return _mesh_xquad
		MODE_FLATQUAD, MODE_FLATQUAD_DECAL:
			return _mesh_flatquad
		MODE_BILLBOARD, MODE_BILLBOARD_SNAP, MODE_LINEQUAD, MODE_LINEQUAD_DECAL:
			return _mesh_quad
		_:
			return _mesh_cube


# 3D-projected overlay: hover tile outline, North compass arc around player, auto-move routes, smoke/debris & SCT!
func _draw_3d_overlay() -> void:
	if not _has_scene or _camera == null:
		return
	var center: Vector2i = _scene_snap.get("center", Vector2i.ZERO)
	var player: Vector2i = _scene_snap.get("player", Vector2i.ZERO)
	var cz := int(_scene_snap.get("center_z", 0))
	var pz := int(_scene_snap.get("player_z", 0))

	# 1. Hover tile crisp 3D projected diamond/quad highlight (matches CCB mouse preselection box!)
	if _hover_valid and not _orbit_dragging and not bool(_scene_snap.get("is_looking", false)):
		var hx := float(_hover_tile.x - center.x)
		var hy := float(_hover_tile.y - center.y)
		if absf(hx) <= 45.0 and absf(hy) <= 45.0:
			var c0 := _project_ccb_to_screen(hx, hy, 0.04)
			var c1 := _project_ccb_to_screen(hx + 1.0, hy, 0.04)
			var c2 := _project_ccb_to_screen(hx + 1.0, hy + 1.0, 0.04)
			var c3 := _project_ccb_to_screen(hx, hy + 1.0, 0.04)
			if c0.x > -1000.0 and c1.x > -1000.0 and c2.x > -1000.0 and c3.x > -1000.0:
				var pts := PackedVector2Array([c0, c1, c2, c3, c0])
				_overlay_2d.draw_colored_polygon(PackedVector2Array([c0, c1, c2, c3]), Color(0.85, 0.94, 1.0, 0.14))
				_overlay_2d.draw_polyline(pts, Color(0.92, 0.97, 1.0, 0.78), 1.6, true)

	# 2. Live 60fps golden forward-movement tile bracket (exact tile the Up key steps into!)
	if pz == cz and not bool(_scene_snap.get("controlling_vehicle", false)):
		var fwd_step: Vector2i = COMPASS8[camera_forward_octant()]
		var fx := float(player.x - center.x + fwd_step.x)
		var fy := float(player.y - center.y + fwd_step.y)
		var pad := 0.14
		var p0 := _project_ccb_to_screen(fx + pad, fy + pad, 0.03)
		var p1 := _project_ccb_to_screen(fx + 1.0 - pad, fy + pad, 0.03)
		var p2 := _project_ccb_to_screen(fx + 1.0 - pad, fy + 1.0 - pad, 0.03)
		var p3 := _project_ccb_to_screen(fx + pad, fy + 1.0 - pad, 0.03)
		if p0.x > -1000.0 and p1.x > -1000.0 and p2.x > -1000.0 and p3.x > -1000.0:
			var ycol := Color(1.0, 0.88, 0.28, 0.78)
			var yfill := Color(1.0, 0.88, 0.28, 0.10)
			_overlay_2d.draw_colored_polygon(PackedVector2Array([p0, p1, p2, p3]), yfill)
			# Crisp 4 corner L-brackets (sleek, never obscures the tile or character!)
			var seg := 0.28
			_overlay_2d.draw_line(p0, p0.lerp(p1, seg), ycol, 1.8, true)
			_overlay_2d.draw_line(p0, p0.lerp(p3, seg), ycol, 1.8, true)
			_overlay_2d.draw_line(p1, p1.lerp(p0, seg), ycol, 1.8, true)
			_overlay_2d.draw_line(p1, p1.lerp(p2, seg), ycol, 1.8, true)
			_overlay_2d.draw_line(p2, p2.lerp(p1, seg), ycol, 1.8, true)
			_overlay_2d.draw_line(p2, p2.lerp(p3, seg), ycol, 1.8, true)
			_overlay_2d.draw_line(p3, p3.lerp(p2, seg), ycol, 1.8, true)
			_overlay_2d.draw_line(p3, p3.lerp(p0, seg), ycol, 1.8, true)

	# 3. World-space North compass arc + 'N' indicator around player (exact CCB compass concept)
	if pz == cz:
		var pcx := float(player.x - center.x) + 0.5
		var pcy := float(player.y - center.y) + 0.5
		var comp_r := 1.15
		var arc_pts := PackedVector2Array()
		for s in range(13):
			var ang := -PI * 0.5 + lerpf(-0.55, 0.55, float(s) / 12.0) # Centered at North (-Y in CCB)
			var pt := _project_ccb_to_screen(pcx + cos(ang) * comp_r, pcy + sin(ang) * comp_r, 0.12)
			if pt.x > -1000.0:
				arc_pts.append(pt)
		if arc_pts.size() >= 2:
			_overlay_2d.draw_polyline(arc_pts, Color(0.42, 0.86, 1.0, 0.65), 2.0, true)
		var n_pt := _project_ccb_to_screen(pcx, pcy - comp_r - 0.25, 0.25)
		if _ui_font != null and n_pt.x > -1000.0:
			_overlay_2d.draw_string(_ui_font, n_pt + Vector2(-4.0, 4.0), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.65, 0.95, 1.0, 0.92))

	# 3. Auto-move / click-to-walk route projected cleanly onto 3D ground!
	var path_pts: Array = _world_snap.get("path_points", [])
	if not path_pts.is_empty():
		var scr_pts := PackedVector2Array()
		scr_pts.append(_project_ccb_to_screen(float(player.x - center.x) + 0.5, float(player.y - center.y) + 0.5, 0.12))
		for pp_v in path_pts:
			var pp: Dictionary = pp_v
			var p2 := _project_ccb_to_screen(float(int(pp["x"]) - center.x) + 0.5, float(int(pp["y"]) - center.y) + 0.5, 0.12)
			if p2.x > -1000.0:
				scr_pts.append(p2)
		if scr_pts.size() >= 2:
			_overlay_2d.draw_polyline(scr_pts, Color(0.30, 0.88, 1.0, 0.85), 2.5, true)
			var last_p := scr_pts[scr_pts.size() - 1]
			_overlay_2d.draw_arc(last_p, 8.0, 0.0, TAU, 20, Color(0.45, 0.96, 1.0, 0.95), 2.0, true)

	# 4. Floating SCT combat numbers projected above 3D creatures!
	var sct_list: Array = _world_snap.get("sct", [])
	if _ui_font != null and not sct_list.is_empty():
		for sc_v in sct_list:
			var sc: Dictionary = sc_v
			var step := float(sc.get("step", 0))
			var mstep := maxf(1.0, float(sc.get("max_steps", 20)))
			var prog := clampf(step / mstep, 0.0, 1.0)
			var sp := _project_ccb_to_screen(float(int(sc["x"]) - center.x) + 0.5, float(int(sc["y"]) - center.y) + 0.5, 1.65 + prog * 1.1)
			if sp.x > -1000.0:
				var rgba := int(sc.get("rgba", 0xFFFFFFFF))
				var col := Color(float(rgba & 255) / 255.0, float((rgba >> 8) & 255) / 255.0, float((rgba >> 16) & 255) / 255.0, 1.0 - prog * 0.65)
				var txt := str(sc.get("text", ""))
				_overlay_2d.draw_string(_ui_font, sp + Vector2(1.0, 1.0), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(0, 0, 0, col.a * 0.8))
				_overlay_2d.draw_string(_ui_font, sp, txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, col)

	# 4b. P2.3 3D-projected footprints, settled brass casings & P3.1 drifting autumn leaves / seasonal motes!
	if _effects != null and pz == cz:
		for fp_var in _effects._footprints:
			var fp: Dictionary = fp_var
			var fpos: Vector2 = fp["pos"]
			var sp := _project_ccb_to_screen(fpos.x - float(center.x), fpos.y - float(center.y), 0.02)
			if sp.x > -1000.0:
				var fade := 1.0 - smoothstep(0.45, 1.0, clampf(float(fp["age"]) / maxf(1.0, float(fp["dur"])), 0.0, 1.0))
				var col := Color(0.44, 0.50, 0.62, 0.45 * fade) if int(fp["kind"]) == 1 else Color(0.05, 0.06, 0.08, 0.34 * fade)
				_overlay_2d.draw_circle(sp, 2.4, col)
		for cs_var in _effects._settled_casings:
			var cs: Dictionary = cs_var
			var cpos: Vector2 = cs["pos"]
			var sp := _project_ccb_to_screen(cpos.x - float(center.x), cpos.y - float(center.y), 0.02)
			if sp.x > -1000.0:
				var fade := 1.0 - smoothstep(0.70, 1.0, clampf(float(cs["age"]) / maxf(1.0, float(cs["dur"])), 0.0, 1.0))
				_overlay_2d.draw_rect(Rect2(sp - Vector2(2.0, 1.0), Vector2(4.0, 2.0)), Color(0.92, 0.76, 0.32, 0.85 * fade))
		var origin_t: Vector2i = _world_snap.get("origin", Vector2i.ZERO)
		var gsz_t: Vector2i = _world_snap.get("size", Vector2i.ZERO)
		var rmask_3d: PackedByteArray = _world_snap.get("rain_mask", PackedByteArray())
		var vrgba_3d: PackedByteArray = _world_snap.get("vis_rgba", PackedByteArray())
		var has_rm3 := (rmask_3d.size() >= gsz_t.x * gsz_t.y and gsz_t.x > 0)
		var has_v3 := (vrgba_3d.size() >= gsz_t.x * gsz_t.y * 4 and gsz_t.x > 0)
		for m_var in _effects._ambient_motes:
			var m: Dictionary = m_var
			var mk := int(m["kind"])
			if mk == 1:
				continue
			var mpos: Vector2 = m["pos"]
			if has_rm3 or has_v3:
				var mtx := int(floor(mpos.x)) - origin_t.x
				var mty := int(floor(mpos.y)) - origin_t.y
				if mtx < 0 or mty < 0 or mtx >= gsz_t.x or mty >= gsz_t.y:
					continue
				var midx := mty * gsz_t.x + mtx
				if has_rm3 and rmask_3d[midx] == 0:
					continue
				if has_v3 and vrgba_3d[midx * 4] < 130:
					continue
			var u := clampf(float(m["age"]) / maxf(0.5, float(m["dur"])), 0.0, 1.0)
			var h_z := lerpf(3.8, 0.15, u) if mk == 2 else (1.2 + sin(_weather_time * 1.4 + float(m["phase"])) * 0.55)
			var sp := _project_ccb_to_screen(mpos.x - float(center.x), mpos.y - float(center.y), h_z)
			if sp.x > -1000.0:
				var fade := smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.80, 1.0, u))
				var col: Color = m["color"]
				if mk == 2:
					_overlay_2d.draw_rect(Rect2(sp - Vector2(3.0, 1.5), Vector2(6.0, 3.0)), Color(col.r, col.g, col.b, col.a * fade))
				else:
					_overlay_2d.draw_circle(sp, 1.8, Color(col.r, col.g, col.b, col.a * fade))

	# 5. Subtle bottom-right 3D control legend
	if _ui_font != null and size.x > 360.0:
		var mode_tag := "3D 同层剖切" if same_level_only else "3D 多层全景"
		var dither_tag := "开" if cursor_dither_enabled else "关"
		var hint := "%s  |  右键拖动旋转 · 滚轮缩放 · z同层 · Z光标透视(%s) · F7切2D" % [mode_tag, dither_tag]
		var tw := _ui_font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var bx := size.x - tw - 16.0
		var by := size.y - 22.0
		_overlay_2d.draw_rect(Rect2(bx - 6.0, by - 2.0, tw + 12.0, 18.0), Color(0.03, 0.04, 0.06, 0.68))
		_overlay_2d.draw_string(_ui_font, Vector2(bx, by + 11.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.76, 0.88, 0.98, 0.92))


# Additive gunfire/explosion/beam VFX projected cleanly into 3D space!
func _draw_3d_additive_vfx() -> void:
	if not _has_scene or _effects == null:
		return
	var center: Vector2i = _scene_snap.get("center", Vector2i.ZERO)
	var vlights := _effects.get_active_vfx_lights()
	for vl in vlights:
		var pw: Vector2 = vl.get("pos", Vector2.ZERO)
		var sp := _project_ccb_to_screen(pw.x - float(center.x), pw.y - float(center.y), 1.05)
		if sp.x <= -1000.0:
			continue
		var col: Color = vl.get("color", Color(1.0, 0.72, 0.3))
		var inten := float(vl.get("intensity", 1.5))
		var rad := clampf((inten * 18.0) * (14.0 / maxf(6.0, cam_dist)), 12.0, 140.0)
		_vfx_add_2d.draw_circle(sp, rad, Color(col.r, col.g, col.b, 0.24))
		_vfx_add_2d.draw_circle(sp, rad * 0.45, Color(1.0, 0.94, 0.78, 0.58))
	# Rising 3D fire embers & summer twilight fireflies!
	for em_var in _effects._embers:
		var em: Dictionary = em_var
		var ep: Vector2 = em["pos"]
		var u := clampf(float(em["age"]) / maxf(0.05, float(em["dur"])), 0.0, 1.0)
		var sp := _project_ccb_to_screen(ep.x - float(center.x), ep.y - float(center.y), 0.4 + u * 2.2)
		if sp.x > -1000.0:
			var ec: Color = em["color"]
			_vfx_add_2d.draw_circle(sp, 2.2 * (1.0 - u * 0.5), Color(ec.r, ec.g, ec.b, (1.0 - u) * 0.85))
	for m_var in _effects._ambient_motes:
		var m: Dictionary = m_var
		if int(m["kind"]) != 1:
			continue
		var mp: Vector2 = m["pos"]
		var u := clampf(float(m["age"]) / maxf(0.5, float(m["dur"])), 0.0, 1.0)
		var sp := _project_ccb_to_screen(mp.x - float(center.x), mp.y - float(center.y), 0.9 + sin(_weather_time * 1.8 + float(m["phase"])) * 0.45)
		if sp.x > -1000.0:
			var blink := pow(0.5 + 0.5 * sin(_weather_time * 3.2 + float(m["phase"])), 2.4)
			var a := smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.80, 1.0, u)) * blink * 0.85
			if a > 0.02:
				_vfx_add_2d.draw_circle(sp, 5.0, Color(0.75, 1.0, 0.36, a * 0.35))
				_vfx_add_2d.draw_circle(sp, 2.0, Color(0.92, 1.0, 0.65, a))
