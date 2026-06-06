class_name WdcMapGenerationConfigCatalog
extends RefCounted

const CONFIG_DIRECTORY_PATH: String = "res://addons/wdc_map_generation/config/generated_map_configs"
const PARENT_PROJECT_CONFIG_DIRECTORY_PATH: String = (
	"res://map_generation/addons/wdc_map_generation/config/generated_map_configs"
)
const CONFIG_EXTENSION: String = ".json"
const DEFAULT_CONFIG_BASENAME: String = "default_generated_map"

const GENERATED_MAP_TYPES_SCRIPT = preload("../core/generated_map_types.gd")
const WdcMapGenerationTypes = GENERATED_MAP_TYPES_SCRIPT


static func get_config_directory_path() -> String:
	return _resolve_config_directory_path()


static func get_config_extension() -> String:
	return CONFIG_EXTENSION


static func get_default_config_filename() -> String:
	var available_configs: Array[Dictionary] = list_available_configs()
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
	config.map_layers = _normalize_map_layers(config_dict.get("map_layers", []))
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
		normalized.append(layer_dict)
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


static func _resolve_display_name(filename: String, config_dict: Dictionary) -> String:
	var display_name: String = str(config_dict.get("display_name", "")).strip_edges()
	return display_name if not display_name.is_empty() else filename

