extends SceneTree

const CONFIG_CATALOG = preload("../../config/data_generated_map_config_catalog.gd")
const MAP_TYPES = preload("../../core/generated_map_types.gd")
const GENERATOR_SCRIPT = preload("../../core/generated_map_generator.gd")
const REPEAT_COUNT: int = 5

const GOLDEN_CASES: Array[Dictionary] = [
	{
		"filename": "default_generated_map",
		"seed": 12345,
		"expected_sha256": "82cf6568cc02d935c9aa3462ca5bee1a7d045acd47f43be281d1793c02fcd337",
	},
	{
		"filename": "small_map",
		"seed": 54321,
		"expected_sha256": "8db97910db539fc7fe2600b9b930b8b94a5a680e847e5a2417554f2f6042f7cd",
	},
]

var _failures: Array[String] = []


func _init() -> void:
	for case: Dictionary in GOLDEN_CASES:
		_run_case(case)
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("legacy_fixed_seed_golden_smoke: %s" % failure)
		quit(1)
		return
	print("legacy_fixed_seed_golden_smoke: PASS")
	quit(0)


func _run_case(case: Dictionary) -> void:
	var filename: String = str(case.get("filename", ""))
	var case_seed: int = int(case.get("seed", 0))
	var raw_config: Dictionary = CONFIG_CATALOG.load_config_dict_by_filename(filename)
	if raw_config.is_empty():
		_failures.append("无法读取 legacy 配置：%s" % filename)
		return
	var expected_sha256: String = str(case.get("expected_sha256", ""))
	var observed_sha256: String = ""
	for repeat_index: int in range(REPEAT_COUNT):
		var config = MAP_TYPES.MapConfig.new()
		CONFIG_CATALOG.apply_config_dict_to_legacy_map_config(config, raw_config)
		config.seed = case_seed
		var generator = GENERATOR_SCRIPT.new()
		var map_data = generator.generate_full(config)
		if map_data == null:
			_failures.append(
				"legacy 配置生成失败：%s seed=%d repeat=%d"
				% [filename, case_seed, repeat_index + 1]
			)
			return
		var artifact: Dictionary = _build_legacy_artifact(map_data)
		var actual_sha256: String = _hash_variant(artifact)
		print(
			"legacy_fixed_seed_golden_smoke: case=%s seed=%d repeat=%d sha256=%s"
			% [filename, case_seed, repeat_index + 1, actual_sha256]
		)
		if observed_sha256.is_empty():
			observed_sha256 = actual_sha256
		elif actual_sha256 != observed_sha256:
			_failures.append(
				"legacy fixed-seed 同进程结果不一致：%s seed=%d first=%s repeat=%d actual=%s"
				% [filename, case_seed, observed_sha256, repeat_index + 1, actual_sha256]
			)
		if not expected_sha256.is_empty() and actual_sha256 != expected_sha256:
			var component_hashes: Dictionary = {}
			for component_name: Variant in artifact.keys():
				component_hashes[str(component_name)] = _hash_variant(artifact[component_name])
			print(
				"legacy_fixed_seed_golden_smoke: drift_components=%s"
				% JSON.stringify(component_hashes)
			)
			_failures.append(
				"legacy fixed-seed golden 漂移：%s seed=%d repeat=%d expected=%s actual=%s"
				% [filename, case_seed, repeat_index + 1, expected_sha256, actual_sha256]
			)


func _build_legacy_artifact(map_data: Variant) -> Dictionary:
	var tiles: Array = []
	for y: int in range(map_data.height):
		var row: Array = []
		for x: int in range(map_data.width):
			var cell = map_data.get_cell(x, y)
			row.append([
				cell.cell_type,
				cell.poi_type,
				cell.biome_id,
				cell.trace_type,
				cell.is_poi_protected,
				cell.has_mineral,
				cell.special_block_type,
				cell.current_hit_points,
				cell.max_hit_points,
				cell.durability_tile_type,
				cell.durability_override_max_hit_points,
			])
		tiles.append(row)
	return {
		"layout_mode": map_data.layout_mode,
		"width": map_data.width,
		"height": map_data.height,
		"tiles": tiles,
		"poi_centers": map_data.poi_centers.duplicate(true),
		"poi_instances": map_data.poi_instances.duplicate(true),
		"player_spawn_points": map_data.player_spawn_points.duplicate(true),
		"extraction_sites": map_data.extraction_sites.duplicate(true),
		"monster_sites": map_data.monster_sites.duplicate(true),
		"camp_encounters": map_data.camp_encounters.duplicate(true),
		"trap_sites": map_data.trap_sites.duplicate(true),
		"total_floor": map_data.total_floor,
		"large_pois": map_data.large_pois,
		"medium_pois": map_data.medium_pois,
		"small_pois": map_data.small_pois,
	}


func _hash_variant(value: Variant) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(_canonical_text(value).to_utf8_buffer())
	return context.finish().hex_encode()


func _canonical_text(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Vector2i:
		var vector: Vector2i = value as Vector2i
		return "v2i(%d,%d)" % [vector.x, vector.y]
	if value is Vector2:
		var vector: Vector2 = value as Vector2
		return "v2(%s,%s)" % [str(vector.x), str(vector.y)]
	if value is Vector3:
		var vector: Vector3 = value as Vector3
		return "v3(%s,%s,%s)" % [str(vector.x), str(vector.y), str(vector.z)]
	if value is Rect2i:
		var rect: Rect2i = value as Rect2i
		return "rect2i(%d,%d,%d,%d)" % [
			rect.position.x,
			rect.position.y,
			rect.size.x,
			rect.size.y,
		]
	if value is PackedInt32Array or value is PackedInt64Array:
		var packed_parts: PackedStringArray = PackedStringArray()
		for entry: Variant in value:
			packed_parts.append(_canonical_text(entry))
		return "[" + ",".join(packed_parts) + "]"
	if value is PackedVector2Array or value is PackedVector3Array:
		var packed_vector_parts: PackedStringArray = PackedStringArray()
		for entry: Variant in value:
			packed_vector_parts.append(_canonical_text(entry))
		return "[" + ",".join(packed_vector_parts) + "]"
	match typeof(value):
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return "i:%d" % int(value)
		TYPE_FLOAT:
			return "f:%s" % str(float(value))
		TYPE_STRING, TYPE_STRING_NAME:
			return "s:%s" % JSON.stringify(str(value))
		TYPE_ARRAY:
			var array_parts: PackedStringArray = PackedStringArray()
			for entry: Variant in value as Array:
				array_parts.append(_canonical_text(entry))
			return "[" + ",".join(array_parts) + "]"
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value as Dictionary
			var keys: Array = dictionary.keys()
			keys.sort_custom(func(left: Variant, right: Variant) -> bool:
				return _canonical_text(left) < _canonical_text(right)
			)
			var dictionary_parts: PackedStringArray = PackedStringArray()
			for key: Variant in keys:
				dictionary_parts.append(
					"%s:%s" % [_canonical_text(key), _canonical_text(dictionary[key])]
				)
			return "{" + ",".join(dictionary_parts) + "}"
	return "variant:%s" % str(value)
