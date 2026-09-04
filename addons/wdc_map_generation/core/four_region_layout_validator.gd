class_name WdcFourRegionLayoutValidator
extends RefCounted

const WdcMapGenerationTypes = preload("generated_map_types.gd")

const _CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]


func validate(map_size: Vector2i, membership: PackedInt32Array) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if map_size.x <= 0 or map_size.y <= 0 or membership.size() != map_size.x * map_size.y:
		issues.append(_issue(
			"region_partition_failed",
			"region_index_by_cell",
			"",
			"四区域 membership 长度与地图尺寸不一致"
		))
		return issues
	var cells_by_region: Array[Array] = [[], [], [], []]
	for flat_index: int in range(membership.size()):
		var region_index: int = int(membership[flat_index])
		if region_index < 0 or region_index >= WdcMapGenerationTypes.REGION_ROLE_ORDER.size():
			issues.append(_issue(
				"region_partition_failed",
				"region_index_by_cell[%d]" % flat_index,
				"",
				"四区域 membership 包含越界 index"
			))
			continue
		cells_by_region[region_index].append(_cell_from_flat(flat_index, map_size.x))
	if not issues.is_empty():
		return issues
	for region_index: int in range(cells_by_region.size()):
		var role: String = WdcMapGenerationTypes.REGION_ROLE_ORDER[region_index]
		var region_cells: Array = cells_by_region[region_index]
		if region_cells.is_empty():
			issues.append(_issue(
				"region_partition_failed",
				"region_index_by_cell",
				role,
				"区域 membership 不能为空"
			))
			continue
		if not _is_region_four_connected(map_size, membership, region_index, region_cells[0]):
			issues.append(_issue(
				"disconnected_region",
				"region_index_by_cell",
				role,
				"区域必须保持四连通"
			))
	for y: int in range(map_size.y):
		for x: int in range(map_size.x):
			var current_index: int = int(membership[y * map_size.x + x])
			if current_index == 0:
				continue
			for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var neighbor: Vector2i = Vector2i(x, y) + direction
				if not _is_in_bounds(neighbor, map_size):
					continue
				var neighbor_index: int = int(
					membership[neighbor.y * map_size.x + neighbor.x]
				)
				if neighbor_index != 0 and neighbor_index != current_index:
					issues.append(_issue(
						"adjacent_high_risk_regions",
						"region_index_by_cell",
						WdcMapGenerationTypes.REGION_ROLE_ORDER[current_index],
						"不同高风险区域不得四邻接"
					))
					return issues
	for region_index: int in range(1, WdcMapGenerationTypes.REGION_ROLE_ORDER.size()):
		if not _has_regular_boundary(map_size, membership, region_index):
			var role: String = WdcMapGenerationTypes.REGION_ROLE_ORDER[region_index]
			issues.append(_issue(
				"missing_regular_access_boundary",
				"region_index_by_cell",
				role,
				"高风险区域必须拥有独立的常规区接触边界"
			))
	return issues


func compute_canonical_centers(
	map_size: Vector2i,
	membership: PackedInt32Array
) -> Dictionary:
	var result: Dictionary = {}
	if map_size.x <= 0 or map_size.y <= 0 or membership.size() != map_size.x * map_size.y:
		return result
	var cell_groups: Array[Array] = [[], [], [], []]
	var sum_x: Array[int] = [0, 0, 0, 0]
	var sum_y: Array[int] = [0, 0, 0, 0]
	for flat_index: int in range(membership.size()):
		var region_index: int = int(membership[flat_index])
		if region_index < 0 or region_index >= cell_groups.size():
			continue
		var cell: Vector2i = _cell_from_flat(flat_index, map_size.x)
		cell_groups[region_index].append(cell)
		sum_x[region_index] += cell.x
		sum_y[region_index] += cell.y
	for region_index: int in range(cell_groups.size()):
		var cells: Array = cell_groups[region_index]
		if cells.is_empty():
			continue
		var count: int = cells.size()
		var best_cell: Vector2i = cells[0] as Vector2i
		var best_distance: int = _centroid_distance_numerator(
			best_cell,
			count,
			sum_x[region_index],
			sum_y[region_index]
		)
		for cell_value: Variant in cells:
			var cell: Vector2i = cell_value as Vector2i
			var distance: int = _centroid_distance_numerator(
				cell,
				count,
				sum_x[region_index],
				sum_y[region_index]
			)
			if (
				distance < best_distance
				or (
					distance == best_distance
					and (cell.y < best_cell.y or (cell.y == best_cell.y and cell.x < best_cell.x))
				)
			):
				best_cell = cell
				best_distance = distance
		result[WdcMapGenerationTypes.REGION_ROLE_ORDER[region_index]] = best_cell
	return result


func collect_regular_boundary_cells(
	map_size: Vector2i,
	membership: PackedInt32Array,
	region_index: int
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen: Dictionary = {}
	if region_index <= 0 or region_index >= WdcMapGenerationTypes.REGION_ROLE_ORDER.size():
		return result
	for y: int in range(map_size.y):
		for x: int in range(map_size.x):
			var cell: Vector2i = Vector2i(x, y)
			if int(membership[y * map_size.x + x]) != region_index:
				continue
			for direction: Vector2i in _CARDINAL_DIRECTIONS:
				var neighbor: Vector2i = cell + direction
				if not _is_in_bounds(neighbor, map_size):
					continue
				if int(membership[neighbor.y * map_size.x + neighbor.x]) != 0:
					continue
				var key: String = "%d:%d" % [cell.x, cell.y]
				if not seen.has(key):
					seen[key] = true
					result.append(cell)
				break
	return result


func _is_region_four_connected(
	map_size: Vector2i,
	membership: PackedInt32Array,
	region_index: int,
	start_value: Variant
) -> bool:
	if not (start_value is Vector2i):
		return false
	var start: Vector2i = start_value as Vector2i
	var queue: Array[Vector2i] = [start]
	var visited: Dictionary = {"%d:%d" % [start.x, start.y]: true}
	var cursor: int = 0
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in _CARDINAL_DIRECTIONS:
			var neighbor: Vector2i = current + direction
			if not _is_in_bounds(neighbor, map_size):
				continue
			if int(membership[neighbor.y * map_size.x + neighbor.x]) != region_index:
				continue
			var key: String = "%d:%d" % [neighbor.x, neighbor.y]
			if visited.has(key):
				continue
			visited[key] = true
			queue.append(neighbor)
	var expected_count: int = 0
	for value: int in membership:
		if value == region_index:
			expected_count += 1
	return visited.size() == expected_count


func _has_regular_boundary(
	map_size: Vector2i,
	membership: PackedInt32Array,
	region_index: int
) -> bool:
	for y: int in range(map_size.y):
		for x: int in range(map_size.x):
			if int(membership[y * map_size.x + x]) != region_index:
				continue
			for direction: Vector2i in _CARDINAL_DIRECTIONS:
				var neighbor: Vector2i = Vector2i(x, y) + direction
				if (
					_is_in_bounds(neighbor, map_size)
					and int(membership[neighbor.y * map_size.x + neighbor.x]) == 0
				):
					return true
	return false


func _centroid_distance_numerator(
	cell: Vector2i,
	count: int,
	sum_x: int,
	sum_y: int
) -> int:
	var delta_x: int = cell.x * count - sum_x
	var delta_y: int = cell.y * count - sum_y
	return delta_x * delta_x + delta_y * delta_y


func _cell_from_flat(flat_index: int, width: int) -> Vector2i:
	return Vector2i(flat_index % width, flat_index / width)


func _is_in_bounds(cell: Vector2i, map_size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_size.x and cell.y < map_size.y


func _issue(code: String, path: String, role: String, message: String) -> Dictionary:
	return WdcMapGenerationTypes.make_generation_issue(code, path, role, message)
