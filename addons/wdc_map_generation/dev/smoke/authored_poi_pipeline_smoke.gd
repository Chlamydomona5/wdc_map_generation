extends SceneTree

const CATALOG = preload("../../config/data_generated_map_config_catalog.gd")
const GENERATOR = preload("../../core/generated_map_generator.gd")
const TYPES = preload("../../core/generated_map_types.gd")
const RESOLVER = preload("../../core/region_content_resolver.gd")
const ALLOCATOR = preload("../../core/authored_poi_content_allocator.gd")
const POPULATION = preload("../../core/poi_population_contract.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var raw: Dictionary = CATALOG.load_config_dict_by_filename("ancient_old_mine")
	var parsed = CATALOG.parse_and_normalize_config(raw)
	_check(parsed.is_success(), "正式 v3 地图必须通过解析")
	if not parsed.is_success():
		_finish()
		return
	_test_schema(raw, parsed)
	var generator = GENERATOR.new()
	var map_data = generator.generate_full(parsed.config)
	_check(map_data != null, "正式生成必须成功：" + str(generator.last_generation_issues))
	if map_data != null:
		_test_artifact(map_data)
		_test_budgets(parsed.config, map_data)
		_test_population(parsed.config, map_data)
	_finish()


func _test_schema(raw: Dictionary, parsed: Variant) -> void:
	var serialized: Dictionary = CATALOG.serialize_normalized_config(parsed)
	_check(int(serialized.schema_version) == 3, "保存必须保留 v3")
	var references: Array = []
	for template: Dictionary in serialized.poi_generation.poi_types:
		if template.get("layout_kind") == "authored_rooms":
			references.append(str(template.get("composition_id", "")))
	_check(references.size() == 3 and not references.has(""), "三个核心组合引用必须无损")
	var legacy: Dictionary = raw.duplicate(true)
	legacy.schema_version = 2
	_check(not CATALOG.parse_and_normalize_config(legacy).is_success(), "v2 不能静默忽略 authored_rooms")
	var mixed: Dictionary = raw.duplicate(true)
	for template: Dictionary in mixed.poi_generation.poi_types:
		if template.get("layout_kind") == "authored_rooms":
			template["main_room"] = {"width_min": 5}
			break
	_check(not CATALOG.parse_and_normalize_config(mixed).is_success(), "新组合不能混入旧矩形生成规则")
	var missing: Dictionary = raw.duplicate(true)
	for template: Dictionary in missing.poi_generation.poi_types:
		if template.get("layout_kind") == "authored_rooms":
			template.composition_id = "missing_composition"
			break
	_check(not CATALOG.parse_and_normalize_config(missing).is_success(), "缺失依赖必须阻止激活")


func _test_artifact(map_data: Variant) -> void:
	var occupied: Dictionary = {}
	var plans: Dictionary = {}
	var actual: Dictionary = {}
	for poi: Dictionary in map_data.poi_instances:
		if poi.get("layout_kind") != "authored_rooms":
			continue
		_check(poi.get("room_content_plans", []).is_empty(), "图纸不能再走旧随机填房")
		for point: Dictionary in poi.footprint_cells:
			occupied[Vector2i(point.x, point.y)] = str(poi.instance_id)
		for plan: Dictionary in poi.content_plans:
			_check(not plans.has(plan.plan_id), "内容计划来源必须唯一")
			plans[plan.plan_id] = plan
			if plan.kind == "torch":
				_check(poi.torch_sites.has(plan.cell), "火把必须消费确切槽位")
	for site: Dictionary in map_data.furnishing_sites + map_data.monster_sites + map_data.camp_encounters + map_data.mineral_sites + map_data.trap_sites:
		var plan_id: String = str(site.get("source_room_content_plan_id", ""))
		if not plan_id.is_empty() and plans.has(plan_id):
			actual[plan_id] = int(actual.get(plan_id, 0)) + 1
		var source: String = str(site.get("source_poi_id", site.get("source_poi_instance_id", "")))
		var points: Array = site.get("cells", site.get("nodes", [site.get("cell", site.get("chest_cell", {}))]))
		for point: Variant in points:
			var cell: Vector2i = point if point is Vector2i else Vector2i(int(point.get("x", -999)), int(point.get("y", -999))) if point is Dictionary else Vector2i(-999, -999)
			if occupied.has(cell):
				_check(source == occupied[cell], "外部随机填充不能覆盖已接管 footprint")
	for id: String in plans:
		if plans[id].kind != "torch":
			_check(int(actual.get(id, 0)) == 1, "内容必须只物化一次：" + id)
	_check(not map_data.furnishing_sites.is_empty(), "正式地图必须输出真实道具")
	var copied = map_data.deep_clone()
	_check(copied.furnishing_sites == map_data.furnishing_sites and copied.poi_instances == map_data.poi_instances, "快照必须保留图纸和道具来源")


func _request(id: String, kind: String, content_id: String, required: bool = true, guards: int = 0) -> Dictionary:
	return {"request_id": id, "slot_id": id, "room_instance_id": "room:0", "kind": kind,
		"content_id": content_id, "entries": [{"id": content_id, "weight": 1}],
		"required": required, "group_required": required, "member_required": true,
		"group_instance_id": id, "guard_cells": range(guards)}


func _fixture(config: Variant, map_data: Variant, requests: Array, budget: int) -> Dictionary:
	var local_config = config.deep_clone()
	var profile_id: String = map_data.region_plan.try_get_by_role("high_1").content_profile_id
	var profile: Dictionary = {"id": profile_id, "reward_value_budget": budget, "mineral_value_budget": budget}
	var definitions: Dictionary = {
		"furnishings": [{"content_id": "cheap", "weight": 1, "value_cost": 1}, {"content_id": "expensive", "weight": 1, "value_cost": 9}, {"content_id": "mandatory", "weight": 1, "value_cost": 4}],
		"camps": [{"camp_id": "camp", "weight": 1, "value_cost": 3}],
		"monster_sites": [{"spawn_template_id": "unit", "weight": 1, "value_cost": 1}],
		"nests": [{"nest_template_id": "nest", "weight": 1, "value_cost": 1}],
		"room_contents": [{"content_kind": "camp", "weight": 1, "value_cost": 2}, {"content_kind": "monster_pack", "weight": 1, "value_cost": 1}, {"content_kind": "nest", "weight": 1, "value_cost": 1}]}
	for section: String in definitions:
		profile[section] = {"target_count": 100, "minimum_count": 0, "entries": definitions[section]}
	local_config.region_generation = {"content_profiles": [profile]}
	var data = TYPES.MapData.new()
	data.width = map_data.width
	data.height = map_data.height
	data.region_plan = map_data.region_plan
	data.poi_instances.append({"instance_id": "test", "layout_kind": "authored_rooms", "region_role": "high_1", "region_index": 1, "content_requests": requests})
	return {"map": data, "resolver": RESOLVER.new(local_config, data.region_plan), "profile": profile}


func _test_budgets(config: Variant, map_data: Variant) -> void:
	var f: Dictionary = _fixture(config, map_data, [_request("a", "prop", "cheap"), _request("b", "prop", "expensive", false)], 1)
	_check(ALLOCATOR.allocate(f.map, f.resolver, 1).is_empty() and f.map.poi_instances[0].content_plans.size() == 1, "可选内容须按剩余预算裁剪")
	f = _fixture(config, map_data, [_request("camp", "camp", "camp", true, 2)], 5)
	_check(ALLOCATOR.allocate(f.map, f.resolver, 1).is_empty(), "营地双重成本预算足够应通过")
	_check(f.resolver.get_remaining_value_budget("high_1", "reward_value_budget") == 0, "营地成本3加房间成本2必须合计扣5")
	_check(f.resolver.get_reserved_count("high_1", "camps") == 1 and f.resolver.get_reserved_count("high_1", "room_contents") == 1, "营地必须分别更新两类计数")
	f = _fixture(config, map_data, [_request("camp", "camp", "camp", true, 2)], 4)
	_check(not ALLOCATOR.allocate(f.map, f.resolver, 1).is_empty(), "必需内容不能超支后报告成功")
	var weighted: Dictionary = _request("a", "prop", "cheap")
	weighted.entries.append({"id": "expensive", "weight": 1000000})
	f = _fixture(config, map_data, [weighted, _request("z", "prop", "mandatory")], 5)
	_check(ALLOCATOR.allocate(f.map, f.resolver, 3).is_empty(), "前面的加权候选不能吞掉后面必需槽的最低预留")
	var optional_member: Dictionary = _request("b", "prop", "mandatory", false)
	optional_member.group_instance_id = "a"
	optional_member.group_required = true
	optional_member.member_required = false
	f = _fixture(config, map_data, [_request("a", "prop", "cheap"), optional_member, _request("z", "prop", "mandatory")], 5)
	_check(ALLOCATOR.allocate(f.map, f.resolver, 1).is_empty() and f.map.poi_instances[0].content_plans.size() == 2, "必需组里的可选成员不能抢占另一必需组")


func _test_population(config: Variant, map_data: Variant) -> void:
	var limits: Dictionary = {"poi_initial_live_cap": 2, "poi_initial_per_poi_cap": 2, "nest_site_cap": 1, "ordinary_initial_target": 1, "ordinary_live_cap": 1, "total_live_monster_safety_cap": 3}
	var f: Dictionary = _fixture(config, map_data, [_request("a", "camp", "camp", true, 2), _request("b", "monster_pack", "unit", false), _request("c", "nest", "nest", false), _request("d", "nest", "nest", false)], 100)
	_check(ALLOCATOR.allocate(f.map, f.resolver, 1, limits).is_empty(), "可选人口超限须裁剪而非整图失败")
	var kinds: Array = []
	for plan: Dictionary in f.map.poi_instances[0].content_plans:
		kinds.append(plan.kind)
	_check(kinds.count("camp") == 1 and kinds.count("monster_pack") == 0 and kinds.count("nest") == 1, "守卫/怪物/巢穴必须共享实际人口剩余额度")
	f = _fixture(config, map_data, [_request("a", "camp", "camp", true, 3)], 100)
	var issues: Array[Dictionary] = ALLOCATOR.allocate(f.map, f.resolver, 1, limits)
	_check(not issues.is_empty() and issues[0].code == "required_slot_population_unavailable", "必需人口超限必须报具体槽位")
	f = _fixture(config, map_data, [_request("a", "camp", "camp", true, 3)], 100)
	_check(ALLOCATOR.allocate(f.map, f.resolver, 1, {}).is_empty(), "无人口参数的局部预算夹具不可误作全部上限为0")
	_check(POPULATION.ordinary_initial_count(map_data, {"ordinary_initial_target": 100, "ordinary_live_cap": 0, "auto_live_cap_area_divisor_cells": map_data.width * map_data.height / 2.0}) == 2, "自动 live cap 必须参与初始人口上限")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	print("AUTHORED_POI_PIPELINE_SMOKE ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
