## 文件职责：`GeneratedMapTileRules` 负责 generated map tile 的共享耐久规则。
## 边界约束：这里只描述 tile durability 语义，不依赖具体 runtime 节点或 world object 生成。

class_name WdcMapGenerationTileRules
extends RefCounted


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


static func refresh_map_runtime_state(map_data: WdcMapGenerationTypes.MapData) -> void:
	if map_data == null:
		return
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			refresh_cell_runtime_state(map_data.get_cell(x, y))


static func refresh_cell_runtime_state(cell: WdcMapGenerationTypes.CellData) -> void:
	if cell == null:
		return
	var tile_type: int = WdcMapGenerationTypes.encode_server_tile(cell)
	var max_hit_points: int = get_tile_max_hit_points(tile_type)
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


static func get_cell_current_hit_points(cell: WdcMapGenerationTypes.CellData) -> int:
	if cell == null:
		return 0
	refresh_cell_runtime_state(cell)
	return cell.current_hit_points


static func get_cell_max_hit_points(cell: WdcMapGenerationTypes.CellData) -> int:
	if cell == null:
		return 0
	refresh_cell_runtime_state(cell)
	return cell.max_hit_points


static func is_cell_fog_blocker(cell: WdcMapGenerationTypes.CellData) -> bool:
	if cell == null:
		return true
	return is_tile_fog_blocker(WdcMapGenerationTypes.encode_server_tile(cell))

