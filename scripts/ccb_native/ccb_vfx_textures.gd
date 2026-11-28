extends RefCounted

# Procedural Photorealistic Combat VFX Texture Atlas Generator (cached once globally at startup):
# - Domain-warped multi-octave FBM turbulent fireballs (blackbody plasma -> orange flame -> crimson soot)
# - Volumetric cumulus smoke puffs with directional top-left shading (charcoal blast smoke & blue-gray gunsmoke)
# - Photographic asymmetric supersonic muzzle-flash flame plumes (Mach-diamond core + flame spears + propellant sparks)
# - Directional muzzle-brake / compensator side-vent plumes
# - Smooth inverse-square optical bloom halo, feathered pressure shockwave ring & motion-blurred spark streaks

static var _ready := false
static var fireballs: Array[ImageTexture] = []
static var smokes: Array[ImageTexture] = []
static var muzzle_plumes: Array[ImageTexture] = []
static var muzzle_baffle: ImageTexture
static var glow_halo: ImageTexture
static var shockwave_ring: ImageTexture
static var spark_streak: ImageTexture


static func ensure_ready() -> void:
	if _ready:
		return
	_ready = true
	fireballs.clear()
	smokes.clear()
	muzzle_plumes.clear()
	for i in range(4):
		fireballs.append(_build_fireball_tex(72, 101 + i * 37))
		smokes.append(_build_smoke_tex(72, 307 + i * 53))
	for i in range(3):
		muzzle_plumes.append(_build_muzzle_plume_tex(88, 56, 701 + i * 89))
	muzzle_baffle = _build_baffle_tex(64)
	glow_halo = _build_glow_tex(64)
	shockwave_ring = _build_shockwave_tex(88)
	spark_streak = _build_spark_tex(40, 10)


static func _hash2(ix: int, iy: int, seed_v: int) -> float:
	var n := (ix * 374761393 + iy * 668265263 + seed_v * 1442695041) & 0x7FFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7FFFFFFF
	return float((n ^ (n >> 16)) & 0xFFFF) / 65535.0


static func _vnoise(x: float, y: float, seed_v: int) -> float:
	var ix := int(floor(x))
	var iy := int(floor(y))
	var fx := x - float(ix)
	var fy := y - float(iy)
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	var a := _hash2(ix, iy, seed_v)
	var b := _hash2(ix + 1, iy, seed_v)
	var c := _hash2(ix, iy + 1, seed_v)
	var d := _hash2(ix + 1, iy + 1, seed_v)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uy)


static func _fbm(x: float, y: float, seed_v: int, octaves: int) -> float:
	var sum := 0.0
	var amp := 0.52
	var freq := 1.0
	var norm := 0.0
	for o in range(octaves):
		sum += amp * _vnoise(x * freq, y * freq, seed_v + o * 19)
		norm += amp
		freq *= 2.07
		amp *= 0.50
	return sum / maxf(0.001, norm)


static func _build_fireball_tex(sz: int, seed_v: int) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var inv_h := 2.0 / float(sz)
	for y in range(sz):
		var ny := (float(y) + 0.5) * inv_h - 1.0
		for x in range(sz):
			var nx := (float(x) + 0.5) * inv_h - 1.0
			var r := sqrt(nx * nx + ny * ny)
			if r >= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Domain-warped convective flame turbulence
			var wx := _fbm(nx * 2.4 + 3.1, ny * 2.4 - 1.7, seed_v, 3) - 0.5
			var wy := _fbm(nx * 2.4 - 2.3, ny * 2.4 + 4.2, seed_v + 11, 3) - 0.5
			var turb := _fbm((nx + wx * 0.72) * 3.1, (ny + wy * 0.72) * 3.1, seed_v + 29, 4)
			var billow := clampf((1.0 - r) * 1.18 + (turb - 0.44) * 0.68, 0.0, 1.0)
			if billow <= 0.02:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var edge := smoothstep(0.0, 0.30, billow) * smoothstep(1.0, 0.70, r)
			# Physical blackbody temperature gradient (white-hot -> bright amber -> deep crimson -> soot)
			var heat := clampf(billow * (0.76 + 0.48 * turb), 0.0, 1.0)
			var cr := clampf(pow(heat, 0.42) * 1.18, 0.0, 1.0)
			var cg := clampf(pow(maxf(0.0, heat - 0.16) / 0.84, 1.18) * 1.08, 0.0, 1.0)
			var cb := clampf(pow(maxf(0.0, heat - 0.54) / 0.46, 1.65) * 0.98, 0.0, 1.0)
			img.set_pixel(x, y, Color(cr, cg, cb, clampf(edge * 0.94, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func _build_smoke_tex(sz: int, seed_v: int) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var inv_h := 2.0 / float(sz)
	for y in range(sz):
		var ny := (float(y) + 0.5) * inv_h - 1.0
		for x in range(sz):
			var nx := (float(x) + 0.5) * inv_h - 1.0
			var r := sqrt(nx * nx + ny * ny)
			if r >= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var n1 := _fbm(nx * 2.5 + 1.3, ny * 2.5 - 0.9, seed_v, 4)
			var n2 := _fbm(nx * 4.2 - 2.1, ny * 4.2 + 1.7, seed_v + 41, 3)
			var density := (1.0 - r * r) * (0.58 + 0.72 * n1)
			density -= maxf(0.0, r - 0.52) * (1.25 - n2)
			var a := clampf(smoothstep(0.05, 0.52, density) * smoothstep(1.0, 0.62, r), 0.0, 1.0)
			if a <= 0.01:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Volumetric directional top-left lighting on cumulus smoke lobes
			var shade := clampf(0.56 + 0.34 * n2 - 0.18 * (nx * 0.55 + ny * 0.80), 0.25, 1.0)
			img.set_pixel(x, y, Color(shade, shade, shade, a * 0.88))
	return ImageTexture.create_from_image(img)


static func _build_muzzle_plume_tex(w: int, h: int, seed_v: int) -> ImageTexture:
	# Photographic forward-pointing supersonic muzzle flash (+X axis, origin at left x=0.14, y=0.50)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var vy := (float(y) + 0.5) / float(h) * 2.0 - 1.0 # -1..1
		for x in range(w):
			var ux := (float(x) + 0.5) / float(w) # 0..1
			var dx := ux - 0.14
			if dx < -0.14:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var ang := atan2(vy * 0.85, maxf(0.001, dx + 0.04))
			var dist := sqrt(dx * dx + vy * vy * 0.82)
			# Main forward teardrop supersonic gas cone + Mach diamond pinch
			var cone_w := (0.14 + 0.42 * pow(clampf(dx / 0.86, 0.0, 1.0), 0.55)) * (1.0 - clampf(dx / 0.90, 0.0, 1.0) * 0.78)
			var radial := absf(vy) / maxf(0.05, cone_w)
			# Turbulent irregular flame spears radiating from muzzle crown
			var ray_n := _fbm(ang * 4.8 + 2.0, dist * 5.2, seed_v, 3)
			var fine_n := _vnoise(ux * 11.0, vy * 9.0, seed_v + 17)
			var forward_mask := smoothstep(-0.10, 0.03, dx) * smoothstep(0.96, 0.18, dx + (0.45 - ray_n) * 0.24)
			var jet := clampf((1.0 - radial * (0.78 + 0.42 * (1.0 - ray_n))) * forward_mask, 0.0, 1.0)
			# Secondary Mach diamond glowing core node along barrel axis
			var mach_d := sqrt(pow((ux - 0.34) * 3.4, 2.0) + pow(vy * 5.2, 2.0))
			var mach := exp(-mach_d * mach_d * 1.45) * 0.75
			# Searing white-hot barrel crown
			var crown_d := sqrt(pow((ux - 0.16) * 5.4, 2.0) + pow(vy * 4.2, 2.0))
			var crown := exp(-crown_d * crown_d * 1.7) * 1.15
			# Outer warm gas corona
			var corona := exp(-dist * dist * 5.2) * (0.28 + 0.25 * fine_n) * smoothstep(-0.12, 0.05, dx)
			var intensity := clampf(jet * (0.72 + 0.42 * fine_n) + mach + crown + corona, 0.0, 1.35)
			if intensity <= 0.02:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var heat := clampf(intensity / 1.15, 0.0, 1.0)
			var cr := clampf(pow(heat, 0.36) * 1.15, 0.0, 1.0)
			var cg := clampf(pow(maxf(0.0, heat - 0.10) / 0.90, 0.92) * 1.05, 0.0, 1.0)
			var cb := clampf(pow(maxf(0.0, heat - 0.46) / 0.54, 1.45) * 0.98, 0.0, 1.0)
			img.set_pixel(x, y, Color(cr, cg, cb, clampf(intensity * 0.92, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func _build_baffle_tex(sz: int) -> ImageTexture:
	# Side-venting muzzle-brake / compensator flame jets (+Y and -Y, slightly swept back/forward)
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var inv_h := 2.0 / float(sz)
	for y in range(sz):
		var ny := (float(y) + 0.5) * inv_h - 1.0
		for x in range(sz):
			var nx := (float(x) + 0.5) * inv_h - 1.0
			var ay := absf(ny)
			var swept_x := nx - ay * 0.18
			var lobe := exp(-(swept_x * swept_x) * 24.0) * smoothstep(0.96, 0.14, ay) * smoothstep(0.02, 0.16, ay)
			var n := _fbm(nx * 5.0 + 1.1, ny * 4.5 - 0.8, 913, 3)
			var v := clampf(lobe * (0.65 + 0.65 * n), 0.0, 1.0)
			if v <= 0.02:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var cr := clampf(pow(v, 0.40) * 1.12, 0.0, 1.0)
			var cg := clampf(pow(maxf(0.0, v - 0.14) / 0.86, 1.1) * 0.95, 0.0, 1.0)
			var cb := clampf(pow(maxf(0.0, v - 0.52) / 0.48, 1.6) * 0.82, 0.0, 1.0)
			img.set_pixel(x, y, Color(cr, cg, cb, v * 0.88))
	return ImageTexture.create_from_image(img)


static func _build_glow_tex(sz: int) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var inv_h := 2.0 / float(sz)
	for y in range(sz):
		var ny := (float(y) + 0.5) * inv_h - 1.0
		for x in range(sz):
			var nx := (float(x) + 0.5) * inv_h - 1.0
			var r := sqrt(nx * nx + ny * ny)
			if r >= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Physically smooth inverse-square + Gaussian optical bloom (zero banding)
			var g := exp(-r * r * 4.4) * smoothstep(1.0, 0.72, r)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(g, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func _build_shockwave_tex(sz: int) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var inv_h := 2.0 / float(sz)
	for y in range(sz):
		var ny := (float(y) + 0.5) * inv_h - 1.0
		for x in range(sz):
			var nx := (float(x) + 0.5) * inv_h - 1.0
			var r := sqrt(nx * nx + ny * ny)
			if r >= 1.0 or r < 0.52:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var ang := atan2(ny, nx)
			var turb := 0.82 + 0.30 * _vnoise(cos(ang) * 3.5 + 4.0, sin(ang) * 3.5 + 4.0, 521)
			# Crisp outer leading compression wave + soft inner rarefaction tail
			var ring_d := (r - 0.87) / 0.075
			var sharp := exp(-ring_d * ring_d * 1.8)
			var tail := smoothstep(0.56, 0.86, r) * smoothstep(0.99, 0.88, r) * 0.38
			var a := clampf((sharp + tail) * turb * smoothstep(1.0, 0.93, r), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.96, 0.90, a * 0.82))
	return ImageTexture.create_from_image(img)


static func _build_spark_tex(w: int, h: int) -> ImageTexture:
	# Elongated motion-blurred incandescent ember/spark/tracer streak (+X head at right x=0.88)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var ny := (float(y) + 0.5) / float(h) * 2.0 - 1.0
		for x in range(w):
			var ux := (float(x) + 0.5) / float(w)
			var taper := smoothstep(0.0, 0.84, ux) * smoothstep(1.0, 0.86, ux)
			var core_w := 0.22 + 0.65 * pow(taper, 0.7)
			var cross := exp(-pow(ny / maxf(0.08, core_w), 2.0) * 2.8)
			var v := clampf(taper * cross, 0.0, 1.0)
			if v <= 0.01:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var cr := 1.0
			var cg := clampf(0.45 + 0.55 * ux * cross, 0.0, 1.0)
			var cb := clampf(pow(ux * cross, 2.2) * 0.95, 0.0, 1.0)
			img.set_pixel(x, y, Color(cr, cg, cb, v))
	return ImageTexture.create_from_image(img)
