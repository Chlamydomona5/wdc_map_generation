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
		return copied


class MapConfig:
	extends RefCounted

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


class MapData:
	extends RefCounted

	var width: int = 0
	var height: int = 0
	var grid: Array[Array] = []
	var poi_centers: Array[Dictionary] = []
	var poi_instances: Array[Dictionary] = []
	var monster_sites: Array[Dictionary] = []
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
		for monster_site: Dictionary in monster_sites:
			copied.monster_sites.append(monster_site.duplicate(true))
		for trap_site: Dictionary in trap_sites:
			copied.trap_sites.append(trap_site.duplicate(true))
		copied.total_floor = total_floor
		copied.large_pois = large_pois
		copied.medium_pois = medium_pois
		copied.small_pois = small_pois
		return copied


class MapServerPayload:
	extends RefCounted

	var width: int = 0
	var height: int = 0
	var cell_size_m: float = 1.0
	var resolved_seed: int = 0
	var revision: int = 0
	var tile_matrix: Array[Array] = []
	var player_spawn_points: Array[Dictionary] = []

	func to_dict() -> Dictionary:
		return {
			"width": width,
			"height": height,
			"cell_size_m": cell_size_m,
			"resolved_seed": resolved_seed,
			"revision": revision,
			"tile_matrix": tile_matrix,
			"player_spawn_points": player_spawn_points
		}


static func server_payload_from_variant(payload_value: Variant) -> MapServerPayload:
	var payload: MapServerPayload = MapServerPayload.new()
	if payload_value is MapServerPayload:
		var source_payload: MapServerPayload = payload_value as MapServerPayload
		payload.width = source_payload.width
		payload.height = source_payload.height
		payload.cell_size_m = source_payload.cell_size_m
		payload.resolved_seed = source_payload.resolved_seed
		payload.revision = source_payload.revision
		for row_value: Variant in source_payload.tile_matrix:
			if not (row_value is Array):
				continue
			var source_row: Array = row_value as Array
			var row_copy: Array = []
			for tile_value: Variant in source_row:
				row_copy.append(int(tile_value))
			payload.tile_matrix.append(row_copy)
		for spawn_point_value: Variant in source_payload.player_spawn_points:
			if spawn_point_value is Dictionary:
				payload.player_spawn_points.append((spawn_point_value as Dictionary).duplicate(true))
		return payload
	if not (payload_value is Dictionary):
		return payload
	var payload_dict: Dictionary = (payload_value as Dictionary).duplicate(true)
	payload.width = int(payload_dict.get("width", 0))
	payload.height = int(payload_dict.get("height", 0))
	payload.cell_size_m = maxf(float(payload_dict.get("cell_size_m", 1.0)), 0.1)
	payload.resolved_seed = int(payload_dict.get("resolved_seed", 0))
	payload.revision = int(payload_dict.get("revision", 0))
	var tile_matrix_value: Variant = payload_dict.get("tile_matrix", [])
	if tile_matrix_value is Array:
		var tile_matrix: Array = tile_matrix_value as Array
		for row_value: Variant in tile_matrix:
			if not (row_value is Array):
				continue
			var source_row: Array = row_value as Array
			var row_copy: Array = []
			for tile_value: Variant in source_row:
				row_copy.append(int(tile_value))
			payload.tile_matrix.append(row_copy)
	var spawn_points_value: Variant = payload_dict.get("player_spawn_points", [])
	if spawn_points_value is Array:
		var spawn_points: Array = spawn_points_value as Array
		for spawn_point_value: Variant in spawn_points:
			if spawn_point_value is Dictionary:
				payload.player_spawn_points.append((spawn_point_value as Dictionary).duplicate(true))
	return payload


static func map_data_from_server_payload(payload: MapServerPayload) -> MapData:
	if payload == null:
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
	revision: int
) -> MapServerPayload:
	var payload: MapServerPayload = MapServerPayload.new()
	if map_data == null:
		return payload
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
	for spawn_cell: Vector2i in spawn_cells:
		payload.player_spawn_points.append({
			"x": spawn_cell.x,
			"y": spawn_cell.y
		})
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

