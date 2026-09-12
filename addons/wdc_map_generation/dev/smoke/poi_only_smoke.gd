extends SceneTree

const C = preload("../../config/data_generated_map_config_catalog.gd")
const G = preload("../../core/generated_map_generator.gd")
const T = preload("../../core/generated_map_types.gd")


func _initialize() -> void:
	var source: Dictionary = C.load_config_dict_by_filename("ancient_old_mine")
	var before: String = JSON.stringify(source)
	for entry: Array in [["miners_settlement", "miner_settlement_core"], ["miners_settlement_alley", "miner_settlement_core"], ["refining_workshop", "refinery_workshop_core"], ["refining_workshop_linear", "refinery_workshop_core"], ["refining_workshop_u", "refinery_workshop_core"], ["boss_control_vault", "command_vault_core"]]:
		for seed_value: int in [1, 1337, 240513]:
			var built: Dictionary = C.build_poi_only_config(source, entry[0], seed_value, {}, "", entry[1])
			if not built.valid:
				_fail("构建测试配置失败 %s：%s" % [entry[0], built.issues])
				return
			var parsed: Variant = C.parse_and_normalize_config(built.config)
			if not parsed.is_success():
				_fail("测试配置回读失败：%s" % [parsed.get_issues()])
				return
			var generator: RefCounted = G.new()
			var map: Variant = generator.generate_full(parsed.config)
			if map == null:
				_fail("生成失败 %s seed=%d：%s" % [entry[0], seed_value, generator.last_generation_issues])
				return
			if map.layout_mode != T.LAYOUT_MODE_POI_ONLY_V1 or map.region_plan != null or map.region_boss_encounter != null or map.poi_instances.size() != 1:
				_fail("POI-only 产生了错误布局或多余 POI")
				return
			if map.player_spawn_points.size() != 1 or map.extraction_sites.size() != 1:
				_fail("出生或撤离点数量错误")
				return
			var spawn: Dictionary = map.player_spawn_points[0]
			var reached: Dictionary = _flood(map, Vector2i(spawn.x, spawn.y))
			var poi: Dictionary = map.poi_instances[0]
			var entry_cell: Vector2i = poi.center_cell
			if not reached.has(entry_cell) or not reached.has(Vector2i(map.extraction_sites[0].x, map.extraction_sites[0].y)):
				_fail("出生无法抵达图纸主锚点或撤离点")
				return
			var payload: Variant = generator.build_server_payload(map)
			var decoded: Variant = T.server_payload_from_variant(payload.to_dict())
			if not decoded.is_valid or decoded.layout_mode != T.LAYOUT_MODE_POI_ONLY_V1 or decoded.region_plan != null:
				_fail("POI-only payload 不能无损往返：%s" % [decoded.issues])
				return
			var again: Variant = generator.generate_full(parsed.config)
			if JSON.stringify(map.poi_instances) != JSON.stringify(again.poi_instances):
				_fail("相同 seed 的图纸内容不确定")
				return
			print("POI-only %s seed=%d size=%dx%d props=%d camps=%d monsters=%d" % [entry[0], seed_value, map.width, map.height, map.furnishing_sites.size(), map.camp_encounters.size(), map.monster_sites.size()])
	if JSON.stringify(source) != before:
		_fail("构建测试配置污染了源地图")
		return
	if not _test_boss_rotations(source) or not _test_invalid(source):
		return
	print("POI-only smoke PASS")
	quit(0)


func _test_boss_rotations(source: Dictionary) -> bool:
	var resource_root: String = C.POI_RESOURCE_CATALOG.get_resource_directories().compositions
	var composition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(resource_root.path_join("boss_control_vault.json")))
	for angle: int in [0, 90, 180, 270]:
		composition.nodes[0]["rotations"] = [angle]
		var overrides: Dictionary = {"compositions": {"boss_control_vault": composition}}
		var built: Dictionary = C.build_poi_only_config(source, "boss_control_vault", 7, overrides)
		if not built.valid:
			_fail("BOSS 旋转配置失败：%s" % [built.issues])
			return false
		var parsed: Variant = C.parse_and_normalize_config(built.config, overrides)
		var generator: RefCounted = G.new()
		var map: Variant = generator.generate_full(parsed.config)
		if map == null:
			_fail("BOSS 旋转生成失败：%s" % [generator.last_generation_issues])
			return false
		var poi: Dictionary = map.poi_instances[0]
		var closed: Dictionary = _flood(map, Vector2i(3, 3))
		if not closed.has(poi.center_cell):
			_fail("BOSS 被锁在奖励区")
			return false
		for device: Dictionary in poi.core_metadata.reward_object_cells:
			if closed.has(Vector2i(device.x, device.y)):
				_fail("关闭奖励门仍可绕行奖励区")
				return false
		var protected: Array = poi.core_metadata.reward_protected_cells
		if protected.size() != 102 or protected.has({"x": poi.center_cell.x, "y": poi.center_cell.y}):
			_fail("奖励区与边界墙保护范围不完整")
			return false
		var opened_map: Variant = map.deep_clone()
		for gate: Dictionary in poi.core_metadata.reward_gate_cells:
			opened_map.get_cell(gate.x, gate.y).cell_type = T.CellType.FLOOR
		var opened: Dictionary = _flood(opened_map, Vector2i(3, 3))
		for device: Dictionary in poi.core_metadata.reward_object_cells:
			if not opened.has(Vector2i(device.x, device.y)):
				_fail("解锁门后奖励区仍不可达")
				return false
		print("POI-only BOSS rotation=%d protected=%d PASS" % [angle, protected.size()])
	return true


func _test_invalid(source: Dictionary) -> bool:
	var built: Dictionary = C.build_poi_only_config(source, "miners_settlement", 1)
	for field: String in ["composition_id", "source_template_id", "content_profile_id", "region_role"]:
		var bad: Dictionary = built.config.duplicate(true)
		bad.poi_only[field] = "missing"
		if C.parse_and_normalize_config(bad).is_success():
			_fail("错误测试引用被接受：" + field)
			return false
	var bad_boss: Dictionary = built.config.duplicate(true)
	bad_boss.poi_only.encounter_profile_id = "unexpected_boss"
	if C.parse_and_normalize_config(bad_boss).is_success():
		_fail("普通组合接受了 BOSS 遭遇")
		return false
	var bad_budget: Dictionary = built.config.duplicate(true)
	bad_budget.region_generation.content_profiles[0].reward_value_budget = 0
	var parsed: Variant = C.parse_and_normalize_config(bad_budget)
	var generator: RefCounted = G.new()
	if parsed.is_success() and generator.generate_full(parsed.config) != null:
		_fail("测试地图绕过了源 profile 必需内容成本")
		return false
	var valid_map: Variant = G.new().generate_full(C.parse_and_normalize_config(built.config).config)
	var encoded: Dictionary = G.new().build_server_payload(valid_map).to_dict()
	encoded["region_plan"] = {}
	if T.server_payload_from_variant(encoded).is_valid:
		_fail("POI-only 接受了伪造四区域产物")
		return false
	encoded.erase("region_plan")
	encoded.tile_matrix[0].pop_back()
	if T.server_payload_from_variant(encoded).is_valid:
		_fail("POI-only 接受了错误 tile 行宽")
		return false
	return true


func _flood(map: Variant, start: Vector2i) -> Dictionary:
	var reached: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor: int = 0
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]
		cursor += 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + step
			var cell: Variant = map.get_cell(next.x, next.y)
			if cell != null and cell.cell_type == T.CellType.FLOOR and not reached.has(next):
				reached[next] = true
				queue.append(next)
	return reached


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
