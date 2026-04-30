class_name WdcMapGenerationGenerator
extends RefCounted

const WdcMapGenerationTypes = preload("generated_map_types.gd")

signal generation_stage_completed(stage: StringName, map_data: WdcMapGenerationTypes.MapData)

var last_resolved_seed: int = 0

const STAGE_INIT: StringName = &"INIT"
const STAGE_POI: StringName = &"POI"
const STAGE_NOISE: StringName = &"NOISE"
const STAGE_CAVE: StringName = &"CAVE"
const STAGE_CORRIDOR: StringName = &"CORRIDOR"
const STAGE_TRACE: StringName = &"TRACE"
const STAGE_MINERAL: StringName = &"MINERAL"
const STAGE_TRAP: StringName = &"TRAP"


func generate_full(config: WdcMapGenerationTypes.MapConfig) -> WdcMapGenerationTypes.MapData:
	return _generate_internal(config, false).get("map_data") as WdcMapGenerationTypes.MapData


func generate_server_payload(config: WdcMapGenerationTypes.MapConfig) -> WdcMapGenerationTypes.MapServerPayload:
	var map_data: WdcMapGenerationTypes.MapData = generate_full(config)
	if map_data == null:
		return null
	var payload_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var resolved_seed: int = last_resolved_seed if last_resolved_seed != 0 else _resolve_seed(config.seed)
	payload_rng.seed = resolved_seed + 1315423911
	return _build_server_payload_with_rng(map_data, payload_rng)


func build_server_payload(map_data: WdcMapGenerationTypes.MapData) -> WdcMapGenerationTypes.MapServerPayload:
	var payload_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	payload_rng.seed = int(Time.get_unix_time_from_system())
	return _build_server_payload_with_rng(map_data, payload_rng)


func _build_server_payload_with_rng(
	map_data: WdcMapGenerationTypes.MapData,
	rng: RandomNumberGenerator
) -> WdcMapGenerationTypes.MapServerPayload:
	var payload: WdcMapGenerationTypes.MapServerPayload = WdcMapGenerationTypes.MapServerPayload.new()
	payload.width = map_data.width
	payload.height = map_data.height
	payload.tile_matrix = _build_server_tile_matrix(map_data)
	payload.player_spawn_points = _generate_player_spawn_points(map_data, rng, 2)
	return payload


func generate_step_by_step(config: WdcMapGenerationTypes.MapConfig) -> Array[Dictionary]:
	return _generate_internal(config, true).get("snapshots", []) as Array[Dictionary]


func _generate_internal(config: WdcMapGenerationTypes.MapConfig, capture_snapshots: bool) -> Dictionary:
	var normalized_config: WdcMapGenerationTypes.MapConfig = config
	normalized_config.normalize()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	last_resolved_seed = _resolve_seed(normalized_config.seed)
	rng.seed = last_resolved_seed
	var map_data: WdcMapGenerationTypes.MapData = WdcMapGenerationTypes.MapData.new()
	map_data.init_grid(normalized_config.width, normalized_config.height)
	var snapshots: Array[Dictionary] = []
	_emit_stage(snapshots, STAGE_INIT, map_data, "INIT", capture_snapshots)
	_fill_noise(map_data, normalized_config.fill_percent, rng)
	_emit_stage(snapshots, STAGE_NOISE, map_data, "NOISE", capture_snapshots)
	_smooth_caves(map_data, normalized_config.smooth_iterations)
	_emit_stage(snapshots, STAGE_CAVE, map_data, "CAVE", capture_snapshots)
	_dig_corridors(map_data, normalized_config, rng)
	_emit_stage(snapshots, STAGE_CORRIDOR, map_data, "CORRIDOR", capture_snapshots)
	_generate_minerals(map_data, normalized_config, rng)
	_place_all_pois(map_data, normalized_config, rng)
	_emit_stage(snapshots, STAGE_POI, map_data, "POI", capture_snapshots)
	_generate_traces(map_data, normalized_config, rng)
	_emit_stage(snapshots, STAGE_TRACE, map_data, "TRACE", capture_snapshots)
	_generate_poi_special_blocks(map_data, normalized_config, rng)
	_generate_environmental_traps(map_data, normalized_config, rng)
	_emit_stage(snapshots, STAGE_TRAP, map_data, "TRAP", capture_snapshots)
	_recalculate_stats(map_data)
	_emit_stage(snapshots, STAGE_MINERAL, map_data, "MINERAL", capture_snapshots)
	return {
		"map_data": map_data,
		"snapshots": snapshots
	}


func _emit_stage(
	snapshots: Array[Dictionary],
	stage: StringName,
	map_data: WdcMapGenerationTypes.MapData,
	message: String,
	capture_snapshots: bool = true
) -> void:
	if not capture_snapshots:
		return
	var copied: WdcMapGenerationTypes.MapData = map_data.deep_clone()
	snapshots.append({
		"stage": String(stage),
		"map_data": copied,
		"message": message
	})
	generation_stage_completed.emit(stage, copied)


func _resolve_seed(input_seed: int) -> int:
	if input_seed != 0:
		return input_seed
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var resolved_seed: int = int(rng.randi() & 0x7fffffff)
	if resolved_seed == 0:
		resolved_seed = int(Time.get_ticks_usec() & 0x7fffffff)
	return maxi(resolved_seed, 1)


func _place_all_pois(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	if not config.poi_templates.is_empty():
		_place_configured_pois(map_data, config, rng)
		return
	var defs: Array[Dictionary] = [
		{
			"type": WdcMapGenerationTypes.PoiType.LARGE_RUIN,
			"count": config.large_poi_count,
			"min_distance": config.large_poi_min_distance,
			"radius": config.large_poi_radius,
			"irregularity": config.large_poi_irregularity
		},
		{
			"type": WdcMapGenerationTypes.PoiType.MEDIUM_BIOME,
			"count": config.medium_poi_count,
			"min_distance": config.medium_poi_min_distance,
			"radius": config.medium_poi_radius,
			"irregularity": config.medium_poi_irregularity
		},
		{
			"type": WdcMapGenerationTypes.PoiType.SMALL_ORE,
			"count": config.small_poi_count,
			"min_distance": config.small_poi_min_distance,
			"radius": config.small_poi_radius,
			"irregularity": config.small_poi_irregularity
		}
	]
	for poi_def: Dictionary in defs:
		var poi_type: int = poi_def.get("type", WdcMapGenerationTypes.PoiType.NONE) as int
		var target_count: int = poi_def.get("count", 0) as int
		var min_distance: float = poi_def.get("min_distance", 0.0) as float
		var radius: int = poi_def.get("radius", 0) as int
		var irregularity: float = poi_def.get("irregularity", 0.0) as float
		var max_attempts: int = target_count * 50
		var placed_count: int = 0
		var attempts: int = 0
		while placed_count < target_count and attempts < max_attempts:
			attempts += 1
			if _try_place_one_poi(map_data, poi_type, min_distance, radius, irregularity, rng):
				placed_count += 1


func _place_configured_pois(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	var template_index: int = 0
	for template_dict: Dictionary in config.poi_templates:
		if not bool(template_dict.get("enabled", true)):
			template_index += 1
			continue
		var target_count: int = maxi(int(template_dict.get("count", 0)), 0)
		var max_attempts: int = maxi(int(template_dict.get("placement", {}).get("poi_attempts", 40)), 1)
		var placed_count: int = 0
		var attempts: int = 0
		var compat_poi_type: int = _resolve_compat_poi_type(template_index)
		while placed_count < target_count and attempts < max_attempts:
			attempts += 1
			if _try_place_configured_poi(map_data, config, template_dict, compat_poi_type, rng):
				placed_count += 1
		template_index += 1


func _resolve_compat_poi_type(template_index: int) -> int:
	match template_index:
		0:
			return WdcMapGenerationTypes.PoiType.LARGE_RUIN
		1:
			return WdcMapGenerationTypes.PoiType.MEDIUM_BIOME
		_:
			return WdcMapGenerationTypes.PoiType.SMALL_ORE


func _try_place_configured_poi(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	template_dict: Dictionary,
	compat_poi_type: int,
	rng: RandomNumberGenerator
) -> bool:
	var placement: Dictionary = template_dict.get("placement", {}) as Dictionary
	var main_room_cfg: Dictionary = template_dict.get("main_room", {}) as Dictionary
	var sub_room_cfg: Dictionary = template_dict.get("sub_rooms", {}) as Dictionary
	var main_room_margin: int = maxi(
		int(sub_room_cfg.get("placement_radius_max_cells", 0)),
		maxi(int(placement.get("footprint_padding_cells", 0)), 0)
	) + 1
	var main_room_rect: Rect2i = _sample_room_rect(map_data, main_room_cfg, rng, main_room_margin)
	if main_room_rect.size == Vector2i.ZERO:
		return false
	var rooms: Array[Rect2i] = [main_room_rect]
	var sub_room_count: int = 0
	var sub_count_min: int = maxi(int(sub_room_cfg.get("count_min", 0)), 0)
	var sub_count_max: int = maxi(int(sub_room_cfg.get("count_max", sub_count_min)), sub_count_min)
	if sub_count_max > 0:
		sub_room_count = rng.randi_range(sub_count_min, sub_count_max)
	var placed_sub_room_count: int = 0
	for _sub_room_index: int in range(sub_room_count):
		var sub_room_rect: Rect2i = _sample_sub_room_rect(map_data, rooms, main_room_rect, sub_room_cfg, rng)
		if sub_room_rect.size == Vector2i.ZERO:
			continue
		rooms.append(sub_room_rect)
		placed_sub_room_count += 1
	if placed_sub_room_count < sub_count_min:
		return false
	var corridor_edges: Array[Dictionary] = _build_poi_connectivity_edges(rooms, template_dict, rng)
	if corridor_edges.is_empty() and rooms.size() > 1:
		return false
	var corridor_plans: Array[Dictionary] = _build_corridor_plans_for_edges(
		rooms,
		corridor_edges,
		template_dict
	)
	var corridor_cells: Array[Vector2i] = _collect_unique_corridor_cells(corridor_plans)
	if corridor_cells.is_empty() and rooms.size() > 1:
		return false
	var total_bounds: Rect2i = _compute_total_poi_bounds(rooms, corridor_cells, placement)
	if not _is_poi_bounds_valid(map_data, total_bounds):
		return false
	for existing_instance: Dictionary in map_data.poi_instances:
		if total_bounds.intersects(existing_instance.get("bounds", Rect2i())):
			return false
	_carve_poi_rooms_and_corridors(map_data, rooms, corridor_cells, compat_poi_type)
	_place_poi_outer_walls(map_data, rooms, corridor_cells, compat_poi_type)
	var center_cell: Vector2i = _rect_center_cell(main_room_rect)
	var torch_sites: Array[Vector2i] = _build_main_room_torch_sites(main_room_rect, template_dict)
	var room_content_plans: Array[Dictionary] = _build_room_content_plans(
		rooms,
		corridor_plans,
		template_dict,
		rng
	)
	map_data.poi_centers.append({
		"x": center_cell.x,
		"y": center_cell.y,
		"type": compat_poi_type,
		"template_id": str(template_dict.get("id", "")),
	})
	map_data.poi_instances.append({
		"template_id": str(template_dict.get("id", "")),
		"poi_type": compat_poi_type,
		"bounds": total_bounds,
		"main_room": _rect_to_dict(main_room_rect),
		"sub_rooms": _rect_array_to_dict_array(rooms.slice(1)),
		"corridors": _corridor_plans_to_dict_array(corridor_plans),
		"corridor_cell_count": corridor_cells.size(),
		"center_cell": center_cell,
		"torch_sites": _vector2i_array_to_dict_array(torch_sites),
		"room_content_plans": _room_content_plan_array_to_dict_array(room_content_plans),
	})
	_append_room_content_sites(map_data, room_content_plans, config)
	_place_poi_center_cluster(map_data, main_room_rect, template_dict, config, rng)
	return true


func _sample_room_rect(
	map_data: WdcMapGenerationTypes.MapData,
	room_cfg: Dictionary,
	rng: RandomNumberGenerator,
	extra_margin: int = 1
) -> Rect2i:
	var width_min: int = maxi(int(room_cfg.get("width_min", 1)), 1)
	var width_max: int = maxi(int(room_cfg.get("width_max", width_min)), width_min)
	var height_min: int = maxi(int(room_cfg.get("height_min", 1)), 1)
	var height_max: int = maxi(int(room_cfg.get("height_max", height_min)), height_min)
	var room_width: int = rng.randi_range(width_min, width_max)
	var room_height: int = rng.randi_range(height_min, height_max)
	if room_width + extra_margin * 2 >= map_data.width or room_height + extra_margin * 2 >= map_data.height:
		return Rect2i()
	var min_x: int = maxi(extra_margin, 1)
	var min_y: int = maxi(extra_margin, 1)
	var max_x: int = maxi(map_data.width - room_width - extra_margin, min_x)
	var max_y: int = maxi(map_data.height - room_height - extra_margin, min_y)
	var origin_x: int = rng.randi_range(min_x, max_x)
	var origin_y: int = rng.randi_range(min_y, max_y)
	return Rect2i(origin_x, origin_y, room_width, room_height)


func _sample_sub_room_rect(
	map_data: WdcMapGenerationTypes.MapData,
	existing_rooms: Array[Rect2i],
	main_room_rect: Rect2i,
	sub_room_cfg: Dictionary,
	rng: RandomNumberGenerator
) -> Rect2i:
	var attempts: int = maxi(int(sub_room_cfg.get("placement_attempts_per_room", 12)), 12)
	var width_min: int = maxi(int(sub_room_cfg.get("width_min", 1)), 1)
	var width_max: int = maxi(int(sub_room_cfg.get("width_max", width_min)), width_min)
	var height_min: int = maxi(int(sub_room_cfg.get("height_min", 1)), 1)
	var height_max: int = maxi(int(sub_room_cfg.get("height_max", height_min)), height_min)
	var min_gap: int = maxi(int(sub_room_cfg.get("min_gap_from_rooms_cells", 1)), 0)
	var radius_min: int = maxi(int(sub_room_cfg.get("placement_radius_min_cells", 1)), 1)
	var radius_max: int = maxi(int(sub_room_cfg.get("placement_radius_max_cells", radius_min)), radius_min)
	var main_center: Vector2i = _rect_center_cell(main_room_rect)
	var preferred_candidates: Array[Rect2i] = _build_preferred_sub_room_candidates(
		main_room_rect,
		width_min,
		width_max,
		height_min,
		height_max,
		min_gap,
		radius_min,
		rng
	)
	for candidate: Rect2i in preferred_candidates:
		if not _is_room_rect_in_bounds(map_data, candidate):
			continue
		var overlaps_preferred: bool = false
		for existing_room: Rect2i in existing_rooms:
			if _rect_intersects_with_margin(candidate, existing_room, min_gap):
				overlaps_preferred = true
				break
		if not overlaps_preferred:
			return candidate
	for _attempt_idx: int in range(attempts):
		var room_width: int = rng.randi_range(width_min, width_max)
		var room_height: int = rng.randi_range(height_min, height_max)
		var radius: float = float(rng.randi_range(radius_min, radius_max))
		var angle: float = rng.randf() * TAU
		var center_x: int = int(roundf(float(main_center.x) + cos(angle) * radius))
		var center_y: int = int(roundf(float(main_center.y) + sin(angle) * radius))
		var candidate: Rect2i = Rect2i(
			center_x - int(floor(room_width * 0.5)),
			center_y - int(floor(room_height * 0.5)),
			room_width,
			room_height
		)
		if not _is_room_rect_in_bounds(map_data, candidate):
			continue
		var overlaps: bool = false
		for existing_room: Rect2i in existing_rooms:
			if _rect_intersects_with_margin(candidate, existing_room, min_gap):
				overlaps = true
				break
		if overlaps:
			continue
		return candidate
	return Rect2i()


func _build_preferred_sub_room_candidates(
	main_room_rect: Rect2i,
	width_min: int,
	width_max: int,
	height_min: int,
	height_max: int,
	min_gap: int,
	radius_min: int,
	rng: RandomNumberGenerator
) -> Array[Rect2i]:
	var candidates: Array[Rect2i] = []
	var sub_room_width: int = rng.randi_range(width_min, width_max)
	var sub_room_height: int = rng.randi_range(height_min, height_max)
	var horizontal_offset: int = int(ceili(main_room_rect.size.x * 0.5)) + int(ceili(sub_room_width * 0.5)) + min_gap + radius_min
	var vertical_offset: int = int(ceili(main_room_rect.size.y * 0.5)) + int(ceili(sub_room_height * 0.5)) + min_gap + radius_min
	var center: Vector2i = _rect_center_cell(main_room_rect)
	candidates.append(
		Rect2i(
			center.x + horizontal_offset - int(floor(sub_room_width * 0.5)),
			center.y - int(floor(sub_room_height * 0.5)),
			sub_room_width,
			sub_room_height
		)
	)
	candidates.append(
		Rect2i(
			center.x - horizontal_offset - int(floor(sub_room_width * 0.5)),
			center.y - int(floor(sub_room_height * 0.5)),
			sub_room_width,
			sub_room_height
		)
	)
	candidates.append(
		Rect2i(
			center.x - int(floor(sub_room_width * 0.5)),
			center.y + vertical_offset - int(floor(sub_room_height * 0.5)),
			sub_room_width,
			sub_room_height
		)
	)
	candidates.append(
		Rect2i(
			center.x - int(floor(sub_room_width * 0.5)),
			center.y - vertical_offset - int(floor(sub_room_height * 0.5)),
			sub_room_width,
			sub_room_height
		)
	)
	return candidates


func _build_poi_connectivity_edges(
	rooms: Array[Rect2i],
	template_dict: Dictionary,
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	if rooms.size() <= 1:
		return []
	var connectivity: Dictionary = template_dict.get("connectivity", {}) as Dictionary
	var neighbor_limit: int = maxi(int(connectivity.get("candidate_neighbors_per_room", 2)), 1)
	var candidate_edges: Array[Dictionary] = []
	var seen_keys: Dictionary = {}
	for room_index: int in range(rooms.size()):
		var room_distances: Array[Dictionary] = []
		var center_a: Vector2i = _rect_center_cell(rooms[room_index])
		for other_index: int in range(rooms.size()):
			if room_index == other_index:
				continue
			var center_b: Vector2i = _rect_center_cell(rooms[other_index])
			room_distances.append({
				"from": room_index,
				"to": other_index,
				"distance": abs(center_a.x - center_b.x) + abs(center_a.y - center_b.y),
			})
		room_distances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("distance", 0)) < int(b.get("distance", 0))
		)
		for neighbor_idx: int in range(mini(neighbor_limit, room_distances.size())):
			var edge: Dictionary = room_distances[neighbor_idx]
			var edge_key: String = _edge_key(int(edge.get("from", 0)), int(edge.get("to", 0)))
			if seen_keys.has(edge_key):
				continue
			seen_keys[edge_key] = true
			candidate_edges.append(edge)
	_ensure_candidate_edge_connectivity(rooms, candidate_edges, seen_keys)
	var mst_edges: Array[Dictionary] = _build_mst_edges(rooms.size(), candidate_edges)
	var selected_keys: Dictionary = {}
	for edge: Dictionary in mst_edges:
		selected_keys[_edge_key(int(edge.get("from", 0)), int(edge.get("to", 0)))] = true
	var extra_edges: Array[Dictionary] = []
	var extra_chance: float = clampf(float(connectivity.get("extra_connection_chance", 0.0)), 0.0, 1.0)
	var max_extra_connections: int = maxi(int(connectivity.get("max_extra_connections", 0)), 0)
	if max_extra_connections > 0 and extra_chance > 0.0:
		var extra_candidates: Array[Dictionary] = []
		for edge: Dictionary in candidate_edges:
			var edge_key: String = _edge_key(int(edge.get("from", 0)), int(edge.get("to", 0)))
			if selected_keys.has(edge_key):
				continue
			extra_candidates.append(edge)
		extra_candidates.shuffle()
		for edge: Dictionary in extra_candidates:
			if extra_edges.size() >= max_extra_connections:
				break
			if rng.randf() > extra_chance:
				continue
			extra_edges.append(edge)
	return mst_edges + extra_edges


func _ensure_candidate_edge_connectivity(
	rooms: Array[Rect2i],
	candidate_edges: Array[Dictionary],
	seen_keys: Dictionary
) -> void:
	if rooms.size() <= 1:
		return
	for room_index: int in range(rooms.size() - 1):
		var next_index: int = room_index + 1
		var edge_key: String = _edge_key(room_index, next_index)
		if seen_keys.has(edge_key):
			continue
		var center_a: Vector2i = _rect_center_cell(rooms[room_index])
		var center_b: Vector2i = _rect_center_cell(rooms[next_index])
		candidate_edges.append({
			"from": room_index,
			"to": next_index,
			"distance": abs(center_a.x - center_b.x) + abs(center_a.y - center_b.y),
		})
		seen_keys[edge_key] = true


func _build_mst_edges(room_count: int, candidate_edges: Array[Dictionary]) -> Array[Dictionary]:
	var sorted_edges: Array[Dictionary] = []
	for edge: Dictionary in candidate_edges:
		sorted_edges.append(edge.duplicate(true))
	sorted_edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("distance", 0)) < int(b.get("distance", 0))
	)
	var parent: Array[int] = []
	parent.resize(room_count)
	for room_index: int in range(room_count):
		parent[room_index] = room_index
	var mst_edges: Array[Dictionary] = []
	for edge: Dictionary in sorted_edges:
		var from_index: int = int(edge.get("from", 0))
		var to_index: int = int(edge.get("to", 0))
		var root_a: int = _find_set_root(parent, from_index)
		var root_b: int = _find_set_root(parent, to_index)
		if root_a == root_b:
			continue
		parent[root_b] = root_a
		mst_edges.append(edge)
		if mst_edges.size() >= room_count - 1:
			break
	return mst_edges


func _find_set_root(parent: Array[int], node_index: int) -> int:
	var root: int = node_index
	while parent[root] != root:
		root = parent[root]
	return root


func _build_corridor_plans_for_edges(
	rooms: Array[Rect2i],
	edges: Array[Dictionary],
	template_dict: Dictionary
) -> Array[Dictionary]:
	var corridor_plans: Array[Dictionary] = []
	for edge: Dictionary in edges:
		var from_index: int = int(edge.get("from", 0))
		var to_index: int = int(edge.get("to", 0))
		if from_index < 0 or from_index >= rooms.size() or to_index < 0 or to_index >= rooms.size():
			return []
		var corridor_plan: Dictionary = _build_corridor_plan_between_rooms(
			rooms[from_index],
			rooms[to_index],
			template_dict
		)
		if corridor_plan.is_empty():
			return []
		corridor_plan["from_room"] = from_index
		corridor_plan["to_room"] = to_index
		corridor_plans.append(corridor_plan)
	return corridor_plans


func _collect_unique_corridor_cells(corridor_plans: Array[Dictionary]) -> Array[Vector2i]:
	var cells_by_key: Dictionary = {}
	for corridor_plan: Dictionary in corridor_plans:
		var corridor_cells: Array = corridor_plan.get("cells", []) as Array
		for cell_value: Variant in corridor_cells:
			if not (cell_value is Vector2i):
				continue
			var cell: Vector2i = cell_value as Vector2i
			cells_by_key[_key(cell.x, cell.y)] = cell
	var cells: Array[Vector2i] = []
	for cell_value: Variant in cells_by_key.values():
		if cell_value is Vector2i:
			cells.append(cell_value as Vector2i)
	return cells


func _build_corridor_plan_between_rooms(
	room_a: Rect2i,
	room_b: Rect2i,
	template_dict: Dictionary
) -> Dictionary:
	var corridor_cfg: Dictionary = template_dict.get("corridor", {}) as Dictionary
	var retry_count: int = maxi(int(corridor_cfg.get("retry_doorway_count", 1)), 1)
	for _retry_idx: int in range(retry_count):
		var doorway_pair: Dictionary = _select_corridor_doorway_pair(room_a, room_b, corridor_cfg)
		var cells: Array[Vector2i] = _build_l_shaped_corridor(
			doorway_pair.get("from", Vector2i.ZERO) as Vector2i,
			doorway_pair.get("to", Vector2i.ZERO) as Vector2i,
			maxi(int(corridor_cfg.get("width_cells", 1)), 1),
			str(corridor_cfg.get("bend_order_mode", "random"))
		)
		if not cells.is_empty():
			return {
				"from_door": doorway_pair.get("from", Vector2i.ZERO),
				"to_door": doorway_pair.get("to", Vector2i.ZERO),
				"cells": cells,
			}
	return {}


func _select_corridor_doorway_pair(
	room_a: Rect2i,
	room_b: Rect2i,
	corridor_cfg: Dictionary
) -> Dictionary:
	var center_a: Vector2i = _rect_center_cell(room_a)
	var center_b: Vector2i = _rect_center_cell(room_b)
	var margin: int = maxi(int(corridor_cfg.get("door_margin_from_corner_cells", 1)), 0)
	var from_cell: Vector2i = center_a
	var to_cell: Vector2i = center_b
	var delta_x: int = center_b.x - center_a.x
	var delta_y: int = center_b.y - center_a.y
	if abs(delta_x) >= abs(delta_y):
		from_cell = _doorway_on_horizontal_side(room_a, delta_x >= 0, center_b.y, margin)
		to_cell = _doorway_on_horizontal_side(room_b, delta_x < 0, center_a.y, margin)
	else:
		from_cell = _doorway_on_vertical_side(room_a, delta_y >= 0, center_b.x, margin)
		to_cell = _doorway_on_vertical_side(room_b, delta_y < 0, center_a.x, margin)
	return {
		"from": from_cell,
		"to": to_cell,
	}


func _doorway_on_horizontal_side(
	room_rect: Rect2i,
	use_right_side: bool,
	preferred_y: int,
	margin: int
) -> Vector2i:
	var min_y: int = room_rect.position.y + margin
	var max_y: int = room_rect.position.y + room_rect.size.y - 1 - margin
	if min_y > max_y:
		min_y = room_rect.position.y
		max_y = room_rect.position.y + room_rect.size.y - 1
	var resolved_y: int = clampi(preferred_y, min_y, max_y)
	var resolved_x: int = room_rect.position.x + room_rect.size.x - 1 if use_right_side else room_rect.position.x
	return Vector2i(resolved_x, resolved_y)


func _doorway_on_vertical_side(
	room_rect: Rect2i,
	use_bottom_side: bool,
	preferred_x: int,
	margin: int
) -> Vector2i:
	var min_x: int = room_rect.position.x + margin
	var max_x: int = room_rect.position.x + room_rect.size.x - 1 - margin
	if min_x > max_x:
		min_x = room_rect.position.x
		max_x = room_rect.position.x + room_rect.size.x - 1
	var resolved_x: int = clampi(preferred_x, min_x, max_x)
	var resolved_y: int = room_rect.position.y + room_rect.size.y - 1 if use_bottom_side else room_rect.position.y
	return Vector2i(resolved_x, resolved_y)


func _build_l_shaped_corridor(
	from_cell: Vector2i,
	to_cell: Vector2i,
	width_cells: int,
	bend_order_mode: String
) -> Array[Vector2i]:
	var horizontal_first: bool = true
	if bend_order_mode == "vertical_first":
		horizontal_first = false
	elif bend_order_mode == "random":
		horizontal_first = abs(from_cell.x - to_cell.x) >= abs(from_cell.y - to_cell.y)
	var cells: Array[Vector2i] = []
	var corridor_radius: int = maxi(int(floor(float(width_cells - 1) * 0.5)), 0)
	if horizontal_first:
		_append_corridor_line(cells, from_cell, Vector2i(to_cell.x, from_cell.y), corridor_radius)
		_append_corridor_line(cells, Vector2i(to_cell.x, from_cell.y), to_cell, corridor_radius)
	else:
		_append_corridor_line(cells, from_cell, Vector2i(from_cell.x, to_cell.y), corridor_radius)
		_append_corridor_line(cells, Vector2i(from_cell.x, to_cell.y), to_cell, corridor_radius)
	return cells


func _append_corridor_line(
	cells: Array[Vector2i],
	from_cell: Vector2i,
	to_cell: Vector2i,
	radius: int
) -> void:
	if from_cell.x == to_cell.x:
		var start_y: int = mini(from_cell.y, to_cell.y)
		var end_y: int = maxi(from_cell.y, to_cell.y)
		for y: int in range(start_y, end_y + 1):
			for x: int in range(from_cell.x - radius, from_cell.x + radius + 1):
				cells.append(Vector2i(x, y))
	else:
		var start_x: int = mini(from_cell.x, to_cell.x)
		var end_x: int = maxi(from_cell.x, to_cell.x)
		for x: int in range(start_x, end_x + 1):
			for y: int in range(from_cell.y - radius, from_cell.y + radius + 1):
				cells.append(Vector2i(x, y))


func _carve_poi_rooms_and_corridors(
	map_data: WdcMapGenerationTypes.MapData,
	rooms: Array[Rect2i],
	corridor_cells: Array[Vector2i],
	compat_poi_type: int
) -> void:
	for room_rect: Rect2i in rooms:
		_carve_room_rect(map_data, room_rect, compat_poi_type)
	for corridor_cell: Vector2i in corridor_cells:
		if not map_data.is_in_bounds(corridor_cell.x, corridor_cell.y):
			continue
		var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(corridor_cell.x, corridor_cell.y)
		if cell == null:
			continue
		cell.cell_type = WdcMapGenerationTypes.CellType.FLOOR
		cell.poi_type = compat_poi_type
		cell.is_poi_protected = true


func _carve_room_rect(
	map_data: WdcMapGenerationTypes.MapData,
	room_rect: Rect2i,
	compat_poi_type: int
) -> void:
	for y: int in range(room_rect.position.y, room_rect.position.y + room_rect.size.y):
		for x: int in range(room_rect.position.x, room_rect.position.x + room_rect.size.x):
			if not map_data.is_in_bounds(x, y):
				continue
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			cell.cell_type = WdcMapGenerationTypes.CellType.FLOOR
			cell.poi_type = compat_poi_type
			cell.is_poi_protected = true


func _place_poi_outer_walls(
	map_data: WdcMapGenerationTypes.MapData,
	rooms: Array[Rect2i],
	corridor_cells: Array[Vector2i],
	compat_poi_type: int
) -> void:
	var interior_keys: Dictionary = {}
	for room_rect: Rect2i in rooms:
		for y: int in range(room_rect.position.y, room_rect.position.y + room_rect.size.y):
			for x: int in range(room_rect.position.x, room_rect.position.x + room_rect.size.x):
				interior_keys[_key(x, y)] = true
	for corridor_cell: Vector2i in corridor_cells:
		interior_keys[_key(corridor_cell.x, corridor_cell.y)] = true
	var shell_cells: Array[Vector2i] = []
	var shell_keys: Dictionary = {}
	for room_rect: Rect2i in rooms:
		for y: int in range(room_rect.position.y - 1, room_rect.position.y + room_rect.size.y + 1):
			for x: int in range(room_rect.position.x - 1, room_rect.position.x + room_rect.size.x + 1):
				var key: String = _key(x, y)
				if interior_keys.has(key) or shell_keys.has(key):
					continue
				if not map_data.is_in_bounds(x, y):
					continue
				shell_keys[key] = true
				shell_cells.append(Vector2i(x, y))
	for corridor_cell: Vector2i in corridor_cells:
		for offset_y: int in range(-1, 2):
			for offset_x: int in range(-1, 2):
				var x: int = corridor_cell.x + offset_x
				var y: int = corridor_cell.y + offset_y
				var key: String = _key(x, y)
				if interior_keys.has(key) or shell_keys.has(key):
					continue
				if not map_data.is_in_bounds(x, y):
					continue
				shell_keys[key] = true
				shell_cells.append(Vector2i(x, y))
	for shell_cell: Vector2i in shell_cells:
		var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(shell_cell.x, shell_cell.y)
		if cell == null:
			continue
		cell.cell_type = WdcMapGenerationTypes.CellType.WALL
		cell.poi_type = compat_poi_type
		cell.is_poi_protected = true
		cell.has_mineral = false
		cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.POI_WALL


func _compute_total_poi_bounds(
	rooms: Array[Rect2i],
	corridor_cells: Array[Vector2i],
	placement_cfg: Dictionary
) -> Rect2i:
	var min_x: int = 1 << 30
	var min_y: int = 1 << 30
	var max_x: int = -(1 << 30)
	var max_y: int = -(1 << 30)
	for room_rect: Rect2i in rooms:
		min_x = mini(min_x, room_rect.position.x)
		min_y = mini(min_y, room_rect.position.y)
		max_x = maxi(max_x, room_rect.position.x + room_rect.size.x - 1)
		max_y = maxi(max_y, room_rect.position.y + room_rect.size.y - 1)
	for corridor_cell: Vector2i in corridor_cells:
		min_x = mini(min_x, corridor_cell.x)
		min_y = mini(min_y, corridor_cell.y)
		max_x = maxi(max_x, corridor_cell.x)
		max_y = maxi(max_y, corridor_cell.y)
	var padding: int = maxi(int(placement_cfg.get("footprint_padding_cells", 0)), 0)
	return Rect2i(
		min_x - padding,
		min_y - padding,
		(max_x - min_x + 1) + padding * 2,
		(max_y - min_y + 1) + padding * 2
	)


func _is_poi_bounds_valid(map_data: WdcMapGenerationTypes.MapData, bounds: Rect2i) -> bool:
	return (
		bounds.position.x >= 0
		and bounds.position.y >= 0
		and bounds.position.x + bounds.size.x <= map_data.width
		and bounds.position.y + bounds.size.y <= map_data.height
	)


func _is_room_rect_in_bounds(map_data: WdcMapGenerationTypes.MapData, room_rect: Rect2i) -> bool:
	return (
		room_rect.size.x > 0
		and room_rect.size.y > 0
		and room_rect.position.x >= 1
		and room_rect.position.y >= 1
		and room_rect.position.x + room_rect.size.x < map_data.width
		and room_rect.position.y + room_rect.size.y < map_data.height
	)


func _rect_intersects_with_margin(rect_a: Rect2i, rect_b: Rect2i, margin: int) -> bool:
	var expanded_b: Rect2i = Rect2i(
		rect_b.position.x - margin,
		rect_b.position.y - margin,
		rect_b.size.x + margin * 2,
		rect_b.size.y + margin * 2
	)
	return rect_a.intersects(expanded_b)


func _rect_center_cell(room_rect: Rect2i) -> Vector2i:
	return Vector2i(
		room_rect.position.x + int(floor(room_rect.size.x * 0.5)),
		room_rect.position.y + int(floor(room_rect.size.y * 0.5))
	)


func _rect_to_dict(room_rect: Rect2i) -> Dictionary:
	return {
		"x": room_rect.position.x,
		"y": room_rect.position.y,
		"width": room_rect.size.x,
		"height": room_rect.size.y,
	}


func _rect_array_to_dict_array(rooms: Array) -> Array[Dictionary]:
	var dicts: Array[Dictionary] = []
	for room_value: Variant in rooms:
		if room_value is Rect2i:
			dicts.append(_rect_to_dict(room_value as Rect2i))
	return dicts


func _vector2i_array_to_dict_array(cells: Array[Vector2i]) -> Array[Dictionary]:
	var dicts: Array[Dictionary] = []
	for cell: Vector2i in cells:
		dicts.append({
			"x": cell.x,
			"y": cell.y,
		})
	return dicts


func _corridor_plans_to_dict_array(corridor_plans: Array[Dictionary]) -> Array[Dictionary]:
	var dicts: Array[Dictionary] = []
	for corridor_plan: Dictionary in corridor_plans:
		dicts.append({
			"from_room": int(corridor_plan.get("from_room", -1)),
			"to_room": int(corridor_plan.get("to_room", -1)),
			"from_door": _vector2i_to_dict(corridor_plan.get("from_door", Vector2i.ZERO) as Vector2i),
			"to_door": _vector2i_to_dict(corridor_plan.get("to_door", Vector2i.ZERO) as Vector2i),
			"cells": _vector2i_array_to_dict_array(_extract_vector2i_array(corridor_plan.get("cells", []))),
		})
	return dicts


func _room_content_plan_array_to_dict_array(plans: Array[Dictionary]) -> Array[Dictionary]:
	var dicts: Array[Dictionary] = []
	for plan: Dictionary in plans:
		var converted: Dictionary = plan.duplicate(true)
		var anchor_cell: Vector2i = converted.get("anchor_cell", Vector2i.ZERO) as Vector2i
		converted["anchor_cell"] = _vector2i_to_dict(anchor_cell)
		dicts.append(converted)
	return dicts


func _append_room_content_sites(
	map_data: WdcMapGenerationTypes.MapData,
	room_content_plans: Array[Dictionary],
	config: WdcMapGenerationTypes.MapConfig
) -> void:
	var isolated_templates: Array[Dictionary] = _extract_dictionary_array(
		config.get_meta("isolated_spawn_templates", [])
	)
	var nest_templates: Array[Dictionary] = _extract_dictionary_array(
		config.get_meta("nest_templates", [])
	)
	for plan: Dictionary in room_content_plans:
		var content_kind: String = str(plan.get("content_kind", "none"))
		if content_kind == "none":
			continue
		var template_id: String = str(plan.get("template_id", ""))
		if template_id.is_empty():
			continue
		var anchor_cell: Vector2i = plan.get("anchor_cell", Vector2i.ZERO) as Vector2i
		if content_kind == "monster_pack":
			var spawn_template: Dictionary = _find_template_by_id(isolated_templates, template_id)
			if spawn_template.is_empty():
				continue
			map_data.monster_sites.append({
				"site_kind": "isolated",
				"room_kind": str(plan.get("room_kind", "")),
				"cell": anchor_cell,
				"template_id": template_id,
				"monster_id": str(spawn_template.get("monster_id", "")),
			})
		elif content_kind == "nest":
			var nest_template: Dictionary = _find_template_by_id(nest_templates, template_id)
			if nest_template.is_empty():
				continue
			map_data.monster_sites.append({
				"site_kind": "nest",
				"room_kind": str(plan.get("room_kind", "")),
				"cell": anchor_cell,
				"template_id": template_id,
				"nest_unit_id": str(nest_template.get("nest_unit_id", "")),
				"monster_id": str(nest_template.get("monster_id", "")),
				"loot_table_id": str(nest_template.get("loot_table_id", "")),
				"activation_radius_m": float(nest_template.get("activation_radius_m", 0.0)),
				"spawn_interval_sec": float(nest_template.get("spawn_interval_sec", 0.0)),
				"max_alive_children": int(nest_template.get("max_alive_children", 0)),
				"max_hit_points": int(nest_template.get("max_hit_points", 0)),
			})


func _vector2i_to_dict(cell: Vector2i) -> Dictionary:
	return {
		"x": cell.x,
		"y": cell.y,
	}


func _find_template_by_id(templates: Array[Dictionary], template_id: String) -> Dictionary:
	for template_dict: Dictionary in templates:
		if str(template_dict.get("id", "")) == template_id:
			return template_dict.duplicate(true)
	return {}


func _extract_vector2i_array(values: Variant) -> Array[Vector2i]:
	var extracted: Array[Vector2i] = []
	if not (values is Array):
		return extracted
	for value: Variant in values:
		if value is Vector2i:
			extracted.append(value as Vector2i)
	return extracted


func _extract_dictionary_array(values: Variant) -> Array[Dictionary]:
	var extracted: Array[Dictionary] = []
	if not (values is Array):
		return extracted
	for value: Variant in values:
		if value is Dictionary:
			extracted.append((value as Dictionary).duplicate(true))
	return extracted


func _edge_key(index_a: int, index_b: int) -> String:
	var min_index: int = mini(index_a, index_b)
	var max_index: int = maxi(index_a, index_b)
	return "%d-%d" % [min_index, max_index]


func _build_main_room_torch_sites(
	main_room_rect: Rect2i,
	template_dict: Dictionary
) -> Array[Vector2i]:
	var torch_cfg: Dictionary = template_dict.get("torch", {}) as Dictionary
	if not bool(torch_cfg.get("enabled", false)):
		return []
	var inset: int = maxi(int(torch_cfg.get("wall_inset_cells", 1)), 0)
	var max_count: int = maxi(int(torch_cfg.get("max_torch_count", 0)), 0)
	if max_count <= 0:
		return []
	var candidates: Array[Vector2i] = []
	candidates.append(Vector2i(main_room_rect.position.x + inset, main_room_rect.position.y + inset))
	candidates.append(
		Vector2i(
			main_room_rect.position.x + main_room_rect.size.x - 1 - inset,
			main_room_rect.position.y + inset
		)
	)
	candidates.append(
		Vector2i(
			main_room_rect.position.x + inset,
			main_room_rect.position.y + main_room_rect.size.y - 1 - inset
		)
	)
	candidates.append(
		Vector2i(
			main_room_rect.position.x + main_room_rect.size.x - 1 - inset,
			main_room_rect.position.y + main_room_rect.size.y - 1 - inset
		)
	)
	if main_room_rect.size.x >= 10:
		candidates.append(
			Vector2i(_rect_center_cell(main_room_rect).x, main_room_rect.position.y + inset)
		)
		candidates.append(
			Vector2i(
				_rect_center_cell(main_room_rect).x,
				main_room_rect.position.y + main_room_rect.size.y - 1 - inset
			)
		)
	if main_room_rect.size.y >= 10:
		candidates.append(
			Vector2i(main_room_rect.position.x + inset, _rect_center_cell(main_room_rect).y)
		)
		candidates.append(
			Vector2i(
				main_room_rect.position.x + main_room_rect.size.x - 1 - inset,
				_rect_center_cell(main_room_rect).y
			)
		)
	var unique_by_key: Dictionary = {}
	for candidate: Vector2i in candidates:
		if _is_cell_inside_rect(candidate, main_room_rect):
			unique_by_key[_key(candidate.x, candidate.y)] = candidate
	var torch_sites: Array[Vector2i] = []
	for cell_value: Variant in unique_by_key.values():
		if cell_value is Vector2i:
			torch_sites.append(cell_value as Vector2i)
	if torch_sites.size() > max_count:
		torch_sites.resize(max_count)
	return torch_sites


func _build_room_content_plans(
	rooms: Array[Rect2i],
	corridor_plans: Array[Dictionary],
	template_dict: Dictionary,
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var content: Dictionary = template_dict.get("content", {}) as Dictionary
	var main_cfg: Dictionary = content.get("main_room_roll", {}) as Dictionary
	var sub_cfg: Dictionary = content.get("sub_room_roll", {}) as Dictionary
	var center_cluster_cfg: Dictionary = content.get("center_ore_cluster", {}) as Dictionary
	var plans: Array[Dictionary] = []
	for room_index: int in range(rooms.size()):
		var room_rect: Rect2i = rooms[room_index]
		var room_cfg: Dictionary = main_cfg if room_index == 0 else sub_cfg
		var room_kind: String = "main" if room_index == 0 else "sub"
		var door_cells: Array[Vector2i] = _collect_room_door_cells(room_index, corridor_plans)
		var plan: Dictionary = _roll_room_content_plan(
			room_index,
			room_kind,
			room_rect,
			room_cfg,
			center_cluster_cfg if room_index == 0 else {},
			door_cells,
			rng
		)
		plans.append(plan)
	return plans


func _collect_room_door_cells(room_index: int, corridor_plans: Array[Dictionary]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for corridor_plan: Dictionary in corridor_plans:
		if int(corridor_plan.get("from_room", -1)) == room_index:
			cells.append(corridor_plan.get("from_door", Vector2i.ZERO) as Vector2i)
		if int(corridor_plan.get("to_room", -1)) == room_index:
			cells.append(corridor_plan.get("to_door", Vector2i.ZERO) as Vector2i)
	return cells


func _roll_room_content_plan(
	room_index: int,
	room_kind: String,
	room_rect: Rect2i,
	room_cfg: Dictionary,
	center_cluster_cfg: Dictionary,
	door_cells: Array[Vector2i],
	rng: RandomNumberGenerator
) -> Dictionary:
	var none_weight: float = maxf(float(room_cfg.get("none_weight", 0.0)), 0.0)
	var monster_entries: Array = room_cfg.get("monster_entries", []) as Array
	var nest_entries: Array = room_cfg.get("nest_entries", []) as Array
	var monster_weight_total: float = _sum_entry_weights(monster_entries)
	var nest_weight_total: float = _sum_entry_weights(nest_entries)
	var total_weight: float = none_weight + monster_weight_total + nest_weight_total
	var content_kind: String = "none"
	var template_id: String = ""
	if total_weight > 0.0:
		var roll: float = rng.randf() * total_weight
		if roll <= none_weight:
			content_kind = "none"
		elif roll <= none_weight + monster_weight_total:
			content_kind = "monster_pack"
			template_id = _pick_weighted_entry_id(monster_entries, "spawn_template_id", rng)
		else:
			content_kind = "nest"
			template_id = _pick_weighted_entry_id(nest_entries, "nest_template_id", rng)
	var anchor_cell: Vector2i = _resolve_room_content_anchor(
		room_rect,
		door_cells,
		maxi(int(room_cfg.get("min_distance_from_door_cells", 0)), 0),
		maxi(int(center_cluster_cfg.get("avoid_radius_cells", 0)), 0),
		room_kind == "main"
	)
	return {
		"room_index": room_index,
		"room_kind": room_kind,
		"content_kind": content_kind,
		"template_id": template_id,
		"anchor_cell": anchor_cell,
	}


func _sum_entry_weights(entries: Array) -> float:
	var total_weight: float = 0.0
	for entry_value: Variant in entries:
		if not (entry_value is Dictionary):
			continue
		total_weight += maxf(float((entry_value as Dictionary).get("weight", 0.0)), 0.0)
	return total_weight


func _pick_weighted_entry_id(
	entries: Array,
	id_key: String,
	rng: RandomNumberGenerator
) -> String:
	var total_weight: float = _sum_entry_weights(entries)
	if total_weight <= 0.0:
		return ""
	var roll: float = rng.randf() * total_weight
	var cumulative: float = 0.0
	for entry_value: Variant in entries:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value as Dictionary
		cumulative += maxf(float(entry.get("weight", 0.0)), 0.0)
		if roll <= cumulative:
			return str(entry.get(id_key, ""))
	return ""


func _resolve_room_content_anchor(
	room_rect: Rect2i,
	door_cells: Array[Vector2i],
	min_distance_from_doors: int,
	center_cluster_avoid_radius: int,
	avoid_room_center: bool
) -> Vector2i:
	var center_cell: Vector2i = _rect_center_cell(room_rect)
	if _is_valid_room_content_anchor(
		center_cell,
		room_rect,
		door_cells,
		min_distance_from_doors,
		center_cluster_avoid_radius,
		avoid_room_center
	):
		return center_cell
	var candidate_cells: Array[Vector2i] = []
	for y: int in range(room_rect.position.y, room_rect.position.y + room_rect.size.y):
		for x: int in range(room_rect.position.x, room_rect.position.x + room_rect.size.x):
			var candidate: Vector2i = Vector2i(x, y)
			if not _is_valid_room_content_anchor(
				candidate,
				room_rect,
				door_cells,
				min_distance_from_doors,
				center_cluster_avoid_radius,
				avoid_room_center
			):
				continue
			candidate_cells.append(candidate)
	candidate_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(center_cell) < b.distance_squared_to(center_cell)
	)
	return center_cell if candidate_cells.is_empty() else candidate_cells[0]


func _is_valid_room_content_anchor(
	candidate: Vector2i,
	room_rect: Rect2i,
	door_cells: Array[Vector2i],
	min_distance_from_doors: int,
	center_cluster_avoid_radius: int,
	avoid_room_center: bool
) -> bool:
	if not _is_cell_inside_rect(candidate, room_rect):
		return false
	if avoid_room_center and center_cluster_avoid_radius > 0:
		if candidate.distance_to(_rect_center_cell(room_rect)) <= float(center_cluster_avoid_radius):
			return false
	for door_cell: Vector2i in door_cells:
		if candidate.distance_to(door_cell) < float(min_distance_from_doors):
			return false
	return true


func _is_cell_inside_rect(cell: Vector2i, room_rect: Rect2i) -> bool:
	return (
		cell.x >= room_rect.position.x
		and cell.y >= room_rect.position.y
		and cell.x < room_rect.position.x + room_rect.size.x
		and cell.y < room_rect.position.y + room_rect.size.y
	)


func _place_poi_center_cluster(
	map_data: WdcMapGenerationTypes.MapData,
	main_room_rect: Rect2i,
	template_dict: Dictionary,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	var content: Dictionary = template_dict.get("content", {}) as Dictionary
	var center_cluster: Dictionary = content.get("center_ore_cluster", {}) as Dictionary
	if not bool(center_cluster.get("enabled", false)):
		return
	var override_id: String = str(center_cluster.get("cluster_override_id", ""))
	if override_id.is_empty():
		return
	var cluster_template: Dictionary = _find_cluster_override(config, override_id)
	if cluster_template.is_empty():
		return
	_grow_cluster_from_seed(map_data, _rect_center_cell(main_room_rect), config, cluster_template, rng)


func _find_cluster_override(
	config: WdcMapGenerationTypes.MapConfig,
	override_id: String
) -> Dictionary:
	for override_entry: Dictionary in config.mineral_cluster_overrides:
		if str(override_entry.get("id", "")) == override_id:
			return override_entry.duplicate(true)
	return {}


func _try_place_one_poi(
	map_data: WdcMapGenerationTypes.MapData,
	poi_type: int,
	min_distance: float,
	radius: int,
	irregularity: float,
	rng: RandomNumberGenerator
) -> bool:
	var min_x: int = radius
	var max_x: int = map_data.width - 1 - radius
	var min_y: int = radius
	var max_y: int = map_data.height - 1 - radius
	if min_x > max_x or min_y > max_y:
		return false
	var center_x: int = rng.randi_range(min_x, max_x)
	var center_y: int = rng.randi_range(min_y, max_y)
	var center: Vector2 = Vector2(center_x, center_y)
	for existing: Dictionary in map_data.poi_centers:
		var ex: int = existing.get("x", 0) as int
		var ey: int = existing.get("y", 0) as int
		if center.distance_to(Vector2(ex, ey)) < min_distance:
			return false
	var offsets: Array[Vector2i] = _generate_ca_shape(radius, irregularity, rng)
	var world_cells: Array[Vector2i] = []
	for offset: Vector2i in offsets:
		var wx: int = center_x + offset.x
		var wy: int = center_y + offset.y
		if not map_data.is_in_bounds(wx, wy):
			return false
		var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(wx, wy)
		if cell == null or cell.poi_type != WdcMapGenerationTypes.PoiType.NONE:
			return false
		world_cells.append(Vector2i(wx, wy))
	for world_cell: Vector2i in world_cells:
		var target: WdcMapGenerationTypes.CellData = map_data.get_cell(world_cell.x, world_cell.y)
		target.cell_type = WdcMapGenerationTypes.CellType.FLOOR
		target.poi_type = poi_type
		target.is_poi_protected = true
	map_data.poi_centers.append({
		"x": center_x,
		"y": center_y,
		"type": poi_type
	})
	return true


func _generate_ca_shape(radius: int, irregularity: float, rng: RandomNumberGenerator) -> Array[Vector2i]:
	if radius <= 0:
		return [Vector2i.ZERO]
	if irregularity < 0.05:
		return _generate_circle_shape(radius)
	var local_size: int = radius * 2 + 3
	var center: int = local_size / 2
	var alive: Dictionary = {}
	var protected_core_radius: float = maxf(1.0, float(radius) * (1.0 - irregularity * 0.55))
	for ly: int in range(local_size):
		for lx: int in range(local_size):
			var dx: int = lx - center
			var dy: int = ly - center
			var dist: float = sqrt(float(dx * dx + dy * dy))
			if dist > float(radius) + 0.6:
				continue
			var key: String = _key(lx, ly)
			var core_alive: bool = dist <= protected_core_radius
			var noise_band_t: float = inverse_lerp(protected_core_radius, float(radius) + 0.6, dist)
			var noise_keep_chance: float = lerpf(
				1.0 - irregularity * 0.15,
				1.0 - irregularity,
				clampf(noise_band_t, 0.0, 1.0)
			)
			var noise_alive: bool = rng.randf() < noise_keep_chance
			alive[key] = core_alive or noise_alive
	for _iteration: int in range(3):
		var next_alive: Dictionary = {}
		for ly: int in range(local_size):
			for lx: int in range(local_size):
				var dx: int = lx - center
				var dy: int = ly - center
				var dist: float = sqrt(float(dx * dx + dy * dy))
				if dist > float(radius) + 0.8:
					continue
				var n: int = _count_alive_neighbors(alive, lx, ly)
				var now_alive: bool = bool(alive.get(_key(lx, ly), false))
				var become_alive: bool = now_alive
				if n > 4:
					become_alive = true
				elif n < 4:
					become_alive = false
				if dist <= protected_core_radius:
					become_alive = true
				next_alive[_key(lx, ly)] = become_alive
		alive = next_alive
	var offsets: Array[Vector2i] = []
	for ly: int in range(local_size):
		for lx: int in range(local_size):
			if not bool(alive.get(_key(lx, ly), false)):
				continue
			offsets.append(Vector2i(lx - center, ly - center))
	if offsets.is_empty():
		return _generate_circle_shape(radius)
	return offsets


func _generate_circle_shape(radius: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	for y: int in range(-radius, radius + 1):
		for x: int in range(-radius, radius + 1):
			if x * x + y * y <= radius * radius:
				offsets.append(Vector2i(x, y))
	return offsets


func _count_alive_neighbors(alive: Dictionary, x: int, y: int) -> int:
	var count: int = 0
	for oy: int in range(-1, 2):
		for ox: int in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			if bool(alive.get(_key(x + ox, y + oy), false)):
				count += 1
	return count


func _fill_noise(
	map_data: WdcMapGenerationTypes.MapData,
	fill_percent: float,
	rng: RandomNumberGenerator
) -> void:
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell.is_poi_protected:
				continue
			cell.cell_type = (
				WdcMapGenerationTypes.CellType.WALL
				if rng.randf() < fill_percent
				else WdcMapGenerationTypes.CellType.FLOOR
			)


func _smooth_caves(map_data: WdcMapGenerationTypes.MapData, iterations: int) -> void:
	for _iteration: int in range(iterations):
		var next_types: Array[Array] = []
		next_types.resize(map_data.height)
		for y: int in range(map_data.height):
			var row: Array = []
			row.resize(map_data.width)
			for x: int in range(map_data.width):
				var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
				if cell.is_poi_protected:
					row[x] = cell.cell_type
					continue
				var wall_neighbors: int = _count_wall_neighbors(map_data, x, y)
				if wall_neighbors > 4:
					row[x] = WdcMapGenerationTypes.CellType.WALL
				elif wall_neighbors < 4:
					row[x] = WdcMapGenerationTypes.CellType.FLOOR
				else:
					row[x] = cell.cell_type
			next_types[y] = row
		for y: int in range(map_data.height):
			for x: int in range(map_data.width):
				var target_cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
				if target_cell.is_poi_protected:
					continue
				target_cell.cell_type = next_types[y][x] as int


func _count_wall_neighbors(map_data: WdcMapGenerationTypes.MapData, x: int, y: int) -> int:
	var walls: int = 0
	for oy: int in range(-1, 2):
		for ox: int in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var nx: int = x + ox
			var ny: int = y + oy
			if not map_data.is_in_bounds(nx, ny):
				walls += 1
				continue
			var ncell: WdcMapGenerationTypes.CellData = map_data.get_cell(nx, ny)
			if ncell.cell_type == WdcMapGenerationTypes.CellType.WALL:
				walls += 1
	return walls


func _dig_corridors(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	if config.corridor_count <= 0:
		return
	var corridor_steps: int = int(round(maxi(map_data.width, map_data.height) * config.corridor_length))
	corridor_steps = maxi(corridor_steps, 1)
	var radius: int = maxi(0, int(floor(float(config.corridor_width - 1) * 0.5)))
	for _corridor_idx: int in range(config.corridor_count):
		var pos: Vector2i = Vector2i(
			rng.randi_range(0, map_data.width - 1),
			rng.randi_range(0, map_data.height - 1)
		)
		var dir: Vector2i = _random_direction(rng)
		for _step: int in range(corridor_steps):
			if not map_data.is_in_bounds(pos.x, pos.y):
				break
			_carve_disc(map_data, pos, radius)
			if rng.randf() < config.corridor_wobble:
				if rng.randf() < 0.5:
					dir += Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
					dir = _sanitize_direction(dir, rng)
				else:
					var side: int = rng.randi_range(-1, 1)
					if dir.x == 0:
						pos.x += side
					else:
						pos.y += side
			pos += dir
			if (
				pos.x <= 0
				or pos.x >= map_data.width - 1
				or pos.y <= 0
				or pos.y >= map_data.height - 1
			):
				break


func _carve_disc(map_data: WdcMapGenerationTypes.MapData, center: Vector2i, radius: int) -> void:
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			if not map_data.is_in_bounds(x, y):
				continue
			if radius > 0:
				var dx: int = x - center.x
				var dy: int = y - center.y
				if dx * dx + dy * dy > radius * radius:
					continue
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell.is_poi_protected:
				continue
			cell.cell_type = WdcMapGenerationTypes.CellType.FLOOR


func _generate_traces(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	var trace_cfg: Dictionary = {
		WdcMapGenerationTypes.PoiType.LARGE_RUIN: {
			"radius": config.trace_large_radius,
			"density": config.trace_large_density,
			"rays": config.trace_large_rays,
			"twist": config.trace_large_twist
		},
		WdcMapGenerationTypes.PoiType.MEDIUM_BIOME: {
			"radius": config.trace_medium_radius,
			"density": config.trace_medium_density,
			"rays": config.trace_medium_rays,
			"twist": config.trace_medium_twist
		},
		WdcMapGenerationTypes.PoiType.SMALL_ORE: {
			"radius": config.trace_small_radius,
			"density": config.trace_small_density,
			"rays": config.trace_small_rays,
			"twist": config.trace_small_twist
		}
	}
	for poi_center: Dictionary in map_data.poi_centers:
		var poi_type: int = poi_center.get("type", WdcMapGenerationTypes.PoiType.NONE) as int
		if not trace_cfg.has(poi_type):
			continue
		var cfg: Dictionary = trace_cfg[poi_type] as Dictionary
		var radius: float = cfg.get("radius", 0.0) as float
		var density: float = cfg.get("density", 0.0) as float
		var rays: float = cfg.get("rays", 1.0) as float
		var twist: float = cfg.get("twist", 1.0) as float
		var cx: int = poi_center.get("x", 0) as int
		var cy: int = poi_center.get("y", 0) as int
		var int_radius: int = int(ceil(radius))
		for y: int in range(cy - int_radius, cy + int_radius + 1):
			for x: int in range(cx - int_radius, cx + int_radius + 1):
				if not map_data.is_in_bounds(x, y):
					continue
				var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
				if cell.poi_type != WdcMapGenerationTypes.PoiType.NONE:
					continue
				if (
					cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR
					and cell.cell_type != WdcMapGenerationTypes.CellType.WALL
				):
					continue
				if cell.cell_type == WdcMapGenerationTypes.CellType.WALL and cell.has_mineral:
					continue
				if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
					continue
				var dx: float = float(x - cx)
				var dy: float = float(y - cy)
				var dist: float = sqrt(dx * dx + dy * dy)
				if dist <= 0.0 or dist > radius:
					continue
				var t: float = dist / radius
				var angle: float = atan2(dy, dx)
				var wave: float = 0.5 + 0.5 * sin(angle * rays + t * twist * TAU)
				var chance: float = density * (1.0 - t) * (0.6 + wave * 0.4)
				if rng.randf() < chance:
					cell.trace_type = poi_type


func _generate_minerals(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	_clear_all_mineral_cells(map_data)
	if not config.mineral_cluster_types.is_empty():
		_generate_mineral_clusters(map_data, config, rng)
		return
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			if cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
				cell.has_mineral = false
				continue
			var chance: float = config.mineral_base_chance
			if _is_exposed_wall(map_data, x, y):
				chance = config.mineral_exposed_chance
			cell.has_mineral = rng.randf() < chance


func _clear_all_mineral_cells(map_data: WdcMapGenerationTypes.MapData) -> void:
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			cell.has_mineral = false
			if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
				cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.NONE


func _generate_mineral_clusters(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	var placed_seed_cells: Array[Vector2i] = []
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if not _is_valid_global_cluster_seed_cell(cell, config):
				continue
			if _is_cluster_seed_too_close(
				Vector2i(x, y),
				placed_seed_cells,
				config.mineral_min_distance_between_cluster_seeds_cells
			):
				continue
			var chance: float = config.mineral_base_chance
			if _is_exposed_wall(map_data, x, y):
				chance = config.mineral_exposed_chance
			if rng.randf() > chance:
				continue
			var cluster_template: Dictionary = _pick_cluster_template(config.mineral_cluster_types, rng)
			if cluster_template.is_empty():
				continue
			if _grow_cluster_from_seed(map_data, Vector2i(x, y), config, cluster_template, rng) > 0:
				placed_seed_cells.append(Vector2i(x, y))


func _pick_cluster_template(cluster_types: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	var total_weight: float = 0.0
	var eligible_templates: Array[Dictionary] = []
	for cluster_entry: Dictionary in cluster_types:
		if not bool(cluster_entry.get("enabled", true)):
			continue
		if not _is_cluster_template_global_scope(cluster_entry):
			continue
		eligible_templates.append(cluster_entry)
		total_weight += maxf(float(cluster_entry.get("weight", 0.0)), 0.0)
	if total_weight <= 0.0:
		return {}
	var roll: float = rng.randf() * total_weight
	var cumulative: float = 0.0
	for cluster_entry: Dictionary in cluster_types:
		if not bool(cluster_entry.get("enabled", true)):
			continue
		if not _is_cluster_template_global_scope(cluster_entry):
			continue
		cumulative += maxf(float(cluster_entry.get("weight", 0.0)), 0.0)
		if roll <= cumulative:
			return cluster_entry.duplicate(true)
	return (
		eligible_templates[eligible_templates.size() - 1] as Dictionary
	).duplicate(true)


func _is_cluster_template_global_scope(cluster_template: Dictionary) -> bool:
	var spawn_scope: String = str(cluster_template.get("spawn_scope", "global"))
	return spawn_scope.begins_with("global")


func _grow_cluster_from_seed(
	map_data: WdcMapGenerationTypes.MapData,
	seed_cell: Vector2i,
	config: WdcMapGenerationTypes.MapConfig,
	cluster_template: Dictionary,
	rng: RandomNumberGenerator
) -> int:
	var min_size: int = maxi(int(cluster_template.get("min_cluster_size", 1)), 1)
	var max_size: int = maxi(int(cluster_template.get("max_cluster_size", min_size)), min_size)
	var target_size: int = rng.randi_range(min_size, max_size)
	var generated_cells: Array[Vector2i] = []
	if not _place_cluster_cell(map_data, seed_cell, cluster_template):
		return 0
	generated_cells.append(seed_cell)
	while generated_cells.size() < target_size:
		var candidates_by_key: Dictionary = {}
		for generated_cell: Vector2i in generated_cells:
			for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var candidate: Vector2i = generated_cell + dir
				var candidate_key: String = _key(candidate.x, candidate.y)
				if candidates_by_key.has(candidate_key):
					continue
				if not _is_valid_cluster_candidate(map_data, candidate, config, cluster_template):
					continue
				candidates_by_key[candidate_key] = candidate
		if candidates_by_key.is_empty():
			break
		var candidate_cells: Array[Vector2i] = []
		for candidate_value: Variant in candidates_by_key.values():
			if candidate_value is Vector2i:
				candidate_cells.append(candidate_value as Vector2i)
		_shuffle_vector2i_array(candidate_cells, rng)
		var generated_this_round: bool = false
		for candidate_cell: Vector2i in candidate_cells:
			if generated_cells.size() >= target_size:
				break
			if rng.randf() > clampf(float(cluster_template.get("spawn_probability", 0.0)), 0.0, 1.0):
				continue
			if _place_cluster_cell(map_data, candidate_cell, cluster_template):
				generated_cells.append(candidate_cell)
				generated_this_round = true
		if not generated_this_round:
			break
	return generated_cells.size()


func _is_valid_global_cluster_seed_cell(
	cell: WdcMapGenerationTypes.CellData,
	config: WdcMapGenerationTypes.MapConfig
) -> bool:
	if cell == null:
		return false
	if cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
		return false
	if cell.has_mineral or cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
		return false
	if not config.mineral_allow_clusters_inside_poi_rooms and cell.poi_type != WdcMapGenerationTypes.PoiType.NONE:
		return false
	return true


func _is_cluster_seed_too_close(
	candidate: Vector2i,
	placed_seed_cells: Array[Vector2i],
	min_distance_cells: int
) -> bool:
	if min_distance_cells <= 0:
		return false
	for existing_seed: Vector2i in placed_seed_cells:
		if existing_seed.distance_to(candidate) < float(min_distance_cells):
			return true
	return false


func _is_valid_cluster_candidate(
	map_data: WdcMapGenerationTypes.MapData,
	candidate: Vector2i,
	config: WdcMapGenerationTypes.MapConfig,
	cluster_template: Dictionary
) -> bool:
	if not map_data.is_in_bounds(candidate.x, candidate.y):
		return false
	var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(candidate.x, candidate.y)
	if cell == null:
		return false
	if cell.has_mineral or cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
		return false
	if not config.mineral_allow_clusters_inside_poi_rooms and cell.poi_type != WdcMapGenerationTypes.PoiType.NONE:
		return false
	if bool(cluster_template.get("require_stone", true)):
		return cell.cell_type == WdcMapGenerationTypes.CellType.WALL
	return (
		cell.cell_type == WdcMapGenerationTypes.CellType.WALL
		or cell.cell_type == WdcMapGenerationTypes.CellType.FLOOR
	)


func _place_cluster_cell(
	map_data: WdcMapGenerationTypes.MapData,
	target_cell: Vector2i,
	cluster_template: Dictionary
) -> bool:
	if not map_data.is_in_bounds(target_cell.x, target_cell.y):
		return false
	var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(target_cell.x, target_cell.y)
	if cell == null or cell.has_mineral or cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
		return false
	var tile_type_id: String = str(cluster_template.get("tile_type_id", ""))
	cell.cell_type = WdcMapGenerationTypes.CellType.WALL
	cell.has_mineral = false
	cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.NONE
	match tile_type_id:
		"rare_mineral_wall":
			cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.RARE_MINERAL
		"turquoise_ore":
			cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.TURQUOISE
		"amethyst_ore":
			cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.AMETHYST
		"gold_block":
			cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.GOLD
		_:
			cell.has_mineral = true
	return true


func _shuffle_vector2i_array(cells: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for index: int in range(cells.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var temp: Vector2i = cells[index]
		cells[index] = cells[swap_index]
		cells[swap_index] = temp


func _generate_poi_special_blocks(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	var cells_by_poi_type: Dictionary = {
		WdcMapGenerationTypes.PoiType.LARGE_RUIN: [],
		WdcMapGenerationTypes.PoiType.MEDIUM_BIOME: [],
		WdcMapGenerationTypes.PoiType.SMALL_ORE: []
	}
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null or cell.poi_type == WdcMapGenerationTypes.PoiType.NONE:
				continue
			var cells: Array = cells_by_poi_type.get(cell.poi_type, [])
			cells.append(cell)
			cells_by_poi_type[cell.poi_type] = cells
	_assign_special_blocks_for_poi_cells(
		map_data,
		cells_by_poi_type.get(WdcMapGenerationTypes.PoiType.SMALL_ORE, []),
		WdcMapGenerationTypes.PoiType.SMALL_ORE,
		WdcMapGenerationTypes.SpecialBlockType.TURQUOISE,
		config.small_poi_special_block_count,
		rng
	)
	_assign_special_blocks_for_poi_cells(
		map_data,
		cells_by_poi_type.get(WdcMapGenerationTypes.PoiType.MEDIUM_BIOME, []),
		WdcMapGenerationTypes.PoiType.MEDIUM_BIOME,
		WdcMapGenerationTypes.SpecialBlockType.AMETHYST,
		config.medium_poi_special_block_count,
		rng
	)
	_assign_special_blocks_for_poi_cells(
		map_data,
		cells_by_poi_type.get(WdcMapGenerationTypes.PoiType.LARGE_RUIN, []),
		WdcMapGenerationTypes.PoiType.LARGE_RUIN,
		WdcMapGenerationTypes.SpecialBlockType.GOLD,
		config.large_poi_special_block_count,
		rng
	)


func _assign_special_blocks_for_poi_cells(
	map_data: WdcMapGenerationTypes.MapData,
	candidate_cells: Array,
	poi_type: int,
	special_block_type: int,
	special_block_count_per_poi: int,
	rng: RandomNumberGenerator
) -> void:
	if candidate_cells.is_empty() or special_block_count_per_poi <= 0:
		return
	for poi_center: Dictionary in map_data.poi_centers:
		if int(poi_center.get("type", WdcMapGenerationTypes.PoiType.NONE)) != poi_type:
			continue
		var center: Vector2i = Vector2i(
			int(poi_center.get("x", 0)),
			int(poi_center.get("y", 0))
		)
		for _special_index: int in range(special_block_count_per_poi):
			var chosen_cell: WdcMapGenerationTypes.CellData = _pick_special_block_cell_for_poi(
				candidate_cells,
				center,
				rng
			)
			if chosen_cell == null:
				break
			chosen_cell.cell_type = WdcMapGenerationTypes.CellType.WALL
			chosen_cell.has_mineral = false
			chosen_cell.special_block_type = special_block_type


func _pick_special_block_cell_for_poi(
	candidate_cells: Array,
	center: Vector2i,
	rng: RandomNumberGenerator
) -> WdcMapGenerationTypes.CellData:
	var best_cell: WdcMapGenerationTypes.CellData = null
	var best_distance_sq: float = INF
	for cell_value: Variant in candidate_cells:
		var cell: WdcMapGenerationTypes.CellData = cell_value as WdcMapGenerationTypes.CellData
		if cell == null or cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
			continue
		var distance_sq: float = Vector2(float(cell.x - center.x), float(cell.y - center.y)).length_squared()
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_cell = cell
		elif is_equal_approx(distance_sq, best_distance_sq) and rng.randf() < 0.5:
			best_cell = cell
	return best_cell


func _is_exposed_wall(map_data: WdcMapGenerationTypes.MapData, x: int, y: int) -> bool:
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for dir: Vector2i in dirs:
		var nx: int = x + dir.x
		var ny: int = y + dir.y
		if not map_data.is_in_bounds(nx, ny):
			continue
		var neighbor: WdcMapGenerationTypes.CellData = map_data.get_cell(nx, ny)
		if neighbor != null and neighbor.cell_type == WdcMapGenerationTypes.CellType.FLOOR:
			return true
	return false


func _recalculate_stats(map_data: WdcMapGenerationTypes.MapData) -> void:
	map_data.total_floor = 0
	map_data.large_pois = 0
	map_data.medium_pois = 0
	map_data.small_pois = 0
	for poi_center: Dictionary in map_data.poi_centers:
		var poi_type: int = poi_center.get("type", WdcMapGenerationTypes.PoiType.NONE) as int
		match poi_type:
			WdcMapGenerationTypes.PoiType.LARGE_RUIN:
				map_data.large_pois += 1
			WdcMapGenerationTypes.PoiType.MEDIUM_BIOME:
				map_data.medium_pois += 1
			WdcMapGenerationTypes.PoiType.SMALL_ORE:
				map_data.small_pois += 1
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell.cell_type == WdcMapGenerationTypes.CellType.FLOOR:
				map_data.total_floor += 1


const TRAP_SPIKE_PATCH_COUNT: int = 4
const TRAP_SPIKE_PATCH_MIN_SIZE: int = 2
const TRAP_SPIKE_PATCH_MAX_SIZE: int = 4
const TRAP_SPIKE_PATCH_SPACING: int = 4


func _generate_environmental_traps(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	var high_density: bool = config.traps_high_density
	_place_spike_patches(
		map_data,
		rng,
		_resolve_trap_count(
			config.traps_spike_max_count,
			TRAP_SPIKE_PATCH_COUNT,
			TRAP_SPIKE_PATCH_COUNT * 4 if high_density else TRAP_SPIKE_PATCH_COUNT
		),
		_resolve_trap_spacing(
			config.traps_spike_min_spacing,
			TRAP_SPIKE_PATCH_SPACING,
			max(2, TRAP_SPIKE_PATCH_SPACING - 2) if high_density else TRAP_SPIKE_PATCH_SPACING
		)
	)
	_place_explosive_ore_chains(
		map_data,
		rng,
		_resolve_trap_count(
			config.traps_explosive_chain_count,
			TRAP_EXPLOSIVE_ORE_CHAIN_COUNT,
			TRAP_EXPLOSIVE_ORE_CHAIN_COUNT * 4 if high_density else TRAP_EXPLOSIVE_ORE_CHAIN_COUNT
		),
		_resolve_trap_spacing(
			config.traps_explosive_chain_spacing,
			TRAP_EXPLOSIVE_ORE_CHAIN_SPACING,
			max(2, TRAP_EXPLOSIVE_ORE_CHAIN_SPACING - 4) if high_density else TRAP_EXPLOSIVE_ORE_CHAIN_SPACING
		)
	)
	_place_arrow_slits(
		map_data,
		rng,
		_resolve_trap_count(
			config.traps_arrow_slit_max_count,
			TRAP_ARROW_SLIT_MAX_COUNT,
			TRAP_ARROW_SLIT_MAX_COUNT * 3 if high_density else TRAP_ARROW_SLIT_MAX_COUNT
		),
		_resolve_trap_spacing(
			config.traps_arrow_slit_min_spacing,
			TRAP_ARROW_SLIT_MIN_SPACING,
			max(1, TRAP_ARROW_SLIT_MIN_SPACING - 1) if high_density else TRAP_ARROW_SLIT_MIN_SPACING
		)
	)
	_place_mimic_ores(
		map_data,
		rng,
		_resolve_trap_count(
			config.traps_mimic_ore_max_count,
			TRAP_MIMIC_ORE_MAX_COUNT,
			TRAP_MIMIC_ORE_MAX_COUNT * 3 if high_density else TRAP_MIMIC_ORE_MAX_COUNT
		),
		_resolve_trap_spacing(
			config.traps_mimic_ore_min_spacing,
			TRAP_MIMIC_ORE_MIN_SPACING,
			max(2, TRAP_MIMIC_ORE_MIN_SPACING - 2) if high_density else TRAP_MIMIC_ORE_MIN_SPACING
		)
	)
	_place_pressure_plates(
		map_data,
		rng,
		_resolve_trap_count(
			config.traps_pressure_plate_max_count,
			TRAP_PRESSURE_PLATE_MAX_COUNT,
			TRAP_PRESSURE_PLATE_MAX_COUNT * 4 if high_density else TRAP_PRESSURE_PLATE_MAX_COUNT
		),
		_resolve_trap_spacing(
			config.traps_pressure_plate_min_spacing,
			TRAP_PRESSURE_PLATE_MIN_SPACING,
			max(2, TRAP_PRESSURE_PLATE_MIN_SPACING - 2) if high_density else TRAP_PRESSURE_PLATE_MIN_SPACING
		)
	)


# 解析陷阱数量参数：显式 >= 0 时用显式值；否则用 fallback（高密度模式或默认）。
func _resolve_trap_count(explicit_value: int, _default_value: int, fallback_value: int) -> int:
	if explicit_value >= 0:
		return explicit_value
	return fallback_value


func _resolve_trap_spacing(explicit_value: int, _default_value: int, fallback_value: int) -> int:
	if explicit_value >= 0:
		return explicit_value
	return fallback_value


func _place_spike_patches(
	map_data: WdcMapGenerationTypes.MapData,
	rng: RandomNumberGenerator,
	max_count: int = TRAP_SPIKE_PATCH_COUNT,
	spacing: int = TRAP_SPIKE_PATCH_SPACING
) -> void:
	var floor_cells: Array[Vector2i] = []
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			if cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR:
				continue
			if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
				continue
			floor_cells.append(Vector2i(x, y))
	if floor_cells.is_empty():
		return
	_shuffle_vector2i_array(floor_cells, rng)
	var placed_cells: Array[Vector2i] = []
	var patches_placed: int = 0
	for seed_cell: Vector2i in floor_cells:
		if patches_placed >= max_count:
			break
		if _is_too_close_to_existing_spike(seed_cell, placed_cells, spacing):
			continue
		var patch_size: int = rng.randi_range(TRAP_SPIKE_PATCH_MIN_SIZE, TRAP_SPIKE_PATCH_MAX_SIZE)
		var patch_cells: Array[Vector2i] = _grow_spike_patch(map_data, seed_cell, patch_size, rng)
		if patch_cells.size() < TRAP_SPIKE_PATCH_MIN_SIZE:
			continue
		for patch_cell: Vector2i in patch_cells:
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(patch_cell.x, patch_cell.y)
			cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.SPIKE
			placed_cells.append(patch_cell)
			map_data.trap_sites.append({
				"trap_kind": "spike",
				"cell": _vector2i_to_dict(patch_cell),
				"metadata": {}
			})
		patches_placed += 1


func _grow_spike_patch(
	map_data: WdcMapGenerationTypes.MapData,
	seed_cell: Vector2i,
	target_size: int,
	rng: RandomNumberGenerator
) -> Array[Vector2i]:
	var patch_cells: Array[Vector2i] = [seed_cell]
	var visited: Dictionary = {}
	visited[_key(seed_cell.x, seed_cell.y)] = true
	var frontier: Array[Vector2i] = [seed_cell]
	while patch_cells.size() < target_size and not frontier.is_empty():
		var pivot_index: int = rng.randi_range(0, frontier.size() - 1)
		var pivot: Vector2i = frontier[pivot_index]
		frontier.remove_at(pivot_index)
		var directions: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
		]
		_shuffle_vector2i_array(directions, rng)
		for direction: Vector2i in directions:
			if patch_cells.size() >= target_size:
				break
			var neighbor: Vector2i = pivot + direction
			var neighbor_key: String = _key(neighbor.x, neighbor.y)
			if visited.has(neighbor_key):
				continue
			visited[neighbor_key] = true
			if not map_data.is_in_bounds(neighbor.x, neighbor.y):
				continue
			var neighbor_cell: WdcMapGenerationTypes.CellData = map_data.get_cell(neighbor.x, neighbor.y)
			if neighbor_cell == null:
				continue
			if neighbor_cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR:
				continue
			if neighbor_cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
				continue
			patch_cells.append(neighbor)
			frontier.append(neighbor)
	return patch_cells


func _is_too_close_to_existing_spike(
	candidate: Vector2i,
	placed_cells: Array[Vector2i],
	spacing: int
) -> bool:
	for placed: Vector2i in placed_cells:
		var dx: int = absi(candidate.x - placed.x)
		var dy: int = absi(candidate.y - placed.y)
		if dx + dy < spacing:
			return true
	return false


const TRAP_EXPLOSIVE_ORE_CHAIN_COUNT: int = 3
const TRAP_EXPLOSIVE_ORE_CHAIN_LENGTH: int = 3
const TRAP_EXPLOSIVE_ORE_CHAIN_SPACING: int = 8


func _place_explosive_ore_chains(
	map_data: WdcMapGenerationTypes.MapData,
	rng: RandomNumberGenerator,
	max_count: int = TRAP_EXPLOSIVE_ORE_CHAIN_COUNT,
	spacing: int = TRAP_EXPLOSIVE_ORE_CHAIN_SPACING
) -> void:
	var wall_cells: Array[Vector2i] = []
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			if cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
				continue
			if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
				continue
			wall_cells.append(Vector2i(x, y))
	if wall_cells.is_empty():
		return
	_shuffle_vector2i_array(wall_cells, rng)
	var placed_chain_anchor_cells: Array[Vector2i] = []
	var chains_placed: int = 0
	for seed_cell: Vector2i in wall_cells:
		if chains_placed >= max_count:
			break
		if _is_too_close_to_existing_chain(
			seed_cell,
			placed_chain_anchor_cells,
			spacing
		):
			continue
		var chain_cells: Array[Vector2i] = _try_grow_explosive_ore_chain(
			map_data,
			seed_cell,
			TRAP_EXPLOSIVE_ORE_CHAIN_LENGTH
		)
		if chain_cells.size() < TRAP_EXPLOSIVE_ORE_CHAIN_LENGTH:
			continue
		var chain_node_dicts: Array = []
		for chain_cell: Vector2i in chain_cells:
			var node_cell: WdcMapGenerationTypes.CellData = map_data.get_cell(chain_cell.x, chain_cell.y)
			node_cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.EXPLOSIVE_ORE
			node_cell.has_mineral = false
			placed_chain_anchor_cells.append(chain_cell)
			chain_node_dicts.append(_vector2i_to_dict(chain_cell))
		map_data.trap_sites.append({
			"trap_kind": "explosive_ore_chain",
			"nodes": chain_node_dicts,
			"metadata": {}
		})
		chains_placed += 1


func _try_grow_explosive_ore_chain(
	map_data: WdcMapGenerationTypes.MapData,
	seed_cell: Vector2i,
	target_length: int
) -> Array[Vector2i]:
	var direction: Vector2i = Vector2i.RIGHT
	var chain_cells: Array[Vector2i] = []
	for step: int in range(target_length):
		var candidate: Vector2i = seed_cell + direction * step
		if not map_data.is_in_bounds(candidate.x, candidate.y):
			return []
		var candidate_cell: WdcMapGenerationTypes.CellData = map_data.get_cell(candidate.x, candidate.y)
		if candidate_cell == null:
			return []
		if candidate_cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
			return []
		if candidate_cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
			return []
		chain_cells.append(candidate)
	return chain_cells


func _is_too_close_to_existing_chain(
	candidate: Vector2i,
	placed_cells: Array[Vector2i],
	spacing: int
) -> bool:
	for placed: Vector2i in placed_cells:
		var dx: int = absi(candidate.x - placed.x)
		var dy: int = absi(candidate.y - placed.y)
		if dx + dy < spacing:
			return true
	return false


const TRAP_ARROW_SLIT_MAX_COUNT: int = 6
const TRAP_ARROW_SLIT_MIN_SPACING: int = 3
const TRAP_ARROW_SLIT_REQUIRED_FORWARD_CLEAR: int = 3

const TRAP_MIMIC_ORE_MAX_COUNT: int = 5
const TRAP_MIMIC_ORE_MIN_SPACING: int = 4
const TRAP_MIMIC_ORE_MONSTER_ID: String = "ghoul"

const TRAP_PRESSURE_PLATE_MAX_COUNT: int = 4
const TRAP_PRESSURE_PLATE_MIN_SPACING: int = 4


func _place_pressure_plates(
	map_data: WdcMapGenerationTypes.MapData,
	rng: RandomNumberGenerator,
	max_count: int = TRAP_PRESSURE_PLATE_MAX_COUNT,
	spacing: int = TRAP_PRESSURE_PLATE_MIN_SPACING
) -> void:
	var floor_cells: Array[Vector2i] = []
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			if cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR:
				continue
			if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
				continue
			floor_cells.append(Vector2i(x, y))
	if floor_cells.is_empty():
		return
	_shuffle_vector2i_array(floor_cells, rng)
	var placed_cells: Array[Vector2i] = []
	var plates_placed: int = 0
	for candidate_cell: Vector2i in floor_cells:
		if plates_placed >= max_count:
			break
		if _is_too_close_to_existing_chain(
			candidate_cell,
			placed_cells,
			spacing
		):
			continue
		var cell_data: WdcMapGenerationTypes.CellData = map_data.get_cell(
			candidate_cell.x,
			candidate_cell.y
		)
		cell_data.special_block_type = WdcMapGenerationTypes.SpecialBlockType.PRESSURE_PLATE
		placed_cells.append(candidate_cell)
		map_data.trap_sites.append({
			"trap_kind": "pressure_plate",
			"cell": _vector2i_to_dict(candidate_cell),
			"metadata": {}
		})
		plates_placed += 1


func _place_mimic_ores(
	map_data: WdcMapGenerationTypes.MapData,
	rng: RandomNumberGenerator,
	max_count: int = TRAP_MIMIC_ORE_MAX_COUNT,
	spacing: int = TRAP_MIMIC_ORE_MIN_SPACING
) -> void:
	var mineral_cells: Array[Vector2i] = []
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			if cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
				continue
			if not cell.has_mineral:
				continue
			if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
				continue
			mineral_cells.append(Vector2i(x, y))
	if mineral_cells.is_empty():
		return
	_shuffle_vector2i_array(mineral_cells, rng)
	var placed_cells: Array[Vector2i] = []
	var mimics_placed: int = 0
	for candidate_cell: Vector2i in mineral_cells:
		if mimics_placed >= max_count:
			break
		if _is_too_close_to_existing_chain(
			candidate_cell,
			placed_cells,
			spacing
		):
			continue
		var variant: String = "explosive" if (mimics_placed % 2) == 0 else "mimic_monster"
		placed_cells.append(candidate_cell)
		var metadata: Dictionary = {"variant": variant}
		if variant == "mimic_monster":
			metadata["monster_id"] = TRAP_MIMIC_ORE_MONSTER_ID
		map_data.trap_sites.append({
			"trap_kind": "mimic_ore",
			"cell": _vector2i_to_dict(candidate_cell),
			"metadata": metadata
		})
		mimics_placed += 1


func _place_arrow_slits(
	map_data: WdcMapGenerationTypes.MapData,
	rng: RandomNumberGenerator,
	max_count: int = TRAP_ARROW_SLIT_MAX_COUNT,
	spacing: int = TRAP_ARROW_SLIT_MIN_SPACING
) -> void:
	var poi_wall_cells: Array[Vector2i] = []
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.POI_WALL:
				continue
			poi_wall_cells.append(Vector2i(x, y))
	if poi_wall_cells.is_empty():
		return
	_shuffle_vector2i_array(poi_wall_cells, rng)
	var placed_cells: Array[Vector2i] = []
	var slits_placed: int = 0
	for candidate_cell: Vector2i in poi_wall_cells:
		if slits_placed >= max_count:
			break
		if _is_too_close_to_existing_chain(
			candidate_cell,
			placed_cells,
			spacing
		):
			continue
		var facing_direction: Vector2i = _resolve_arrow_slit_facing(map_data, candidate_cell)
		if facing_direction == Vector2i.ZERO:
			continue
		var cell_data: WdcMapGenerationTypes.CellData = map_data.get_cell(
			candidate_cell.x,
			candidate_cell.y
		)
		cell_data.special_block_type = WdcMapGenerationTypes.SpecialBlockType.ARROW_SLIT
		placed_cells.append(candidate_cell)
		map_data.trap_sites.append({
			"trap_kind": "arrow_slit",
			"cell": _vector2i_to_dict(candidate_cell),
			"metadata": {
				"facing_x": facing_direction.x,
				"facing_y": facing_direction.y
			}
		})
		slits_placed += 1


func _resolve_arrow_slit_facing(
	map_data: WdcMapGenerationTypes.MapData,
	candidate_cell: Vector2i
) -> Vector2i:
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
	]
	var empty_directions: Array[Vector2i] = []
	for direction: Vector2i in directions:
		var neighbor: Vector2i = candidate_cell + direction
		if not map_data.is_in_bounds(neighbor.x, neighbor.y):
			continue
		var neighbor_cell: WdcMapGenerationTypes.CellData = map_data.get_cell(neighbor.x, neighbor.y)
		if neighbor_cell == null:
			continue
		if neighbor_cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR:
			continue
		if neighbor_cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
			continue
		empty_directions.append(direction)
	if empty_directions.size() != 1:
		return Vector2i.ZERO
	var facing: Vector2i = empty_directions[0]
	for step: int in range(1, TRAP_ARROW_SLIT_REQUIRED_FORWARD_CLEAR + 1):
		var probe: Vector2i = candidate_cell + facing * step
		if not map_data.is_in_bounds(probe.x, probe.y):
			return Vector2i.ZERO
		var probe_cell: WdcMapGenerationTypes.CellData = map_data.get_cell(probe.x, probe.y)
		if probe_cell == null:
			return Vector2i.ZERO
		if probe_cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR:
			return Vector2i.ZERO
		if probe_cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
			return Vector2i.ZERO
	return facing


func _random_direction(rng: RandomNumberGenerator) -> Vector2i:
	return _sanitize_direction(Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1)), rng)


func _sanitize_direction(dir: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var sx: int = signi(dir.x)
	var sy: int = signi(dir.y)
	if sx == 0 and sy == 0:
		if rng.randf() < 0.5:
			sx = 1 if rng.randf() < 0.5 else -1
		else:
			sy = 1 if rng.randf() < 0.5 else -1
	return Vector2i(sx, sy)


func _key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


func _build_server_tile_matrix(map_data: WdcMapGenerationTypes.MapData) -> Array[Array]:
	var matrix: Array[Array] = []
	matrix.resize(map_data.height)
	for y: int in range(map_data.height):
		var row: Array = []
		row.resize(map_data.width)
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			row[x] = _encode_server_tile(cell)
		matrix[y] = row
	return matrix


func _encode_server_tile(cell: WdcMapGenerationTypes.CellData) -> int:
	if cell == null:
		return WdcMapGenerationTypes.ServerTileType.WALL
	match cell.special_block_type:
		WdcMapGenerationTypes.SpecialBlockType.TURQUOISE:
			return WdcMapGenerationTypes.ServerTileType.TURQUOISE_ORE
		WdcMapGenerationTypes.SpecialBlockType.AMETHYST:
			return WdcMapGenerationTypes.ServerTileType.AMETHYST_ORE
		WdcMapGenerationTypes.SpecialBlockType.GOLD:
			return WdcMapGenerationTypes.ServerTileType.GOLD_BLOCK
	if cell.has_mineral:
		return WdcMapGenerationTypes.ServerTileType.MINERAL_WALL
	if cell.cell_type == WdcMapGenerationTypes.CellType.FLOOR:
		return WdcMapGenerationTypes.ServerTileType.EMPTY
	return WdcMapGenerationTypes.ServerTileType.WALL


func _generate_player_spawn_points(
	map_data: WdcMapGenerationTypes.MapData,
	rng: RandomNumberGenerator,
	target_count: int
) -> Array[Dictionary]:
	var floor_cells: Array[Vector2i] = []
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell != null and cell.cell_type == WdcMapGenerationTypes.CellType.FLOOR:
				floor_cells.append(Vector2i(x, y))
	var spawn_points: Array[Dictionary] = []
	if floor_cells.is_empty():
		return spawn_points
	var needed: int = mini(target_count, floor_cells.size())
	for _idx: int in range(needed):
		var pick_index: int = rng.randi_range(0, floor_cells.size() - 1)
		var picked: Vector2i = floor_cells[pick_index]
		spawn_points.append({
			"x": picked.x,
			"y": picked.y
		})
		floor_cells.remove_at(pick_index)
	return spawn_points

