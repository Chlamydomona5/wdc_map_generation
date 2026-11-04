## 文件职责：从图纸编辑器启动独立的 WDC 主干正式入口，并让大厅开局使用已保存的生成参数档案。
## 边界约束：仅交接档案文件名与种子，不启动 authority、不跳过封面与大厅、不传递编辑器内存中的 gameplay 状态。
extends RefCounted

const TYPES = preload("../../core/generated_map_types.gd")
const FORMAL_ENTRY_SCENE: String = "res://scenes/app/main.tscn"
const SUBMODULE_DIRECTORY: String = "map_generation/addons/wdc_map_generation"
## 主干只从子模块档案目录读取生成参数档案（`scripts/shared/map/map_profile_logic.gd`），编辑器也保存在这里。
const PROFILE_SUBDIRECTORY: String = SUBMODULE_DIRECTORY + "/config/generated_map_configs"
const SUPPORTED_LAYOUT_MODES: Array[String] = [TYPES.LAYOUT_MODE_PVE_FOUR_REGION_V1, TYPES.LAYOUT_MODE_POI_ONLY_V1]


static func launch_saved_map_test(config_filename: String, seed_value: int = 0) -> Dictionary:
	var project_root: String = resolve_main_project_root()
	if project_root.is_empty():
		return {"ok": false, "pid": -1, "error": "找不到 WDC 主干。请把地图生成子模块放回 WDC 的 map_generation 目录，再从编辑器启动正式测试。"}
	var arguments: PackedStringArray = build_launch_arguments(config_filename, seed_value, project_root)
	if arguments.is_empty():
		return {"ok": false, "pid": -1, "error": "测试地图尚未保存，或档案不是主干支持的四区域 / POI Only 布局：%s" % config_filename}
	var executable: String = OS.get_environment("WDC_GODOT_BIN").strip_edges()
	if executable.is_empty():
		executable = OS.get_executable_path()
	if executable.ends_with("_console.exe"):
		var gui_executable: String = executable.replace("_console.exe", ".exe")
		if FileAccess.file_exists(gui_executable):
			executable = gui_executable
	var pid: int = OS.create_process(executable, arguments, false)
	if pid <= 0:
		return {"ok": false, "pid": pid, "error": "无法启动正式入口，请检查 Godot 可执行文件：%s" % executable}
	return {"ok": true, "pid": pid, "error": ""}


## 主干大厅读取 `--map-profile=<id>`（与 `--map-seed=<n>`），Solo / Host 选择生成地图时替换档案。
static func build_launch_arguments(config_filename: String, seed_value: int = 0, project_root: String = "") -> PackedStringArray:
	var resolved_root: String = project_root if not project_root.is_empty() else resolve_main_project_root()
	if resolved_root.is_empty() or not _is_main_project_root(resolved_root):
		return PackedStringArray()
	var basename: String = config_filename.trim_suffix(".json")
	var filename_pattern := RegEx.new()
	filename_pattern.compile("^[A-Za-z0-9_-]+$")
	if filename_pattern.search(basename) == null:
		return PackedStringArray()
	var config_path: String = resolved_root.path_join(PROFILE_SUBDIRECTORY).path_join(basename + ".json")
	if not FileAccess.file_exists(config_path):
		return PackedStringArray()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not (parsed is Dictionary) or str((parsed as Dictionary).get("id", "")) != basename:
		return PackedStringArray()
	var region_layout: Variant = (parsed as Dictionary).get("region_layout", {})
	if not (region_layout is Dictionary) or not SUPPORTED_LAYOUT_MODES.has(str((region_layout as Dictionary).get("mode", ""))):
		return PackedStringArray()
	var arguments := PackedStringArray(["--path", resolved_root, FORMAL_ENTRY_SCENE, "--", "--map-profile=" + basename])
	if seed_value > 0:
		arguments.append("--map-seed=%d" % seed_value)
	return arguments


## 方法职责：兼容从主干或嵌套 map_generation 独立工程打开编辑器的两种入口。
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
	return FileAccess.file_exists(path.path_join("project.godot")) and FileAccess.file_exists(path.path_join("scenes/app/main.tscn")) and DirAccess.dir_exists_absolute(path.path_join(SUBMODULE_DIRECTORY))
