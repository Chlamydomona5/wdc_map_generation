class_name WdcMapGenerationTypes
extends RefCounted

enum CellType { WALL, FLOOR }

enum PoiType { NONE, LARGE_RUIN, MEDIUM_BIOME, SMALL_ORE }

enum SpecialBlockType { NONE, RARE_MINERAL, TURQUOISE, AMETHYST, GOLD, POI_WALL, SPIKE, EXPLOSIVE_ORE, ARROW_SLIT, PRESSURE_PLATE }

enum ServerTileType {
	EMPTY,
	WALL,
	MINERAL_WALL,
	RARE_MINERAL_WALL,
	TURQUOISE_ORE,
	AMETHYST_ORE,
	GOLD_BLOCK,
	POI_WALL,
	SPIKE_TILE,
	EXPLOSIVE_ORE_TILE,
	ARROW_SLIT_TILE,
	PRESSURE_PLATE_TILE
}

const LAYOUT_MODE_LEGACY_RADIAL: String = "legacy_radial"
const LAYOUT_MODE_PVE_FOUR_REGION_V1: String = "pve_four_region_v1"
const REGION_LAYOUT_CONFIG_SCHEMA_VERSION: int = 2
const REGION_PLAN_SCHEMA_VERSION: int = 1
const REGION_ROLE_REGULAR: String = "regular"
const REGION_ROLE_HIGH_1: String = "high_1"
const REGION_ROLE_HIGH_2: String = "high_2"
const REGION_ROLE_BOSS: String = "boss"
const REGION_ROLE_ORDER: Array[String] = [
	REGION_ROLE_REGULAR,
	REGION_ROLE_HIGH_1,
	REGION_ROLE_HIGH_2,
	REGION_ROLE_BOSS,
]
const REGION_DIFFICULTY_RANK_BY_ROLE: Dictionary = {
	REGION_ROLE_REGULAR: 0,
	REGION_ROLE_HIGH_1: 1,
	REGION_ROLE_HIGH_2: 2,
	REGION_ROLE_BOSS: 3,
}


class GenerationIssue:
	extends RefCounted

	var code: String = ""
	var path: String = ""
	var role: String = ""
	var message: String = ""

	func _init(
		issue_code: String = "",
		issue_path: String = "",
		issue_role: String = "",
		issue_message: String = ""
	) -> void:
		code = issue_code
		path = issue_path
		role = issue_role
		message = issue_message

	func to_dict() -> Dictionary:
		return {
			"code": code,
			"path": path,
			"role": role,
			"message": message,
		}

	func duplicate_issue() -> GenerationIssue:
		return GenerationIssue.new(code, path, role, message)


static func make_generation_issue(
	code: String,
	path: String = "",
	role: String = "",
	message: String = ""
) -> Dictionary:
	return GenerationIssue.new(code, path, role, message).to_dict()


static func get_region_difficulty_rank(role: String) -> int:
	return int(REGION_DIFFICULTY_RANK_BY_ROLE.get(role, -1))


static func is_supported_layout_mode(mode: String) -> bool:
	return mode == LAYOUT_MODE_LEGACY_RADIAL or mode == LAYOUT_MODE_PVE_FOUR_REGION_V1


class CellData:
	extends RefCounted

	var x: int = 0
	var y: int = 0
	var cell_type: int = CellType.WALL
	var poi_type: int = PoiType.NONE
	var biome_id: int = -1
	var trace_type: int = PoiType.NONE
	var is_poi_protected: bool = false
	var has_mineral: bool = false
	var special_block_type: int = SpecialBlockType.NONE
	var current_hit_points: int = 0
	var max_hit_points: int = 0
	var durability_tile_type: int = -1
	var durability_override_max_hit_points: int = 0

	func clone() -> CellData:
		var copied: CellData = CellData.new()
		copied.x = x
		copied.y = y
		copied.cell_type = cell_type
		copied.poi_type = poi_type
		copied.biome_id = biome_id
		copied.trace_type = trace_type
		copied.is_poi_protected = is_poi_protected
		copied.has_mineral = has_mineral
		copied.special_block_type = special_block_type
		copied.current_hit_points = current_hit_points
		copied.max_hit_points = max_hit_points
		copied.durability_tile_type = durability_tile_type
		copied.durability_override_max_hit_points = durability_override_max_hit_points
		return copied


class MapConfig:
	extends RefCounted

	var layout_mode: String = LAYOUT_MODE_LEGACY_RADIAL
	var region_layout: Dictionary = {}
	var validation_issues: Array[Dictionary] = []
	var width: int = 64
	var height: int = 64
	var seed: int = 0
	var fill_percent: float = 0.60
	var smooth_iterations: int = 4
	var large_poi_count: int = 3
	var large_poi_min_distance: float = 15.0
	var large_poi_radius: int = 5
	var large_poi_irregularity: float = 0.8
	var large_poi_special_block_count: int = 1
	var medium_poi_count: int = 12
	var medium_poi_min_distance: float = 10.0
	var medium_poi_radius: int = 3
	var medium_poi_irregularity: float = 0.5
	var medium_poi_special_block_count: int = 1
	var small_poi_count: int = 50
	var small_poi_min_distance: float = 2.0
	var small_poi_radius: int = 0
	var small_poi_irregularity: float = 0.0
	var small_poi_special_block_count: int = 1
	var corridor_count: int = 8
	var corridor_width: int = 3
	var corridor_length: float = 0.6
	var corridor_wobble: float = 0.2
	var trace_large_radius: float = 15.0
	var trace_large_density: float = 0.95
	var trace_large_rays: float = 7.0
	var trace_large_twist: float = 1.2
	var trace_medium_radius: float = 8.0
	var trace_medium_density: float = 0.70
	var trace_medium_rays: float = 5.0
	var trace_medium_twist: float = 0.9
	var trace_small_radius: float = 4.0
	var trace_small_density: float = 0.50
	var trace_small_rays: float = 3.0
	var trace_small_twist: float = 1.4
	var mineral_base_chance: float = 0.02
	var mineral_exposed_chance: float = 0.08
	var mineral_min_distance_between_cluster_seeds_cells: int = 0
	var mineral_allow_clusters_inside_poi_rooms: bool = false
	var mineral_allow_clusters_under_poi_corridors: bool = false
	var mineral_cluster_types: Array[Dictionary] = []
	var mineral_cluster_overrides: Array[Dictionary] = []
	var poi_templates: Array[Dictionary] = []
	var map_layers: Array[Dictionary] = []
	var player_spawn_count: int = 1
	var player_spawn_layer_id: String = "outer"
	var player_spawn_edge_margin_cells: int = 6
	var player_spawn_min_distance_between_spawns_cells: float = 10.0
	var player_spawn_clearance_radius_cells: int = 2
	var player_spawn_min_clearance_ratio: float = 0.65
	var extraction_site_count: int = 1
	var extraction_site_layer_distribution: Array[Dictionary] = [
		{"layer_id": "inner", "ratio": 1.0},
	]
	var extraction_site_min_distance_from_player_spawns_cells: float = 12.0
	var extraction_site_min_distance_between_sites_cells: float = 10.0
	var extraction_site_edge_margin_cells: int = 6
	var extraction_site_clearance_radius_cells: int = 2
	var extraction_site_min_clearance_ratio: float = 0.65
	var traps_high_density: bool = false
	var traps_spike_max_count: int = -1
	var traps_spike_min_spacing: int = -1
	var traps_explosive_chain_count: int = -1
	var traps_explosive_chain_spacing: int = -1
	var traps_arrow_slit_max_count: int = -1
	var traps_arrow_slit_min_spacing: int = -1
	var traps_mimic_ore_max_count: int = -1
	var traps_mimic_ore_min_spacing: int = -1
	var traps_pressure_plate_max_count: int = -1
	var traps_pressure_plate_min_spacing: int = -1

	func normalize() -> void:
		layout_mode = layout_mode.strip_edges()
		width = maxi(8, width)
		height = maxi(8, height)
		fill_percent = clampf(fill_percent, 0.0, 1.0)
		smooth_iterations = maxi(0, smooth_iterations)
		large_poi_count = maxi(0, large_poi_count)
		large_poi_min_distance = maxf(0.0, large_poi_min_distance)
		large_poi_radius = maxi(0, large_poi_radius)
		large_poi_irregularity = clampf(large_poi_irregularity, 0.0, 1.0)
		large_poi_special_block_count = maxi(0, large_poi_special_block_count)
		medium_poi_count = maxi(0, medium_poi_count)
		medium_poi_min_distance = maxf(0.0, medium_poi_min_distance)
		medium_poi_radius = maxi(0, medium_poi_radius)
		medium_poi_irregularity = clampf(medium_poi_irregularity, 0.0, 1.0)
		medium_poi_special_block_count = maxi(0, medium_poi_special_block_count)
		small_poi_count = maxi(0, small_poi_count)
		small_poi_min_distance = maxf(0.0, small_poi_min_distance)
		small_poi_radius = maxi(0, small_poi_radius)
		small_poi_irregularity = clampf(small_poi_irregularity, 0.0, 1.0)
		small_poi_special_block_count = maxi(0, small_poi_special_block_count)
		corridor_count = maxi(0, corridor_count)
		corridor_width = maxi(1, corridor_width)
		corridor_length = clampf(corridor_length, 0.0, 1.5)
		corridor_wobble = clampf(corridor_wobble, 0.0, 1.0)
		trace_large_radius = maxf(0.0, trace_large_radius)
		trace_large_density = clampf(trace_large_density, 0.0, 1.0)
		trace_large_rays = maxf(0.1, trace_large_rays)
		trace_large_twist = maxf(0.0, trace_large_twist)
		trace_medium_radius = maxf(0.0, trace_medium_radius)
		trace_medium_density = clampf(trace_medium_density, 0.0, 1.0)
		trace_medium_rays = maxf(0.1, trace_medium_rays)
		trace_medium_twist = maxf(0.0, trace_medium_twist)
		trace_small_radius = maxf(0.0, trace_small_radius)
		trace_small_density = clampf(trace_small_density, 0.0, 1.0)
		trace_small_rays = maxf(0.1, trace_small_rays)
		trace_small_twist = maxf(0.0, trace_small_twist)
		mineral_base_chance = clampf(mineral_base_chance, 0.0, 1.0)
		mineral_exposed_chance = clampf(mineral_exposed_chance, 0.0, 1.0)
		mineral_min_distance_between_cluster_seeds_cells = maxi(
			0,
			mineral_min_distance_between_cluster_seeds_cells
		)
		if layout_mode == LAYOUT_MODE_LEGACY_RADIAL:
			map_layers = _normalize_map_layers(map_layers, width, height)
		else:
			map_layers.clear()
		player_spawn_count = maxi(player_spawn_count, 0)
		player_spawn_layer_id = player_spawn_layer_id.strip_edges()
		if layout_mode == LAYOUT_MODE_LEGACY_RADIAL and player_spawn_layer_id.is_empty():
			player_spawn_layer_id = "outer"
		elif layout_mode != LAYOUT_MODE_LEGACY_RADIAL:
			player_spawn_layer_id = ""
		player_spawn_edge_margin_cells = maxi(player_spawn_edge_margin_cells, 0)
		player_spawn_min_distance_between_spawns_cells = maxf(
			player_spawn_min_distance_between_spawns_cells,
			0.0
		)
		player_spawn_clearance_radius_cells = maxi(player_spawn_clearance_radius_cells, 0)
		player_spawn_min_clearance_ratio = clampf(player_spawn_min_clearance_ratio, 0.0, 1.0)
		extraction_site_count = maxi(extraction_site_count, 0)
		if layout_mode == LAYOUT_MODE_LEGACY_RADIAL:
			extraction_site_layer_distribution = _normalize_site_layer_distribution(
				extraction_site_layer_distribution
			)
		else:
			extraction_site_layer_distribution.clear()
		extraction_site_min_distance_from_player_spawns_cells = maxf(
			extraction_site_min_distance_from_player_spawns_cells,
			0.0
		)
		extraction_site_min_distance_between_sites_cells = maxf(
			extraction_site_min_distance_between_sites_cells,
			0.0
		)
		extraction_site_edge_margin_cells = maxi(extraction_site_edge_margin_cells, 0)
		extraction_site_clearance_radius_cells = maxi(extraction_site_clearance_radius_cells, 0)
		extraction_site_min_clearance_ratio = clampf(
			extraction_site_min_clearance_ratio,
			0.0,
			1.0
		)
		region_layout = region_layout.duplicate(true)
		validation_issues = validation_issues.duplicate(true)

	func get_validation_issues() -> Array[Dictionary]:
		return validation_issues.duplicate(true)

	func set_validation_issues(issues: Array[Dictionary]) -> void:
		validation_issues = issues.duplicate(true)

	func _normalize_map_layers(
		layer_values: Array[Dictionary],
		map_width: int,
		map_height: int
	) -> Array[Dictionary]:
		var max_radius: float = sqrt(
			pow(float(map_width) * 0.5, 2.0) + pow(float(map_height) * 0.5, 2.0)
		)
		var defaults: Array[Dictionary] = [
			{
				"id": "inner",
				"max_radius_ratio": 0.34,
				"stone_max_hit_points": 4,
				"mineral_budget_weight": 2.0,
				"poi_budget_weight": 2.0,
				"trap_budget_weight": 2.0,
				"monster_budget_weight": 2.0,
				"room_content_danger_multiplier": 1.5,
				"boundary_noise_amplitude_cells": 0.0,
				"boundary_noise_scale_cells": 16.0,
				"boundary_noise_octaves": 1,
				"boundary_noise_persistence": 0.5,
				"boundary_noise_seed_offset": 0,
			},
			{
				"id": "middle",
				"max_radius_ratio": 0.67,
				"stone_max_hit_points": 2,
				"mineral_budget_weight": 1.25,
				"poi_budget_weight": 1.25,
				"trap_budget_weight": 1.25,
				"monster_budget_weight": 1.25,
				"room_content_danger_multiplier": 1.15,
				"boundary_noise_amplitude_cells": 0.0,
				"boundary_noise_scale_cells": 16.0,
				"boundary_noise_octaves": 1,
				"boundary_noise_persistence": 0.5,
				"boundary_noise_seed_offset": 0,
			},
			{
				"id": "outer",
				"max_radius_ratio": 1.01,
				"stone_max_hit_points": 1,
				"mineral_budget_weight": 0.75,
				"poi_budget_weight": 0.75,
				"trap_budget_weight": 0.75,
				"monster_budget_weight": 0.75,
				"room_content_danger_multiplier": 0.85,
				"boundary_noise_amplitude_cells": 0.0,
				"boundary_noise_scale_cells": 16.0,
				"boundary_noise_octaves": 1,
				"boundary_noise_persistence": 0.5,
				"boundary_noise_seed_offset": 0,
			},
		]
		var by_id: Dictionary = {}
		for layer_value: Dictionary in layer_values:
			var layer_id: String = str(layer_value.get("id", "")).strip_edges()
			if layer_id.is_empty():
				continue
			by_id[layer_id] = layer_value
		var normalized: Array[Dictionary] = []
		for default_layer: Dictionary in defaults:
			var merged: Dictionary = default_layer.duplicate(true)
			var layer_id: String = str(merged.get("id", ""))
			if by_id.has(layer_id):
				merged.merge((by_id[layer_id] as Dictionary).duplicate(true), true)
			var max_radius_cells: float = float(merged.get("max_radius_cells", -1.0))
			if max_radius_cells <= 0.0:
				max_radius_cells = float(merged.get("max_radius_ratio", 1.0)) * max_radius
			merged["max_radius_cells"] = maxf(max_radius_cells, 0.0)
			merged["stone_max_hit_points"] = maxi(int(merged.get("stone_max_hit_points", 1)), 1)
			merged["mineral_budget_weight"] = maxf(float(merged.get("mineral_budget_weight", 1.0)), 0.0)
			merged["poi_budget_weight"] = maxf(float(merged.get("poi_budget_weight", 1.0)), 0.0)
			merged["trap_budget_weight"] = maxf(float(merged.get("trap_budget_weight", 1.0)), 0.0)
			merged["monster_budget_weight"] = maxf(float(merged.get("monster_budget_weight", 1.0)), 0.0)
			merged["room_content_danger_multiplier"] = maxf(
				float(merged.get("room_content_danger_multiplier", 1.0)),
				0.0
			)
			merged["boundary_noise_amplitude_cells"] = maxf(
				float(merged.get("boundary_noise_amplitude_cells", 0.0)),
				0.0
			)
			merged["boundary_noise_scale_cells"] = maxf(
				float(merged.get("boundary_noise_scale_cells", 16.0)),
				1.0
			)
			merged["boundary_noise_octaves"] = clampi(
				int(merged.get("boundary_noise_octaves", 1)),
				1,
				6
			)
			merged["boundary_noise_persistence"] = clampf(
				float(merged.get("boundary_noise_persistence", 0.5)),
				0.0,
				1.0
			)
			merged["boundary_noise_seed_offset"] = int(
				merged.get("boundary_noise_seed_offset", 0)
			)
			normalized.append(merged)
		normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("max_radius_cells", 0.0)) < float(b.get("max_radius_cells", 0.0))
		)
		return normalized

	func _normalize_site_layer_distribution(
		distribution_values: Array[Dictionary]
	) -> Array[Dictionary]:
		var normalized: Array[Dictionary] = []
		for distribution_value: Dictionary in distribution_values:
			var layer_id: String = str(distribution_value.get("layer_id", "")).strip_edges()
			if layer_id.is_empty():
				layer_id = str(distribution_value.get("id", "")).strip_edges()
			var ratio: float = maxf(float(distribution_value.get("ratio", 0.0)), 0.0)
			if layer_id.is_empty() or ratio <= 0.0:
				continue
			normalized.append({
				"layer_id": layer_id,
				"ratio": ratio,
			})
		if normalized.is_empty():
			normalized = [
				{"layer_id": "inner", "ratio": 0.8},
				{"layer_id": "middle", "ratio": 0.2},
			]
		return normalized


class GeneratedMapConfigParseResult:
	extends RefCounted

	var config: Variant = null
	var normalized_document: Dictionary = {}
	var issues: Array[Dictionary] = []

	func is_success() -> bool:
		return config != null and issues.is_empty()

	func get_issues() -> Array[Dictionary]:
		return issues.duplicate(true)

	func get_normalized_document() -> Dictionary:
		return normalized_document.duplicate(true)


class RegionDescriptorSnapshot:
	extends RefCounted

	var index: int = -1
	var id: String = ""
	var display_name: String = ""
	var role: String = ""
	var difficulty_rank: int = -1
	var content_profile_id: String = ""
	var center_cell: Vector2i = Vector2i(-1, -1)
	var bounds: Rect2i = Rect2i()
	var cell_count: int = 0
	var core_anchor_cell: Vector2i = Vector2i(-1, -1)
	var core_poi_template_id: String = ""
	var core_poi_instance_id: String = ""

	func to_authority_dict() -> Dictionary:
		var encoded: Dictionary = {
			"index": index,
			"id": id,
			"display_name": display_name,
			"role": role,
			"difficulty_rank": difficulty_rank,
			"content_profile_id": content_profile_id,
			"center_cell": {"x": center_cell.x, "y": center_cell.y},
			"bounds": {
				"x": bounds.position.x,
				"y": bounds.position.y,
				"width": bounds.size.x,
				"height": bounds.size.y,
			},
			"cell_count": cell_count,
		}
		if role != REGION_ROLE_REGULAR:
			encoded["core_anchor_cell"] = {
				"x": core_anchor_cell.x,
				"y": core_anchor_cell.y,
			}
			encoded["core_poi_template_id"] = core_poi_template_id
			encoded["core_poi_instance_id"] = core_poi_instance_id
		return encoded

	func to_view_dict() -> Dictionary:
		return {
			"index": index,
			"id": id,
			"display_name": display_name,
			"role": role,
			"difficulty_rank": difficulty_rank,
		}


class RegionPlanBuildResult:
	extends RefCounted

	var plan: Variant = null
	var issues: Array[Dictionary] = []

	func is_success() -> bool:
		return plan != null and issues.is_empty()

	func get_issues() -> Array[Dictionary]:
		return issues.duplicate(true)


class RegionPlan:
	extends RefCounted

	var _schema_version: int = REGION_PLAN_SCHEMA_VERSION
	var _map_size: Vector2i = Vector2i.ZERO
	var _regions: Array[Dictionary] = []
	var _region_index_by_cell: PackedInt32Array = PackedInt32Array()

	static func create_structurally_validated(
		schema_version_value: int,
		map_size_value: Vector2i,
		raw_regions_value: Variant,
		region_index_by_cell_value: Variant
	) -> RegionPlanBuildResult:
		var result: RegionPlanBuildResult = RegionPlanBuildResult.new()
		if schema_version_value != REGION_PLAN_SCHEMA_VERSION:
			result.issues.append(_issue("schema_version", "", "区域产物 schema version 不受支持"))
		if map_size_value.x <= 0 or map_size_value.y <= 0:
			result.issues.append(_issue("map_size", "", "区域产物地图尺寸无效"))
		if not (raw_regions_value is Array):
			result.issues.append(_issue("regions", "", "区域 descriptor 必须是数组"))
			return result
		var raw_regions: Array = raw_regions_value as Array
		if raw_regions.size() != REGION_ROLE_ORDER.size():
			result.issues.append(_issue("regions", "", "区域 descriptor 必须恰好包含四项"))
		var normalized_by_index: Dictionary = {}
		var seen_roles: Dictionary = {}
		var seen_ids: Dictionary = {}
		var seen_core_instance_ids: Dictionary = {}
		for raw_region_value: Variant in raw_regions:
			if not (raw_region_value is Dictionary):
				result.issues.append(_issue("regions", "", "区域 descriptor 项必须是对象"))
				continue
			var raw_region: Dictionary = raw_region_value as Dictionary
			var role_value: Variant = _string_from_variant(raw_region.get("role", null))
			var role: String = role_value as String if role_value is String else ""
			if role_value == null:
				result.issues.append(_issue("regions.role", "", "区域角色必须是字符串"))
				continue
			var index_value: Variant = _integer_from_variant(raw_region.get("index", null))
			var index: int = index_value as int if index_value is int else -1
			if not REGION_ROLE_ORDER.has(role):
				result.issues.append(_issue("regions.role", role, "区域角色无效"))
				continue
			if seen_roles.has(role):
				result.issues.append(_issue("regions.role", role, "区域角色重复"))
				continue
			seen_roles[role] = true
			var expected_index: int = REGION_ROLE_ORDER.find(role)
			var expected_rank: int = int(REGION_DIFFICULTY_RANK_BY_ROLE.get(role, -1))
			if index_value == null:
				result.issues.append(_issue("regions.index", role, "区域 index 必须是整数"))
			elif index != expected_index:
				result.issues.append(_issue("regions.index", role, "区域 index 与固定角色不匹配"))
			var rank_value: Variant = _integer_from_variant(
				raw_region.get("difficulty_rank", null)
			)
			if rank_value == null:
				result.issues.append(_issue("regions.difficulty_rank", role, "区域难度 rank 必须是整数"))
			elif int(rank_value) != expected_rank:
				result.issues.append(_issue("regions.difficulty_rank", role, "区域难度 rank 与固定角色不匹配"))
			var region_id_value: Variant = _string_from_variant(raw_region.get("id", null))
			var region_id: String = region_id_value as String if region_id_value is String else ""
			if region_id_value == null:
				result.issues.append(_issue("regions.id", role, "区域 id 必须是字符串"))
			elif region_id.is_empty():
				result.issues.append(_issue("regions.id", role, "区域 id 不能为空"))
			elif seen_ids.has(region_id):
				result.issues.append(_issue("regions.id", role, "区域 id 重复"))
			else:
				seen_ids[region_id] = true
			var display_name_value: Variant = _string_from_variant(
				raw_region.get("display_name", null)
			)
			var display_name: String = (
				display_name_value as String if display_name_value is String else ""
			)
			if display_name_value == null:
				result.issues.append(_issue("regions.display_name", role, "区域展示名必须是字符串"))
			elif display_name.is_empty():
				result.issues.append(_issue("regions.display_name", role, "区域展示名不能为空"))
			var content_profile_value: Variant = _string_from_variant(
				raw_region.get("content_profile_id", null)
			)
			var content_profile_id: String = (
				content_profile_value as String if content_profile_value is String else ""
			)
			if content_profile_value == null:
				result.issues.append(_issue("regions.content_profile_id", role, "内容 profile 引用必须是字符串"))
			elif content_profile_id.is_empty():
				result.issues.append(_issue("regions.content_profile_id", role, "内容 profile 引用不能为空"))
			var center_cell_value: Variant = _cell_from_variant(raw_region.get("center_cell", null))
			var center_cell: Vector2i = Vector2i(-1, -1)
			if center_cell_value is Vector2i:
				center_cell = center_cell_value as Vector2i
			else:
				result.issues.append(_issue("regions.center_cell", role, "区域中心格格式无效"))
			var normalized_region: Dictionary = {
				"index": index,
				"id": region_id,
				"display_name": display_name,
				"role": role,
				"difficulty_rank": expected_rank,
				"content_profile_id": content_profile_id,
				"center_cell": center_cell,
			}
			if role == REGION_ROLE_REGULAR:
				for forbidden_key: String in [
					"core_anchor_cell",
					"core_poi_template_id",
					"core_poi_instance_id",
				]:
					if raw_region.has(forbidden_key):
						result.issues.append(_issue("regions.%s" % forbidden_key, role, "常规区域不得携带核心 POI 字段"))
			else:
				var core_anchor_value: Variant = _cell_from_variant(
					raw_region.get("core_anchor_cell", null)
				)
				var core_anchor_cell: Vector2i = Vector2i(-1, -1)
				if core_anchor_value is Vector2i:
					core_anchor_cell = core_anchor_value as Vector2i
				else:
					result.issues.append(_issue("regions.core_anchor_cell", role, "核心 POI anchor 格格式无效"))
				var core_template_value: Variant = _string_from_variant(
					raw_region.get("core_poi_template_id", null)
				)
				var core_template_id: String = (
					core_template_value as String if core_template_value is String else ""
				)
				var core_instance_value: Variant = _string_from_variant(
					raw_region.get("core_poi_instance_id", null)
				)
				var core_instance_id: String = (
					core_instance_value as String if core_instance_value is String else ""
				)
				if core_template_value == null:
					result.issues.append(_issue("regions.core_poi_template_id", role, "核心 POI 模板 identity 必须是字符串"))
				elif core_template_id.is_empty():
					result.issues.append(_issue("regions.core_poi_template_id", role, "核心 POI 模板 identity 不能为空"))
				if core_instance_value == null:
					result.issues.append(_issue("regions.core_poi_instance_id", role, "核心 POI instance identity 必须是字符串"))
				elif core_instance_id.is_empty():
					result.issues.append(_issue("regions.core_poi_instance_id", role, "核心 POI instance identity 不能为空"))
				elif seen_core_instance_ids.has(core_instance_id):
					result.issues.append(_issue("regions.core_poi_instance_id", role, "核心 POI instance identity 重复"))
				else:
					seen_core_instance_ids[core_instance_id] = true
				normalized_region["core_anchor_cell"] = core_anchor_cell
				normalized_region["core_poi_template_id"] = core_template_id
				normalized_region["core_poi_instance_id"] = core_instance_id
			if normalized_by_index.has(index):
				result.issues.append(_issue("regions.index", role, "区域 index 重复"))
			else:
				normalized_by_index[index] = normalized_region
		var membership_result: Dictionary = _membership_from_variant(region_index_by_cell_value)
		if not bool(membership_result.get("valid", false)):
			result.issues.append(_issue("region_index_by_cell", "", "区域 membership 必须是整数数组"))
			return result
		var membership: PackedInt32Array = membership_result.get("values", PackedInt32Array())
		var expected_cell_count: int = map_size_value.x * map_size_value.y
		if membership.size() != expected_cell_count:
			result.issues.append(_issue("region_index_by_cell", "", "区域 membership 长度与地图面积不一致"))
		var counts: Array[int] = [0, 0, 0, 0]
		var min_cells: Array[Vector2i] = [
			Vector2i(map_size_value.x, map_size_value.y),
			Vector2i(map_size_value.x, map_size_value.y),
			Vector2i(map_size_value.x, map_size_value.y),
			Vector2i(map_size_value.x, map_size_value.y),
		]
		var max_cells: Array[Vector2i] = [
			Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(-1, -1)
		]
		for cell_index: int in range(membership.size()):
			var region_index: int = int(membership[cell_index])
			if region_index < 0 or region_index >= REGION_ROLE_ORDER.size():
				result.issues.append(_issue("region_index_by_cell[%d]" % cell_index, "", "区域 membership index 越界"))
				continue
			counts[region_index] += 1
			if map_size_value.x > 0:
				var cell: Vector2i = Vector2i(cell_index % map_size_value.x, cell_index / map_size_value.x)
				min_cells[region_index] = Vector2i(
					mini(min_cells[region_index].x, cell.x),
					mini(min_cells[region_index].y, cell.y)
				)
				max_cells[region_index] = Vector2i(
					maxi(max_cells[region_index].x, cell.x),
					maxi(max_cells[region_index].y, cell.y)
				)
		for expected_index: int in range(REGION_ROLE_ORDER.size()):
			var expected_role: String = REGION_ROLE_ORDER[expected_index]
			if not normalized_by_index.has(expected_index):
				result.issues.append(_issue("regions", expected_role, "缺少固定区域 descriptor"))
				continue
			if counts[expected_index] <= 0:
				result.issues.append(_issue("region_index_by_cell", expected_role, "区域 membership 不能为空"))
				continue
			var region: Dictionary = normalized_by_index[expected_index] as Dictionary
			var center_cell: Vector2i = region.get("center_cell", Vector2i(-1, -1))
			if not _cell_belongs_to_index(center_cell, map_size_value, membership, expected_index):
				result.issues.append(_issue("regions.center_cell", expected_role, "区域中心格不属于对应区域"))
			if expected_role != REGION_ROLE_REGULAR:
				var core_anchor_cell: Vector2i = region.get("core_anchor_cell", Vector2i(-1, -1))
				if not _cell_belongs_to_index(core_anchor_cell, map_size_value, membership, expected_index):
					result.issues.append(_issue("regions.core_anchor_cell", expected_role, "核心 POI anchor 不属于对应区域"))
			region["cell_count"] = counts[expected_index]
			region["bounds"] = Rect2i(
				min_cells[expected_index],
				max_cells[expected_index] - min_cells[expected_index] + Vector2i.ONE
			)
		if not result.issues.is_empty():
			return result
		var plan: RegionPlan = RegionPlan.new()
		plan._schema_version = schema_version_value
		plan._map_size = map_size_value
		for index: int in range(REGION_ROLE_ORDER.size()):
			plan._regions.append((normalized_by_index[index] as Dictionary).duplicate(true))
		plan._region_index_by_cell = membership.duplicate()
		result.plan = plan
		return result

	func get_schema_version() -> int:
		return _schema_version

	func get_map_size() -> Vector2i:
		return _map_size

	func get_region_index_by_cell_copy() -> PackedInt32Array:
		return _region_index_by_cell.duplicate()

	func get_region_snapshots() -> Array[RegionDescriptorSnapshot]:
		var snapshots: Array[RegionDescriptorSnapshot] = []
		for region: Dictionary in _regions:
			snapshots.append(_snapshot_from_dictionary(region))
		return snapshots

	func try_get_by_role(role: String) -> RegionDescriptorSnapshot:
		for region: Dictionary in _regions:
			if str(region.get("role", "")) == role:
				return _snapshot_from_dictionary(region)
		return null

	func try_get_at(cell: Vector2i) -> RegionDescriptorSnapshot:
		if cell.x < 0 or cell.y < 0 or cell.x >= _map_size.x or cell.y >= _map_size.y:
			return null
		var flat_index: int = cell.y * _map_size.x + cell.x
		if flat_index < 0 or flat_index >= _region_index_by_cell.size():
			return null
		var region_index: int = int(_region_index_by_cell[flat_index])
		if region_index < 0 or region_index >= _regions.size():
			return null
		return _snapshot_from_dictionary(_regions[region_index])

	func _to_authority_dict() -> Dictionary:
		var encoded_regions: Array[Dictionary] = []
		for region: Dictionary in _regions:
			encoded_regions.append(_snapshot_from_dictionary(region).to_authority_dict())
		return {
			"schema_version": _schema_version,
			"map_size": {"x": _map_size.x, "y": _map_size.y},
			"regions": encoded_regions,
			"region_index_by_cell": Array(_region_index_by_cell),
		}

	static func _snapshot_from_dictionary(source: Dictionary) -> RegionDescriptorSnapshot:
		var snapshot: RegionDescriptorSnapshot = RegionDescriptorSnapshot.new()
		snapshot.index = int(source.get("index", -1))
		snapshot.id = str(source.get("id", ""))
		snapshot.display_name = str(source.get("display_name", ""))
		snapshot.role = str(source.get("role", ""))
		snapshot.difficulty_rank = int(source.get("difficulty_rank", -1))
		snapshot.content_profile_id = str(source.get("content_profile_id", ""))
		snapshot.center_cell = source.get("center_cell", Vector2i(-1, -1))
		snapshot.bounds = source.get("bounds", Rect2i())
		snapshot.cell_count = int(source.get("cell_count", 0))
		snapshot.core_anchor_cell = source.get("core_anchor_cell", Vector2i(-1, -1))
		snapshot.core_poi_template_id = str(source.get("core_poi_template_id", ""))
		snapshot.core_poi_instance_id = str(source.get("core_poi_instance_id", ""))
		return snapshot

	static func _membership_from_variant(value: Variant) -> Dictionary:
		var converted: PackedInt32Array = PackedInt32Array()
		if value is PackedInt32Array:
			return {"valid": true, "values": (value as PackedInt32Array).duplicate()}
		if not (value is Array):
			return {"valid": false, "values": converted}
		for entry: Variant in value as Array:
			if typeof(entry) != TYPE_INT and typeof(entry) != TYPE_FLOAT:
				return {"valid": false, "values": PackedInt32Array()}
			var numeric_value: float = float(entry)
			if numeric_value != floor(numeric_value):
				return {"valid": false, "values": PackedInt32Array()}
			converted.append(int(numeric_value))
		return {"valid": true, "values": converted}

	static func _string_from_variant(value: Variant) -> Variant:
		if typeof(value) != TYPE_STRING:
			return null
		return (value as String).strip_edges()

	static func _integer_from_variant(value: Variant) -> Variant:
		if typeof(value) == TYPE_INT:
			return int(value)
		if typeof(value) == TYPE_FLOAT:
			var numeric_value: float = float(value)
			if numeric_value == floor(numeric_value):
				return int(numeric_value)
		return null

	static func _cell_from_variant(value: Variant) -> Variant:
		if value is Vector2i:
			return value
		if value is Dictionary:
			var cell_dict: Dictionary = value as Dictionary
			if cell_dict.has("x") and cell_dict.has("y"):
				var x_value: Variant = _integer_from_variant(cell_dict.get("x"))
				var y_value: Variant = _integer_from_variant(cell_dict.get("y"))
				if x_value is int and y_value is int:
					return Vector2i(int(x_value), int(y_value))
		if value is Array and (value as Array).size() == 2:
			var cell_values: Array = value as Array
			var x_value: Variant = _integer_from_variant(cell_values[0])
			var y_value: Variant = _integer_from_variant(cell_values[1])
			if x_value is int and y_value is int:
				return Vector2i(int(x_value), int(y_value))
		return null

	static func _cell_belongs_to_index(
		cell: Vector2i,
		map_size: Vector2i,
		membership: PackedInt32Array,
		expected_index: int
	) -> bool:
		if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
			return false
		var flat_index: int = cell.y * map_size.x + cell.x
		return flat_index >= 0 and flat_index < membership.size() and int(membership[flat_index]) == expected_index

	static func _issue(path: String, role: String, message: String) -> Dictionary:
		return {
			"code": "invalid_region_layout_artifact",
			"path": path,
			"role": role,
			"message": message,
		}


class BossEncounterAnchor:
	extends RefCounted

	var id: String = ""
	var cell: Vector2i = Vector2i(-1, -1)

	func to_dict() -> Dictionary:
		return {"id": id, "cell": {"x": cell.x, "y": cell.y}}


class BossEncounterBuildResult:
	extends RefCounted

	var descriptor: Variant = null
	var issues: Array[Dictionary] = []

	func is_success() -> bool:
		return descriptor != null and issues.is_empty()

	func get_issues() -> Array[Dictionary]:
		return issues.duplicate(true)


class BossEncounterDescriptor:
	extends RefCounted

	var _encounter_id: String = ""
	var _region_id: String = ""
	var _core_poi_instance_id: String = ""
	var _encounter_profile_id: String = ""
	var _anchors: Array[Dictionary] = []

	static func create_structurally_validated(
		region_plan_value: Variant,
		raw_descriptor_value: Variant
	) -> BossEncounterBuildResult:
		var result: BossEncounterBuildResult = BossEncounterBuildResult.new()
		if not (region_plan_value is RegionPlan):
			result.issues.append(_issue("region_plan", "BOSS encounter 缺少有效 RegionPlan"))
			return result
		if not (raw_descriptor_value is Dictionary):
			result.issues.append(_issue("region_boss_encounter", "BOSS encounter descriptor 必须是对象"))
			return result
		var region_plan: RegionPlan = region_plan_value as RegionPlan
		var raw_descriptor: Dictionary = raw_descriptor_value as Dictionary
		if _contains_extraction_field(raw_descriptor):
			result.issues.append(_issue("region_boss_encounter", "BOSS encounter descriptor 不得包含撤离定义"))
		var required_strings: Dictionary = {
			"encounter_id": raw_descriptor.get("encounter_id", null),
			"region_id": raw_descriptor.get("region_id", null),
			"core_poi_instance_id": raw_descriptor.get("core_poi_instance_id", null),
			"encounter_profile_id": raw_descriptor.get("encounter_profile_id", null),
		}
		var normalized_strings: Dictionary = {}
		for field_name: String in required_strings:
			var normalized_value: Variant = RegionPlan._string_from_variant(
				required_strings[field_name]
			)
			var field_path: String = "region_boss_encounter.%s" % field_name
			if normalized_value == null:
				result.issues.append(_issue(field_path, "BOSS encounter 必填 id 必须是字符串"))
				normalized_strings[field_name] = ""
			elif (normalized_value as String).is_empty():
				result.issues.append(_issue(field_path, "BOSS encounter 必填 id 不能为空"))
				normalized_strings[field_name] = ""
			else:
				normalized_strings[field_name] = normalized_value
		var encounter_id: String = str(normalized_strings.get("encounter_id", ""))
		var region_id: String = str(normalized_strings.get("region_id", ""))
		var core_poi_instance_id: String = str(
			normalized_strings.get("core_poi_instance_id", "")
		)
		var encounter_profile_id: String = str(
			normalized_strings.get("encounter_profile_id", "")
		)
		var boss_region: RegionDescriptorSnapshot = region_plan.try_get_by_role(REGION_ROLE_BOSS)
		if boss_region == null:
			result.issues.append(_mismatch_issue("region_boss_encounter.region_id", "RegionPlan 缺少 BOSS descriptor"))
		else:
			if region_id != boss_region.id:
				result.issues.append(_mismatch_issue("region_boss_encounter.region_id", "encounter region id 与 BOSS 区域不一致"))
			if core_poi_instance_id != boss_region.core_poi_instance_id:
				result.issues.append(_mismatch_issue("region_boss_encounter.core_poi_instance_id", "encounter 核心 POI identity 与 BOSS 区域不一致"))
		var anchors_value: Variant = raw_descriptor.get("anchors", null)
		var normalized_anchors: Array[Dictionary] = []
		var seen_anchor_ids: Dictionary = {}
		if not (anchors_value is Array) or (anchors_value as Array).is_empty():
			result.issues.append(_issue("region_boss_encounter.anchors", "BOSS encounter 必须至少包含一个 anchor"))
		else:
			for anchor_index: int in range((anchors_value as Array).size()):
				var anchor_value: Variant = (anchors_value as Array)[anchor_index]
				if not (anchor_value is Dictionary):
					result.issues.append(_issue("region_boss_encounter.anchors[%d]" % anchor_index, "BOSS anchor 必须是对象"))
					continue
				var anchor_dict: Dictionary = anchor_value as Dictionary
				var anchor_id_value: Variant = RegionPlan._string_from_variant(
					anchor_dict.get("id", null)
				)
				var anchor_id: String = (
					anchor_id_value as String if anchor_id_value is String else ""
				)
				if anchor_id_value == null:
					result.issues.append(_issue("region_boss_encounter.anchors[%d].id" % anchor_index, "BOSS anchor id 必须是字符串"))
				elif anchor_id.is_empty():
					result.issues.append(_issue("region_boss_encounter.anchors[%d].id" % anchor_index, "BOSS anchor id 不能为空"))
				elif seen_anchor_ids.has(anchor_id):
					result.issues.append(_issue("region_boss_encounter.anchors[%d].id" % anchor_index, "BOSS anchor id 重复"))
				else:
					seen_anchor_ids[anchor_id] = true
				var anchor_cell_value: Variant = RegionPlan._cell_from_variant(anchor_dict.get("cell", null))
				if not (anchor_cell_value is Vector2i):
					result.issues.append(_issue("region_boss_encounter.anchors[%d].cell" % anchor_index, "BOSS anchor cell 格式无效"))
					continue
				var anchor_cell: Vector2i = anchor_cell_value as Vector2i
				var anchor_region: RegionDescriptorSnapshot = region_plan.try_get_at(anchor_cell)
				if anchor_region == null or anchor_region.role != REGION_ROLE_BOSS:
					result.issues.append(_issue("region_boss_encounter.anchors[%d].cell" % anchor_index, "BOSS anchor 必须位于 BOSS 区域"))
				normalized_anchors.append({"id": anchor_id, "cell": anchor_cell})
		if not result.issues.is_empty():
			return result
		var descriptor: BossEncounterDescriptor = BossEncounterDescriptor.new()
		descriptor._encounter_id = encounter_id
		descriptor._region_id = region_id
		descriptor._core_poi_instance_id = core_poi_instance_id
		descriptor._encounter_profile_id = encounter_profile_id
		descriptor._anchors = normalized_anchors.duplicate(true)
		result.descriptor = descriptor
		return result

	func get_encounter_id() -> String:
		return _encounter_id

	func get_region_id() -> String:
		return _region_id

	func get_core_poi_instance_id() -> String:
		return _core_poi_instance_id

	func get_encounter_profile_id() -> String:
		return _encounter_profile_id

	func get_anchor_snapshots() -> Array[BossEncounterAnchor]:
		var snapshots: Array[BossEncounterAnchor] = []
		for anchor: Dictionary in _anchors:
			var snapshot: BossEncounterAnchor = BossEncounterAnchor.new()
			snapshot.id = str(anchor.get("id", ""))
			snapshot.cell = anchor.get("cell", Vector2i(-1, -1))
			snapshots.append(snapshot)
		return snapshots

	func _to_authority_dict() -> Dictionary:
		var encoded_anchors: Array[Dictionary] = []
		for anchor_snapshot: BossEncounterAnchor in get_anchor_snapshots():
			encoded_anchors.append(anchor_snapshot.to_dict())
		return {
			"encounter_id": _encounter_id,
			"region_id": _region_id,
			"core_poi_instance_id": _core_poi_instance_id,
			"encounter_profile_id": _encounter_profile_id,
			"anchors": encoded_anchors,
		}

	static func _contains_extraction_field(value: Variant) -> bool:
		if value is Dictionary:
			for key_value: Variant in (value as Dictionary).keys():
				if str(key_value).to_lower().contains("extraction"):
					return true
				if _contains_extraction_field((value as Dictionary)[key_value]):
					return true
		elif value is Array:
			for entry: Variant in value as Array:
				if _contains_extraction_field(entry):
					return true
		return false

	static func _issue(path: String, message: String) -> Dictionary:
		return {
			"code": "invalid_boss_encounter_descriptor",
			"path": path,
			"role": REGION_ROLE_BOSS,
			"message": message,
		}

	static func _mismatch_issue(path: String, message: String) -> Dictionary:
		return {
			"code": "boss_encounter_mismatch",
			"path": path,
			"role": REGION_ROLE_BOSS,
			"message": message,
		}


class RegionDescriptorViewSnapshot:
	extends RefCounted

	var index: int = -1
	var id: String = ""
	var display_name: String = ""
	var role: String = ""
	var difficulty_rank: int = -1

	func to_dict() -> Dictionary:
		return {
			"index": index,
			"id": id,
			"display_name": display_name,
			"role": role,
			"difficulty_rank": difficulty_rank,
		}


class RegionPlanViewBuildResult:
	extends RefCounted

	var view: Variant = null
	var issues: Array[Dictionary] = []

	func is_success() -> bool:
		return view != null and issues.is_empty()

	func get_issues() -> Array[Dictionary]:
		return issues.duplicate(true)


class RegionPlanView:
	extends RefCounted

	var _schema_version: int = REGION_PLAN_SCHEMA_VERSION
	var _map_size: Vector2i = Vector2i.ZERO
	var _region_catalog: Array[Dictionary] = []
	var _region_index_by_cell: PackedInt32Array = PackedInt32Array()

	static func create_structurally_validated(
		schema_version_value: int,
		map_size_value: Vector2i,
		raw_catalog_value: Variant,
		region_index_by_cell_value: Variant
	) -> RegionPlanViewBuildResult:
		var result: RegionPlanViewBuildResult = RegionPlanViewBuildResult.new()
		if schema_version_value != REGION_PLAN_SCHEMA_VERSION:
			result.issues.append(_issue("region_plan.schema_version", "区域视图 schema version 不受支持"))
		if map_size_value.x <= 0 or map_size_value.y <= 0:
			result.issues.append(_issue("region_plan.map_size", "区域视图地图尺寸无效"))
		if not (raw_catalog_value is Array):
			result.issues.append(_issue("region_plan.region_catalog", "区域视图 catalog 必须是数组"))
			return result
		var raw_catalog: Array = raw_catalog_value as Array
		if raw_catalog.size() != REGION_ROLE_ORDER.size():
			result.issues.append(_issue("region_plan.region_catalog", "区域视图 catalog 必须恰好包含四项"))
		var normalized_by_index: Dictionary = {}
		var seen_roles: Dictionary = {}
		var seen_ids: Dictionary = {}
		var allowed_keys: Array[String] = ["index", "id", "display_name", "role", "difficulty_rank"]
		for entry_index: int in range(raw_catalog.size()):
			var entry_value: Variant = raw_catalog[entry_index]
			if not (entry_value is Dictionary):
				result.issues.append(_issue("region_plan.region_catalog[%d]" % entry_index, "区域视图 catalog 项必须是对象"))
				continue
			var entry: Dictionary = entry_value as Dictionary
			for key_value: Variant in entry.keys():
				if not allowed_keys.has(str(key_value)):
					result.issues.append(_issue("region_plan.region_catalog[%d].%s" % [entry_index, str(key_value)], "区域视图包含 authority-only 或未知字段"))
			var role_value: Variant = RegionPlan._string_from_variant(entry.get("role", null))
			var role: String = role_value as String if role_value is String else ""
			if role_value == null:
				result.issues.append(_issue("region_plan.region_catalog[%d].role" % entry_index, "区域视图角色必须是字符串"))
				continue
			var index_value: Variant = RegionPlan._integer_from_variant(
				entry.get("index", null)
			)
			var index: int = int(index_value) if index_value is int else -1
			if not REGION_ROLE_ORDER.has(role):
				result.issues.append(_issue("region_plan.region_catalog[%d].role" % entry_index, "区域视图角色无效"))
				continue
			if seen_roles.has(role):
				result.issues.append(_issue("region_plan.region_catalog[%d].role" % entry_index, "区域视图角色重复"))
			else:
				seen_roles[role] = true
			var expected_index: int = REGION_ROLE_ORDER.find(role)
			var rank_value: Variant = RegionPlan._integer_from_variant(
				entry.get("difficulty_rank", null)
			)
			if index_value == null or rank_value == null:
				result.issues.append(_issue("region_plan.region_catalog[%d]" % entry_index, "区域视图 index/rank 必须是整数"))
			elif (
				index != expected_index
				or int(rank_value) != int(REGION_DIFFICULTY_RANK_BY_ROLE.get(role, -1))
			):
				result.issues.append(_issue("region_plan.region_catalog[%d]" % entry_index, "区域视图 index/rank 与固定角色不匹配"))
			var region_id_value: Variant = RegionPlan._string_from_variant(entry.get("id", null))
			var display_name_value: Variant = RegionPlan._string_from_variant(
				entry.get("display_name", null)
			)
			var region_id: String = region_id_value as String if region_id_value is String else ""
			var display_name: String = (
				display_name_value as String if display_name_value is String else ""
			)
			if region_id_value == null or display_name_value == null:
				result.issues.append(_issue("region_plan.region_catalog[%d]" % entry_index, "区域视图 id 与展示名必须是字符串"))
			elif region_id.is_empty() or display_name.is_empty():
				result.issues.append(_issue("region_plan.region_catalog[%d]" % entry_index, "区域视图 id 与展示名不能为空"))
			elif seen_ids.has(region_id):
				result.issues.append(_issue("region_plan.region_catalog[%d].id" % entry_index, "区域视图 id 重复"))
			else:
				seen_ids[region_id] = true
			if index_value != null:
				normalized_by_index[index] = {
					"index": index,
					"id": region_id,
					"display_name": display_name,
					"role": role,
					"difficulty_rank": int(REGION_DIFFICULTY_RANK_BY_ROLE.get(role, -1)),
				}
		var membership_result: Dictionary = RegionPlan._membership_from_variant(region_index_by_cell_value)
		if not bool(membership_result.get("valid", false)):
			result.issues.append(_issue("region_plan.region_index_by_cell", "区域视图 membership 必须是整数数组"))
			return result
		var membership: PackedInt32Array = membership_result.get("values", PackedInt32Array())
		if membership.size() != map_size_value.x * map_size_value.y:
			result.issues.append(_issue("region_plan.region_index_by_cell", "区域视图 membership 长度与地图面积不一致"))
		var membership_counts: Array[int] = [0, 0, 0, 0]
		for cell_index: int in range(membership.size()):
			var region_index: int = int(membership[cell_index])
			if region_index < 0 or region_index >= REGION_ROLE_ORDER.size():
				result.issues.append(_issue("region_plan.region_index_by_cell[%d]" % cell_index, "区域视图 membership index 越界"))
			else:
				membership_counts[region_index] += 1
		for expected_index: int in range(REGION_ROLE_ORDER.size()):
			if not normalized_by_index.has(expected_index):
				result.issues.append(_issue("region_plan.region_catalog", "区域视图缺少固定角色"))
			elif membership_counts[expected_index] <= 0:
				result.issues.append(_issue("region_plan.region_index_by_cell", "区域视图中的固定角色不能没有格子"))
		if not result.issues.is_empty():
			return result
		var view: RegionPlanView = RegionPlanView.new()
		view._schema_version = schema_version_value
		view._map_size = map_size_value
		for index: int in range(REGION_ROLE_ORDER.size()):
			view._region_catalog.append((normalized_by_index[index] as Dictionary).duplicate(true))
		view._region_index_by_cell = membership.duplicate()
		result.view = view
		return result

	func get_schema_version() -> int:
		return _schema_version

	func get_map_size() -> Vector2i:
		return _map_size

	func get_region_index_by_cell_copy() -> PackedInt32Array:
		return _region_index_by_cell.duplicate()

	func try_get_by_role(role: String) -> RegionDescriptorViewSnapshot:
		for entry: Dictionary in _region_catalog:
			if str(entry.get("role", "")) == role:
				return _snapshot_from_dictionary(entry)
		return null

	func try_get_at(cell: Vector2i) -> RegionDescriptorViewSnapshot:
		if cell.x < 0 or cell.y < 0 or cell.x >= _map_size.x or cell.y >= _map_size.y:
			return null
		var flat_index: int = cell.y * _map_size.x + cell.x
		if flat_index < 0 or flat_index >= _region_index_by_cell.size():
			return null
		var region_index: int = int(_region_index_by_cell[flat_index])
		if region_index < 0 or region_index >= _region_catalog.size():
			return null
		return _snapshot_from_dictionary(_region_catalog[region_index])

	func _to_dict() -> Dictionary:
		var catalog: Array[Dictionary] = []
		for entry: Dictionary in _region_catalog:
			catalog.append(_snapshot_from_dictionary(entry).to_dict())
		return {
			"schema_version": _schema_version,
			"map_size": {"x": _map_size.x, "y": _map_size.y},
			"region_catalog": catalog,
			"region_index_by_cell": Array(_region_index_by_cell),
		}

	static func _snapshot_from_dictionary(source: Dictionary) -> RegionDescriptorViewSnapshot:
		var snapshot: RegionDescriptorViewSnapshot = RegionDescriptorViewSnapshot.new()
		snapshot.index = int(source.get("index", -1))
		snapshot.id = str(source.get("id", ""))
		snapshot.display_name = str(source.get("display_name", ""))
		snapshot.role = str(source.get("role", ""))
		snapshot.difficulty_rank = int(source.get("difficulty_rank", -1))
		return snapshot

	static func _issue(path: String, message: String) -> Dictionary:
		return {
			"code": "invalid_region_payload",
			"path": path,
			"role": "",
			"message": message,
		}


class MapDataRegionArtifactsBuildResult:
	extends RefCounted

	var map_data: Variant = null
	var issues: Array[Dictionary] = []

	func is_success() -> bool:
		return map_data != null and issues.is_empty()

	func get_issues() -> Array[Dictionary]:
		return issues.duplicate(true)


class MapData:
	extends RefCounted

	var layout_mode: String = LAYOUT_MODE_LEGACY_RADIAL
	var region_plan: Variant = null
	var region_boss_encounter: Variant = null
	var width: int = 0
	var height: int = 0
	var grid: Array[Array] = []
	var poi_centers: Array[Dictionary] = []
	var poi_instances: Array[Dictionary] = []
	var player_spawn_points: Array[Dictionary] = []
	var extraction_sites: Array[Dictionary] = []
	var monster_sites: Array[Dictionary] = []
	var camp_encounters: Array[Dictionary] = []
	var trap_sites: Array[Dictionary] = []
	var total_floor: int = 0
	var large_pois: int = 0
	var medium_pois: int = 0
	var small_pois: int = 0

	func init_grid(new_width: int, new_height: int) -> void:
		width = new_width
		height = new_height
		grid.clear()
		grid.resize(height)
		for y: int in range(height):
			var row: Array = []
			row.resize(width)
			for x: int in range(width):
				var cell: CellData = CellData.new()
				cell.x = x
				cell.y = y
				row[x] = cell
			grid[y] = row

	func is_in_bounds(x: int, y: int) -> bool:
		return x >= 0 and x < width and y >= 0 and y < height

	func get_cell(x: int, y: int) -> CellData:
		if not is_in_bounds(x, y):
			return null
		return grid[y][x] as CellData

	func deep_clone() -> MapData:
		var copied: MapData = MapData.new()
		copied.layout_mode = layout_mode
		if region_plan is RegionPlan:
			var plan_encoded: Dictionary = (region_plan as RegionPlan)._to_authority_dict()
			var plan_map_size_value: Variant = RegionPlan._cell_from_variant(
				plan_encoded.get("map_size", null)
			)
			var plan_map_size: Vector2i = (
				plan_map_size_value as Vector2i
				if plan_map_size_value is Vector2i
				else Vector2i.ZERO
			)
			var plan_result: RegionPlanBuildResult = RegionPlan.create_structurally_validated(
				int(plan_encoded.get("schema_version", 0)),
				plan_map_size,
				plan_encoded.get("regions", null),
				plan_encoded.get("region_index_by_cell", null)
			)
			if plan_result.is_success():
				copied.region_plan = plan_result.plan
		if copied.region_plan is RegionPlan and region_boss_encounter is BossEncounterDescriptor:
			var encounter_result: BossEncounterBuildResult = (
				BossEncounterDescriptor.create_structurally_validated(
					copied.region_plan,
					(region_boss_encounter as BossEncounterDescriptor)._to_authority_dict()
				)
			)
			if encounter_result.is_success():
				copied.region_boss_encounter = encounter_result.descriptor
		copied.width = width
		copied.height = height
		copied.grid.resize(height)
		for y: int in range(height):
			var src_row: Array = grid[y]
			var dst_row: Array = []
			dst_row.resize(width)
			for x: int in range(width):
				var src_cell: CellData = src_row[x] as CellData
				dst_row[x] = src_cell.clone()
			copied.grid[y] = dst_row
		for center_data: Dictionary in poi_centers:
			copied.poi_centers.append(center_data.duplicate(true))
		for poi_instance: Dictionary in poi_instances:
			copied.poi_instances.append(poi_instance.duplicate(true))
		for spawn_point: Dictionary in player_spawn_points:
			copied.player_spawn_points.append(spawn_point.duplicate(true))
		for extraction_site: Dictionary in extraction_sites:
			copied.extraction_sites.append(extraction_site.duplicate(true))
		for monster_site: Dictionary in monster_sites:
			copied.monster_sites.append(monster_site.duplicate(true))
		for camp_encounter: Dictionary in camp_encounters:
			copied.camp_encounters.append(camp_encounter.duplicate(true))
		for trap_site: Dictionary in trap_sites:
			copied.trap_sites.append(trap_site.duplicate(true))
		copied.total_floor = total_floor
		copied.large_pois = large_pois
		copied.medium_pois = medium_pois
		copied.small_pois = small_pois
		return copied


class MapServerPayload:
	extends RefCounted

	var layout_mode: String = LAYOUT_MODE_LEGACY_RADIAL
	var region_plan: Variant = null
	var is_valid: bool = true
	var issues: Array[Dictionary] = []
	var width: int = 0
	var height: int = 0
	var cell_size_m: float = 1.0
	var resolved_seed: int = 0
	var revision: int = 0
	var tile_matrix: Array[Array] = []
	var player_spawn_points: Array[Dictionary] = []
	var extraction_sites: Array[Dictionary] = []

	func to_dict() -> Dictionary:
		var encoded: Dictionary = {
			"layout_mode": layout_mode,
			"width": width,
			"height": height,
			"cell_size_m": cell_size_m,
			"resolved_seed": resolved_seed,
			"revision": revision,
			"tile_matrix": tile_matrix,
			"player_spawn_points": player_spawn_points,
			"extraction_sites": extraction_sites
		}
		if region_plan is RegionPlanView:
			encoded["region_plan"] = (region_plan as RegionPlanView)._to_dict().duplicate(true)
		return encoded

	func get_issues() -> Array[Dictionary]:
		return issues.duplicate(true)


static func encode_region_plan_authority(plan_value: Variant) -> Dictionary:
	if not (plan_value is RegionPlan):
		return {}
	return (plan_value as RegionPlan)._to_authority_dict().duplicate(true)


static func decode_region_plan_authority(encoded_value: Variant) -> RegionPlanBuildResult:
	if not (encoded_value is Dictionary):
		var invalid_result: RegionPlanBuildResult = RegionPlanBuildResult.new()
		invalid_result.issues.append(make_generation_issue(
			"invalid_region_layout_artifact",
			"region_plan",
			"",
			"RegionPlan authority payload 必须是对象"
		))
		return invalid_result
	var encoded: Dictionary = encoded_value as Dictionary
	var schema_version_value: Variant = RegionPlan._integer_from_variant(
		encoded.get("schema_version", null)
	)
	if schema_version_value == null:
		var invalid_schema_result: RegionPlanBuildResult = RegionPlanBuildResult.new()
		invalid_schema_result.issues.append(make_generation_issue(
			"invalid_region_layout_artifact",
			"region_plan.schema_version",
			"",
			"RegionPlan schema version 必须是整数"
		))
		return invalid_schema_result
	var map_size_value: Variant = RegionPlan._cell_from_variant(encoded.get("map_size", null))
	var map_size: Vector2i = (
		map_size_value as Vector2i
		if map_size_value is Vector2i
		else Vector2i.ZERO
	)
	return RegionPlan.create_structurally_validated(
		int(schema_version_value),
		map_size,
		encoded.get("regions", null),
		encoded.get("region_index_by_cell", null)
	)


static func deep_clone_region_plan(plan_value: Variant) -> Variant:
	if plan_value == null:
		return null
	var decoded: RegionPlanBuildResult = decode_region_plan_authority(
		encode_region_plan_authority(plan_value)
	)
	return decoded.plan if decoded.is_success() else null


static func project_region_plan_view(plan_value: Variant) -> RegionPlanViewBuildResult:
	var result: RegionPlanViewBuildResult = RegionPlanViewBuildResult.new()
	if not (plan_value is RegionPlan):
		result.issues.append(make_generation_issue(
			"invalid_region_payload",
			"region_plan",
			"",
			"无法从空或损坏的 authority RegionPlan 创建客户端视图"
		))
		return result
	var plan: RegionPlan = plan_value as RegionPlan
	var catalog: Array[Dictionary] = []
	for snapshot: RegionDescriptorSnapshot in plan.get_region_snapshots():
		catalog.append(snapshot.to_view_dict())
	return RegionPlanView.create_structurally_validated(
		plan.get_schema_version(),
		plan.get_map_size(),
		catalog,
		plan.get_region_index_by_cell_copy()
	)


static func encode_region_plan_view(view_value: Variant) -> Dictionary:
	if not (view_value is RegionPlanView):
		return {}
	return (view_value as RegionPlanView)._to_dict().duplicate(true)


static func decode_region_plan_view(encoded_value: Variant) -> RegionPlanViewBuildResult:
	if not (encoded_value is Dictionary):
		var invalid_result: RegionPlanViewBuildResult = RegionPlanViewBuildResult.new()
		invalid_result.issues.append(make_generation_issue(
			"invalid_region_payload",
			"region_plan",
			"",
			"RegionPlanView payload 必须是对象"
		))
		return invalid_result
	var encoded: Dictionary = encoded_value as Dictionary
	var unexpected_field_issues: Array[Dictionary] = []
	var allowed_keys: Array[String] = [
		"schema_version",
		"map_size",
		"region_catalog",
		"region_index_by_cell",
	]
	for key_value: Variant in encoded.keys():
		var key: String = str(key_value)
		if allowed_keys.has(key):
			continue
		unexpected_field_issues.append(make_generation_issue(
			"invalid_region_payload",
			"region_plan.%s" % key,
			"",
			"RegionPlanView 包含 authority-only 或未知字段"
		))
	var schema_version_value: Variant = RegionPlan._integer_from_variant(
		encoded.get("schema_version", null)
	)
	if schema_version_value == null:
		var invalid_schema_result: RegionPlanViewBuildResult = RegionPlanViewBuildResult.new()
		invalid_schema_result.issues = unexpected_field_issues.duplicate(true)
		invalid_schema_result.issues.append(make_generation_issue(
			"invalid_region_payload",
			"region_plan.schema_version",
			"",
			"RegionPlanView schema version 必须是整数"
		))
		return invalid_schema_result
	var map_size_value: Variant = RegionPlan._cell_from_variant(encoded.get("map_size", null))
	var map_size: Vector2i = (
		map_size_value as Vector2i
		if map_size_value is Vector2i
		else Vector2i.ZERO
	)
	var result: RegionPlanViewBuildResult = RegionPlanView.create_structurally_validated(
		int(schema_version_value),
		map_size,
		encoded.get("region_catalog", null),
		encoded.get("region_index_by_cell", null)
	)
	result.issues.append_array(unexpected_field_issues)
	if not unexpected_field_issues.is_empty():
		result.view = null
	return result


static func encode_boss_encounter_authority(descriptor_value: Variant) -> Dictionary:
	if not (descriptor_value is BossEncounterDescriptor):
		return {}
	return (descriptor_value as BossEncounterDescriptor)._to_authority_dict().duplicate(true)


static func decode_boss_encounter_authority(
	region_plan_value: Variant,
	encoded_value: Variant
) -> BossEncounterBuildResult:
	return BossEncounterDescriptor.create_structurally_validated(
		region_plan_value,
		encoded_value
	)


static func deep_clone_boss_encounter(
	region_plan_value: Variant,
	descriptor_value: Variant
) -> Variant:
	if descriptor_value == null:
		return null
	var decoded: BossEncounterBuildResult = decode_boss_encounter_authority(
		region_plan_value,
		encode_boss_encounter_authority(descriptor_value)
	)
	return decoded.descriptor if decoded.is_success() else null


static func validate_map_data_layout_artifacts(
	map_data: MapData,
	legacy_boss_encounter_count: int = 0
) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if map_data == null:
		issues.append(make_generation_issue(
			"layout_mode_artifact_mismatch",
			"map_data",
			"",
			"MapData 不能为空"
		))
		return issues
	match map_data.layout_mode:
		LAYOUT_MODE_LEGACY_RADIAL:
			if map_data.region_plan != null or map_data.region_boss_encounter != null:
				issues.append(make_generation_issue(
					"layout_mode_artifact_mismatch",
					"map_data",
					"",
					"legacy_radial 不得携带四区域 authority 产物"
				))
		LAYOUT_MODE_PVE_FOUR_REGION_V1:
			if legacy_boss_encounter_count > 0:
				issues.append(make_generation_issue(
					"layout_mode_artifact_mismatch",
					"map_data.boss_encounters",
					REGION_ROLE_BOSS,
					"pve_four_region_v1 不得携带 legacy BOSS encounter 集合"
				))
			if not (map_data.region_plan is RegionPlan):
				issues.append(make_generation_issue(
					"layout_mode_artifact_mismatch",
					"map_data.region_plan",
					"",
					"pve_four_region_v1 必须携带 RegionPlan"
				))
			if not (map_data.region_boss_encounter is BossEncounterDescriptor):
				issues.append(make_generation_issue(
					"layout_mode_artifact_mismatch",
					"map_data.region_boss_encounter",
					REGION_ROLE_BOSS,
					"pve_four_region_v1 必须携带单一 BOSS encounter descriptor"
				))
			elif map_data.region_plan is RegionPlan:
				var encounter_result: BossEncounterBuildResult = decode_boss_encounter_authority(
					map_data.region_plan,
					encode_boss_encounter_authority(map_data.region_boss_encounter)
				)
				issues.append_array(encounter_result.get_issues())
		_:
			issues.append(make_generation_issue(
				"layout_mode_artifact_mismatch",
				"map_data.layout_mode",
				"",
				"MapData layout mode 不受支持"
			))
	return issues


static func encode_map_data_region_artifacts(map_data: MapData) -> Dictionary:
	if map_data == null or not validate_map_data_layout_artifacts(map_data).is_empty():
		return {}
	var encoded: Dictionary = {"layout_mode": map_data.layout_mode}
	if map_data.layout_mode == LAYOUT_MODE_PVE_FOUR_REGION_V1:
		encoded["region_plan"] = encode_region_plan_authority(map_data.region_plan)
		encoded["region_boss_encounter"] = encode_boss_encounter_authority(
			map_data.region_boss_encounter
		)
	return encoded


static func decode_map_data_region_artifacts(encoded_value: Variant) -> MapDataRegionArtifactsBuildResult:
	var result: MapDataRegionArtifactsBuildResult = MapDataRegionArtifactsBuildResult.new()
	if not (encoded_value is Dictionary):
		result.issues.append(make_generation_issue(
			"layout_mode_artifact_mismatch",
			"map_data",
			"",
			"MapData 区域产物必须是对象"
		))
		return result
	var encoded: Dictionary = encoded_value as Dictionary
	var map_data: MapData = MapData.new()
	var layout_mode_value: Variant = RegionPlan._string_from_variant(
		encoded.get("layout_mode", null)
	)
	if layout_mode_value == null:
		result.issues.append(make_generation_issue(
			"layout_mode_artifact_mismatch",
			"map_data.layout_mode",
			"",
			"MapData layout mode 必须是字符串"
		))
		return result
	map_data.layout_mode = layout_mode_value as String
	if map_data.layout_mode == LAYOUT_MODE_PVE_FOUR_REGION_V1:
		var plan_result: RegionPlanBuildResult = decode_region_plan_authority(
			encoded.get("region_plan", null)
		)
		result.issues.append_array(plan_result.get_issues())
		if plan_result.is_success():
			map_data.region_plan = plan_result.plan
			var encounter_result: BossEncounterBuildResult = decode_boss_encounter_authority(
				map_data.region_plan,
				encoded.get("region_boss_encounter", null)
			)
			result.issues.append_array(encounter_result.get_issues())
			if encounter_result.is_success():
				map_data.region_boss_encounter = encounter_result.descriptor
	elif map_data.layout_mode == LAYOUT_MODE_LEGACY_RADIAL:
		if encoded.has("region_plan") or encoded.has("region_boss_encounter"):
			result.issues.append(make_generation_issue(
				"layout_mode_artifact_mismatch",
				"map_data",
				"",
				"legacy_radial 区域产物不得包含新模式字段"
			))
	else:
		result.issues.append(make_generation_issue(
			"layout_mode_artifact_mismatch",
			"map_data.layout_mode",
			"",
			"MapData layout mode 不受支持"
		))
	result.issues.append_array(validate_map_data_layout_artifacts(map_data))
	if result.issues.is_empty():
		result.map_data = map_data
	return result


static func server_payload_from_variant(payload_value: Variant) -> MapServerPayload:
	var payload: MapServerPayload = MapServerPayload.new()
	if payload_value is MapServerPayload:
		var source_payload: MapServerPayload = payload_value as MapServerPayload
		payload.layout_mode = source_payload.layout_mode
		var strict_four_region_payload: bool = (
			payload.layout_mode == LAYOUT_MODE_PVE_FOUR_REGION_V1
		)
		payload.is_valid = source_payload.is_valid
		payload.issues = source_payload.get_issues()
		if source_payload.region_plan != null:
			var source_view_result: RegionPlanViewBuildResult = decode_region_plan_view(
				encode_region_plan_view(source_payload.region_plan)
			)
			if source_view_result.is_success():
				payload.region_plan = source_view_result.view
			else:
				payload.is_valid = false
				payload.issues.append_array(source_view_result.get_issues())
		payload.width = source_payload.width
		payload.height = source_payload.height
		payload.cell_size_m = source_payload.cell_size_m
		payload.resolved_seed = source_payload.resolved_seed
		payload.revision = source_payload.revision
		for row_index: int in range(source_payload.tile_matrix.size()):
			var row_value: Variant = source_payload.tile_matrix[row_index]
			if not (row_value is Array):
				continue
			var source_row: Array = row_value as Array
			var row_copy: Array = []
			for column_index: int in range(source_row.size()):
				var tile_value: Variant = source_row[column_index]
				var tile_integer: Variant = RegionPlan._integer_from_variant(tile_value)
				if strict_four_region_payload and tile_integer == null:
					payload.is_valid = false
					payload.issues.append(make_generation_issue(
						"invalid_region_payload",
						"tile_matrix[%d][%d]" % [row_index, column_index],
						"",
						"pve_four_region_v1 payload 的 tile 必须是整数"
					))
					row_copy.append(0)
				else:
					row_copy.append(
						int(tile_integer) if tile_integer != null else int(tile_value)
					)
			payload.tile_matrix.append(row_copy)
		for spawn_point_value: Variant in source_payload.player_spawn_points:
			if spawn_point_value is Dictionary:
				payload.player_spawn_points.append((spawn_point_value as Dictionary).duplicate(true))
		for extraction_site_value: Variant in source_payload.extraction_sites:
			if extraction_site_value is Dictionary:
				payload.extraction_sites.append((extraction_site_value as Dictionary).duplicate(true))
		_append_decoded_payload_layout_issues(
			payload,
			true,
			source_payload.region_plan != null,
			source_payload.tile_matrix
		)
		return payload
	if not (payload_value is Dictionary):
		payload.is_valid = false
		payload.issues.append(make_generation_issue(
			"invalid_region_payload",
			"payload",
			"",
			"地图 full payload 必须是对象"
		))
		return payload
	var payload_dict: Dictionary = (payload_value as Dictionary).duplicate(true)
	var has_layout_mode: bool = payload_dict.has("layout_mode")
	var has_region_plan: bool = payload_dict.has("region_plan")
	if not has_layout_mode and not has_region_plan:
		payload.layout_mode = LAYOUT_MODE_LEGACY_RADIAL
	elif not has_layout_mode and has_region_plan:
		payload.layout_mode = ""
	else:
		var layout_mode_value: Variant = RegionPlan._string_from_variant(
			payload_dict.get("layout_mode", null)
		)
		if layout_mode_value == null:
			payload.is_valid = false
			payload.issues.append(make_generation_issue(
				"invalid_region_payload",
				"layout_mode",
				"",
				"payload layout mode 必须是字符串"
			))
			payload.layout_mode = ""
		else:
			payload.layout_mode = layout_mode_value as String
	var strict_four_region_payload: bool = (
		has_layout_mode and payload.layout_mode == LAYOUT_MODE_PVE_FOUR_REGION_V1
	)
	var width_value: Variant = payload_dict.get("width", 0)
	var height_value: Variant = payload_dict.get("height", 0)
	var width_integer: Variant = RegionPlan._integer_from_variant(width_value)
	var height_integer: Variant = RegionPlan._integer_from_variant(height_value)
	if strict_four_region_payload and width_integer == null:
		payload.is_valid = false
		payload.issues.append(make_generation_issue(
			"invalid_region_payload",
			"width",
			"",
			"pve_four_region_v1 payload width 必须是整数"
		))
	if strict_four_region_payload and height_integer == null:
		payload.is_valid = false
		payload.issues.append(make_generation_issue(
			"invalid_region_payload",
			"height",
			"",
			"pve_four_region_v1 payload height 必须是整数"
		))
	payload.width = (
		int(width_integer)
		if width_integer != null
		else (0 if strict_four_region_payload else int(width_value))
	)
	payload.height = (
		int(height_integer)
		if height_integer != null
		else (0 if strict_four_region_payload else int(height_value))
	)
	var cell_size_value: Variant = payload_dict.get("cell_size_m", 1.0)
	var cell_size_is_numeric: bool = (
		typeof(cell_size_value) == TYPE_INT or typeof(cell_size_value) == TYPE_FLOAT
	)
	if strict_four_region_payload and not cell_size_is_numeric:
		payload.is_valid = false
		payload.issues.append(make_generation_issue(
			"invalid_region_payload",
			"cell_size_m",
			"",
			"pve_four_region_v1 payload cell_size_m 必须是数值"
		))
	payload.cell_size_m = (
		maxf(float(cell_size_value), 0.1)
		if cell_size_is_numeric or not strict_four_region_payload
		else 1.0
	)
	var resolved_seed_value: Variant = payload_dict.get("resolved_seed", 0)
	var revision_value: Variant = payload_dict.get("revision", 0)
	var resolved_seed_integer: Variant = RegionPlan._integer_from_variant(resolved_seed_value)
	var revision_integer: Variant = RegionPlan._integer_from_variant(revision_value)
	if strict_four_region_payload and resolved_seed_integer == null:
		payload.is_valid = false
		payload.issues.append(make_generation_issue(
			"invalid_region_payload",
			"resolved_seed",
			"",
			"pve_four_region_v1 payload resolved_seed 必须是整数"
		))
	if strict_four_region_payload and revision_integer == null:
		payload.is_valid = false
		payload.issues.append(make_generation_issue(
			"invalid_region_payload",
			"revision",
			"",
			"pve_four_region_v1 payload revision 必须是整数"
		))
	payload.resolved_seed = (
		int(resolved_seed_integer)
		if resolved_seed_integer != null
		else (0 if strict_four_region_payload else int(resolved_seed_value))
	)
	payload.revision = (
		int(revision_integer)
		if revision_integer != null
		else (0 if strict_four_region_payload else int(revision_value))
	)
	var tile_matrix_value: Variant = payload_dict.get("tile_matrix", [])
	if tile_matrix_value is Array:
		var tile_matrix: Array = tile_matrix_value as Array
		for row_index: int in range(tile_matrix.size()):
			var row_value: Variant = tile_matrix[row_index]
			if not (row_value is Array):
				continue
			var source_row: Array = row_value as Array
			var row_copy: Array = []
			for column_index: int in range(source_row.size()):
				var tile_value: Variant = source_row[column_index]
				var tile_integer: Variant = RegionPlan._integer_from_variant(tile_value)
				if strict_four_region_payload and tile_integer == null:
					payload.is_valid = false
					payload.issues.append(make_generation_issue(
						"invalid_region_payload",
						"tile_matrix[%d][%d]" % [row_index, column_index],
						"",
						"pve_four_region_v1 payload 的 tile 必须是整数"
					))
					row_copy.append(0)
				else:
					row_copy.append(
						int(tile_integer) if tile_integer != null else int(tile_value)
					)
			payload.tile_matrix.append(row_copy)
	var spawn_points_value: Variant = payload_dict.get("player_spawn_points", [])
	if spawn_points_value is Array:
		var spawn_points: Array = spawn_points_value as Array
		for spawn_point_value: Variant in spawn_points:
			if spawn_point_value is Dictionary:
				payload.player_spawn_points.append((spawn_point_value as Dictionary).duplicate(true))
	var extraction_sites_value: Variant = payload_dict.get("extraction_sites", [])
	if extraction_sites_value is Array:
		var extraction_sites: Array = extraction_sites_value as Array
		for extraction_site_value: Variant in extraction_sites:
			if extraction_site_value is Dictionary:
				payload.extraction_sites.append((extraction_site_value as Dictionary).duplicate(true))
	if has_layout_mode and payload.layout_mode == LAYOUT_MODE_PVE_FOUR_REGION_V1 and has_region_plan:
		var view_result: RegionPlanViewBuildResult = decode_region_plan_view(
			payload_dict.get("region_plan", null)
		)
		if view_result.is_success():
			payload.region_plan = view_result.view
		else:
			payload.is_valid = false
			payload.issues.append_array(view_result.get_issues())
	_append_decoded_payload_layout_issues(
		payload,
		has_layout_mode,
		has_region_plan,
		payload_dict.get("tile_matrix", null)
	)
	return payload


static func _append_decoded_payload_layout_issues(
	payload: MapServerPayload,
	has_layout_mode: bool,
	has_region_plan: bool,
	raw_tile_matrix_value: Variant
) -> void:
	if not has_layout_mode:
		if has_region_plan:
			payload.is_valid = false
			payload.issues.append(make_generation_issue(
				"invalid_region_payload",
				"layout_mode",
				"",
				"携带 region_plan 的 payload 必须显式声明 layout_mode"
			))
		return
	match payload.layout_mode:
		LAYOUT_MODE_LEGACY_RADIAL:
			if has_region_plan:
				payload.is_valid = false
				payload.issues.append(make_generation_issue(
					"invalid_region_payload",
					"region_plan",
					"",
					"legacy_radial payload 不得携带 RegionPlanView"
				))
		LAYOUT_MODE_PVE_FOUR_REGION_V1:
			_append_four_region_tile_matrix_issues(payload, raw_tile_matrix_value)
			if not has_region_plan:
				payload.is_valid = false
				payload.issues.append(make_generation_issue(
					"invalid_region_payload",
					"region_plan",
					"",
					"pve_four_region_v1 payload 必须携带 RegionPlanView"
				))
			elif payload.region_plan is RegionPlanView:
				var view_size: Vector2i = (payload.region_plan as RegionPlanView).get_map_size()
				if payload.width != view_size.x or payload.height != view_size.y:
					payload.is_valid = false
					payload.issues.append(make_generation_issue(
						"invalid_region_payload",
						"region_plan.map_size",
						"",
						"RegionPlanView 地图尺寸与 tile payload 不一致"
					))
		_:
			payload.is_valid = false
			payload.issues.append(make_generation_issue(
				"invalid_region_payload",
				"layout_mode",
				"",
				"payload layout mode 不受支持"
			))


static func _append_four_region_tile_matrix_issues(
	payload: MapServerPayload,
	raw_tile_matrix_value: Variant
) -> void:
	if not (raw_tile_matrix_value is Array):
		payload.is_valid = false
		payload.issues.append(make_generation_issue(
			"invalid_region_payload",
			"tile_matrix",
			"",
			"pve_four_region_v1 payload 的 tile_matrix 必须是数组"
		))
		return
	var raw_tile_matrix: Array = raw_tile_matrix_value as Array
	if raw_tile_matrix.size() != payload.height:
		payload.is_valid = false
		payload.issues.append(make_generation_issue(
			"invalid_region_payload",
			"tile_matrix",
			"",
			"pve_four_region_v1 payload 的 tile_matrix 行数必须等于 height"
		))
	for row_index: int in range(raw_tile_matrix.size()):
		var row_value: Variant = raw_tile_matrix[row_index]
		if not (row_value is Array):
			payload.is_valid = false
			payload.issues.append(make_generation_issue(
				"invalid_region_payload",
				"tile_matrix[%d]" % row_index,
				"",
				"pve_four_region_v1 payload 的 tile_matrix 行必须是数组"
			))
			continue
		if (row_value as Array).size() != payload.width:
			payload.is_valid = false
			payload.issues.append(make_generation_issue(
				"invalid_region_payload",
				"tile_matrix[%d]" % row_index,
				"",
				"pve_four_region_v1 payload 的 tile_matrix 行宽必须等于 width"
			))


static func map_data_from_server_payload(payload: MapServerPayload) -> MapData:
	if payload == null or not payload.is_valid:
		return null
	if payload.layout_mode == LAYOUT_MODE_PVE_FOUR_REGION_V1:
		# 客户端只持有 RegionPlanView，不能伪造 authority RegionPlan。
		return null
	var height: int = payload.tile_matrix.size()
	var width: int = 0
	if height > 0:
		width = (payload.tile_matrix[0] as Array).size()
	width = maxi(width, payload.width)
	height = maxi(height, payload.height)
	if width <= 0 or height <= 0:
		return null
	var map_data: MapData = MapData.new()
	map_data.layout_mode = payload.layout_mode
	map_data.init_grid(width, height)
	var total_floor: int = 0
	for y: int in range(height):
		var row: Array = []
		if y < payload.tile_matrix.size():
			var row_value: Variant = payload.tile_matrix[y]
			if row_value is Array:
				row = row_value as Array
		for x: int in range(width):
			var tile_type: int = (
				int(row[x])
				if x < row.size()
				else ServerTileType.WALL
			)
			var cell: CellData = map_data.get_cell(x, y)
			apply_server_tile_to_cell(tile_type, cell)
			if cell != null and cell.cell_type == CellType.FLOOR:
				total_floor += 1
	map_data.total_floor = total_floor
	for spawn_point_value: Variant in payload.player_spawn_points:
		if spawn_point_value is Dictionary:
			map_data.player_spawn_points.append((spawn_point_value as Dictionary).duplicate(true))
	for extraction_site_value: Variant in payload.extraction_sites:
		if extraction_site_value is Dictionary:
			map_data.extraction_sites.append((extraction_site_value as Dictionary).duplicate(true))
	return map_data


static func spawn_cells_from_server_payload(payload: MapServerPayload) -> Array[Vector2i]:
	var spawn_cells: Array[Vector2i] = []
	if payload == null:
		return spawn_cells
	for spawn_point: Dictionary in payload.player_spawn_points:
		spawn_cells.append(
			Vector2i(
				int(spawn_point.get("x", 0)),
				int(spawn_point.get("y", 0))
			)
		)
	return spawn_cells


static func build_server_payload_from_runtime(
	map_data: MapData,
	spawn_cells: Array[Vector2i],
	cell_size_m: float,
	resolved_seed: int,
	revision: int,
	extraction_sites: Array[Dictionary] = []
) -> MapServerPayload:
	var payload: MapServerPayload = MapServerPayload.new()
	if map_data == null:
		payload.is_valid = false
		payload.issues.append(make_generation_issue(
			"layout_mode_artifact_mismatch",
			"map_data",
			"",
			"无法从空 MapData 构建 payload"
		))
		return payload
	payload.layout_mode = map_data.layout_mode
	var layout_issues: Array[Dictionary] = validate_map_data_layout_artifacts(map_data)
	if not layout_issues.is_empty():
		payload.is_valid = false
		payload.issues = layout_issues.duplicate(true)
		return payload
	if map_data.layout_mode == LAYOUT_MODE_PVE_FOUR_REGION_V1:
		var view_result: RegionPlanViewBuildResult = project_region_plan_view(map_data.region_plan)
		if not view_result.is_success():
			payload.is_valid = false
			payload.issues = view_result.get_issues()
			return payload
		var view_size: Vector2i = view_result.view.get_map_size()
		if view_size != Vector2i(map_data.width, map_data.height):
			payload.is_valid = false
			payload.issues.append(make_generation_issue(
				"invalid_region_payload",
				"region_plan.map_size",
				"",
				"RegionPlanView 地图尺寸与 MapData 尺寸不一致"
			))
			return payload
		payload.region_plan = view_result.view
	payload.width = map_data.width
	payload.height = map_data.height
	payload.cell_size_m = maxf(cell_size_m, 0.1)
	payload.resolved_seed = resolved_seed
	payload.revision = maxi(revision, 0)
	payload.tile_matrix.resize(map_data.height)
	for y: int in range(map_data.height):
		var row: Array = []
		row.resize(map_data.width)
		for x: int in range(map_data.width):
			row[x] = encode_server_tile(map_data.get_cell(x, y))
		payload.tile_matrix[y] = row
	if spawn_cells.is_empty():
		for spawn_point: Dictionary in map_data.player_spawn_points:
			payload.player_spawn_points.append(spawn_point.duplicate(true))
	else:
		var spawn_points_by_key: Dictionary = {}
		for spawn_point: Dictionary in map_data.player_spawn_points:
			var spawn_key: String = "%d,%d" % [
				int(spawn_point.get("x", 0)),
				int(spawn_point.get("y", 0))
			]
			spawn_points_by_key[spawn_key] = spawn_point.duplicate(true)
		for spawn_cell: Vector2i in spawn_cells:
			var spawn_cell_key: String = "%d,%d" % [spawn_cell.x, spawn_cell.y]
			var payload_spawn_point: Dictionary = {}
			if spawn_points_by_key.has(spawn_cell_key) and spawn_points_by_key[spawn_cell_key] is Dictionary:
				payload_spawn_point = (spawn_points_by_key[spawn_cell_key] as Dictionary).duplicate(true)
			payload_spawn_point["x"] = spawn_cell.x
			payload_spawn_point["y"] = spawn_cell.y
			if not payload_spawn_point.has("site_kind"):
				payload_spawn_point["site_kind"] = "player_spawn"
			payload.player_spawn_points.append(payload_spawn_point)
	var source_extraction_sites: Array[Dictionary] = extraction_sites
	if source_extraction_sites.is_empty():
		source_extraction_sites = map_data.extraction_sites
	for extraction_site: Dictionary in source_extraction_sites:
		payload.extraction_sites.append(extraction_site.duplicate(true))
	return payload


static func encode_server_tile(cell: CellData) -> int:
	if cell == null:
		return ServerTileType.WALL
	if cell.cell_type == CellType.FLOOR:
		if cell.special_block_type == SpecialBlockType.SPIKE:
			return ServerTileType.SPIKE_TILE
		if cell.special_block_type == SpecialBlockType.PRESSURE_PLATE:
			return ServerTileType.PRESSURE_PLATE_TILE
		return ServerTileType.EMPTY
	match cell.special_block_type:
		SpecialBlockType.RARE_MINERAL:
			return ServerTileType.RARE_MINERAL_WALL
		SpecialBlockType.TURQUOISE:
			return ServerTileType.TURQUOISE_ORE
		SpecialBlockType.AMETHYST:
			return ServerTileType.AMETHYST_ORE
		SpecialBlockType.GOLD:
			return ServerTileType.GOLD_BLOCK
		SpecialBlockType.POI_WALL:
			return ServerTileType.POI_WALL
		SpecialBlockType.EXPLOSIVE_ORE:
			return ServerTileType.EXPLOSIVE_ORE_TILE
		SpecialBlockType.ARROW_SLIT:
			return ServerTileType.ARROW_SLIT_TILE
	if cell.has_mineral:
		return ServerTileType.MINERAL_WALL
	return ServerTileType.WALL


static func apply_server_tile_to_cell(tile_type: int, cell: CellData) -> void:
	if cell == null:
		return
	cell.poi_type = PoiType.NONE
	cell.biome_id = -1
	cell.trace_type = PoiType.NONE
	cell.is_poi_protected = false
	cell.has_mineral = false
	cell.special_block_type = SpecialBlockType.NONE
	cell.current_hit_points = 0
	cell.max_hit_points = 0
	cell.durability_tile_type = -1
	cell.durability_override_max_hit_points = 0
	if tile_type == ServerTileType.EMPTY:
		cell.cell_type = CellType.FLOOR
		return
	if tile_type == ServerTileType.SPIKE_TILE:
		cell.cell_type = CellType.FLOOR
		cell.special_block_type = SpecialBlockType.SPIKE
		return
	if tile_type == ServerTileType.PRESSURE_PLATE_TILE:
		cell.cell_type = CellType.FLOOR
		cell.special_block_type = SpecialBlockType.PRESSURE_PLATE
		return
	cell.cell_type = CellType.WALL
	match tile_type:
		ServerTileType.MINERAL_WALL:
			cell.has_mineral = true
		ServerTileType.RARE_MINERAL_WALL:
			cell.special_block_type = SpecialBlockType.RARE_MINERAL
		ServerTileType.TURQUOISE_ORE:
			cell.special_block_type = SpecialBlockType.TURQUOISE
		ServerTileType.AMETHYST_ORE:
			cell.special_block_type = SpecialBlockType.AMETHYST
		ServerTileType.GOLD_BLOCK:
			cell.special_block_type = SpecialBlockType.GOLD
		ServerTileType.POI_WALL:
			cell.special_block_type = SpecialBlockType.POI_WALL
		ServerTileType.EXPLOSIVE_ORE_TILE:
			cell.special_block_type = SpecialBlockType.EXPLOSIVE_ORE
		ServerTileType.ARROW_SLIT_TILE:
			cell.special_block_type = SpecialBlockType.ARROW_SLIT


static func apply_chunk_payloads_to_map_data(
	map_data: MapData,
	chunk_payloads: Array,
	recompute_total_floor: bool = false
) -> bool:
	if map_data == null or chunk_payloads.is_empty():
		return false
	var changed: bool = false
	var total_floor_delta: int = 0
	for chunk_payload_value: Variant in chunk_payloads:
		if not (chunk_payload_value is Dictionary):
			continue
		var chunk_payload: Dictionary = chunk_payload_value as Dictionary
		var origin_cell: Vector2i = chunk_payload.get("origin_cell", Vector2i.ZERO)
		var size_cells: Vector2i = chunk_payload.get("size_cells", Vector2i.ZERO)
		var tile_matrix_value: Variant = chunk_payload.get("tile_matrix", [])
		var tile_hit_points_matrix_value: Variant = chunk_payload.get("tile_hit_points_matrix", [])
		var tile_max_hit_points_matrix_value: Variant = chunk_payload.get("tile_max_hit_points_matrix", [])
		if not (tile_matrix_value is Array):
			continue
		var tile_matrix: Array = tile_matrix_value as Array
		var tile_hit_points_matrix: Array = (
			tile_hit_points_matrix_value as Array
			if tile_hit_points_matrix_value is Array
			else []
		)
		var tile_max_hit_points_matrix: Array = (
			tile_max_hit_points_matrix_value as Array
			if tile_max_hit_points_matrix_value is Array
			else []
		)
		for local_y: int in range(mini(size_cells.y, tile_matrix.size())):
			var row_value: Variant = tile_matrix[local_y]
			if not (row_value is Array):
				continue
			var row: Array = row_value as Array
			var tile_hit_points_row: Array = (
				tile_hit_points_matrix[local_y] as Array
				if local_y < tile_hit_points_matrix.size() and tile_hit_points_matrix[local_y] is Array
				else []
			)
			var tile_max_hit_points_row: Array = (
				tile_max_hit_points_matrix[local_y] as Array
				if local_y < tile_max_hit_points_matrix.size() and tile_max_hit_points_matrix[local_y] is Array
				else []
			)
			for local_x: int in range(mini(size_cells.x, row.size())):
				var target_cell: Vector2i = origin_cell + Vector2i(local_x, local_y)
				if not map_data.is_in_bounds(target_cell.x, target_cell.y):
					continue
				var cell: CellData = map_data.get_cell(target_cell.x, target_cell.y)
				if cell == null:
					continue
				var previous_was_floor: bool = cell.cell_type == CellType.FLOOR
				var tile_type: int = int(row[local_x])
				apply_server_tile_to_cell(tile_type, cell)
				var tile_max_hit_points: int = (
					int(tile_max_hit_points_row[local_x])
					if local_x < tile_max_hit_points_row.size()
					else 0
				)
				var tile_hit_points: int = (
					int(tile_hit_points_row[local_x])
					if local_x < tile_hit_points_row.size()
					else tile_max_hit_points
				)
				if tile_max_hit_points > 0:
					cell.max_hit_points = maxi(tile_max_hit_points, 0)
					cell.current_hit_points = clampi(tile_hit_points, 0, cell.max_hit_points)
					cell.durability_tile_type = tile_type
					cell.durability_override_max_hit_points = cell.max_hit_points
				var next_was_floor: bool = cell.cell_type == CellType.FLOOR
				if previous_was_floor and not next_was_floor:
					total_floor_delta -= 1
				elif not previous_was_floor and next_was_floor:
					total_floor_delta += 1
				changed = true
	if changed:
		if recompute_total_floor:
			var total_floor: int = 0
			for y: int in range(map_data.height):
				for x: int in range(map_data.width):
					var cell: CellData = map_data.get_cell(x, y)
					if cell != null and cell.cell_type == CellType.FLOOR:
						total_floor += 1
			map_data.total_floor = total_floor
		else:
			map_data.total_floor = maxi(map_data.total_floor + total_floor_delta, 0)
	return changed

