class_name WdcMapGenerationConfigCatalog
extends RefCounted

const CONFIG_DIRECTORY_PATH: String = "res://addons/wdc_map_generation/config/generated_map_configs"
const PARENT_PROJECT_CONFIG_DIRECTORY_PATH: String = (
	"res://map_generation/addons/wdc_map_generation/config/generated_map_configs"
)
const CONFIG_EXTENSION: String = ".json"
const DEFAULT_CONFIG_BASENAME: String = "ancient_old_mine"

const GENERATED_MAP_TYPES_SCRIPT = preload("../core/generated_map_types.gd")
const WdcMapGenerationTypes = GENERATED_MAP_TYPES_SCRIPT
const POI_RESOURCE_CATALOG = preload("poi_resource_catalog.gd")
const POI_POPULATION_CONTRACT = preload("../core/poi_population_contract.gd")
const POI_COMPOSITION_GENERATOR = preload("../core/poi_composition_generator.gd")
const REGION_CONTENT_GROUP_SPECS: Dictionary = {
	"minerals": {
		"count_unit": "site",
		"entry_key": "cluster_type_id",
		"reference_kind": "mineral",
		"uses_value_cost": true,
	},
	"pois": {"count_unit": "instance", "entry_key": "template_id", "reference_kind": "poi"},
	"room_contents": {
		"count_unit": "placement_site",
		"entry_key": "content_kind",
		"reference_kind": "room_content",
		"uses_value_cost": true,
	},
	"traps": {"count_unit": "instance", "entry_key": "trap_kind", "reference_kind": "trap"},
	"furnishings": {"count_unit": "instance", "entry_key": "content_id", "reference_kind": "prop", "uses_value_cost": true},
	"torches": {"count_unit": "instance", "entry_key": "content_id", "reference_kind": "torch", "uses_value_cost": true},
	"monster_sites": {"count_unit": "spawn_site", "entry_key": "spawn_template_id", "reference_kind": "spawn"},
	"nests": {"count_unit": "instance", "entry_key": "nest_template_id", "reference_kind": "nest"},
	"camps": {
		"count_unit": "encounter",
		"entry_key": "camp_id",
		"reference_kind": "camp",
		"uses_value_cost": true,
	},
}
const REGION_ROOM_CONTENT_KINDS: Array[String] = ["monster_pack", "nest", "camp"]


static func get_config_directory_path() -> String:
	return _resolve_config_directory_path()


static func get_config_extension() -> String:
	return CONFIG_EXTENSION


static func get_default_config_filename() -> String:
	var available_configs: Array[Dictionary] = list_available_configs()
	for config_entry: Dictionary in available_configs:
		if str(config_entry.get("filename", "")) == DEFAULT_CONFIG_BASENAME:
			return DEFAULT_CONFIG_BASENAME
	if not available_configs.is_empty():
		return str(available_configs[0].get("filename", DEFAULT_CONFIG_BASENAME))
	return DEFAULT_CONFIG_BASENAME


static func normalize_config_filename_input(filename_value: Variant) -> String:
	var normalized: String = str(filename_value).strip_edges()
	if normalized.is_empty():
		return ""
	normalized = normalized.replace("\\", "/").get_file().get_basename()
	var rebuilt: String = ""
	for char_idx: int in range(normalized.length()):
		var char_value: String = normalized.substr(char_idx, 1)
		var code: int = char_value.unicode_at(0)
		var is_ascii_letter_or_digit: bool = (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
		)
		if is_ascii_letter_or_digit or char_value == "_" or char_value == "-":
			rebuilt += char_value
	return rebuilt


static func build_config_resource_path(filename_value: Variant) -> String:
	var normalized_filename: String = normalize_config_filename_input(filename_value)
	if normalized_filename.is_empty():
		normalized_filename = DEFAULT_CONFIG_BASENAME
	return "%s/%s%s" % [_resolve_config_directory_path(), normalized_filename, CONFIG_EXTENSION]


static func list_available_configs() -> Array[Dictionary]:
	var listed: Array[Dictionary] = []
	var directory: DirAccess = DirAccess.open(_resolve_config_directory_path())
	if directory == null:
		return listed
	directory.list_dir_begin()
	while true:
		var entry_name: String = directory.get_next()
		if entry_name.is_empty():
			break
		if directory.current_is_dir() or not entry_name.ends_with(CONFIG_EXTENSION):
			continue
		var filename: String = entry_name.get_basename()
		var config_dict: Dictionary = load_config_dict_by_filename(filename)
		listed.append({
			"filename": filename,
			"display_name": _resolve_display_name(filename, config_dict),
			"description": str(config_dict.get("description", "")),
		})
	directory.list_dir_end()
	listed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("display_name", "")).nocasecmp_to(
			str(b.get("display_name", ""))
		) < 0
	)
	return listed


static func _resolve_config_directory_path() -> String:
	if DirAccess.dir_exists_absolute(CONFIG_DIRECTORY_PATH):
		return CONFIG_DIRECTORY_PATH
	if DirAccess.dir_exists_absolute(PARENT_PROJECT_CONFIG_DIRECTORY_PATH):
		return PARENT_PROJECT_CONFIG_DIRECTORY_PATH
	return CONFIG_DIRECTORY_PATH


static func load_config_dict_by_filename(filename_value: Variant) -> Dictionary:
	var path: String = build_config_resource_path(filename_value)
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var raw_text: String = file.get_as_text()
	if raw_text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


static func parse_and_normalize_config(
	raw_config_value: Variant,
	resource_overrides: Dictionary = {}
) -> WdcMapGenerationTypes.GeneratedMapConfigParseResult:
	return _parse_and_normalize_config_into(
		raw_config_value,
		WdcMapGenerationTypes.MapConfig.new(),
		resource_overrides
	)


static func serialize_normalized_config(config_or_result: Variant) -> Dictionary:
	if config_or_result is WdcMapGenerationTypes.GeneratedMapConfigParseResult:
		var parse_result: WdcMapGenerationTypes.GeneratedMapConfigParseResult = config_or_result
		if not parse_result.is_success():
			return {}
		return parse_result.get_normalized_document()
	# MapConfig 不保存完整源文档，不能无损恢复 POI 引用等字段；序列化只接受
	# canonical parse result，避免未知 mode 被误写成 legacy 或四区域引用丢失。
	return {}


static func _parse_and_normalize_config_into(
	raw_config_value: Variant,
	target_config: WdcMapGenerationTypes.MapConfig,
	resource_overrides: Dictionary = {}
) -> WdcMapGenerationTypes.GeneratedMapConfigParseResult:
	var result: WdcMapGenerationTypes.GeneratedMapConfigParseResult = (
		WdcMapGenerationTypes.GeneratedMapConfigParseResult.new()
	)
	if target_config == null:
		target_config = WdcMapGenerationTypes.MapConfig.new()
	var issues: Array[Dictionary] = []
	if not (raw_config_value is Dictionary):
		issues.append(_config_issue(
			"invalid_region_layout_declaration",
			"",
			"",
			"generated-map 配置必须是 JSON 对象"
		))
		target_config.set_validation_issues(issues)
		result.issues = issues.duplicate(true)
		return result
	var raw_config: Dictionary = (raw_config_value as Dictionary).duplicate(true)
	var layout_mode: String = WdcMapGenerationTypes.LAYOUT_MODE_LEGACY_RADIAL
	var normalized_region_layout: Dictionary = {}
	var normalized_region_generation: Dictionary = {}
	# 必须先在原始 JSON 上判定字段是否出现；任何默认值注入都发生在这之后。
	if raw_config.has("region_layout"):
		var region_layout_value: Variant = raw_config.get("region_layout")
		if not (region_layout_value is Dictionary):
			issues.append(_config_issue(
				"invalid_region_layout_declaration",
				"region_layout",
				"",
				"region_layout 必须是对象，且不能为 null"
			))
		else:
			var raw_region_layout: Dictionary = region_layout_value as Dictionary
			if not raw_region_layout.has("mode"):
				issues.append(_config_issue(
					"invalid_region_layout_declaration",
					"region_layout.mode",
					"",
					"region_layout.mode 不能为空"
				))
			elif typeof(raw_region_layout.get("mode")) != TYPE_STRING:
				issues.append(_config_issue(
					"invalid_region_layout_declaration",
					"region_layout.mode",
					"",
					"region_layout.mode 必须是字符串"
				))
			else:
				layout_mode = str(raw_region_layout.get("mode", "")).strip_edges()
				if layout_mode == WdcMapGenerationTypes.LAYOUT_MODE_POI_ONLY_V1:
					normalized_region_layout = {"mode": layout_mode}
					normalized_region_generation = _normalize_poi_only_config(raw_config, issues)
				elif layout_mode != WdcMapGenerationTypes.LAYOUT_MODE_PVE_FOUR_REGION_V1:
					issues.append(_config_issue(
						"unsupported_region_layout_mode",
						"region_layout.mode",
						"",
						"不支持的区域布局模式：%s" % layout_mode
					))
				else:
					_validate_region_schema_version(raw_config, issues)
					_validate_raw_legacy_conflicts(raw_config, issues)
					normalized_region_layout = _normalize_four_region_layout(
						raw_config,
						raw_region_layout,
						issues
					)
					normalized_region_generation = _normalize_region_generation(
						raw_config,
						normalized_region_layout,
						issues
					)
					_validate_and_normalize_core_poi_metadata(
						raw_config,
						normalized_region_layout,
						issues
					)
	var authored_bundle: Dictionary = _resolve_authored_pois(raw_config, resource_overrides, issues) if issues.is_empty() else {}
	if layout_mode == WdcMapGenerationTypes.LAYOUT_MODE_POI_ONLY_V1 and not authored_bundle.is_empty():
		var test: Dictionary = raw_config.get("poi_only", {})
		var composition: Dictionary = authored_bundle.get("compositions", {}).get(str(test.get("composition_id", "")), {})
		var has_recipe: bool = not str(composition.get("reward_recipe_id", "")).is_empty()
		var has_encounter: bool = not str(test.get("encounter_profile_id", "")).is_empty()
		if has_recipe != has_encounter:
			issues.append(_config_issue("invalid_poi_only_config", "poi_only.encounter_profile_id", "", "BOSS 图纸必须配置遭遇 profile，普通图纸不得携带 BOSS 遭遇"))
	if not issues.is_empty():
		target_config.layout_mode = layout_mode
		target_config.region_layout = {}
		target_config.region_generation = {}
		target_config.set_validation_issues(issues)
		result.issues = issues.duplicate(true)
		return result
	target_config.layout_mode = layout_mode
	target_config.region_layout = normalized_region_layout.duplicate(true)
	target_config.region_generation = normalized_region_generation.duplicate(true)
	target_config.set_validation_issues([])
	if layout_mode != WdcMapGenerationTypes.LAYOUT_MODE_LEGACY_RADIAL:
		target_config.map_layers.clear()
		target_config.player_spawn_layer_id = ""
		target_config.extraction_site_layer_distribution.clear()
	_apply_config_dict_to_map_config_unchecked(target_config, raw_config)
	if layout_mode == WdcMapGenerationTypes.LAYOUT_MODE_POI_ONLY_V1:
		target_config.set_meta("poi_only", raw_config.poi_only.duplicate(true))
	if not authored_bundle.is_empty():
		target_config.set_meta("poi_resource_bundle", authored_bundle.duplicate(true))
		target_config.set_meta("poi_population_limits", POI_POPULATION_CONTRACT.resolve_limits(
			raw_config.get("monster_generation", {}).get("population_budgets", {}),
			authored_bundle.get("capabilities", {}).get("population_limits", {})))
	result.config = target_config
	result.normalized_document = _build_normalized_document(target_config, raw_config)
	return result


## 从源地图条目提取真实内容规则；只改变几何模式和测试组合，不增加预算。
static func build_poi_only_config(source_document: Dictionary, composition_id: String, seed_value: int,
	resource_overrides: Dictionary = {}, content_profile_id: String = "", source_template_id: String = "") -> Dictionary:
	var source: Dictionary = source_document.duplicate(true)
	var templates: Array = source.get("poi_generation", {}).get("poi_types", [])
	var selected: Dictionary = {}
	for candidate: Dictionary in templates:
		if (not source_template_id.is_empty() and str(candidate.get("id", "")) == source_template_id) or (source_template_id.is_empty() and str(candidate.get("composition_id", "")) == composition_id):
			selected = candidate
			break
	var source_layout: Dictionary = source.get("region_layout", {})
	if selected.is_empty() and source_template_id.is_empty():
		var fallback_id: String = str(source_layout.get(WdcMapGenerationTypes.REGION_ROLE_HIGH_1, {}).get("core_poi", {}).get("template_id", ""))
		for candidate: Dictionary in templates:
			if str(candidate.get("id", "")) == fallback_id:
				selected = candidate
				break
	if selected.is_empty():
		return _poi_only_build_failure("poi_only.source_template_id", "源地图没有可用于测试的 POI 条目")
	var role: String = ""
	var profile_id: String = content_profile_id
	for candidate_role: String in WdcMapGenerationTypes.REGION_ROLE_ORDER:
		var slot: Dictionary = source_layout.get(candidate_role, {})
		var matches: bool = str(slot.get("core_poi", {}).get("template_id", "")) == str(selected.id)
		if not matches:
			for profile: Dictionary in source.get("region_generation", {}).get("content_profiles", []):
				if str(profile.get("id", "")) == str(slot.get("content_profile_id", "")):
					for entry: Dictionary in profile.get("pois", {}).get("entries", []):
						matches = matches or str(entry.get("template_id", "")) == str(selected.id)
		if (not content_profile_id.is_empty() and str(slot.get("content_profile_id", "")) == content_profile_id) or (content_profile_id.is_empty() and matches):
			role = candidate_role
			profile_id = str(slot.get("content_profile_id", ""))
			break
	# 已保存的 POI-only 文档仍能重新导出，不需要还原四区域布局。
	if role.is_empty() and source_layout.get("mode", "") == WdcMapGenerationTypes.LAYOUT_MODE_POI_ONLY_V1:
		role = str(source.get("poi_only", {}).get("region_role", ""))
		if profile_id.is_empty():
			profile_id = str(source.get("poi_only", {}).get("content_profile_id", ""))
	var chosen_profile: Dictionary = {}
	for profile: Dictionary in source.get("region_generation", {}).get("content_profiles", []):
		if str(profile.get("id", "")) == profile_id:
			chosen_profile = profile.duplicate(true)
	if role.is_empty() or chosen_profile.is_empty():
		return _poi_only_build_failure("poi_only.content_profile_id", "所选条目没有唯一的源地图内容 profile")
	selected["layout_kind"] = "authored_rooms"
	selected["composition_id"] = composition_id
	selected["enabled"] = true
	for key: String in ["main_room", "sub_rooms", "connectivity", "core_metadata"]:
		selected.erase(key)
	var encounter_profile_id: String = str(source_layout.get(WdcMapGenerationTypes.REGION_ROLE_BOSS, {}).get("encounter_profile_id", source.get("poi_only", {}).get("encounter_profile_id", "")))
	var selected_bundle: Dictionary = POI_RESOURCE_CATALOG.load_bundle(resource_overrides, [composition_id])
	if not bool(selected_bundle.get("valid", false)):
		return {"valid": false, "config": {}, "issues": selected_bundle.get("issues", [])}
	if str(selected_bundle.get("compositions", {}).get(composition_id, {}).get("reward_recipe_id", "")).is_empty():
		encounter_profile_id = ""
	source["schema_version"] = 3
	source["region_layout"] = {"mode": WdcMapGenerationTypes.LAYOUT_MODE_POI_ONLY_V1}
	source["region_generation"] = {"content_profiles": [chosen_profile]}
	source["poi_only"] = {"composition_id": composition_id, "source_template_id": str(selected.id),
		"region_role": role, "content_profile_id": profile_id, "encounter_profile_id": encounter_profile_id,
		"padding_cells": 8}
	source.erase("map_layers")
	source.erase("boss_generation")
	var map: Dictionary = source.get("map", {}).duplicate(true)
	map["seed"] = {"mode": "fixed", "fixed_value": maxi(seed_value, 1)}
	map["player_spawn"] = {"count": 1}
	map["extraction_sites"] = {"count": 1}
	source["map"] = map
	var parsed: WdcMapGenerationTypes.GeneratedMapConfigParseResult = parse_and_normalize_config(source, resource_overrides)
	if not parsed.is_success():
		return {"valid": false, "config": {}, "issues": parsed.get_issues()}
	var layout: Dictionary = POI_COMPOSITION_GENERATOR.generate(composition_id,
		parsed.config.get_meta("poi_resource_bundle", {}), maxi(seed_value, 1))
	if not bool(layout.get("valid", false)):
		return {"valid": false, "config": {}, "issues": layout.get("issues", [])}
	var bounds: Dictionary = layout.plan.bounds
	var document: Dictionary = parsed.get_normalized_document()
	document.map["width_cells"] = maxi(int(bounds.width) + 16, 32)
	document.map["height_cells"] = maxi(int(bounds.height) + 16, 32)
	return {"valid": true, "config": document, "issues": []}


static func _poi_only_build_failure(path: String, message: String) -> Dictionary:
	return {"valid": false, "config": {}, "issues": [_config_issue("invalid_poi_only_config", path, "", message)]}


static func _normalize_poi_only_config(raw: Dictionary, issues: Array[Dictionary]) -> Dictionary:
	if typeof(raw.get("schema_version")) not in [TYPE_INT, TYPE_FLOAT] or float(raw.get("schema_version", 0)) != 3.0:
		issues.append(_config_issue("invalid_poi_only_config", "schema_version", "", "POI-only 要求 schema_version=3"))
	if not raw.get("region_generation") is Dictionary or not raw.get("poi_generation") is Dictionary:
		issues.append(_config_issue("invalid_poi_only_config", "region_generation", "", "测试地图必须携带内容 profile 与源条目定义对象"))
		return {}
	_append_unknown_region_profile_fields(raw.region_generation, ["content_profiles"], "region_generation", issues)
	if not raw.get("poi_only") is Dictionary:
		issues.append(_config_issue("invalid_poi_only_config", "poi_only", "", "POI-only 必须声明测试条目"))
		return {}
	var config: Dictionary = raw.poi_only
	_append_unknown_region_profile_fields(config, ["composition_id", "source_template_id", "region_role", "content_profile_id", "encounter_profile_id", "padding_cells"], "poi_only", issues)
	for key: String in ["composition_id", "source_template_id", "region_role", "content_profile_id"]:
		if not config.get(key) is String or str(config.get(key, "")).strip_edges().is_empty():
			issues.append(_config_issue("invalid_poi_only_config", "poi_only." + key, "", "测试字段必须是非空字符串"))
	if config.get("region_role", "") not in WdcMapGenerationTypes.REGION_ROLE_ORDER:
		issues.append(_config_issue("invalid_poi_only_config", "poi_only.region_role", "", "测试条目必须保留源内容区域角色"))
	var padding: Variant = config.get("padding_cells", 8)
	if typeof(padding) not in [TYPE_INT, TYPE_FLOAT] or float(padding) != floor(float(padding)) or float(padding) < 6 or float(padding) > 32:
		issues.append(_config_issue("invalid_poi_only_config", "poi_only.padding_cells", "", "测试外围净空必须是 6–32 格整数"))
	else:
		config["padding_cells"] = int(padding)
	if not config.get("encounter_profile_id", "") is String:
		issues.append(_config_issue("invalid_poi_only_config", "poi_only.encounter_profile_id", "", "遭遇 profile 必须是字符串"))
	if raw.has("map_layers") or raw.has("boss_generation") or (raw.get("region_layout", {}) as Dictionary).size() != 1:
		issues.append(_config_issue("invalid_poi_only_config", "region_layout", "", "POI-only 不得混入四区域或旧布局声明"))
	var selected_count: int = 0
	for template: Dictionary in raw.get("poi_generation", {}).get("poi_types", []):
		if str(template.get("id", "")) == str(config.get("source_template_id", "")):
			selected_count += 1
			if template.get("layout_kind", "") != "authored_rooms" or template.get("composition_id", "") != config.get("composition_id", ""):
				issues.append(_config_issue("invalid_poi_only_config", "poi_only.composition_id", "", "测试组合与源条目不一致"))
	if selected_count != 1:
		issues.append(_config_issue("invalid_poi_only_config", "poi_only.source_template_id", "", "测试条目必须唯一存在"))
	var profiles: Array[Dictionary] = _normalize_region_content_profiles(raw.get("region_generation", {}).get("content_profiles"), _build_region_content_reference_counts(raw), issues)
	if profiles.size() != 1 or str(profiles[0].get("id", "")) != str(config.get("content_profile_id", "")):
		issues.append(_config_issue("invalid_poi_only_config", "poi_only.content_profile_id", "", "POI-only 必须恰好保留所选内容 profile"))
	return {"content_profiles": profiles}


static func extract_map_dimensions(config_dict: Dictionary) -> Vector2i:
	var map_dict: Dictionary = config_dict.get("map", {}) as Dictionary
	return Vector2i(
		maxi(int(map_dict.get("width_cells", 64)), 8),
		maxi(int(map_dict.get("height_cells", 64)), 8)
	)


static func extract_seed_mode(config_dict: Dictionary) -> String:
	var map_dict: Dictionary = config_dict.get("map", {}) as Dictionary
	var seed_dict: Dictionary = map_dict.get("seed", {}) as Dictionary
	return "fixed" if str(seed_dict.get("mode", "random")) == "fixed" else "random"


static func extract_fixed_seed(config_dict: Dictionary) -> int:
	var map_dict: Dictionary = config_dict.get("map", {}) as Dictionary
	var seed_dict: Dictionary = map_dict.get("seed", {}) as Dictionary
	return maxi(int(seed_dict.get("fixed_value", 0)), 0)


static func extract_cell_size_m(config_dict: Dictionary) -> float:
	var map_dict: Dictionary = config_dict.get("map", {}) as Dictionary
	return maxf(float(map_dict.get("cell_size_m", 1.0)), 0.1)


static func apply_config_dict_to_legacy_map_config(
	config: WdcMapGenerationTypes.MapConfig,
	config_dict: Dictionary
) -> WdcMapGenerationTypes.GeneratedMapConfigParseResult:
	return _parse_and_normalize_config_into(config_dict, config)


static func _apply_config_dict_to_map_config_unchecked(
	config: WdcMapGenerationTypes.MapConfig,
	config_dict: Dictionary
) -> void:
	if config == null:
		return
	var map_dict: Dictionary = config_dict.get("map", {}) as Dictionary
	var terrain_dict: Dictionary = config_dict.get("terrain", {}) as Dictionary
	var global_corridors: Dictionary = terrain_dict.get("global_corridors", {}) as Dictionary
	var minerals_dict: Dictionary = config_dict.get("minerals", {}) as Dictionary
	var global_distribution: Dictionary = (
		minerals_dict.get("global_distribution", {}) as Dictionary
	)
	config.width = maxi(int(map_dict.get("width_cells", config.width)), 8)
	config.height = maxi(int(map_dict.get("height_cells", config.height)), 8)
	config.seed = (
		extract_fixed_seed(config_dict)
		if extract_seed_mode(config_dict) == "fixed"
		else 0
	)
	config.fill_percent = float(
		terrain_dict.get("noise_fill_percent", config.fill_percent)
	)
	config.smooth_iterations = int(
		terrain_dict.get("smooth_iterations", config.smooth_iterations)
	)
	config.corridor_count = (
		int(global_corridors.get("count", config.corridor_count))
		if bool(global_corridors.get("enabled", true))
		else 0
	)
	config.corridor_width = int(
		global_corridors.get("width_cells", config.corridor_width)
	)
	config.corridor_length = float(
		global_corridors.get("length_factor", config.corridor_length)
	)
	config.corridor_wobble = float(
		global_corridors.get("wobble_chance", config.corridor_wobble)
	)
	config.mineral_base_chance = float(
		global_distribution.get("base_candidate_chance", config.mineral_base_chance)
	)
	config.mineral_exposed_chance = float(
		global_distribution.get(
			"exposed_wall_candidate_chance",
			config.mineral_exposed_chance
		)
	)
	config.mineral_min_distance_between_cluster_seeds_cells = maxi(
		int(
			global_distribution.get(
				"min_distance_between_cluster_seeds_cells",
				config.mineral_min_distance_between_cluster_seeds_cells
			)
		),
		0
	)
	config.mineral_allow_clusters_inside_poi_rooms = bool(
		global_distribution.get(
			"allow_clusters_inside_poi_rooms",
			config.mineral_allow_clusters_inside_poi_rooms
		)
	)
	config.mineral_allow_clusters_under_poi_corridors = bool(
		global_distribution.get(
			"allow_clusters_under_poi_corridors",
			config.mineral_allow_clusters_under_poi_corridors
		)
	)
	config.mineral_cluster_types = _normalize_cluster_types(
		minerals_dict.get("cluster_types", [])
	)
	config.mineral_cluster_overrides = _normalize_cluster_overrides(
		minerals_dict.get("cluster_overrides", []),
		config.mineral_cluster_types
	)
	if config.layout_mode == WdcMapGenerationTypes.LAYOUT_MODE_LEGACY_RADIAL:
		config.map_layers = _normalize_map_layers(config_dict.get("map_layers", []))
	else:
		config.map_layers.clear()
	_apply_player_spawn_config(config, map_dict.get("player_spawn", {}))
	_apply_extraction_site_config(
		config,
		map_dict.get("extraction_sites", {}),
		config.layout_mode == WdcMapGenerationTypes.LAYOUT_MODE_LEGACY_RADIAL
	)
	config.poi_templates = _normalize_poi_templates(
		(config_dict.get("poi_generation", {}) as Dictionary).get("poi_types", [])
	)
	config.set_meta("isolated_spawn_templates", _normalize_spawn_templates(
		(config_dict.get("monster_generation", {}) as Dictionary).get("isolated_spawn_templates", []),
		"monster_id"
	))
	config.set_meta("nest_templates", _normalize_spawn_templates(
		(config_dict.get("monster_generation", {}) as Dictionary).get("nest_templates", []),
		"nest_unit_id"
	))
	var traps_dict: Dictionary = config_dict.get("traps", {}) as Dictionary
	config.traps_high_density = bool(traps_dict.get("high_density_mode", false))
	config.traps_spike_max_count = int(traps_dict.get("spike_max_count", -1))
	config.traps_spike_min_spacing = int(traps_dict.get("spike_min_spacing", -1))
	config.traps_explosive_chain_count = int(traps_dict.get("explosive_chain_count", -1))
	config.traps_explosive_chain_spacing = int(traps_dict.get("explosive_chain_spacing", -1))
	config.traps_arrow_slit_max_count = int(traps_dict.get("arrow_slit_max_count", -1))
	config.traps_arrow_slit_min_spacing = int(traps_dict.get("arrow_slit_min_spacing", -1))
	config.traps_mimic_ore_max_count = int(traps_dict.get("mimic_ore_max_count", -1))
	config.traps_mimic_ore_min_spacing = int(traps_dict.get("mimic_ore_min_spacing", -1))
	config.traps_pressure_plate_max_count = int(traps_dict.get("pressure_plate_max_count", -1))
	config.traps_pressure_plate_min_spacing = int(traps_dict.get("pressure_plate_min_spacing", -1))
	_apply_poi_template_overrides(config, config_dict)
	config.normalize()


static func apply_config_dict_to_builder(
	builder: Node,
	config_dict: Dictionary,
	resolved_seed: int
) -> void:
	if builder == null:
		return
	var map_dict: Dictionary = config_dict.get("map", {}) as Dictionary
	var terrain_dict: Dictionary = config_dict.get("terrain", {}) as Dictionary
	var global_corridors: Dictionary = terrain_dict.get("global_corridors", {}) as Dictionary
	var minerals_dict: Dictionary = config_dict.get("minerals", {}) as Dictionary
	var global_distribution: Dictionary = (
		minerals_dict.get("global_distribution", {}) as Dictionary
	)
	var map_size: Vector2i = extract_map_dimensions(config_dict)
	builder.set("generated_map_width", map_size.x)
	builder.set("generated_map_height", map_size.y)
	builder.set("generated_map_seed", resolved_seed)
	builder.set("generated_map_cell_size_m", extract_cell_size_m(config_dict))
	builder.set(
		"generated_map_fill_percent",
		float(terrain_dict.get("noise_fill_percent", builder.get("generated_map_fill_percent")))
	)
	builder.set(
		"generated_map_smooth_iterations",
		int(terrain_dict.get("smooth_iterations", builder.get("generated_map_smooth_iterations")))
	)
	builder.set(
		"generated_map_corridor_count",
		int(global_corridors.get("count", builder.get("generated_map_corridor_count")))
		if bool(global_corridors.get("enabled", true))
		else 0
	)
	builder.set(
		"generated_map_corridor_width",
		int(global_corridors.get("width_cells", builder.get("generated_map_corridor_width")))
	)
	builder.set(
		"generated_map_corridor_length",
		float(global_corridors.get("length_factor", builder.get("generated_map_corridor_length")))
	)
	builder.set(
		"generated_map_corridor_wobble",
		float(global_corridors.get("wobble_chance", builder.get("generated_map_corridor_wobble")))
	)
	builder.set(
		"generated_map_mineral_base_chance",
		float(global_distribution.get("base_candidate_chance", 0.02))
	)
	builder.set(
		"generated_map_mineral_exposed_chance",
		float(global_distribution.get("exposed_wall_candidate_chance", 0.08))
	)
	_apply_poi_template_overrides_to_builder(builder, config_dict)


static func _apply_poi_template_overrides(
	config: WdcMapGenerationTypes.MapConfig,
	config_dict: Dictionary
) -> void:
	var poi_generation: Dictionary = config_dict.get("poi_generation", {}) as Dictionary
	var poi_types: Array = poi_generation.get("poi_types", []) as Array
	var sorted_templates: Array[Dictionary] = []
	for poi_value: Variant in poi_types:
		if not (poi_value is Dictionary):
			continue
		var template_dict: Dictionary = (poi_value as Dictionary).duplicate(true)
		if not bool(template_dict.get("enabled", true)):
			continue
		sorted_templates.append(template_dict)
	if sorted_templates.is_empty():
		return
	_apply_single_poi_template(config, sorted_templates[0], "large")
	if sorted_templates.size() >= 2:
		_apply_single_poi_template(config, sorted_templates[1], "medium")
	if sorted_templates.size() >= 3:
		_apply_single_poi_template(config, sorted_templates[2], "small")


static func _apply_single_poi_template(
	config: WdcMapGenerationTypes.MapConfig,
	template_dict: Dictionary,
	slot_name: String
) -> void:
	var count_value: int = maxi(int(template_dict.get("count", 0)), 0)
	var placement: Dictionary = template_dict.get("placement", {}) as Dictionary
	var trace: Dictionary = template_dict.get("trace", {}) as Dictionary
	var main_room: Dictionary = template_dict.get("main_room", {}) as Dictionary
	var footprint_padding: int = maxi(int(placement.get("footprint_padding_cells", 0)), 0)
	var room_width_max: int = maxi(int(main_room.get("width_max", 1)), 1)
	var room_height_max: int = maxi(int(main_room.get("height_max", 1)), 1)
	var derived_radius: int = maxi(
		int(ceili(float(maxi(room_width_max, room_height_max)) * 0.5)) + footprint_padding,
		0
	)
	var min_distance: float = float(
		placement.get("min_distance_from_other_pois_cells", float(derived_radius * 2 + 1))
	)
	match slot_name:
		"large":
			config.large_poi_count = count_value
			config.large_poi_min_distance = min_distance
			config.large_poi_radius = derived_radius
			config.large_poi_irregularity = 0.0
			config.large_poi_special_block_count = 1
			config.trace_large_radius = float(trace.get("radius_cells", config.trace_large_radius))
			config.trace_large_density = float(trace.get("density_ratio", config.trace_large_density))
			config.trace_large_rays = float(trace.get("rays", config.trace_large_rays))
			config.trace_large_twist = float(trace.get("twist", config.trace_large_twist))
		"medium":
			config.medium_poi_count = count_value
			config.medium_poi_min_distance = min_distance
			config.medium_poi_radius = derived_radius
			config.medium_poi_irregularity = 0.0
			config.medium_poi_special_block_count = 1
			config.trace_medium_radius = float(trace.get("radius_cells", config.trace_medium_radius))
			config.trace_medium_density = float(trace.get("density_ratio", config.trace_medium_density))
			config.trace_medium_rays = float(trace.get("rays", config.trace_medium_rays))
			config.trace_medium_twist = float(trace.get("twist", config.trace_medium_twist))
		"small":
			config.small_poi_count = count_value
			config.small_poi_min_distance = min_distance
			config.small_poi_radius = derived_radius
			config.small_poi_irregularity = 0.0
			config.small_poi_special_block_count = 1
			config.trace_small_radius = float(trace.get("radius_cells", config.trace_small_radius))
			config.trace_small_density = float(trace.get("density_ratio", config.trace_small_density))
			config.trace_small_rays = float(trace.get("rays", config.trace_small_rays))
			config.trace_small_twist = float(trace.get("twist", config.trace_small_twist))


static func _normalize_cluster_types(cluster_types_value: Variant) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	if not (cluster_types_value is Array):
		return normalized
	for cluster_value: Variant in cluster_types_value:
		if not (cluster_value is Dictionary):
			continue
		var cluster_dict: Dictionary = (cluster_value as Dictionary).duplicate(true)
		if str(cluster_dict.get("id", "")).strip_edges().is_empty():
			continue
		cluster_dict["enabled"] = bool(cluster_dict.get("enabled", true))
		cluster_dict["tile_type_id"] = str(cluster_dict.get("tile_type_id", ""))
		cluster_dict["spawn_scope"] = str(cluster_dict.get("spawn_scope", "global"))
		cluster_dict["weight"] = maxf(float(cluster_dict.get("weight", 0.0)), 0.0)
		cluster_dict["min_cluster_size"] = maxi(int(cluster_dict.get("min_cluster_size", 1)), 1)
		cluster_dict["max_cluster_size"] = maxi(
			int(cluster_dict.get("max_cluster_size", cluster_dict.get("min_cluster_size", 1))),
			int(cluster_dict.get("min_cluster_size", 1))
		)
		cluster_dict["require_stone"] = bool(cluster_dict.get("require_stone", true))
		cluster_dict["spawn_probability"] = clampf(
			float(cluster_dict.get("spawn_probability", 0.0)),
			0.0,
			1.0
		)
		normalized.append(cluster_dict)
	return normalized


static func _normalize_cluster_overrides(
	cluster_overrides_value: Variant,
	cluster_types: Array[Dictionary]
) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	if not (cluster_overrides_value is Array):
		return normalized
	for override_value: Variant in cluster_overrides_value:
		if not (override_value is Dictionary):
			continue
		var override_dict: Dictionary = (override_value as Dictionary).duplicate(true)
		var base_cluster_type_id: String = str(override_dict.get("base_cluster_type_id", ""))
		var merged: Dictionary = _find_cluster_type_by_id(cluster_types, base_cluster_type_id)
		if merged.is_empty():
			continue
		merged["id"] = str(override_dict.get("id", ""))
		if merged["id"] == "":
			continue
		merged["tile_type_id"] = str(merged.get("tile_type_id", ""))
		merged["spawn_scope"] = str(override_dict.get("spawn_scope", merged.get("spawn_scope", "global")))
		merged["min_cluster_size"] = maxi(
			int(override_dict.get("min_cluster_size", merged.get("min_cluster_size", 1))),
			1
		)
		merged["max_cluster_size"] = maxi(
			int(override_dict.get("max_cluster_size", merged.get("max_cluster_size", merged["min_cluster_size"]))),
			int(merged["min_cluster_size"])
		)
		merged["require_stone"] = bool(
			override_dict.get("require_stone", merged.get("require_stone", true))
		)
		merged["spawn_probability"] = clampf(
			float(override_dict.get("spawn_probability", merged.get("spawn_probability", 0.0))),
			0.0,
			1.0
		)
		normalized.append(merged)
	return normalized


static func _find_cluster_type_by_id(
	cluster_types: Array[Dictionary],
	cluster_type_id: String
) -> Dictionary:
	for cluster_entry: Dictionary in cluster_types:
		if str(cluster_entry.get("id", "")) == cluster_type_id:
			return cluster_entry.duplicate(true)
	return {}


static func _normalize_map_layers(layer_values: Variant) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	if not (layer_values is Array):
		return normalized
	for layer_value: Variant in layer_values:
		if not (layer_value is Dictionary):
			continue
		var layer_dict: Dictionary = (layer_value as Dictionary).duplicate(true)
		var layer_id: String = str(layer_dict.get("id", "")).strip_edges()
		if layer_id.is_empty():
			continue
		layer_dict["id"] = layer_id
		if layer_dict.has("max_radius_cells"):
			layer_dict["max_radius_cells"] = maxf(float(layer_dict["max_radius_cells"]), 0.0)
		if layer_dict.has("max_radius_ratio"):
			layer_dict["max_radius_ratio"] = maxf(float(layer_dict["max_radius_ratio"]), 0.0)
		layer_dict["stone_max_hit_points"] = maxi(
			int(layer_dict.get("stone_max_hit_points", 1)),
			1
		)
		layer_dict["mineral_budget_weight"] = maxf(
			float(layer_dict.get("mineral_budget_weight", 1.0)),
			0.0
		)
		layer_dict["poi_budget_weight"] = maxf(
			float(layer_dict.get("poi_budget_weight", 1.0)),
			0.0
		)
		layer_dict["trap_budget_weight"] = maxf(
			float(layer_dict.get("trap_budget_weight", 1.0)),
			0.0
		)
		layer_dict["monster_budget_weight"] = maxf(
			float(layer_dict.get("monster_budget_weight", 1.0)),
			0.0
		)
		layer_dict["room_content_danger_multiplier"] = maxf(
			float(layer_dict.get("room_content_danger_multiplier", 1.0)),
			0.0
		)
		if layer_dict.has("boundary_noise_amplitude_cells"):
			layer_dict["boundary_noise_amplitude_cells"] = maxf(
				float(layer_dict["boundary_noise_amplitude_cells"]),
				0.0
			)
		if layer_dict.has("boundary_noise_scale_cells"):
			layer_dict["boundary_noise_scale_cells"] = maxf(
				float(layer_dict["boundary_noise_scale_cells"]),
				1.0
			)
		if layer_dict.has("boundary_noise_octaves"):
			layer_dict["boundary_noise_octaves"] = clampi(
				int(layer_dict["boundary_noise_octaves"]),
				1,
				6
			)
		if layer_dict.has("boundary_noise_persistence"):
			layer_dict["boundary_noise_persistence"] = clampf(
				float(layer_dict["boundary_noise_persistence"]),
				0.0,
				1.0
			)
		if layer_dict.has("boundary_noise_seed_offset"):
			layer_dict["boundary_noise_seed_offset"] = int(
				layer_dict["boundary_noise_seed_offset"]
			)
		normalized.append(layer_dict)
	return normalized


static func _apply_player_spawn_config(
	config: WdcMapGenerationTypes.MapConfig,
	player_spawn_value: Variant
) -> void:
	if not (player_spawn_value is Dictionary):
		return
	var player_spawn: Dictionary = player_spawn_value as Dictionary
	config.player_spawn_count = maxi(int(player_spawn.get("count", config.player_spawn_count)), 0)
	config.player_spawn_layer_id = str(
		player_spawn.get("layer_id", config.player_spawn_layer_id)
	).strip_edges()
	config.player_spawn_edge_margin_cells = maxi(
		int(player_spawn.get("edge_margin_cells", config.player_spawn_edge_margin_cells)),
		0
	)
	config.player_spawn_min_distance_between_spawns_cells = maxf(
		float(
			player_spawn.get(
				"min_distance_between_spawns_cells",
				config.player_spawn_min_distance_between_spawns_cells
			)
		),
		0.0
	)
	config.player_spawn_clearance_radius_cells = maxi(
		int(
			player_spawn.get(
				"clearance_radius_cells",
				config.player_spawn_clearance_radius_cells
			)
		),
		0
	)
	config.player_spawn_min_clearance_ratio = clampf(
		float(player_spawn.get("min_clearance_ratio", config.player_spawn_min_clearance_ratio)),
		0.0,
		1.0
	)


static func _apply_extraction_site_config(
	config: WdcMapGenerationTypes.MapConfig,
	extraction_sites_value: Variant,
	allow_legacy_layer_default: bool = true
) -> void:
	if not (extraction_sites_value is Dictionary):
		return
	var extraction_sites: Dictionary = extraction_sites_value as Dictionary
	config.extraction_site_count = maxi(
		int(extraction_sites.get("count", config.extraction_site_count)),
		0
	)
	config.extraction_site_layer_distribution = _normalize_site_layer_distribution(
		extraction_sites.get(
			"layer_distribution",
			config.extraction_site_layer_distribution
		),
		allow_legacy_layer_default
	)
	config.extraction_site_min_distance_from_player_spawns_cells = maxf(
		float(
			extraction_sites.get(
				"min_distance_from_player_spawns_cells",
				config.extraction_site_min_distance_from_player_spawns_cells
			)
		),
		0.0
	)
	config.extraction_site_min_distance_between_sites_cells = maxf(
		float(
			extraction_sites.get(
				"min_distance_between_sites_cells",
				config.extraction_site_min_distance_between_sites_cells
			)
		),
		0.0
	)
	config.extraction_site_edge_margin_cells = maxi(
		int(extraction_sites.get("edge_margin_cells", config.extraction_site_edge_margin_cells)),
		0
	)
	config.extraction_site_clearance_radius_cells = maxi(
		int(
			extraction_sites.get(
				"clearance_radius_cells",
				config.extraction_site_clearance_radius_cells
			)
		),
		0
	)
	config.extraction_site_min_clearance_ratio = clampf(
		float(
			extraction_sites.get(
				"min_clearance_ratio",
				config.extraction_site_min_clearance_ratio
			)
		),
		0.0,
		1.0
	)


static func _normalize_site_layer_distribution(
	distribution_value: Variant,
	allow_legacy_default: bool = true
) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	if distribution_value is Array:
		var distribution: Array = distribution_value as Array
		for entry_value: Variant in distribution:
			if not (entry_value is Dictionary):
				continue
			var entry: Dictionary = entry_value as Dictionary
			var layer_id: String = str(entry.get("layer_id", "")).strip_edges()
			if layer_id.is_empty():
				layer_id = str(entry.get("id", "")).strip_edges()
			var ratio: float = maxf(float(entry.get("ratio", 0.0)), 0.0)
			if layer_id.is_empty() or ratio <= 0.0:
				continue
			normalized.append({
				"layer_id": layer_id,
				"ratio": ratio,
			})
	if normalized.is_empty() and allow_legacy_default:
		normalized = [
			{"layer_id": "inner", "ratio": 0.8},
			{"layer_id": "middle", "ratio": 0.2},
		]
	return normalized


static func _normalize_poi_templates(poi_templates_value: Variant) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	if not (poi_templates_value is Array):
		return normalized
	for poi_value: Variant in poi_templates_value:
		if not (poi_value is Dictionary):
			continue
		var poi_dict: Dictionary = (poi_value as Dictionary).duplicate(true)
		if str(poi_dict.get("id", "")).strip_edges().is_empty():
			continue
		normalized.append(poi_dict)
	return normalized


static func _normalize_spawn_templates(
	templates_value: Variant,
	required_field: String
) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	if not (templates_value is Array):
		return normalized
	for template_value: Variant in templates_value:
		if not (template_value is Dictionary):
			continue
		var template_dict: Dictionary = (template_value as Dictionary).duplicate(true)
		if str(template_dict.get("id", "")).strip_edges().is_empty():
			continue
		if str(template_dict.get(required_field, "")).strip_edges().is_empty():
			continue
		normalized.append(template_dict)
	return normalized


static func _apply_poi_template_overrides_to_builder(
	builder: Node,
	config_dict: Dictionary
) -> void:
	var config: WdcMapGenerationTypes.MapConfig = WdcMapGenerationTypes.MapConfig.new()
	apply_config_dict_to_legacy_map_config(config, config_dict)
	builder.set("generated_map_large_poi_count", config.large_poi_count)
	builder.set("generated_map_large_poi_min_distance", config.large_poi_min_distance)
	builder.set("generated_map_large_poi_radius", config.large_poi_radius)
	builder.set("generated_map_large_poi_irregularity", config.large_poi_irregularity)
	builder.set("generated_map_large_poi_special_block_count", config.large_poi_special_block_count)
	builder.set("generated_map_medium_poi_count", config.medium_poi_count)
	builder.set("generated_map_medium_poi_min_distance", config.medium_poi_min_distance)
	builder.set("generated_map_medium_poi_radius", config.medium_poi_radius)
	builder.set("generated_map_medium_poi_irregularity", config.medium_poi_irregularity)
	builder.set("generated_map_medium_poi_special_block_count", config.medium_poi_special_block_count)
	builder.set("generated_map_small_poi_count", config.small_poi_count)
	builder.set("generated_map_small_poi_min_distance", config.small_poi_min_distance)
	builder.set("generated_map_small_poi_radius", config.small_poi_radius)
	builder.set("generated_map_small_poi_irregularity", config.small_poi_irregularity)
	builder.set("generated_map_small_poi_special_block_count", config.small_poi_special_block_count)
	builder.set("generated_map_trace_large_radius", config.trace_large_radius)
	builder.set("generated_map_trace_large_density", config.trace_large_density)
	builder.set("generated_map_trace_large_rays", config.trace_large_rays)
	builder.set("generated_map_trace_large_twist", config.trace_large_twist)
	builder.set("generated_map_trace_medium_radius", config.trace_medium_radius)
	builder.set("generated_map_trace_medium_density", config.trace_medium_density)
	builder.set("generated_map_trace_medium_rays", config.trace_medium_rays)
	builder.set("generated_map_trace_medium_twist", config.trace_medium_twist)
	builder.set("generated_map_trace_small_radius", config.trace_small_radius)
	builder.set("generated_map_trace_small_density", config.trace_small_density)
	builder.set("generated_map_trace_small_rays", config.trace_small_rays)
	builder.set("generated_map_trace_small_twist", config.trace_small_twist)


## 图纸只在解析配置时读取；生成阶段与重试共享同一份依赖快照。
static func _resolve_authored_pois(raw: Dictionary, overrides: Dictionary, issues: Array[Dictionary]) -> Dictionary:
	var references: Array[Dictionary] = []
	var poi_generation: Dictionary = raw.get("poi_generation", {}) as Dictionary
	for value: Variant in poi_generation.get("poi_types", []):
		if not value is Dictionary:
			continue
		var template: Dictionary = value
		if str(raw.get("region_layout", {}).get("mode", "")) == WdcMapGenerationTypes.LAYOUT_MODE_POI_ONLY_V1 and str(template.get("id", "")) != str(raw.get("poi_only", {}).get("source_template_id", "")):
			continue
		var kind: String = str(template.get("layout_kind", "legacy_rooms"))
		if kind == "legacy_rooms":
			continue
		var path: String = "poi_generation.poi_types.%s" % str(template.get("id", ""))
		if kind != "authored_rooms":
			issues.append(_config_issue("unknown_poi_layout_kind", path, "", "未知 POI 构造类型：%s" % kind))
			continue
		if int(raw.get("schema_version", 0)) != 3 or not raw.has("region_layout"):
			issues.append(_config_issue("authored_poi_requires_v3", path, "", "图纸组装需要显式布局模式和 schema_version=3"))
		for old_key: String in ["main_room", "sub_rooms", "connectivity", "core_metadata"]:
			if template.has(old_key):
				issues.append(_config_issue("mixed_poi_layout", path + "." + old_key, "", "图纸组装不能混填旧矩形几何或坐标 metadata"))
		references.append(template)
	if references.is_empty():
		return {}
	var composition_ids: Array = []
	for template: Dictionary in references:
		var id: String = str(template.get("composition_id", ""))
		if not composition_ids.has(id):
			composition_ids.append(id)
	var bundle: Dictionary = POI_RESOURCE_CATALOG.load_bundle(overrides, composition_ids)
	if not bool(bundle.get("valid", false)):
		for issue: Dictionary in bundle.get("issues", []):
			issues.append(issue.duplicate(true))
		return {}
	for template: Dictionary in references:
		var composition_id: String = str(template.get("composition_id", ""))
		if not (bundle.get("compositions", {}) as Dictionary).has(composition_id):
			issues.append(_config_issue("unknown_poi_composition", "poi_generation.poi_types.%s.composition_id" % str(template.get("id", "")), "", "找不到 POI 组合：%s" % composition_id))
	return bundle


static func _validate_region_schema_version(
	raw_config: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var version_value: Variant = raw_config.get("schema_version", null)
	var is_numeric: bool = typeof(version_value) == TYPE_INT or typeof(version_value) == TYPE_FLOAT
	if (
		not is_numeric
		or float(version_value) != floor(float(version_value))
		or int(version_value) not in [WdcMapGenerationTypes.REGION_LAYOUT_CONFIG_SCHEMA_VERSION, 3]
	):
		issues.append(_config_issue(
			"unsupported_region_layout_schema_version",
			"schema_version",
			"",
			"pve_four_region_v1 只支持 schema version 2 或 3"
		))


static func _validate_raw_legacy_conflicts(
	raw_config: Dictionary,
	issues: Array[Dictionary]
) -> void:
	if raw_config.has("map_layers"):
		issues.append(_config_issue(
			"conflicting_legacy_region_field",
			"map_layers",
			"",
			"四区域模式不得声明 legacy map_layers"
		))
	if raw_config.has("boss_generation"):
		issues.append(_config_issue(
			"conflicting_legacy_region_field",
			"boss_generation",
			WdcMapGenerationTypes.REGION_ROLE_BOSS,
			"四区域模式不得声明 legacy boss_generation"
		))
	var map_value: Variant = raw_config.get("map", null)
	if not (map_value is Dictionary):
		return
	var map_dict: Dictionary = map_value as Dictionary
	var player_spawn_value: Variant = map_dict.get("player_spawn", null)
	if player_spawn_value is Dictionary and (player_spawn_value as Dictionary).has("layer_id"):
		issues.append(_config_issue(
			"conflicting_legacy_region_field",
			"map.player_spawn.layer_id",
			WdcMapGenerationTypes.REGION_ROLE_REGULAR,
			"四区域模式不得声明出生 layer_id"
		))
	var extraction_sites_value: Variant = map_dict.get("extraction_sites", null)
	if extraction_sites_value is Dictionary and (extraction_sites_value as Dictionary).has("layer_distribution"):
		issues.append(_config_issue(
			"conflicting_legacy_region_field",
			"map.extraction_sites.layer_distribution",
			WdcMapGenerationTypes.REGION_ROLE_REGULAR,
			"四区域模式不得声明撤离 layer_distribution"
		))


static func _normalize_four_region_layout(
	raw_config: Dictionary,
	raw_region_layout: Dictionary,
	issues: Array[Dictionary]
) -> Dictionary:
	var allowed_layout_keys: Array[String] = [
		"mode",
		WdcMapGenerationTypes.REGION_ROLE_REGULAR,
		WdcMapGenerationTypes.REGION_ROLE_HIGH_1,
		WdcMapGenerationTypes.REGION_ROLE_HIGH_2,
		WdcMapGenerationTypes.REGION_ROLE_BOSS,
	]
	_append_unknown_field_issues(
		raw_region_layout,
		allowed_layout_keys,
		"region_layout",
		"",
		issues
	)
	var normalized: Dictionary = {
		"mode": WdcMapGenerationTypes.LAYOUT_MODE_PVE_FOUR_REGION_V1,
	}
	var seen_region_ids: Dictionary = {}
	for role: String in WdcMapGenerationTypes.REGION_ROLE_ORDER:
		if not raw_region_layout.has(role):
			issues.append(_config_issue(
				"missing_region_role",
				"region_layout.%s" % role,
				role,
				"四区域声明缺少固定角色 %s" % role
			))
			continue
		var role_value: Variant = raw_region_layout.get(role)
		if not (role_value is Dictionary):
			issues.append(_config_issue(
				"invalid_region_layout_declaration",
				"region_layout.%s" % role,
				role,
				"区域槽位必须是对象"
			))
			continue
		var normalized_slot: Dictionary = _normalize_region_slot(
			role,
			role_value as Dictionary,
			issues
		)
		if normalized_slot.is_empty():
			continue
		var region_id: String = str(normalized_slot.get("id", ""))
		if not region_id.is_empty():
			if seen_region_ids.has(region_id):
				issues.append(_config_issue(
					"duplicate_region_id",
					"region_layout.%s.id" % role,
					role,
					"区域 id 与 %s 重复" % str(seen_region_ids[region_id])
				))
			else:
				seen_region_ids[region_id] = role
		normalized[role] = normalized_slot
	_validate_core_poi_references(raw_config, normalized, issues)
	return normalized


static func _normalize_region_slot(
	role: String,
	raw_slot: Dictionary,
	issues: Array[Dictionary]
) -> Dictionary:
	var allowed_keys: Array[String] = ["id", "display_name", "content_profile_id"]
	if role != WdcMapGenerationTypes.REGION_ROLE_REGULAR:
		allowed_keys.append("layout_profile_id")
		allowed_keys.append("core_poi")
	if role == WdcMapGenerationTypes.REGION_ROLE_BOSS:
		allowed_keys.append("encounter_profile_id")
	_append_unknown_field_issues(
		raw_slot,
		allowed_keys,
		"region_layout.%s" % role,
		role,
		issues
	)
	var region_id_value: Variant = _strict_config_string(raw_slot.get("id", null))
	var region_id: String = region_id_value as String if region_id_value is String else ""
	if region_id_value == null:
		issues.append(_config_issue(
			"invalid_region_layout_declaration",
			"region_layout.%s.id" % role,
			role,
			"区域 id 必须是字符串"
		))
	elif region_id.is_empty():
		issues.append(_config_issue(
			"invalid_region_layout_declaration",
			"region_layout.%s.id" % role,
			role,
			"区域 id 不能为空"
		))
	var display_name_value: Variant = _strict_config_string(
		raw_slot.get("display_name", null)
	)
	var display_name: String = (
		display_name_value as String if display_name_value is String else ""
	)
	if not raw_slot.has("display_name"):
		issues.append(_config_issue(
			"missing_region_display_name",
			"region_layout.%s.display_name" % role,
			role,
			"区域展示名不能为空"
		))
	elif display_name_value == null:
		issues.append(_config_issue(
			"invalid_region_layout_declaration",
			"region_layout.%s.display_name" % role,
			role,
			"区域展示名必须是字符串"
		))
	elif display_name.is_empty():
		issues.append(_config_issue(
			"missing_region_display_name",
			"region_layout.%s.display_name" % role,
			role,
			"区域展示名不能为空"
		))
	var content_profile_value: Variant = _strict_config_string(
		raw_slot.get("content_profile_id", null)
	)
	var content_profile_id: String = (
		content_profile_value as String if content_profile_value is String else ""
	)
	if not raw_slot.has("content_profile_id"):
		issues.append(_config_issue(
			"missing_content_profile_reference",
			"region_layout.%s.content_profile_id" % role,
			role,
			"区域 content profile 引用不能为空"
		))
	elif content_profile_value == null:
		issues.append(_config_issue(
			"invalid_region_layout_declaration",
			"region_layout.%s.content_profile_id" % role,
			role,
			"区域 content profile 引用必须是字符串"
		))
	elif content_profile_id.is_empty():
		issues.append(_config_issue(
			"missing_content_profile_reference",
			"region_layout.%s.content_profile_id" % role,
			role,
			"区域 content profile 引用不能为空"
		))
	var normalized: Dictionary = {
		"id": region_id,
		"display_name": display_name,
		"content_profile_id": content_profile_id,
		"role": role,
		"difficulty_rank": WdcMapGenerationTypes.get_region_difficulty_rank(role),
	}
	if role == WdcMapGenerationTypes.REGION_ROLE_REGULAR:
		return normalized
	var layout_profile_value: Variant = _strict_config_string(
		raw_slot.get("layout_profile_id", null)
	)
	var layout_profile_id: String = (
		layout_profile_value as String if layout_profile_value is String else ""
	)
	if not raw_slot.has("layout_profile_id"):
		issues.append(_config_issue(
			"missing_layout_profile_reference",
			"region_layout.%s.layout_profile_id" % role,
			role,
			"高风险区域 layout profile 引用不能为空"
		))
	elif layout_profile_value == null:
		issues.append(_config_issue(
			"invalid_region_layout_declaration",
			"region_layout.%s.layout_profile_id" % role,
			role,
			"高风险区域 layout profile 引用必须是字符串"
		))
	elif layout_profile_id.is_empty():
		issues.append(_config_issue(
			"missing_layout_profile_reference",
			"region_layout.%s.layout_profile_id" % role,
			role,
			"高风险区域 layout profile 引用不能为空"
		))
	normalized["layout_profile_id"] = layout_profile_id
	var core_poi_value: Variant = raw_slot.get("core_poi", null)
	if not (core_poi_value is Dictionary):
		issues.append(_config_issue(
			"missing_core_poi_reference",
			"region_layout.%s.core_poi" % role,
			role,
			"高风险区域必须声明核心 POI"
		))
	else:
		var raw_core_poi: Dictionary = core_poi_value as Dictionary
		_append_unknown_field_issues(
			raw_core_poi,
			["template_id", "max_center_offset_cells"],
			"region_layout.%s.core_poi" % role,
			role,
			issues
		)
		var template_id_value: Variant = _strict_config_string(
			raw_core_poi.get("template_id", null)
		)
		var template_id: String = (
			template_id_value as String if template_id_value is String else ""
		)
		if not raw_core_poi.has("template_id"):
			issues.append(_config_issue(
				"missing_core_poi_reference",
				"region_layout.%s.core_poi.template_id" % role,
				role,
				"核心 POI 模板引用不能为空"
			))
		elif template_id_value == null:
			issues.append(_config_issue(
				"invalid_region_layout_declaration",
				"region_layout.%s.core_poi.template_id" % role,
				role,
				"核心 POI 模板引用必须是字符串"
			))
		elif template_id.is_empty():
			issues.append(_config_issue(
				"missing_core_poi_reference",
				"region_layout.%s.core_poi.template_id" % role,
				role,
				"核心 POI 模板引用不能为空"
			))
		var offset_value: Variant = raw_core_poi.get("max_center_offset_cells", null)
		var offset_is_number: bool = (
			typeof(offset_value) == TYPE_INT or typeof(offset_value) == TYPE_FLOAT
		)
		if (
			not offset_is_number
			or float(offset_value) != floor(float(offset_value))
			or int(offset_value) < 0
		):
			issues.append(_config_issue(
				"invalid_region_layout_declaration",
				"region_layout.%s.core_poi.max_center_offset_cells" % role,
				role,
				"核心 POI 中心偏移必须是非负整数"
			))
		normalized["core_poi"] = {
			"template_id": template_id,
			"max_center_offset_cells": maxi(int(offset_value), 0) if offset_is_number else 0,
		}
	if role == WdcMapGenerationTypes.REGION_ROLE_BOSS:
		var encounter_profile_value: Variant = _strict_config_string(
			raw_slot.get("encounter_profile_id", null)
		)
		var encounter_profile_id: String = (
			encounter_profile_value as String if encounter_profile_value is String else ""
		)
		if not raw_slot.has("encounter_profile_id"):
			issues.append(_config_issue(
				"missing_boss_encounter_reference",
				"region_layout.boss.encounter_profile_id",
				role,
				"BOSS 区域 encounter profile 引用不能为空"
			))
		elif encounter_profile_value == null:
			issues.append(_config_issue(
				"invalid_region_layout_declaration",
				"region_layout.boss.encounter_profile_id",
				role,
				"BOSS encounter profile 引用必须是字符串"
			))
		elif encounter_profile_id.is_empty():
			issues.append(_config_issue(
				"missing_boss_encounter_reference",
				"region_layout.boss.encounter_profile_id",
				role,
				"BOSS 区域 encounter profile 引用不能为空"
			))
		normalized["encounter_profile_id"] = encounter_profile_id
	return normalized


static func _normalize_region_generation(
	raw_config: Dictionary,
	normalized_region_layout: Dictionary,
	issues: Array[Dictionary]
) -> Dictionary:
	if not raw_config.has("region_generation"):
		issues.append(_config_issue(
			"invalid_region_profile",
			"region_generation",
			"",
			"pve_four_region_v1 必须声明 region_generation"
		))
		return {}
	var generation_value: Variant = raw_config.get("region_generation")
	if not (generation_value is Dictionary):
		issues.append(_config_issue(
			"invalid_region_profile",
			"region_generation",
			"",
			"region_generation 必须是对象"
		))
		return {}
	var raw_generation: Dictionary = generation_value as Dictionary
	_append_unknown_region_profile_fields(
		raw_generation,
		["layout_profiles", "content_profiles"],
		"region_generation",
		issues
	)
	var reference_counts: Dictionary = _build_region_content_reference_counts(raw_config)
	var normalized_layout_profiles: Array[Dictionary] = _normalize_region_layout_profiles(
		raw_generation.get("layout_profiles", null),
		issues
	)
	var normalized_content_profiles: Array[Dictionary] = _normalize_region_content_profiles(
		raw_generation.get("content_profiles", null),
		reference_counts,
		issues
	)
	_validate_region_slot_profile_references(
		normalized_region_layout,
		normalized_layout_profiles,
		normalized_content_profiles,
		issues
	)
	return {
		"layout_profiles": normalized_layout_profiles,
		"content_profiles": normalized_content_profiles,
	}


static func _normalize_region_layout_profiles(
	profiles_value: Variant,
	issues: Array[Dictionary]
) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	var base_path: String = "region_generation.layout_profiles"
	if not (profiles_value is Array):
		issues.append(_config_issue(
			"invalid_region_profile",
			base_path,
			"",
			"layout_profiles 必须是非空数组"
		))
		return normalized
	var profiles: Array = profiles_value as Array
	if profiles.is_empty():
		issues.append(_config_issue(
			"invalid_region_profile",
			base_path,
			"",
			"layout_profiles 必须至少包含一个 profile"
		))
		return normalized
	var seen_ids: Dictionary = {}
	for profile_index: int in range(profiles.size()):
		var profile_path: String = "%s[%d]" % [base_path, profile_index]
		var profile_value: Variant = profiles[profile_index]
		if not (profile_value is Dictionary):
			issues.append(_config_issue(
				"invalid_region_profile",
				profile_path,
				"",
				"layout profile 必须是对象"
			))
			continue
		var profile: Dictionary = _normalize_region_layout_profile(
			profile_value as Dictionary,
			profile_path,
			issues
		)
		var profile_id: String = str(profile.get("id", ""))
		if not profile_id.is_empty():
			if seen_ids.has(profile_id):
				issues.append(_config_issue(
					"duplicate_region_profile_id",
					"%s.id" % profile_path,
					"",
					"layout profile id 重复：%s" % profile_id
				))
			else:
				seen_ids[profile_id] = profile_index
		normalized.append(profile)
	return normalized


static func _normalize_region_layout_profile(
	raw_profile: Dictionary,
	profile_path: String,
	issues: Array[Dictionary]
) -> Dictionary:
	_append_unknown_region_profile_fields(
		raw_profile,
		[
			"id",
			"shape_algorithm",
			"min_size_cells",
			"max_size_cells",
			"edge_margin_cells",
			"regular_moat_cells",
			"core_poi_padding_cells",
			"seed_salt",
			"max_attempts",
		],
		profile_path,
		issues
	)
	var profile_id: String = _read_region_profile_string(
		raw_profile,
		"id",
		"%s.id" % profile_path,
		issues
	)
	var shape_algorithm: String = _read_region_profile_string(
		raw_profile,
		"shape_algorithm",
		"%s.shape_algorithm" % profile_path,
		issues
	)
	if (
		not shape_algorithm.is_empty()
		and not WdcMapGenerationTypes.REGION_LAYOUT_SHAPE_ALGORITHMS.has(shape_algorithm)
	):
		issues.append(_config_issue(
			"invalid_region_profile",
			"%s.shape_algorithm" % profile_path,
			"",
			"不支持的四区域形状算法：%s" % shape_algorithm
		))
	var min_size: Dictionary = _normalize_region_profile_size(
		raw_profile.get("min_size_cells", null),
		"%s.min_size_cells" % profile_path,
		issues
	)
	var max_size: Dictionary = _normalize_region_profile_size(
		raw_profile.get("max_size_cells", null),
		"%s.max_size_cells" % profile_path,
		issues
	)
	if int(min_size.get("x", 1)) > int(max_size.get("x", 1)):
		issues.append(_config_issue(
			"invalid_region_profile",
			"%s.min_size_cells.x" % profile_path,
			"",
			"min_size_cells.x 不得大于 max_size_cells.x"
		))
	if int(min_size.get("y", 1)) > int(max_size.get("y", 1)):
		issues.append(_config_issue(
			"invalid_region_profile",
			"%s.min_size_cells.y" % profile_path,
			"",
			"min_size_cells.y 不得大于 max_size_cells.y"
		))
	return {
		"id": profile_id,
		"shape_algorithm": shape_algorithm,
		"min_size_cells": min_size,
		"max_size_cells": max_size,
		"edge_margin_cells": _read_region_profile_integer(
			raw_profile,
			"edge_margin_cells",
			"%s.edge_margin_cells" % profile_path,
			1,
			true,
			issues
		),
		"regular_moat_cells": _read_region_profile_integer(
			raw_profile,
			"regular_moat_cells",
			"%s.regular_moat_cells" % profile_path,
			1,
			true,
			issues
		),
		"core_poi_padding_cells": _read_region_profile_integer(
			raw_profile,
			"core_poi_padding_cells",
			"%s.core_poi_padding_cells" % profile_path,
			0,
			true,
			issues
		),
		"seed_salt": _read_region_profile_integer(
			raw_profile,
			"seed_salt",
			"%s.seed_salt" % profile_path,
			0,
			false,
			issues
		),
		"max_attempts": _read_region_profile_integer(
			raw_profile,
			"max_attempts",
			"%s.max_attempts" % profile_path,
			1,
			true,
			issues
		),
	}


static func _normalize_region_profile_size(
	size_value: Variant,
	path: String,
	issues: Array[Dictionary]
) -> Dictionary:
	if not (size_value is Dictionary):
		issues.append(_config_issue(
			"invalid_region_profile",
			path,
			"",
			"区域尺寸必须是包含 x/y 的对象"
		))
		return {"x": 1, "y": 1}
	var size_dict: Dictionary = size_value as Dictionary
	_append_unknown_region_profile_fields(size_dict, ["x", "y"], path, issues)
	return {
		"x": _read_region_profile_integer(size_dict, "x", "%s.x" % path, 1, true, issues),
		"y": _read_region_profile_integer(size_dict, "y", "%s.y" % path, 1, true, issues),
	}


static func _normalize_region_content_profiles(
	profiles_value: Variant,
	reference_counts: Dictionary,
	issues: Array[Dictionary]
) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	var base_path: String = "region_generation.content_profiles"
	if not (profiles_value is Array):
		issues.append(_config_issue(
			"invalid_region_profile",
			base_path,
			"",
			"content_profiles 必须是非空数组"
		))
		return normalized
	var profiles: Array = profiles_value as Array
	if profiles.is_empty():
		issues.append(_config_issue(
			"invalid_region_profile",
			base_path,
			"",
			"content_profiles 必须至少包含一个 profile"
		))
		return normalized
	var seen_ids: Dictionary = {}
	for profile_index: int in range(profiles.size()):
		var profile_path: String = "%s[%d]" % [base_path, profile_index]
		var profile_value: Variant = profiles[profile_index]
		if not (profile_value is Dictionary):
			issues.append(_config_issue(
				"invalid_region_profile",
				profile_path,
				"",
				"content profile 必须是对象"
			))
			continue
		var profile: Dictionary = _normalize_region_content_profile(
			profile_value as Dictionary,
			profile_path,
			reference_counts,
			issues
		)
		var profile_id: String = str(profile.get("id", ""))
		if not profile_id.is_empty():
			if seen_ids.has(profile_id):
				issues.append(_config_issue(
					"duplicate_region_profile_id",
					"%s.id" % profile_path,
					"",
					"content profile id 重复：%s" % profile_id
				))
			else:
				seen_ids[profile_id] = profile_index
		normalized.append(profile)
	return normalized


static func _normalize_region_content_profile(
	raw_profile: Dictionary,
	profile_path: String,
	reference_counts: Dictionary,
	issues: Array[Dictionary]
) -> Dictionary:
	var allowed_keys: Array[String] = [
		"id",
		"wall_durability",
		"mineral_value_budget",
		"reward_value_budget",
	]
	for group_name_value: Variant in REGION_CONTENT_GROUP_SPECS.keys():
		allowed_keys.append(str(group_name_value))
	_append_unknown_region_profile_fields(raw_profile, allowed_keys, profile_path, issues)
	var normalized: Dictionary = {
		"id": _read_region_profile_string(raw_profile, "id", "%s.id" % profile_path, issues),
		"wall_durability": _normalize_region_wall_durability(
			raw_profile.get("wall_durability", null),
			"%s.wall_durability" % profile_path,
			issues
		),
		"mineral_value_budget": _read_region_profile_integer(
			raw_profile,
			"mineral_value_budget",
			"%s.mineral_value_budget" % profile_path,
			0,
			true,
			issues
		),
		"reward_value_budget": _read_region_profile_integer(
			raw_profile,
			"reward_value_budget",
			"%s.reward_value_budget" % profile_path,
			0,
			true,
			issues
		),
	}
	for group_name_value: Variant in REGION_CONTENT_GROUP_SPECS.keys():
		var group_name: String = str(group_name_value)
		if group_name in ["furnishings", "torches"] and not raw_profile.has(group_name):
			continue
		normalized[group_name] = _normalize_region_content_count_group(
			raw_profile.get(group_name, null),
			group_name,
			"%s.%s" % [profile_path, group_name],
			reference_counts,
			issues
		)
	return normalized


static func _normalize_region_wall_durability(
	value: Variant,
	path: String,
	issues: Array[Dictionary]
) -> Dictionary:
	var allowed_keys: Array[String] = [
		"ordinary_max_hit_points",
		"mineral_max_hit_points",
		"poi_max_hit_points",
	]
	if not (value is Dictionary):
		issues.append(_config_issue(
			"invalid_region_profile",
			path,
			"",
			"wall_durability 必须是对象"
		))
		return {
			"ordinary_max_hit_points": 1,
			"mineral_max_hit_points": 1,
			"poi_max_hit_points": 1,
		}
	var durability: Dictionary = value as Dictionary
	_append_unknown_region_profile_fields(durability, allowed_keys, path, issues)
	var normalized: Dictionary = {}
	for key: String in allowed_keys:
		normalized[key] = _read_region_profile_integer(
			durability,
			key,
			"%s.%s" % [path, key],
			1,
			true,
			issues
		)
	return normalized


static func _normalize_region_content_count_group(
	value: Variant,
	group_name: String,
	path: String,
	reference_counts: Dictionary,
	issues: Array[Dictionary]
) -> Dictionary:
	var spec: Dictionary = REGION_CONTENT_GROUP_SPECS[group_name] as Dictionary
	var expected_unit: String = str(spec.get("count_unit", ""))
	var normalized: Dictionary = {
		"count_unit": expected_unit,
		"target_count": 0,
		"minimum_count": 0,
		"entries": [],
	}
	if not (value is Dictionary):
		issues.append(_config_issue(
			"invalid_region_profile",
			path,
			"",
			"区域内容计数配置必须是对象"
		))
		return normalized
	var group: Dictionary = value as Dictionary
	_append_unknown_region_profile_fields(
		group,
		["count_unit", "target_count", "minimum_count", "entries"],
		path,
		issues
	)
	var count_unit: String = _read_region_profile_string(
		group,
		"count_unit",
		"%s.count_unit" % path,
		issues
	)
	if not count_unit.is_empty() and count_unit != expected_unit:
		issues.append(_config_issue(
			"invalid_region_profile",
			"%s.count_unit" % path,
			"",
			"%s 的固定计数单位必须是 %s" % [group_name, expected_unit]
		))
	var target_count: int = _read_region_profile_integer(
		group,
		"target_count",
		"%s.target_count" % path,
		0,
		true,
		issues
	)
	var minimum_count: int = _read_region_profile_integer(
		group,
		"minimum_count",
		"%s.minimum_count" % path,
		0,
		true,
		issues
	)
	if minimum_count > target_count:
		issues.append(_config_issue(
			"invalid_region_profile",
			"%s.minimum_count" % path,
			"",
			"minimum_count 不得大于 target_count"
		))
	var normalized_entries: Array[Dictionary] = []
	var entries_value: Variant = group.get("entries", null)
	if not (entries_value is Array):
		issues.append(_config_issue(
			"invalid_region_profile",
			"%s.entries" % path,
			"",
			"entries 必须是数组"
		))
	else:
		var entries: Array = entries_value as Array
		for entry_index: int in range(entries.size()):
			var entry_path: String = "%s.entries[%d]" % [path, entry_index]
			var entry_value: Variant = entries[entry_index]
			if not (entry_value is Dictionary):
				issues.append(_config_issue(
					"invalid_region_profile",
					entry_path,
					"",
					"区域内容 entry 必须是对象"
				))
				continue
			normalized_entries.append(_normalize_region_content_entry(
				entry_value as Dictionary,
				group_name,
				entry_path,
				reference_counts,
				issues
			))
		if target_count > 0 and entries.is_empty():
			issues.append(_config_issue(
				"invalid_region_profile",
				"%s.entries" % path,
				"",
				"target_count 大于零时必须提供至少一个允许 entry"
			))
	normalized["count_unit"] = expected_unit
	normalized["target_count"] = target_count
	normalized["minimum_count"] = minimum_count
	normalized["entries"] = normalized_entries
	return normalized


static func _normalize_region_content_entry(
	raw_entry: Dictionary,
	group_name: String,
	path: String,
	reference_counts: Dictionary,
	issues: Array[Dictionary]
) -> Dictionary:
	var spec: Dictionary = REGION_CONTENT_GROUP_SPECS[group_name] as Dictionary
	var entry_key: String = str(spec.get("entry_key", ""))
	var reference_kind: String = str(spec.get("reference_kind", ""))
	var uses_value_cost: bool = bool(spec.get("uses_value_cost", false))
	var allowed_keys: Array[String] = [entry_key, "weight"]
	if uses_value_cost:
		allowed_keys.append("value_cost")
	_append_unknown_region_profile_fields(raw_entry, allowed_keys, path, issues)
	var entry_id: String = _read_region_profile_string(
		raw_entry,
		entry_key,
		"%s.%s" % [path, entry_key],
		issues
	)
	var weight_value: Variant = raw_entry.get("weight", null)
	var weight_is_number: bool = (
		typeof(weight_value) == TYPE_INT or typeof(weight_value) == TYPE_FLOAT
	)
	if not weight_is_number or float(weight_value) <= 0.0:
		issues.append(_config_issue(
			"invalid_region_profile",
			"%s.weight" % path,
			"",
			"entry weight 必须是正数"
		))
	var normalized: Dictionary = {
		entry_key: entry_id,
		"weight": float(weight_value) if weight_is_number else 0.0,
	}
	if uses_value_cost:
		normalized["value_cost"] = _read_region_profile_integer(
			raw_entry,
			"value_cost",
			"%s.value_cost" % path,
			0 if reference_kind in ["prop", "torch"] else 1,
			true,
			issues
		)
	if entry_id.is_empty():
		return normalized
	if reference_kind in ["prop", "torch"]:
		return normalized
	if reference_kind == "room_content":
		if not REGION_ROOM_CONTENT_KINDS.has(entry_id):
			_append_unknown_region_content_reference(entry_id, "%s.%s" % [path, entry_key], issues)
		return normalized
	if reference_kind == "trap":
		if not WdcMapGenerationTypes.REGION_TRAP_KINDS.has(entry_id):
			_append_unknown_region_content_reference(entry_id, "%s.%s" % [path, entry_key], issues)
		return normalized
	var counts: Dictionary = reference_counts.get(reference_kind, {}) as Dictionary
	var match_count: int = int(counts.get(entry_id, 0))
	if match_count == 0:
		_append_unknown_region_content_reference(entry_id, "%s.%s" % [path, entry_key], issues)
	elif match_count > 1:
		issues.append(_config_issue(
			"ambiguous_region_content_reference",
			"%s.%s" % [path, entry_key],
			"",
			"区域内容模板引用匹配到多个同 id 定义：%s" % entry_id
		))
	return normalized


static func _append_unknown_region_content_reference(
	reference_id: String,
	path: String,
	issues: Array[Dictionary]
) -> void:
	issues.append(_config_issue(
		"unknown_region_content_reference",
		path,
		"",
		"区域内容模板引用不存在：%s" % reference_id
	))


static func _build_region_content_reference_counts(raw_config: Dictionary) -> Dictionary:
	var minerals: Dictionary = raw_config.get("minerals", {}) as Dictionary
	var poi_generation: Dictionary = raw_config.get("poi_generation", {}) as Dictionary
	var monster_generation: Dictionary = raw_config.get("monster_generation", {}) as Dictionary
	var mineral_counts: Dictionary = {}
	_append_id_counts(mineral_counts, minerals.get("cluster_types", []), "id")
	var poi_counts: Dictionary = {}
	_append_id_counts(poi_counts, poi_generation.get("poi_types", []), "id")
	var spawn_counts: Dictionary = {}
	_append_id_counts(
		spawn_counts,
		monster_generation.get("isolated_spawn_templates", []),
		"id"
	)
	var nest_counts: Dictionary = {}
	_append_id_counts(nest_counts, monster_generation.get("nest_templates", []), "id")
	return {
		"mineral": mineral_counts,
		"poi": poi_counts,
		"spawn": spawn_counts,
		"nest": nest_counts,
		"camp": _collect_camp_id_counts(poi_generation.get("poi_types", [])),
	}


static func _append_id_counts(target: Dictionary, values: Variant, id_key: String) -> void:
	if not (values is Array):
		return
	for value: Variant in values as Array:
		if not (value is Dictionary):
			continue
		var id_value: Variant = _strict_config_string((value as Dictionary).get(id_key, null))
		if not (id_value is String) or (id_value as String).is_empty():
			continue
		var entry_id: String = id_value as String
		target[entry_id] = int(target.get(entry_id, 0)) + 1


static func _collect_camp_id_counts(poi_templates_value: Variant) -> Dictionary:
	var counts: Dictionary = {}
	if not (poi_templates_value is Array):
		return counts
	for poi_value: Variant in poi_templates_value as Array:
		if not (poi_value is Dictionary):
			continue
		var content_value: Variant = (poi_value as Dictionary).get("content", null)
		if not (content_value is Dictionary):
			continue
		var content: Dictionary = content_value as Dictionary
		for roll_key: String in ["main_room_roll", "sub_room_roll"]:
			var roll_value: Variant = content.get(roll_key, null)
			if not (roll_value is Dictionary):
				continue
			_append_id_counts(
				counts,
				(roll_value as Dictionary).get("camp_entries", []),
				"id"
			)
	return counts


static func _validate_region_slot_profile_references(
	normalized_region_layout: Dictionary,
	layout_profiles: Array[Dictionary],
	content_profiles: Array[Dictionary],
	issues: Array[Dictionary]
) -> void:
	var layout_counts: Dictionary = {}
	_append_id_counts(layout_counts, layout_profiles, "id")
	var content_counts: Dictionary = {}
	_append_id_counts(content_counts, content_profiles, "id")
	for role: String in WdcMapGenerationTypes.REGION_ROLE_ORDER:
		var slot_value: Variant = normalized_region_layout.get(role, null)
		if not (slot_value is Dictionary):
			continue
		var slot: Dictionary = slot_value as Dictionary
		var content_profile_id: String = str(slot.get("content_profile_id", ""))
		if not content_profile_id.is_empty() and int(content_counts.get(content_profile_id, 0)) == 0:
			issues.append(_config_issue(
				"unknown_region_content_profile",
				"region_layout.%s.content_profile_id" % role,
				role,
				"区域引用了不存在的 content profile：%s" % content_profile_id
			))
		if role == WdcMapGenerationTypes.REGION_ROLE_REGULAR:
			continue
		var layout_profile_id: String = str(slot.get("layout_profile_id", ""))
		if not layout_profile_id.is_empty() and int(layout_counts.get(layout_profile_id, 0)) == 0:
			issues.append(_config_issue(
				"unknown_region_layout_profile",
				"region_layout.%s.layout_profile_id" % role,
				role,
				"区域引用了不存在的 layout profile：%s" % layout_profile_id
			))


static func _read_region_profile_string(
	source: Dictionary,
	key: String,
	path: String,
	issues: Array[Dictionary]
) -> String:
	var value: Variant = _strict_config_string(source.get(key, null))
	if value == null or (value as String).is_empty():
		issues.append(_config_issue(
			"invalid_region_profile",
			path,
			"",
			"profile 字段必须是非空字符串"
		))
		return ""
	return value as String


static func _read_region_profile_integer(
	source: Dictionary,
	key: String,
	path: String,
	minimum_value: int,
	has_minimum: bool,
	issues: Array[Dictionary]
) -> int:
	var value: Variant = source.get(key, null)
	if not _is_integer_number(value):
		issues.append(_config_issue(
			"invalid_region_profile",
			path,
			"",
			"profile 字段必须是整数"
		))
		return minimum_value if has_minimum else 0
	var normalized: int = int(value)
	if has_minimum and normalized < minimum_value:
		issues.append(_config_issue(
			"invalid_region_profile",
			path,
			"",
			"profile 字段不得小于 %d" % minimum_value
		))
	return normalized


static func _is_integer_number(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and float(value) == floor(float(value))
	)


static func _append_unknown_region_profile_fields(
	source: Dictionary,
	allowed_keys: Array[String],
	base_path: String,
	issues: Array[Dictionary]
) -> void:
	for key_value: Variant in source.keys():
		var key: String = str(key_value)
		if allowed_keys.has(key):
			continue
		issues.append(_config_issue(
			"invalid_region_profile",
			"%s.%s" % [base_path, key],
			"",
			"region profile 包含未声明字段"
		))


static func _validate_and_normalize_core_poi_metadata(
	raw_config: Dictionary,
	normalized_region_layout: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var poi_generation_value: Variant = raw_config.get("poi_generation", null)
	if not (poi_generation_value is Dictionary):
		return
	var poi_generation: Dictionary = poi_generation_value as Dictionary
	var poi_types_value: Variant = poi_generation.get("poi_types", null)
	if not (poi_types_value is Array):
		return
	var boss_slot: Dictionary = normalized_region_layout.get(
		WdcMapGenerationTypes.REGION_ROLE_BOSS,
		{}
	) as Dictionary
	var boss_core: Dictionary = boss_slot.get("core_poi", {}) as Dictionary
	var boss_template_id: String = str(boss_core.get("template_id", ""))
	var boss_template_match_count: int = 0
	var boss_metadata_count: int = 0
	var poi_types: Array = poi_types_value as Array
	for poi_index: int in range(poi_types.size()):
		var poi_value: Variant = poi_types[poi_index]
		if not (poi_value is Dictionary):
			continue
		var poi_template: Dictionary = poi_value as Dictionary
		var template_id_value: Variant = _strict_config_string(poi_template.get("id", null))
		var template_id: String = template_id_value as String if template_id_value is String else ""
		if template_id == boss_template_id:
			boss_template_match_count += 1
		if str(poi_template.get("layout_kind", "")) == "authored_rooms":
			if template_id == boss_template_id:
				boss_metadata_count += 1
			continue
		if not poi_template.has("core_metadata"):
			continue
		var metadata_path: String = "poi_generation.poi_types[%d].core_metadata" % poi_index
		var normalized_metadata: Dictionary = _normalize_core_poi_metadata(
			poi_template.get("core_metadata"),
			metadata_path,
			issues
		)
		poi_template["core_metadata"] = normalized_metadata
		if template_id == boss_template_id:
			boss_metadata_count += 1
	if boss_template_match_count == 1 and boss_metadata_count == 0:
		issues.append(_config_issue(
			"invalid_core_poi_metadata",
			"region_layout.boss.core_poi.template_id",
			WdcMapGenerationTypes.REGION_ROLE_BOSS,
			"BOSS 核心 POI 模板必须声明 core_metadata"
		))


static func _normalize_core_poi_metadata(
	value: Variant,
	path: String,
	issues: Array[Dictionary]
) -> Dictionary:
	var normalized: Dictionary = {
		"reward_gate_cells": [],
		"reward_object_cells": [],
		"reward_recipe_id": "",
	}
	if not (value is Dictionary):
		issues.append(_config_issue(
			"invalid_core_poi_metadata",
			path,
			"",
			"core_metadata 必须是对象"
		))
		return normalized
	var metadata: Dictionary = value as Dictionary
	for key_value: Variant in metadata.keys():
		var key: String = str(key_value)
		if ["reward_gate_cells", "reward_object_cells", "reward_recipe_id"].has(key):
			continue
		issues.append(_config_issue(
			"invalid_core_poi_metadata",
			"%s.%s" % [path, key],
			"",
			"core_metadata 包含未声明字段"
		))
	normalized["reward_gate_cells"] = _normalize_core_metadata_cells(
		metadata.get("reward_gate_cells", null),
		"%s.reward_gate_cells" % path,
		issues
	)
	normalized["reward_object_cells"] = _normalize_core_metadata_cells(
		metadata.get("reward_object_cells", null),
		"%s.reward_object_cells" % path,
		issues
	)
	var reward_recipe_value: Variant = _strict_config_string(
		metadata.get("reward_recipe_id", null)
	)
	if reward_recipe_value == null or (reward_recipe_value as String).is_empty():
		issues.append(_config_issue(
			"invalid_core_poi_metadata",
			"%s.reward_recipe_id" % path,
			"",
			"reward_recipe_id 必须是非空字符串"
		))
	else:
		normalized["reward_recipe_id"] = reward_recipe_value as String
	return normalized


static func _normalize_core_metadata_cells(
	value: Variant,
	path: String,
	issues: Array[Dictionary]
) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	if not (value is Array) or (value as Array).is_empty():
		issues.append(_config_issue(
			"invalid_core_poi_metadata",
			path,
			"",
			"奖励位置必须是非空 cell 数组"
		))
		return normalized
	var cells: Array = value as Array
	for cell_index: int in range(cells.size()):
		var cell_path: String = "%s[%d]" % [path, cell_index]
		var cell_value: Variant = cells[cell_index]
		if not (cell_value is Dictionary):
			issues.append(_config_issue(
				"invalid_core_poi_metadata",
				cell_path,
				"",
				"奖励位置必须是包含 x/y 的对象"
			))
			continue
		var cell: Dictionary = cell_value as Dictionary
		for key_value: Variant in cell.keys():
			var key: String = str(key_value)
			if key == "x" or key == "y":
				continue
			issues.append(_config_issue(
				"invalid_core_poi_metadata",
				"%s.%s" % [cell_path, key],
				"",
				"奖励位置只允许 x/y"
			))
		var x_value: Variant = cell.get("x", null)
		var y_value: Variant = cell.get("y", null)
		if not _is_integer_number(x_value):
			issues.append(_config_issue(
				"invalid_core_poi_metadata",
				"%s.x" % cell_path,
				"",
				"奖励位置 x 必须是整数"
			))
		if not _is_integer_number(y_value):
			issues.append(_config_issue(
				"invalid_core_poi_metadata",
				"%s.y" % cell_path,
				"",
				"奖励位置 y 必须是整数"
			))
		normalized.append({
			"x": int(x_value) if _is_integer_number(x_value) else 0,
			"y": int(y_value) if _is_integer_number(y_value) else 0,
		})
	return normalized


static func _append_unknown_field_issues(
	source: Dictionary,
	allowed_keys: Array[String],
	base_path: String,
	role: String,
	issues: Array[Dictionary]
) -> void:
	for key_value: Variant in source.keys():
		var key: String = str(key_value)
		if allowed_keys.has(key):
			continue
		issues.append(_config_issue(
			"invalid_region_layout_declaration",
			"%s.%s" % [base_path, key],
			role,
			"区域声明包含不属于该角色的字段"
		))


static func _validate_core_poi_references(
	raw_config: Dictionary,
	normalized_region_layout: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var template_id_counts: Dictionary = {}
	var poi_generation_value: Variant = raw_config.get("poi_generation", null)
	if poi_generation_value is Dictionary:
		var poi_types_value: Variant = (poi_generation_value as Dictionary).get("poi_types", null)
		if poi_types_value is Array:
			for poi_index: int in range((poi_types_value as Array).size()):
				var poi_value: Variant = (poi_types_value as Array)[poi_index]
				if not (poi_value is Dictionary):
					continue
				var poi_id_value: Variant = (poi_value as Dictionary).get("id", null)
				if typeof(poi_id_value) != TYPE_STRING:
					issues.append(_config_issue(
						"invalid_region_layout_declaration",
						"poi_generation.poi_types[%d].id" % poi_index,
						"",
						"四区域配置引用的 POI 模板 id 必须是字符串"
					))
					continue
				var poi_id: String = (poi_id_value as String).strip_edges()
				if poi_id.is_empty():
					continue
				template_id_counts[poi_id] = int(template_id_counts.get(poi_id, 0)) + 1
	for role: String in [
		WdcMapGenerationTypes.REGION_ROLE_HIGH_1,
		WdcMapGenerationTypes.REGION_ROLE_HIGH_2,
		WdcMapGenerationTypes.REGION_ROLE_BOSS,
	]:
		var slot_value: Variant = normalized_region_layout.get(role, null)
		if not (slot_value is Dictionary):
			continue
		var core_poi_value: Variant = (slot_value as Dictionary).get("core_poi", null)
		if not (core_poi_value is Dictionary):
			continue
		var template_id: String = str((core_poi_value as Dictionary).get("template_id", ""))
		if template_id.is_empty():
			continue
		var match_count: int = int(template_id_counts.get(template_id, 0))
		if match_count == 0:
			issues.append(_config_issue(
				"unknown_core_poi_reference",
				"region_layout.%s.core_poi.template_id" % role,
				role,
				"核心 POI 模板引用不存在：%s" % template_id
			))
		elif match_count > 1:
			issues.append(_config_issue(
				"ambiguous_core_poi_reference",
				"region_layout.%s.core_poi.template_id" % role,
				role,
				"核心 POI 模板引用匹配到多个同 id 模板：%s" % template_id
			))


static func _build_normalized_document(
	config: WdcMapGenerationTypes.MapConfig,
	source_document: Dictionary
) -> Dictionary:
	var normalized: Dictionary = source_document.duplicate(true)
	if config.layout_mode == WdcMapGenerationTypes.LAYOUT_MODE_POI_ONLY_V1:
		normalized["schema_version"] = 3
		normalized["region_layout"] = {"mode": config.layout_mode}
		normalized["region_generation"] = config.get_region_generation_snapshot()
		normalized["poi_only"] = config.get_meta("poi_only", {}).duplicate(true)
		normalized.erase("map_layers")
		normalized.erase("boss_generation")
		return normalized
	if config.layout_mode == WdcMapGenerationTypes.LAYOUT_MODE_PVE_FOUR_REGION_V1:
		normalized["schema_version"] = int(source_document.get("schema_version", WdcMapGenerationTypes.REGION_LAYOUT_CONFIG_SCHEMA_VERSION))
		normalized["region_layout"] = _serialize_region_layout(config.region_layout)
		normalized["region_generation"] = config.get_region_generation_snapshot()
		normalized.erase("map_layers")
		normalized.erase("boss_generation")
		var pve_map: Dictionary = (
			(normalized.get("map", {}) as Dictionary).duplicate(true)
			if normalized.get("map", {}) is Dictionary
			else {}
		)
		var player_spawn: Dictionary = (
			(pve_map.get("player_spawn", {}) as Dictionary).duplicate(true)
			if pve_map.get("player_spawn", {}) is Dictionary
			else {}
		)
		player_spawn.erase("layer_id")
		if not player_spawn.is_empty() or pve_map.has("player_spawn"):
			pve_map["player_spawn"] = player_spawn
		var extraction_sites: Dictionary = (
			(pve_map.get("extraction_sites", {}) as Dictionary).duplicate(true)
			if pve_map.get("extraction_sites", {}) is Dictionary
			else {}
		)
		extraction_sites.erase("layer_distribution")
		if not extraction_sites.is_empty() or pve_map.has("extraction_sites"):
			pve_map["extraction_sites"] = extraction_sites
		normalized["map"] = pve_map
		return normalized
	normalized.erase("region_layout")
	normalized.erase("region_generation")
	normalized["map_layers"] = config.map_layers.duplicate(true)
	var legacy_map: Dictionary = (
		(normalized.get("map", {}) as Dictionary).duplicate(true)
		if normalized.get("map", {}) is Dictionary
		else {}
	)
	var legacy_player_spawn: Dictionary = (
		(legacy_map.get("player_spawn", {}) as Dictionary).duplicate(true)
		if legacy_map.get("player_spawn", {}) is Dictionary
		else {}
	)
	legacy_player_spawn["count"] = config.player_spawn_count
	legacy_player_spawn["layer_id"] = config.player_spawn_layer_id
	legacy_map["player_spawn"] = legacy_player_spawn
	var legacy_extraction_sites: Dictionary = (
		(legacy_map.get("extraction_sites", {}) as Dictionary).duplicate(true)
		if legacy_map.get("extraction_sites", {}) is Dictionary
		else {}
	)
	legacy_extraction_sites["count"] = config.extraction_site_count
	legacy_extraction_sites["layer_distribution"] = (
		config.extraction_site_layer_distribution.duplicate(true)
	)
	legacy_map["extraction_sites"] = legacy_extraction_sites
	normalized["map"] = legacy_map
	return normalized


static func _serialize_region_layout(region_layout: Dictionary) -> Dictionary:
	var serialized: Dictionary = {
		"mode": WdcMapGenerationTypes.LAYOUT_MODE_PVE_FOUR_REGION_V1,
	}
	for role: String in WdcMapGenerationTypes.REGION_ROLE_ORDER:
		var slot_value: Variant = region_layout.get(role, null)
		if not (slot_value is Dictionary):
			continue
		var slot: Dictionary = slot_value as Dictionary
		var encoded_slot: Dictionary = {
			"id": str(slot.get("id", "")),
			"display_name": str(slot.get("display_name", "")),
			"content_profile_id": str(slot.get("content_profile_id", "")),
		}
		if role != WdcMapGenerationTypes.REGION_ROLE_REGULAR:
			encoded_slot["layout_profile_id"] = str(slot.get("layout_profile_id", ""))
			encoded_slot["core_poi"] = (
				(slot.get("core_poi", {}) as Dictionary).duplicate(true)
				if slot.get("core_poi", {}) is Dictionary
				else {}
			)
		if role == WdcMapGenerationTypes.REGION_ROLE_BOSS:
			encoded_slot["encounter_profile_id"] = str(
				slot.get("encounter_profile_id", "")
			)
		serialized[role] = encoded_slot
	return serialized


static func _config_issue(
	code: String,
	path: String,
	role: String,
	message: String
) -> Dictionary:
	return WdcMapGenerationTypes.make_generation_issue(code, path, role, message)


static func _strict_config_string(value: Variant) -> Variant:
	if typeof(value) != TYPE_STRING:
		return null
	return (value as String).strip_edges()


static func _resolve_display_name(filename: String, config_dict: Dictionary) -> String:
	var display_name: String = str(config_dict.get("display_name", "")).strip_edges()
	return display_name if not display_name.is_empty() else filename

