## 文件职责：`GeneratedMapTileRules` 负责 generated map tile 的共享耐久规则。
## 边界约束：这里只描述 tile durability 语义，不依赖具体 runtime 节点或 world object 生成。

class_name WdcMapGenerationTileRules
extends RefCounted

const WdcMapGenerationTypes = preload("generated_map_types.gd")


static func get_tile_max_hit_points(tile_type: int) -> int:
	match tile_type:
		WdcMapGenerationTypes.ServerTileType.MINERAL_WALL:
			return 2
		WdcMapGenerationTypes.ServerTileType.RARE_MINERAL_WALL:
			return 3
		WdcMapGenerationTypes.ServerTileType.TURQUOISE_ORE:
			return 3
		WdcMapGenerationTypes.ServerTileType.AMETHYST_ORE:
			return 4
		WdcMapGenerationTypes.ServerTileType.GOLD_BLOCK:
			return 5
		WdcMapGenerationTypes.ServerTileType.POI_WALL:
			return 2
		WdcMapGenerationTypes.ServerTileType.SPIKE_TILE:
			return 2
		WdcMapGenerationTypes.ServerTileType.EXPLOSIVE_ORE_TILE:
			return 2
		WdcMapGenerationTypes.ServerTileType.ARROW_SLIT_TILE:
			return 1
		WdcMapGenerationTypes.ServerTileType.PRESSURE_PLATE_TILE:
			return 1
		WdcMapGenerationTypes.ServerTileType.EMPTY:
			return 0
		_:
			return 1


static func is_tile_fog_blocker(tile_type: int) -> bool:
	if tile_type == WdcMapGenerationTypes.ServerTileType.EMPTY:
		return false
	if tile_type == WdcMapGenerationTypes.ServerTileType.SPIKE_TILE:
		return false
	if tile_type == WdcMapGenerationTypes.ServerTileType.PRESSURE_PLATE_TILE:
		return false
	return true


static func refresh_map_runtime_state(map_data: RefCounted) -> void:
	if map_data == null:
		return
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			refresh_cell_runtime_state(map_data.get_cell(x, y))


static func refresh_cell_runtime_state(cell: RefCounted) -> void:
	if cell == null:
		return
	var tile_type: int = _encode_server_tile(cell)
	var max_hit_points: int = _resolve_cell_max_hit_points(cell, tile_type)
	cell.max_hit_points = max_hit_points
	if max_hit_points <= 0:
		cell.current_hit_points = 0
		cell.durability_tile_type = tile_type
		return
	if cell.durability_tile_type != tile_type:
		cell.current_hit_points = max_hit_points
		cell.durability_tile_type = tile_type
		return
	cell.current_hit_points = clampi(cell.current_hit_points, 1, max_hit_points)


static func get_cell_current_hit_points(cell: RefCounted) -> int:
	if cell == null:
		return 0
	refresh_cell_runtime_state(cell)
	return cell.current_hit_points


static func get_cell_max_hit_points(cell: RefCounted) -> int:
	if cell == null:
		return 0
	refresh_cell_runtime_state(cell)
	return cell.max_hit_points


static func is_cell_fog_blocker(cell: RefCounted) -> bool:
	if cell == null:
		return true
	return is_tile_fog_blocker(_encode_server_tile(cell))


static func _encode_server_tile(cell: RefCounted) -> int:
	if cell == null:
		return WdcMapGenerationTypes.ServerTileType.WALL
	if cell.cell_type == WdcMapGenerationTypes.CellType.FLOOR:
		if cell.special_block_type == WdcMapGenerationTypes.SpecialBlockType.SPIKE:
			return WdcMapGenerationTypes.ServerTileType.SPIKE_TILE
		if cell.special_block_type == WdcMapGenerationTypes.SpecialBlockType.PRESSURE_PLATE:
			return WdcMapGenerationTypes.ServerTileType.PRESSURE_PLATE_TILE
		return WdcMapGenerationTypes.ServerTileType.EMPTY
	match cell.special_block_type:
		WdcMapGenerationTypes.SpecialBlockType.RARE_MINERAL:
			return WdcMapGenerationTypes.ServerTileType.RARE_MINERAL_WALL
		WdcMapGenerationTypes.SpecialBlockType.TURQUOISE:
			return WdcMapGenerationTypes.ServerTileType.TURQUOISE_ORE
		WdcMapGenerationTypes.SpecialBlockType.AMETHYST:
			return WdcMapGenerationTypes.ServerTileType.AMETHYST_ORE
		WdcMapGenerationTypes.SpecialBlockType.GOLD:
			return WdcMapGenerationTypes.ServerTileType.GOLD_BLOCK
		WdcMapGenerationTypes.SpecialBlockType.POI_WALL:
			return WdcMapGenerationTypes.ServerTileType.POI_WALL
		WdcMapGenerationTypes.SpecialBlockType.EXPLOSIVE_ORE:
			return WdcMapGenerationTypes.ServerTileType.EXPLOSIVE_ORE_TILE
		WdcMapGenerationTypes.SpecialBlockType.ARROW_SLIT:
			return WdcMapGenerationTypes.ServerTileType.ARROW_SLIT_TILE
	if cell.has_mineral:
		return WdcMapGenerationTypes.ServerTileType.MINERAL_WALL
	return WdcMapGenerationTypes.ServerTileType.WALL


static func _resolve_cell_max_hit_points(cell: RefCounted, tile_type: int) -> int:
	if cell != null and _is_layer_durability_tile(tile_type):
		var override_value: int = int(cell.get("durability_override_max_hit_points"))
		if override_value > 0:
			return override_value
	return get_tile_max_hit_points(tile_type)


static func _is_layer_durability_tile(tile_type: int) -> bool:
	match tile_type:
		WdcMapGenerationTypes.ServerTileType.WALL:
			return true
		WdcMapGenerationTypes.ServerTileType.MINERAL_WALL:
			return true
		WdcMapGenerationTypes.ServerTileType.RARE_MINERAL_WALL:
			return true
		WdcMapGenerationTypes.ServerTileType.TURQUOISE_ORE:
			return true
		WdcMapGenerationTypes.ServerTileType.AMETHYST_ORE:
			return true
		WdcMapGenerationTypes.ServerTileType.GOLD_BLOCK:
			return true
	return false

