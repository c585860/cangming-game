extends SceneTree

# Zero-Source Minimal PCK Packager for Cataclysm:EmperorCOOP 2.0 Release Distribution.
# Packs ONLY runtime game assets (project.godot, scenes, scripts, shaders, art, fonts, packs, gdextension)
# into release/Cataclysm-EmperorCOOP2.0.pck — strictly ZERO C++ source, build artifacts, dev tools, or .git data!

const ALLOWED_ROOT_FILES := [
	"project.godot",
	"cangling.gdextension",
	"main.tscn",
]

const ALLOWED_DIRS := [
	"scripts",
	"shaders",
	"art",
	"fonts",
	"packs",
]

const ALLOWED_EXTS := [
	"gd", "gdshader", "gdshaderinc", "tscn", "tres", "uid", "png", "jpg", "jpeg", "webp", "svg",
	"ttf", "otf", "woff2", "json", "motd", "title", "tsv", "cfg", "import", "ctex", "gdextension",
]

const BLOCKED_EXTS := [
	"cpp", "hpp", "h", "c", "cc", "cxx", "py", "ps1", "sh", "bat", "cmd",
	"md", "obj", "o", "a", "lib", "dll", "exe", "pdb", "log", "tmp",
]


func _init() -> void:
	var out_pck := ProjectSettings.globalize_path("res://release/Cataclysm-EmperorCOOP2.0.pck").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_pck.get_base_dir())

	var packer := PCKPacker.new()
	var err := packer.pck_start(out_pck)
	if err != OK:
		printerr("[pack_release] pck_start failed: %d (%s)" % [err, out_pck])
		quit(1)
		return

	var count := 0
	for rf_v in ALLOWED_ROOT_FILES:
		var rp: String = "res://" + str(rf_v)
		if FileAccess.file_exists(rp):
			var ae := packer.add_file(rp, rp)
			if ae != OK:
				printerr("[pack_release] add_file failed for %s: %d" % [rp, ae])
				quit(1)
				return
			count += 1

	for d_v in ALLOWED_DIRS:
		count += _add_dir_recursive(packer, "res://" + str(d_v))

	# Include Godot's pre-imported .godot/imported textures & global script class cache if present
	if FileAccess.file_exists("res://.godot/global_script_class_cache.cfg"):
		packer.add_file("res://.godot/global_script_class_cache.cfg", "res://.godot/global_script_class_cache.cfg")
		count += 1
	if FileAccess.file_exists("res://.godot/extension_list.cfg"):
		packer.add_file("res://.godot/extension_list.cfg", "res://.godot/extension_list.cfg")
		count += 1
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.godot/imported")):
		count += _add_dir_recursive(packer, "res://.godot/imported", true)

	err = packer.flush(true)
	if err != OK:
		printerr("[pack_release] flush failed: %d" % err)
		quit(1)
		return

	print("[pack_release] OK -> %s (%d files packed, ZERO source files)" % [out_pck, count])
	quit(0)


func _add_dir_recursive(packer: PCKPacker, res_dir: String, allow_all_imported := false) -> int:
	var added := 0
	var da := DirAccess.open(res_dir)
	if da == null:
		return 0
	da.list_dir_begin()
	var name := da.get_next()
	while not name.is_empty():
		if name.begins_with("."):
			name = da.get_next()
			continue
		var full := res_dir.path_join(name)
		if da.current_is_dir():
			added += _add_dir_recursive(packer, full, allow_all_imported)
		else:
			var ext := name.get_extension().to_lower()
			if allow_all_imported:
				if name.contains(".obj-") or ext == "md5":
					name = da.get_next()
					continue
			else:
				if BLOCKED_EXTS.has(ext) or not ALLOWED_EXTS.has(ext):
					name = da.get_next()
					continue
			var ae := packer.add_file(full, full)
			if ae == OK:
				added += 1
		name = da.get_next()
	da.list_dir_end()
	return added
