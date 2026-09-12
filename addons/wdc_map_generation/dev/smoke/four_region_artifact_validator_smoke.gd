extends SceneTree

const CONFIG_CATALOG = preload("../../config/data_generated_map_config_catalog.gd")
const MAP_TYPES = preload("../../core/generated_map_types.gd")
const GENERATOR_SCRIPT = preload("../../core/generated_map_generator.gd")
const RESOLVER_SCRIPT = preload("../../core/region_content_resolver.gd")

var _failures: Array[String] = []


func _init() -> void:
	var raw_config: Dictionary = CONFIG_CATALOG.load_config_dict_by_filename("ancient_old_mine")
	var parse_result = CONFIG_CATALOG.parse_and_normalize_config(raw_config)
	_expect(
		parse_result.is_success(),
		"ancient_old_mine final artifact smoke 配置解析失败：%s" % str(parse_result.get_issues())
	)
	if parse_result.is_success():
		var generator = GENERATOR_SCRIPT.new()
		var map_data = generator.generate_full(parse_result.config)
		_expect(
			map_data != null,
			"ancient_old_mine final artifact smoke 生成失败：%s" % str(generator.get_last_generation_issues())
		)
		if map_data != null:
			_test_core_artifact_contract(parse_result.config, map_data)
			_test_region_content_resolver(parse_result.config, map_data)
			_test_derived_region_caches(generator, map_data)
			_test_final_artifact_rejections(generator, map_data)
			_test_regular_only_fallback(generator, parse_result.config, map_data)
			_test_camp_minimum_budget_reservation(
				parse_result.config,
				generator.last_four_region_success_attempt
			)
			_test_failed_generation_atomicity(generator, parse_result.config, map_data)
	_finish()


func _test_core_artifact_contract(config: Variant, map_data: Variant) -> void:
	var repeat_generator = GENERATOR_SCRIPT.new()
	var repeated = repeat_generator.generate_full(config.deep_clone())
	_expect(
		repeated != null,
		"同 config/seed 重复生成不得失败：%s" % str(repeat_generator.get_last_generation_issues())
	)
	if repeated == null:
		return
	var first_signature: Dictionary = _core_artifact_signature(map_data)
	var repeated_signature: Dictionary = _core_artifact_signature(repeated)
	_expect(first_signature == repeated_signature, "核心 POI identity/footprint 与 encounter id 必须稳定")

	var plan = map_data.region_plan
	var core_ids: Dictionary = {}
	for role: String in [
		MAP_TYPES.REGION_ROLE_HIGH_1,
		MAP_TYPES.REGION_ROLE_HIGH_2,
		MAP_TYPES.REGION_ROLE_BOSS,
	]:
		var region = plan.try_get_by_role(role)
		_expect(region != null, "%s RegionPlan snapshot 不能为空" % role)
		if region == null:
			continue
		var matching_cores: Array[Dictionary] = _core_instances_for_role(map_data, role)
		_expect(matching_cores.size() == 1, "%s 必须恰有一个核心 POI" % role)
		if matching_cores.size() != 1:
			continue
		var core: Dictionary = matching_cores[0]
		var instance_id: String = str(core.get("instance_id", ""))
		_expect(not instance_id.is_empty(), "%s 核心 POI identity 不能为空" % role)
		_expect(not core_ids.has(instance_id), "三个核心 POI identity 必须互不重复")
		core_ids[instance_id] = true
		_expect(instance_id == region.core_poi_instance_id, "%s identity 必须与 RegionPlan 一致" % role)
		_expect(
			str(core.get("template_id", "")) == region.core_poi_template_id,
			"%s template 必须与 RegionPlan 一致" % role
		)
		var anchor: Vector2i = _cell_from_variant(core.get("center_cell", null))
		var canonical_center: Vector2i = _cell_from_variant(core.get("canonical_center", null))
		var max_offset: int = int(core.get("max_center_offset_cells", -1))
		_expect(anchor == region.core_anchor_cell, "%s anchor 必须与 RegionPlan 一致" % role)
		_expect(canonical_center == region.center_cell, "%s canonical center 必须来自 RegionPlan" % role)
		_expect(
			max_offset >= 0 and anchor.distance_to(canonical_center) <= float(max_offset),
			"%s 核心 POI 必须位于允许的 center offset 内" % role
		)
		_validate_complete_core_footprint(core, role)

	var boss_region = plan.try_get_by_role(MAP_TYPES.REGION_ROLE_BOSS)
	var descriptor = map_data.region_boss_encounter
	_expect(descriptor != null, "四区域地图必须提供单值 BOSS descriptor")
	if boss_region != null and descriptor != null:
		var boss_core: Dictionary = _find_core_instance(map_data, MAP_TYPES.REGION_ROLE_BOSS)
		_expect(
			descriptor.get_encounter_id() == "%s:%s" % [
				boss_region.id,
				boss_region.core_poi_instance_id,
			],
			"encounter id 必须由 boss region id 与核心 POI identity 稳定派生"
		)
		var anchors: Array = descriptor.get_anchor_snapshots()
		_expect(anchors.size() == 1, "首版 BOSS descriptor 必须恰有一个 anchor")
		if anchors.size() == 1:
			_expect(anchors[0].id == "primary", "首版 BOSS descriptor 唯一 anchor 必须名为 primary")
			_expect(
				anchors[0].cell == _cell_from_variant(boss_core.get("named_anchors", {}).get("primary", boss_core.get("main_room_center", null))),
				"primary 必须等于 BOSS 核心的具名锚点"
			)
		var metadata: Dictionary = boss_core.get("core_metadata", {}) as Dictionary
		_expect(not str(metadata.get("reward_recipe_id", "")).is_empty(), "BOSS 核心 POI 必须保存奖励配方")
		_expect(not (metadata.get("reward_gate_cells", []) as Array).is_empty(), "BOSS 核心 POI 必须保存奖励门格")
		_expect(not (metadata.get("reward_object_cells", []) as Array).is_empty(), "BOSS 核心 POI 必须保存奖励物件位置")


func _validate_complete_core_footprint(core: Dictionary, role: String) -> void:
	var footprint: Dictionary = _cell_set(core.get("footprint_cells", []))
	_expect(not footprint.is_empty(), "%s 核心 POI footprint 不能为空" % role)
	if str(core.get("layout_kind", "")) == "authored_rooms":
		var explicit_cells: Dictionary = _cell_set(core.get("floor_cells", []) + core.get("wall_cells", []))
		_expect(explicit_cells.size() == footprint.size(), "图纸 footprint 必须恰好来自显式地板和墙格")
		for room: Dictionary in core.get("rooms", []):
			for key: String in _cell_set(room.get("footprint_cells", [])):
				_expect(footprint.has(key), "图纸实例的真实占地不能在总 footprint 中丢失")
		for connection: Dictionary in core.get("connections", []):
			for key: String in _cell_set(connection.get("corridor_cells", [])):
				_expect(footprint.has(key), "精确宽度通道必须保留在总 footprint 中")
		return
	var interior: Dictionary = {}
	var room_values: Array = [core.get("main_room", {})]
	room_values.append_array(core.get("sub_rooms", []) as Array)
	for room_value: Variant in room_values:
		var room: Rect2i = _rect_from_variant(room_value)
		for y: int in range(room.position.y, room.end.y):
			for x: int in range(room.position.x, room.end.x):
				interior[_cell_key(Vector2i(x, y))] = Vector2i(x, y)
	for corridor_value: Variant in core.get("corridors", []) as Array:
		if not (corridor_value is Dictionary):
			continue
		for cell_value: Variant in (corridor_value as Dictionary).get("cells", []) as Array:
			var corridor_cell: Vector2i = _cell_from_variant(cell_value)
			interior[_cell_key(corridor_cell)] = corridor_cell
	for cell_value: Variant in interior.values():
		var cell: Vector2i = cell_value as Vector2i
		for offset_y: int in range(-1, 2):
			for offset_x: int in range(-1, 2):
				var structural_cell: Vector2i = cell + Vector2i(offset_x, offset_y)
				_expect(
					footprint.has(_cell_key(structural_cell)),
					"%s footprint 必须覆盖房间、走廊及其结构墙：%s" % [role, structural_cell]
				)


func _test_region_content_resolver(config: Variant, map_data: Variant) -> void:
	var resolver = RESOLVER_SCRIPT.new(config, map_data.region_plan)
	_expect(resolver.is_ready(), "RegionContentResolver 必须成功绑定 config 与 RegionPlan")
	var plan = map_data.region_plan
	for role: String in MAP_TYPES.REGION_ROLE_ORDER:
		var region = plan.try_get_by_role(role)
		var resolved: Dictionary = resolver.resolve_cell(region.center_cell)
		_expect(bool(resolved.get("valid", false)), "%s center 必须可由 resolver 查询" % role)
		_expect(int(resolved.get("region_index", -1)) == region.index, "%s resolver index 必须匹配" % role)
		_expect(str(resolved.get("role", "")) == role, "%s resolver role 必须匹配" % role)
		_expect(
			str(resolved.get("content_profile_id", "")) == region.content_profile_id,
			"%s resolver content profile 必须匹配" % role
		)
		var configured_profile: Dictionary = config.try_get_region_content_profile(
			region.content_profile_id
		)
		_expect(
			resolver.get_profile_for_role(role) == configured_profile,
			"%s resolver 必须返回规范化 content profile" % role
		)
		for budget_name: String in ["mineral_value_budget", "reward_value_budget"]:
			_expect(
				resolver.get_value_budget(role, budget_name) == int(configured_profile.get(budget_name, 0)),
				"%s %s 不得受 difficulty rank 隐式倍率影响" % [role, budget_name]
			)
		_expect(
			resolver.get_wall_hit_points(region.center_cell, "ordinary")
			== int((configured_profile.get("wall_durability", {}) as Dictionary).get("ordinary_max_hit_points", 1)),
			"%s 普通墙耐久必须直接来自 content profile" % role
		)

	var high_1 = plan.try_get_by_role(MAP_TYPES.REGION_ROLE_HIGH_1)
	var same_region_pair: Array[Vector2i] = _find_adjacent_region_pair(plan, high_1.index)
	_expect(same_region_pair.size() == 2, "high_1 必须存在同区相邻 footprint 样本")
	if same_region_pair.size() == 2:
		var same_result: Dictionary = resolver.resolve_footprint(same_region_pair)
		_expect(bool(same_result.get("valid", false)), "同区 footprint 必须解析成功")
	var regular = plan.try_get_by_role(MAP_TYPES.REGION_ROLE_REGULAR)
	var cross_region_footprint: Array[Vector2i] = [
		regular.center_cell,
		high_1.center_cell,
	]
	var cross_result: Dictionary = resolver.resolve_footprint(cross_region_footprint)
	_expect(
		not bool(cross_result.get("valid", false))
		and _result_has_issue(cross_result, "content_footprint_crosses_region"),
		"跨区 footprint 必须稳定失败"
	)

	var candidates: Array[Dictionary] = []
	for index: int in range(6):
		candidates.append({"id": "candidate_%d" % index, "cell": Vector2i(index + 1, 1)})
	var first_selection: Dictionary = resolver.select_candidates(
		MAP_TYPES.REGION_ROLE_HIGH_1,
		"monster_sites",
		candidates,
		73
	)
	var second_selection: Dictionary = resolver.select_candidates(
		MAP_TYPES.REGION_ROLE_HIGH_1,
		"monster_sites",
		candidates,
		73
	)
	var high_1_section: Dictionary = resolver.get_section_for_role(
		MAP_TYPES.REGION_ROLE_HIGH_1,
		"monster_sites"
	)
	_expect(bool(first_selection.get("success", false)), "候选达到 target 时 resolver 必须成功")
	_expect(
		(first_selection.get("selected", []) as Array).size() == int(high_1_section.get("target_count", 0)),
		"resolver 必须按 target_count 确定性裁剪"
	)
	_expect(first_selection == second_selection, "相同 seed salt 的候选裁剪必须稳定")
	var no_candidates: Array[Dictionary] = []
	var minimum_failure: Dictionary = resolver.select_candidates(
		MAP_TYPES.REGION_ROLE_HIGH_1,
		"monster_sites",
		no_candidates,
		73
	)
	_expect(
		not bool(minimum_failure.get("success", false))
		and _has_issue(minimum_failure.get("issues", []), "content_minimum_not_met"),
		"候选低于 minimum_count 必须稳定失败"
	)
	var disabled_result: Dictionary = resolver.select_candidates(
		MAP_TYPES.REGION_ROLE_REGULAR,
		"monster_sites",
		candidates,
		73
	)
	_expect(
		bool(disabled_result.get("success", false))
		and (disabled_result.get("selected", []) as Array).is_empty(),
		"target_count=0 必须严格禁用内容"
	)
	_test_rank_independent_profile_resolution(config, plan, candidates)


func _test_rank_independent_profile_resolution(
	config: Variant,
	plan: Variant,
	candidates: Array[Dictionary]
) -> void:
	var shared_profile_plan_dict: Dictionary = MAP_TYPES.encode_region_plan_authority(plan)
	var shared_regions: Array = shared_profile_plan_dict.get("regions", []) as Array
	var high_1_profile_id: String = ""
	for region_value: Variant in shared_regions:
		if not (region_value is Dictionary):
			continue
		var region: Dictionary = region_value as Dictionary
		if str(region.get("role", "")) == MAP_TYPES.REGION_ROLE_HIGH_1:
			high_1_profile_id = str(region.get("content_profile_id", ""))
	for region_value: Variant in shared_regions:
		if region_value is Dictionary and str((region_value as Dictionary).get("role", "")) == MAP_TYPES.REGION_ROLE_HIGH_2:
			(region_value as Dictionary)["content_profile_id"] = high_1_profile_id
	var shared_plan_result = MAP_TYPES.decode_region_plan_authority(shared_profile_plan_dict)
	_expect(shared_plan_result.is_success(), "共享 content profile 的不同 rank RegionPlan 必须合法")
	if shared_plan_result.is_success():
		var shared_resolver = RESOLVER_SCRIPT.new(config, shared_plan_result.plan)
		var high_1 = shared_plan_result.plan.try_get_by_role(MAP_TYPES.REGION_ROLE_HIGH_1)
		var high_2 = shared_plan_result.plan.try_get_by_role(MAP_TYPES.REGION_ROLE_HIGH_2)
		_expect(high_1.difficulty_rank != high_2.difficulty_rank, "rank 解耦样本必须保留不同 difficulty_rank")
		_expect(
			shared_resolver.get_profile_for_role(MAP_TYPES.REGION_ROLE_HIGH_1)
			== shared_resolver.get_profile_for_role(MAP_TYPES.REGION_ROLE_HIGH_2),
			"不同 difficulty_rank 引用同一 profile 时 resolver 输出必须完全一致"
		)
		for budget_name: String in ["mineral_value_budget", "reward_value_budget"]:
			_expect(
				shared_resolver.get_value_budget(MAP_TYPES.REGION_ROLE_HIGH_1, budget_name)
				== shared_resolver.get_value_budget(MAP_TYPES.REGION_ROLE_HIGH_2, budget_name),
				"共享 profile 的 %s 不得因 difficulty_rank 产生倍率" % budget_name
			)
		for wall_kind: String in ["ordinary", "mineral", "poi"]:
			_expect(
				shared_resolver.get_wall_hit_points(high_1.center_cell, wall_kind)
				== shared_resolver.get_wall_hit_points(high_2.center_cell, wall_kind),
				"共享 profile 的 %s 墙耐久不得因 difficulty_rank 产生倍率" % wall_kind
			)
		var first_selection: Dictionary = shared_resolver.select_candidates(
			MAP_TYPES.REGION_ROLE_HIGH_1,
			"monster_sites",
			candidates,
			911
		)
		var second_selection: Dictionary = shared_resolver.select_candidates(
			MAP_TYPES.REGION_ROLE_HIGH_2,
			"monster_sites",
			candidates,
			911
		)
		_expect(
			first_selection.get("selected", []) == second_selection.get("selected", []),
			"共享 profile 的候选裁剪不得因 difficulty_rank 改变"
		)
		var first_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		first_rng.seed = 321321
		var second_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		second_rng.seed = 321321
		_expect(
			shared_resolver.pick_weighted_entry(
				MAP_TYPES.REGION_ROLE_HIGH_1,
				"monster_sites",
				first_rng
			)
			== shared_resolver.pick_weighted_entry(
				MAP_TYPES.REGION_ROLE_HIGH_2,
				"monster_sites",
				second_rng
			),
			"共享 profile 的权重选择不得因 difficulty_rank 改变"
		)

	var swapped_plan_dict: Dictionary = MAP_TYPES.encode_region_plan_authority(plan)
	var swapped_regions: Array = swapped_plan_dict.get("regions", []) as Array
	var high_2_profile_id: String = ""
	for region_value: Variant in swapped_regions:
		if not (region_value is Dictionary):
			continue
		var region: Dictionary = region_value as Dictionary
		match str(region.get("role", "")):
			MAP_TYPES.REGION_ROLE_HIGH_1:
				high_1_profile_id = str(region.get("content_profile_id", ""))
			MAP_TYPES.REGION_ROLE_HIGH_2:
				high_2_profile_id = str(region.get("content_profile_id", ""))
	for region_value: Variant in swapped_regions:
		if not (region_value is Dictionary):
			continue
		var region: Dictionary = region_value as Dictionary
		match str(region.get("role", "")):
			MAP_TYPES.REGION_ROLE_HIGH_1:
				region["content_profile_id"] = high_2_profile_id
			MAP_TYPES.REGION_ROLE_HIGH_2:
				region["content_profile_id"] = high_1_profile_id
	var swapped_plan_result = MAP_TYPES.decode_region_plan_authority(swapped_plan_dict)
	_expect(swapped_plan_result.is_success(), "交换 content profile 的 RegionPlan 必须合法")
	if swapped_plan_result.is_success():
		var swapped_resolver = RESOLVER_SCRIPT.new(config, swapped_plan_result.plan)
		_expect(
			swapped_resolver.get_profile_for_role(MAP_TYPES.REGION_ROLE_HIGH_1)
			== config.try_get_region_content_profile(high_2_profile_id)
			and swapped_resolver.get_profile_for_role(MAP_TYPES.REGION_ROLE_HIGH_2)
			== config.try_get_region_content_profile(high_1_profile_id),
			"resolver 输出必须随 content profile 引用交换，而不是黏在 difficulty_rank 上"
		)


func _test_derived_region_caches(generator: Variant, map_data: Variant) -> void:
	var plan = map_data.region_plan
	for collection_name: String in [
		"poi_instances",
		"monster_sites",
		"trap_sites",
		"camp_encounters",
		"player_spawn_points",
		"extraction_sites",
	]:
		var collection: Array = map_data.get(collection_name) as Array
		_expect(not collection.is_empty(), "%s 必须提供区域缓存验证样本" % collection_name)
		for item_value: Variant in collection:
			if not (item_value is Dictionary):
				continue
			var item: Dictionary = item_value as Dictionary
			var anchor: Vector2i = _site_anchor(item)
			var region = plan.try_get_at(anchor)
			_expect(region != null, "%s anchor 必须能查询 RegionPlan" % collection_name)
			if region == null:
				continue
			_expect(item.has("region_index"), "%s 必须保存派生 region_index" % collection_name)
			_expect(item.has("region_role"), "%s 必须保存派生 region_role" % collection_name)
			_expect(
				int(item.get("region_index", -1)) == region.index,
				"%s region_index 必须与 RegionPlan 一致" % collection_name
			)
			_expect(
				str(item.get("region_role", "")) == region.role,
				"%s region_role 必须与 RegionPlan 一致" % collection_name
			)

	for mineral_site: Dictionary in map_data.mineral_sites:
		_expect(
			not mineral_site.has("region_index") and not mineral_site.has("region_role"),
			"矿物 site 不得保存第二份区域归属缓存"
		)
	_test_mineral_site_negative_cases(generator, map_data)
	var property_names: Dictionary = {}
	for property_value: Variant in map_data.get_cell(0, 0).get_property_list():
		if property_value is Dictionary:
			property_names[str((property_value as Dictionary).get("name", ""))] = true
	for forbidden_name: String in ["region_index", "region_role", "content_profile_id"]:
		_expect(not property_names.has(forbidden_name), "CellData 不得保存 %s" % forbidden_name)

	for collection_name: String in [
		"poi_instances",
		"monster_sites",
		"trap_sites",
		"camp_encounters",
		"player_spawn_points",
		"extraction_sites",
	]:
		_test_cached_site_negative(generator, map_data, collection_name, "region_index")
		_test_cached_site_negative(generator, map_data, collection_name, "region_role")


func _test_mineral_site_negative_cases(generator: Variant, map_data: Variant) -> void:
	_expect(not map_data.mineral_sites.is_empty(), "矿物区域归属负向测试必须存在站点样本")
	if map_data.mineral_sites.is_empty():
		return
	for forbidden_field: String in ["region_index", "region_role"]:
		var cached_mineral = map_data.deep_clone()
		var cached_site: Dictionary = cached_mineral.mineral_sites[0]
		cached_site[forbidden_field] = (
			0 if forbidden_field == "region_index" else MAP_TYPES.REGION_ROLE_REGULAR
		)
		cached_mineral.mineral_sites[0] = cached_site
		_expect(
			_has_issue(
				generator.call("_validate_four_region_artifact", cached_mineral),
				"mineral_region_cache_not_allowed"
			),
			"final validator 必须拒绝矿物 site 的禁止缓存字段：%s" % forbidden_field
		)

	var crossed_mineral = map_data.deep_clone()
	var crossed_site: Dictionary = crossed_mineral.mineral_sites[0]
	var anchor: Vector2i = _site_anchor(crossed_site)
	var anchor_region = crossed_mineral.region_plan.try_get_at(anchor)
	var other_region = crossed_mineral.region_plan.try_get_by_role(
		MAP_TYPES.REGION_ROLE_HIGH_1
		if anchor_region == null or anchor_region.role != MAP_TYPES.REGION_ROLE_HIGH_1
		else MAP_TYPES.REGION_ROLE_HIGH_2
	)
	var cells: Array = (crossed_site.get("cells", []) as Array).duplicate(true)
	if cells.is_empty():
		cells.append(anchor)
	cells[0] = {"x": other_region.center_cell.x, "y": other_region.center_cell.y}
	crossed_site["cells"] = cells
	crossed_mineral.mineral_sites[0] = crossed_site
	_expect(
		_has_issue(
			generator.call("_validate_four_region_artifact", crossed_mineral),
			"mineral_site_region_mismatch"
		),
		"final validator 必须拒绝跨越 RegionPlan 区域的矿簇 footprint"
	)


func _test_cached_site_negative(
	generator: Variant,
	map_data: Variant,
	collection_name: String,
	field_name: String
) -> void:
	var mutated = map_data.deep_clone()
	var collection: Array = mutated.get(collection_name) as Array
	var item_index: int = _preferred_site_index(collection_name, collection)
	if item_index < 0:
		_expect(false, "%s 缺少 %s 负向样本" % [collection_name, field_name])
		return
	var item: Dictionary = collection[item_index] as Dictionary
	if field_name == "region_index":
		item["region_index"] = (int(item.get("region_index", 0)) + 1) % MAP_TYPES.REGION_ROLE_ORDER.size()
	else:
		var current_role: String = str(item.get("region_role", ""))
		item["region_role"] = (
			MAP_TYPES.REGION_ROLE_HIGH_1
			if current_role != MAP_TYPES.REGION_ROLE_HIGH_1
			else MAP_TYPES.REGION_ROLE_HIGH_2
		)
	collection[item_index] = item
	mutated.set(collection_name, collection)
	_expect(
		_has_issue(generator.call("_validate_four_region_artifact", mutated), "site_region_mismatch"),
		"final validator 必须拒绝 %s 的错误 %s 缓存" % [collection_name, field_name]
	)


func _test_final_artifact_rejections(generator: Variant, map_data: Variant) -> void:
	var duplicate_core = map_data.deep_clone()
	duplicate_core.poi_instances.append(
		_find_core_instance(duplicate_core, MAP_TYPES.REGION_ROLE_HIGH_1).duplicate(true)
	)
	_expect(
		_has_issue(generator.call("_validate_four_region_artifact", duplicate_core), "core_poi_count_mismatch"),
		"final validator 必须拒绝同区域重复核心 POI"
	)

	var crossed_footprint = map_data.deep_clone()
	var high_1_core_index: int = _find_core_instance_index(
		crossed_footprint,
		MAP_TYPES.REGION_ROLE_HIGH_1
	)
	var regular = crossed_footprint.region_plan.try_get_by_role(MAP_TYPES.REGION_ROLE_REGULAR)
	if high_1_core_index >= 0 and regular != null:
		var high_1_core: Dictionary = crossed_footprint.poi_instances[high_1_core_index]
		var footprint: Array = high_1_core.get("footprint_cells", []) as Array
		if not footprint.is_empty():
			footprint[0] = {"x": regular.center_cell.x, "y": regular.center_cell.y}
			high_1_core["footprint_cells"] = footprint
			crossed_footprint.poi_instances[high_1_core_index] = high_1_core
		_expect(
			_has_issue(
				generator.call("_validate_four_region_artifact", crossed_footprint),
				"core_poi_footprint_crosses_region"
			),
			"final validator 必须拒绝跨区核心 footprint"
		)

	var exceeded_offset = map_data.deep_clone()
	var offset_core_index: int = _find_core_instance_index(
		exceeded_offset,
		MAP_TYPES.REGION_ROLE_HIGH_1
	)
	if offset_core_index >= 0:
		var offset_core: Dictionary = exceeded_offset.poi_instances[offset_core_index]
		offset_core["canonical_center"] = Vector2i(-1024, -1024)
		exceeded_offset.poi_instances[offset_core_index] = offset_core
		_expect(
			_has_issue(
				generator.call("_validate_four_region_artifact", exceeded_offset),
				"core_poi_center_offset_exceeded"
			),
			"final validator 必须拒绝超过 canonical center 偏移的核心 POI"
		)

	var multiple_anchors = map_data.deep_clone()
	var boss_region = multiple_anchors.region_plan.try_get_by_role(MAP_TYPES.REGION_ROLE_BOSS)
	var descriptor = multiple_anchors.region_boss_encounter
	var alternate_boss_cell: Vector2i = _find_region_cell(
		multiple_anchors.region_plan,
		boss_region.index,
		descriptor.get_anchor_snapshots()[0].cell
	)
	var descriptor_result = MAP_TYPES.BossEncounterDescriptor.create_structurally_validated(
		multiple_anchors.region_plan,
		{
			"encounter_id": descriptor.get_encounter_id(),
			"region_id": descriptor.get_region_id(),
			"core_poi_instance_id": descriptor.get_core_poi_instance_id(),
			"encounter_profile_id": descriptor.get_encounter_profile_id(),
			"anchors": [
				{"id": "primary", "cell": descriptor.get_anchor_snapshots()[0].cell},
				{"id": "secondary", "cell": alternate_boss_cell},
			],
		}
	)
	_expect(descriptor_result.is_success(), "多 anchor 公共 descriptor 应可构造负向样本")
	if descriptor_result.is_success():
		multiple_anchors.region_boss_encounter = descriptor_result.descriptor
		_expect(
			_has_issue(
				generator.call("_validate_four_region_artifact", multiple_anchors),
				"boss_encounter_mismatch"
			),
			"首版 final validator 必须拒绝 primary 以外的额外 anchor"
		)

	var missing_reward_metadata = map_data.deep_clone()
	var boss_core_index: int = _find_core_instance_index(
		missing_reward_metadata,
		MAP_TYPES.REGION_ROLE_BOSS
	)
	if boss_core_index >= 0:
		var boss_core: Dictionary = missing_reward_metadata.poi_instances[boss_core_index]
		var metadata: Dictionary = (boss_core.get("core_metadata", {}) as Dictionary).duplicate(true)
		metadata.erase("reward_recipe_id")
		boss_core["core_metadata"] = metadata
		missing_reward_metadata.poi_instances[boss_core_index] = boss_core
		_expect(
			_has_issue(
				generator.call("_validate_four_region_artifact", missing_reward_metadata),
				"invalid_core_poi_metadata"
			),
			"final validator 必须拒绝缺失奖励配方的 BOSS 核心 metadata"
		)

	var special_extraction = map_data.deep_clone()
	(special_extraction.extraction_sites[0] as Dictionary)["site_kind"] = "stone_golem_vault"
	(special_extraction.extraction_sites[0] as Dictionary)["guaranteed"] = true
	_expect(
		_has_issue(
			generator.call("_validate_four_region_artifact", special_extraction),
			"special_extraction_not_allowed"
		),
		"final validator 必须拒绝四区域特殊撤离"
	)

	var blocked_boundary = map_data.deep_clone()
	_protect_regular_boundary(blocked_boundary, MAP_TYPES.REGION_ROLE_HIGH_2)
	_expect(
		_has_issue(
			generator.call("_validate_four_region_artifact", blocked_boundary),
			"missing_regular_access_boundary"
		),
		"final validator 必须拒绝保护结构封死 high_2 独立 regular 边界"
	)

	var blocked_route = map_data.deep_clone()
	var membership: PackedInt32Array = blocked_route.region_plan.get_region_index_by_cell_copy()
	var spawn_cell: Vector2i = _site_anchor(blocked_route.player_spawn_points[0])
	var extraction_cell: Vector2i = _site_anchor(blocked_route.extraction_sites[0])
	for flat_index: int in range(membership.size()):
		if int(membership[flat_index]) != 0:
			continue
		var cell_coord: Vector2i = Vector2i(
			flat_index % blocked_route.width,
			flat_index / blocked_route.width
		)
		if cell_coord == spawn_cell or cell_coord == extraction_cell:
			continue
		blocked_route.get_cell(cell_coord.x, cell_coord.y).is_poi_protected = true
	_expect(
		_has_issue(
			generator.call("_validate_four_region_artifact", blocked_route),
			"regular_route_missing"
		),
		"final validator 必须拒绝被永久保护结构切断的 regular-only 撤离路线"
	)


func _test_regular_only_fallback(generator: Variant, config: Variant, map_data: Variant) -> void:
	var blocked_regular = map_data.deep_clone()
	var membership: PackedInt32Array = blocked_regular.region_plan.get_region_index_by_cell_copy()
	for flat_index: int in range(membership.size()):
		if int(membership[flat_index]) != 0:
			continue
		var cell: Vector2i = Vector2i(flat_index % blocked_regular.width, flat_index / blocked_regular.width)
		blocked_regular.get_cell(cell.x, cell.y).is_poi_protected = true
	var resolver = RESOLVER_SCRIPT.new(config, blocked_regular.region_plan)
	var avoid_cells: Array[Vector2i] = []
	var result: Variant = generator.call(
		"_select_four_region_site_cell",
		blocked_regular,
		resolver,
		config.player_spawn_edge_margin_cells,
		config.player_spawn_clearance_radius_cells,
		config.player_spawn_min_clearance_ratio,
		avoid_cells,
		0.0,
		"player_spawn",
		generator.last_resolved_seed,
		0
	)
	_expect(
		_site_selection_cell(result) == Vector2i(-1, -1),
		"regular 候选全部不可用时 fallback 必须失败，不得越区选择高风险格"
	)

	var carved_regular = map_data.deep_clone()
	var carved_membership: PackedInt32Array = (
		carved_regular.region_plan.get_region_index_by_cell_copy()
	)
	for flat_index: int in range(carved_membership.size()):
		if int(carved_membership[flat_index]) != 0:
			continue
		var cell_coord: Vector2i = Vector2i(
			flat_index % carved_regular.width,
			flat_index / carved_regular.width
		)
		var cell = carved_regular.get_cell(cell_coord.x, cell_coord.y)
		if cell == null or cell.is_poi_protected:
			continue
		cell.cell_type = MAP_TYPES.CellType.WALL
		cell.has_mineral = false
		cell.special_block_type = MAP_TYPES.SpecialBlockType.NONE
	var carved_resolver = RESOLVER_SCRIPT.new(config, carved_regular.region_plan)
	var fallback_issues: Array[Dictionary] = generator.call(
		"_generate_four_region_spawn_and_extraction",
		carved_regular,
		config,
		carved_resolver,
		generator.last_resolved_seed,
		generator.last_four_region_success_attempt
	)
	_expect(
		fallback_issues.is_empty(),
		"regular 内仍有可雕刻格时出生撤离 fallback 必须成功：%s" % str(fallback_issues)
	)
	if fallback_issues.is_empty():
		for site: Dictionary in [
			carved_regular.player_spawn_points[0],
			carved_regular.extraction_sites[0],
		]:
			var site_cell: Vector2i = _site_anchor(site)
			_expect(
				carved_resolver.is_cell_in_role(site_cell, MAP_TYPES.REGION_ROLE_REGULAR),
				"雕刻 fallback 只能选择 regular 格：%s" % str(site)
			)
			_expect(
				str(site.get("fallback_reason", "")) == "carved_regular_cell",
				"雕刻 fallback 必须记录 carved_regular_cell：%s" % str(site)
			)
			_expect(
				carved_regular.get_cell(site_cell.x, site_cell.y).cell_type
				== MAP_TYPES.CellType.FLOOR,
				"雕刻 fallback 必须把最终站点变为可通行地板：%s" % str(site_cell)
			)
	_expect(map_data.player_spawn_points.size() == 1, "成功产物必须恰有一个出生锚点")
	_expect(map_data.extraction_sites.size() == 1, "成功产物必须恰有一个普通撤离点")
	var high_2 = map_data.region_plan.try_get_by_role(MAP_TYPES.REGION_ROLE_HIGH_2)
	_expect(
		bool(generator.call(
			"_has_unprotected_regular_access_boundary",
			map_data,
			map_data.region_plan.get_region_index_by_cell_copy(),
			high_2.index
		)),
		"high_2 必须拥有不依赖 high_1 的独立 regular 接触边界"
	)
	_expect(
		bool(generator.call(
			"_has_regular_only_route",
			map_data,
			map_data.region_plan.get_region_index_by_cell_copy(),
			_site_anchor(map_data.player_spawn_points[0]),
			_site_anchor(map_data.extraction_sites[0])
		)),
		"出生到撤离必须存在 regular-only 开放或标准可挖路线"
	)


func _test_failed_generation_atomicity(
	generator: Variant,
	config: Variant,
	map_data: Variant
) -> void:
	var baseline_seed: int = generator.last_resolved_seed
	var baseline_signature: Dictionary = _core_artifact_signature(map_data)
	var impossible_config = config.deep_clone()
	# Seed 2 的首个 layout attempt 可用，使本夹具只隔离核心 POI 放置失败。
	impossible_config.seed = 2
	for profile: Dictionary in impossible_config.region_generation.get("layout_profiles", []) as Array:
		profile["max_attempts"] = 1
	var high_1_slot: Dictionary = impossible_config.region_layout.get(
		MAP_TYPES.REGION_ROLE_HIGH_1,
		{}
	) as Dictionary
	var core_template_id: String = str(
		(high_1_slot.get("core_poi", {}) as Dictionary).get("template_id", "")
	)
	var bundle: Dictionary = impossible_config.get_meta("poi_resource_bundle", {}).duplicate(true)
	for template: Dictionary in impossible_config.poi_templates:
		if str(template.get("id", "")) == core_template_id:
			for node: Dictionary in bundle.compositions[str(template.composition_id)].nodes:
				if str(node.id) == "kitchen":
					# 必需单实例的合法固定偏移超过 POI 搜索边界，不能裁剪或退回旧矩形。
					node["position"] = {"x": 10000, "y": 10000}
					node["rotation"] = 0
			break
	impossible_config.set_meta("poi_resource_bundle", bundle)
	var failed_map = generator.generate_full(impossible_config)
	_expect(failed_map == null, "核心 POI 无法放置时整图必须失败")
	_expect(
		_has_issue(generator.get_last_generation_issues(), "core_poi_placement_failed"),
		"核心 POI 重试耗尽必须返回 core_poi_placement_failed"
	)
	_expect(generator.last_resolved_seed == baseline_seed, "失败生成不得替换上一张成功地图的 resolved seed")
	_expect(
		_core_artifact_signature(map_data) == baseline_signature,
		"失败生成不得修改调用方持有的上一张成功 MapData"
	)


func _test_camp_minimum_budget_reservation(
	config: Variant,
	baseline_success_attempt: int
) -> void:
	var insufficient_config = config.deep_clone()
	for profile_value: Variant in (
		insufficient_config.region_generation.get("layout_profiles", []) as Array
	):
		if profile_value is Dictionary:
			(profile_value as Dictionary)["max_attempts"] = maxi(
				baseline_success_attempt + 1,
				1
			)
	var high_1_profile: Dictionary = {}
	for profile_value: Variant in (
		insufficient_config.region_generation.get("content_profiles", []) as Array
	):
		if (
			profile_value is Dictionary
			and str((profile_value as Dictionary).get("id", ""))
			== "ancient_old_mine_high_1_content"
		):
			high_1_profile = profile_value as Dictionary
			break
	_expect(not high_1_profile.is_empty(), "camp minimum 预算守门必须找到 high_1 content profile")
	if high_1_profile.is_empty():
		return
	high_1_profile["reward_value_budget"] = 5
	var room_contents: Dictionary = high_1_profile.get("room_contents", {}) as Dictionary
	room_contents["target_count"] = 1
	room_contents["minimum_count"] = 1
	room_contents["entries"] = [
		{"content_kind": "monster_pack", "weight": 1.0, "value_cost": 1},
		{"content_kind": "camp", "weight": 1.0, "value_cost": 2},
	]
	var camps: Dictionary = high_1_profile.get("camps", {}) as Dictionary
	camps["target_count"] = 1
	camps["minimum_count"] = 1
	camps["entries"] = [
		{"camp_id": "miner_settlement_supply_camp", "weight": 1.0, "value_cost": 4},
	]

	var budget_generator = GENERATOR_SCRIPT.new()
	var failed_map = budget_generator.generate_full(insufficient_config)
	_expect(failed_map == null, "reward budget 低于 camp room 双重 minimum 成本时整图必须失败")
	var generation_issues: Array[Dictionary] = budget_generator.get_last_generation_issues()
	_expect(
		_has_issue(generation_issues, "required_slot_budget_unavailable"),
		"camp minimum 预留不足必须在必需图纸槽分配时阻止公开 generate_full：%s"
		% str(generation_issues)
	)


func _core_artifact_signature(map_data: Variant) -> Dictionary:
	var result: Dictionary = {
		"spawn": map_data.player_spawn_points.duplicate(true),
		"extraction": map_data.extraction_sites.duplicate(true),
		"cores": [],
		"encounter": {},
	}
	for role: String in [
		MAP_TYPES.REGION_ROLE_HIGH_1,
		MAP_TYPES.REGION_ROLE_HIGH_2,
		MAP_TYPES.REGION_ROLE_BOSS,
	]:
		var region = map_data.region_plan.try_get_by_role(role)
		var core: Dictionary = _find_core_instance(map_data, role)
		(result["cores"] as Array).append({
			"role": role,
			"region_id": region.id,
			"center": region.center_cell,
			"anchor": region.core_anchor_cell,
			"template_id": region.core_poi_template_id,
			"instance_id": region.core_poi_instance_id,
			"footprint": (core.get("footprint_cells", []) as Array).duplicate(true),
			"metadata": (core.get("core_metadata", {}) as Dictionary).duplicate(true),
		})
	var descriptor = map_data.region_boss_encounter
	if descriptor != null:
		var anchors: Array[Dictionary] = []
		for anchor in descriptor.get_anchor_snapshots():
			anchors.append({"id": anchor.id, "cell": anchor.cell})
		result["encounter"] = {
			"encounter_id": descriptor.get_encounter_id(),
			"region_id": descriptor.get_region_id(),
			"core_poi_instance_id": descriptor.get_core_poi_instance_id(),
			"encounter_profile_id": descriptor.get_encounter_profile_id(),
			"anchors": anchors,
		}
	return result


func _protect_regular_boundary(map_data: Variant, role: String) -> void:
	var plan = map_data.region_plan
	var region = plan.try_get_by_role(role)
	var membership: PackedInt32Array = plan.get_region_index_by_cell_copy()
	for flat_index: int in range(membership.size()):
		if int(membership[flat_index]) != region.index:
			continue
		var cell: Vector2i = Vector2i(flat_index % map_data.width, flat_index / map_data.width)
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + direction
			if not map_data.is_in_bounds(neighbor.x, neighbor.y):
				continue
			if int(membership[neighbor.y * map_data.width + neighbor.x]) != 0:
				continue
			map_data.get_cell(cell.x, cell.y).is_poi_protected = true
			map_data.get_cell(neighbor.x, neighbor.y).is_poi_protected = true


func _preferred_site_index(collection_name: String, collection: Array) -> int:
	if collection_name != "poi_instances":
		return 0 if not collection.is_empty() else -1
	for index: int in range(collection.size()):
		var value: Variant = collection[index]
		if value is Dictionary and not bool((value as Dictionary).get("is_core", false)):
			return index
	return -1


func _find_adjacent_region_pair(plan: Variant, region_index: int) -> Array[Vector2i]:
	var map_size: Vector2i = plan.get_map_size()
	var membership: PackedInt32Array = plan.get_region_index_by_cell_copy()
	for flat_index: int in range(membership.size()):
		if int(membership[flat_index]) != region_index:
			continue
		var cell: Vector2i = Vector2i(flat_index % map_size.x, flat_index / map_size.x)
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + direction
			if neighbor.x >= map_size.x or neighbor.y >= map_size.y:
				continue
			if int(membership[neighbor.y * map_size.x + neighbor.x]) == region_index:
				var pair: Array[Vector2i] = [cell, neighbor]
				return pair
	var empty: Array[Vector2i] = []
	return empty


func _find_region_cell(plan: Variant, region_index: int, excluded: Vector2i) -> Vector2i:
	var map_size: Vector2i = plan.get_map_size()
	var membership: PackedInt32Array = plan.get_region_index_by_cell_copy()
	for flat_index: int in range(membership.size()):
		if int(membership[flat_index]) != region_index:
			continue
		var cell: Vector2i = Vector2i(flat_index % map_size.x, flat_index / map_size.x)
		if cell != excluded:
			return cell
	return excluded


func _core_instances_for_role(map_data: Variant, role: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for instance: Dictionary in map_data.poi_instances:
		if bool(instance.get("is_core", false)) and str(instance.get("region_role", "")) == role:
			result.append(instance)
	return result


func _find_core_instance(map_data: Variant, role: String) -> Dictionary:
	var matches: Array[Dictionary] = _core_instances_for_role(map_data, role)
	return matches[0] if matches.size() == 1 else {}


func _find_core_instance_index(map_data: Variant, role: String) -> int:
	for index: int in range(map_data.poi_instances.size()):
		var instance: Dictionary = map_data.poi_instances[index]
		if bool(instance.get("is_core", false)) and str(instance.get("region_role", "")) == role:
			return index
	return -1


func _site_selection_cell(result: Variant) -> Vector2i:
	if result is Vector2i:
		return result as Vector2i
	if result is Dictionary:
		return _cell_from_variant((result as Dictionary).get("cell", Vector2i(-1, -1)))
	return Vector2i(-1, -1)


func _site_anchor(item: Dictionary) -> Vector2i:
	if item.has("center_cell"):
		return _cell_from_variant(item.get("center_cell"))
	if item.has("chest_cell"):
		return _cell_from_variant(item.get("chest_cell"))
	if item.has("cell"):
		return _cell_from_variant(item.get("cell"))
	return Vector2i(int(item.get("x", -1)), int(item.get("y", -1)))


func _rect_from_variant(value: Variant) -> Rect2i:
	if value is Rect2i:
		return value as Rect2i
	if value is Dictionary:
		var data: Dictionary = value as Dictionary
		return Rect2i(
			int(data.get("x", 0)),
			int(data.get("y", 0)),
			int(data.get("width", 0)),
			int(data.get("height", 0))
		)
	return Rect2i()


func _cell_set(values: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not (values is Array):
		return result
	for value: Variant in values as Array:
		var cell: Vector2i = _cell_from_variant(value)
		result[_cell_key(cell)] = true
	return result


func _cell_from_variant(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Dictionary:
		return Vector2i(
			int((value as Dictionary).get("x", -1)),
			int((value as Dictionary).get("y", -1))
		)
	return Vector2i(-1, -1)


func _cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


func _has_issue(issues_value: Variant, code: String) -> bool:
	if not (issues_value is Array):
		return false
	for issue_value: Variant in issues_value as Array:
		if issue_value is Dictionary and str((issue_value as Dictionary).get("code", "")) == code:
			return true
	return false


func _has_issue_at_path(issues_value: Variant, code: String, path: String) -> bool:
	if not (issues_value is Array):
		return false
	for issue_value: Variant in issues_value as Array:
		if not (issue_value is Dictionary):
			continue
		var issue: Dictionary = issue_value as Dictionary
		if str(issue.get("code", "")) == code and str(issue.get("path", "")) == path:
			return true
	return false


func _result_has_issue(result: Dictionary, code: String) -> bool:
	if result.get("issue", null) is Dictionary:
		return str((result.get("issue") as Dictionary).get("code", "")) == code
	return _has_issue(result.get("issues", []), code)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("four_region_artifact_validator_smoke: %s" % failure)
		quit(1)
		return
	print("four_region_artifact_validator_smoke: PASS")
	quit(0)
