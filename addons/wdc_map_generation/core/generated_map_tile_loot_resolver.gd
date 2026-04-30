## 文件职责：`WdcMapGenerationTileLootResolver` 提供 generated map tile 的独立掉落数据解析。
## 边界约束：这里只返回纯 item snapshot / spawn payload 数据，不依赖主仓 inventory catalog 或 scene runtime。

class_name WdcMapGenerationTileLootResolver
extends RefCounted

const WdcMapGenerationTypes = preload("generated_map_types.gd")


static var _mineral_wall_weighted_entries: Array[Dictionary] = [
	{"item_id": "coal_ore", "min_count": 1, "max_count": 2, "weight": 6},
	{"item_id": "iron_ore", "min_count": 1, "max_count": 2, "weight": 3},
	{"item_id": "gold_ore", "min_count": 1, "max_count": 1, "weight": 1},
]


static var _drop_definitions: Dictionary = {
	WdcMapGenerationTypes.ServerTileType.MINERAL_WALL: {
		"weighted_entries": _mineral_wall_weighted_entries,
		"source_kind": "generated_map_mineral_wall",
	},
	WdcMapGenerationTypes.ServerTileType.RARE_MINERAL_WALL: {
		"item_id": "gold_ore",
		"min_count": 1,
		"max_count": 2,
		"source_kind": "generated_map_rare_mineral_wall",
	},
	WdcMapGenerationTypes.ServerTileType.TURQUOISE_ORE: {
		"item_id": "turquoise_gem",
		"min_count": 1,
		"max_count": 2,
		"source_kind": "generated_map_turquoise_ore",
	},
	WdcMapGenerationTypes.ServerTileType.AMETHYST_ORE: {
		"item_id": "amethyst_gem",
		"min_count": 1,
		"max_count": 2,
		"source_kind": "generated_map_amethyst_ore",
	},
	WdcMapGenerationTypes.ServerTileType.GOLD_BLOCK: {
		"item_id": "raw_gold",
		"min_count": 1,
		"max_count": 2,
		"source_kind": "generated_map_gold_block",
	},
}


static var _inventory_grant_definitions: Dictionary = {
	WdcMapGenerationTypes.ServerTileType.WALL: {
		"item_id": "stone",
		"min_count": 1,
		"max_count": 1,
	}
}


static func build_dropped_item_stack_spawn_payload(
	tile_type: int,
	spawn_position: Vector3,
	rng: RandomNumberGenerator = null
) -> Dictionary:
	var slot_snapshots: Array = _build_slot_snapshots_from_definition(
		_drop_definitions.get(tile_type, {}) as Dictionary,
		rng
	)
	if slot_snapshots.is_empty():
		return {}
	return {
		"spawn_position": spawn_position,
		"item_snapshot": _normalize_item_snapshot(slot_snapshots[0]),
	}


static func build_dropped_item_stack_spawn_descriptors(
	tile_type: int,
	spawn_position: Vector3,
	rng: RandomNumberGenerator = null
) -> Array[Dictionary]:
	var slot_snapshots: Array = _build_slot_snapshots_from_definition(
		_drop_definitions.get(tile_type, {}) as Dictionary,
		rng
	)
	return build_dropped_item_stack_spawn_descriptors_from_slot_snapshots(
		slot_snapshots,
		spawn_position
	)


static func build_dropped_item_stack_spawn_descriptors_from_slot_snapshots(
	slot_snapshots: Array,
	spawn_position: Vector3
) -> Array[Dictionary]:
	var descriptors: Array[Dictionary] = []
	for snapshot_value: Variant in slot_snapshots:
		var spawn_payload: Dictionary = build_dropped_item_stack_spawn_payload_from_item_snapshot(
			_normalize_item_snapshot(snapshot_value),
			spawn_position
		)
		if spawn_payload.is_empty():
			continue
		descriptors.append({
			"object_kind": "dropped_item_stack",
			"spawn_position": spawn_position,
			"spawn_payload": spawn_payload,
		})
	return descriptors


static func build_dropped_item_stack_spawn_payload_from_item_snapshot(
	item_snapshot: Dictionary,
	spawn_position: Vector3
) -> Dictionary:
	var normalized_snapshot: Dictionary = _normalize_item_snapshot(item_snapshot)
	if normalized_snapshot.is_empty():
		return {}
	return {
		"spawn_position": spawn_position,
		"item_snapshot": normalized_snapshot,
	}


static func build_inventory_slot_snapshots(
	tile_type: int,
	rng: RandomNumberGenerator = null
) -> Array:
	return _build_slot_snapshots_from_definition(
		_inventory_grant_definitions.get(tile_type, {}) as Dictionary,
		rng
	)


static func build_loot_slot_snapshots(tile_type: int, rng: RandomNumberGenerator = null) -> Array:
	return _build_slot_snapshots_from_definition(
		_drop_definitions.get(tile_type, {}) as Dictionary,
		rng
	)


static func get_drop_definition(tile_type: int) -> Dictionary:
	return (_drop_definitions.get(tile_type, {}) as Dictionary).duplicate(true)


static func _normalize_item_snapshot(snapshot_value: Variant) -> Dictionary:
	if not (snapshot_value is Dictionary):
		return {}
	var snapshot: Dictionary = (snapshot_value as Dictionary).duplicate(true)
	if snapshot.has("stack") and snapshot.get("stack", {}) is Dictionary:
		snapshot = (snapshot.get("stack", {}) as Dictionary).duplicate(true)
	var item_id: String = str(snapshot.get("item_id", ""))
	var count: int = maxi(int(snapshot.get("count", 0)), 0)
	if item_id.is_empty() or count <= 0:
		return {}
	return {
		"item_id": item_id,
		"count": count,
	}


static func _build_slot_snapshots_from_definition(
	definition: Dictionary,
	rng: RandomNumberGenerator = null
) -> Array:
	if definition.is_empty():
		return []
	var resolved_definition: Dictionary = _resolve_stack_definition(definition, rng)
	if resolved_definition.is_empty():
		return []
	var item_id: String = str(resolved_definition.get("item_id", ""))
	if item_id.is_empty():
		return []
	var min_count: int = maxi(int(resolved_definition.get("min_count", 1)), 1)
	var max_count: int = maxi(int(resolved_definition.get("max_count", min_count)), min_count)
	var resolved_count: int = min_count
	if rng != null and max_count > min_count:
		resolved_count = rng.randi_range(min_count, max_count)
	return [{
		"item_id": item_id,
		"count": resolved_count,
	}]


static func _resolve_stack_definition(
	definition: Dictionary,
	rng: RandomNumberGenerator = null
) -> Dictionary:
	var weighted_entries_value: Variant = definition.get("weighted_entries", [])
	if weighted_entries_value is Array and not (weighted_entries_value as Array).is_empty():
		return _resolve_weighted_entry(weighted_entries_value as Array, rng)
	return definition.duplicate(true)


static func _resolve_weighted_entry(
	weighted_entries: Array,
	rng: RandomNumberGenerator = null
) -> Dictionary:
	var valid_entries: Array[Dictionary] = []
	var total_weight: int = 0
	for entry_value: Variant in weighted_entries:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = (entry_value as Dictionary).duplicate(true)
		var entry_weight: int = maxi(int(entry.get("weight", 0)), 0)
		if entry_weight <= 0:
			continue
		valid_entries.append(entry)
		total_weight += entry_weight
	if valid_entries.is_empty() or total_weight <= 0:
		return {}
	if rng == null:
		return valid_entries[0].duplicate(true)
	var roll: int = rng.randi_range(1, total_weight)
	var cumulative_weight: int = 0
	for entry: Dictionary in valid_entries:
		cumulative_weight += maxi(int(entry.get("weight", 0)), 0)
		if roll <= cumulative_weight:
			return entry.duplicate(true)
	return valid_entries[valid_entries.size() - 1].duplicate(true)
