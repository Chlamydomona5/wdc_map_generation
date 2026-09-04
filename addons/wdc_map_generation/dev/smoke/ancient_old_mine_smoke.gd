extends SceneTree

const CONFIG_CATALOG = preload("../../config/data_generated_map_config_catalog.gd")
const MAP_TYPES = preload("../../core/generated_map_types.gd")
const GENERATOR_SCRIPT = preload("../../core/generated_map_generator.gd")
const REGION_CONTENT_RESOLVER = preload("../../core/region_content_resolver.gd")

var _failures: Array[String] = []


func _init() -> void:
	var raw_config: Dictionary = CONFIG_CATALOG.load_config_dict_by_filename("ancient_old_mine")
	_expect(not raw_config.is_empty(), "必须能从 canonical 配置目录加载 ancient_old_mine")
	if raw_config.is_empty():
		_finish()
		return
	_test_static_contract(raw_config)
	var parse_result = CONFIG_CATALOG.parse_and_normalize_config(raw_config)
	_expect(
		parse_result.is_success(),
		"ancient_old_mine 必须通过 canonical parser：%s" % str(parse_result.get_issues())
	)
	if parse_result.is_success():
		_test_generated_artifact(parse_result.config)
	_finish()


func _test_static_contract(raw_config: Dictionary) -> void:
	_expect(int(raw_config.get("schema_version", 0)) == 2, "配置必须保持 schema_version=2")
	_expect(str(raw_config.get("id", "")) == "ancient_old_mine", "配置 id 必须稳定")
	_expect(not raw_config.has("map_layers"), "四区域配置不得携带 legacy map_layers")
	_expect(not raw_config.has("boss_generation"), "四区域配置不得携带 legacy boss_generation")
	var map_config: Dictionary = raw_config.get("map", {}) as Dictionary
	_expect(
		int(map_config.get("width_cells", 0)) == 128
		and int(map_config.get("height_cells", 0)) == 128,
		"古代旧矿必须使用 128x128"
	)
	var seed: Dictionary = map_config.get("seed", {}) as Dictionary
	_expect(
		str(seed.get("mode", "")) == "fixed" and int(seed.get("fixed_value", 0)) > 0,
		"古代旧矿必须声明非零 fixed seed"
	)
	_expect(
		int((map_config.get("player_spawn", {}) as Dictionary).get("count", 0)) == 1,
		"古代旧矿必须声明一个出生锚点"
	)
	_expect(
		int((map_config.get("extraction_sites", {}) as Dictionary).get("count", 0)) == 1,
		"古代旧矿必须声明一个普通撤离点"
	)
	var region_layout: Dictionary = raw_config.get("region_layout", {}) as Dictionary
	_expect(
		str(region_layout.get("mode", "")) == MAP_TYPES.LAYOUT_MODE_PVE_FOUR_REGION_V1,
		"古代旧矿必须使用 pve_four_region_v1"
	)
	var core_template_ids: Dictionary = {}
	for role: String in ["high_1", "high_2", "boss"]:
		var slot: Dictionary = region_layout.get(role, {}) as Dictionary
		var template_id: String = str(
			(slot.get("core_poi", {}) as Dictionary).get("template_id", "")
		)
		_expect(not template_id.is_empty(), "%s 必须声明核心 POI" % role)
		_expect(not core_template_ids.has(template_id), "三个核心 POI 模板必须互不重复")
		core_template_ids[template_id] = true
	var generation: Dictionary = raw_config.get("region_generation", {}) as Dictionary
	for layout_profile_value: Variant in generation.get("layout_profiles", []) as Array:
		if layout_profile_value is Dictionary:
			_expect(
				str((layout_profile_value as Dictionary).get("shape_algorithm", ""))
				== "noisy_ellipse",
				"古代旧矿三个高风险区必须全部使用噪声不规则圆形"
			)
	var regular: Dictionary = _find_profile(
		generation.get("content_profiles", []),
		"ancient_old_mine_regular_content"
	)
	var high_1: Dictionary = _find_profile(
		generation.get("content_profiles", []),
		"ancient_old_mine_high_1_content"
	)
	var high_2: Dictionary = _find_profile(
		generation.get("content_profiles", []),
		"ancient_old_mine_high_2_content"
	)
	var boss: Dictionary = _find_profile(
		generation.get("content_profiles", []),
		"ancient_old_mine_boss_content"
	)
	_expect(not regular.is_empty() and not high_1.is_empty() and not high_2.is_empty() and not boss.is_empty(), "必须声明四个 content profile")
	_expect(
		int(regular.get("mineral_value_budget", -1)) == 24
		and _target_count(regular, "minerals") == 18
		and _minimum_count(regular, "minerals") == 9,
		"regular 矿物 budget/target/minimum 必须为原基线 8/6/3 的三倍"
	)
	_expect(int(regular.get("reward_value_budget", -1)) == 0, "regular reward budget 必须为零")
	for section_name: String in ["room_contents", "traps", "monster_sites", "nests", "camps"]:
		_expect(_target_count(regular, section_name) == 0, "regular %s target 必须为零" % section_name)
	_expect(_minimum_count(high_1, "monster_sites") >= 1, "high_1 固定守卫 minimum 必须至少为 1")
	_expect(_minimum_count(high_1, "traps") >= 1, "high_1 简单陷阱 minimum 必须至少为 1")
	_expect(
		_target_count(high_2, "monster_sites") > _target_count(high_1, "monster_sites"),
		"high_2 守卫 target 必须高于 high_1"
	)
	_expect(
		_entry_weight(high_2, "monster_sites", "spawn_template_id", "skeleton_archer_single")
		> _entry_weight(high_1, "monster_sites", "spawn_template_id", "skeleton_archer_single"),
		"high_2 骷髅弓手权重必须高于 high_1"
	)
	_expect(
		_target_count(high_2, "traps") > _target_count(high_1, "traps"),
		"high_2 陷阱 target 必须高于 high_1"
	)
	_expect(
		_is_strict_entry_superset(high_2, high_1, "traps", "trap_kind"),
		"high_2 陷阱集合必须严格包含 high_1"
	)
	_expect(
		int(high_2.get("mineral_value_budget", 0)) > int(high_1.get("mineral_value_budget", 0)),
		"high_2 mineral value budget 必须高于 high_1"
	)
	_expect(
		int(high_2.get("reward_value_budget", 0)) > int(high_1.get("reward_value_budget", 0)),
		"high_2 reward value budget 必须高于 high_1"
	)
	for section_name: String in ["minerals", "pois", "room_contents", "traps", "monster_sites", "nests", "camps"]:
		_expect(_target_count(boss, section_name) == 0, "boss %s target 必须为零" % section_name)
	var poi_types: Array = (raw_config.get("poi_generation", {}) as Dictionary).get("poi_types", []) as Array
	for template_id: String in core_template_ids.keys():
		_expect(not _find_template(poi_types, template_id).is_empty(), "核心 POI 模板必须存在：%s" % template_id)
	var boss_template: Dictionary = _find_template(poi_types, "command_vault_core")
	var core_metadata: Dictionary = boss_template.get("core_metadata", {}) as Dictionary
	_expect(
		str(core_metadata.get("reward_recipe_id", "")) == "ancient_old_mine_vault_rewards_v1",
		"总控金库必须引用稳定奖励配方"
	)
	_expect(
		(core_metadata.get("reward_gate_cells", []) as Array).size() >= 1
		and (core_metadata.get("reward_object_cells", []) as Array).size() >= 1,
		"总控金库必须声明奖励门格和奖励物件位置"
	)


func _test_generated_artifact(config: Variant) -> void:
	var generator = GENERATOR_SCRIPT.new()
	var map_data = generator.generate_full(config)
	_expect(
		map_data != null,
		"验收 seed 必须生成成功：%s" % str(generator.get_last_generation_issues())
	)
	if map_data == null:
		return
	_expect(map_data.layout_mode == MAP_TYPES.LAYOUT_MODE_PVE_FOUR_REGION_V1, "最终地图 mode 错误")
	_expect(map_data.region_plan is MAP_TYPES.RegionPlan, "最终地图必须携带 RegionPlan")
	_expect(map_data.region_boss_encounter is MAP_TYPES.BossEncounterDescriptor, "最终地图必须携带单值 BOSS descriptor")
	if not (map_data.region_plan is MAP_TYPES.RegionPlan):
		return
	var plan = map_data.region_plan as MAP_TYPES.RegionPlan
	var core_ids: Dictionary = {}
	for role: String in MAP_TYPES.REGION_ROLE_ORDER:
		var snapshot = plan.try_get_by_role(role)
		_expect(snapshot != null, "RegionPlan 缺少角色：%s" % role)
		if snapshot == null:
			continue
		_expect(snapshot.difficulty_rank == MAP_TYPES.get_region_difficulty_rank(role), "%s difficulty rank 错误" % role)
		if role != MAP_TYPES.REGION_ROLE_REGULAR:
			_expect(not snapshot.core_poi_instance_id.is_empty(), "%s 核心 identity 不能为空" % role)
			_expect(not core_ids.has(snapshot.core_poi_instance_id), "核心 identity 必须唯一")
			core_ids[snapshot.core_poi_instance_id] = true
	_expect(map_data.player_spawn_points.size() == 1, "最终地图必须恰有一个出生锚点")
	_expect(map_data.extraction_sites.size() == 1, "最终地图必须恰有一个普通撤离点")
	if map_data.player_spawn_points.size() == 1:
		_expect(_site_region_role(map_data.player_spawn_points[0], plan) == MAP_TYPES.REGION_ROLE_REGULAR, "出生锚点必须位于 regular")
	if map_data.extraction_sites.size() == 1:
		var extraction: Dictionary = map_data.extraction_sites[0]
		_expect(_site_region_role(extraction, plan) == MAP_TYPES.REGION_ROLE_REGULAR, "撤离点必须位于 regular")
		_expect(str(extraction.get("extraction_kind", "normal")) == "normal", "古代旧矿不得生成特殊撤离")
		_expect(str(extraction.get("site_kind", "extraction")) == "extraction", "古代旧矿必须使用普通撤离 site kind")
		_expect(not bool(extraction.get("guaranteed", false)), "古代旧矿普通撤离不得 guaranteed")
	var descriptor = map_data.region_boss_encounter as MAP_TYPES.BossEncounterDescriptor
	_expect(
		descriptor.get_encounter_profile_id() == "ancient_old_mine_stone_golem_v1",
		"BOSS descriptor profile id 错误"
	)
	var anchors: Array = descriptor.get_anchor_snapshots()
	_expect(
		anchors.size() == 1 and str(anchors[0].id) == "primary",
		"BOSS descriptor 必须只有 primary anchor"
	)
	var core_count_by_role: Dictionary = {"high_1": 0, "high_2": 0, "boss": 0}
	var reward_metadata_seen: bool = false
	for poi_instance: Dictionary in map_data.poi_instances:
		var role: String = str(poi_instance.get("region_role", ""))
		if bool(poi_instance.get("is_core", false)) and core_count_by_role.has(role):
			core_count_by_role[role] = int(core_count_by_role.get(role, 0)) + 1
		if role == MAP_TYPES.REGION_ROLE_BOSS and bool(poi_instance.get("is_core", false)):
			var metadata: Dictionary = poi_instance.get("core_metadata", {}) as Dictionary
			reward_metadata_seen = (
				str(metadata.get("reward_recipe_id", "")) == "ancient_old_mine_vault_rewards_v1"
				and not (metadata.get("reward_gate_cells", []) as Array).is_empty()
				and not (metadata.get("reward_object_cells", []) as Array).is_empty()
			)
			_validate_reward_geometry(map_data, poi_instance, metadata)
	for role: String in core_count_by_role.keys():
		_expect(int(core_count_by_role.get(role, 0)) == 1, "%s 必须恰有一个核心 POI" % role)
	_expect(reward_metadata_seen, "BOSS 核心 POI 必须携带绝对格奖励 metadata")
	_validate_generated_content_counts(map_data, config, plan)
	_validate_room_content_materialization(map_data, config, plan)
	var reward_spent_by_role: Dictionary = _reward_spent_by_role(map_data)
	_validate_role_budgets(config, plan, reward_spent_by_role, "reward_value_budget")
	_expect(
		int(reward_spent_by_role.get("high_2", 0)) > int(reward_spent_by_role.get("high_1", 0)),
		"最终 high_2 reward budget 消费必须高于 high_1"
	)
	var monster_count_by_role: Dictionary = {}
	for monster_site: Dictionary in map_data.monster_sites:
		var role: String = _site_region_role(monster_site, plan)
		_expect(role in [MAP_TYPES.REGION_ROLE_HIGH_1, MAP_TYPES.REGION_ROLE_HIGH_2], "普通怪物点不得污染 regular/boss")
		monster_count_by_role[role] = int(monster_count_by_role.get(role, 0)) + 1
	_expect(int(monster_count_by_role.get("high_1", 0)) >= 1, "high_1 必须产出固定守卫点")
	_expect(int(monster_count_by_role.get("high_2", 0)) > int(monster_count_by_role.get("high_1", 0)), "high_2 最终守卫点必须多于 high_1")
	var trap_count_by_role: Dictionary = {}
	for trap_site: Dictionary in map_data.trap_sites:
		var role: String = _site_region_role(trap_site, plan)
		_expect(role in [MAP_TYPES.REGION_ROLE_HIGH_1, MAP_TYPES.REGION_ROLE_HIGH_2], "随机陷阱不得污染 regular/boss")
		trap_count_by_role[role] = int(trap_count_by_role.get(role, 0)) + 1
	_expect(int(trap_count_by_role.get("high_1", 0)) >= 1, "high_1 必须产出简单陷阱")
	_expect(int(trap_count_by_role.get("high_2", 0)) > int(trap_count_by_role.get("high_1", 0)), "high_2 最终陷阱必须多于 high_1")
	var mineral_value_by_role: Dictionary = {}
	for site: Dictionary in map_data.mineral_sites:
		var role: String = _site_region_role(site, plan)
		mineral_value_by_role[role] = int(mineral_value_by_role.get(role, 0)) + int(site.get("value_cost", 0))
	_validate_mineral_site_materialization(map_data)
	_validate_role_budgets(config, plan, mineral_value_by_role, "mineral_value_budget")
	_expect(
		int(mineral_value_by_role.get("high_2", 0)) > int(mineral_value_by_role.get("high_1", 0)),
		"最终 high_2 矿物 value budget 消费必须高于 high_1"
	)
	_validate_poi_wall_integrity(map_data, config, plan)
	_test_value_budget_enforcement(generator, map_data, config)
	_test_final_artifact_rejections(generator, map_data)
	_test_extraction_distance_fallback(generator, map_data, config)


func _validate_generated_content_counts(
	map_data: Variant,
	config: Variant,
	region_plan: Variant
) -> void:
	var section_names: Array[String] = [
		"minerals",
		"pois",
		"room_contents",
		"traps",
		"monster_sites",
		"nests",
		"camps",
	]
	var counts_by_role: Dictionary = _generated_content_counts_by_role(map_data, region_plan)
	for role: String in MAP_TYPES.REGION_ROLE_ORDER:
		var region = region_plan.try_get_by_role(role)
		if region == null:
			continue
		var profile: Dictionary = config.try_get_region_content_profile(region.content_profile_id)
		var role_counts: Dictionary = counts_by_role.get(role, {}) as Dictionary
		for section_name: String in section_names:
			var actual_count: int = int(role_counts.get(section_name, 0))
			var minimum_count: int = _minimum_count(profile, section_name)
			var target_count: int = _target_count(profile, section_name)
			_expect(
				actual_count >= minimum_count and actual_count <= target_count,
				"%s %s 最终计数必须位于 minimum/target 范围：%d 不在 %d..%d"
				% [role, section_name, actual_count, minimum_count, target_count]
			)
			if target_count == 0:
				_expect(
					actual_count == 0,
					"%s %s target=0 时必须严格禁用" % [role, section_name]
				)

	var high_1_region = region_plan.try_get_by_role(MAP_TYPES.REGION_ROLE_HIGH_1)
	if high_1_region != null:
		var high_1_profile: Dictionary = config.try_get_region_content_profile(
			high_1_region.content_profile_id
		)
		var high_1_counts: Dictionary = counts_by_role.get(
			MAP_TYPES.REGION_ROLE_HIGH_1,
			{}
		) as Dictionary
		for section_name: String in section_names:
			var target_count: int = _target_count(high_1_profile, section_name)
			if target_count <= 0:
				continue
			_expect(
				int(high_1_counts.get(section_name, 0)) == target_count,
				"high_1 %s 在候选与预算充足时必须达到 target=%d"
				% [section_name, target_count]
			)

	var high_2_region = region_plan.try_get_by_role(MAP_TYPES.REGION_ROLE_HIGH_2)
	if high_2_region != null:
		var high_2_profile: Dictionary = config.try_get_region_content_profile(
			high_2_region.content_profile_id
		)
		var high_2_counts: Dictionary = counts_by_role.get(
			MAP_TYPES.REGION_ROLE_HIGH_2,
			{}
		) as Dictionary
		for section_name: String in ["minerals"]:
			var actual_count: int = int(high_2_counts.get(section_name, 0))
			var minimum_count: int = _minimum_count(high_2_profile, section_name)
			var target_count: int = _target_count(high_2_profile, section_name)
			_expect(
				actual_count >= minimum_count and actual_count < target_count,
				"high_2 %s 固定 seed 必须展示 minimum 到 target 之间的合法裁剪"
				% section_name
			)


func _generated_content_counts_by_role(map_data: Variant, region_plan: Variant) -> Dictionary:
	var counts_by_role: Dictionary = {}
	for role: String in MAP_TYPES.REGION_ROLE_ORDER:
		counts_by_role[role] = {
			"minerals": 0,
			"pois": 0,
			"room_contents": 0,
			"traps": 0,
			"monster_sites": 0,
			"nests": 0,
			"camps": 0,
		}
	for site: Dictionary in map_data.mineral_sites:
		_increment_content_count(counts_by_role, _site_region_role(site, region_plan), "minerals")
	for poi_instance: Dictionary in map_data.poi_instances:
		var role: String = _site_region_role(poi_instance, region_plan)
		if not bool(poi_instance.get("is_core", false)):
			_increment_content_count(counts_by_role, role, "pois")
		for _room_plan: Variant in poi_instance.get("room_content_plans", []) as Array:
			_increment_content_count(counts_by_role, role, "room_contents")
	for trap_site: Dictionary in map_data.trap_sites:
		_increment_content_count(counts_by_role, _site_region_role(trap_site, region_plan), "traps")
	for monster_site: Dictionary in map_data.monster_sites:
		var section_name: String = (
			"nests"
			if str(monster_site.get("site_kind", "")) == "nest"
			else "monster_sites"
		)
		_increment_content_count(
			counts_by_role,
			_site_region_role(monster_site, region_plan),
			section_name
		)
	for camp: Dictionary in map_data.camp_encounters:
		_increment_content_count(counts_by_role, _site_region_role(camp, region_plan), "camps")
	return counts_by_role


func _increment_content_count(counts_by_role: Dictionary, role: String, section_name: String) -> void:
	if not counts_by_role.has(role):
		_expect(false, "%s 产物无法由 RegionPlan 解析区域：%s" % [section_name, role])
		return
	var role_counts: Dictionary = counts_by_role.get(role, {}) as Dictionary
	role_counts[section_name] = int(role_counts.get(section_name, 0)) + 1


func _validate_room_content_materialization(
	map_data: Variant,
	config: Variant,
	region_plan: Variant
) -> void:
	var plans_by_id: Dictionary = {}
	var materialized_by_plan_id: Dictionary = {}
	for site: Dictionary in map_data.monster_sites:
		var source_plan_id: String = str(site.get("source_room_content_plan_id", ""))
		if source_plan_id.is_empty():
			continue
		var artifacts: Array = materialized_by_plan_id.get(source_plan_id, []) as Array
		artifacts.append({"artifact_kind": "monster_site", "artifact": site})
		materialized_by_plan_id[source_plan_id] = artifacts
	for camp: Dictionary in map_data.camp_encounters:
		var source_plan_id: String = str(camp.get("source_room_content_plan_id", ""))
		if source_plan_id.is_empty():
			continue
		var artifacts: Array = materialized_by_plan_id.get(source_plan_id, []) as Array
		artifacts.append({"artifact_kind": "camp", "artifact": camp})
		materialized_by_plan_id[source_plan_id] = artifacts
	for poi_instance: Dictionary in map_data.poi_instances:
		for plan_value: Variant in poi_instance.get("room_content_plans", []) as Array:
			if not (plan_value is Dictionary):
				_expect(false, "room_content_plans 只能包含对象")
				continue
			var room_plan: Dictionary = plan_value as Dictionary
			var plan_id: String = str(room_plan.get("plan_id", ""))
			var content_kind: String = str(room_plan.get("content_kind", ""))
			var template_id: String = str(room_plan.get("template_id", ""))
			_expect(not plan_id.is_empty(), "room content plan 必须具有稳定 plan_id")
			_expect(not plans_by_id.has(plan_id), "room content plan_id 不得重复：%s" % plan_id)
			_expect(not template_id.is_empty(), "room content plan 必须冻结具体 template_id：%s" % plan_id)
			if plan_id.is_empty() or plans_by_id.has(plan_id):
				continue
			plans_by_id[plan_id] = room_plan
			var region = region_plan.try_get_by_role(str(room_plan.get("region_role", "")))
			var profile: Dictionary = (
				config.try_get_region_content_profile(region.content_profile_id)
				if region != null
				else {}
			)
			var expected_room_cost: int = _entry_value_cost(
				profile,
				"room_contents",
				"content_kind",
				content_kind
			)
			_expect(
				int(room_plan.get("room_content_value_cost", 0)) == expected_room_cost,
				"room content plan 必须记录 canonical room entry cost：%s" % plan_id
			)
			var artifacts: Array = materialized_by_plan_id.get(plan_id, []) as Array
			_expect(artifacts.size() == 1, "每个 room content plan 必须恰好物化一次：%s" % plan_id)
			if artifacts.size() != 1:
				continue
			var materialized: Dictionary = artifacts[0] as Dictionary
			var artifact: Dictionary = materialized.get("artifact", {}) as Dictionary
			if content_kind in ["monster_pack", "nest"]:
				_expect(str(materialized.get("artifact_kind", "")) == "monster_site", "怪物 room plan 不得物化为其他产物：%s" % plan_id)
				_expect(str(artifact.get("template_id", "")) == template_id, "room content 怪物模板必须与计划一致：%s" % plan_id)
				_expect(str(artifact.get("site_source", "")) == "poi_room", "room content 怪物必须标记 poi_room 来源：%s" % plan_id)
				_expect(str(artifact.get("site_id", "")) == plan_id, "room content 怪物必须具有稳定 site_id：%s" % plan_id)
				_expect(str(room_plan.get("materialized_site_id", "")) == str(artifact.get("site_id", "")), "room content 怪物计划必须回写实际 site_id：%s" % plan_id)
				_expect(int(room_plan.get("reward_budget_cost", 0)) == expected_room_cost, "怪物 room plan 的总成本必须等于 room entry cost：%s" % plan_id)
			elif content_kind == "camp":
				var expected_camp_cost: int = _entry_value_cost(
					profile,
					"camps",
					"camp_id",
					template_id
				)
				_expect(str(materialized.get("artifact_kind", "")) == "camp", "营地 room plan 不得物化为其他产物：%s" % plan_id)
				_expect(str(artifact.get("camp_id", "")) == template_id, "room content 营地模板必须与计划一致：%s" % plan_id)
				_expect(int(room_plan.get("content_value_cost", 0)) == expected_camp_cost, "营地 room plan 必须记录 canonical camp entry cost：%s" % plan_id)
				_expect(int(room_plan.get("reward_budget_cost", 0)) == expected_room_cost + expected_camp_cost, "营地 room plan 必须同时消费 room 与 camp 成本：%s" % plan_id)
				_expect(int(artifact.get("reward_budget_cost", 0)) == expected_camp_cost, "已物化营地必须记录自身 camp entry cost：%s" % plan_id)
				_expect(
					str(artifact.get("encounter_id", "")) == str(room_plan.get("materialized_encounter_id", "")),
					"room content 营地计划必须回写实际 encounter id：%s" % plan_id
				)
			else:
				_expect(false, "room content plan kind 不受支持：%s" % content_kind)
	_expect(not plans_by_id.is_empty(), "古代旧矿必须生成可验证的 room content plan")
	for source_plan_id_value: Variant in materialized_by_plan_id.keys():
		var source_plan_id: String = str(source_plan_id_value)
		_expect(plans_by_id.has(source_plan_id), "产物不得引用不存在的 room content plan：%s" % source_plan_id)
	for camp: Dictionary in map_data.camp_encounters:
		if not str(camp.get("source_room_content_plan_id", "")).is_empty():
			continue
		var region = region_plan.try_get_by_role(str(camp.get("region_role", "")))
		var profile: Dictionary = (
			config.try_get_region_content_profile(region.content_profile_id)
			if region != null
			else {}
		)
		_expect(
			int(camp.get("reward_budget_cost", 0))
			== _entry_value_cost(profile, "camps", "camp_id", str(camp.get("camp_id", ""))),
			"独立营地必须记录 canonical camp entry cost：%s" % str(camp.get("encounter_id", ""))
		)


func _entry_value_cost(
	profile: Dictionary,
	section_name: String,
	id_field: String,
	id_value: String
) -> int:
	var section: Dictionary = profile.get(section_name, {}) as Dictionary
	for entry_value: Variant in section.get("entries", []) as Array:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value as Dictionary
		if str(entry.get(id_field, "")) == id_value:
			return int(entry.get("value_cost", 0))
	return 0


func _validate_mineral_site_materialization(map_data: Variant) -> void:
	for site: Dictionary in map_data.mineral_sites:
		var cluster_type_id: String = str(site.get("cluster_type_id", ""))
		var cells: Array = site.get("cells", []) as Array
		_expect(not cells.is_empty(), "矿簇站点必须包含最终格子：%s" % str(site.get("site_id", "")))
		for cell_value: Variant in cells:
			var cell_coord: Vector2i = _cell_from_variant(cell_value)
			var cell = map_data.get_cell(cell_coord.x, cell_coord.y)
			_expect(cell != null and cell.cell_type == MAP_TYPES.CellType.WALL, "矿簇站点格必须仍是墙体：%s" % _cell_key(cell_coord))
			if cell == null:
				continue
			if cluster_type_id == "rare_mineral":
				_expect(
					cell.special_block_type == MAP_TYPES.SpecialBlockType.RARE_MINERAL,
					"稀有矿簇不得被后续陷阱覆盖：%s" % _cell_key(cell_coord)
				)
			else:
				_expect(
					cell.has_mineral
					and cell.special_block_type == MAP_TYPES.SpecialBlockType.NONE,
					"普通矿簇不得被后续陷阱覆盖：%s" % _cell_key(cell_coord)
				)


func _reward_spent_by_role(map_data: Variant) -> Dictionary:
	var spent_by_role: Dictionary = {}
	for poi_instance: Dictionary in map_data.poi_instances:
		var role: String = str(poi_instance.get("region_role", ""))
		for plan_value: Variant in poi_instance.get("room_content_plans", []) as Array:
			if plan_value is Dictionary:
				spent_by_role[role] = int(spent_by_role.get(role, 0)) + int(
					(plan_value as Dictionary).get("reward_budget_cost", 0)
				)
	for camp: Dictionary in map_data.camp_encounters:
		if not str(camp.get("source_room_content_plan_id", "")).is_empty():
			continue
		var role: String = str(camp.get("region_role", ""))
		spent_by_role[role] = int(spent_by_role.get(role, 0)) + int(
			camp.get("reward_budget_cost", 0)
		)
	return spent_by_role


func _validate_role_budgets(
	config: Variant,
	plan: Variant,
	spent_by_role: Dictionary,
	budget_name: String
) -> void:
	for role: String in MAP_TYPES.REGION_ROLE_ORDER:
		var region = plan.try_get_by_role(role)
		if region == null:
			continue
		var profile: Dictionary = config.try_get_region_content_profile(region.content_profile_id)
		var budget: int = int(profile.get(budget_name, 0))
		var spent: int = int(spent_by_role.get(role, 0))
		_expect(
			spent <= budget,
			"%s 的 %s 消费不得超过预算：%d > %d" % [role, budget_name, spent, budget]
		)


func _validate_poi_wall_integrity(map_data: Variant, config: Variant, plan: Variant) -> void:
	var protected_wall_count: int = 0
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell = map_data.get_cell(x, y)
			if cell == null or cell.cell_type != MAP_TYPES.CellType.WALL or not cell.is_poi_protected:
				continue
			protected_wall_count += 1
			_expect(
				cell.special_block_type == MAP_TYPES.SpecialBlockType.POI_WALL,
				"矿物重置后受保护 POI 墙必须保留 POI_WALL：%d,%d" % [x, y]
			)
			var region = plan.try_get_at(Vector2i(x, y))
			if region == null:
				continue
			var profile: Dictionary = config.try_get_region_content_profile(region.content_profile_id)
			var durability: Dictionary = profile.get("wall_durability", {}) as Dictionary
			_expect(
				cell.durability_override_max_hit_points == int(durability.get("poi_max_hit_points", 0)),
				"POI 墙必须使用所属区域 profile 的耐久：%d,%d" % [x, y]
			)
	_expect(protected_wall_count > 0, "古代旧矿必须保留可验证的受保护 POI 墙")


func _test_value_budget_enforcement(generator: Variant, map_data: Variant, config: Variant) -> void:
	var poi_wall_probe = map_data.deep_clone()
	var probe_cell = null
	for y: int in range(poi_wall_probe.height):
		for x: int in range(poi_wall_probe.width):
			var cell = poi_wall_probe.get_cell(x, y)
			if (
				cell != null
				and cell.cell_type == MAP_TYPES.CellType.WALL
				and cell.special_block_type == MAP_TYPES.SpecialBlockType.POI_WALL
			):
				probe_cell = cell
				break
		if probe_cell != null:
			break
	_expect(probe_cell != null, "矿物重置保护测试必须找到 POI_WALL")
	if probe_cell != null:
		probe_cell.has_mineral = true
		generator.call("_clear_four_region_mineral_cells", poi_wall_probe)
		_expect(not probe_cell.has_mineral, "四区域矿物重置必须清除旧矿物标记")
		_expect(
			probe_cell.special_block_type == MAP_TYPES.SpecialBlockType.POI_WALL,
			"四区域矿物重置不得擦除 POI_WALL"
		)
		_expect(probe_cell.is_poi_protected, "四区域矿物重置不得擦除 POI 保护标记")

	var clipped_mineral_config = config.deep_clone()
	var clipped_mineral_profile: Dictionary = _find_profile(
		clipped_mineral_config.region_generation.get("content_profiles", []),
		"ancient_old_mine_high_1_content"
	)
	clipped_mineral_profile["mineral_value_budget"] = 12
	for entry_value: Variant in (
		clipped_mineral_profile.get("minerals", {}) as Dictionary
	).get("entries", []) as Array:
		if entry_value is Dictionary:
			(entry_value as Dictionary)["value_cost"] = 2
	var clipped_mineral_map = map_data.deep_clone()
	var clipped_mineral_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	clipped_mineral_rng.seed = 424242
	var clipped_mineral_resolver = REGION_CONTENT_RESOLVER.new(
		clipped_mineral_config,
		clipped_mineral_map.region_plan
	)
	var clipped_mineral_issues: Variant = generator.call(
		"_generate_four_region_minerals",
		clipped_mineral_map,
		clipped_mineral_config,
		clipped_mineral_resolver,
		clipped_mineral_rng
	)
	_expect(
		clipped_mineral_issues is Array and (clipped_mineral_issues as Array).is_empty(),
		"预算足够 minimum 时矿物生成必须稳定裁剪而非失败：%s" % str(clipped_mineral_issues)
	)
	var clipped_high_1_count: int = 0
	for site: Dictionary in clipped_mineral_map.mineral_sites:
		if _site_region_role(site, clipped_mineral_map.region_plan) == MAP_TYPES.REGION_ROLE_HIGH_1:
			clipped_high_1_count += 1
	_expect(clipped_high_1_count == 6, "矿物 value budget 必须把 high_1 从 target=10 稳定裁剪为 6")

	var failed_mineral_config = clipped_mineral_config.deep_clone()
	var failed_mineral_profile: Dictionary = _find_profile(
		failed_mineral_config.region_generation.get("content_profiles", []),
		"ancient_old_mine_high_1_content"
	)
	failed_mineral_profile["mineral_value_budget"] = 10
	var failed_mineral_map = map_data.deep_clone()
	var failed_mineral_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	failed_mineral_rng.seed = 424242
	var failed_mineral_resolver = REGION_CONTENT_RESOLVER.new(
		failed_mineral_config,
		failed_mineral_map.region_plan
	)
	var failed_mineral_issues: Variant = generator.call(
		"_generate_four_region_minerals",
		failed_mineral_map,
		failed_mineral_config,
		failed_mineral_resolver,
		failed_mineral_rng
	)
	_expect(
		_has_issue(
			failed_mineral_issues,
			"content_minimum_not_met",
			"region_generation.content_profiles.minerals"
		),
		"矿物预算低于 minimum 所需成本时必须失败"
	)

	var clipped_reward_config = config.deep_clone()
	var clipped_reward_profile: Dictionary = _find_profile(
		clipped_reward_config.region_generation.get("content_profiles", []),
		"ancient_old_mine_high_1_content"
	)
	clipped_reward_profile["reward_value_budget"] = 6
	(clipped_reward_profile.get("room_contents", {}) as Dictionary)["entries"] = [
		{"content_kind": "camp", "weight": 1.0, "value_cost": 2},
	]
	(clipped_reward_profile.get("camps", {}) as Dictionary)["entries"] = [
		{"camp_id": "miner_settlement_supply_camp", "weight": 1.0, "value_cost": 4},
	]
	var clipped_reward_map = map_data.deep_clone()
	_clear_room_content_plans(clipped_reward_map)
	var clipped_reward_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	clipped_reward_rng.seed = 515151
	var clipped_reward_resolver = REGION_CONTENT_RESOLVER.new(
		clipped_reward_config,
		clipped_reward_map.region_plan
	)
	var clipped_reward_issues: Variant = generator.call(
		"_generate_four_region_room_contents",
		clipped_reward_map,
		clipped_reward_config,
		clipped_reward_resolver,
		clipped_reward_rng
	)
	_expect(
		clipped_reward_issues is Array and (clipped_reward_issues as Array).is_empty(),
		"reward budget 足够 camp room 双重 minimum 成本时必须稳定裁剪：%s" % str(clipped_reward_issues)
	)
	var clipped_high_1_plans: int = 0
	for poi_instance: Dictionary in clipped_reward_map.poi_instances:
		if str(poi_instance.get("region_role", "")) != MAP_TYPES.REGION_ROLE_HIGH_1:
			continue
		clipped_high_1_plans += (poi_instance.get("room_content_plans", []) as Array).size()
	_expect(clipped_high_1_plans == 1, "reward value budget 必须把 high_1 camp room target=2 稳定裁剪为 1")
	var shared_budget_issues: Variant = generator.call(
		"_generate_four_region_population_sites",
		clipped_reward_map,
		clipped_reward_config,
		clipped_reward_resolver,
		clipped_reward_rng
	)
	_expect(
		shared_budget_issues is Array and (shared_budget_issues as Array).is_empty(),
		"总预算 6 必须稳定裁剪为一个总成本 6 的 camp room plan：%s" % str(shared_budget_issues)
	)
	var clipped_reward_spent: Dictionary = _reward_spent_by_role(clipped_reward_map)
	_expect(
		int(clipped_reward_spent.get(MAP_TYPES.REGION_ROLE_HIGH_1, 0)) == 6,
		"camp room plan 必须同时消费 room_contents 与 camps 成本，且总消费恰为 6"
	)
	var clipped_direct_camps: int = 0
	var clipped_camp_plan_id: String = ""
	for poi_instance: Dictionary in clipped_reward_map.poi_instances:
		if str(poi_instance.get("region_role", "")) != MAP_TYPES.REGION_ROLE_HIGH_1:
			continue
		for plan_value: Variant in poi_instance.get("room_content_plans", []) as Array:
			if not (plan_value is Dictionary):
				continue
			var plan: Dictionary = plan_value as Dictionary
			if str(plan.get("content_kind", "")) != "camp":
				continue
			clipped_camp_plan_id = str(plan.get("plan_id", ""))
			_expect(int(plan.get("room_content_value_cost", 0)) == 2, "camp room entry 成本必须保真")
			_expect(int(plan.get("content_value_cost", 0)) == 4, "camp entry 成本必须保真")
			_expect(int(plan.get("reward_budget_cost", 0)) == 6, "camp room plan 必须记录双重总成本")
	var clipped_materialized_camps: int = 0
	for camp: Dictionary in clipped_reward_map.camp_encounters:
		if (
			str(camp.get("region_role", "")) == MAP_TYPES.REGION_ROLE_HIGH_1
			and str(camp.get("source_room_content_plan_id", "")).is_empty()
		):
			clipped_direct_camps += 1
		if str(camp.get("source_room_content_plan_id", "")) == clipped_camp_plan_id:
			clipped_materialized_camps += 1
	_expect(clipped_direct_camps == 0, "camp minimum 已由冻结 plan 满足时不得额外生成独立 camp")
	_expect(
		not clipped_camp_plan_id.is_empty() and clipped_materialized_camps == 1,
		"双重成本 camp room plan 必须恰好物化一次"
	)

	var camp_budget_config = config.deep_clone()
	var camp_budget_profile: Dictionary = _find_profile(
		camp_budget_config.region_generation.get("content_profiles", []),
		"ancient_old_mine_high_1_content"
	)
	camp_budget_profile["reward_value_budget"] = 4
	(camp_budget_profile.get("room_contents", {}) as Dictionary)["entries"] = [
		{"content_kind": "camp", "weight": 1.0, "value_cost": 2},
	]
	(camp_budget_profile.get("camps", {}) as Dictionary)["entries"] = [
		{"camp_id": "miner_settlement_side_supply", "weight": 1.0, "value_cost": 2},
	]
	var insufficient_camp_budget_config = camp_budget_config.deep_clone()
	var insufficient_camp_profile: Dictionary = _find_profile(
		insufficient_camp_budget_config.region_generation.get("content_profiles", []),
		"ancient_old_mine_high_1_content"
	)
	insufficient_camp_profile["reward_value_budget"] = 3
	var insufficient_camp_map = map_data.deep_clone()
	_clear_room_content_plans(insufficient_camp_map)
	var insufficient_camp_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	insufficient_camp_rng.seed = 616161
	var insufficient_camp_resolver = REGION_CONTENT_RESOLVER.new(
		insufficient_camp_budget_config,
		insufficient_camp_map.region_plan
	)
	var insufficient_camp_issues: Variant = generator.call(
		"_generate_four_region_room_contents",
		insufficient_camp_map,
		insufficient_camp_budget_config,
		insufficient_camp_resolver,
		insufficient_camp_rng
	)
	_expect(
		_has_issue(
			insufficient_camp_issues,
			"content_minimum_not_met",
			"region_generation.content_profiles.room_contents"
		),
		"camp room plan 必须同时支付 room cost 与 camp cost，预算 3 不得支付总成本 4"
	)

	var camp_budget_map = map_data.deep_clone()
	_clear_room_content_plans(camp_budget_map)
	var camp_budget_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	camp_budget_rng.seed = 616161
	var camp_budget_resolver = REGION_CONTENT_RESOLVER.new(
		camp_budget_config,
		camp_budget_map.region_plan
	)
	var camp_plan_issues: Variant = generator.call(
		"_generate_four_region_room_contents",
		camp_budget_map,
		camp_budget_config,
		camp_budget_resolver,
		camp_budget_rng
	)
	_expect(
		camp_plan_issues is Array and (camp_plan_issues as Array).is_empty(),
		"预算 4 必须允许生成一个总成本 4 的 camp room plan：%s" % str(camp_plan_issues)
	)
	var camp_population_issues: Variant = generator.call(
		"_generate_four_region_population_sites",
		camp_budget_map,
		camp_budget_config,
		camp_budget_resolver,
		camp_budget_rng
	)
	_expect(
		camp_population_issues is Array and (camp_population_issues as Array).is_empty(),
		"冻结的 camp room plan 必须可成功物化：%s" % str(camp_population_issues)
	)
	var high_1_camp_plans: Array[Dictionary] = []
	for poi_instance: Dictionary in camp_budget_map.poi_instances:
		if str(poi_instance.get("region_role", "")) != MAP_TYPES.REGION_ROLE_HIGH_1:
			continue
		for plan_value: Variant in poi_instance.get("room_content_plans", []) as Array:
			if plan_value is Dictionary:
				high_1_camp_plans.append(plan_value as Dictionary)
	_expect(high_1_camp_plans.size() == 1, "预算 4 必须只生成一个 high_1 camp room plan")
	if high_1_camp_plans.size() == 1:
		var camp_room_plan: Dictionary = high_1_camp_plans[0]
		_expect(str(camp_room_plan.get("content_kind", "")) == "camp", "强制 camp 测试必须命中 camp 分支")
		_expect(int(camp_room_plan.get("room_content_value_cost", 0)) == 2, "camp room entry cost 必须保真")
		_expect(int(camp_room_plan.get("content_value_cost", 0)) == 2, "camp content entry cost 必须保真")
		_expect(int(camp_room_plan.get("reward_budget_cost", 0)) == 4, "camp room plan 总成本必须为两类 entry 成本之和")
		var source_plan_id: String = str(camp_room_plan.get("plan_id", ""))
		var materialized_count: int = 0
		for camp: Dictionary in camp_budget_map.camp_encounters:
			if str(camp.get("source_room_content_plan_id", "")) == source_plan_id:
				materialized_count += 1
		_expect(materialized_count == 1, "强制 camp room plan 必须恰好物化一次")

	var nest_config = config.deep_clone()
	nest_config.set_meta("nest_templates", [{
		"id": "smoke_ghoul_nest",
		"monster_id": "ghoul",
		"nest_unit_id": "smoke_ghoul_nest_unit",
		"loot_table_id": "",
		"activation_radius_m": 12.0,
		"spawn_interval_sec": 5.0,
		"max_alive_children": 2,
		"max_hit_points": 10,
	}])
	var nest_profile: Dictionary = _find_profile(
		nest_config.region_generation.get("content_profiles", []),
		"ancient_old_mine_high_1_content"
	)
	nest_profile["reward_value_budget"] = 1
	(nest_profile.get("room_contents", {}) as Dictionary)["target_count"] = 1
	(nest_profile.get("room_contents", {}) as Dictionary)["minimum_count"] = 1
	(nest_profile.get("room_contents", {}) as Dictionary)["entries"] = [
		{"content_kind": "nest", "weight": 1.0, "value_cost": 1},
	]
	(nest_profile.get("nests", {}) as Dictionary)["target_count"] = 1
	(nest_profile.get("nests", {}) as Dictionary)["minimum_count"] = 1
	(nest_profile.get("nests", {}) as Dictionary)["entries"] = [
		{"nest_template_id": "smoke_ghoul_nest", "weight": 1.0},
	]
	(nest_profile.get("camps", {}) as Dictionary)["target_count"] = 0
	(nest_profile.get("camps", {}) as Dictionary)["minimum_count"] = 0
	(nest_profile.get("camps", {}) as Dictionary)["entries"] = []
	var nest_map = map_data.deep_clone()
	_clear_room_content_plans(nest_map)
	var nest_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	nest_rng.seed = 717171
	var nest_resolver = REGION_CONTENT_RESOLVER.new(nest_config, nest_map.region_plan)
	var nest_plan_issues: Variant = generator.call(
		"_generate_four_region_room_contents",
		nest_map,
		nest_config,
		nest_resolver,
		nest_rng
	)
	_expect(
		nest_plan_issues is Array and (nest_plan_issues as Array).is_empty(),
		"强制 nest room plan 必须生成成功：%s" % str(nest_plan_issues)
	)
	var nest_population_issues: Variant = generator.call(
		"_generate_four_region_population_sites",
		nest_map,
		nest_config,
		nest_resolver,
		nest_rng
	)
	_expect(
		nest_population_issues is Array and (nest_population_issues as Array).is_empty(),
		"冻结的 nest room plan 必须可成功物化：%s" % str(nest_population_issues)
	)
	var nest_plan_id: String = ""
	for poi_instance: Dictionary in nest_map.poi_instances:
		if str(poi_instance.get("region_role", "")) != MAP_TYPES.REGION_ROLE_HIGH_1:
			continue
		for plan_value: Variant in poi_instance.get("room_content_plans", []) as Array:
			if plan_value is Dictionary and str((plan_value as Dictionary).get("content_kind", "")) == "nest":
				nest_plan_id = str((plan_value as Dictionary).get("plan_id", ""))
	_expect(not nest_plan_id.is_empty(), "强制 nest 测试必须命中 nest 分支")
	var materialized_nest_count: int = 0
	for site: Dictionary in nest_map.monster_sites:
		if str(site.get("source_room_content_plan_id", "")) != nest_plan_id:
			continue
		materialized_nest_count += 1
		_expect(str(site.get("site_kind", "")) == "nest", "nest room plan 必须物化为 nest site")
		_expect(str(site.get("site_id", "")) == nest_plan_id, "nest site 必须回写稳定 site_id")
	_expect(materialized_nest_count == 1, "强制 nest room plan 必须恰好物化一次")


func _clear_room_content_plans(map_data: Variant) -> void:
	for poi_index: int in range(map_data.poi_instances.size()):
		var poi_instance: Dictionary = map_data.poi_instances[poi_index]
		poi_instance["room_content_plans"] = []
		map_data.poi_instances[poi_index] = poi_instance


func _validate_reward_geometry(map_data: Variant, boss_core: Dictionary, metadata: Dictionary) -> void:
	var main_room: Rect2i = _rect_from_variant(boss_core.get("main_room", {}))
	var footprint: Dictionary = _cell_set(boss_core.get("footprint_cells", []))
	for gate_value: Variant in metadata.get("reward_gate_cells", []) as Array:
		var gate_cell: Vector2i = _cell_from_variant(gate_value)
		var gate_data = map_data.get_cell(gate_cell.x, gate_cell.y)
		_expect(footprint.has(_cell_key(gate_cell)), "奖励门必须属于 BOSS 核心 POI footprint")
		_expect(
			gate_data != null
			and gate_data.cell_type == MAP_TYPES.CellType.WALL
			and gate_data.special_block_type == MAP_TYPES.SpecialBlockType.POI_WALL
			and gate_data.is_poi_protected,
			"奖励门必须实化为受保护 POI 结构墙"
		)
		var outward_direction: Vector2i = _main_room_gate_outward_direction(gate_cell, main_room)
		var outside_cell: Vector2i = gate_cell + outward_direction
		var outside_data = (
			map_data.get_cell(outside_cell.x, outside_cell.y)
			if outward_direction != Vector2i.ZERO
			else null
		)
		_expect(
			outside_data != null
			and outside_data.cell_type == MAP_TYPES.CellType.FLOOR
			and outside_data.special_block_type == MAP_TYPES.SpecialBlockType.NONE
			and not outside_data.is_poi_protected,
			"奖励门外侧必须是可通行地板，避免解锁后仍有双层墙"
		)
	for object_value: Variant in metadata.get("reward_object_cells", []) as Array:
		var object_cell: Vector2i = _cell_from_variant(object_value)
		var object_data = map_data.get_cell(object_cell.x, object_cell.y)
		_expect(main_room.has_point(object_cell), "奖励物件必须位于 BOSS 核心 POI 主房")
		_expect(footprint.has(_cell_key(object_cell)), "奖励物件必须属于 BOSS 核心 POI footprint")
		_expect(
			object_data != null
			and object_data.cell_type == MAP_TYPES.CellType.FLOOR
			and object_data.special_block_type == MAP_TYPES.SpecialBlockType.NONE
			and not object_data.has_mineral,
			"奖励物件必须位于可放置物件的主房地板"
		)


func _test_final_artifact_rejections(generator: Variant, map_data: Variant) -> void:
	var special_extraction = map_data.deep_clone()
	(special_extraction.extraction_sites[0] as Dictionary)["site_kind"] = "stone_golem_vault"
	(special_extraction.extraction_sites[0] as Dictionary)["guaranteed"] = true
	_expect(
		_has_issue(
			generator.call("_validate_four_region_artifact", special_extraction),
			"special_extraction_not_allowed",
			"extraction_sites"
		),
		"final validator 必须拒绝 site_kind/guaranteed 特殊撤离"
	)

	var invalid_gate = map_data.deep_clone()
	var invalid_gate_core: Dictionary = _find_boss_core_instance(invalid_gate)
	var invalid_gate_metadata: Dictionary = invalid_gate_core.get("core_metadata", {}) as Dictionary
	var gate_cell: Vector2i = _cell_from_variant(
		(invalid_gate_metadata.get("reward_gate_cells", []) as Array)[0]
	)
	var gate_data = invalid_gate.get_cell(gate_cell.x, gate_cell.y)
	gate_data.cell_type = MAP_TYPES.CellType.FLOOR
	gate_data.special_block_type = MAP_TYPES.SpecialBlockType.NONE
	gate_data.is_poi_protected = false
	_expect(
		_has_issue(
			generator.call("_validate_four_region_artifact", invalid_gate),
			"invalid_core_poi_metadata",
			"poi_instances.core_metadata.reward_gate_cells"
		),
		"final validator 必须拒绝非受保护 POI 结构墙的奖励门"
	)
	var invalid_gate_footprint = map_data.deep_clone()
	var invalid_gate_footprint_core: Dictionary = _find_boss_core_instance(invalid_gate_footprint)
	var invalid_gate_footprint_metadata: Dictionary = (
		invalid_gate_footprint_core.get("core_metadata", {}) as Dictionary
	)
	var boss_region = invalid_gate_footprint.region_plan.try_get_by_role(
		MAP_TYPES.REGION_ROLE_BOSS
	)
	var outside_footprint_cell: Vector2i = _find_region_cell_outside_set(
		invalid_gate_footprint.region_plan,
		boss_region.index,
		_cell_set(invalid_gate_footprint_core.get("footprint_cells", []))
	)
	(invalid_gate_footprint_metadata.get("reward_gate_cells", []) as Array)[0] = {
		"x": outside_footprint_cell.x,
		"y": outside_footprint_cell.y,
	}
	_expect(
		_has_issue(
			generator.call("_validate_four_region_artifact", invalid_gate_footprint),
			"invalid_core_poi_metadata",
			"poi_instances.core_metadata.reward_gate_cells"
		),
		"final validator 必须拒绝不属于 BOSS 核心 POI footprint 的奖励门"
	)

	var invalid_reward_object = map_data.deep_clone()
	var invalid_object_core: Dictionary = _find_boss_core_instance(invalid_reward_object)
	var invalid_object_metadata: Dictionary = invalid_object_core.get("core_metadata", {}) as Dictionary
	var object_cell: Vector2i = _cell_from_variant(
		(invalid_object_metadata.get("reward_object_cells", []) as Array)[0]
	)
	var object_data = invalid_reward_object.get_cell(object_cell.x, object_cell.y)
	object_data.cell_type = MAP_TYPES.CellType.WALL
	object_data.special_block_type = MAP_TYPES.SpecialBlockType.POI_WALL
	_expect(
		_has_issue(
			generator.call("_validate_four_region_artifact", invalid_reward_object),
			"invalid_core_poi_metadata",
			"poi_instances.core_metadata.reward_object_cells"
		),
		"final validator 必须拒绝非主房可放置地板的奖励物件坐标"
	)
	var invalid_object_footprint = map_data.deep_clone()
	var invalid_object_footprint_core: Dictionary = _find_boss_core_instance(
		invalid_object_footprint
	)
	var invalid_object_footprint_metadata: Dictionary = (
		invalid_object_footprint_core.get("core_metadata", {}) as Dictionary
	)
	var outside_object_cell: Vector2i = _find_region_cell_outside_set(
		invalid_object_footprint.region_plan,
		boss_region.index,
		_cell_set(invalid_object_footprint_core.get("footprint_cells", []))
	)
	var outside_object_data = invalid_object_footprint.get_cell(
		outside_object_cell.x,
		outside_object_cell.y
	)
	outside_object_data.cell_type = MAP_TYPES.CellType.FLOOR
	outside_object_data.special_block_type = MAP_TYPES.SpecialBlockType.NONE
	outside_object_data.has_mineral = false
	(invalid_object_footprint_metadata.get("reward_object_cells", []) as Array)[0] = {
		"x": outside_object_cell.x,
		"y": outside_object_cell.y,
	}
	_expect(
		_has_issue(
			generator.call("_validate_four_region_artifact", invalid_object_footprint),
			"invalid_core_poi_metadata",
			"poi_instances.core_metadata.reward_object_cells"
		),
		"final validator 必须拒绝不属于 BOSS 核心 POI footprint/主房的奖励物件"
	)

	var invalid_template = map_data.deep_clone()
	var invalid_template_core: Dictionary = _find_boss_core_instance(invalid_template)
	invalid_template_core["template_id"] = "tampered_core_template"
	_expect(
		_has_issue(
			generator.call("_validate_four_region_artifact", invalid_template),
			"core_poi_identity_mismatch",
			"poi_instances"
		),
		"final validator 必须拒绝 RegionPlan 与实际核心 POI template 不一致"
	)

	var invalid_anchor = map_data.deep_clone()
	var invalid_anchor_core: Dictionary = _find_boss_core_instance(invalid_anchor)
	invalid_anchor_core["center_cell"] = (
		invalid_anchor_core.get("center_cell", Vector2i.ZERO) as Vector2i
	) + Vector2i.RIGHT
	_expect(
		_has_issue(
			generator.call("_validate_four_region_artifact", invalid_anchor),
			"core_poi_identity_mismatch",
			"poi_instances.center_cell"
		),
		"final validator 必须拒绝 RegionPlan core anchor 与实际核心 POI 不一致"
	)

	var invalid_primary = map_data.deep_clone()
	boss_region = invalid_primary.region_plan.try_get_by_role(MAP_TYPES.REGION_ROLE_BOSS)
	var alternate_boss_cell: Vector2i = _find_alternate_region_cell(
		invalid_primary.region_plan,
		boss_region.index,
		boss_region.core_anchor_cell
	)
	var descriptor_result = MAP_TYPES.BossEncounterDescriptor.create_structurally_validated(
		invalid_primary.region_plan,
		{
			"encounter_id": invalid_primary.region_boss_encounter.get_encounter_id(),
			"region_id": boss_region.id,
			"core_poi_instance_id": boss_region.core_poi_instance_id,
			"encounter_profile_id": invalid_primary.region_boss_encounter.get_encounter_profile_id(),
			"anchors": [{"id": "primary", "cell": alternate_boss_cell}],
		}
	)
	_expect(descriptor_result.is_success(), "篡改 primary 的结构 descriptor 应可用于 final validator 负向测试")
	if descriptor_result.is_success():
		invalid_primary.region_boss_encounter = descriptor_result.descriptor
		_expect(
			_has_issue(
				generator.call("_validate_four_region_artifact", invalid_primary),
				"boss_encounter_mismatch",
				"region_boss_encounter.anchors"
			),
			"final validator 必须拒绝不等于核心 POI 主房中心的 primary"
		)


func _test_extraction_distance_fallback(generator: Variant, map_data: Variant, config: Variant) -> void:
	var plan = map_data.region_plan as MAP_TYPES.RegionPlan
	var spawn_cell: Vector2i = _cell_from_variant(map_data.player_spawn_points[0])
	var avoid_cells: Array[Vector2i] = [spawn_cell]
	var impossible_distance: float = float(maxi(map_data.width, map_data.height) * 4)
	var resolver = REGION_CONTENT_RESOLVER.new(config, plan)
	var fallback_result: Dictionary = generator.call(
		"_select_four_region_site_cell",
		map_data.deep_clone(),
		resolver,
		config.extraction_site_edge_margin_cells,
		config.extraction_site_clearance_radius_cells,
		config.extraction_site_min_clearance_ratio,
		avoid_cells,
		impossible_distance,
		"extraction",
		generator.last_resolved_seed,
		0
	)
	_expect(
		not bool(fallback_result.get("success", false))
		and fallback_result.get("cell", Vector2i.ZERO) == Vector2i(-1, -1),
		"四区域撤离 fallback 不得放宽与出生点的最小距离"
	)


func _find_boss_core_instance(map_data: Variant) -> Dictionary:
	var boss_region = map_data.region_plan.try_get_by_role(MAP_TYPES.REGION_ROLE_BOSS)
	for poi_instance: Dictionary in map_data.poi_instances:
		if str(poi_instance.get("instance_id", "")) == boss_region.core_poi_instance_id:
			return poi_instance
	return {}


func _find_alternate_region_cell(plan: Variant, region_index: int, excluded: Vector2i) -> Vector2i:
	var map_size: Vector2i = plan.get_map_size()
	var membership: PackedInt32Array = plan.get_region_index_by_cell_copy()
	for flat_index: int in range(membership.size()):
		if int(membership[flat_index]) != region_index:
			continue
		var cell: Vector2i = Vector2i(flat_index % map_size.x, flat_index / map_size.x)
		if cell != excluded:
			return cell
	return excluded


func _find_region_cell_outside_set(
	plan: Variant,
	region_index: int,
	excluded_cells: Dictionary
) -> Vector2i:
	var map_size: Vector2i = plan.get_map_size()
	var membership: PackedInt32Array = plan.get_region_index_by_cell_copy()
	for flat_index: int in range(membership.size()):
		if int(membership[flat_index]) != region_index:
			continue
		var cell: Vector2i = Vector2i(flat_index % map_size.x, flat_index / map_size.x)
		if not excluded_cells.has(_cell_key(cell)):
			return cell
	return Vector2i(-1, -1)


func _rect_from_variant(value: Variant) -> Rect2i:
	if value is Rect2i:
		return value as Rect2i
	if value is Dictionary:
		return Rect2i(
			int((value as Dictionary).get("x", 0)),
			int((value as Dictionary).get("y", 0)),
			int((value as Dictionary).get("width", 0)),
			int((value as Dictionary).get("height", 0))
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


func _cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


func _main_room_gate_outward_direction(gate_cell: Vector2i, main_room: Rect2i) -> Vector2i:
	if gate_cell.y == main_room.position.y - 1 and gate_cell.x >= main_room.position.x and gate_cell.x < main_room.end.x:
		return Vector2i.UP
	if gate_cell.y == main_room.end.y and gate_cell.x >= main_room.position.x and gate_cell.x < main_room.end.x:
		return Vector2i.DOWN
	if gate_cell.x == main_room.position.x - 1 and gate_cell.y >= main_room.position.y and gate_cell.y < main_room.end.y:
		return Vector2i.LEFT
	if gate_cell.x == main_room.end.x and gate_cell.y >= main_room.position.y and gate_cell.y < main_room.end.y:
		return Vector2i.RIGHT
	return Vector2i.ZERO


func _find_profile(value: Variant, profile_id: String) -> Dictionary:
	if not (value is Array):
		return {}
	for entry_value: Variant in value as Array:
		if entry_value is Dictionary and str((entry_value as Dictionary).get("id", "")) == profile_id:
			return entry_value as Dictionary
	return {}


func _find_template(values: Array, template_id: String) -> Dictionary:
	for value: Variant in values:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == template_id:
			return value as Dictionary
	return {}


func _target_count(profile: Dictionary, section_name: String) -> int:
	return int((profile.get(section_name, {}) as Dictionary).get("target_count", -1))


func _minimum_count(profile: Dictionary, section_name: String) -> int:
	return int((profile.get(section_name, {}) as Dictionary).get("minimum_count", -1))


func _entry_weight(
	profile: Dictionary,
	section_name: String,
	id_field: String,
	id_value: String
) -> float:
	var section: Dictionary = profile.get(section_name, {}) as Dictionary
	for entry_value: Variant in section.get("entries", []) as Array:
		if entry_value is Dictionary and str((entry_value as Dictionary).get(id_field, "")) == id_value:
			return float((entry_value as Dictionary).get("weight", 0.0))
	return 0.0


func _is_strict_entry_superset(
	superset_profile: Dictionary,
	subset_profile: Dictionary,
	section_name: String,
	id_field: String
) -> bool:
	var superset_ids: Dictionary = _entry_id_set(superset_profile, section_name, id_field)
	var subset_ids: Dictionary = _entry_id_set(subset_profile, section_name, id_field)
	if superset_ids.size() <= subset_ids.size():
		return false
	for id_value: Variant in subset_ids.keys():
		if not superset_ids.has(id_value):
			return false
	return true


func _entry_id_set(profile: Dictionary, section_name: String, id_field: String) -> Dictionary:
	var result: Dictionary = {}
	var section: Dictionary = profile.get(section_name, {}) as Dictionary
	for entry_value: Variant in section.get("entries", []) as Array:
		if entry_value is Dictionary:
			var id_value: String = str((entry_value as Dictionary).get(id_field, ""))
			if not id_value.is_empty():
				result[id_value] = true
	return result


func _site_region_role(site: Dictionary, plan: Variant) -> String:
	var cell_value: Variant = site.get("cell", site.get("position", null))
	if site.has("center_cell"):
		cell_value = site.get("center_cell")
	elif site.has("chest_cell"):
		cell_value = site.get("chest_cell")
	var cell: Vector2i = _cell_from_variant(cell_value)
	var snapshot = (plan as MAP_TYPES.RegionPlan).try_get_at(cell)
	return snapshot.role if snapshot != null else ""


func _has_issue(issues_value: Variant, code: String, path: String = "") -> bool:
	if not (issues_value is Array):
		return false
	for issue_value: Variant in issues_value as Array:
		if not (issue_value is Dictionary):
			continue
		var issue: Dictionary = issue_value as Dictionary
		if str(issue.get("code", "")) != code:
			continue
		if not path.is_empty() and str(issue.get("path", "")) != path:
			continue
		return true
	return false


func _cell_from_variant(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Dictionary:
		return Vector2i(int((value as Dictionary).get("x", 0)), int((value as Dictionary).get("y", 0)))
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i.ZERO


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("ancient_old_mine_smoke: %s" % failure)
		quit(1)
		return
	print("ancient_old_mine_smoke: PASS")
	quit(0)
