## 文件职责：从图纸编辑器启动独立的 WDC 正式主菜单，并预选已保存的地图配置。
## 边界约束：仅交接文件名，不启动 authority、不跳过菜单、不传递编辑器内存中的 gameplay 状态。
extends RefCounted

const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const CONFIG_SUBDIRECTORY: String = "map_generation/addons/wdc_map_generation/config/generated_map_configs"


static func launch_saved_map_test(config_filename: String) -> Dictionary:
	var project_root: String = resolve_main_project_root()
	if project_root.is_empty():
		return {"ok": false, "pid": -1, "error": "找不到 WDC 主仓。请把地图生成子模块放回 WDC 的 map_generation 目录，再从编辑器启动正式测试。"}
	var arguments: PackedStringArray = build_main_menu_arguments(config_filename, project_root)
	if arguments.is_empty():
		return {"ok": false, "pid": -1, "error": "测试地图尚未保存，或配置文件名无效：%s" % config_filename}
	var executable: String = OS.get_environment("WDC_GODOT_BIN").strip_edges()
	if executable.is_empty():
		executable = OS.get_executable_path()
	if executable.ends_with("_console.exe"):
		var gui_executable: String = executable.replace("_console.exe", ".exe")
		if FileAccess.file_exists(gui_executable):
			executable = gui_executable
	var pid: int = OS.create_process(executable, arguments, false)
	if pid <= 0:
		return {"ok": false, "pid": pid, "error": "无法启动正式主菜单，请检查 Godot 可执行文件：%s" % executable}
	return {"ok": true, "pid": pid, "error": ""}


static func build_main_menu_arguments(config_filename: String, project_root: String = "") -> PackedStringArray:
	var resolved_root: String = project_root if not project_root.is_empty() else resolve_main_project_root()
	if resolved_root.is_empty() or not _is_main_project_root(resolved_root):
		return PackedStringArray()
	var basename: String = config_filename.trim_suffix(".json")
	var filename_pattern := RegEx.new()
	filename_pattern.compile("^[A-Za-z0-9_-]+$")
	if filename_pattern.search(basename) == null:
		return PackedStringArray()
	var main_config: String = resolved_root.path_join("assets/generated_map_configs").path_join(basename + ".json")
	var canonical_config: String = resolved_root.path_join(CONFIG_SUBDIRECTORY).path_join(basename + ".json")
	var config_path: String = main_config if FileAccess.file_exists(main_config) else canonical_config
	if not FileAccess.file_exists(config_path):
		return PackedStringArray()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not (parsed is Dictionary) or (parsed as Dictionary).is_empty():
		return PackedStringArray()
	return PackedStringArray(["--path", resolved_root, MAIN_MENU_SCENE, "--", "--generated-map-config=" + basename])


## 方法职责：兼容从主仓或嵌套 map_generation 独立工程打开编辑器的两种入口。
static func resolve_main_project_root(project_path: String = "") -> String:
	var candidate: String = project_path if not project_path.is_empty() else ProjectSettings.globalize_path("res://")
	candidate = candidate.replace("\\", "/").trim_suffix("/")
	for _level: int in range(8):
		if _is_main_project_root(candidate):
			return candidate
		var parent: String = candidate.get_base_dir()
		if parent.is_empty() or parent == candidate:
			break
		candidate = parent
	return ""


static func _is_main_project_root(path: String) -> bool:
	return FileAccess.file_exists(path.path_join("project.godot")) and FileAccess.file_exists(path.path_join("scenes/ui/main_menu.tscn")) and DirAccess.dir_exists_absolute(path.path_join("map_generation/addons/wdc_map_generation"))
