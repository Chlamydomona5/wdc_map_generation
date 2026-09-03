extends SceneTree

const CONFIG_CATALOG = preload("../../config/data_generated_map_config_catalog.gd")
const MAP_TYPES = preload("../../core/generated_map_types.gd")
const GENERATOR_SCRIPT = preload("../../core/generated_map_generator.gd")
const PREVIEW_SCRIPT = preload("../../preview/scripts/map_generation_preview.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_legacy_config_compatibility()
	_test_four_region_config_contract()
	_test_region_plan_contract()
	_test_boss_encounter_contract()
	_test_authority_and_payload_codecs()
	_test_generator_fail_closed()
	_test_preview_clear_contract()
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("four_region_contract_smoke: %s" % failure)
		quit(1)
		return
	print("four_region_contract_smoke: PASS")
	quit(0)


func _test_legacy_config_compatibility() -> void:
	var default_config = MAP_TYPES.MapConfig.new()
	_expect(
		default_config.layout_mode == MAP_TYPES.LAYOUT_MODE_LEGACY_RADIAL,
		"MapConfig.new() 必须默认使用 legacy_radial"
	)
	var result = CONFIG_CATALOG.parse_and_normalize_config({"map": {}})
	_expect(result.is_success(), "完全缺少 region_layout 的旧配置必须继续成功")
	if not result.is_success():
		return
	var config = result.config
	_expect(config.layout_mode == MAP_TYPES.LAYOUT_MODE_LEGACY_RADIAL, "旧配置 mode 错误")
	_expect(config.map_layers.size() == 3, "旧配置必须继续补齐三层 radial 默认值")
	_expect(config.player_spawn_layer_id == "outer", "旧配置必须继续补齐 outer 出生层")
	_expect(
		config.extraction_site_layer_distribution.size() > 0
		and str(config.extraction_site_layer_distribution[0].get("layer_id", "")) == "inner",
		"旧配置必须继续补齐 inner 撤离层"
	)
	var serialized: Dictionary = CONFIG_CATALOG.serialize_normalized_config(result)
	_expect(serialized.has("map_layers"), "legacy serialize 必须保留 radial map_layers")


func _test_four_region_config_contract() -> void:
	_expect_parse_issue({"region_layout": null}, "invalid_region_layout_declaration", "region_layout")
	_expect_parse_issue({"region_layout": {}}, "invalid_region_layout_declaration", "region_layout.mode")
	_expect_parse_issue(
		{"schema_version": 2, "region_layout": {"mode": 123}},
		"invalid_region_layout_declaration",
		"region_layout.mode"
	)
	_expect_parse_issue(
		{"schema_version": 2, "region_layout": {"mode": "future_mode"}},
		"unsupported_region_layout_mode",
		"region_layout.mode"
	)
	var wrong_version: Dictionary = _valid_four_region_config()
	wrong_version["schema_version"] = 1
	_expect_parse_issue(
		wrong_version,
		"unsupported_region_layout_schema_version",
		"schema_version"
	)

	var valid_result = CONFIG_CATALOG.parse_and_normalize_config(_valid_four_region_config())
	_expect(valid_result.is_success(), "最小合法四区域配置必须通过 canonical parser")
	if valid_result.is_success():
		var config = valid_result.config
		_expect(
			config.layout_mode == MAP_TYPES.LAYOUT_MODE_PVE_FOUR_REGION_V1,
			"四区域配置 mode 未保真"
		)
		_expect(config.map_layers.is_empty(), "四区域 normalize 不得补入 map_layers")
		_expect(config.player_spawn_layer_id.is_empty(), "四区域 normalize 不得补入出生 layer")
		_expect(
			config.extraction_site_layer_distribution.is_empty(),
			"四区域 normalize 不得补入撤离 layer_distribution"
		)
		for role_index: int in range(MAP_TYPES.REGION_ROLE_ORDER.size()):
			var role: String = MAP_TYPES.REGION_ROLE_ORDER[role_index]
			var slot: Dictionary = config.region_layout.get(role, {}) as Dictionary
			_expect(str(slot.get("role", "")) == role, "规范化角色缺失：%s" % role)
			_expect(
				int(slot.get("difficulty_rank", -1)) == role_index,
				"固定 difficulty rank 错误：%s" % role
			)
		var serialized: Dictionary = CONFIG_CATALOG.serialize_normalized_config(valid_result)
		_expect(not serialized.has("map_layers"), "四区域 serialize 不得写入 map_layers")
		_expect(not serialized.has("boss_generation"), "四区域 serialize 不得写入 boss_generation")
		var serialized_map: Dictionary = serialized.get("map", {}) as Dictionary
		var serialized_spawn: Dictionary = serialized_map.get("player_spawn", {}) as Dictionary
		var serialized_extraction: Dictionary = serialized_map.get("extraction_sites", {}) as Dictionary
		_expect(not serialized_spawn.has("layer_id"), "四区域 serialize 不得写入出生 layer_id")
		_expect(
			not serialized_extraction.has("layer_distribution"),
			"四区域 serialize 不得写入撤离 layer_distribution"
		)
		var second_result = CONFIG_CATALOG.parse_and_normalize_config(serialized)
		_expect(second_result.is_success(), "四区域 parse → serialize → parse 必须成功")
		if second_result.is_success():
			_expect(
				second_result.get_normalized_document() == serialized,
				"四区域 parse → serialize → parse 必须无损"
			)
	var unknown_map_config = MAP_TYPES.MapConfig.new()
	unknown_map_config.layout_mode = "future_mode"
	_expect(
		CONFIG_CATALOG.serialize_normalized_config(unknown_map_config).is_empty(),
		"serialize_normalized_config 不得将未知 MapConfig mode 静默写成 legacy"
	)

	var numeric_region_id: Dictionary = _valid_four_region_config()
	(numeric_region_id["region_layout"]["regular"] as Dictionary)["id"] = 123
	_expect_parse_issue(
		numeric_region_id,
		"invalid_region_layout_declaration",
		"region_layout.regular.id"
	)
	var numeric_content_profile: Dictionary = _valid_four_region_config()
	(numeric_content_profile["region_layout"]["regular"] as Dictionary)[
		"content_profile_id"
	] = 123
	_expect_parse_issue(
		numeric_content_profile,
		"invalid_region_layout_declaration",
		"region_layout.regular.content_profile_id"
	)
	var numeric_core_template: Dictionary = _valid_four_region_config()
	(numeric_core_template["region_layout"]["high_1"]["core_poi"] as Dictionary)[
		"template_id"
	] = 123
	_expect_parse_issue(
		numeric_core_template,
		"invalid_region_layout_declaration",
		"region_layout.high_1.core_poi.template_id"
	)
	var numeric_poi_template_id: Dictionary = _valid_four_region_config()
	(numeric_poi_template_id["region_layout"]["high_1"]["core_poi"] as Dictionary)[
		"template_id"
	] = "123"
	(numeric_poi_template_id["poi_generation"]["poi_types"][0] as Dictionary)["id"] = 123
	_expect_parse_issue(
		numeric_poi_template_id,
		"invalid_region_layout_declaration",
		"poi_generation.poi_types[0].id"
	)
	var numeric_encounter_profile: Dictionary = _valid_four_region_config()
	(numeric_encounter_profile["region_layout"]["boss"] as Dictionary)[
		"encounter_profile_id"
	] = 123
	_expect_parse_issue(
		numeric_encounter_profile,
		"invalid_region_layout_declaration",
		"region_layout.boss.encounter_profile_id"
	)

	var missing_role: Dictionary = _valid_four_region_config()
	(missing_role["region_layout"] as Dictionary).erase("high_2")
	_expect_parse_issue(missing_role, "missing_region_role", "region_layout.high_2")
	var duplicate_id: Dictionary = _valid_four_region_config()
	var duplicate_layout: Dictionary = duplicate_id["region_layout"] as Dictionary
	(duplicate_layout["high_2"] as Dictionary)["id"] = (
		(duplicate_layout["high_1"] as Dictionary)["id"]
	)
	_expect_parse_issue(duplicate_id, "duplicate_region_id", "region_layout.high_2.id")
	var missing_content: Dictionary = _valid_four_region_config()
	(missing_content["region_layout"]["regular"] as Dictionary).erase("content_profile_id")
	_expect_parse_issue(
		missing_content,
		"missing_content_profile_reference",
		"region_layout.regular.content_profile_id"
	)
	var missing_layout: Dictionary = _valid_four_region_config()
	(missing_layout["region_layout"]["high_1"] as Dictionary).erase("layout_profile_id")
	_expect_parse_issue(
		missing_layout,
		"missing_layout_profile_reference",
		"region_layout.high_1.layout_profile_id"
	)
	var missing_core: Dictionary = _valid_four_region_config()
	(missing_core["region_layout"]["high_1"] as Dictionary).erase("core_poi")
	_expect_parse_issue(missing_core, "missing_core_poi_reference", "region_layout.high_1.core_poi")
	var missing_encounter: Dictionary = _valid_four_region_config()
	(missing_encounter["region_layout"]["boss"] as Dictionary).erase("encounter_profile_id")
	_expect_parse_issue(
		missing_encounter,
		"missing_boss_encounter_reference",
		"region_layout.boss.encounter_profile_id"
	)
	var invalid_regular_fields: Dictionary = _valid_four_region_config()
	var regular_slot: Dictionary = invalid_regular_fields["region_layout"]["regular"] as Dictionary
	regular_slot["layout_profile_id"] = "forbidden"
	regular_slot["core_poi"] = {"template_id": "forbidden", "max_center_offset_cells": 0}
	regular_slot["encounter_profile_id"] = "forbidden"
	_expect_parse_issue(
		invalid_regular_fields,
		"invalid_region_layout_declaration",
		"region_layout.regular.layout_profile_id"
	)
	var invalid_high_field: Dictionary = _valid_four_region_config()
	(invalid_high_field["region_layout"]["high_1"] as Dictionary)["encounter_profile_id"] = "forbidden"
	_expect_parse_issue(
		invalid_high_field,
		"invalid_region_layout_declaration",
		"region_layout.high_1.encounter_profile_id"
	)

	for conflict_path: String in [
		"map_layers",
		"boss_generation",
		"map.player_spawn.layer_id",
		"map.extraction_sites.layer_distribution",
	]:
		var conflict: Dictionary = _valid_four_region_config()
		match conflict_path:
			"map_layers":
				conflict["map_layers"] = []
			"boss_generation":
				conflict["boss_generation"] = {}
			"map.player_spawn.layer_id":
				(conflict["map"]["player_spawn"] as Dictionary)["layer_id"] = "outer"
			"map.extraction_sites.layer_distribution":
				(conflict["map"]["extraction_sites"] as Dictionary)["layer_distribution"] = [
					{"layer_id": "inner", "ratio": 1.0}
				]
		_expect_parse_issue(conflict, "conflicting_legacy_region_field", conflict_path)

	var unknown_core: Dictionary = _valid_four_region_config()
	(unknown_core["region_layout"]["high_1"]["core_poi"] as Dictionary)["template_id"] = "missing"
	_expect_parse_issue(
		unknown_core,
		"unknown_core_poi_reference",
		"region_layout.high_1.core_poi.template_id"
	)
	var ambiguous_core: Dictionary = _valid_four_region_config()
	var poi_types: Array = ambiguous_core["poi_generation"]["poi_types"] as Array
	poi_types.append({"id": "high_1_core"})
	_expect_parse_issue(
		ambiguous_core,
		"ambiguous_core_poi_reference",
		"region_layout.high_1.core_poi.template_id"
	)


func _test_region_plan_contract() -> void:
	var raw_regions: Array = _valid_region_descriptors()
	var membership: PackedInt32Array = _valid_membership()
	var result = MAP_TYPES.RegionPlan.create_structurally_validated(
		MAP_TYPES.REGION_PLAN_SCHEMA_VERSION,
		Vector2i(4, 2),
		raw_regions,
		membership
	)
	_expect(result.is_success(), "合法 RegionPlan 必须构造成功")
	if not result.is_success():
		return
	var plan = result.plan
	var regular = plan.try_get_by_role(MAP_TYPES.REGION_ROLE_REGULAR)
	var boss = plan.try_get_at(Vector2i(3, 1))
	_expect(regular != null and regular.id == "regular_region", "按角色查询 RegionPlan 错误")
	_expect(boss != null and boss.role == MAP_TYPES.REGION_ROLE_BOSS, "按格查询 RegionPlan 错误")
	_expect(regular.cell_count == 2, "RegionPlan 必须从 membership 派生 cell_count")
	_expect(
		regular.bounds == Rect2i(Vector2i(0, 0), Vector2i(2, 1)),
		"RegionPlan 必须从 membership 派生 bounds"
	)
	_expect(plan.try_get_by_role("unknown") == null, "未知角色查询必须返回 null")
	_expect(plan.try_get_at(Vector2i(-1, 0)) == null, "越界格查询必须返回 null")
	raw_regions[0]["id"] = "mutated_input"
	membership[0] = 3
	regular.id = "mutated_snapshot"
	_expect(
		plan.try_get_by_role(MAP_TYPES.REGION_ROLE_REGULAR).id == "regular_region"
		and plan.try_get_at(Vector2i(0, 0)).role == MAP_TYPES.REGION_ROLE_REGULAR,
		"RegionPlan 必须深拷贝输入并返回隔离 snapshot"
	)
	var encoded_plan: Dictionary = MAP_TYPES.encode_region_plan_authority(plan)
	(encoded_plan["regions"][0] as Dictionary)["id"] = "mutated_codec"
	_expect(
		plan.try_get_by_role(MAP_TYPES.REGION_ROLE_REGULAR).id == "regular_region",
		"authority codec 输出不得暴露 plan 内部引用"
	)

	_expect_plan_issue(_valid_region_descriptors(), PackedInt32Array([0, 1, 2, 3]), "membership 长度错误必须失败")
	var out_of_range: PackedInt32Array = _valid_membership()
	out_of_range[0] = 4
	_expect_plan_issue(_valid_region_descriptors(), out_of_range, "membership 越界必须失败")
	var wrong_center: Array = _valid_region_descriptors()
	(wrong_center[0] as Dictionary)["center_cell"] = Vector2i(2, 1)
	_expect_plan_issue(wrong_center, _valid_membership(), "center 不属于本区必须失败")
	var wrong_anchor: Array = _valid_region_descriptors()
	(wrong_anchor[1] as Dictionary)["core_anchor_cell"] = Vector2i(0, 0)
	_expect_plan_issue(wrong_anchor, _valid_membership(), "核心 anchor 不属于本区必须失败")
	var duplicate_core: Array = _valid_region_descriptors()
	(duplicate_core[2] as Dictionary)["core_poi_instance_id"] = "high_1_instance"
	_expect_plan_issue(duplicate_core, _valid_membership(), "核心 POI instance 重复必须失败")
	var regular_with_core: Array = _valid_region_descriptors()
	(regular_with_core[0] as Dictionary)["core_poi_template_id"] = "forbidden"
	_expect_plan_issue(regular_with_core, _valid_membership(), "regular 携带 core 字段必须失败")
	var wrong_rank: Array = _valid_region_descriptors()
	(wrong_rank[3] as Dictionary)["difficulty_rank"] = 2
	_expect_plan_issue(wrong_rank, _valid_membership(), "固定 rank 不匹配必须失败")
	var string_index: Array = _valid_region_descriptors()
	(string_index[0] as Dictionary)["index"] = "0"
	_expect_plan_issue(string_index, _valid_membership(), "字符串 index 不得被强转为整数")
	var fractional_rank: Array = _valid_region_descriptors()
	(fractional_rank[3] as Dictionary)["difficulty_rank"] = 3.5
	_expect_plan_issue(fractional_rank, _valid_membership(), "小数 rank 不得被截断为整数")
	var numeric_id: Array = _valid_region_descriptors()
	(numeric_id[0] as Dictionary)["id"] = 123
	_expect_plan_issue(numeric_id, _valid_membership(), "数字区域 id 不得被强转为字符串")
	var string_coordinate: Array = _valid_region_descriptors()
	(string_coordinate[0] as Dictionary)["center_cell"] = {"x": "0", "y": 0}
	_expect_plan_issue(string_coordinate, _valid_membership(), "字符串坐标不得被强转为整数")
	var fractional_coordinate: Array = _valid_region_descriptors()
	(fractional_coordinate[0] as Dictionary)["center_cell"] = {"x": 0.5, "y": 0}
	_expect_plan_issue(fractional_coordinate, _valid_membership(), "小数坐标不得被截断为整数")
	var invalid_schema_plan: Dictionary = MAP_TYPES.encode_region_plan_authority(plan)
	invalid_schema_plan["schema_version"] = str(MAP_TYPES.REGION_PLAN_SCHEMA_VERSION)
	var invalid_schema_result = MAP_TYPES.decode_region_plan_authority(invalid_schema_plan)
	_expect(
		not invalid_schema_result.is_success()
		and _has_issue(invalid_schema_result.get_issues(), "invalid_region_layout_artifact"),
		"authority codec 不得强转字符串 schema version"
	)
	var invalid_map_size_plan: Dictionary = MAP_TYPES.encode_region_plan_authority(plan)
	(invalid_map_size_plan["map_size"] as Dictionary)["x"] = "4"
	_expect(
		not MAP_TYPES.decode_region_plan_authority(invalid_map_size_plan).is_success(),
		"authority codec 不得强转字符串 map_size"
	)


func _test_boss_encounter_contract() -> void:
	var plan = _create_valid_plan()
	if plan == null:
		return
	var raw_descriptor: Dictionary = _valid_boss_descriptor()
	var result = MAP_TYPES.BossEncounterDescriptor.create_structurally_validated(
		plan,
		raw_descriptor
	)
	_expect(result.is_success(), "合法 BOSS encounter descriptor 必须构造成功")
	if not result.is_success():
		return
	var descriptor = result.descriptor
	_expect(descriptor.get_anchor_snapshots().size() == 2, "BOSS descriptor 必须支持多个命名 anchor")
	raw_descriptor["encounter_id"] = "mutated"
	(raw_descriptor["anchors"][0] as Dictionary)["id"] = "mutated"
	_expect(
		descriptor.get_encounter_id() == "boss_encounter"
		and descriptor.get_anchor_snapshots()[0].id == "phase_start",
		"BOSS descriptor 必须深拷贝构造输入"
	)
	var encoded: Dictionary = MAP_TYPES.encode_boss_encounter_authority(descriptor)
	var decoded = MAP_TYPES.decode_boss_encounter_authority(plan, encoded)
	_expect(decoded.is_success(), "BOSS descriptor authority round-trip 必须成功")
	if decoded.is_success():
		_expect(
			decoded.descriptor.get_anchor_snapshots().size() == 2,
			"BOSS descriptor authority round-trip 丢失 anchor"
		)

	var missing_id: Dictionary = _valid_boss_descriptor()
	missing_id["encounter_id"] = ""
	_expect_boss_issue(plan, missing_id, "invalid_boss_encounter_descriptor", "空 encounter id 必须失败")
	var empty_anchors: Dictionary = _valid_boss_descriptor()
	empty_anchors["anchors"] = []
	_expect_boss_issue(plan, empty_anchors, "invalid_boss_encounter_descriptor", "空 anchors 必须失败")
	var duplicate_anchor: Dictionary = _valid_boss_descriptor()
	(duplicate_anchor["anchors"][1] as Dictionary)["id"] = "phase_start"
	_expect_boss_issue(plan, duplicate_anchor, "invalid_boss_encounter_descriptor", "重复 anchor id 必须失败")
	var outside_anchor: Dictionary = _valid_boss_descriptor()
	(outside_anchor["anchors"][0] as Dictionary)["cell"] = Vector2i(0, 0)
	_expect_boss_issue(plan, outside_anchor, "invalid_boss_encounter_descriptor", "区域外 anchor 必须失败")
	var wrong_region: Dictionary = _valid_boss_descriptor()
	wrong_region["region_id"] = "high_2_region"
	_expect_boss_issue(plan, wrong_region, "boss_encounter_mismatch", "region 关联错误必须失败")
	var wrong_core: Dictionary = _valid_boss_descriptor()
	wrong_core["core_poi_instance_id"] = "high_2_instance"
	_expect_boss_issue(plan, wrong_core, "boss_encounter_mismatch", "core POI 关联错误必须失败")
	var extraction_field: Dictionary = _valid_boss_descriptor()
	extraction_field["extraction_sites"] = []
	_expect_boss_issue(
		plan,
		extraction_field,
		"invalid_boss_encounter_descriptor",
		"descriptor 携带 extraction 字段必须失败"
	)
	var numeric_encounter_id: Dictionary = _valid_boss_descriptor()
	numeric_encounter_id["encounter_id"] = 123
	_expect_boss_issue(
		plan,
		numeric_encounter_id,
		"invalid_boss_encounter_descriptor",
		"数字 encounter id 不得被强转为字符串"
	)
	var numeric_anchor_id: Dictionary = _valid_boss_descriptor()
	(numeric_anchor_id["anchors"][0] as Dictionary)["id"] = 123
	_expect_boss_issue(
		plan,
		numeric_anchor_id,
		"invalid_boss_encounter_descriptor",
		"数字 anchor id 不得被强转为字符串"
	)


func _test_authority_and_payload_codecs() -> void:
	var plan = _create_valid_plan()
	if plan == null:
		return
	var encounter_result = MAP_TYPES.BossEncounterDescriptor.create_structurally_validated(
		plan,
		_valid_boss_descriptor()
	)
	if not encounter_result.is_success():
		_expect(false, "payload 测试无法构造 BOSS descriptor")
		return
	var map_data = MAP_TYPES.MapData.new()
	map_data.layout_mode = MAP_TYPES.LAYOUT_MODE_PVE_FOUR_REGION_V1
	map_data.region_plan = plan
	map_data.region_boss_encounter = encounter_result.descriptor
	map_data.init_grid(4, 2)
	_expect(
		MAP_TYPES.validate_map_data_layout_artifacts(map_data).is_empty(),
		"合法四区域 MapData 组合必须通过校验"
	)
	_expect(
		not MAP_TYPES.validate_map_data_layout_artifacts(map_data, 1).is_empty(),
		"四区域 MapData 不得与 legacy BOSS encounter 集合混用"
	)
	var cloned = map_data.deep_clone()
	_expect(
		cloned != null
		and cloned.region_plan != plan
		and cloned.region_plan.try_get_at(Vector2i(3, 1)).role == MAP_TYPES.REGION_ROLE_BOSS
		and cloned.region_boss_encounter.get_encounter_id() == "boss_encounter",
		"MapData deep clone 必须保真复制 authority 区域产物"
	)
	var artifact_encoded: Dictionary = MAP_TYPES.encode_map_data_region_artifacts(map_data)
	var artifact_decoded = MAP_TYPES.decode_map_data_region_artifacts(artifact_encoded)
	_expect(artifact_decoded.is_success(), "四区域 MapData authority codec 必须往返成功")
	var numeric_artifact_mode: Dictionary = artifact_encoded.duplicate(true)
	numeric_artifact_mode["layout_mode"] = 1
	_expect(
		not MAP_TYPES.decode_map_data_region_artifacts(numeric_artifact_mode).is_success(),
		"MapData authority codec 不得强转数字 layout mode"
	)
	var invalid_legacy = MAP_TYPES.MapData.new()
	invalid_legacy.region_plan = plan
	_expect(
		_has_issue(
			MAP_TYPES.validate_map_data_layout_artifacts(invalid_legacy),
			"layout_mode_artifact_mismatch"
		),
		"legacy mode 携带 RegionPlan 必须失败"
	)

	var view_result = MAP_TYPES.project_region_plan_view(plan)
	_expect(view_result.is_success(), "authority RegionPlan 必须可投影为 RegionPlanView")
	if not view_result.is_success():
		return
	var view_encoded: Dictionary = MAP_TYPES.encode_region_plan_view(view_result.view)
	_expect(not view_encoded.has("regions"), "RegionPlanView 不得泄露 authority regions")
	for entry: Dictionary in view_encoded.get("region_catalog", []) as Array:
		for forbidden_key: String in [
			"content_profile_id",
			"center_cell",
			"core_anchor_cell",
			"core_poi_template_id",
			"core_poi_instance_id",
			"encounter_profile_id",
		]:
			_expect(not entry.has(forbidden_key), "RegionPlanView 泄露 authority 字段：%s" % forbidden_key)
	var view_decoded = MAP_TYPES.decode_region_plan_view(view_encoded)
	_expect(
		view_decoded.is_success()
		and view_decoded.view.try_get_at(Vector2i(3, 1)).role == MAP_TYPES.REGION_ROLE_BOSS,
		"RegionPlanView codec 必须保留按格查询"
	)
	var leaking_view: Dictionary = view_encoded.duplicate(true)
	leaking_view["regions"] = MAP_TYPES.encode_region_plan_authority(plan).get("regions", [])
	_expect(
		not MAP_TYPES.decode_region_plan_view(leaking_view).is_success(),
		"RegionPlanView 必须拒绝 authority-only 顶层字段"
	)
	var missing_region_membership: Dictionary = view_encoded.duplicate(true)
	missing_region_membership["region_index_by_cell"] = [0, 0, 0, 0, 0, 0, 0, 0]
	_expect(
		not MAP_TYPES.decode_region_plan_view(missing_region_membership).is_success(),
		"RegionPlanView 必须拒绝没有实际格子的固定区域"
	)
	var string_view_index: Dictionary = view_encoded.duplicate(true)
	(string_view_index["region_catalog"][0] as Dictionary)["index"] = "0"
	_expect(
		not MAP_TYPES.decode_region_plan_view(string_view_index).is_success(),
		"RegionPlanView 不得强转字符串 index"
	)
	var fractional_view_rank: Dictionary = view_encoded.duplicate(true)
	(fractional_view_rank["region_catalog"][3] as Dictionary)["difficulty_rank"] = 3.5
	_expect(
		not MAP_TYPES.decode_region_plan_view(fractional_view_rank).is_success(),
		"RegionPlanView 不得截断小数 rank"
	)
	var string_view_schema: Dictionary = view_encoded.duplicate(true)
	string_view_schema["schema_version"] = str(MAP_TYPES.REGION_PLAN_SCHEMA_VERSION)
	_expect(
		not MAP_TYPES.decode_region_plan_view(string_view_schema).is_success(),
		"RegionPlanView codec 不得强转字符串 schema version"
	)
	var string_view_map_size: Dictionary = view_encoded.duplicate(true)
	(string_view_map_size["map_size"] as Dictionary)["x"] = "4"
	_expect(
		not MAP_TYPES.decode_region_plan_view(string_view_map_size).is_success(),
		"RegionPlanView codec 不得强转字符串 map_size"
	)

	var payload = MAP_TYPES.build_server_payload_from_runtime(map_data, [], 1.0, 123, 7)
	_expect(payload.is_valid, "合法四区域 MapData 必须构建有效 full payload")
	var mismatched_map_data = map_data.deep_clone()
	mismatched_map_data.width += 1
	var mismatched_payload = MAP_TYPES.build_server_payload_from_runtime(
		mismatched_map_data,
		[],
		1.0,
		123,
		7
	)
	var generator = GENERATOR_SCRIPT.new()
	var null_generator_payload = generator.build_server_payload(null)
	_expect(
		not null_generator_payload.is_valid
		and _has_issue(
			null_generator_payload.get_issues(),
			"layout_mode_artifact_mismatch"
		),
		"generator payload builder 必须拒绝空 MapData"
	)
	var mismatched_generator_payload = generator.build_server_payload(mismatched_map_data)
	_expect(
		not mismatched_payload.is_valid
		and _has_issue(mismatched_payload.get_issues(), "invalid_region_payload"),
		"payload builder 必须拒绝 RegionPlan 与 MapData 尺寸不一致"
	)
	_expect(
		not mismatched_generator_payload.is_valid
		and _has_issue(
			mismatched_generator_payload.get_issues(),
			"invalid_region_payload"
		),
		"generator payload builder 必须拒绝 RegionPlan 与 MapData 尺寸不一致"
	)
	var payload_dict: Dictionary = payload.to_dict()
	_expect(not payload_dict.has("region_boss_encounter"), "full payload 不得下发 authority BOSS descriptor")
	_expect(not payload_dict.has("boss_encounters"), "四区域 full payload 不得写入 legacy BOSS 集合")
	var decoded_payload = MAP_TYPES.server_payload_from_variant(payload_dict)
	_expect(
		decoded_payload.is_valid
		and decoded_payload.region_plan != null
		and decoded_payload.region_plan.get_map_size() == Vector2i(4, 2),
		"合法四区域 full payload 必须原子解码"
	)

	var wrong_row_count: Dictionary = payload_dict.duplicate(true)
	(wrong_row_count["tile_matrix"] as Array).pop_back()
	_expect_invalid_payload(wrong_row_count, "tile_matrix 行数错误必须拒绝")
	var wrong_row_width: Dictionary = payload_dict.duplicate(true)
	(wrong_row_width["tile_matrix"][0] as Array).pop_back()
	_expect_invalid_payload(wrong_row_width, "tile_matrix 行宽错误必须拒绝")
	var malformed_payload_object = MAP_TYPES.server_payload_from_variant(payload_dict)
	malformed_payload_object.tile_matrix.pop_back()
	_expect(
		not MAP_TYPES.server_payload_from_variant(malformed_payload_object).is_valid,
		"MapServerPayload 对象解码也必须原子校验 tile_matrix 尺寸"
	)
	var malformed_tile_object = MAP_TYPES.server_payload_from_variant(payload_dict)
	(malformed_tile_object.tile_matrix[0] as Array)[0] = "0"
	_expect(
		not MAP_TYPES.server_payload_from_variant(malformed_tile_object).is_valid,
		"MapServerPayload 对象解码不得强转四区域字符串 tile"
	)
	var wrong_view_size: Dictionary = payload_dict.duplicate(true)
	wrong_view_size["width"] = 5
	_expect_invalid_payload(wrong_view_size, "view map_size 与 payload 尺寸不一致必须拒绝")
	var string_payload_width: Dictionary = payload_dict.duplicate(true)
	string_payload_width["width"] = "4"
	_expect_invalid_payload(string_payload_width, "四区域 payload 不得强转字符串 width")
	var fractional_payload_height: Dictionary = payload_dict.duplicate(true)
	fractional_payload_height["height"] = 2.5
	_expect_invalid_payload(fractional_payload_height, "四区域 payload 不得截断小数 height")
	var string_payload_tile: Dictionary = payload_dict.duplicate(true)
	(string_payload_tile["tile_matrix"][0] as Array)[0] = "0"
	_expect_invalid_payload(string_payload_tile, "四区域 payload 不得强转字符串 tile")
	var string_payload_seed: Dictionary = payload_dict.duplicate(true)
	string_payload_seed["resolved_seed"] = "123"
	_expect_invalid_payload(string_payload_seed, "四区域 payload 不得强转字符串 seed")
	var fractional_payload_revision: Dictionary = payload_dict.duplicate(true)
	fractional_payload_revision["revision"] = 7.5
	_expect_invalid_payload(fractional_payload_revision, "四区域 payload 不得截断小数 revision")
	var string_payload_cell_size: Dictionary = payload_dict.duplicate(true)
	string_payload_cell_size["cell_size_m"] = "1.0"
	_expect_invalid_payload(string_payload_cell_size, "四区域 payload 不得强转字符串 cell_size_m")
	var no_mode_with_plan: Dictionary = payload_dict.duplicate(true)
	no_mode_with_plan.erase("layout_mode")
	_expect_invalid_payload(no_mode_with_plan, "无 mode 却携带 plan 必须拒绝")
	var legacy_with_plan: Dictionary = payload_dict.duplicate(true)
	legacy_with_plan["layout_mode"] = MAP_TYPES.LAYOUT_MODE_LEGACY_RADIAL
	_expect_invalid_payload(legacy_with_plan, "legacy payload 携带 plan 必须拒绝")
	var four_region_without_plan: Dictionary = payload_dict.duplicate(true)
	four_region_without_plan.erase("region_plan")
	_expect_invalid_payload(four_region_without_plan, "四区域 payload 缺少 plan 必须拒绝")
	var unknown_mode: Dictionary = payload_dict.duplicate(true)
	unknown_mode["layout_mode"] = "future_mode"
	_expect_invalid_payload(unknown_mode, "未知 payload mode 必须拒绝")
	var numeric_mode: Dictionary = payload_dict.duplicate(true)
	numeric_mode["layout_mode"] = 1
	_expect_invalid_payload(numeric_mode, "payload 不得强转数字 layout mode")
	var old_legacy_payload: Dictionary = {
		"width": 4,
		"height": 2,
		"tile_matrix": [[0], [0, 0, 0, 0]],
	}
	_expect(
		MAP_TYPES.server_payload_from_variant(old_legacy_payload).is_valid,
		"旧 legacy payload 必须保留宽松 tile_matrix 兼容"
	)
	var explicit_legacy_payload: Dictionary = old_legacy_payload.duplicate(true)
	explicit_legacy_payload["layout_mode"] = MAP_TYPES.LAYOUT_MODE_LEGACY_RADIAL
	_expect(
		MAP_TYPES.server_payload_from_variant(explicit_legacy_payload).is_valid,
		"显式 legacy_radial 且无 plan 的 payload 必须合法"
	)


func _test_generator_fail_closed() -> void:
	var parse_result = CONFIG_CATALOG.parse_and_normalize_config(_valid_four_region_config())
	if not parse_result.is_success():
		_expect(false, "generator fail-closed 测试配置解析失败")
		return
	var generator = GENERATOR_SCRIPT.new()
	var map_data = generator.generate_full(parse_result.config)
	_expect(map_data == null, "generate_full 必须拒绝尚未实现的四区域模式")
	_expect_generation_not_implemented(generator, "generate_full")
	_expect(generator.last_resolved_seed == 0, "四区域失败前不得推进 resolved seed")
	var payload = generator.generate_server_payload(parse_result.config)
	_expect(payload == null, "generate_server_payload 必须拒绝尚未实现的四区域模式")
	_expect_generation_not_implemented(generator, "generate_server_payload")
	var snapshots: Array = generator.generate_step_by_step(parse_result.config)
	_expect(snapshots.is_empty(), "generate_step_by_step 失败时不得留下 radial snapshot")
	_expect_generation_not_implemented(generator, "generate_step_by_step")


func _test_preview_clear_contract() -> void:
	var preview = PREVIEW_SCRIPT.new()
	var texture_rect: TextureRect = TextureRect.new()
	var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	texture_rect.texture = ImageTexture.create_from_image(image)
	var hover_rect: ColorRect = ColorRect.new()
	hover_rect.visible = true
	var hover_label: Label = Label.new()
	hover_label.visible = true
	var seed_label: Label = Label.new()
	seed_label.text = "种子：123"
	preview.set("_current_map_data", MAP_TYPES.MapData.new())
	preview.set("_texture_rect", texture_rect)
	preview.set("_hover_cell_rect", hover_rect)
	preview.set("_hover_tile_label", hover_label)
	preview.set("_seed_label", seed_label)
	preview.call("_clear_preview_result")
	_expect(preview.get("_current_map_data") == null, "预览失败态必须清空旧 MapData")
	_expect(texture_rect.texture == null, "预览失败态必须清空旧纹理")
	_expect(not hover_rect.visible and not hover_label.visible, "预览失败态必须清空 hover overlay")
	_expect(seed_label.text == "种子：-", "预览失败态必须清空旧种子标记")
	preview.free()
	texture_rect.free()
	hover_rect.free()
	hover_label.free()
	seed_label.free()


func _valid_four_region_config() -> Dictionary:
	return {
		"schema_version": 2,
		"id": "four_region_contract_smoke",
		"display_name": "四区域契约 Smoke",
		"map": {
			"width_cells": 8,
			"height_cells": 8,
			"seed": {"mode": "fixed", "fixed_value": 12345},
			"player_spawn": {"count": 1},
			"extraction_sites": {"count": 1},
		},
		"terrain": {},
		"minerals": {},
		"poi_generation": {
			"poi_types": [
				{"id": "high_1_core"},
				{"id": "high_2_core"},
				{"id": "boss_core"},
			]
		},
		"region_layout": {
			"mode": MAP_TYPES.LAYOUT_MODE_PVE_FOUR_REGION_V1,
			"regular": {
				"id": "regular_region",
				"display_name": "常规区域",
				"content_profile_id": "regular_content",
			},
			"high_1": {
				"id": "high_1_region",
				"display_name": "高等级区域 1",
				"layout_profile_id": "high_1_layout",
				"content_profile_id": "high_1_content",
				"core_poi": {"template_id": "high_1_core", "max_center_offset_cells": 3},
			},
			"high_2": {
				"id": "high_2_region",
				"display_name": "高等级区域 2",
				"layout_profile_id": "high_2_layout",
				"content_profile_id": "high_2_content",
				"core_poi": {"template_id": "high_2_core", "max_center_offset_cells": 2},
			},
			"boss": {
				"id": "boss_region",
				"display_name": "BOSS 区域",
				"layout_profile_id": "boss_layout",
				"content_profile_id": "boss_content",
				"core_poi": {"template_id": "boss_core", "max_center_offset_cells": 1},
				"encounter_profile_id": "boss_encounter_profile",
			},
		},
	}


func _valid_region_descriptors() -> Array:
	return [
		{
			"index": 0,
			"id": "regular_region",
			"display_name": "常规区域",
			"role": MAP_TYPES.REGION_ROLE_REGULAR,
			"difficulty_rank": 0,
			"content_profile_id": "regular_content",
			"center_cell": Vector2i(0, 0),
		},
		{
			"index": 1,
			"id": "high_1_region",
			"display_name": "高等级区域 1",
			"role": MAP_TYPES.REGION_ROLE_HIGH_1,
			"difficulty_rank": 1,
			"content_profile_id": "high_1_content",
			"center_cell": Vector2i(2, 0),
			"core_anchor_cell": Vector2i(2, 0),
			"core_poi_template_id": "high_1_core",
			"core_poi_instance_id": "high_1_instance",
		},
		{
			"index": 2,
			"id": "high_2_region",
			"display_name": "高等级区域 2",
			"role": MAP_TYPES.REGION_ROLE_HIGH_2,
			"difficulty_rank": 2,
			"content_profile_id": "high_2_content",
			"center_cell": Vector2i(0, 1),
			"core_anchor_cell": Vector2i(0, 1),
			"core_poi_template_id": "high_2_core",
			"core_poi_instance_id": "high_2_instance",
		},
		{
			"index": 3,
			"id": "boss_region",
			"display_name": "BOSS 区域",
			"role": MAP_TYPES.REGION_ROLE_BOSS,
			"difficulty_rank": 3,
			"content_profile_id": "boss_content",
			"center_cell": Vector2i(2, 1),
			"core_anchor_cell": Vector2i(2, 1),
			"core_poi_template_id": "boss_core",
			"core_poi_instance_id": "boss_instance",
		},
	]


func _valid_membership() -> PackedInt32Array:
	return PackedInt32Array([0, 0, 1, 1, 2, 2, 3, 3])


func _create_valid_plan() -> Variant:
	var result = MAP_TYPES.RegionPlan.create_structurally_validated(
		MAP_TYPES.REGION_PLAN_SCHEMA_VERSION,
		Vector2i(4, 2),
		_valid_region_descriptors(),
		_valid_membership()
	)
	if not result.is_success():
		_expect(false, "测试夹具 RegionPlan 构造失败")
		return null
	return result.plan


func _valid_boss_descriptor() -> Dictionary:
	return {
		"encounter_id": "boss_encounter",
		"region_id": "boss_region",
		"core_poi_instance_id": "boss_instance",
		"encounter_profile_id": "boss_encounter_profile",
		"anchors": [
			{"id": "phase_start", "cell": Vector2i(2, 1)},
			{"id": "summon_slot", "cell": Vector2i(3, 1)},
		],
	}


func _expect_parse_issue(raw_config: Variant, code: String, path: String = "") -> void:
	var result = CONFIG_CATALOG.parse_and_normalize_config(raw_config)
	_expect(not result.is_success(), "预期配置失败但成功：%s" % code)
	_expect(
		_has_issue(result.get_issues(), code, path),
		"配置错误缺少 issue：%s @ %s，实际=%s" % [code, path, result.get_issues()]
	)


func _expect_plan_issue(raw_regions: Array, membership: Variant, message: String) -> void:
	var result = MAP_TYPES.RegionPlan.create_structurally_validated(
		MAP_TYPES.REGION_PLAN_SCHEMA_VERSION,
		Vector2i(4, 2),
		raw_regions,
		membership
	)
	_expect(
		not result.is_success()
		and _has_issue(result.get_issues(), "invalid_region_layout_artifact"),
		message
	)


func _expect_boss_issue(plan: Variant, raw: Dictionary, code: String, message: String) -> void:
	var result = MAP_TYPES.BossEncounterDescriptor.create_structurally_validated(plan, raw)
	_expect(not result.is_success() and _has_issue(result.get_issues(), code), message)


func _expect_invalid_payload(payload_dict: Dictionary, message: String) -> void:
	var payload = MAP_TYPES.server_payload_from_variant(payload_dict)
	_expect(not payload.is_valid and _has_issue(payload.get_issues(), "invalid_region_payload"), message)


func _expect_generation_not_implemented(generator: Variant, entry_name: String) -> void:
	_expect(
		_has_issue(generator.get_last_generation_issues(), "region_layout_mode_not_implemented"),
		"%s 必须暴露 region_layout_mode_not_implemented" % entry_name
	)
	_expect(
		generator.last_generation_error == "pve_four_region_v1 区域生成尚未实现",
		"%s 的兼容字符串错误必须由首个结构化 issue 派生" % entry_name
	)


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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
