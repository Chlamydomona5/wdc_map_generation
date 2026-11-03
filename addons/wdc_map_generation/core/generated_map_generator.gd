class_name WdcMapGenerationGenerator
extends RefCounted

const WdcMapGenerationTypes = preload("generated_map_types.gd")
const WdcMapGenerationTileRules = preload("generated_map_tile_rules.gd")
const WdcFourRegionLayoutProducer = preload("four_region_layout_producer.gd")
const WdcFourRegionLayoutValidator = preload("four_region_layout_validator.gd")
const WdcRegionContentResolver = preload("region_content_resolver.gd")
const POI_COMPOSITION_GENERATOR = preload("poi_composition_generator.gd")
const AUTHORED_CONTENT_ALLOCATOR = preload("authored_poi_content_allocator.gd")
const POI_POPULATION_CONTRACT = preload("poi_population_contract.gd")

signal generation_stage_completed(stage: StringName, map_data: WdcMapGenerationTypes.MapData)

var last_resolved_seed: int = 0
var last_four_region_success_attempt: int = -1
var last_four_region_attempt_issues: Array[Dictionary] = []
var last_generation_error: String = ""
var last_generation_issues: Array[Dictionary] = []
var _active_authored_seed: int = 0

const STAGE_INIT: StringName = &"INIT"
const STAGE_POI: StringName = &"POI"
const STAGE_NOISE: StringName = &"NOISE"
const STAGE_CAVE: StringName = &"CAVE"
const STAGE_CORRIDOR: StringName = &"CORRIDOR"
const STAGE_TRACE: StringName = &"TRACE"
const STAGE_MINERAL: StringName = &"MINERAL"
const STAGE_TRAP: StringName = &"TRAP"
const FOUR_REGION_POI_ATTEMPT_SAFETY_MULTIPLIER: int = 4
const PLAYER_SPAWN_HARD_MIN_DISTANCE_CELLS: float = 6.0


func generate_full(config: WdcMapGenerationTypes.MapConfig) -> WdcMapGenerationTypes.MapData:
	return _generate_internal(config, false).get("map_data") as WdcMapGenerationTypes.MapData


func generate_server_payload(config: WdcMapGenerationTypes.MapConfig) -> WdcMapGenerationTypes.MapServerPayload:
	var map_data: WdcMapGenerationTypes.MapData = generate_full(config)
	if map_data == null:
		return null
	var payload_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var resolved_seed: int = last_resolved_seed if last_resolved_seed != 0 else _resolve_seed(config.seed)
	payload_rng.seed = resolved_seed + 1315423911
	return _build_server_payload_with_rng(map_data, payload_rng)


func build_server_payload(map_data: WdcMapGenerationTypes.MapData) -> WdcMapGenerationTypes.MapServerPayload:
	var payload_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	payload_rng.seed = int(Time.get_unix_time_from_system())
	return _build_server_payload_with_rng(map_data, payload_rng)


func _build_server_payload_with_rng(
	map_data: WdcMapGenerationTypes.MapData,
	_rng: RandomNumberGenerator
) -> WdcMapGenerationTypes.MapServerPayload:
	var payload: WdcMapGenerationTypes.MapServerPayload = WdcMapGenerationTypes.MapServerPayload.new()
	if map_data == null:
		payload.is_valid = false
		payload.issues.append(WdcMapGenerationTypes.make_generation_issue(
			"layout_mode_artifact_mismatch",
			"map_data",
			"",
			"无法从空 MapData 构建 payload"
		))
		return payload
	payload.layout_mode = map_data.layout_mode
	var layout_issues: Array[Dictionary] = WdcMapGenerationTypes.validate_map_data_layout_artifacts(
		map_data
	)
	if not layout_issues.is_empty():
		payload.is_valid = false
		payload.issues = layout_issues.duplicate(true)
		return payload
	if map_data.layout_mode == WdcMapGenerationTypes.LAYOUT_MODE_PVE_FOUR_REGION_V1:
		var view_result: WdcMapGenerationTypes.RegionPlanViewBuildResult = (
			WdcMapGenerationTypes.project_region_plan_view(map_data.region_plan)
		)
		if not view_result.is_success():
			payload.is_valid = false
			payload.issues = view_result.get_issues()
			return payload
		var view_size: Vector2i = view_result.view.get_map_size()
		if view_size != Vector2i(map_data.width, map_data.height):
			payload.is_valid = false
			payload.issues.append(WdcMapGenerationTypes.make_generation_issue(
				"invalid_region_payload",
				"region_plan.map_size",
				"",
				"RegionPlanView 地图尺寸与 MapData 尺寸不一致"
			))
			return payload
		payload.region_plan = view_result.view
	payload.width = map_data.width
	payload.height = map_data.height
	payload.tile_matrix = _build_server_tile_matrix(map_data)
	payload.player_spawn_points = map_data.player_spawn_points.duplicate(true)
	payload.extraction_sites = map_data.extraction_sites.duplicate(true)
	return payload


func generate_step_by_step(config: WdcMapGenerationTypes.MapConfig) -> Array[Dictionary]:
	return _generate_internal(config, true).get("snapshots", []) as Array[Dictionary]


func _generate_internal(config: WdcMapGenerationTypes.MapConfig, capture_snapshots: bool) -> Dictionary:
	last_generation_error = ""
	last_generation_issues.clear()
	last_four_region_success_attempt = -1
	if config == null:
		return _fail_generation(
			WdcMapGenerationTypes.make_generation_issue(
				"invalid_region_layout_declaration",
				"config",
				"",
				"地图生成配置不能为空"
			)
		)
	var config_issues: Array[Dictionary] = config.get_validation_issues()
	if not config_issues.is_empty():
		last_generation_issues = config_issues.duplicate(true)
		last_generation_error = str(last_generation_issues[0].get("message", "地图配置无效"))
		return {}
	if config.layout_mode == WdcMapGenerationTypes.LAYOUT_MODE_PVE_FOUR_REGION_V1:
		return _generate_four_region_internal(config, capture_snapshots)
	if config.layout_mode == WdcMapGenerationTypes.LAYOUT_MODE_POI_ONLY_V1:
		return _generate_poi_only_internal(config, capture_snapshots)
	if config.layout_mode != WdcMapGenerationTypes.LAYOUT_MODE_LEGACY_RADIAL:
		return _fail_generation(
			WdcMapGenerationTypes.make_generation_issue(
				"unsupported_region_layout_mode",
				"region_layout.mode",
				"",
				"不支持的区域布局模式：%s" % config.layout_mode
			)
		)
	var normalized_config: WdcMapGenerationTypes.MapConfig = config
	normalized_config.normalize()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	last_resolved_seed = _resolve_seed(normalized_config.seed)
	rng.seed = last_resolved_seed
	var map_data: WdcMapGenerationTypes.MapData = WdcMapGenerationTypes.MapData.new()
	map_data.layout_mode = normalized_config.layout_mode
	map_data.init_grid(normalized_config.width, normalized_config.height)
	var snapshots: Array[Dictionary] = []
	_emit_stage(snapshots, STAGE_INIT, map_data, "INIT", capture_snapshots)
	_fill_noise(map_data, normalized_config.fill_percent, rng)
	_emit_stage(snapshots, STAGE_NOISE, map_data, "NOISE", capture_snapshots)
	_smooth_caves(map_data, normalized_config.smooth_iterations)
	_emit_stage(snapshots, STAGE_CAVE, map_data, "CAVE", capture_snapshots)
	_dig_corridors(map_data, normalized_config, rng)
	_emit_stage(snapshots, STAGE_CORRIDOR, map_data, "CORRIDOR", capture_snapshots)
	_generate_minerals(map_data, normalized_config, rng)
	_place_all_pois(map_data, normalized_config, rng)
	_emit_stage(snapshots, STAGE_POI, map_data, "POI", capture_snapshots)
	_generate_traces(map_data, normalized_config, rng)
	_emit_stage(snapshots, STAGE_TRACE, map_data, "TRACE", capture_snapshots)
	_generate_poi_special_blocks(map_data, normalized_config, rng)
	_generate_environmental_traps(map_data, normalized_config, rng)
	_emit_stage(snapshots, STAGE_TRAP, map_data, "TRAP", capture_snapshots)
	_apply_layer_durability_overrides(map_data, normalized_config)
	_generate_spawn_and_extraction_sites(map_data, normalized_config)
	_recalculate_stats(map_data)
	_emit_stage(snapshots, STAGE_MINERAL, map_data, "MINERAL", capture_snapshots)
	return {
		"map_data": map_data,
		"snapshots": snapshots
	}


## 只组装一个正式图纸组合；外围开放区承载出生与撤离，不生成环境随机内容。
func _generate_poi_only_internal(config: WdcMapGenerationTypes.MapConfig, capture_snapshots: bool) -> Dictionary:
	var selected: Dictionary = config.get_meta("poi_only", {})
	var bundle: Dictionary = config.get_meta("poi_resource_bundle", {})
	last_resolved_seed = _resolve_seed(config.seed)
	_active_authored_seed = last_resolved_seed
	var composition_id: String = str(selected.get("composition_id", ""))
	var preview: Dictionary = POI_COMPOSITION_GENERATOR.generate(composition_id, bundle, last_resolved_seed)
	if not bool(preview.get("valid", false)):
		last_generation_issues.assign(preview.get("issues", []))
		last_generation_error = str(last_generation_issues[0].get("message", "POI-only 组装失败"))
		return {}
	var bounds: Dictionary = preview.plan.bounds
	var padding: int = int(selected.get("padding_cells", 8))
	var width: int = maxi(int(bounds.width) + padding * 2, 32)
	var height: int = maxi(int(bounds.height) + padding * 2, 32)
	if width > 512 or height > 512:
		return _fail_generation(WdcMapGenerationTypes.make_generation_issue("poi_only_too_large", "poi_only", "", "测试组合含净空后的尺寸不得超过 512 格"))
	# 尺寸由同 seed 的实际图纸确定，客户端和 authority 使用发布产物的真实尺寸。
	config.width = width
	config.height = height
	var map_data: WdcMapGenerationTypes.MapData = WdcMapGenerationTypes.MapData.new()
	map_data.layout_mode = WdcMapGenerationTypes.LAYOUT_MODE_POI_ONLY_V1
	map_data.init_grid(width, height)
	for y: int in range(1, height - 1):
		for x: int in range(1, width - 1):
			map_data.get_cell(x, y).cell_type = WdcMapGenerationTypes.CellType.FLOOR
	var center: Vector2i = Vector2i(padding - int(bounds.x), padding - int(bounds.y))
	var template: Dictionary = _find_template_by_id(config.poi_templates, str(selected.get("source_template_id", "")))
	var resolver: WdcRegionContentResolver = WdcRegionContentResolver.new(config)
	var role: String = str(selected.get("region_role", ""))
	var is_boss: bool = not str(bundle.get("compositions", {}).get(composition_id, {}).get("reward_recipe_id", "")).is_empty()
	var instance: Dictionary = _try_place_authored_poi(map_data, config, template, role, -1,
		PackedInt32Array(), center, is_boss, 0, 0, resolver)
	if instance.is_empty():
		return _fail_generation(WdcMapGenerationTypes.make_generation_issue("poi_only_placement_failed", "poi_only", role, "测试图纸无法放入地图或缺少完整 BOSS 具名配方"))
	var issues: Array[Dictionary] = AUTHORED_CONTENT_ALLOCATOR.allocate(map_data, resolver, last_resolved_seed, config.get_meta("poi_population_limits", {}))
	if issues.is_empty():
		issues.append_array(_materialize_authored_content(map_data, config, resolver))
	if issues.is_empty():
		issues.append_array(POI_POPULATION_CONTRACT.validate(map_data, config.get_meta("poi_population_limits", {})))
	if not issues.is_empty():
		last_generation_issues = issues
		last_generation_error = str(issues[0].get("message", "测试内容分配失败"))
		return {}
	_apply_four_region_durability(map_data, resolver)
	# 外围六格以上净空保证队伍出生与撤离点不占图纸、家具和遭遇的位置。
	map_data.player_spawn_points.append({"x": 3, "y": 3, "site_kind": "player_spawn", "region_role": role})
	map_data.extraction_sites.append({"x": width - 4, "y": height - 4, "site_kind": "extraction", "region_role": role})
	var reached: Dictionary = {Vector2i(3, 3): true}
	var queue: Array[Vector2i] = [Vector2i(3, 3)]
	var cursor: int = 0
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]
		cursor += 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + step
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(next.x, next.y)
			if cell != null and cell.cell_type == WdcMapGenerationTypes.CellType.FLOOR and not reached.has(next):
				reached[next] = true
				queue.append(next)
	var access_target: Vector2i = center
	if not reached.has(access_target) or not reached.has(Vector2i(width - 4, height - 4)):
		return _fail_generation(WdcMapGenerationTypes.make_generation_issue("poi_only_entry_unreachable", "poi_only", role, "出生点无法抵达组合入口或撤离点；请为普通图纸配置开放的外部端口"))
	if is_boss:
		var boss_issues: Array[Dictionary] = _validate_authored_boss_geometry(map_data, instance)
		if not boss_issues.is_empty():
			last_generation_issues = boss_issues
			last_generation_error = str(boss_issues[0].message)
			return {}
	for y: int in range(height):
		for x: int in range(width):
			if map_data.get_cell(x, y).cell_type == WdcMapGenerationTypes.CellType.FLOOR:
				map_data.total_floor += 1
	var snapshots: Array[Dictionary] = []
	_emit_stage(snapshots, STAGE_POI, map_data, "POI-only 图纸、内容与测试入口已生成", capture_snapshots)
	return {"map_data": map_data, "snapshots": snapshots}


func _generate_four_region_internal(
	config: WdcMapGenerationTypes.MapConfig,
	capture_snapshots: bool
) -> Dictionary:
	var normalized_config: WdcMapGenerationTypes.MapConfig = config
	normalized_config.normalize()
	var resolved_seed: int = _resolve_seed(normalized_config.seed)
	var producer: WdcFourRegionLayoutProducer = WdcFourRegionLayoutProducer.new()
	_active_authored_seed = resolved_seed
	var max_attempts: int = producer.get_max_attempts(normalized_config)
	var terminal_issues: Array[Dictionary] = []
	last_four_region_attempt_issues.clear()
	for attempt_index: int in range(max_attempts):
		if not terminal_issues.is_empty():
			last_four_region_attempt_issues.append({"attempt": attempt_index - 1, "issues": terminal_issues.duplicate(true)})
		var draft = producer.build_attempt(normalized_config, resolved_seed, attempt_index)
		if not draft.is_success():
			terminal_issues = draft.get_issues()
			continue
		var map_data: WdcMapGenerationTypes.MapData = WdcMapGenerationTypes.MapData.new()
		map_data.layout_mode = WdcMapGenerationTypes.LAYOUT_MODE_PVE_FOUR_REGION_V1
		map_data.init_grid(normalized_config.width, normalized_config.height)
		var terrain_rng: RandomNumberGenerator = _make_four_region_rng(
			resolved_seed,
			attempt_index,
			101
		)
		_fill_noise(map_data, normalized_config.fill_percent, terrain_rng)
		_smooth_caves(map_data, normalized_config.smooth_iterations)
		_dig_corridors(map_data, normalized_config, terrain_rng)
		var core_result: Dictionary = _place_four_region_core_pois(
			map_data,
			normalized_config,
			draft.membership,
			draft.centers_by_role,
			attempt_index,
			resolved_seed
		)
		if not bool(core_result.get("success", false)):
			terminal_issues = _extract_dictionary_array(core_result.get("issues", []))
			continue
		var plan_result: Dictionary = _build_four_region_plan(
			normalized_config,
			draft.membership,
			draft.centers_by_role,
			core_result.get("instances_by_role", {}) as Dictionary
		)
		if not bool(plan_result.get("success", false)):
			terminal_issues = _extract_dictionary_array(plan_result.get("issues", []))
			continue
		map_data.region_plan = plan_result.get("plan")
		var encounter_result: Dictionary = _build_four_region_boss_descriptor(
			normalized_config,
			map_data.region_plan,
			core_result.get("instances_by_role", {}) as Dictionary
		)
		if not bool(encounter_result.get("success", false)):
			terminal_issues = _extract_dictionary_array(encounter_result.get("issues", []))
			continue
		map_data.region_boss_encounter = encounter_result.get("descriptor")
		var resolver: WdcRegionContentResolver = WdcRegionContentResolver.new(
			normalized_config,
			map_data.region_plan
		)
		var content_rng: RandomNumberGenerator = _make_four_region_rng(
			resolved_seed,
			attempt_index,
			307
		)
		var content_issues: Array[Dictionary] = []
		content_issues.append_array(_generate_four_region_regular_pois(
			map_data,
			normalized_config,
			resolver,
			content_rng,
			attempt_index
		))
		if content_issues.is_empty():
			content_issues.append_array(AUTHORED_CONTENT_ALLOCATOR.allocate(map_data, resolver, resolved_seed, normalized_config.get_meta("poi_population_limits", {})))
		if content_issues.is_empty():
			content_issues.append_array(_generate_four_region_minerals(
				map_data,
				normalized_config,
				resolver,
				content_rng
			))
		if content_issues.is_empty():
			content_issues.append_array(_generate_four_region_room_contents(
				map_data,
				normalized_config,
				resolver,
				content_rng
			))
		if content_issues.is_empty():
			content_issues.append_array(_generate_four_region_traps(
				map_data,
				resolver,
				content_rng
			))
		if content_issues.is_empty():
			content_issues.append_array(_generate_four_region_population_sites(
				map_data,
				normalized_config,
				resolver,
				content_rng
			))
		if content_issues.is_empty():
			content_issues.append_array(POI_POPULATION_CONTRACT.validate(map_data, normalized_config.get_meta("poi_population_limits", {})))
		if not content_issues.is_empty():
			terminal_issues = content_issues
			continue
		_apply_four_region_durability(map_data, resolver)
		var site_issues: Array[Dictionary] = _generate_four_region_spawn_and_extraction(
			map_data,
			normalized_config,
			resolver,
			resolved_seed,
			attempt_index
		)
		if not site_issues.is_empty():
			terminal_issues = site_issues
			continue
		var final_issues: Array[Dictionary] = _validate_four_region_artifact(map_data)
		if not final_issues.is_empty():
			terminal_issues = final_issues
			continue
		_recalculate_stats(map_data)
		last_resolved_seed = resolved_seed
		last_four_region_success_attempt = attempt_index
		var snapshots: Array[Dictionary] = []
		_emit_stage(snapshots, STAGE_MINERAL, map_data, "FINAL", capture_snapshots)
		return {"map_data": map_data, "snapshots": snapshots}
	if terminal_issues.is_empty():
		terminal_issues.append(WdcMapGenerationTypes.make_generation_issue(
			"region_partition_failed",
			"region_generation.layout_profiles",
			"",
			"四区域生成在最大 attempt 内失败"
		))
	return _fail_generation_issues(terminal_issues)


func _place_four_region_core_pois(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	membership: PackedInt32Array,
	centers_by_role: Dictionary,
	attempt_index: int,
	resolved_seed: int
) -> Dictionary:
	var instances_by_role: Dictionary = {}
	for region_index: int in range(1, WdcMapGenerationTypes.REGION_ROLE_ORDER.size()):
		var role: String = WdcMapGenerationTypes.REGION_ROLE_ORDER[region_index]
		var slot: Dictionary = config.region_layout.get(role, {}) as Dictionary
		var core_poi: Dictionary = slot.get("core_poi", {}) as Dictionary
		var template_id: String = str(core_poi.get("template_id", ""))
		var template: Dictionary = _find_template_by_id(config.poi_templates, template_id)
		if template.is_empty():
			return _four_region_failure(
				"unknown_core_poi_reference",
				"region_layout.%s.core_poi.template_id" % role,
				role,
				"核心 POI 模板不存在：%s" % template_id
			)
		var center: Vector2i = centers_by_role.get(role, Vector2i(-1, -1))
		var max_offset: int = maxi(int(core_poi.get("max_center_offset_cells", 0)), 0)
		var candidate_centers: Array[Vector2i] = _collect_center_offset_candidates(
			center,
			max_offset,
			map_data,
			membership,
			region_index
		)
		var placed_instance: Dictionary = {}
		var candidate_ordinal: int = 0
		for candidate_center: Vector2i in candidate_centers:
			var poi_rng: RandomNumberGenerator = _make_four_region_rng(
				resolved_seed,
				attempt_index,
				401 + region_index * 101 + candidate_ordinal
			)
			placed_instance = _try_place_four_region_poi(
				map_data,
				config,
				template,
				role,
				region_index,
				membership,
				candidate_center,
				true,
				attempt_index,
				instances_by_role.size(),
				poi_rng
			)
			if not placed_instance.is_empty():
				break
			candidate_ordinal += 1
		if placed_instance.is_empty():
			return _four_region_failure(
				"core_poi_placement_failed",
				"region_layout.%s.core_poi" % role,
				role,
				"核心 POI 无法在 canonical center 偏移范围内完整放入区域"
			)
		placed_instance["canonical_center"] = center
		placed_instance["max_center_offset_cells"] = max_offset
		for instance_index: int in range(map_data.poi_instances.size() - 1, -1, -1):
			if str(map_data.poi_instances[instance_index].get("instance_id", "")) == str(placed_instance.get("instance_id", "")):
				map_data.poi_instances[instance_index] = placed_instance
				break
		instances_by_role[role] = placed_instance
	return {"success": true, "instances_by_role": instances_by_role, "issues": []}


func _build_four_region_plan(
	config: WdcMapGenerationTypes.MapConfig,
	membership: PackedInt32Array,
	centers_by_role: Dictionary,
	instances_by_role: Dictionary
) -> Dictionary:
	var raw_regions: Array[Dictionary] = []
	for region_index: int in range(WdcMapGenerationTypes.REGION_ROLE_ORDER.size()):
		var role: String = WdcMapGenerationTypes.REGION_ROLE_ORDER[region_index]
		var slot: Dictionary = config.region_layout.get(role, {}) as Dictionary
		var raw_region: Dictionary = {
			"index": region_index,
			"id": str(slot.get("id", "")),
			"display_name": str(slot.get("display_name", "")),
			"role": role,
			"difficulty_rank": WdcMapGenerationTypes.get_region_difficulty_rank(role),
			"content_profile_id": str(slot.get("content_profile_id", "")),
			"center_cell": centers_by_role.get(role, Vector2i(-1, -1)),
		}
		if role != WdcMapGenerationTypes.REGION_ROLE_REGULAR:
			var instance: Dictionary = instances_by_role.get(role, {}) as Dictionary
			raw_region["core_anchor_cell"] = instance.get("center_cell", Vector2i(-1, -1))
			raw_region["core_poi_template_id"] = str(instance.get("template_id", ""))
			raw_region["core_poi_instance_id"] = str(instance.get("instance_id", ""))
		raw_regions.append(raw_region)
	var build_result = WdcMapGenerationTypes.RegionPlan.create_structurally_validated(
		WdcMapGenerationTypes.REGION_PLAN_SCHEMA_VERSION,
		Vector2i(config.width, config.height),
		raw_regions,
		membership
	)
	if not build_result.is_success():
		return {"success": false, "issues": build_result.get_issues()}
	return {"success": true, "plan": build_result.plan, "issues": []}


func _build_four_region_boss_descriptor(
	config: WdcMapGenerationTypes.MapConfig,
	region_plan: Variant,
	instances_by_role: Dictionary
) -> Dictionary:
	var boss_slot: Dictionary = config.region_layout.get(
		WdcMapGenerationTypes.REGION_ROLE_BOSS,
		{}
	) as Dictionary
	var boss_instance: Dictionary = instances_by_role.get(
		WdcMapGenerationTypes.REGION_ROLE_BOSS,
		{}
	) as Dictionary
	var encounter_id: String = "%s:%s" % [
		str(boss_slot.get("id", "")),
		str(boss_instance.get("instance_id", "")),
	]
	var descriptor_result = WdcMapGenerationTypes.BossEncounterDescriptor.create_structurally_validated(
		region_plan,
		{
			"encounter_id": encounter_id,
			"region_id": str(boss_slot.get("id", "")),
			"core_poi_instance_id": str(boss_instance.get("instance_id", "")),
			"encounter_profile_id": str(boss_slot.get("encounter_profile_id", "")),
			"anchors": [{
				"id": "primary",
				"cell": boss_instance.get("center_cell", Vector2i(-1, -1)),
			}],
		}
	)
	if not descriptor_result.is_success():
		return {"success": false, "issues": descriptor_result.get_issues()}
	return {"success": true, "descriptor": descriptor_result.descriptor, "issues": []}


func _generate_four_region_regular_pois(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	resolver: WdcRegionContentResolver,
	rng: RandomNumberGenerator,
	attempt_index: int
) -> Array[Dictionary]:
	var core_template_ids: Dictionary = {}
	for high_role: String in [
		WdcMapGenerationTypes.REGION_ROLE_HIGH_1,
		WdcMapGenerationTypes.REGION_ROLE_HIGH_2,
		WdcMapGenerationTypes.REGION_ROLE_BOSS,
	]:
		var high_slot: Dictionary = config.region_layout.get(high_role, {}) as Dictionary
		var core_poi: Dictionary = high_slot.get("core_poi", {}) as Dictionary
		core_template_ids[str(core_poi.get("template_id", ""))] = true
	for role: String in WdcMapGenerationTypes.REGION_ROLE_ORDER:
		var resolved_region: Dictionary = resolver.resolve_role(role)
		if not bool(resolved_region.get("valid", false)):
			return [resolved_region.get("issue", {}) as Dictionary]
		var region_index: int = int(resolved_region.get("region_index", -1))
		var section: Dictionary = resolver.get_section_for_role(role, "pois")
		var target_count: int = maxi(int(section.get("target_count", 0)), 0)
		var minimum_count: int = clampi(int(section.get("minimum_count", 0)), 0, target_count)
		if target_count <= 0:
			continue
		var entries: Array[Dictionary] = resolver.get_weighted_entries(role, "pois")
		var candidates: Array[Vector2i] = _collect_region_candidate_cells(
			map_data,
			resolver,
			role,
			false,
			true
		)
		_shuffle_vector2i_array(candidates, rng)
		var candidate_limit: int = _resolve_four_region_poi_candidate_limit(
			config,
			entries,
			target_count,
			candidates.size()
		)
		var placed_count: int = 0
		var candidate_cursor: int = 0
		while placed_count < target_count and candidate_cursor < candidate_limit:
			var entry: Dictionary = resolver.pick_weighted_from_entries(entries, rng)
			if entry.is_empty():
				break
			var template_id: String = str(entry.get("template_id", ""))
			if core_template_ids.has(template_id):
				candidate_cursor += 1
				continue
			var template: Dictionary = _find_template_by_id(config.poi_templates, template_id)
			if template.is_empty():
				candidate_cursor += 1
				continue
			var instance: Dictionary = _try_place_four_region_poi(
				map_data,
				config,
				template,
				role,
				region_index,
				PackedInt32Array(),
				candidates[candidate_cursor],
				false,
				attempt_index,
				placed_count,
				rng,
				resolver
			)
			candidate_cursor += 1
			if instance.is_empty():
				continue
			placed_count += 1
		if placed_count < minimum_count:
			return [_four_region_issue(
				"content_minimum_not_met",
				"region_generation.content_profiles.pois",
				role,
				"普通 POI 数量低于 minimum_count：%d < %d" % [placed_count, minimum_count]
			)]
	return []


## 方法职责：将四区域普通 POI 搜索限制在模板声明的尝试预算内，避免失败候选遍历整张地图。
func _resolve_four_region_poi_candidate_limit(
	config: WdcMapGenerationTypes.MapConfig,
	entries: Array[Dictionary],
	target_count: int,
	candidate_count: int
) -> int:
	var attempts_per_poi: int = 1
	for entry: Dictionary in entries:
		var template: Dictionary = _find_template_by_id(
			config.poi_templates,
			str(entry.get("template_id", ""))
		)
		attempts_per_poi = maxi(
			attempts_per_poi,
			maxi(int(template.get("placement", {}).get("poi_attempts", 1)), 1)
		)
	return mini(
		candidate_count,
		attempts_per_poi * maxi(target_count, 1) * FOUR_REGION_POI_ATTEMPT_SAFETY_MULTIPLIER
	)


func _generate_four_region_minerals(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	resolver: WdcRegionContentResolver,
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	_clear_four_region_mineral_cells(map_data)
	var mineral_sites: Array[Dictionary] = []
	for role: String in WdcMapGenerationTypes.REGION_ROLE_ORDER:
		var section: Dictionary = resolver.get_section_for_role(role, "minerals")
		var target_count: int = maxi(int(section.get("target_count", 0)), 0)
		var minimum_count: int = clampi(int(section.get("minimum_count", 0)), 0, target_count)
		if target_count <= 0:
			continue
		var candidates: Array[Vector2i] = _collect_region_candidate_cells(
			map_data,
			resolver,
			role,
			true,
			false
		)
		_shuffle_vector2i_array(candidates, rng)
		var placed_count: int = resolver.get_reserved_count(role, "minerals")
		for candidate: Vector2i in candidates:
			if placed_count >= target_count:
				break
			var entry: Dictionary = resolver.pick_weighted_entry(
				role,
				"minerals",
				rng,
				resolver.get_remaining_value_budget(role, "mineral_value_budget"),
				"value_cost"
			)
			if entry.is_empty():
				break
			var template: Dictionary = _find_template_by_id(
				config.mineral_cluster_types,
				str(entry.get("cluster_type_id", ""))
			)
			if template.is_empty():
				continue
			var generated_cells: Array[Vector2i] = _grow_four_region_cluster(
				map_data,
				candidate,
				config,
				template,
				rng,
				resolver,
				role
			)
			if generated_cells.is_empty():
				continue
			var value_cost: int = maxi(int(entry.get("value_cost", 1)), 1)
			if not resolver.try_spend_value_budget(role, "mineral_value_budget", value_cost):
				return [_four_region_issue(
					"content_budget_exhausted",
					"region_generation.content_profiles.mineral_value_budget",
					role,
					"矿簇生成后无法提交 mineral value budget"
				)]
			mineral_sites.append({
				"site_id": "%s:mineral:%03d" % [role, placed_count],
				"cluster_type_id": str(entry.get("cluster_type_id", "")),
				"cell": candidate,
				"cells": _vector2i_array_to_dict_array(generated_cells),
				"value_cost": value_cost,
			})
			placed_count += 1
		if placed_count < minimum_count:
			return [_four_region_issue(
				"content_minimum_not_met",
				"region_generation.content_profiles.minerals",
				role,
				"矿簇数量低于 minimum_count：%d < %d" % [placed_count, minimum_count]
			)]
	map_data.mineral_sites = mineral_sites
	return []


func _grow_four_region_cluster(
	map_data: WdcMapGenerationTypes.MapData,
	seed_cell: Vector2i,
	config: WdcMapGenerationTypes.MapConfig,
	cluster_template: Dictionary,
	rng: RandomNumberGenerator,
	resolver: WdcRegionContentResolver,
	role: String
) -> Array[Vector2i]:
	if not _is_valid_four_region_cluster_cell(
		map_data,
		seed_cell,
		config,
		cluster_template,
		resolver,
		role
	):
		return []
	var min_size: int = maxi(int(cluster_template.get("min_cluster_size", 1)), 1)
	var max_size: int = maxi(int(cluster_template.get("max_cluster_size", min_size)), min_size)
	var target_size: int = rng.randi_range(min_size, max_size)
	var generated: Array[Vector2i] = []
	if not _place_cluster_cell(map_data, seed_cell, cluster_template):
		return generated
	generated.append(seed_cell)
	while generated.size() < target_size:
		var candidates_by_key: Dictionary = {}
		for generated_cell: Vector2i in generated:
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var candidate: Vector2i = generated_cell + direction
				if candidates_by_key.has(_key(candidate.x, candidate.y)):
					continue
				if not _is_valid_four_region_cluster_cell(
					map_data,
					candidate,
					config,
					cluster_template,
					resolver,
					role
				):
					continue
				candidates_by_key[_key(candidate.x, candidate.y)] = candidate
		if candidates_by_key.is_empty():
			break
		var candidates: Array[Vector2i] = []
		for value: Variant in candidates_by_key.values():
			if value is Vector2i:
				candidates.append(value as Vector2i)
		_shuffle_vector2i_array(candidates, rng)
		var placed_this_round: bool = false
		for candidate: Vector2i in candidates:
			if generated.size() >= target_size:
				break
			if rng.randf() > clampf(float(cluster_template.get("spawn_probability", 1.0)), 0.0, 1.0):
				continue
			if _place_cluster_cell(map_data, candidate, cluster_template):
				generated.append(candidate)
				placed_this_round = true
		if not placed_this_round:
			break
	return generated


func _is_valid_four_region_cluster_cell(
	map_data: WdcMapGenerationTypes.MapData,
	cell_coord: Vector2i,
	config: WdcMapGenerationTypes.MapConfig,
	cluster_template: Dictionary,
	resolver: WdcRegionContentResolver,
	role: String
) -> bool:
	if not map_data.is_in_bounds(cell_coord.x, cell_coord.y):
		return false
	if not resolver.is_cell_in_role(cell_coord, role):
		return false
	# 图纸内部矿物只能来自已扣账的槽位，外部矿簇不能越界补进。
	if map_data.get_cell(cell_coord.x, cell_coord.y).is_poi_protected:
		return false
	return _is_valid_cluster_candidate(map_data, cell_coord, config, cluster_template)


func _generate_four_region_room_contents(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	resolver: WdcRegionContentResolver,
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var population_limits: Dictionary = config.get_meta("poi_population_limits", {})
	var population: Dictionary = POI_POPULATION_CONTRACT.collect_usage(map_data, true)
	for role: String in WdcMapGenerationTypes.REGION_ROLE_ORDER:
		var section: Dictionary = resolver.get_section_for_role(role, "room_contents")
		var target_count: int = maxi(int(section.get("target_count", 0)), 0)
		var minimum_count: int = clampi(int(section.get("minimum_count", 0)), 0, target_count)
		if target_count <= 0:
			continue
		var room_candidates: Array[Dictionary] = _collect_room_content_candidates(
			map_data,
			resolver,
			role
		)
		_shuffle_dictionary_array(room_candidates, rng)
		var entries: Array[Dictionary] = resolver.get_weighted_entries(role, "room_contents")
		var camp_section: Dictionary = resolver.get_section_for_role(role, "camps")
		var camp_minimum_count: int = clampi(
			int(camp_section.get("minimum_count", 0)),
			0,
			maxi(int(camp_section.get("target_count", 0)), 0)
		)
		var minimum_camp_plan_value_cost: int = _minimum_four_region_camp_plan_value_cost(
			entries,
			resolver.get_weighted_entries(role, "camps")
		)
		var planned_counts: Dictionary = {
			"monster_sites": resolver.get_reserved_count(role, "monster_sites"),
			"nests": resolver.get_reserved_count(role, "nests"),
			"camps": resolver.get_reserved_count(role, "camps"),
		}
		var placed_count: int = resolver.get_reserved_count(role, "room_contents")
		for candidate_index: int in range(room_candidates.size()):
			var candidate: Dictionary = room_candidates[candidate_index]
			if placed_count >= target_count:
				break
			var population_entries: Array[Dictionary] = []
			for population_entry: Dictionary in entries:
				var population_request: Dictionary = {"kind": str(population_entry.get("content_kind", "")), "source_poi_id": str(candidate.get("poi_instance_id", ""))}
				if population_request.kind == "camp":
					var guard_count: int = 0
					for camp_entry: Dictionary in resolver.get_weighted_entries(role, "camps"):
						var definition: Dictionary = _find_camp_definition(config, str(camp_entry.get("camp_id", "")))
						guard_count = maxi(guard_count, int(definition.get("guard_count_max", 1)))
					population_request["guard_cells"] = range(guard_count)
				if POI_POPULATION_CONTRACT.reserve(population.duplicate(true), population_request, map_data, population_limits):
					population_entries.append(population_entry)
			var selection: Dictionary = _pick_four_region_room_content_selection(
				role,
				population_entries,
				resolver,
				resolver.get_remaining_value_budget(role, "reward_value_budget"),
				planned_counts,
				camp_minimum_count,
				minimum_camp_plan_value_cost,
				room_candidates.size() - candidate_index - 1,
				rng
			)
			if selection.is_empty():
				# 当前 POI 的人口额度可能耗尽，其他候选房间仍有独立额度。
				continue
			var entry: Dictionary = selection.get("room_entry", {}) as Dictionary
			var content_entry: Dictionary = selection.get("content_entry", {}) as Dictionary
			var content_kind: String = str(entry.get("content_kind", ""))
			var section_name: String = _room_content_section_name(content_kind)
			var value_cost: int = int(selection.get("total_value_cost", 0))
			var poi_instance_id: String = str(candidate.get("poi_instance_id", ""))
			var room_index: int = int(candidate.get("room_index", -1))
			var plan: Dictionary = {
				"plan_id": "%s:room_content:%d" % [poi_instance_id, room_index],
				"content_kind": content_kind,
				"anchor_cell": candidate.get("cell", Vector2i.ZERO),
				"room_kind": str(candidate.get("room_kind", "")),
				"room_index": room_index,
				"room_rect": candidate.get("room_rect", Rect2i()),
				"poi_instance_id": poi_instance_id,
				"region_index": int(candidate.get("region_index", -1)),
				"region_role": role,
				"room_content_value_cost": maxi(int(entry.get("value_cost", 1)), 1),
				"reward_budget_cost": value_cost,
			}
			match section_name:
				"monster_sites":
					plan["template_id"] = str(content_entry.get("spawn_template_id", ""))
				"nests":
					plan["template_id"] = str(content_entry.get("nest_template_id", ""))
				"camps":
					var camp_id: String = str(content_entry.get("camp_id", ""))
					plan["template_id"] = camp_id
					plan["camp_id"] = camp_id
					plan["content_value_cost"] = maxi(
						int(content_entry.get("value_cost", 1)),
						1
					)
			var poi_index: int = int(candidate.get("poi_index", -1))
			var population_request: Dictionary = {"kind": content_kind, "source_poi_id": poi_instance_id}
			if content_kind == "camp":
				var definition: Dictionary = _find_camp_definition(config, str(plan.get("camp_id", "")))
				population_request["guard_cells"] = range(int(definition.get("guard_count_max", 1)))
			if not POI_POPULATION_CONTRACT.reserve(population, population_request, map_data, population_limits):
				continue
			if poi_index >= 0 and poi_index < map_data.poi_instances.size():
				var poi_instance: Dictionary = map_data.poi_instances[poi_index]
				var plans: Array = poi_instance.get("room_content_plans", []) as Array
				plans.append(plan)
				poi_instance["room_content_plans"] = plans
				map_data.poi_instances[poi_index] = poi_instance
			if not resolver.try_spend_value_budget(role, "reward_value_budget", value_cost):
				return [_four_region_issue(
					"content_budget_exhausted",
					"region_generation.content_profiles.reward_value_budget",
					role,
					"房间内容生成后无法提交 reward value budget"
				)]
			planned_counts[section_name] = int(planned_counts.get(section_name, 0)) + 1
			placed_count += 1
		if placed_count < minimum_count:
			return [_four_region_issue(
				"content_minimum_not_met",
				"region_generation.content_profiles.room_contents",
				role,
				"房间内容数量低于 minimum_count：%d < %d" % [placed_count, minimum_count]
			)]
	return []


func _pick_four_region_room_content_selection(
	role: String,
	room_entries: Array[Dictionary],
	resolver: WdcRegionContentResolver,
	remaining_budget: int,
	planned_counts: Dictionary,
	camp_minimum_count: int,
	minimum_camp_plan_value_cost: int,
	remaining_room_slots_after_selection: int,
	rng: RandomNumberGenerator
) -> Dictionary:
	var eligible_room_entries: Array[Dictionary] = []
	for room_entry: Dictionary in room_entries:
		var content_kind: String = str(room_entry.get("content_kind", ""))
		var section_name: String = _room_content_section_name(content_kind)
		if section_name.is_empty():
			continue
		var section: Dictionary = resolver.get_section_for_role(role, section_name)
		var section_target: int = maxi(int(section.get("target_count", 0)), 0)
		if int(planned_counts.get(section_name, 0)) >= section_target:
			continue
		var room_value_cost: int = maxi(int(room_entry.get("value_cost", 1)), 1)
		var projected_camp_count: int = int(planned_counts.get("camps", 0))
		if section_name == "camps":
			projected_camp_count += 1
		var remaining_camp_minimum: int = maxi(
			camp_minimum_count - projected_camp_count,
			0
		)
		if remaining_room_slots_after_selection < remaining_camp_minimum:
			continue
		if remaining_camp_minimum > 0 and minimum_camp_plan_value_cost <= 0:
			continue
		var reserved_camp_value: int = remaining_camp_minimum * minimum_camp_plan_value_cost
		if room_value_cost + reserved_camp_value > remaining_budget:
			continue
		var content_entries: Array[Dictionary] = resolver.get_weighted_entries(role, section_name)
		if section_name == "camps":
			content_entries = resolver.filter_entries_by_value_budget(
				role,
				section_name,
				remaining_budget - room_value_cost - reserved_camp_value,
				"value_cost"
			)
		if content_entries.is_empty():
			continue
		eligible_room_entries.append(room_entry)
	if eligible_room_entries.is_empty():
		return {}
	var room_entry: Dictionary = resolver.pick_weighted_from_entries(eligible_room_entries, rng)
	var content_kind: String = str(room_entry.get("content_kind", ""))
	var section_name: String = _room_content_section_name(content_kind)
	var content_entries: Array[Dictionary] = resolver.get_weighted_entries(role, section_name)
	var room_value_cost: int = maxi(int(room_entry.get("value_cost", 1)), 1)
	if section_name == "camps":
		var remaining_camp_minimum: int = maxi(
			camp_minimum_count - int(planned_counts.get("camps", 0)) - 1,
			0
		)
		content_entries = resolver.filter_entries_by_value_budget(
			role,
			section_name,
			remaining_budget
			- room_value_cost
			- remaining_camp_minimum * minimum_camp_plan_value_cost,
			"value_cost"
		)
	var content_entry: Dictionary = resolver.pick_weighted_from_entries(content_entries, rng)
	if content_entry.is_empty():
		return {}
	var total_value_cost: int = room_value_cost
	if section_name == "camps":
		total_value_cost += maxi(int(content_entry.get("value_cost", 1)), 1)
	return {
		"room_entry": room_entry,
		"content_entry": content_entry,
		"total_value_cost": total_value_cost,
	}


func _room_content_section_name(content_kind: String) -> String:
	match content_kind:
		"monster_pack":
			return "monster_sites"
		"nest":
			return "nests"
		"camp":
			return "camps"
	return ""


func _minimum_four_region_entry_value_cost(entries: Array[Dictionary]) -> int:
	var minimum_cost: int = -1
	for entry: Dictionary in entries:
		var value_cost: int = maxi(int(entry.get("value_cost", 1)), 1)
		if minimum_cost < 0 or value_cost < minimum_cost:
			minimum_cost = value_cost
	return minimum_cost


func _minimum_four_region_camp_plan_value_cost(
	room_entries: Array[Dictionary],
	camp_entries: Array[Dictionary]
) -> int:
	var minimum_room_cost: int = -1
	for room_entry: Dictionary in room_entries:
		if str(room_entry.get("content_kind", "")) != "camp":
			continue
		var room_cost: int = maxi(int(room_entry.get("value_cost", 1)), 1)
		if minimum_room_cost < 0 or room_cost < minimum_room_cost:
			minimum_room_cost = room_cost
	var minimum_camp_cost: int = _minimum_four_region_entry_value_cost(camp_entries)
	if minimum_room_cost <= 0 or minimum_camp_cost <= 0:
		return -1
	return minimum_room_cost + minimum_camp_cost


func _collect_room_content_candidates(
	map_data: WdcMapGenerationTypes.MapData,
	resolver: WdcRegionContentResolver,
	role: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for poi_index: int in range(map_data.poi_instances.size()):
		var instance: Dictionary = map_data.poi_instances[poi_index]
		if str(instance.get("layout_kind", "")) == "authored_rooms":
			continue
		var instance_footprint: Array[Vector2i] = _cells_from_dictionary_array(
			instance.get("footprint_cells", [])
		)
		var instance_region: Dictionary = resolver.resolve_footprint_for_role(
			instance_footprint,
			role
		)
		if not bool(instance_region.get("valid", false)):
			continue
		var main_room: Rect2i = _rect_from_dictionary(instance.get("main_room", {}))
		var main_room_region: Dictionary = resolver.resolve_footprint_for_role(
			_rect_cells(main_room),
			role
		)
		if main_room.size != Vector2i.ZERO and bool(main_room_region.get("valid", false)):
			result.append({
				"poi_index": poi_index,
				"poi_instance_id": str(instance.get("instance_id", "")),
				"room_index": 0,
				"room_kind": "main",
				"cell": _rect_center_cell(main_room),
				"room_rect": main_room,
				"region_index": int(main_room_region.get("region_index", -1)),
			})
		var sub_rooms_value: Variant = instance.get("sub_rooms", [])
		if sub_rooms_value is Array:
			for sub_index: int in range((sub_rooms_value as Array).size()):
				var sub_room: Rect2i = _rect_from_dictionary((sub_rooms_value as Array)[sub_index])
				if sub_room.size == Vector2i.ZERO:
					continue
				var sub_room_region: Dictionary = resolver.resolve_footprint_for_role(
					_rect_cells(sub_room),
					role
				)
				if not bool(sub_room_region.get("valid", false)):
					continue
				result.append({
					"poi_index": poi_index,
					"poi_instance_id": str(instance.get("instance_id", "")),
					"room_index": sub_index + 1,
					"room_kind": "sub",
					"cell": _rect_center_cell(sub_room),
					"room_rect": sub_room,
					"region_index": int(sub_room_region.get("region_index", -1)),
				})
	return result


func _generate_four_region_traps(
	map_data: WdcMapGenerationTypes.MapData,
	resolver: WdcRegionContentResolver,
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	map_data.trap_sites.clear()
	for role: String in WdcMapGenerationTypes.REGION_ROLE_ORDER:
		var section: Dictionary = resolver.get_section_for_role(role, "traps")
		var target_count: int = maxi(int(section.get("target_count", 0)), 0)
		var minimum_count: int = clampi(int(section.get("minimum_count", 0)), 0, target_count)
		if target_count <= 0:
			continue
		var placed_count: int = resolver.get_reserved_count(role, "traps")
		var failed_rolls: int = 0
		while placed_count < target_count and failed_rolls < target_count * 32 + 32:
			var entry: Dictionary = resolver.pick_weighted_entry(role, "traps", rng)
			if entry.is_empty():
				break
			var trap_kind: String = str(entry.get("trap_kind", ""))
			var placement: Dictionary = _try_place_four_region_trap(
				map_data,
				resolver,
				role,
				trap_kind,
				placed_count,
				rng
			)
			if placement.is_empty():
				failed_rolls += 1
				continue
			map_data.trap_sites.append(placement)
			placed_count += 1
		if placed_count < minimum_count:
			return [_four_region_issue(
				"content_minimum_not_met",
				"region_generation.content_profiles.traps",
				role,
				"陷阱数量低于 minimum_count：%d < %d" % [placed_count, minimum_count]
			)]
	return []


func _try_place_four_region_trap(
	map_data: WdcMapGenerationTypes.MapData,
	resolver: WdcRegionContentResolver,
	role: String,
	trap_kind: String,
	ordinal: int,
	rng: RandomNumberGenerator
) -> Dictionary:
	var require_wall: bool = trap_kind in ["arrow_slit", "explosive_ore_chain", "mimic_ore"]
	var candidates: Array[Vector2i] = _collect_region_candidate_cells(
		map_data,
		resolver,
		role,
		require_wall,
		false
	)
	_shuffle_vector2i_array(candidates, rng)
	for candidate: Vector2i in candidates:
		var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(candidate.x, candidate.y)
		if (
			cell == null
			or cell.has_mineral
			or cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE
		):
			continue
		var site: Dictionary = {
			"instance_id": "%s:trap:%s:%03d" % [role, trap_kind, ordinal],
			"trap_kind": trap_kind,
			"cell": _vector2i_to_dict(candidate),
			"metadata": {},
			"region_index": int(resolver.resolve_cell(candidate).get("region_index", -1)),
			"region_role": role,
		}
		match trap_kind:
			"spike":
				if cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR:
					continue
				cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.SPIKE
				site["cells"] = [_vector2i_to_dict(candidate)]
			"pressure_plate":
				if cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR:
					continue
				cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.PRESSURE_PLATE
			"arrow_slit":
				if cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
					continue
				var facing: Vector2i = _resolve_arrow_slit_facing(map_data, candidate)
				if facing == Vector2i.ZERO:
					continue
				cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.ARROW_SLIT
				site["metadata"] = {"facing_x": facing.x, "facing_y": facing.y}
			"explosive_ore_chain":
				var chain: Array[Vector2i] = _try_grow_four_region_explosive_chain(
					map_data,
					candidate,
					resolver,
					role
				)
				if chain.is_empty():
					continue
				var nodes: Array[Dictionary] = []
				for chain_cell: Vector2i in chain:
					var chain_data: WdcMapGenerationTypes.CellData = map_data.get_cell(
						chain_cell.x,
						chain_cell.y
					)
					chain_data.special_block_type = WdcMapGenerationTypes.SpecialBlockType.EXPLOSIVE_ORE
					chain_data.has_mineral = false
					nodes.append(_vector2i_to_dict(chain_cell))
				site["nodes"] = nodes
			"mimic_ore":
				if cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
					continue
				cell.has_mineral = true
				site["metadata"] = {"variant": "mimic_monster", "monster_id": "ghoul"}
			_:
				continue
		var resolved_footprint: Dictionary = resolver.resolve_footprint_for_role(
			_collect_trap_region_cells(site),
			role
		)
		if not bool(resolved_footprint.get("valid", false)):
			continue
		site["region_index"] = int(resolved_footprint.get("region_index", -1))
		site["region_role"] = str(resolved_footprint.get("role", ""))
		return site
	return {}


func _try_grow_four_region_explosive_chain(
	map_data: WdcMapGenerationTypes.MapData,
	seed_cell: Vector2i,
	resolver: WdcRegionContentResolver,
	role: String
) -> Array[Vector2i]:
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var chain: Array[Vector2i] = []
		var valid: bool = true
		for step: int in range(TRAP_EXPLOSIVE_ORE_CHAIN_LENGTH):
			var candidate: Vector2i = seed_cell + direction * step
			if (
				not map_data.is_in_bounds(candidate.x, candidate.y)
				or not resolver.is_cell_in_role(candidate, role)
			):
				valid = false
				break
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(candidate.x, candidate.y)
			if (
				cell == null
				or cell.cell_type != WdcMapGenerationTypes.CellType.WALL
				or cell.has_mineral
				or cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE
				or cell.is_poi_protected
			):
				valid = false
				break
			chain.append(candidate)
		if valid:
			return chain
	return []


func _generate_four_region_population_sites(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	resolver: WdcRegionContentResolver,
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	map_data.monster_sites.clear()
	map_data.camp_encounters.clear()
	var authored_issues: Array[Dictionary] = _materialize_authored_content(map_data, config, resolver)
	if not authored_issues.is_empty():
		return authored_issues
	var materialization_issues: Array[Dictionary] = _materialize_four_region_room_contents(
		map_data,
		config,
		resolver
	)
	if not materialization_issues.is_empty():
		return materialization_issues
	var isolated_templates: Array[Dictionary] = _extract_dictionary_array(
		config.get_meta("isolated_spawn_templates", [])
	)
	var nest_templates: Array[Dictionary] = _extract_dictionary_array(
		config.get_meta("nest_templates", [])
	)
	var population_limits: Dictionary = config.get_meta("poi_population_limits", {})
	for role: String in WdcMapGenerationTypes.REGION_ROLE_ORDER:
		var resolved_region: Dictionary = resolver.resolve_role(role)
		if not bool(resolved_region.get("valid", false)):
			return [resolved_region.get("issue", {}) as Dictionary]
		var monster_issue: Dictionary = _generate_four_region_monster_section(
			map_data,
			resolver,
			rng,
			role,
			"monster_sites",
			isolated_templates,
			false,
			population_limits
		)
		if not monster_issue.is_empty():
			return [monster_issue]
		var nest_issue: Dictionary = _generate_four_region_monster_section(
			map_data,
			resolver,
			rng,
			role,
			"nests",
			nest_templates,
			true,
			population_limits
		)
		if not nest_issue.is_empty():
			return [nest_issue]
		var camp_issue: Dictionary = _generate_four_region_camps(
			map_data,
			config,
			resolver,
			rng,
			role
		)
		if not camp_issue.is_empty():
			return [camp_issue]
	return []


## 唯一实体化步骤消费已扣账的图纸计划，不再次选点或随机填房。
func _materialize_authored_content(map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig, resolver: WdcRegionContentResolver) -> Array[Dictionary]:
	map_data.furnishing_sites.clear()
	for poi: Dictionary in map_data.poi_instances:
		if str(poi.get("layout_kind", "")) != "authored_rooms":
			continue
		poi["torch_sites"] = []
		for plan: Dictionary in poi.get("content_plans", []):
			var position: Vector2i = _cell_from_variant(plan.get("cell", null))
			var role: String = str(poi.region_role)
			var kind: String = str(plan.kind)
			var content_id: String = str(plan.content_id)
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(position.x, position.y)
			var footprint: Array[Vector2i] = _cells_from_dictionary_array(plan.get("placement_footprint", []))
			if footprint.is_empty():
				footprint.append(position)
			if cell == null or not bool(resolver.resolve_footprint_for_role(footprint, role).get("valid", false)):
				return [AUTHORED_CONTENT_ALLOCATOR._issue(plan, "invalid_slot_footprint", "槽位实际占地跨区或超出地图")]
			var site: Dictionary = {"site_id": str(plan.plan_id), "cell": position,
				"source_site_id": str(plan.plan_id), "source_poi_id": str(poi.instance_id),
				"source_poi_instance_id": str(poi.instance_id), "source_room_content_plan_id": str(plan.plan_id),
				"room_instance_id": str(plan.get("room_instance_id", "")), "slot_id": str(plan.get("slot_id", "")),
				"region_role": role, "region_index": int(poi.region_index), "required": bool(plan.get("required", false)),
				"rotation": int(plan.get("rotation", 0)), "layout_kind": "authored_rooms"}
			match kind:
				"prop":
					site["prop_id"] = content_id
					site["footprint_cells"] = _vector2i_array_to_dict_array(footprint)
					map_data.furnishing_sites.append(site)
				"torch":
					(poi.torch_sites as Array).append(_vector2i_to_dict(position))
				"monster_pack", "nest":
					var templates: Array[Dictionary] = _extract_dictionary_array(config.get_meta(
						"nest_templates" if kind == "nest" else "isolated_spawn_templates", []))
					var template: Dictionary = _find_template_by_id(templates, content_id)
					if template.is_empty():
						return [AUTHORED_CONTENT_ALLOCATOR._issue(plan, "unknown_slot_content", "当前地图没有声明怪物或巢穴模板")]
					site["site_kind"] = "nest" if kind == "nest" else "isolated"
					site["site_source"] = "poi_room"
					site["population_domain"] = "poi_nest"
					site["template_id"] = content_id
					site["monster_id"] = str(template.get("monster_id", ""))
					if kind == "nest":
						for field: String in ["nest_unit_id", "loot_table_id", "activation_radius_m", "spawn_interval_sec", "max_alive_children", "max_hit_points"]:
							site[field] = template.get(field)
					map_data.monster_sites.append(site)
					plan["materialized_site_id"] = str(plan.plan_id)
				"camp":
					var definition: Dictionary = _find_camp_definition(config, content_id)
					var guards: Array[Vector2i] = _cells_from_dictionary_array(plan.get("guard_cells", []))
					if definition.is_empty() or guards.size() < int(definition.get("guard_count_min", 1)) or guards.size() > int(definition.get("guard_count_max", 1)):
						return [AUTHORED_CONTENT_ALLOCATOR._issue(plan, "invalid_camp_guard_slots", "营地守卫具名位置数量不符合当前营地定义")]
					var guard_sites: Array[Dictionary] = []
					var camp_rng: RandomNumberGenerator = RandomNumberGenerator.new()
					camp_rng.seed = maxi(abs(str(plan.plan_id).hash()), 1)
					for guard_cell: Vector2i in guards:
						var guard_entry: Dictionary = _pick_weighted_entry(definition.get("guard_entries", []), camp_rng)
						var template_id: String = str(guard_entry.get("spawn_template_id", ""))
						var monster_id: String = str(guard_entry.get("monster_id", ""))
						if monster_id.is_empty():
							monster_id = str(_find_template_by_id(_extract_dictionary_array(config.get_meta("isolated_spawn_templates", [])), template_id).get("monster_id", ""))
						var guard_data: WdcMapGenerationTypes.CellData = map_data.get_cell(guard_cell.x, guard_cell.y)
						if monster_id.is_empty() or guard_data == null or guard_data.cell_type != WdcMapGenerationTypes.CellType.FLOOR or not resolver.is_cell_in_role(guard_cell, role):
							return [AUTHORED_CONTENT_ALLOCATOR._issue(plan, "invalid_camp_guard_slots", "守卫位置或真实怪物引用无效")]
						guard_sites.append({"cell": _vector2i_to_dict(guard_cell), "monster_id": monster_id, "template_id": template_id})
					site["encounter_id"] = str(plan.plan_id) + ":camp"
					site["camp_id"] = content_id
					site["poi_template_id"] = str(poi.template_id)
					site["chest_cell"] = _vector2i_to_dict(position)
					site["guard_sites"] = guard_sites
					site["loot_container"] = _normalize_camp_loot_container(definition.get("loot_container", {}))
					site["locked_prompt_text"] = str(definition.get("locked_prompt_text", "需要击败房间中的所有怪物"))
					site["source_room_key"] = "%s:%s" % [poi.instance_id, site.room_instance_id]
					site["reward_budget_cost"] = int(plan.budget_cost) - int(plan.room_content_value_cost)
					map_data.camp_encounters.append(site)
					plan["materialized_encounter_id"] = str(site.encounter_id)
				"mineral":
					var template: Dictionary = _find_template_by_id(config.mineral_cluster_types, content_id)
					if template.is_empty():
						return [AUTHORED_CONTENT_ALLOCATOR._issue(plan, "unknown_slot_content", "当前地图没有该矿物模板")]
					for mineral_cell: Vector2i in footprint:
						var mineral_data: WdcMapGenerationTypes.CellData = map_data.get_cell(mineral_cell.x, mineral_cell.y)
						if mineral_data.special_block_type == WdcMapGenerationTypes.SpecialBlockType.POI_WALL:
							mineral_data.special_block_type = WdcMapGenerationTypes.SpecialBlockType.NONE
						if not _place_cluster_cell(map_data, mineral_cell, template):
							return [AUTHORED_CONTENT_ALLOCATOR._issue(plan, "invalid_mineral_slot", "固定矿物槽占地不可写入")]
					site.erase("region_role")
					site.erase("region_index")
					site["cluster_type_id"] = content_id
					site["cells"] = _vector2i_array_to_dict_array(footprint)
					site["value_cost"] = int(plan.budget_cost)
					map_data.mineral_sites.append(site)
				"trap":
					site["instance_id"] = str(plan.plan_id)
					site["trap_kind"] = content_id
					site["metadata"] = {}
					match content_id:
						"spike":
							cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.SPIKE
							site["cells"] = [_vector2i_to_dict(position)]
						"pressure_plate":
							cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.PRESSURE_PLATE
						"arrow_slit":
							var facing: Vector2i = _resolve_arrow_slit_facing(map_data, position)
							if facing == Vector2i.ZERO:
								return [AUTHORED_CONTENT_ALLOCATOR._issue(plan, "invalid_arrow_slot", "箭孔需要朝向开放地板")]
							cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.ARROW_SLIT
							site["metadata"] = {"facing_x": facing.x, "facing_y": facing.y}
						"mimic_ore":
							cell.has_mineral = true
							site["metadata"] = {"variant": "mimic_monster", "monster_id": "ghoul"}
						"explosive_ore_chain":
							for chain_cell: Vector2i in footprint:
								map_data.get_cell(chain_cell.x, chain_cell.y).special_block_type = WdcMapGenerationTypes.SpecialBlockType.EXPLOSIVE_ORE
							site["nodes"] = _vector2i_array_to_dict_array(footprint)
						_:
							return [AUTHORED_CONTENT_ALLOCATOR._issue(plan, "unsupported_trap_slot", "没有该陷阱实体化规则")]
					map_data.trap_sites.append(site)
	return []


func _materialize_four_region_room_contents(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	resolver: WdcRegionContentResolver
) -> Array[Dictionary]:
	var materialized_plan_ids: Dictionary = {}
	var isolated_templates: Array[Dictionary] = _extract_dictionary_array(
		config.get_meta("isolated_spawn_templates", [])
	)
	var nest_templates: Array[Dictionary] = _extract_dictionary_array(
		config.get_meta("nest_templates", [])
	)
	for poi_index: int in range(map_data.poi_instances.size()):
		var poi_instance: Dictionary = map_data.poi_instances[poi_index]
		var plans: Array = poi_instance.get("room_content_plans", []) as Array
		for plan_index: int in range(plans.size()):
			var plan_value: Variant = plans[plan_index]
			if not (plan_value is Dictionary):
				return [_four_region_issue(
					"room_content_materialization_failed",
					"poi_instances.room_content_plans[%d]" % plan_index,
					str(poi_instance.get("region_role", "")),
					"room content plan 必须是对象"
				)]
			var plan: Dictionary = plan_value as Dictionary
			var plan_id: String = str(plan.get("plan_id", ""))
			if plan_id.is_empty() or materialized_plan_ids.has(plan_id):
				return [_four_region_issue(
					"room_content_materialization_failed",
					"poi_instances.room_content_plans.plan_id",
					str(plan.get("region_role", "")),
					"room content plan identity 不能为空且必须唯一"
				)]
			materialized_plan_ids[plan_id] = true
			var anchor_cell: Vector2i = _cell_from_variant(plan.get("anchor_cell", null))
			var room_rect: Rect2i = _rect_from_dictionary(plan.get("room_rect", {}))
			var resolved_room: Dictionary = resolver.resolve_footprint(
				_rect_cells(room_rect)
			)
			if not bool(resolved_room.get("valid", false)):
				return [_four_region_issue(
					"room_content_materialization_failed",
					"poi_instances.room_content_plans.room_rect",
					str(plan.get("region_role", "")),
					"room content 必须通过 RegionPlan 解析到单一区域"
				)]
			var role: String = str(resolved_room.get("role", ""))
			var region_index: int = int(resolved_room.get("region_index", -1))
			if not resolver.is_cell_in_role(anchor_cell, role):
				return [_four_region_issue(
					"room_content_materialization_failed",
					"poi_instances.room_content_plans.anchor_cell",
					role,
					"room content anchor 必须位于所属区域"
				)]
			plan["region_index"] = region_index
			plan["region_role"] = role
			var content_kind: String = str(plan.get("content_kind", ""))
			var template_id: String = str(plan.get("template_id", ""))
			match content_kind:
				"monster_pack", "nest":
					var is_nest: bool = content_kind == "nest"
					var templates: Array[Dictionary] = nest_templates if is_nest else isolated_templates
					var template: Dictionary = _find_template_by_id(templates, template_id)
					if template.is_empty():
						return [_four_region_issue(
							"room_content_materialization_failed",
							"poi_instances.room_content_plans.template_id",
							role,
							"room content 引用的怪物模板不存在：%s" % template_id
						)]
					var site: Dictionary = {
						"site_id": plan_id,
						"site_kind": "nest" if is_nest else "isolated",
						"cell": anchor_cell,
						"template_id": template_id,
						"monster_id": str(template.get("monster_id", "")),
						"room_kind": str(plan.get("room_kind", "")),
						"region_index": region_index,
						"region_role": role,
						"site_source": "poi_room",
						"source_room_content_plan_id": plan_id,
						"source_poi_instance_id": str(plan.get("poi_instance_id", "")),
					}
					if is_nest:
						for field_name: String in [
							"nest_unit_id",
							"loot_table_id",
							"activation_radius_m",
							"spawn_interval_sec",
							"max_alive_children",
							"max_hit_points",
						]:
							site[field_name] = template.get(field_name)
					map_data.monster_sites.append(site)
					plan["materialized_site_id"] = plan_id
				"camp":
					var camp_id: String = str(plan.get("camp_id", template_id))
					var definition: Dictionary = _find_camp_definition(config, camp_id)
					if definition.is_empty():
						return [_four_region_issue(
							"room_content_materialization_failed",
							"poi_instances.room_content_plans.camp_id",
							role,
							"room content 引用的营地定义不存在：%s" % camp_id
						)]
					var camp_plan: Dictionary = {
						"encounter_id": "%s:camp" % plan_id,
						"room_rect": room_rect,
						"anchor_cell": anchor_cell,
						"room_index": int(plan.get("room_index", -1)),
						"room_kind": str(plan.get("room_kind", "")),
						"layer_id": "",
					}
					var camp_rng: RandomNumberGenerator = RandomNumberGenerator.new()
					camp_rng.seed = maxi(abs(plan_id.hash()), 1)
					_apply_locked_treasure_camp_plan(
						camp_plan,
						room_rect,
						[],
						{},
						definition,
						config,
						camp_rng
					)
					if bool(camp_plan.get("invalid", false)):
						return [_four_region_issue(
							"room_content_materialization_failed",
							"poi_instances.room_content_plans",
							role,
							"room content 营地无法在目标房间内生成"
						)]
					_append_camp_encounter(
						map_data,
						camp_plan,
						str(poi_instance.get("template_id", ""))
					)
					var camp: Dictionary = map_data.camp_encounters.back()
					var camp_region: Dictionary = resolver.resolve_footprint_for_role(
						_collect_camp_region_cells(camp),
						role
					)
					if not bool(camp_region.get("valid", false)):
						map_data.camp_encounters.pop_back()
						return [_four_region_issue(
							"room_content_materialization_failed",
							"poi_instances.room_content_plans.camp",
							role,
							"room content 营地 footprint 不得跨区"
						)]
					camp.erase("layer_id")
					camp["region_index"] = region_index
					camp["region_role"] = role
					camp["camp_id"] = camp_id
					camp["reward_budget_cost"] = maxi(
						int(plan.get("content_value_cost", 1)),
						1
					)
					camp["source_room_content_plan_id"] = plan_id
					camp["source_room_key"] = _four_region_room_key(
						str(plan.get("poi_instance_id", "")),
						int(plan.get("room_index", -1))
					)
					map_data.camp_encounters[map_data.camp_encounters.size() - 1] = camp
					plan["materialized_encounter_id"] = str(camp.get("encounter_id", ""))
				_:
					return [_four_region_issue(
						"room_content_materialization_failed",
						"poi_instances.room_content_plans.content_kind",
						role,
						"不支持的 room content kind：%s" % content_kind
					)]
			plans[plan_index] = plan
		poi_instance["room_content_plans"] = plans
		map_data.poi_instances[poi_index] = poi_instance
	return []


func _generate_four_region_monster_section(
	map_data: WdcMapGenerationTypes.MapData,
	resolver: WdcRegionContentResolver,
	rng: RandomNumberGenerator,
	role: String,
	section_name: String,
	templates: Array[Dictionary],
	is_nest: bool,
	population_limits: Dictionary = {}
) -> Dictionary:
	var population: Dictionary = POI_POPULATION_CONTRACT.collect_usage(map_data)
	var section: Dictionary = resolver.get_section_for_role(role, section_name)
	var target_count: int = maxi(int(section.get("target_count", 0)), 0)
	var minimum_count: int = clampi(int(section.get("minimum_count", 0)), 0, target_count)
	if target_count <= 0:
		return {}
	var entries: Array[Dictionary] = resolver.get_weighted_entries(role, section_name)
	var candidates: Array[Vector2i] = _collect_region_candidate_cells(
		map_data,
		resolver,
		role,
		false,
		true
	)
	_shuffle_vector2i_array(candidates, rng)
	var expected_site_kind: String = "nest" if is_nest else "isolated"
	var occupied_cells: Dictionary = {}
	var placed_count: int = 0
	for existing_site: Dictionary in map_data.monster_sites:
		var existing_cell: Vector2i = _site_cell(existing_site)
		occupied_cells[_key(existing_cell.x, existing_cell.y)] = true
		if (
			resolver.is_cell_in_role(existing_cell, role)
			and str(existing_site.get("site_kind", "")) == expected_site_kind
		):
			placed_count += 1
	for candidate: Vector2i in candidates:
		if placed_count >= target_count:
			break
		if occupied_cells.has(_key(candidate.x, candidate.y)):
			continue
		if is_nest and not POI_POPULATION_CONTRACT.reserve(population.duplicate(true), {"kind": "nest"}, map_data, population_limits):
			break
		var entry: Dictionary = resolver.pick_weighted_from_entries(entries, rng)
		if entry.is_empty():
			break
		var id_key: String = "nest_template_id" if is_nest else "spawn_template_id"
		var template_id: String = str(entry.get(id_key, ""))
		var template: Dictionary = _find_template_by_id(templates, template_id)
		if template.is_empty():
			continue
		var resolved_site: Dictionary = resolver.resolve_cell(candidate)
		if not bool(resolved_site.get("valid", false)):
			continue
		var site: Dictionary = {
			"site_kind": "nest" if is_nest else "isolated",
			"cell": candidate,
			"template_id": template_id,
			"monster_id": str(template.get("monster_id", "")),
			"region_index": int(resolved_site.get("region_index", -1)),
			"region_role": str(resolved_site.get("role", "")),
			"site_source": "ambient",
			"population_domain": "poi_nest" if is_nest else "ordinary",
		}
		if is_nest:
			for field_name: String in [
				"nest_unit_id",
				"loot_table_id",
				"activation_radius_m",
				"spawn_interval_sec",
				"max_alive_children",
				"max_hit_points",
			]:
				site[field_name] = template.get(field_name)
		map_data.monster_sites.append(site)
		if is_nest:
			POI_POPULATION_CONTRACT.reserve(population, {"kind": "nest"}, map_data, population_limits)
		occupied_cells[_key(candidate.x, candidate.y)] = true
		placed_count += 1
	if placed_count < minimum_count:
		return _four_region_issue(
			"content_minimum_not_met",
			"region_generation.content_profiles.%s" % section_name,
			role,
			"%s 数量低于 minimum_count：%d < %d" % [section_name, placed_count, minimum_count]
		)
	return {}


func _generate_four_region_camps(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	resolver: WdcRegionContentResolver,
	rng: RandomNumberGenerator,
	role: String
) -> Dictionary:
	var population_limits: Dictionary = config.get_meta("poi_population_limits", {})
	var population: Dictionary = POI_POPULATION_CONTRACT.collect_usage(map_data)
	var section: Dictionary = resolver.get_section_for_role(role, "camps")
	var target_count: int = maxi(int(section.get("target_count", 0)), 0)
	var minimum_count: int = clampi(int(section.get("minimum_count", 0)), 0, target_count)
	if target_count <= 0:
		return {}
	var remaining_budget: int = resolver.get_remaining_value_budget(role, "reward_value_budget")
	var candidates: Array[Dictionary] = _collect_room_content_candidates(map_data, resolver, role)
	_shuffle_dictionary_array(candidates, rng)
	var reserved_room_keys: Dictionary = _collect_four_region_reserved_room_keys(
		map_data,
		resolver,
		role
	)
	var placed_count: int = 0
	for existing_camp: Dictionary in map_data.camp_encounters:
		if resolver.is_cell_in_role(
			_cell_from_variant(existing_camp.get("chest_cell", null)),
			role
		):
			placed_count += 1
	for candidate: Dictionary in candidates:
		if placed_count >= target_count:
			break
		var room_key: String = _four_region_room_key(
			str(candidate.get("poi_instance_id", "")),
			int(candidate.get("room_index", -1))
		)
		if reserved_room_keys.has(room_key):
			continue
		var entry: Dictionary = resolver.pick_weighted_entry(
			role,
			"camps",
			rng,
			remaining_budget,
			"value_cost"
		)
		if entry.is_empty():
			break
		var camp_id: String = str(entry.get("camp_id", ""))
		var definition: Dictionary = _find_camp_definition(config, camp_id)
		if definition.is_empty():
			continue
		var plan: Dictionary = {
			"encounter_id": "%s:camp:%03d" % [role, placed_count],
			"room_rect": candidate.get("room_rect", Rect2i()),
			"anchor_cell": candidate.get("cell", Vector2i.ZERO),
			"room_index": int(candidate.get("room_index", -1)),
			"room_kind": str(candidate.get("room_kind", "")),
			"layer_id": "",
		}
		_apply_locked_treasure_camp_plan(
			plan,
			candidate.get("room_rect", Rect2i()),
			[],
			{},
			definition,
			config,
			rng
		)
		if bool(plan.get("invalid", false)):
			continue
		_append_camp_encounter(
			map_data,
			plan,
			str((map_data.poi_instances[int(candidate.get("poi_index", -1))] as Dictionary).get("template_id", ""))
		)
		var camp: Dictionary = map_data.camp_encounters.back()
		var source_poi_id: String = str(candidate.get("poi_instance_id", ""))
		if not POI_POPULATION_CONTRACT.reserve(population.duplicate(true), {"kind": "camp", "source_poi_id": source_poi_id, "guard_cells": camp.get("guard_sites", [])}, map_data, population_limits):
			map_data.camp_encounters.pop_back()
			continue
		var resolved_camp: Dictionary = resolver.resolve_footprint_for_role(
			_collect_camp_region_cells(camp),
			role
		)
		if not bool(resolved_camp.get("valid", false)):
			map_data.camp_encounters.pop_back()
			continue
		camp.erase("layer_id")
		camp["region_index"] = int(resolved_camp.get("region_index", -1))
		camp["region_role"] = str(resolved_camp.get("role", ""))
		camp["camp_id"] = camp_id
		camp["reward_budget_cost"] = maxi(int(entry.get("value_cost", 1)), 1)
		camp["source_room_key"] = room_key
		camp["source_poi_instance_id"] = source_poi_id
		map_data.camp_encounters[map_data.camp_encounters.size() - 1] = camp
		var value_cost: int = maxi(int(entry.get("value_cost", 1)), 1)
		if not resolver.try_spend_value_budget(role, "reward_value_budget", value_cost):
			map_data.camp_encounters.pop_back()
			return _four_region_issue(
				"content_budget_exhausted",
				"region_generation.content_profiles.reward_value_budget",
				role,
				"营地生成后无法提交 reward value budget"
			)
		remaining_budget = resolver.get_remaining_value_budget(role, "reward_value_budget")
		POI_POPULATION_CONTRACT.reserve(population, {"kind": "camp", "source_poi_id": source_poi_id, "guard_cells": camp.get("guard_sites", [])}, map_data, population_limits)
		reserved_room_keys[room_key] = true
		placed_count += 1
	if placed_count < minimum_count:
		return _four_region_issue(
			"content_minimum_not_met",
			"region_generation.content_profiles.camps",
			role,
			"营地数量低于 minimum_count：%d < %d" % [placed_count, minimum_count]
		)
	return {}


func _collect_four_region_reserved_room_keys(
	map_data: WdcMapGenerationTypes.MapData,
	resolver: WdcRegionContentResolver,
	role: String
) -> Dictionary:
	var reserved: Dictionary = {}
	for instance: Dictionary in map_data.poi_instances:
		var footprint: Array[Vector2i] = _cells_from_dictionary_array(
			instance.get("footprint_cells", [])
		)
		if not bool(resolver.resolve_footprint_for_role(footprint, role).get("valid", false)):
			continue
		var instance_id: String = str(instance.get("instance_id", ""))
		for plan_value: Variant in instance.get("room_content_plans", []) as Array:
			if not (plan_value is Dictionary):
				continue
			var plan: Dictionary = plan_value as Dictionary
			reserved[_four_region_room_key(
				instance_id,
				int(plan.get("room_index", -1))
			)] = true
	for camp: Dictionary in map_data.camp_encounters:
		if not resolver.is_cell_in_role(
			_cell_from_variant(camp.get("chest_cell", null)),
			role
		):
			continue
		var source_room_key: String = str(camp.get("source_room_key", ""))
		if not source_room_key.is_empty():
			reserved[source_room_key] = true
	return reserved


func _four_region_room_key(poi_instance_id: String, room_index: int) -> String:
	return "%s:r%d" % [poi_instance_id, room_index]


func _find_camp_definition(
	config: WdcMapGenerationTypes.MapConfig,
	camp_id: String
) -> Dictionary:
	for template: Dictionary in config.poi_templates:
		var content: Dictionary = template.get("content", {}) as Dictionary
		for room_key: String in ["main_room_roll", "sub_room_roll"]:
			var room_roll: Dictionary = content.get(room_key, {}) as Dictionary
			var entries_value: Variant = room_roll.get("camp_entries", [])
			if not (entries_value is Array):
				continue
			for entry_value: Variant in entries_value as Array:
				if entry_value is Dictionary and str((entry_value as Dictionary).get("id", "")) == camp_id:
					return (entry_value as Dictionary).duplicate(true)
	return {}


func _apply_four_region_durability(
	map_data: WdcMapGenerationTypes.MapData,
	resolver: WdcRegionContentResolver
) -> void:
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null or cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
				if cell != null:
					cell.durability_override_max_hit_points = 0
					WdcMapGenerationTileRules.refresh_cell_runtime_state(cell)
				continue
			var wall_kind: String = "ordinary"
			if cell.special_block_type == WdcMapGenerationTypes.SpecialBlockType.POI_WALL:
				wall_kind = "poi"
			elif cell.has_mineral or cell.special_block_type in [
				WdcMapGenerationTypes.SpecialBlockType.RARE_MINERAL,
				WdcMapGenerationTypes.SpecialBlockType.TURQUOISE,
				WdcMapGenerationTypes.SpecialBlockType.AMETHYST,
				WdcMapGenerationTypes.SpecialBlockType.GOLD,
			]:
				wall_kind = "mineral"
			cell.durability_override_max_hit_points = resolver.get_wall_hit_points(
				Vector2i(x, y),
				wall_kind
			)
			WdcMapGenerationTileRules.refresh_cell_runtime_state(cell)
			# 新生成的墙没有损伤：区域 override 抬高上限后，refresh 只夹取当前值，必须补满。
			cell.current_hit_points = cell.max_hit_points


func _generate_four_region_spawn_and_extraction(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	resolver: WdcRegionContentResolver,
	resolved_seed: int,
	attempt_index: int
) -> Array[Dictionary]:
	map_data.player_spawn_points.clear()
	map_data.extraction_sites.clear()
	var spawn_selection: Dictionary = _select_four_region_site_cell(
		map_data,
		resolver,
		config.player_spawn_edge_margin_cells,
		config.player_spawn_clearance_radius_cells,
		config.player_spawn_min_clearance_ratio,
		[],
		0.0,
		"player_spawn",
		resolved_seed,
		attempt_index
	)
	if not bool(spawn_selection.get("success", false)):
		return [_four_region_issue(
			"spawn_placement_failed",
			"map.player_spawn",
			WdcMapGenerationTypes.REGION_ROLE_REGULAR,
			"无法在常规区域生成唯一出生锚点"
		)]
	var spawn_cell: Vector2i = spawn_selection.get("cell", Vector2i(-1, -1))
	map_data.player_spawn_points.append({
		"x": spawn_cell.x,
		"y": spawn_cell.y,
		"site_kind": "player_spawn",
		"region_index": 0,
		"region_role": WdcMapGenerationTypes.REGION_ROLE_REGULAR,
		"fallback_reason": str(spawn_selection.get("fallback_reason", "")),
	})
	var extraction_selection: Dictionary = _select_four_region_site_cell(
		map_data,
		resolver,
		config.extraction_site_edge_margin_cells,
		config.extraction_site_clearance_radius_cells,
		config.extraction_site_min_clearance_ratio,
		[spawn_cell],
		config.extraction_site_min_distance_from_player_spawns_cells,
		"extraction",
		resolved_seed,
		attempt_index
	)
	if not bool(extraction_selection.get("success", false)):
		return [_four_region_issue(
			"extraction_placement_failed",
			"map.extraction_sites",
			WdcMapGenerationTypes.REGION_ROLE_REGULAR,
			"无法在常规区域生成唯一普通撤离点"
		)]
	var extraction_cell: Vector2i = extraction_selection.get("cell", Vector2i(-1, -1))
	map_data.extraction_sites.append({
		"x": extraction_cell.x,
		"y": extraction_cell.y,
		"site_kind": "extraction",
		"extraction_kind": "normal",
		"region_index": 0,
		"region_role": WdcMapGenerationTypes.REGION_ROLE_REGULAR,
		"fallback_reason": str(extraction_selection.get("fallback_reason", "")),
	})
	return []


func _select_four_region_site_cell(
	map_data: WdcMapGenerationTypes.MapData,
	resolver: WdcRegionContentResolver,
	edge_margin: int,
	clearance_radius: int,
	minimum_clearance_ratio: float,
	avoid_cells: Array[Vector2i],
	minimum_avoid_distance: float,
	site_kind: String,
	resolved_seed: int,
	attempt_index: int
) -> Dictionary:
	var regular_resolution: Dictionary = resolver.resolve_role(
		WdcMapGenerationTypes.REGION_ROLE_REGULAR
	)
	if not bool(regular_resolution.get("valid", false)):
		return {
			"success": false,
			"cell": Vector2i(-1, -1),
			"fallback_reason": "",
		}
	var candidates: Array[Dictionary] = []
	var margin: int = maxi(edge_margin, 0)
	var avoid_distance_sq: float = minimum_avoid_distance * minimum_avoid_distance
	for y: int in range(margin, map_data.height - margin):
		for x: int in range(margin, map_data.width - margin):
			var cell_coord: Vector2i = Vector2i(x, y)
			if not resolver.is_cell_in_role(
				cell_coord,
				WdcMapGenerationTypes.REGION_ROLE_REGULAR
			):
				continue
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if (
				cell == null
				or cell.has_mineral
				or cell.is_poi_protected
				or cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE
			):
				continue
			var avoid_ok: bool = true
			for avoid_cell: Vector2i in avoid_cells:
				if cell_coord.distance_squared_to(avoid_cell) < avoid_distance_sq:
					avoid_ok = false
					break
			var clearance_ratio: float = _compute_site_clearance_ratio(
				map_data,
				cell_coord,
				clearance_radius
			)
			candidates.append({
				"cell": cell_coord,
				"is_floor": _is_site_floor_cell(cell),
				"clearance_ratio": clearance_ratio,
				"clearance_ok": clearance_ratio >= minimum_clearance_ratio,
				"avoid_ok": avoid_ok,
				"tie": _stable_four_region_site_tie_breaker(
					cell_coord,
					site_kind,
					resolved_seed,
					attempt_index
				),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var clearance_a: float = float(a.get("clearance_ratio", 0.0))
		var clearance_b: float = float(b.get("clearance_ratio", 0.0))
		if absf(clearance_a - clearance_b) > 0.0001:
			return clearance_a > clearance_b
		return int(a.get("tie", 0)) < int(b.get("tie", 0))
	)
	var passes: Array[Dictionary] = [
		{
			"floor": true,
			"clearance": true,
			"carve": false,
			"fallback_reason": "",
		},
		{
			"floor": true,
			"clearance": false,
			"carve": false,
			"fallback_reason": "relaxed_clearance",
		},
		{
			"floor": false,
			"clearance": false,
			"carve": true,
			"fallback_reason": "carved_regular_cell",
		},
	]
	for pass_config: Dictionary in passes:
		for candidate: Dictionary in candidates:
			if bool(pass_config.get("floor", false)) and not bool(candidate.get("is_floor", false)):
				continue
			if bool(pass_config.get("clearance", false)) and not bool(candidate.get("clearance_ok", false)):
				continue
			if not bool(candidate.get("avoid_ok", false)):
				continue
			var candidate_cell: Vector2i = candidate.get("cell", Vector2i(-1, -1))
			if bool(pass_config.get("carve", false)):
				_carve_site_floor_cell(map_data, candidate_cell)
			return {
				"success": true,
				"cell": candidate_cell,
				"fallback_reason": str(pass_config.get("fallback_reason", "")),
			}
	return {
		"success": false,
		"cell": Vector2i(-1, -1),
		"fallback_reason": "",
	}


func _validate_four_region_artifact(
	map_data: WdcMapGenerationTypes.MapData
) -> Array[Dictionary]:
	var issues: Array[Dictionary] = WdcMapGenerationTypes.validate_map_data_layout_artifacts(
		map_data
	)
	if not issues.is_empty():
		return issues
	var plan: WdcMapGenerationTypes.RegionPlan = map_data.region_plan
	var membership: PackedInt32Array = plan.get_region_index_by_cell_copy()
	var validator: WdcFourRegionLayoutValidator = WdcFourRegionLayoutValidator.new()
	issues.append_array(validator.validate(Vector2i(map_data.width, map_data.height), membership))
	if not issues.is_empty():
		return issues
	var core_instances_by_role: Dictionary = {}
	for role: String in [
		WdcMapGenerationTypes.REGION_ROLE_HIGH_1,
		WdcMapGenerationTypes.REGION_ROLE_HIGH_2,
		WdcMapGenerationTypes.REGION_ROLE_BOSS,
	]:
		var region = plan.try_get_by_role(role)
		var matching_core_count: int = 0
		var identity_match_count: int = 0
		for instance: Dictionary in map_data.poi_instances:
			if str(instance.get("instance_id", "")) == region.core_poi_instance_id:
				identity_match_count += 1
				if (
					not bool(instance.get("is_core", false))
					or str(instance.get("region_role", "")) != role
				):
					issues.append(_four_region_issue(
						"core_poi_identity_mismatch",
						"poi_instances",
						role,
						"RegionPlan core identity 必须解析到所属区域的核心 POI"
					))
			if not bool(instance.get("is_core", false)):
				continue
			if str(instance.get("region_role", "")) != role:
				continue
			matching_core_count += 1
			if str(instance.get("instance_id", "")) != region.core_poi_instance_id:
				issues.append(_four_region_issue(
					"core_poi_identity_mismatch",
					"poi_instances",
					role,
					"核心 POI instance identity 与 RegionPlan 不一致"
				))
			else:
				core_instances_by_role[role] = instance
			if (
				str(instance.get("template_id", "")) != region.core_poi_template_id
				or int(instance.get("region_index", -1)) != region.index
			):
				issues.append(_four_region_issue(
					"core_poi_identity_mismatch",
					"poi_instances",
					role,
					"核心 POI 模板或区域索引与 RegionPlan 不一致"
				))
			var canonical_center: Vector2i = instance.get("canonical_center", region.center_cell)
			var actual_center: Vector2i = instance.get("center_cell", Vector2i(-1, -1))
			var main_room_center: Vector2i = instance.get(
				"main_room_center",
				Vector2i(-1, -1)
			)
			var computed_main_room_center: Vector2i = _rect_center_cell(
				_rect_from_dictionary(instance.get("main_room", {}))
			)
			if str(instance.get("layout_kind", "")) == "authored_rooms":
				main_room_center = _cell_from_variant(instance.get("named_anchors", {}).get("primary", null))
				computed_main_room_center = main_room_center
			if (
				actual_center != region.core_anchor_cell
				or main_room_center != region.core_anchor_cell
				or computed_main_room_center != region.core_anchor_cell
			):
				issues.append(_four_region_issue(
					"core_poi_identity_mismatch",
					"poi_instances.center_cell",
					role,
					"核心 POI anchor 与 RegionPlan core_anchor_cell 不一致"
				))
			var max_offset: int = maxi(int(instance.get("max_center_offset_cells", 0)), 0)
			if actual_center.distance_to(canonical_center) > float(max_offset):
				issues.append(_four_region_issue(
					"core_poi_center_offset_exceeded",
					"poi_instances.center_cell",
					role,
					"核心 POI 主房中心超过配置的 canonical center 偏移"
				))
			var footprint: Array[Vector2i] = _cells_from_dictionary_array(
				instance.get("footprint_cells", [])
			)
			if not _footprint_belongs_to_region(
				footprint,
				membership,
				Vector2i(map_data.width, map_data.height),
				region.index
			):
				issues.append(_four_region_issue(
					"core_poi_footprint_crosses_region",
					"poi_instances.footprint_cells",
					role,
					"核心 POI 完整 footprint 必须位于目标区域"
				))
		if matching_core_count != 1:
			issues.append(_four_region_issue(
				"core_poi_count_mismatch",
				"poi_instances",
				role,
				"每个高风险区域必须恰好有一个核心 POI"
			))
		if identity_match_count != 1:
			issues.append(_four_region_issue(
				"core_poi_identity_mismatch",
				"poi_instances",
				role,
				"RegionPlan core identity 必须解析到恰好一个实际 POI instance"
			))
		if not _has_unprotected_regular_access_boundary(map_data, membership, region.index):
			issues.append(_four_region_issue(
				"missing_regular_access_boundary",
				"region_index_by_cell",
				role,
				"高风险区域与常规区域之间缺少未被永久保护结构封死的边界"
			))
	if map_data.player_spawn_points.size() != 1:
		issues.append(_four_region_issue(
			"spawn_placement_failed",
			"player_spawn_points",
			WdcMapGenerationTypes.REGION_ROLE_REGULAR,
			"四区域地图必须恰好包含一个出生锚点"
		))
	if map_data.extraction_sites.size() != 1:
		issues.append(_four_region_issue(
			"extraction_placement_failed",
			"extraction_sites",
			WdcMapGenerationTypes.REGION_ROLE_REGULAR,
			"四区域地图必须恰好包含一个普通撤离点"
		))
	for site: Dictionary in map_data.player_spawn_points + map_data.extraction_sites:
		var site_cell: Vector2i = _site_cell(site)
		var site_region = plan.try_get_at(site_cell)
		if (
			site_region == null
			or site_region.role != WdcMapGenerationTypes.REGION_ROLE_REGULAR
			or int(site.get("region_index", -1)) != site_region.index
			or str(site.get("region_role", "")) != site_region.role
		):
			issues.append(_four_region_issue(
				"site_region_mismatch",
				"spawn_or_extraction",
				WdcMapGenerationTypes.REGION_ROLE_REGULAR,
				"出生与撤离必须位于常规区域"
			))
	for extraction_site: Dictionary in map_data.extraction_sites:
		if _is_special_four_region_extraction_site(extraction_site):
			issues.append(_four_region_issue(
				"special_extraction_not_allowed",
				"extraction_sites",
				WdcMapGenerationTypes.REGION_ROLE_REGULAR,
				"四区域地图不得生成 BOSS、宝库或 guaranteed 特殊撤离"
			))
	issues.append_array(_validate_four_region_derived_sites(map_data, plan))
	issues.append_array(_validate_four_region_mineral_sites(map_data, plan))
	if map_data.region_boss_encounter != null:
		var anchors = map_data.region_boss_encounter.get_anchor_snapshots()
		var boss_region = plan.try_get_by_role(WdcMapGenerationTypes.REGION_ROLE_BOSS)
		var boss_instance: Dictionary = core_instances_by_role.get(
			WdcMapGenerationTypes.REGION_ROLE_BOSS,
			{}
		) as Dictionary
		var primary_matches: bool = (
			anchors.size() == 1
			and anchors[0].id == "primary"
			and not boss_instance.is_empty()
			and anchors[0].cell == boss_instance.get("center_cell", Vector2i(-1, -1))
		)
		if (
			boss_region == null
			or map_data.region_boss_encounter.get_region_id() != boss_region.id
			or map_data.region_boss_encounter.get_core_poi_instance_id()
			!= boss_region.core_poi_instance_id
			or not primary_matches
		):
			issues.append(_four_region_issue(
				"boss_encounter_mismatch",
				"region_boss_encounter.anchors",
				WdcMapGenerationTypes.REGION_ROLE_BOSS,
				"BOSS descriptor 必须匹配核心 POI，并只包含主房中心 primary anchor"
			))
	issues.append_array(_validate_four_region_reward_metadata(map_data, plan))
	if (
		map_data.player_spawn_points.size() == 1
		and map_data.extraction_sites.size() == 1
		and not _has_regular_only_route(
			map_data,
			membership,
			_site_cell(map_data.player_spawn_points[0]),
			_site_cell(map_data.extraction_sites[0])
		)
	):
		issues.append(_four_region_issue(
			"regular_route_missing",
			"player_spawn_points",
			WdcMapGenerationTypes.REGION_ROLE_REGULAR,
			"唯一出生到唯一撤离缺少 regular-only 开放或标准可挖路线"
		))
	return issues


func _validate_four_region_derived_sites(
	map_data: WdcMapGenerationTypes.MapData,
	plan: WdcMapGenerationTypes.RegionPlan
) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var collections: Array = [
		map_data.poi_instances,
		map_data.monster_sites,
		map_data.trap_sites,
		map_data.camp_encounters,
		map_data.furnishing_sites,
	]
	for collection: Array in collections:
		for item_value: Variant in collection:
			if not (item_value is Dictionary):
				continue
			var item: Dictionary = item_value as Dictionary
			var cell: Vector2i = _site_cell(item)
			if item.has("center_cell"):
				cell = _cell_from_variant(item.get("center_cell"))
			elif item.has("chest_cell"):
				cell = _cell_from_variant(item.get("chest_cell"))
			var region = plan.try_get_at(cell)
			var footprint: Array = _derived_site_region_cells(item)
			var footprint_matches: bool = region != null and not footprint.is_empty()
			if footprint_matches:
				for footprint_cell_value: Variant in footprint:
					if not (footprint_cell_value is Vector2i):
						footprint_matches = false
						break
					var footprint_cell: Vector2i = footprint_cell_value as Vector2i
					var footprint_region = plan.try_get_at(footprint_cell)
					if footprint_region == null or footprint_region.index != region.index:
						footprint_matches = false
						break
			if (
				region == null
				or int(item.get("region_index", -1)) != region.index
				or str(item.get("region_role", "")) != region.role
				or not footprint_matches
			):
				issues.append(_four_region_issue(
					"site_region_mismatch",
					"generated_sites.region_identity",
					str(item.get("region_role", "")),
					"派生站点 role/index 与完整 footprint 必须和 RegionPlan 查询一致"
				))
	return issues


func _validate_four_region_mineral_sites(
	map_data: WdcMapGenerationTypes.MapData,
	plan: WdcMapGenerationTypes.RegionPlan
) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	for site: Dictionary in map_data.mineral_sites:
		if site.has("region_index") or site.has("region_role"):
			issues.append(_four_region_issue(
				"mineral_region_cache_not_allowed",
				"mineral_sites",
				"",
				"矿物站点不得保存派生 region_index 或 region_role"
			))
			continue
		var anchor_cell: Vector2i = _site_cell(site)
		var anchor_region = plan.try_get_at(anchor_cell)
		var mineral_cells: Array[Vector2i] = _cells_from_dictionary_array(
			site.get("cells", [])
		)
		if mineral_cells.is_empty():
			mineral_cells.append(anchor_cell)
		var footprint_matches: bool = anchor_region != null
		if footprint_matches:
			for mineral_cell: Vector2i in mineral_cells:
				var mineral_region = plan.try_get_at(mineral_cell)
				if mineral_region == null or mineral_region.index != anchor_region.index:
					footprint_matches = false
					break
		if not footprint_matches:
			issues.append(_four_region_issue(
				"mineral_site_region_mismatch",
				"mineral_sites.cells",
				"",
				"矿物站点 anchor 与完整矿簇必须由 RegionPlan 解析到同一区域"
			))
	return issues


func _derived_site_region_cells(item: Dictionary) -> Array[Vector2i]:
	if item.has("footprint_cells"):
		return _cells_from_dictionary_array(item.get("footprint_cells", []))
	if item.has("chest_cell"):
		return _collect_camp_region_cells(item)
	if item.has("nodes") or item.has("cells"):
		return _collect_trap_region_cells(item)
	var cell: Vector2i = _site_cell(item)
	var cells: Array[Vector2i] = []
	if cell != Vector2i(-1, -1):
		cells.append(cell)
	return cells


func _validate_four_region_reward_metadata(
	map_data: WdcMapGenerationTypes.MapData,
	plan: WdcMapGenerationTypes.RegionPlan
) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var boss_region = plan.try_get_by_role(WdcMapGenerationTypes.REGION_ROLE_BOSS)
	for instance: Dictionary in map_data.poi_instances:
		if str(instance.get("instance_id", "")) != boss_region.core_poi_instance_id:
			continue
		var metadata_value: Variant = instance.get("core_metadata", null)
		if not (metadata_value is Dictionary):
			return [_four_region_issue(
				"invalid_core_poi_metadata",
				"poi_instances.core_metadata",
				WdcMapGenerationTypes.REGION_ROLE_BOSS,
				"BOSS 核心 POI 缺少 canonical reward metadata"
			)]
		var metadata: Dictionary = metadata_value as Dictionary
		if str(instance.get("layout_kind", "")) == "authored_rooms":
			return _validate_authored_boss_geometry(map_data, instance)
		var main_room_rect: Rect2i = _rect_from_dictionary(instance.get("main_room", {}))
		var footprint_keys: Dictionary = _cell_key_lookup(
			_cells_from_dictionary_array(instance.get("footprint_cells", []))
		)
		if str(metadata.get("reward_recipe_id", "")).is_empty():
			issues.append(_four_region_issue(
				"invalid_core_poi_metadata",
				"poi_instances.core_metadata.reward_recipe_id",
				WdcMapGenerationTypes.REGION_ROLE_BOSS,
				"BOSS 核心 POI reward_recipe_id 不能为空"
			))
		var gate_cells_value: Variant = metadata.get("reward_gate_cells", [])
		if not (gate_cells_value is Array) or (gate_cells_value as Array).is_empty():
			issues.append(_four_region_issue(
				"invalid_core_poi_metadata",
				"poi_instances.core_metadata.reward_gate_cells",
				WdcMapGenerationTypes.REGION_ROLE_BOSS,
				"BOSS 核心 POI reward gate 坐标不能为空"
			))
		else:
			for cell_value: Variant in gate_cells_value as Array:
				var gate_cell: Vector2i = _cell_from_variant(cell_value)
				var gate_region = plan.try_get_at(gate_cell)
				var gate_data: WdcMapGenerationTypes.CellData = map_data.get_cell(
					gate_cell.x,
					gate_cell.y
				)
				var outward_direction: Vector2i = _main_room_gate_outward_direction(
					gate_cell,
					main_room_rect
				)
				var outside_cell: Vector2i = gate_cell + outward_direction
				var outside_data: WdcMapGenerationTypes.CellData = (
					map_data.get_cell(outside_cell.x, outside_cell.y)
					if outward_direction != Vector2i.ZERO
					else null
				)
				if (
					gate_region == null
					or gate_region.role != WdcMapGenerationTypes.REGION_ROLE_BOSS
					or not footprint_keys.has(_key(gate_cell.x, gate_cell.y))
					or gate_data == null
					or gate_data.cell_type != WdcMapGenerationTypes.CellType.WALL
					or gate_data.special_block_type
					!= WdcMapGenerationTypes.SpecialBlockType.POI_WALL
					or not gate_data.is_poi_protected
					or outside_data == null
					or outside_data.cell_type != WdcMapGenerationTypes.CellType.FLOOR
					or outside_data.special_block_type
					!= WdcMapGenerationTypes.SpecialBlockType.NONE
					or outside_data.is_poi_protected
				):
					issues.append(_four_region_issue(
						"invalid_core_poi_metadata",
						"poi_instances.core_metadata.reward_gate_cells",
						WdcMapGenerationTypes.REGION_ROLE_BOSS,
						"奖励门必须是 BOSS 核心 POI footprint 内、外侧可通行的受保护结构墙"
					))
		var object_cells_value: Variant = metadata.get("reward_object_cells", [])
		if not (object_cells_value is Array) or (object_cells_value as Array).is_empty():
			issues.append(_four_region_issue(
				"invalid_core_poi_metadata",
				"poi_instances.core_metadata.reward_object_cells",
				WdcMapGenerationTypes.REGION_ROLE_BOSS,
				"BOSS 核心 POI reward object 坐标不能为空"
			))
		else:
			for cell_value: Variant in object_cells_value as Array:
				var object_cell: Vector2i = _cell_from_variant(cell_value)
				var object_region = plan.try_get_at(object_cell)
				var object_data: WdcMapGenerationTypes.CellData = map_data.get_cell(
					object_cell.x,
					object_cell.y
				)
				if (
					object_region == null
					or object_region.role != WdcMapGenerationTypes.REGION_ROLE_BOSS
					or not main_room_rect.has_point(object_cell)
					or not footprint_keys.has(_key(object_cell.x, object_cell.y))
					or object_data == null
					or object_data.cell_type != WdcMapGenerationTypes.CellType.FLOOR
					or object_data.special_block_type
					!= WdcMapGenerationTypes.SpecialBlockType.NONE
					or object_data.has_mineral
				):
					issues.append(_four_region_issue(
						"invalid_core_poi_metadata",
						"poi_instances.core_metadata.reward_object_cells",
						WdcMapGenerationTypes.REGION_ROLE_BOSS,
						"奖励物件必须位于 BOSS 核心 POI 主房的可放置地板"
					))
		return issues
	return [_four_region_issue(
		"invalid_core_poi_metadata",
		"poi_instances",
		WdcMapGenerationTypes.REGION_ROLE_BOSS,
		"找不到 BOSS 核心 POI instance"
	)]


func _validate_authored_boss_geometry(map_data: WdcMapGenerationTypes.MapData, instance: Dictionary) -> Array[Dictionary]:
	var metadata: Dictionary = instance.get("core_metadata", {})
	var gates: Array = metadata.get("reward_gate_cells", [])
	var normals: Array = metadata.get("reward_gate_normals", [])
	var floors: Dictionary = _cell_key_lookup(_cells_from_dictionary_array(instance.get("floor_cells", [])))
	var walls: Dictionary = _cell_key_lookup(_cells_from_dictionary_array(instance.get("wall_cells", [])))
	var footprint: Dictionary = _cell_key_lookup(_cells_from_dictionary_array(instance.get("footprint_cells", [])))
	var issues: Array[Dictionary] = []
	var occupied: Dictionary = {}
	var invalid_gate: bool = gates.is_empty() or gates.size() != normals.size()
	for index: int in range(gates.size()):
		var position: Vector2i = _cell_from_variant(gates[index])
		var normal: Vector2i = _cell_from_variant(normals[index]) if index < normals.size() else Vector2i.ZERO
		var key: String = _key(position.x, position.y)
		var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(position.x, position.y)
		invalid_gate = invalid_gate or occupied.has(key) or absi(normal.x) + absi(normal.y) != 1
		invalid_gate = invalid_gate or not walls.has(key) or not footprint.has(key)
		invalid_gate = invalid_gate or cell == null or cell.cell_type != WdcMapGenerationTypes.CellType.WALL or cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.POI_WALL or not cell.is_poi_protected
		for side: int in [-1, 1]:
			var adjacent: Vector2i = position + normal * side
			var adjacent_cell: WdcMapGenerationTypes.CellData = map_data.get_cell(adjacent.x, adjacent.y)
			invalid_gate = invalid_gate or not floors.has(_key(adjacent.x, adjacent.y)) or adjacent_cell == null or adjacent_cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR or adjacent_cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE
		occupied[key] = true
	if invalid_gate:
		issues.append(_four_region_issue("invalid_core_poi_metadata", "poi_instances.core_metadata.reward_gate_cells", "boss", "具名奖励门必须是图纸占地内唯一的受保护结构墙，法向两侧都应保留可走地板"))
	var devices: Dictionary = metadata.get("reward_device_slots", {})
	var object_cells: Array = metadata.get("reward_object_cells", [])
	var object_keys: Dictionary = _cell_key_lookup(_cells_from_dictionary_array(object_cells))
	var invalid_objects: bool = devices.is_empty() or devices.size() != object_cells.size() or object_keys.size() != object_cells.size()
	for id: String in devices:
		var position: Vector2i = _cell_from_variant(devices[id])
		var key: String = _key(position.x, position.y)
		var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(position.x, position.y)
		invalid_objects = invalid_objects or not floors.has(key) or not footprint.has(key) or not object_keys.has(key) or occupied.has(key)
		invalid_objects = invalid_objects or cell == null or cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR or cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE or cell.has_mineral
		invalid_objects = invalid_objects or _cell_from_variant(instance.get("named_anchors", {}).get("reward_device_" + id, null)) != position
		occupied[key] = true
	if invalid_objects:
		issues.append(_four_region_issue("invalid_core_poi_metadata", "poi_instances.core_metadata.reward_object_cells", "boss", "奖励坐标必须逐一对应具名槽，且位于图纸占地内唯一的可放置地板"))
	if str(metadata.get("reward_recipe_id", "")).is_empty():
		issues.append(_four_region_issue("invalid_core_poi_metadata", "poi_instances.core_metadata.reward_recipe_id", "boss", "奖励配方不能为空"))
	var walkable: Dictionary = {}
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			if map_data.get_cell(x, y).cell_type == WdcMapGenerationTypes.CellType.FLOOR:
				walkable[Vector2i(x, y)] = true
	var boss: Vector2i = _cell_from_variant(instance.get("named_anchors", {}).get("boss_spawn", null))
	var closed: Dictionary = _flood_authored_cells(boss, walkable)
	for value: Variant in gates:
		walkable[_cell_from_variant(value)] = true
	var opened: Dictionary = _flood_authored_cells(boss, walkable)
	var protected: Dictionary = {}
	for point: Vector2i in _cells_from_dictionary_array(metadata.get("reward_protected_cells", [])):
		protected[point] = true
	var invalid_separation: bool = protected.is_empty() or protected.has(boss)
	for value: Variant in object_cells:
		var point: Vector2i = _cell_from_variant(value)
		invalid_separation = invalid_separation or closed.has(point) or not opened.has(point) or not protected.has(point)
	for value: Variant in gates:
		invalid_separation = invalid_separation or not protected.has(_cell_from_variant(value))
	for point: Vector2i in protected:
		invalid_separation = invalid_separation or not footprint.has(_key(point.x, point.y))
	# 奖励侧每一格及其相邻结构墙都要进入保护范围，避免挖侧墙绕过门锁。
	if not object_cells.is_empty():
		var reward_floors: Dictionary = {}
		for point: Vector2i in _cells_from_dictionary_array(instance.get("floor_cells", [])):
			reward_floors[point] = true
		var reward_component: Dictionary = _flood_authored_cells(_cell_from_variant(object_cells[0]), reward_floors)
		for point: Vector2i in reward_component:
			invalid_separation = invalid_separation or not protected.has(point)
			for y: int in range(-1, 2):
				for x: int in range(-1, 2):
					var boundary: Vector2i = point + Vector2i(x, y)
					if walls.has(_key(boundary.x, boundary.y)):
						invalid_separation = invalid_separation or not protected.has(boundary)
	if invalid_separation:
		issues.append(_four_region_issue("invalid_core_poi_metadata", "poi_instances.core_metadata.reward_protected_cells", "boss", "BOSS 战斗区必须与奖励区隔开：关门不可达奖励，开门可达，奖励地板及边墙完整受保护"))
	return issues


func _is_special_four_region_extraction_site(site: Dictionary) -> bool:
	var extraction_kind: String = str(site.get("extraction_kind", "normal")).strip_edges().to_lower()
	if extraction_kind not in ["", "normal", "regular"]:
		return true
	var site_kind: String = str(site.get("site_kind", "extraction")).strip_edges().to_lower()
	if site_kind not in ["", "extraction", "regular", "normal"]:
		return true
	if bool(site.get("guaranteed", false)):
		return true
	for forbidden_key: String in [
		"boss_encounter_id",
		"reward_encounter_id",
		"reward_recipe_id",
		"reward_kind",
		"vault_id",
	]:
		if site.has(forbidden_key):
			return true
	return false


func _has_unprotected_regular_access_boundary(
	map_data: WdcMapGenerationTypes.MapData,
	membership: PackedInt32Array,
	region_index: int
) -> bool:
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			if int(membership[y * map_data.width + x]) != region_index:
				continue
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell != null and cell.is_poi_protected:
				continue
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = Vector2i(x, y) + direction
				if not map_data.is_in_bounds(neighbor.x, neighbor.y):
					continue
				if int(membership[neighbor.y * map_data.width + neighbor.x]) != 0:
					continue
				var neighbor_cell: WdcMapGenerationTypes.CellData = map_data.get_cell(
					neighbor.x,
					neighbor.y
				)
				if neighbor_cell != null and not neighbor_cell.is_poi_protected:
					return true
	return false


func _has_regular_only_route(
	map_data: WdcMapGenerationTypes.MapData,
	membership: PackedInt32Array,
	start: Vector2i,
	target: Vector2i
) -> bool:
	if start == target:
		return true
	var queue: Array[Vector2i] = [start]
	var seen: Dictionary = {_key(start.x, start.y): true}
	var cursor: int = 0
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = current + direction
			if not map_data.is_in_bounds(neighbor.x, neighbor.y):
				continue
			if int(membership[neighbor.y * map_data.width + neighbor.x]) != 0:
				continue
			var key: String = _key(neighbor.x, neighbor.y)
			if seen.has(key):
				continue
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(neighbor.x, neighbor.y)
			if cell == null or cell.is_poi_protected:
				continue
			if neighbor == target:
				return true
			seen[key] = true
			queue.append(neighbor)
	return false


func _collect_region_candidate_cells(
	map_data: WdcMapGenerationTypes.MapData,
	resolver: WdcRegionContentResolver,
	role: String,
	require_wall: bool,
	avoid_protected: bool
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var authored_cells: Dictionary = {}
	for poi: Dictionary in map_data.poi_instances:
		if str(poi.get("layout_kind", "")) == "authored_rooms":
			for position: Vector2i in _cells_from_dictionary_array(poi.get("footprint_cells", [])):
				authored_cells[_key(position.x, position.y)] = true
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var candidate: Vector2i = Vector2i(x, y)
			if authored_cells.has(_key(x, y)):
				continue
			if not resolver.is_cell_in_role(candidate, role):
				continue
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null or (avoid_protected and cell.is_poi_protected):
				continue
			if require_wall and cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
				continue
			if not require_wall and cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR:
				continue
			result.append(candidate)
	return result


func _pick_weighted_dictionary(
	entries: Array[Dictionary],
	rng: RandomNumberGenerator
) -> Dictionary:
	var total_weight: float = 0.0
	for entry: Dictionary in entries:
		total_weight += maxf(float(entry.get("weight", 0.0)), 0.0)
	if total_weight <= 0.0:
		return {}
	var roll: float = rng.randf() * total_weight
	for entry: Dictionary in entries:
		roll -= maxf(float(entry.get("weight", 0.0)), 0.0)
		if roll <= 0.0:
			return entry.duplicate(true)
	return entries.back().duplicate(true)


func _shuffle_dictionary_array(
	values: Array[Dictionary],
	rng: RandomNumberGenerator
) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var temp: Dictionary = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temp


func _rect_from_dictionary(value: Variant) -> Rect2i:
	if value is Rect2i:
		return value as Rect2i
	if not (value is Dictionary):
		return Rect2i()
	var rect: Dictionary = value as Dictionary
	return Rect2i(
		int(rect.get("x", 0)),
		int(rect.get("y", 0)),
		int(rect.get("width", 0)),
		int(rect.get("height", 0))
	)


func _site_cell(site: Dictionary) -> Vector2i:
	if site.has("cell"):
		return _cell_from_variant(site.get("cell"))
	return Vector2i(int(site.get("x", -1)), int(site.get("y", -1)))


func _collect_trap_region_cells(site: Dictionary) -> Array[Vector2i]:
	for field_name: String in ["nodes", "cells"]:
		var cells: Array[Vector2i] = _cells_from_dictionary_array(site.get(field_name, []))
		if not cells.is_empty():
			return cells
	var anchor: Vector2i = _site_cell(site)
	var cells: Array[Vector2i] = []
	if anchor != Vector2i(-1, -1):
		cells.append(anchor)
	return cells


func _collect_camp_region_cells(camp: Dictionary) -> Array[Vector2i]:
	var cells_by_key: Dictionary = {}
	var room_rect: Rect2i = _rect_from_dictionary(camp.get("room_rect", {}))
	for room_cell: Vector2i in _rect_cells(room_rect):
		cells_by_key[_key(room_cell.x, room_cell.y)] = room_cell
	var chest_cell: Vector2i = _cell_from_variant(camp.get("chest_cell", null))
	if chest_cell != Vector2i(-1, -1):
		cells_by_key[_key(chest_cell.x, chest_cell.y)] = chest_cell
	for guard_value: Variant in camp.get("guard_sites", []):
		if not (guard_value is Dictionary):
			continue
		var guard_cell: Vector2i = _site_cell(guard_value as Dictionary)
		if guard_cell != Vector2i(-1, -1):
			cells_by_key[_key(guard_cell.x, guard_cell.y)] = guard_cell
	var cells: Array[Vector2i] = []
	for cell_value: Variant in cells_by_key.values():
		if cell_value is Vector2i:
			cells.append(cell_value as Vector2i)
	return cells


func _make_four_region_rng(
	resolved_seed: int,
	attempt_index: int,
	salt: int
) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var mixed: int = resolved_seed & 0x7fffffff
	mixed = int((mixed ^ ((attempt_index + 1) * 1103515245)) & 0x7fffffff)
	mixed = int((mixed ^ (salt * 265443576)) & 0x7fffffff)
	rng.seed = maxi(mixed, 1)
	return rng


func _four_region_failure(
	code: String,
	path: String,
	role: String,
	message: String
) -> Dictionary:
	return {"success": false, "issues": [_four_region_issue(code, path, role, message)]}


func _four_region_issue(
	code: String,
	path: String,
	role: String,
	message: String
) -> Dictionary:
	return WdcMapGenerationTypes.make_generation_issue(code, path, role, message)


func get_last_generation_issues() -> Array[Dictionary]:
	return last_generation_issues.duplicate(true)


func _fail_generation(issue: Dictionary) -> Dictionary:
	last_generation_issues = [issue.duplicate(true)]
	last_generation_error = str(issue.get("message", "地图生成失败"))
	return {}


func _fail_generation_issues(issues: Array[Dictionary]) -> Dictionary:
	last_generation_issues = issues.duplicate(true)
	last_generation_error = (
		str(last_generation_issues[0].get("message", "地图生成失败"))
		if not last_generation_issues.is_empty()
		else "地图生成失败"
	)
	return {}


func _emit_stage(
	snapshots: Array[Dictionary],
	stage: StringName,
	map_data: WdcMapGenerationTypes.MapData,
	message: String,
	capture_snapshots: bool = true
) -> void:
	if not capture_snapshots:
		return
	var copied: WdcMapGenerationTypes.MapData = map_data.deep_clone()
	snapshots.append({
		"stage": String(stage),
		"map_data": copied,
		"message": message
	})
	generation_stage_completed.emit(stage, copied)


func _resolve_seed(input_seed: int) -> int:
	if input_seed != 0:
		return input_seed
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var resolved_seed: int = int(rng.randi() & 0x7fffffff)
	if resolved_seed == 0:
		resolved_seed = int(Time.get_ticks_usec() & 0x7fffffff)
	return maxi(resolved_seed, 1)


func _place_all_pois(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	if not config.poi_templates.is_empty():
		_place_configured_pois(map_data, config, rng)
		return
	var defs: Array[Dictionary] = [
		{
			"type": WdcMapGenerationTypes.PoiType.LARGE_RUIN,
			"count": config.large_poi_count,
			"min_distance": config.large_poi_min_distance,
			"radius": config.large_poi_radius,
			"irregularity": config.large_poi_irregularity
		},
		{
			"type": WdcMapGenerationTypes.PoiType.MEDIUM_BIOME,
			"count": config.medium_poi_count,
			"min_distance": config.medium_poi_min_distance,
			"radius": config.medium_poi_radius,
			"irregularity": config.medium_poi_irregularity
		},
		{
			"type": WdcMapGenerationTypes.PoiType.SMALL_ORE,
			"count": config.small_poi_count,
			"min_distance": config.small_poi_min_distance,
			"radius": config.small_poi_radius,
			"irregularity": config.small_poi_irregularity
		}
	]
	for poi_def: Dictionary in defs:
		var poi_type: int = poi_def.get("type", WdcMapGenerationTypes.PoiType.NONE) as int
		var target_count: int = poi_def.get("count", 0) as int
		var min_distance: float = poi_def.get("min_distance", 0.0) as float
		var radius: int = poi_def.get("radius", 0) as int
		var irregularity: float = poi_def.get("irregularity", 0.0) as float
		var max_attempts: int = target_count * 50
		var placed_count: int = 0
		var attempts: int = 0
		while placed_count < target_count and attempts < max_attempts:
			attempts += 1
			if _try_place_one_poi(map_data, poi_type, min_distance, radius, irregularity, rng):
				placed_count += 1


func _place_configured_pois(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	var template_index: int = 0
	for template_dict: Dictionary in config.poi_templates:
		if not bool(template_dict.get("enabled", true)):
			template_index += 1
			continue
		var target_count: int = maxi(int(template_dict.get("count", 0)), 0)
		var max_attempts: int = maxi(int(template_dict.get("placement", {}).get("poi_attempts", 40)), 1)
		var compat_poi_type: int = _resolve_compat_poi_type(template_index)
		var placed_total: int = 0
		var layer_budget: Dictionary = _split_layer_budget_counts(
			target_count,
			config,
			"poi_budget_weight"
		)
		for layer: Dictionary in config.map_layers:
			var layer_id: String = str(layer.get("id", ""))
			var layer_target_count: int = int(layer_budget.get(layer_id, 0))
			var placed_in_layer: int = 0
			var attempts: int = 0
			while placed_in_layer < layer_target_count and attempts < max_attempts * maxi(layer_target_count, 1):
				attempts += 1
				if _try_place_configured_poi(
					map_data,
					config,
					template_dict,
					compat_poi_type,
					rng,
					layer_id
				):
					placed_in_layer += 1
					placed_total += 1
		var fallback_attempts: int = 0
		while placed_total < target_count and fallback_attempts < max_attempts * maxi(target_count, 1):
			fallback_attempts += 1
			if _try_place_configured_poi(map_data, config, template_dict, compat_poi_type, rng):
				placed_total += 1
		template_index += 1


func _resolve_compat_poi_type(template_index: int) -> int:
	match template_index:
		0:
			return WdcMapGenerationTypes.PoiType.LARGE_RUIN
		1:
			return WdcMapGenerationTypes.PoiType.MEDIUM_BIOME
		_:
			return WdcMapGenerationTypes.PoiType.SMALL_ORE


func _try_place_configured_poi(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	template_dict: Dictionary,
	compat_poi_type: int,
	rng: RandomNumberGenerator,
	target_layer_id: String = ""
) -> bool:
	var placement: Dictionary = template_dict.get("placement", {}) as Dictionary
	var main_room_cfg: Dictionary = template_dict.get("main_room", {}) as Dictionary
	var sub_room_cfg: Dictionary = template_dict.get("sub_rooms", {}) as Dictionary
	var main_room_margin: int = maxi(
		int(sub_room_cfg.get("placement_radius_max_cells", 0)),
		maxi(int(placement.get("footprint_padding_cells", 0)), 0)
	) + 1
	var main_room_rect: Rect2i = _sample_room_rect(map_data, main_room_cfg, rng, main_room_margin)
	if main_room_rect.size == Vector2i.ZERO:
		return false
	if not target_layer_id.is_empty():
		var layer: Dictionary = _resolve_layer_for_rect_center(config, map_data, main_room_rect)
		if str(layer.get("id", "")) != target_layer_id:
			return false
	var rooms: Array[Rect2i] = [main_room_rect]
	var sub_room_count: int = 0
	var sub_count_min: int = maxi(int(sub_room_cfg.get("count_min", 0)), 0)
	var sub_count_max: int = maxi(int(sub_room_cfg.get("count_max", sub_count_min)), sub_count_min)
	if sub_count_max > 0:
		sub_room_count = rng.randi_range(sub_count_min, sub_count_max)
	var placed_sub_room_count: int = 0
	for _sub_room_index: int in range(sub_room_count):
		var sub_room_rect: Rect2i = _sample_sub_room_rect(map_data, rooms, main_room_rect, sub_room_cfg, rng)
		if sub_room_rect.size == Vector2i.ZERO:
			continue
		rooms.append(sub_room_rect)
		placed_sub_room_count += 1
	if placed_sub_room_count < sub_count_min:
		return false
	var corridor_edges: Array[Dictionary] = _build_poi_connectivity_edges(rooms, template_dict, rng)
	if corridor_edges.is_empty() and rooms.size() > 1:
		return false
	var corridor_plans: Array[Dictionary] = _build_corridor_plans_for_edges(
		rooms,
		corridor_edges,
		template_dict
	)
	var corridor_cells: Array[Vector2i] = _collect_unique_corridor_cells(corridor_plans)
	if corridor_cells.is_empty() and rooms.size() > 1:
		return false
	var total_bounds: Rect2i = _compute_total_poi_bounds(rooms, corridor_cells, placement)
	if not _is_poi_bounds_valid(map_data, total_bounds):
		return false
	for existing_instance: Dictionary in map_data.poi_instances:
		if total_bounds.intersects(existing_instance.get("bounds", Rect2i())):
			return false
	var center_cell: Vector2i = _rect_center_cell(main_room_rect)
	var torch_sites: Array[Vector2i] = _build_main_room_torch_sites(main_room_rect, template_dict)
	var room_content_plans: Array[Dictionary] = _build_room_content_plans(
		rooms,
		corridor_plans,
		template_dict,
		config,
		rng
	)
	if _has_invalid_room_content_plan(room_content_plans):
		return false
	_carve_poi_rooms_and_corridors(map_data, rooms, corridor_cells, compat_poi_type)
	_place_poi_outer_walls(map_data, rooms, corridor_cells, compat_poi_type)
	var poi_layer: Dictionary = _resolve_layer_for_rect_center(config, map_data, main_room_rect)
	map_data.poi_centers.append({
		"x": center_cell.x,
		"y": center_cell.y,
		"type": compat_poi_type,
		"template_id": str(template_dict.get("id", "")),
		"layer_id": str(poi_layer.get("id", "")),
	})
	map_data.poi_instances.append({
		"template_id": str(template_dict.get("id", "")),
		"poi_type": compat_poi_type,
		"layer_id": str(poi_layer.get("id", "")),
		"bounds": total_bounds,
		"main_room": _rect_to_dict(main_room_rect),
		"sub_rooms": _rect_array_to_dict_array(rooms.slice(1)),
		"corridors": _corridor_plans_to_dict_array(corridor_plans),
		"corridor_cell_count": corridor_cells.size(),
		"center_cell": center_cell,
		"torch_sites": _vector2i_array_to_dict_array(torch_sites),
		"room_content_plans": _room_content_plan_array_to_dict_array(room_content_plans),
	})
	_append_room_content_sites(
		map_data,
		room_content_plans,
		config,
		str(template_dict.get("id", ""))
	)
	_place_poi_center_cluster(map_data, main_room_rect, template_dict, config, rng, room_content_plans)
	return true


func _try_place_four_region_poi(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	template_dict: Dictionary,
	role: String,
	region_index: int,
	membership: PackedInt32Array,
	requested_center: Vector2i,
	is_core: bool,
	attempt_index: int,
	instance_ordinal: int,
	rng: RandomNumberGenerator,
	resolver: WdcRegionContentResolver = null
) -> Dictionary:
	if not bool(template_dict.get("enabled", true)):
		return {}
	if str(template_dict.get("layout_kind", "")) == "authored_rooms":
		return _try_place_authored_poi(map_data, config, template_dict, role, region_index,
			membership, requested_center, is_core, attempt_index, instance_ordinal, resolver)
	var main_room_cfg: Dictionary = template_dict.get("main_room", {}) as Dictionary
	var main_width_min: int = maxi(int(main_room_cfg.get("width_min", 1)), 1)
	var main_width_max: int = maxi(int(main_room_cfg.get("width_max", main_width_min)), main_width_min)
	var main_height_min: int = maxi(int(main_room_cfg.get("height_min", 1)), 1)
	var main_height_max: int = maxi(int(main_room_cfg.get("height_max", main_height_min)), main_height_min)
	var main_width: int = rng.randi_range(main_width_min, main_width_max)
	var main_height: int = rng.randi_range(main_height_min, main_height_max)
	var main_room_rect: Rect2i = Rect2i(
		requested_center.x - int(floor(float(main_width) * 0.5)),
		requested_center.y - int(floor(float(main_height) * 0.5)),
		main_width,
		main_height
	)
	if not _is_room_rect_in_bounds(map_data, main_room_rect):
		return {}
	var rooms: Array[Rect2i] = [main_room_rect]
	var sub_room_cfg: Dictionary = template_dict.get("sub_rooms", {}) as Dictionary
	var sub_count_min: int = maxi(int(sub_room_cfg.get("count_min", 0)), 0)
	var sub_count_max: int = maxi(int(sub_room_cfg.get("count_max", sub_count_min)), sub_count_min)
	var sub_room_count: int = rng.randi_range(sub_count_min, sub_count_max) if sub_count_max > 0 else 0
	for _sub_room_index: int in range(sub_room_count):
		var sub_room_rect: Rect2i = _sample_four_region_sub_room_rect(
			map_data,
			rooms,
			main_room_rect,
			sub_room_cfg,
			rng
		)
		if sub_room_rect.size == Vector2i.ZERO:
			continue
		rooms.append(sub_room_rect)
	if rooms.size() - 1 < sub_count_min:
		return {}
	var corridor_edges: Array[Dictionary] = _build_four_region_poi_connectivity_edges(
		rooms,
		template_dict,
		rng
	)
	if rooms.size() > 1 and corridor_edges.is_empty():
		return {}
	var corridor_plans: Array[Dictionary] = _build_corridor_plans_for_edges(
		rooms,
		corridor_edges,
		template_dict
	)
	var corridor_cells: Array[Vector2i] = _collect_unique_corridor_cells(corridor_plans)
	if rooms.size() > 1 and corridor_cells.is_empty():
		return {}
	var structural_footprint: Array[Vector2i] = _collect_poi_structural_footprint(
		rooms,
		corridor_cells,
		0
	)
	var validation_padding: int = (
		_get_four_region_core_padding(config, role)
		if is_core
		else maxi(int(template_dict.get("placement", {}).get("footprint_padding_cells", 0)), 0)
	)
	var validated_footprint: Array[Vector2i] = _expand_footprint(
		structural_footprint,
		validation_padding,
		map_data
	)
	if resolver != null:
		var resolved_footprint: Dictionary = resolver.resolve_footprint_for_role(
			validated_footprint,
			role
		)
		if not bool(resolved_footprint.get("valid", false)):
			return {}
		region_index = int(resolved_footprint.get("region_index", -1))
	elif not _footprint_belongs_to_region(
		validated_footprint,
		membership,
		Vector2i(map_data.width, map_data.height),
		region_index
	):
		return {}
	var bounds: Rect2i = _bounds_from_cells(structural_footprint)
	if bounds.size == Vector2i.ZERO or not _is_poi_bounds_valid(map_data, bounds):
		return {}
	if _four_region_poi_overlaps_existing(map_data, structural_footprint, bounds):
		return {}
	var center_cell: Vector2i = _rect_center_cell(main_room_rect)
	var core_metadata: Dictionary = {}
	if is_core:
		core_metadata = _materialize_core_metadata(
			template_dict.get("core_metadata", {}),
			center_cell,
			map_data,
			membership,
			region_index
		)
		if template_dict.has("core_metadata") and core_metadata.is_empty():
			return {}
		if not _is_four_region_core_metadata_geometry_valid(
			core_metadata,
			main_room_rect,
			structural_footprint,
			map_data,
			membership,
			region_index
		):
			return {}
	var compat_poi_type: int = _four_region_poi_type(role, is_core)
	_carve_poi_rooms_and_corridors(map_data, rooms, corridor_cells, compat_poi_type)
	_place_poi_outer_walls(map_data, rooms, corridor_cells, compat_poi_type)
	if is_core and not core_metadata.is_empty():
		_apply_four_region_core_metadata_geometry(
			map_data,
			core_metadata,
			main_room_rect,
			compat_poi_type
		)
	var template_id: String = str(template_dict.get("id", ""))
	var instance_id: String = "%s:%s:a%d:n%d:%d:%d" % [
		role,
		template_id,
		attempt_index,
		instance_ordinal,
		center_cell.x,
		center_cell.y,
	]
	var torch_sites: Array[Vector2i] = _build_main_room_torch_sites(main_room_rect, template_dict)
	var instance: Dictionary = {
		"instance_id": instance_id,
		"template_id": template_id,
		"poi_type": _four_region_poi_type(role, is_core),
		"region_index": region_index,
		"region_role": role,
		"is_core": is_core,
		"bounds": bounds,
		"main_room": _rect_to_dict(main_room_rect),
		"main_room_center": center_cell,
		"sub_rooms": _rect_array_to_dict_array(rooms.slice(1)),
		"corridors": _corridor_plans_to_dict_array(corridor_plans),
		"corridor_cell_count": corridor_cells.size(),
		"center_cell": center_cell,
		"torch_sites": _vector2i_array_to_dict_array(torch_sites),
		"room_content_plans": [],
		"footprint_cells": _vector2i_array_to_dict_array(structural_footprint),
	}
	if is_core:
		instance["core_metadata"] = core_metadata
	map_data.poi_centers.append({
		"x": center_cell.x,
		"y": center_cell.y,
		"type": _four_region_poi_type(role, is_core),
		"template_id": template_id,
		"instance_id": instance_id,
		"region_index": region_index,
		"region_role": role,
		"is_core": is_core,
	})
	map_data.poi_instances.append(instance)
	return instance


## 图纸几何逐格写入；外接矩形只用于快速拒绝，不能替代实际地板或墙。
func _try_place_authored_poi(
	map_data: WdcMapGenerationTypes.MapData, config: WdcMapGenerationTypes.MapConfig,
	template: Dictionary, role: String, region_index: int, membership: PackedInt32Array,
	center: Vector2i, is_core: bool, attempt: int, ordinal: int,
	resolver: WdcRegionContentResolver
) -> Dictionary:
	var bundle: Dictionary = config.get_meta("poi_resource_bundle", {})
	var seed_value: int = _active_authored_seed
	var result: Dictionary = POI_COMPOSITION_GENERATOR.generate(
		str(template.get("composition_id", "")), bundle,
		seed_value if config.layout_mode == WdcMapGenerationTypes.LAYOUT_MODE_POI_ONLY_V1 else maxi(abs(("%d:%s:%d:%d" % [seed_value, role, attempt, ordinal]).hash()), 1),
		{"origin": {"x": center.x, "y": center.y}})
	if not bool(result.get("valid", false)):
		return {}
	var plan: Dictionary = result.get("plan", {})
	var footprint: Array[Vector2i] = _cells_from_dictionary_array(plan.get("footprint_cells", []))
	var floor_cells: Array[Vector2i] = _cells_from_dictionary_array(plan.get("floor_cells", []))
	var walls: Array[Vector2i] = _cells_from_dictionary_array(plan.get("wall_cells", []))
	if footprint.is_empty() or not floor_cells.has(center):
		return {}
	var bounds: Rect2i = _bounds_from_cells(footprint)
	if not _is_poi_bounds_valid(map_data, bounds) or _four_region_poi_overlaps_existing(map_data, footprint, bounds):
		return {}
	var padding: int = 0 if config.layout_mode == WdcMapGenerationTypes.LAYOUT_MODE_POI_ONLY_V1 else (_get_four_region_core_padding(config, role) if is_core else int(template.get("placement", {}).get("footprint_padding_cells", 0)))
	var padded: Array[Vector2i] = _expand_footprint(footprint, padding, map_data)
	if resolver != null:
		if not bool(resolver.resolve_footprint_for_role(padded, role).get("valid", false)):
			return {}
	elif not _footprint_belongs_to_region(padded, membership, Vector2i(map_data.width, map_data.height), region_index):
		return {}
	var instance_id: String = "%s:%s:a%d:n%d:%d:%d" % [role, template.id, attempt, ordinal, center.x, center.y]
	var poi_type: int = _four_region_poi_type(role, is_core)
	var instance: Dictionary = {
		"instance_id": instance_id, "template_id": str(template.id), "layout_kind": "authored_rooms",
		"composition_id": str(template.composition_id), "content_hash": str(bundle.get("content_hash", "")),
		"poi_type": poi_type, "region_index": region_index, "region_role": role, "is_core": is_core,
		"bounds": bounds, "center_cell": center, "named_anchors": plan.get("anchors", {}).duplicate(true),
		"rooms": plan.get("rooms", []).duplicate(true), "connections": plan.get("connections", []).duplicate(true),
		"floor_cells": plan.get("floor_cells", []).duplicate(true), "wall_cells": plan.get("wall_cells", []).duplicate(true),
		"footprint_cells": plan.get("footprint_cells", []).duplicate(true), "keep_clear": plan.get("keep_clear", []).duplicate(true),
		"content_requests": plan.get("content_requests", []).duplicate(true), "content_plans": [],
		"room_content_plans": [], "torch_sites": [],
	}
	if is_core and (role == WdcMapGenerationTypes.REGION_ROLE_BOSS or config.layout_mode == WdcMapGenerationTypes.LAYOUT_MODE_POI_ONLY_V1):
		var metadata: Dictionary = _authored_boss_metadata(instance, bundle)
		if metadata.is_empty():
			return {}
		instance["core_metadata"] = metadata
	for position: Vector2i in floor_cells:
		var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(position.x, position.y)
		cell.cell_type = WdcMapGenerationTypes.CellType.FLOOR
		cell.poi_type = poi_type
		cell.is_poi_protected = true
		cell.has_mineral = false
		cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.NONE
		cell.trace_type = WdcMapGenerationTypes.PoiType.NONE
		WdcMapGenerationTileRules.refresh_cell_runtime_state(cell)
	for position: Vector2i in walls:
		var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(position.x, position.y)
		cell.cell_type = WdcMapGenerationTypes.CellType.WALL
		cell.poi_type = poi_type
		cell.is_poi_protected = true
		cell.has_mineral = false
		cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.POI_WALL
		cell.trace_type = WdcMapGenerationTypes.PoiType.NONE
		WdcMapGenerationTileRules.refresh_cell_runtime_state(cell)
	for gate: Variant in instance.get("core_metadata", {}).get("reward_gate_cells", []):
		var gate_cell: Vector2i = _cell_from_variant(gate)
		var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(gate_cell.x, gate_cell.y)
		cell.cell_type = WdcMapGenerationTypes.CellType.WALL
		cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.POI_WALL
		WdcMapGenerationTileRules.refresh_cell_runtime_state(cell)
	map_data.poi_centers.append({"x": center.x, "y": center.y, "type": poi_type,
		"template_id": str(template.id), "instance_id": instance_id, "region_index": region_index,
		"region_role": role, "is_core": is_core})
	map_data.poi_instances.append(instance)
	return instance


func _authored_boss_metadata(instance: Dictionary, bundle: Dictionary) -> Dictionary:
	var anchors: Dictionary = instance.get("named_anchors", {})
	if not anchors.has("boss_spawn") or _cell_from_variant(anchors.boss_spawn) != instance.center_cell:
		return {}
	var composition: Dictionary = bundle.get("compositions", {}).get(instance.composition_id, {})
	var gates: Array = []
	var gate_normals: Array = []
	for room: Dictionary in instance.get("rooms", []):
		for port: Dictionary in room.get("ports", []):
			if str(port.get("kind", "")) != "reward_gate":
				continue
			for cell: Variant in port.get("cells", []):
				gates.append(cell)
				gate_normals.append(port.get("normal", {}))
	var devices: Dictionary = {}
	for key: String in anchors:
		if key.begins_with("reward_device_"):
			devices[key.trim_prefix("reward_device_")] = anchors[key]
	if gates.is_empty() or devices.is_empty() or str(composition.get("reward_recipe_id", "")).is_empty():
		return {}
	var floors: Dictionary = {}
	var walls: Dictionary = {}
	for point: Vector2i in _cells_from_dictionary_array(instance.get("floor_cells", [])):
		floors[point] = true
	for point: Vector2i in _cells_from_dictionary_array(instance.get("wall_cells", [])):
		walls[point] = true
	var boss_cell: Vector2i = _cell_from_variant(anchors.boss_spawn)
	var battle: Dictionary = _flood_authored_cells(boss_cell, floors)
	var rewards: Dictionary = _flood_authored_cells(_cell_from_variant(devices.values()[0]), floors)
	if rewards.is_empty() or rewards.has(boss_cell):
		return {}
	for value: Variant in devices.values():
		if not rewards.has(_cell_from_variant(value)):
			return {}
	var opened: Dictionary = floors.duplicate()
	for value: Variant in gates:
		opened[_cell_from_variant(value)] = true
	var unlocked: Dictionary = _flood_authored_cells(boss_cell, opened)
	var protected: Dictionary = rewards.duplicate()
	for reward: Vector2i in rewards:
		if not unlocked.has(reward):
			return {}
		for y: int in range(-1, 2):
			for x: int in range(-1, 2):
				var boundary: Vector2i = reward + Vector2i(x, y)
				if walls.has(boundary):
					protected[boundary] = true
	for value: Variant in gates:
		if not protected.has(_cell_from_variant(value)):
			return {}
	var external_entry: bool = false
	for room: Dictionary in instance.get("rooms", []):
		for port: Dictionary in room.get("ports", []):
			if str(port.get("kind", "")) != "reward_gate" and str(port.get("unused", "")) == "open" and not bool(port.get("consumed", false)):
				for value: Variant in port.get("cells", []):
					if battle.has(_cell_from_variant(value)):
						external_entry = true
	if not external_entry:
		return {}
	return {"reward_gate_cells": gates, "reward_gate_normals": gate_normals,
		"reward_object_cells": devices.values(), "reward_device_slots": devices,
		"reward_recipe_id": str(composition.reward_recipe_id),
		"reward_protected_cells": _vector2i_array_to_dict_array(_typed_cells(protected.keys()))}


func _typed_cells(values: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(values)
	return result


func _flood_authored_cells(start: Vector2i, walkable: Dictionary) -> Dictionary:
	if not walkable.has(start):
		return {}
	var reached: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor: int = 0
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]
		cursor += 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + step
			if walkable.has(next) and not reached.has(next):
				reached[next] = true
				queue.append(next)
	return reached


func _build_four_region_poi_connectivity_edges(
	rooms: Array[Rect2i],
	template_dict: Dictionary,
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	if rooms.size() <= 1:
		return []
	var connectivity: Dictionary = template_dict.get("connectivity", {}) as Dictionary
	var neighbor_limit: int = maxi(int(connectivity.get("candidate_neighbors_per_room", 2)), 1)
	var candidate_edges: Array[Dictionary] = []
	var seen_keys: Dictionary = {}
	for room_index: int in range(rooms.size()):
		var room_distances: Array[Dictionary] = []
		var center_a: Vector2i = _rect_center_cell(rooms[room_index])
		for other_index: int in range(rooms.size()):
			if room_index == other_index:
				continue
			var center_b: Vector2i = _rect_center_cell(rooms[other_index])
			room_distances.append({
				"from": room_index,
				"to": other_index,
				"distance": abs(center_a.x - center_b.x) + abs(center_a.y - center_b.y),
			})
		room_distances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var distance_a: int = int(a.get("distance", 0))
			var distance_b: int = int(b.get("distance", 0))
			if distance_a != distance_b:
				return distance_a < distance_b
			return int(a.get("to", 0)) < int(b.get("to", 0))
		)
		for neighbor_index: int in range(mini(neighbor_limit, room_distances.size())):
			var edge: Dictionary = room_distances[neighbor_index]
			var key: String = _edge_key(int(edge.get("from", 0)), int(edge.get("to", 0)))
			if seen_keys.has(key):
				continue
			seen_keys[key] = true
			candidate_edges.append(edge)
	_ensure_candidate_edge_connectivity(rooms, candidate_edges, seen_keys)
	var mst_edges: Array[Dictionary] = _build_mst_edges(rooms.size(), candidate_edges)
	var selected_keys: Dictionary = {}
	for edge: Dictionary in mst_edges:
		selected_keys[_edge_key(int(edge.get("from", 0)), int(edge.get("to", 0)))] = true
	var extra_chance: float = clampf(float(connectivity.get("extra_connection_chance", 0.0)), 0.0, 1.0)
	var max_extra: int = maxi(int(connectivity.get("max_extra_connections", 0)), 0)
	if max_extra <= 0 or extra_chance <= 0.0:
		return mst_edges
	var extra_candidates: Array[Dictionary] = []
	for edge: Dictionary in candidate_edges:
		if selected_keys.has(_edge_key(int(edge.get("from", 0)), int(edge.get("to", 0)))):
			continue
		extra_candidates.append(edge)
	_shuffle_dictionary_array(extra_candidates, rng)
	var extra_edges: Array[Dictionary] = []
	for edge: Dictionary in extra_candidates:
		if extra_edges.size() >= max_extra:
			break
		if rng.randf() <= extra_chance:
			extra_edges.append(edge)
	return mst_edges + extra_edges


func _sample_four_region_sub_room_rect(
	map_data: WdcMapGenerationTypes.MapData,
	existing_rooms: Array[Rect2i],
	main_room_rect: Rect2i,
	sub_room_cfg: Dictionary,
	rng: RandomNumberGenerator
) -> Rect2i:
	var attempts: int = maxi(int(sub_room_cfg.get("placement_attempts_per_room", 24)), 24)
	var width_min: int = maxi(int(sub_room_cfg.get("width_min", 1)), 1)
	var width_max: int = maxi(int(sub_room_cfg.get("width_max", width_min)), width_min)
	var height_min: int = maxi(int(sub_room_cfg.get("height_min", 1)), 1)
	var height_max: int = maxi(int(sub_room_cfg.get("height_max", height_min)), height_min)
	var min_gap: int = maxi(int(sub_room_cfg.get("min_gap_from_rooms_cells", 1)), 0)
	var configured_radius_min: int = maxi(int(sub_room_cfg.get("placement_radius_min_cells", 1)), 1)
	var configured_radius_max: int = maxi(
		int(sub_room_cfg.get("placement_radius_max_cells", configured_radius_min)),
		configured_radius_min
	)
	var main_center: Vector2i = _rect_center_cell(main_room_rect)
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	_shuffle_vector2i_array(directions, rng)
	for attempt: int in range(attempts):
		var width: int = rng.randi_range(width_min, width_max)
		var height: int = rng.randi_range(height_min, height_max)
		var direction: Vector2i = directions[attempt % directions.size()]
		var minimum_radius: int = configured_radius_min
		if direction.x != 0:
			minimum_radius = maxi(
				minimum_radius,
				int(ceili(float(main_room_rect.size.x + width) * 0.5)) + min_gap
			)
		else:
			minimum_radius = maxi(
				minimum_radius,
				int(ceili(float(main_room_rect.size.y + height) * 0.5)) + min_gap
			)
		var maximum_radius: int = maxi(configured_radius_max, minimum_radius)
		var radius: int = rng.randi_range(minimum_radius, maximum_radius)
		var center: Vector2i = main_center + direction * radius
		var candidate: Rect2i = Rect2i(
			center.x - int(floor(float(width) * 0.5)),
			center.y - int(floor(float(height) * 0.5)),
			width,
			height
		)
		if not _is_room_rect_in_bounds(map_data, candidate):
			continue
		var overlaps: bool = false
		for existing_room: Rect2i in existing_rooms:
			if _rect_intersects_with_margin(candidate, existing_room, min_gap):
				overlaps = true
				break
		if not overlaps:
			return candidate
	return Rect2i()


func _collect_center_offset_candidates(
	center: Vector2i,
	max_offset: int,
	map_data: WdcMapGenerationTypes.MapData,
	membership: PackedInt32Array,
	region_index: int
) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for y: int in range(center.y - max_offset, center.y + max_offset + 1):
		for x: int in range(center.x - max_offset, center.x + max_offset + 1):
			var candidate: Vector2i = Vector2i(x, y)
			if not map_data.is_in_bounds(x, y):
				continue
			if int(membership[y * map_data.width + x]) != region_index:
				continue
			candidates.append(candidate)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var distance_a: int = a.distance_squared_to(center)
		var distance_b: int = b.distance_squared_to(center)
		if distance_a != distance_b:
			return distance_a < distance_b
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return candidates


func _collect_poi_structural_footprint(
	rooms: Array[Rect2i],
	corridor_cells: Array[Vector2i],
	extra_padding: int
) -> Array[Vector2i]:
	var interior: Dictionary = {}
	for room: Rect2i in rooms:
		for y: int in range(room.position.y, room.end.y):
			for x: int in range(room.position.x, room.end.x):
				interior[_key(x, y)] = Vector2i(x, y)
	for corridor_cell: Vector2i in corridor_cells:
		interior[_key(corridor_cell.x, corridor_cell.y)] = corridor_cell
	var structural: Dictionary = interior.duplicate()
	for cell_value: Variant in interior.values():
		var cell: Vector2i = cell_value as Vector2i
		for offset_y: int in range(-1, 2):
			for offset_x: int in range(-1, 2):
				var shell_cell: Vector2i = cell + Vector2i(offset_x, offset_y)
				structural[_key(shell_cell.x, shell_cell.y)] = shell_cell
	var cells: Array[Vector2i] = []
	for cell_value: Variant in structural.values():
		if cell_value is Vector2i:
			cells.append(cell_value as Vector2i)
	if extra_padding <= 0:
		return cells
	return _expand_footprint_without_bounds(cells, extra_padding)


func _expand_footprint(
	cells: Array[Vector2i],
	padding: int,
	map_data: WdcMapGenerationTypes.MapData
) -> Array[Vector2i]:
	var expanded: Array[Vector2i] = _expand_footprint_without_bounds(cells, padding)
	for cell: Vector2i in expanded:
		if not map_data.is_in_bounds(cell.x, cell.y):
			return []
	return expanded


func _expand_footprint_without_bounds(
	cells: Array[Vector2i],
	padding: int
) -> Array[Vector2i]:
	var values: Dictionary = {}
	for cell: Vector2i in cells:
		for offset_y: int in range(-padding, padding + 1):
			for offset_x: int in range(-padding, padding + 1):
				var expanded_cell: Vector2i = cell + Vector2i(offset_x, offset_y)
				values[_key(expanded_cell.x, expanded_cell.y)] = expanded_cell
	var result: Array[Vector2i] = []
	for value: Variant in values.values():
		if value is Vector2i:
			result.append(value as Vector2i)
	return result


func _footprint_belongs_to_region(
	cells: Array[Vector2i],
	membership: PackedInt32Array,
	map_size: Vector2i,
	region_index: int
) -> bool:
	if cells.is_empty():
		return false
	for cell: Vector2i in cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
			return false
		if int(membership[cell.y * map_size.x + cell.x]) != region_index:
			return false
	return true


func _four_region_poi_overlaps_existing(
	map_data: WdcMapGenerationTypes.MapData,
	footprint: Array[Vector2i],
	bounds: Rect2i
) -> bool:
	var footprint_keys: Dictionary = _cell_key_lookup(footprint)
	for existing: Dictionary in map_data.poi_instances:
		var existing_footprint: Array[Vector2i] = _cells_from_dictionary_array(
			existing.get("footprint_cells", [])
		)
		if not existing_footprint.is_empty():
			for cell: Vector2i in existing_footprint:
				if footprint_keys.has(_key(cell.x, cell.y)):
					return true
			continue
		var existing_bounds_value: Variant = existing.get("bounds", Rect2i())
		if existing_bounds_value is Rect2i and bounds.intersects(existing_bounds_value as Rect2i):
			return true
	return false


func _bounds_from_cells(cells: Array[Vector2i]) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var min_cell: Vector2i = cells[0]
	var max_cell: Vector2i = cells[0]
	for cell: Vector2i in cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	return Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)


func _materialize_core_metadata(
	raw_value: Variant,
	main_room_center: Vector2i,
	map_data: WdcMapGenerationTypes.MapData,
	membership: PackedInt32Array,
	region_index: int
) -> Dictionary:
	if not (raw_value is Dictionary):
		return {}
	var raw: Dictionary = raw_value as Dictionary
	var result: Dictionary = {
		"reward_gate_cells": [],
		"reward_object_cells": [],
		"reward_recipe_id": str(raw.get("reward_recipe_id", "")),
	}
	for field_name: String in ["reward_gate_cells", "reward_object_cells"]:
		var values: Variant = raw.get(field_name, [])
		if not (values is Array):
			return {}
		var absolute_cells: Array[Dictionary] = []
		for value: Variant in values as Array:
			var offset: Vector2i = _cell_from_variant(value)
			var absolute_cell: Vector2i = main_room_center + offset
			if (
				not map_data.is_in_bounds(absolute_cell.x, absolute_cell.y)
				or int(membership[absolute_cell.y * map_data.width + absolute_cell.x]) != region_index
			):
				return {}
			absolute_cells.append(_vector2i_to_dict(absolute_cell))
		result[field_name] = absolute_cells
	return result


func _is_four_region_core_metadata_geometry_valid(
	metadata: Dictionary,
	main_room_rect: Rect2i,
	structural_footprint: Array[Vector2i],
	map_data: WdcMapGenerationTypes.MapData,
	membership: PackedInt32Array,
	region_index: int
) -> bool:
	if metadata.is_empty():
		return true
	var footprint_keys: Dictionary = _cell_key_lookup(structural_footprint)
	for gate_value: Variant in metadata.get("reward_gate_cells", []) as Array:
		var gate_cell: Vector2i = _cell_from_variant(gate_value)
		var outward_direction: Vector2i = _main_room_gate_outward_direction(
			gate_cell,
			main_room_rect
		)
		if outward_direction == Vector2i.ZERO or not footprint_keys.has(_key(gate_cell.x, gate_cell.y)):
			return false
		var outside_cell: Vector2i = gate_cell + outward_direction
		if (
			not map_data.is_in_bounds(outside_cell.x, outside_cell.y)
			or int(membership[outside_cell.y * map_data.width + outside_cell.x]) != region_index
		):
			return false
	for object_value: Variant in metadata.get("reward_object_cells", []) as Array:
		var object_cell: Vector2i = _cell_from_variant(object_value)
		if (
			not main_room_rect.has_point(object_cell)
			or not footprint_keys.has(_key(object_cell.x, object_cell.y))
		):
			return false
	return true


func _apply_four_region_core_metadata_geometry(
	map_data: WdcMapGenerationTypes.MapData,
	metadata: Dictionary,
	main_room_rect: Rect2i,
	compat_poi_type: int
) -> void:
	for gate_value: Variant in metadata.get("reward_gate_cells", []) as Array:
		var gate_cell: Vector2i = _cell_from_variant(gate_value)
		var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(gate_cell.x, gate_cell.y)
		if cell == null:
			continue
		cell.cell_type = WdcMapGenerationTypes.CellType.WALL
		cell.poi_type = compat_poi_type
		cell.is_poi_protected = true
		cell.has_mineral = false
		cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.POI_WALL
		cell.trace_type = WdcMapGenerationTypes.PoiType.NONE
		WdcMapGenerationTileRules.refresh_cell_runtime_state(cell)
		var outward_direction: Vector2i = _main_room_gate_outward_direction(
			gate_cell,
			main_room_rect
		)
		if outward_direction != Vector2i.ZERO:
			_carve_site_floor_cell(map_data, gate_cell + outward_direction)
	for object_value: Variant in metadata.get("reward_object_cells", []) as Array:
		var object_cell: Vector2i = _cell_from_variant(object_value)
		var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(object_cell.x, object_cell.y)
		if cell == null:
			continue
		cell.cell_type = WdcMapGenerationTypes.CellType.FLOOR
		cell.poi_type = compat_poi_type
		cell.is_poi_protected = true
		cell.has_mineral = false
		cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.NONE
		cell.trace_type = WdcMapGenerationTypes.PoiType.NONE
		WdcMapGenerationTileRules.refresh_cell_runtime_state(cell)


func _main_room_gate_outward_direction(gate_cell: Vector2i, main_room_rect: Rect2i) -> Vector2i:
	if (
		gate_cell.y == main_room_rect.position.y - 1
		and gate_cell.x >= main_room_rect.position.x
		and gate_cell.x < main_room_rect.end.x
	):
		return Vector2i.UP
	if (
		gate_cell.y == main_room_rect.end.y
		and gate_cell.x >= main_room_rect.position.x
		and gate_cell.x < main_room_rect.end.x
	):
		return Vector2i.DOWN
	if (
		gate_cell.x == main_room_rect.position.x - 1
		and gate_cell.y >= main_room_rect.position.y
		and gate_cell.y < main_room_rect.end.y
	):
		return Vector2i.LEFT
	if (
		gate_cell.x == main_room_rect.end.x
		and gate_cell.y >= main_room_rect.position.y
		and gate_cell.y < main_room_rect.end.y
	):
		return Vector2i.RIGHT
	return Vector2i.ZERO


func _get_four_region_core_padding(
	config: WdcMapGenerationTypes.MapConfig,
	role: String
) -> int:
	var slot: Dictionary = config.region_layout.get(role, {}) as Dictionary
	var profile_id: String = str(slot.get("layout_profile_id", ""))
	var generation_value: Variant = config.get("region_generation")
	if not (generation_value is Dictionary):
		return 0
	var profiles_value: Variant = (generation_value as Dictionary).get("layout_profiles", [])
	if not (profiles_value is Array):
		return 0
	for profile_value: Variant in profiles_value as Array:
		if profile_value is Dictionary and str((profile_value as Dictionary).get("id", "")) == profile_id:
			return maxi(int((profile_value as Dictionary).get("core_poi_padding_cells", 0)), 0)
	return 0


func _four_region_poi_type(role: String, is_core: bool) -> int:
	if is_core and role == WdcMapGenerationTypes.REGION_ROLE_BOSS:
		return WdcMapGenerationTypes.PoiType.LARGE_RUIN
	if role == WdcMapGenerationTypes.REGION_ROLE_HIGH_2:
		return WdcMapGenerationTypes.PoiType.MEDIUM_BIOME
	return WdcMapGenerationTypes.PoiType.SMALL_ORE


func _cells_from_dictionary_array(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not (value is Array):
		return result
	for entry: Variant in value as Array:
		result.append(_cell_from_variant(entry))
	return result


func _cell_from_variant(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Dictionary:
		return Vector2i(int((value as Dictionary).get("x", 0)), int((value as Dictionary).get("y", 0)))
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i.ZERO


func _sample_room_rect(
	map_data: WdcMapGenerationTypes.MapData,
	room_cfg: Dictionary,
	rng: RandomNumberGenerator,
	extra_margin: int = 1
) -> Rect2i:
	var width_min: int = maxi(int(room_cfg.get("width_min", 1)), 1)
	var width_max: int = maxi(int(room_cfg.get("width_max", width_min)), width_min)
	var height_min: int = maxi(int(room_cfg.get("height_min", 1)), 1)
	var height_max: int = maxi(int(room_cfg.get("height_max", height_min)), height_min)
	var room_width: int = rng.randi_range(width_min, width_max)
	var room_height: int = rng.randi_range(height_min, height_max)
	if room_width + extra_margin * 2 >= map_data.width or room_height + extra_margin * 2 >= map_data.height:
		return Rect2i()
	var min_x: int = maxi(extra_margin, 1)
	var min_y: int = maxi(extra_margin, 1)
	var max_x: int = maxi(map_data.width - room_width - extra_margin, min_x)
	var max_y: int = maxi(map_data.height - room_height - extra_margin, min_y)
	var origin_x: int = rng.randi_range(min_x, max_x)
	var origin_y: int = rng.randi_range(min_y, max_y)
	return Rect2i(origin_x, origin_y, room_width, room_height)


func _sample_sub_room_rect(
	map_data: WdcMapGenerationTypes.MapData,
	existing_rooms: Array[Rect2i],
	main_room_rect: Rect2i,
	sub_room_cfg: Dictionary,
	rng: RandomNumberGenerator
) -> Rect2i:
	var attempts: int = maxi(int(sub_room_cfg.get("placement_attempts_per_room", 12)), 12)
	var width_min: int = maxi(int(sub_room_cfg.get("width_min", 1)), 1)
	var width_max: int = maxi(int(sub_room_cfg.get("width_max", width_min)), width_min)
	var height_min: int = maxi(int(sub_room_cfg.get("height_min", 1)), 1)
	var height_max: int = maxi(int(sub_room_cfg.get("height_max", height_min)), height_min)
	var min_gap: int = maxi(int(sub_room_cfg.get("min_gap_from_rooms_cells", 1)), 0)
	var radius_min: int = maxi(int(sub_room_cfg.get("placement_radius_min_cells", 1)), 1)
	var radius_max: int = maxi(int(sub_room_cfg.get("placement_radius_max_cells", radius_min)), radius_min)
	var main_center: Vector2i = _rect_center_cell(main_room_rect)
	var preferred_candidates: Array[Rect2i] = _build_preferred_sub_room_candidates(
		main_room_rect,
		width_min,
		width_max,
		height_min,
		height_max,
		min_gap,
		radius_min,
		rng
	)
	for candidate: Rect2i in preferred_candidates:
		if not _is_room_rect_in_bounds(map_data, candidate):
			continue
		var overlaps_preferred: bool = false
		for existing_room: Rect2i in existing_rooms:
			if _rect_intersects_with_margin(candidate, existing_room, min_gap):
				overlaps_preferred = true
				break
		if not overlaps_preferred:
			return candidate
	for _attempt_idx: int in range(attempts):
		var room_width: int = rng.randi_range(width_min, width_max)
		var room_height: int = rng.randi_range(height_min, height_max)
		var radius: float = float(rng.randi_range(radius_min, radius_max))
		var angle: float = rng.randf() * TAU
		var center_x: int = int(roundf(float(main_center.x) + cos(angle) * radius))
		var center_y: int = int(roundf(float(main_center.y) + sin(angle) * radius))
		var candidate: Rect2i = Rect2i(
			center_x - int(floor(room_width * 0.5)),
			center_y - int(floor(room_height * 0.5)),
			room_width,
			room_height
		)
		if not _is_room_rect_in_bounds(map_data, candidate):
			continue
		var overlaps: bool = false
		for existing_room: Rect2i in existing_rooms:
			if _rect_intersects_with_margin(candidate, existing_room, min_gap):
				overlaps = true
				break
		if overlaps:
			continue
		return candidate
	return Rect2i()


func _build_preferred_sub_room_candidates(
	main_room_rect: Rect2i,
	width_min: int,
	width_max: int,
	height_min: int,
	height_max: int,
	min_gap: int,
	radius_min: int,
	rng: RandomNumberGenerator
) -> Array[Rect2i]:
	var candidates: Array[Rect2i] = []
	var sub_room_width: int = rng.randi_range(width_min, width_max)
	var sub_room_height: int = rng.randi_range(height_min, height_max)
	var horizontal_offset: int = int(ceili(main_room_rect.size.x * 0.5)) + int(ceili(sub_room_width * 0.5)) + min_gap + radius_min
	var vertical_offset: int = int(ceili(main_room_rect.size.y * 0.5)) + int(ceili(sub_room_height * 0.5)) + min_gap + radius_min
	var center: Vector2i = _rect_center_cell(main_room_rect)
	candidates.append(
		Rect2i(
			center.x + horizontal_offset - int(floor(sub_room_width * 0.5)),
			center.y - int(floor(sub_room_height * 0.5)),
			sub_room_width,
			sub_room_height
		)
	)
	candidates.append(
		Rect2i(
			center.x - horizontal_offset - int(floor(sub_room_width * 0.5)),
			center.y - int(floor(sub_room_height * 0.5)),
			sub_room_width,
			sub_room_height
		)
	)
	candidates.append(
		Rect2i(
			center.x - int(floor(sub_room_width * 0.5)),
			center.y + vertical_offset - int(floor(sub_room_height * 0.5)),
			sub_room_width,
			sub_room_height
		)
	)
	candidates.append(
		Rect2i(
			center.x - int(floor(sub_room_width * 0.5)),
			center.y - vertical_offset - int(floor(sub_room_height * 0.5)),
			sub_room_width,
			sub_room_height
		)
	)
	return candidates


func _build_poi_connectivity_edges(
	rooms: Array[Rect2i],
	template_dict: Dictionary,
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	if rooms.size() <= 1:
		return []
	var connectivity: Dictionary = template_dict.get("connectivity", {}) as Dictionary
	var neighbor_limit: int = maxi(int(connectivity.get("candidate_neighbors_per_room", 2)), 1)
	var candidate_edges: Array[Dictionary] = []
	var seen_keys: Dictionary = {}
	for room_index: int in range(rooms.size()):
		var room_distances: Array[Dictionary] = []
		var center_a: Vector2i = _rect_center_cell(rooms[room_index])
		for other_index: int in range(rooms.size()):
			if room_index == other_index:
				continue
			var center_b: Vector2i = _rect_center_cell(rooms[other_index])
			room_distances.append({
				"from": room_index,
				"to": other_index,
				"distance": abs(center_a.x - center_b.x) + abs(center_a.y - center_b.y),
			})
		room_distances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("distance", 0)) < int(b.get("distance", 0))
		)
		for neighbor_idx: int in range(mini(neighbor_limit, room_distances.size())):
			var edge: Dictionary = room_distances[neighbor_idx]
			var edge_key: String = _edge_key(int(edge.get("from", 0)), int(edge.get("to", 0)))
			if seen_keys.has(edge_key):
				continue
			seen_keys[edge_key] = true
			candidate_edges.append(edge)
	_ensure_candidate_edge_connectivity(rooms, candidate_edges, seen_keys)
	var mst_edges: Array[Dictionary] = _build_mst_edges(rooms.size(), candidate_edges)
	var selected_keys: Dictionary = {}
	for edge: Dictionary in mst_edges:
		selected_keys[_edge_key(int(edge.get("from", 0)), int(edge.get("to", 0)))] = true
	var extra_edges: Array[Dictionary] = []
	var extra_chance: float = clampf(float(connectivity.get("extra_connection_chance", 0.0)), 0.0, 1.0)
	var max_extra_connections: int = maxi(int(connectivity.get("max_extra_connections", 0)), 0)
	if max_extra_connections > 0 and extra_chance > 0.0:
		var extra_candidates: Array[Dictionary] = []
		for edge: Dictionary in candidate_edges:
			var edge_key: String = _edge_key(int(edge.get("from", 0)), int(edge.get("to", 0)))
			if selected_keys.has(edge_key):
				continue
			extra_candidates.append(edge)
		# 派生局部洗牌流但不推进主 RNG，保持 legacy 后续随机序列不变。
		var shuffle_rng := RandomNumberGenerator.new()
		shuffle_rng.seed = rng.state
		_shuffle_dictionary_array(extra_candidates, shuffle_rng)
		for edge: Dictionary in extra_candidates:
			if extra_edges.size() >= max_extra_connections:
				break
			if rng.randf() > extra_chance:
				continue
			extra_edges.append(edge)
	return mst_edges + extra_edges


func _ensure_candidate_edge_connectivity(
	rooms: Array[Rect2i],
	candidate_edges: Array[Dictionary],
	seen_keys: Dictionary
) -> void:
	if rooms.size() <= 1:
		return
	for room_index: int in range(rooms.size() - 1):
		var next_index: int = room_index + 1
		var edge_key: String = _edge_key(room_index, next_index)
		if seen_keys.has(edge_key):
			continue
		var center_a: Vector2i = _rect_center_cell(rooms[room_index])
		var center_b: Vector2i = _rect_center_cell(rooms[next_index])
		candidate_edges.append({
			"from": room_index,
			"to": next_index,
			"distance": abs(center_a.x - center_b.x) + abs(center_a.y - center_b.y),
		})
		seen_keys[edge_key] = true


func _build_mst_edges(room_count: int, candidate_edges: Array[Dictionary]) -> Array[Dictionary]:
	var sorted_edges: Array[Dictionary] = []
	for edge: Dictionary in candidate_edges:
		sorted_edges.append(edge.duplicate(true))
	sorted_edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("distance", 0)) < int(b.get("distance", 0))
	)
	var parent: Array[int] = []
	parent.resize(room_count)
	for room_index: int in range(room_count):
		parent[room_index] = room_index
	var mst_edges: Array[Dictionary] = []
	for edge: Dictionary in sorted_edges:
		var from_index: int = int(edge.get("from", 0))
		var to_index: int = int(edge.get("to", 0))
		var root_a: int = _find_set_root(parent, from_index)
		var root_b: int = _find_set_root(parent, to_index)
		if root_a == root_b:
			continue
		parent[root_b] = root_a
		mst_edges.append(edge)
		if mst_edges.size() >= room_count - 1:
			break
	return mst_edges


func _find_set_root(parent: Array[int], node_index: int) -> int:
	var root: int = node_index
	while parent[root] != root:
		root = parent[root]
	return root


func _build_corridor_plans_for_edges(
	rooms: Array[Rect2i],
	edges: Array[Dictionary],
	template_dict: Dictionary
) -> Array[Dictionary]:
	var corridor_plans: Array[Dictionary] = []
	for edge: Dictionary in edges:
		var from_index: int = int(edge.get("from", 0))
		var to_index: int = int(edge.get("to", 0))
		if from_index < 0 or from_index >= rooms.size() or to_index < 0 or to_index >= rooms.size():
			return []
		var corridor_plan: Dictionary = _build_corridor_plan_between_rooms(
			rooms[from_index],
			rooms[to_index],
			template_dict
		)
		if corridor_plan.is_empty():
			return []
		corridor_plan["from_room"] = from_index
		corridor_plan["to_room"] = to_index
		corridor_plans.append(corridor_plan)
	return corridor_plans


func _collect_unique_corridor_cells(corridor_plans: Array[Dictionary]) -> Array[Vector2i]:
	var cells_by_key: Dictionary = {}
	for corridor_plan: Dictionary in corridor_plans:
		var corridor_cells: Array = corridor_plan.get("cells", []) as Array
		for cell_value: Variant in corridor_cells:
			if not (cell_value is Vector2i):
				continue
			var cell: Vector2i = cell_value as Vector2i
			cells_by_key[_key(cell.x, cell.y)] = cell
	var cells: Array[Vector2i] = []
	for cell_value: Variant in cells_by_key.values():
		if cell_value is Vector2i:
			cells.append(cell_value as Vector2i)
	return cells


func _build_corridor_plan_between_rooms(
	room_a: Rect2i,
	room_b: Rect2i,
	template_dict: Dictionary
) -> Dictionary:
	var corridor_cfg: Dictionary = template_dict.get("corridor", {}) as Dictionary
	var retry_count: int = maxi(int(corridor_cfg.get("retry_doorway_count", 1)), 1)
	for _retry_idx: int in range(retry_count):
		var doorway_pair: Dictionary = _select_corridor_doorway_pair(room_a, room_b, corridor_cfg)
		var cells: Array[Vector2i] = _build_l_shaped_corridor(
			doorway_pair.get("from", Vector2i.ZERO) as Vector2i,
			doorway_pair.get("to", Vector2i.ZERO) as Vector2i,
			maxi(int(corridor_cfg.get("width_cells", 1)), 1),
			str(corridor_cfg.get("bend_order_mode", "random"))
		)
		if not cells.is_empty():
			return {
				"from_door": doorway_pair.get("from", Vector2i.ZERO),
				"to_door": doorway_pair.get("to", Vector2i.ZERO),
				"cells": cells,
			}
	return {}


func _select_corridor_doorway_pair(
	room_a: Rect2i,
	room_b: Rect2i,
	corridor_cfg: Dictionary
) -> Dictionary:
	var center_a: Vector2i = _rect_center_cell(room_a)
	var center_b: Vector2i = _rect_center_cell(room_b)
	var margin: int = maxi(int(corridor_cfg.get("door_margin_from_corner_cells", 1)), 0)
	var from_cell: Vector2i = center_a
	var to_cell: Vector2i = center_b
	var delta_x: int = center_b.x - center_a.x
	var delta_y: int = center_b.y - center_a.y
	if abs(delta_x) >= abs(delta_y):
		from_cell = _doorway_on_horizontal_side(room_a, delta_x >= 0, center_b.y, margin)
		to_cell = _doorway_on_horizontal_side(room_b, delta_x < 0, center_a.y, margin)
	else:
		from_cell = _doorway_on_vertical_side(room_a, delta_y >= 0, center_b.x, margin)
		to_cell = _doorway_on_vertical_side(room_b, delta_y < 0, center_a.x, margin)
	return {
		"from": from_cell,
		"to": to_cell,
	}


func _doorway_on_horizontal_side(
	room_rect: Rect2i,
	use_right_side: bool,
	preferred_y: int,
	margin: int
) -> Vector2i:
	var min_y: int = room_rect.position.y + margin
	var max_y: int = room_rect.position.y + room_rect.size.y - 1 - margin
	if min_y > max_y:
		min_y = room_rect.position.y
		max_y = room_rect.position.y + room_rect.size.y - 1
	var resolved_y: int = clampi(preferred_y, min_y, max_y)
	var resolved_x: int = room_rect.position.x + room_rect.size.x - 1 if use_right_side else room_rect.position.x
	return Vector2i(resolved_x, resolved_y)


func _doorway_on_vertical_side(
	room_rect: Rect2i,
	use_bottom_side: bool,
	preferred_x: int,
	margin: int
) -> Vector2i:
	var min_x: int = room_rect.position.x + margin
	var max_x: int = room_rect.position.x + room_rect.size.x - 1 - margin
	if min_x > max_x:
		min_x = room_rect.position.x
		max_x = room_rect.position.x + room_rect.size.x - 1
	var resolved_x: int = clampi(preferred_x, min_x, max_x)
	var resolved_y: int = room_rect.position.y + room_rect.size.y - 1 if use_bottom_side else room_rect.position.y
	return Vector2i(resolved_x, resolved_y)


func _build_l_shaped_corridor(
	from_cell: Vector2i,
	to_cell: Vector2i,
	width_cells: int,
	bend_order_mode: String
) -> Array[Vector2i]:
	var horizontal_first: bool = true
	if bend_order_mode == "vertical_first":
		horizontal_first = false
	elif bend_order_mode == "random":
		horizontal_first = abs(from_cell.x - to_cell.x) >= abs(from_cell.y - to_cell.y)
	var cells: Array[Vector2i] = []
	var corridor_radius: int = maxi(int(floor(float(width_cells - 1) * 0.5)), 0)
	if horizontal_first:
		_append_corridor_line(cells, from_cell, Vector2i(to_cell.x, from_cell.y), corridor_radius)
		_append_corridor_line(cells, Vector2i(to_cell.x, from_cell.y), to_cell, corridor_radius)
	else:
		_append_corridor_line(cells, from_cell, Vector2i(from_cell.x, to_cell.y), corridor_radius)
		_append_corridor_line(cells, Vector2i(from_cell.x, to_cell.y), to_cell, corridor_radius)
	return cells


func _append_corridor_line(
	cells: Array[Vector2i],
	from_cell: Vector2i,
	to_cell: Vector2i,
	radius: int
) -> void:
	if from_cell.x == to_cell.x:
		var start_y: int = mini(from_cell.y, to_cell.y)
		var end_y: int = maxi(from_cell.y, to_cell.y)
		for y: int in range(start_y, end_y + 1):
			for x: int in range(from_cell.x - radius, from_cell.x + radius + 1):
				cells.append(Vector2i(x, y))
	else:
		var start_x: int = mini(from_cell.x, to_cell.x)
		var end_x: int = maxi(from_cell.x, to_cell.x)
		for x: int in range(start_x, end_x + 1):
			for y: int in range(from_cell.y - radius, from_cell.y + radius + 1):
				cells.append(Vector2i(x, y))


func _carve_poi_rooms_and_corridors(
	map_data: WdcMapGenerationTypes.MapData,
	rooms: Array[Rect2i],
	corridor_cells: Array[Vector2i],
	compat_poi_type: int
) -> void:
	for room_rect: Rect2i in rooms:
		_carve_room_rect(map_data, room_rect, compat_poi_type)
	for corridor_cell: Vector2i in corridor_cells:
		if not map_data.is_in_bounds(corridor_cell.x, corridor_cell.y):
			continue
		var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(corridor_cell.x, corridor_cell.y)
		if cell == null:
			continue
		cell.cell_type = WdcMapGenerationTypes.CellType.FLOOR
		cell.poi_type = compat_poi_type
		cell.is_poi_protected = true


func _carve_room_rect(
	map_data: WdcMapGenerationTypes.MapData,
	room_rect: Rect2i,
	compat_poi_type: int
) -> void:
	for y: int in range(room_rect.position.y, room_rect.position.y + room_rect.size.y):
		for x: int in range(room_rect.position.x, room_rect.position.x + room_rect.size.x):
			if not map_data.is_in_bounds(x, y):
				continue
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			cell.cell_type = WdcMapGenerationTypes.CellType.FLOOR
			cell.poi_type = compat_poi_type
			cell.is_poi_protected = true


func _place_poi_outer_walls(
	map_data: WdcMapGenerationTypes.MapData,
	rooms: Array[Rect2i],
	corridor_cells: Array[Vector2i],
	compat_poi_type: int
) -> void:
	var interior_keys: Dictionary = {}
	for room_rect: Rect2i in rooms:
		for y: int in range(room_rect.position.y, room_rect.position.y + room_rect.size.y):
			for x: int in range(room_rect.position.x, room_rect.position.x + room_rect.size.x):
				interior_keys[_key(x, y)] = true
	for corridor_cell: Vector2i in corridor_cells:
		interior_keys[_key(corridor_cell.x, corridor_cell.y)] = true
	var shell_cells: Array[Vector2i] = []
	var shell_keys: Dictionary = {}
	for room_rect: Rect2i in rooms:
		for y: int in range(room_rect.position.y - 1, room_rect.position.y + room_rect.size.y + 1):
			for x: int in range(room_rect.position.x - 1, room_rect.position.x + room_rect.size.x + 1):
				var key: String = _key(x, y)
				if interior_keys.has(key) or shell_keys.has(key):
					continue
				if not map_data.is_in_bounds(x, y):
					continue
				shell_keys[key] = true
				shell_cells.append(Vector2i(x, y))
	for corridor_cell: Vector2i in corridor_cells:
		for offset_y: int in range(-1, 2):
			for offset_x: int in range(-1, 2):
				var x: int = corridor_cell.x + offset_x
				var y: int = corridor_cell.y + offset_y
				var key: String = _key(x, y)
				if interior_keys.has(key) or shell_keys.has(key):
					continue
				if not map_data.is_in_bounds(x, y):
					continue
				shell_keys[key] = true
				shell_cells.append(Vector2i(x, y))
	for shell_cell: Vector2i in shell_cells:
		var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(shell_cell.x, shell_cell.y)
		if cell == null:
			continue
		cell.cell_type = WdcMapGenerationTypes.CellType.WALL
		cell.poi_type = compat_poi_type
		cell.is_poi_protected = true
		cell.has_mineral = false
		cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.POI_WALL


func _compute_total_poi_bounds(
	rooms: Array[Rect2i],
	corridor_cells: Array[Vector2i],
	placement_cfg: Dictionary
) -> Rect2i:
	var min_x: int = 1 << 30
	var min_y: int = 1 << 30
	var max_x: int = -(1 << 30)
	var max_y: int = -(1 << 30)
	for room_rect: Rect2i in rooms:
		min_x = mini(min_x, room_rect.position.x)
		min_y = mini(min_y, room_rect.position.y)
		max_x = maxi(max_x, room_rect.position.x + room_rect.size.x - 1)
		max_y = maxi(max_y, room_rect.position.y + room_rect.size.y - 1)
	for corridor_cell: Vector2i in corridor_cells:
		min_x = mini(min_x, corridor_cell.x)
		min_y = mini(min_y, corridor_cell.y)
		max_x = maxi(max_x, corridor_cell.x)
		max_y = maxi(max_y, corridor_cell.y)
	var padding: int = maxi(int(placement_cfg.get("footprint_padding_cells", 0)), 0)
	return Rect2i(
		min_x - padding,
		min_y - padding,
		(max_x - min_x + 1) + padding * 2,
		(max_y - min_y + 1) + padding * 2
	)


func _is_poi_bounds_valid(map_data: WdcMapGenerationTypes.MapData, bounds: Rect2i) -> bool:
	return (
		bounds.position.x >= 0
		and bounds.position.y >= 0
		and bounds.position.x + bounds.size.x <= map_data.width
		and bounds.position.y + bounds.size.y <= map_data.height
	)


func _is_room_rect_in_bounds(map_data: WdcMapGenerationTypes.MapData, room_rect: Rect2i) -> bool:
	return (
		room_rect.size.x > 0
		and room_rect.size.y > 0
		and room_rect.position.x >= 1
		and room_rect.position.y >= 1
		and room_rect.position.x + room_rect.size.x < map_data.width
		and room_rect.position.y + room_rect.size.y < map_data.height
	)


func _rect_intersects_with_margin(rect_a: Rect2i, rect_b: Rect2i, margin: int) -> bool:
	var expanded_b: Rect2i = Rect2i(
		rect_b.position.x - margin,
		rect_b.position.y - margin,
		rect_b.size.x + margin * 2,
		rect_b.size.y + margin * 2
	)
	return rect_a.intersects(expanded_b)


func _rect_center_cell(room_rect: Rect2i) -> Vector2i:
	return Vector2i(
		room_rect.position.x + int(floor(room_rect.size.x * 0.5)),
		room_rect.position.y + int(floor(room_rect.size.y * 0.5))
	)


func _rect_cells(room_rect: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if room_rect.size.x <= 0 or room_rect.size.y <= 0:
		return cells
	for y: int in range(room_rect.position.y, room_rect.position.y + room_rect.size.y):
		for x: int in range(room_rect.position.x, room_rect.position.x + room_rect.size.x):
			cells.append(Vector2i(x, y))
	return cells


func _rect_to_dict(room_rect: Rect2i) -> Dictionary:
	return {
		"x": room_rect.position.x,
		"y": room_rect.position.y,
		"width": room_rect.size.x,
		"height": room_rect.size.y,
	}


func _rect_array_to_dict_array(rooms: Array) -> Array[Dictionary]:
	var dicts: Array[Dictionary] = []
	for room_value: Variant in rooms:
		if room_value is Rect2i:
			dicts.append(_rect_to_dict(room_value as Rect2i))
	return dicts


func _vector2i_array_to_dict_array(cells: Array[Vector2i]) -> Array[Dictionary]:
	var dicts: Array[Dictionary] = []
	for cell: Vector2i in cells:
		dicts.append({
			"x": cell.x,
			"y": cell.y,
		})
	return dicts


func _corridor_plans_to_dict_array(corridor_plans: Array[Dictionary]) -> Array[Dictionary]:
	var dicts: Array[Dictionary] = []
	for corridor_plan: Dictionary in corridor_plans:
		dicts.append({
			"from_room": int(corridor_plan.get("from_room", -1)),
			"to_room": int(corridor_plan.get("to_room", -1)),
			"from_door": _vector2i_to_dict(corridor_plan.get("from_door", Vector2i.ZERO) as Vector2i),
			"to_door": _vector2i_to_dict(corridor_plan.get("to_door", Vector2i.ZERO) as Vector2i),
			"cells": _vector2i_array_to_dict_array(_extract_vector2i_array(corridor_plan.get("cells", []))),
		})
	return dicts


func _room_content_plan_array_to_dict_array(plans: Array[Dictionary]) -> Array[Dictionary]:
	var dicts: Array[Dictionary] = []
	for plan: Dictionary in plans:
		var converted: Dictionary = plan.duplicate(true)
		var anchor_cell: Vector2i = converted.get("anchor_cell", Vector2i.ZERO) as Vector2i
		converted["anchor_cell"] = _vector2i_to_dict(anchor_cell)
		if converted.get("room_rect", null) is Rect2i:
			converted["room_rect"] = _rect_to_dict(converted.get("room_rect", Rect2i()) as Rect2i)
		if converted.get("chest_cell", null) is Vector2i:
			converted["chest_cell"] = _vector2i_to_dict(
				converted.get("chest_cell", Vector2i.ZERO) as Vector2i
			)
		if converted.get("guard_sites", null) is Array:
			converted["guard_sites"] = _guard_site_array_to_dict_array(
				converted.get("guard_sites", []) as Array
			)
		dicts.append(converted)
	return dicts


func _append_room_content_sites(
	map_data: WdcMapGenerationTypes.MapData,
	room_content_plans: Array[Dictionary],
	config: WdcMapGenerationTypes.MapConfig,
	poi_template_id: String = ""
) -> void:
	var isolated_templates: Array[Dictionary] = _extract_dictionary_array(
		config.get_meta("isolated_spawn_templates", [])
	)
	var nest_templates: Array[Dictionary] = _extract_dictionary_array(
		config.get_meta("nest_templates", [])
	)
	for plan: Dictionary in room_content_plans:
		var content_kind: String = str(plan.get("content_kind", "none"))
		if content_kind == "none":
			continue
		var template_id: String = str(plan.get("template_id", ""))
		var anchor_cell: Vector2i = plan.get("anchor_cell", Vector2i.ZERO) as Vector2i
		if content_kind == "monster_pack":
			if template_id.is_empty():
				continue
			var spawn_template: Dictionary = _find_template_by_id(isolated_templates, template_id)
			if spawn_template.is_empty():
				continue
			map_data.monster_sites.append({
				"site_kind": "isolated",
				"room_kind": str(plan.get("room_kind", "")),
				"cell": anchor_cell,
				"template_id": template_id,
				"monster_id": str(spawn_template.get("monster_id", "")),
				"layer_id": str(plan.get("layer_id", "")),
			})
		elif content_kind == "nest":
			if template_id.is_empty():
				continue
			var nest_template: Dictionary = _find_template_by_id(nest_templates, template_id)
			if nest_template.is_empty():
				continue
			map_data.monster_sites.append({
				"site_kind": "nest",
				"room_kind": str(plan.get("room_kind", "")),
				"cell": anchor_cell,
				"template_id": template_id,
				"nest_unit_id": str(nest_template.get("nest_unit_id", "")),
				"monster_id": str(nest_template.get("monster_id", "")),
				"loot_table_id": str(nest_template.get("loot_table_id", "")),
				"activation_radius_m": float(nest_template.get("activation_radius_m", 0.0)),
				"spawn_interval_sec": float(nest_template.get("spawn_interval_sec", 0.0)),
				"max_alive_children": int(nest_template.get("max_alive_children", 0)),
				"max_hit_points": int(nest_template.get("max_hit_points", 0)),
				"layer_id": str(plan.get("layer_id", "")),
			})
		elif content_kind == "locked_treasure_camp":
			_append_camp_encounter(map_data, plan, poi_template_id)


func _append_camp_encounter(
	map_data: WdcMapGenerationTypes.MapData,
	plan: Dictionary,
	poi_template_id: String
) -> void:
	var encounter_id: String = str(plan.get("encounter_id", ""))
	if encounter_id.is_empty():
		encounter_id = "camp_%03d" % (map_data.camp_encounters.size() + 1)
	var room_rect_value: Variant = plan.get("room_rect", Rect2i())
	var room_rect: Rect2i = room_rect_value as Rect2i if room_rect_value is Rect2i else Rect2i()
	var chest_cell: Vector2i = plan.get("chest_cell", plan.get("anchor_cell", Vector2i.ZERO)) as Vector2i
	map_data.camp_encounters.append({
		"encounter_id": encounter_id,
		"poi_template_id": poi_template_id,
		"layer_id": str(plan.get("layer_id", "")),
		"room_index": int(plan.get("room_index", -1)),
		"room_kind": str(plan.get("room_kind", "")),
		"room_rect": _rect_to_dict(room_rect),
		"chest_cell": _vector2i_to_dict(chest_cell),
		"guard_sites": _guard_site_array_to_dict_array(plan.get("guard_sites", []) as Array),
		"loot_container": (plan.get("loot_container", {}) as Dictionary).duplicate(true),
		"locked_prompt_text": str(
			plan.get("locked_prompt_text", "需要击败房间中的所有怪物")
		),
	})


func _guard_site_array_to_dict_array(guard_sites: Array) -> Array[Dictionary]:
	var dicts: Array[Dictionary] = []
	for site_value: Variant in guard_sites:
		if not (site_value is Dictionary):
			continue
		var site: Dictionary = (site_value as Dictionary).duplicate(true)
		if site.get("cell", null) is Vector2i:
			site["cell"] = _vector2i_to_dict(site.get("cell", Vector2i.ZERO) as Vector2i)
		dicts.append(site)
	return dicts


func _vector2i_to_dict(cell: Vector2i) -> Dictionary:
	return {
		"x": cell.x,
		"y": cell.y,
	}


func _find_template_by_id(templates: Array[Dictionary], template_id: String) -> Dictionary:
	for template_dict: Dictionary in templates:
		if str(template_dict.get("id", "")) == template_id:
			return template_dict.duplicate(true)
	return {}


func _extract_vector2i_array(values: Variant) -> Array[Vector2i]:
	var extracted: Array[Vector2i] = []
	if not (values is Array):
		return extracted
	for value: Variant in values:
		if value is Vector2i:
			extracted.append(value as Vector2i)
	return extracted


func _extract_dictionary_array(values: Variant) -> Array[Dictionary]:
	var extracted: Array[Dictionary] = []
	if not (values is Array):
		return extracted
	for value: Variant in values:
		if value is Dictionary:
			extracted.append((value as Dictionary).duplicate(true))
	return extracted


func _edge_key(index_a: int, index_b: int) -> String:
	var min_index: int = mini(index_a, index_b)
	var max_index: int = maxi(index_a, index_b)
	return "%d-%d" % [min_index, max_index]


func _build_main_room_torch_sites(
	main_room_rect: Rect2i,
	template_dict: Dictionary
) -> Array[Vector2i]:
	var torch_cfg: Dictionary = template_dict.get("torch", {}) as Dictionary
	if not bool(torch_cfg.get("enabled", false)):
		return []
	var inset: int = maxi(int(torch_cfg.get("wall_inset_cells", 1)), 0)
	var max_count: int = maxi(int(torch_cfg.get("max_torch_count", 0)), 0)
	if max_count <= 0:
		return []
	var candidates: Array[Vector2i] = []
	candidates.append(Vector2i(main_room_rect.position.x + inset, main_room_rect.position.y + inset))
	candidates.append(
		Vector2i(
			main_room_rect.position.x + main_room_rect.size.x - 1 - inset,
			main_room_rect.position.y + inset
		)
	)
	candidates.append(
		Vector2i(
			main_room_rect.position.x + inset,
			main_room_rect.position.y + main_room_rect.size.y - 1 - inset
		)
	)
	candidates.append(
		Vector2i(
			main_room_rect.position.x + main_room_rect.size.x - 1 - inset,
			main_room_rect.position.y + main_room_rect.size.y - 1 - inset
		)
	)
	if main_room_rect.size.x >= 10:
		candidates.append(
			Vector2i(_rect_center_cell(main_room_rect).x, main_room_rect.position.y + inset)
		)
		candidates.append(
			Vector2i(
				_rect_center_cell(main_room_rect).x,
				main_room_rect.position.y + main_room_rect.size.y - 1 - inset
			)
		)
	if main_room_rect.size.y >= 10:
		candidates.append(
			Vector2i(main_room_rect.position.x + inset, _rect_center_cell(main_room_rect).y)
		)
		candidates.append(
			Vector2i(
				main_room_rect.position.x + main_room_rect.size.x - 1 - inset,
				_rect_center_cell(main_room_rect).y
			)
		)
	var unique_by_key: Dictionary = {}
	for candidate: Vector2i in candidates:
		if _is_cell_inside_rect(candidate, main_room_rect):
			unique_by_key[_key(candidate.x, candidate.y)] = candidate
	var torch_sites: Array[Vector2i] = []
	for cell_value: Variant in unique_by_key.values():
		if cell_value is Vector2i:
			torch_sites.append(cell_value as Vector2i)
	if torch_sites.size() > max_count:
		torch_sites.resize(max_count)
	return torch_sites


func _build_room_content_plans(
	rooms: Array[Rect2i],
	corridor_plans: Array[Dictionary],
	template_dict: Dictionary,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var content: Dictionary = template_dict.get("content", {}) as Dictionary
	var main_cfg: Dictionary = content.get("main_room_roll", {}) as Dictionary
	var sub_cfg: Dictionary = content.get("sub_room_roll", {}) as Dictionary
	var center_cluster_cfg: Dictionary = content.get("center_ore_cluster", {}) as Dictionary
	var plans: Array[Dictionary] = []
	for room_index: int in range(rooms.size()):
		var room_rect: Rect2i = rooms[room_index]
		var room_cfg: Dictionary = main_cfg if room_index == 0 else sub_cfg
		var room_kind: String = "main" if room_index == 0 else "sub"
		var door_cells: Array[Vector2i] = _collect_room_door_cells(room_index, corridor_plans)
		var plan: Dictionary = _roll_room_content_plan(
			room_index,
			room_kind,
			room_rect,
			room_cfg,
			center_cluster_cfg if room_index == 0 else {},
			door_cells,
			config,
			rng
		)
		plans.append(plan)
	return plans


func _has_invalid_room_content_plan(plans: Array[Dictionary]) -> bool:
	for plan: Dictionary in plans:
		if bool(plan.get("invalid", false)):
			return true
	return false


func _collect_room_door_cells(room_index: int, corridor_plans: Array[Dictionary]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for corridor_plan: Dictionary in corridor_plans:
		if int(corridor_plan.get("from_room", -1)) == room_index:
			cells.append(corridor_plan.get("from_door", Vector2i.ZERO) as Vector2i)
		if int(corridor_plan.get("to_room", -1)) == room_index:
			cells.append(corridor_plan.get("to_door", Vector2i.ZERO) as Vector2i)
	return cells


func _roll_room_content_plan(
	room_index: int,
	room_kind: String,
	room_rect: Rect2i,
	room_cfg: Dictionary,
	center_cluster_cfg: Dictionary,
	door_cells: Array[Vector2i],
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> Dictionary:
	var none_weight: float = maxf(float(room_cfg.get("none_weight", 0.0)), 0.0)
	var monster_entries: Array = room_cfg.get("monster_entries", []) as Array
	var nest_entries: Array = room_cfg.get("nest_entries", []) as Array
	var camp_entries: Array = room_cfg.get("camp_entries", []) as Array
	var monster_weight_total: float = _sum_entry_weights(monster_entries)
	var nest_weight_total: float = _sum_entry_weights(nest_entries)
	var camp_weight_total: float = _sum_entry_weights(camp_entries)
	var layer: Dictionary = _resolve_layer_for_rect_center(config, null, room_rect)
	var danger_multiplier: float = maxf(
		float(layer.get("room_content_danger_multiplier", 1.0)),
		0.0
	)
	if danger_multiplier > 0.0:
		monster_weight_total *= danger_multiplier
		nest_weight_total *= danger_multiplier
		camp_weight_total *= danger_multiplier
		none_weight = none_weight / danger_multiplier
	var total_weight: float = none_weight + monster_weight_total + nest_weight_total + camp_weight_total
	var content_kind: String = "none"
	var template_id: String = ""
	var camp_entry: Dictionary = {}
	if total_weight > 0.0:
		var roll: float = rng.randf() * total_weight
		if roll <= none_weight:
			content_kind = "none"
		elif roll <= none_weight + monster_weight_total:
			content_kind = "monster_pack"
			template_id = _pick_weighted_entry_id(monster_entries, "spawn_template_id", rng)
		elif roll <= none_weight + monster_weight_total + nest_weight_total:
			content_kind = "nest"
			template_id = _pick_weighted_entry_id(nest_entries, "nest_template_id", rng)
		else:
			content_kind = "locked_treasure_camp"
			camp_entry = _pick_weighted_entry(camp_entries, rng)
			template_id = str(camp_entry.get("id", ""))
	var anchor_cell: Vector2i = _resolve_room_content_anchor(
		room_rect,
		door_cells,
		maxi(int(room_cfg.get("min_distance_from_door_cells", 0)), 0),
		maxi(int(center_cluster_cfg.get("avoid_radius_cells", 0)), 0),
		room_kind == "main"
	)
	var plan: Dictionary = {
		"room_index": room_index,
		"room_kind": room_kind,
		"room_rect": room_rect,
		"content_kind": content_kind,
		"template_id": template_id,
		"anchor_cell": anchor_cell,
		"layer_id": str(layer.get("id", "")),
	}
	if content_kind == "locked_treasure_camp":
		_apply_locked_treasure_camp_plan(
			plan,
			room_rect,
			door_cells,
			room_cfg,
			camp_entry,
			config,
			rng
		)
	return plan


func _sum_entry_weights(entries: Array) -> float:
	var total_weight: float = 0.0
	for entry_value: Variant in entries:
		if not (entry_value is Dictionary):
			continue
		total_weight += maxf(float((entry_value as Dictionary).get("weight", 0.0)), 0.0)
	return total_weight


func _pick_weighted_entry_id(
	entries: Array,
	id_key: String,
	rng: RandomNumberGenerator
) -> String:
	var total_weight: float = _sum_entry_weights(entries)
	if total_weight <= 0.0:
		return ""
	var roll: float = rng.randf() * total_weight
	var cumulative: float = 0.0
	for entry_value: Variant in entries:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value as Dictionary
		cumulative += maxf(float(entry.get("weight", 0.0)), 0.0)
		if roll <= cumulative:
			return str(entry.get(id_key, ""))
	return ""


func _pick_weighted_entry(entries: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total_weight: float = _sum_entry_weights(entries)
	if total_weight <= 0.0:
		return {}
	var roll: float = rng.randf() * total_weight
	var cumulative: float = 0.0
	for entry_value: Variant in entries:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value as Dictionary
		cumulative += maxf(float(entry.get("weight", 0.0)), 0.0)
		if roll <= cumulative:
			return entry.duplicate(true)
	return {}


func _apply_locked_treasure_camp_plan(
	plan: Dictionary,
	room_rect: Rect2i,
	door_cells: Array[Vector2i],
	room_cfg: Dictionary,
	camp_entry: Dictionary,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	if camp_entry.is_empty():
		plan["invalid"] = true
		return
	var chest_cell: Vector2i = _rect_center_cell(room_rect)
	var guard_count_min: int = maxi(int(camp_entry.get("guard_count_min", 1)), 1)
	var guard_count_max: int = maxi(
		int(camp_entry.get("guard_count_max", guard_count_min)),
		guard_count_min
	)
	var guard_count: int = rng.randi_range(guard_count_min, guard_count_max)
	var chest_avoid_radius: int = maxi(int(camp_entry.get("chest_avoid_radius_cells", 1)), 0)
	var min_distance_from_doors: int = maxi(
		int(
			camp_entry.get(
				"min_distance_from_door_cells",
				room_cfg.get("min_distance_from_door_cells", 0)
			)
		),
		0
	)
	var guard_cells: Array[Vector2i] = _pick_camp_guard_cells(
		room_rect,
		door_cells,
		chest_cell,
		min_distance_from_doors,
		chest_avoid_radius,
		guard_count,
		rng
	)
	if guard_cells.size() < guard_count_min:
		plan["invalid"] = true
		return
	guard_count = mini(guard_count, guard_cells.size())
	var guard_entries: Array = camp_entry.get("guard_entries", []) as Array
	var isolated_templates: Array[Dictionary] = _extract_dictionary_array(
		config.get_meta("isolated_spawn_templates", [])
	)
	var guard_sites: Array[Dictionary] = []
	for guard_index: int in range(guard_count):
		var guard_entry: Dictionary = _pick_weighted_entry(guard_entries, rng)
		var spawn_template_id: String = str(guard_entry.get("spawn_template_id", ""))
		var monster_id: String = str(guard_entry.get("monster_id", ""))
		if monster_id.is_empty() and not spawn_template_id.is_empty():
			var spawn_template: Dictionary = _find_template_by_id(isolated_templates, spawn_template_id)
			monster_id = str(spawn_template.get("monster_id", ""))
		if monster_id.is_empty():
			plan["invalid"] = true
			return
		guard_sites.append({
			"cell": guard_cells[guard_index],
			"monster_id": monster_id,
			"template_id": spawn_template_id,
		})
	plan["encounter_id"] = str(camp_entry.get("encounter_id", ""))
	plan["chest_cell"] = chest_cell
	plan["guard_sites"] = guard_sites
	plan["loot_container"] = _normalize_camp_loot_container(camp_entry.get("loot_container", {}))
	plan["locked_prompt_text"] = str(
		camp_entry.get("locked_prompt_text", "需要击败房间中的所有怪物")
	)


func _pick_camp_guard_cells(
	room_rect: Rect2i,
	door_cells: Array[Vector2i],
	chest_cell: Vector2i,
	min_distance_from_doors: int,
	chest_avoid_radius: int,
	guard_count: int,
	rng: RandomNumberGenerator
) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for y: int in range(room_rect.position.y, room_rect.position.y + room_rect.size.y):
		for x: int in range(room_rect.position.x, room_rect.position.x + room_rect.size.x):
			var candidate: Vector2i = Vector2i(x, y)
			if candidate == chest_cell:
				continue
			if candidate.distance_to(chest_cell) <= float(chest_avoid_radius):
				continue
			var blocked_by_door: bool = false
			for door_cell: Vector2i in door_cells:
				if candidate.distance_to(door_cell) < float(min_distance_from_doors):
					blocked_by_door = true
					break
			if blocked_by_door:
				continue
			candidates.append(candidate)
	var selected: Array[Vector2i] = []
	while not candidates.is_empty() and selected.size() < guard_count:
		var pick_index: int = rng.randi_range(0, candidates.size() - 1)
		selected.append(candidates[pick_index])
		candidates.remove_at(pick_index)
	return selected


func _normalize_camp_loot_container(value: Variant) -> Dictionary:
	var container: Dictionary = {}
	if value is Dictionary:
		container = (value as Dictionary).duplicate(true)
	container["container_kind"] = str(container.get("container_kind", "loot_container"))
	container["container_title"] = str(container.get("container_title", "营地宝箱"))
	container["visual_kind"] = str(container.get("visual_kind", "treasure_chest"))
	container["grid_width"] = maxi(int(container.get("grid_width", 4)), 1)
	container["grid_height"] = maxi(int(container.get("grid_height", 2)), 1)
	container["slot_columns"] = maxi(
		int(container.get("slot_columns", container.get("grid_width", 4))),
		1
	)
	container["blocked_cells"] = (container.get("blocked_cells", []) as Array).duplicate(true)
	container["slot_snapshots"] = (container.get("slot_snapshots", []) as Array).duplicate(true)
	container["placement_snapshots"] = (
		container.get("placement_snapshots", container.get("placements", [])) as Array
	).duplicate(true)
	container["destroy_when_empty"] = bool(container.get("destroy_when_empty", false))
	container["empty_cleanup_delay_sec"] = float(container.get("empty_cleanup_delay_sec", 8.0))
	return container


func _resolve_room_content_anchor(
	room_rect: Rect2i,
	door_cells: Array[Vector2i],
	min_distance_from_doors: int,
	center_cluster_avoid_radius: int,
	avoid_room_center: bool
) -> Vector2i:
	var center_cell: Vector2i = _rect_center_cell(room_rect)
	if _is_valid_room_content_anchor(
		center_cell,
		room_rect,
		door_cells,
		min_distance_from_doors,
		center_cluster_avoid_radius,
		avoid_room_center
	):
		return center_cell
	var candidate_cells: Array[Vector2i] = []
	for y: int in range(room_rect.position.y, room_rect.position.y + room_rect.size.y):
		for x: int in range(room_rect.position.x, room_rect.position.x + room_rect.size.x):
			var candidate: Vector2i = Vector2i(x, y)
			if not _is_valid_room_content_anchor(
				candidate,
				room_rect,
				door_cells,
				min_distance_from_doors,
				center_cluster_avoid_radius,
				avoid_room_center
			):
				continue
			candidate_cells.append(candidate)
	candidate_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(center_cell) < b.distance_squared_to(center_cell)
	)
	return center_cell if candidate_cells.is_empty() else candidate_cells[0]


func _is_valid_room_content_anchor(
	candidate: Vector2i,
	room_rect: Rect2i,
	door_cells: Array[Vector2i],
	min_distance_from_doors: int,
	center_cluster_avoid_radius: int,
	avoid_room_center: bool
) -> bool:
	if not _is_cell_inside_rect(candidate, room_rect):
		return false
	if avoid_room_center and center_cluster_avoid_radius > 0:
		if candidate.distance_to(_rect_center_cell(room_rect)) <= float(center_cluster_avoid_radius):
			return false
	for door_cell: Vector2i in door_cells:
		if candidate.distance_to(door_cell) < float(min_distance_from_doors):
			return false
	return true


func _is_cell_inside_rect(cell: Vector2i, room_rect: Rect2i) -> bool:
	return (
		cell.x >= room_rect.position.x
		and cell.y >= room_rect.position.y
		and cell.x < room_rect.position.x + room_rect.size.x
		and cell.y < room_rect.position.y + room_rect.size.y
	)


func _place_poi_center_cluster(
	map_data: WdcMapGenerationTypes.MapData,
	main_room_rect: Rect2i,
	template_dict: Dictionary,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator,
	room_content_plans: Array[Dictionary] = []
) -> void:
	for plan: Dictionary in room_content_plans:
		if int(plan.get("room_index", -1)) != 0:
			continue
		if str(plan.get("content_kind", "")) == "locked_treasure_camp":
			return
	var content: Dictionary = template_dict.get("content", {}) as Dictionary
	var center_cluster: Dictionary = content.get("center_ore_cluster", {}) as Dictionary
	if not bool(center_cluster.get("enabled", false)):
		return
	var override_id: String = str(center_cluster.get("cluster_override_id", ""))
	if override_id.is_empty():
		return
	var cluster_template: Dictionary = _find_cluster_override(config, override_id)
	if cluster_template.is_empty():
		return
	_grow_cluster_from_seed(map_data, _rect_center_cell(main_room_rect), config, cluster_template, rng)


func _find_cluster_override(
	config: WdcMapGenerationTypes.MapConfig,
	override_id: String
) -> Dictionary:
	for override_entry: Dictionary in config.mineral_cluster_overrides:
		if str(override_entry.get("id", "")) == override_id:
			return override_entry.duplicate(true)
	return {}


func _try_place_one_poi(
	map_data: WdcMapGenerationTypes.MapData,
	poi_type: int,
	min_distance: float,
	radius: int,
	irregularity: float,
	rng: RandomNumberGenerator
) -> bool:
	var min_x: int = radius
	var max_x: int = map_data.width - 1 - radius
	var min_y: int = radius
	var max_y: int = map_data.height - 1 - radius
	if min_x > max_x or min_y > max_y:
		return false
	var center_x: int = rng.randi_range(min_x, max_x)
	var center_y: int = rng.randi_range(min_y, max_y)
	var center: Vector2 = Vector2(center_x, center_y)
	for existing: Dictionary in map_data.poi_centers:
		var ex: int = existing.get("x", 0) as int
		var ey: int = existing.get("y", 0) as int
		if center.distance_to(Vector2(ex, ey)) < min_distance:
			return false
	var offsets: Array[Vector2i] = _generate_ca_shape(radius, irregularity, rng)
	var world_cells: Array[Vector2i] = []
	for offset: Vector2i in offsets:
		var wx: int = center_x + offset.x
		var wy: int = center_y + offset.y
		if not map_data.is_in_bounds(wx, wy):
			return false
		var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(wx, wy)
		if cell == null or cell.poi_type != WdcMapGenerationTypes.PoiType.NONE:
			return false
		world_cells.append(Vector2i(wx, wy))
	for world_cell: Vector2i in world_cells:
		var target: WdcMapGenerationTypes.CellData = map_data.get_cell(world_cell.x, world_cell.y)
		target.cell_type = WdcMapGenerationTypes.CellType.FLOOR
		target.poi_type = poi_type
		target.is_poi_protected = true
	map_data.poi_centers.append({
		"x": center_x,
		"y": center_y,
		"type": poi_type
	})
	return true


func _generate_ca_shape(radius: int, irregularity: float, rng: RandomNumberGenerator) -> Array[Vector2i]:
	if radius <= 0:
		return [Vector2i.ZERO]
	if irregularity < 0.05:
		return _generate_circle_shape(radius)
	var local_size: int = radius * 2 + 3
	var center: int = local_size / 2
	var alive: Dictionary = {}
	var protected_core_radius: float = maxf(1.0, float(radius) * (1.0 - irregularity * 0.55))
	for ly: int in range(local_size):
		for lx: int in range(local_size):
			var dx: int = lx - center
			var dy: int = ly - center
			var dist: float = sqrt(float(dx * dx + dy * dy))
			if dist > float(radius) + 0.6:
				continue
			var key: String = _key(lx, ly)
			var core_alive: bool = dist <= protected_core_radius
			var noise_band_t: float = inverse_lerp(protected_core_radius, float(radius) + 0.6, dist)
			var noise_keep_chance: float = lerpf(
				1.0 - irregularity * 0.15,
				1.0 - irregularity,
				clampf(noise_band_t, 0.0, 1.0)
			)
			var noise_alive: bool = rng.randf() < noise_keep_chance
			alive[key] = core_alive or noise_alive
	for _iteration: int in range(3):
		var next_alive: Dictionary = {}
		for ly: int in range(local_size):
			for lx: int in range(local_size):
				var dx: int = lx - center
				var dy: int = ly - center
				var dist: float = sqrt(float(dx * dx + dy * dy))
				if dist > float(radius) + 0.8:
					continue
				var n: int = _count_alive_neighbors(alive, lx, ly)
				var now_alive: bool = bool(alive.get(_key(lx, ly), false))
				var become_alive: bool = now_alive
				if n > 4:
					become_alive = true
				elif n < 4:
					become_alive = false
				if dist <= protected_core_radius:
					become_alive = true
				next_alive[_key(lx, ly)] = become_alive
		alive = next_alive
	var offsets: Array[Vector2i] = []
	for ly: int in range(local_size):
		for lx: int in range(local_size):
			if not bool(alive.get(_key(lx, ly), false)):
				continue
			offsets.append(Vector2i(lx - center, ly - center))
	if offsets.is_empty():
		return _generate_circle_shape(radius)
	return offsets


func _generate_circle_shape(radius: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	for y: int in range(-radius, radius + 1):
		for x: int in range(-radius, radius + 1):
			if x * x + y * y <= radius * radius:
				offsets.append(Vector2i(x, y))
	return offsets


func _count_alive_neighbors(alive: Dictionary, x: int, y: int) -> int:
	var count: int = 0
	for oy: int in range(-1, 2):
		for ox: int in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			if bool(alive.get(_key(x + ox, y + oy), false)):
				count += 1
	return count


func _fill_noise(
	map_data: WdcMapGenerationTypes.MapData,
	fill_percent: float,
	rng: RandomNumberGenerator
) -> void:
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell.is_poi_protected:
				continue
			cell.cell_type = (
				WdcMapGenerationTypes.CellType.WALL
				if rng.randf() < fill_percent
				else WdcMapGenerationTypes.CellType.FLOOR
			)


func _smooth_caves(map_data: WdcMapGenerationTypes.MapData, iterations: int) -> void:
	for _iteration: int in range(iterations):
		var next_types: Array[Array] = []
		next_types.resize(map_data.height)
		for y: int in range(map_data.height):
			var row: Array = []
			row.resize(map_data.width)
			for x: int in range(map_data.width):
				var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
				if cell.is_poi_protected:
					row[x] = cell.cell_type
					continue
				var wall_neighbors: int = _count_wall_neighbors(map_data, x, y)
				if wall_neighbors > 4:
					row[x] = WdcMapGenerationTypes.CellType.WALL
				elif wall_neighbors < 4:
					row[x] = WdcMapGenerationTypes.CellType.FLOOR
				else:
					row[x] = cell.cell_type
			next_types[y] = row
		for y: int in range(map_data.height):
			for x: int in range(map_data.width):
				var target_cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
				if target_cell.is_poi_protected:
					continue
				target_cell.cell_type = next_types[y][x] as int


func _count_wall_neighbors(map_data: WdcMapGenerationTypes.MapData, x: int, y: int) -> int:
	var walls: int = 0
	for oy: int in range(-1, 2):
		for ox: int in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var nx: int = x + ox
			var ny: int = y + oy
			if not map_data.is_in_bounds(nx, ny):
				walls += 1
				continue
			var ncell: WdcMapGenerationTypes.CellData = map_data.get_cell(nx, ny)
			if ncell.cell_type == WdcMapGenerationTypes.CellType.WALL:
				walls += 1
	return walls


func _dig_corridors(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	if config.corridor_count <= 0:
		return
	var corridor_steps: int = int(round(maxi(map_data.width, map_data.height) * config.corridor_length))
	corridor_steps = maxi(corridor_steps, 1)
	var radius: int = maxi(0, int(floor(float(config.corridor_width - 1) * 0.5)))
	for _corridor_idx: int in range(config.corridor_count):
		var pos: Vector2i = Vector2i(
			rng.randi_range(0, map_data.width - 1),
			rng.randi_range(0, map_data.height - 1)
		)
		var dir: Vector2i = _random_direction(rng)
		for _step: int in range(corridor_steps):
			if not map_data.is_in_bounds(pos.x, pos.y):
				break
			_carve_disc(map_data, pos, radius)
			if rng.randf() < config.corridor_wobble:
				if rng.randf() < 0.5:
					dir += Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
					dir = _sanitize_direction(dir, rng)
				else:
					var side: int = rng.randi_range(-1, 1)
					if dir.x == 0:
						pos.x += side
					else:
						pos.y += side
			pos += dir
			if (
				pos.x <= 0
				or pos.x >= map_data.width - 1
				or pos.y <= 0
				or pos.y >= map_data.height - 1
			):
				break


func _carve_disc(map_data: WdcMapGenerationTypes.MapData, center: Vector2i, radius: int) -> void:
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			if not map_data.is_in_bounds(x, y):
				continue
			if radius > 0:
				var dx: int = x - center.x
				var dy: int = y - center.y
				if dx * dx + dy * dy > radius * radius:
					continue
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell.is_poi_protected:
				continue
			cell.cell_type = WdcMapGenerationTypes.CellType.FLOOR


func _generate_traces(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	var trace_cfg: Dictionary = {
		WdcMapGenerationTypes.PoiType.LARGE_RUIN: {
			"radius": config.trace_large_radius,
			"density": config.trace_large_density,
			"rays": config.trace_large_rays,
			"twist": config.trace_large_twist
		},
		WdcMapGenerationTypes.PoiType.MEDIUM_BIOME: {
			"radius": config.trace_medium_radius,
			"density": config.trace_medium_density,
			"rays": config.trace_medium_rays,
			"twist": config.trace_medium_twist
		},
		WdcMapGenerationTypes.PoiType.SMALL_ORE: {
			"radius": config.trace_small_radius,
			"density": config.trace_small_density,
			"rays": config.trace_small_rays,
			"twist": config.trace_small_twist
		}
	}
	for poi_center: Dictionary in map_data.poi_centers:
		var poi_type: int = poi_center.get("type", WdcMapGenerationTypes.PoiType.NONE) as int
		if not trace_cfg.has(poi_type):
			continue
		var cfg: Dictionary = trace_cfg[poi_type] as Dictionary
		var radius: float = cfg.get("radius", 0.0) as float
		var density: float = cfg.get("density", 0.0) as float
		var rays: float = cfg.get("rays", 1.0) as float
		var twist: float = cfg.get("twist", 1.0) as float
		var cx: int = poi_center.get("x", 0) as int
		var cy: int = poi_center.get("y", 0) as int
		var int_radius: int = int(ceil(radius))
		for y: int in range(cy - int_radius, cy + int_radius + 1):
			for x: int in range(cx - int_radius, cx + int_radius + 1):
				if not map_data.is_in_bounds(x, y):
					continue
				var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
				if cell.poi_type != WdcMapGenerationTypes.PoiType.NONE:
					continue
				if (
					cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR
					and cell.cell_type != WdcMapGenerationTypes.CellType.WALL
				):
					continue
				if cell.cell_type == WdcMapGenerationTypes.CellType.WALL and cell.has_mineral:
					continue
				if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
					continue
				var dx: float = float(x - cx)
				var dy: float = float(y - cy)
				var dist: float = sqrt(dx * dx + dy * dy)
				if dist <= 0.0 or dist > radius:
					continue
				var t: float = dist / radius
				var angle: float = atan2(dy, dx)
				var wave: float = 0.5 + 0.5 * sin(angle * rays + t * twist * TAU)
				var chance: float = density * (1.0 - t) * (0.6 + wave * 0.4)
				if rng.randf() < chance:
					cell.trace_type = poi_type


func _generate_minerals(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	_clear_all_mineral_cells(map_data)
	if not config.mineral_cluster_types.is_empty():
		_generate_mineral_clusters(map_data, config, rng)
		return
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			if cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
				cell.has_mineral = false
				continue
			var chance: float = config.mineral_base_chance
			if _is_exposed_wall(map_data, x, y):
				chance = config.mineral_exposed_chance
			chance *= _resolve_layer_weight_for_cell(
				config,
				map_data,
				Vector2i(x, y),
				"mineral_budget_weight"
			)
			chance = clampf(chance, 0.0, 1.0)
			cell.has_mineral = rng.randf() < chance


func _clear_all_mineral_cells(map_data: WdcMapGenerationTypes.MapData) -> void:
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			cell.has_mineral = false
			if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
				cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.NONE


func _clear_four_region_mineral_cells(map_data: WdcMapGenerationTypes.MapData) -> void:
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			cell.has_mineral = false
			if cell.special_block_type in [
				WdcMapGenerationTypes.SpecialBlockType.RARE_MINERAL,
				WdcMapGenerationTypes.SpecialBlockType.TURQUOISE,
				WdcMapGenerationTypes.SpecialBlockType.AMETHYST,
				WdcMapGenerationTypes.SpecialBlockType.GOLD,
			]:
				cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.NONE


func _generate_mineral_clusters(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	var placed_seed_cells: Array[Vector2i] = []
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if not _is_valid_global_cluster_seed_cell(cell, config):
				continue
			if _is_cluster_seed_too_close(
				Vector2i(x, y),
				placed_seed_cells,
				config.mineral_min_distance_between_cluster_seeds_cells
			):
				continue
			var chance: float = config.mineral_base_chance
			if _is_exposed_wall(map_data, x, y):
				chance = config.mineral_exposed_chance
			chance *= _resolve_layer_weight_for_cell(
				config,
				map_data,
				Vector2i(x, y),
				"mineral_budget_weight"
			)
			chance = clampf(chance, 0.0, 1.0)
			if rng.randf() > chance:
				continue
			var cluster_template: Dictionary = _pick_cluster_template(config.mineral_cluster_types, rng)
			if cluster_template.is_empty():
				continue
			if _grow_cluster_from_seed(map_data, Vector2i(x, y), config, cluster_template, rng) > 0:
				placed_seed_cells.append(Vector2i(x, y))


func _pick_cluster_template(cluster_types: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	var total_weight: float = 0.0
	var eligible_templates: Array[Dictionary] = []
	for cluster_entry: Dictionary in cluster_types:
		if not bool(cluster_entry.get("enabled", true)):
			continue
		if not _is_cluster_template_global_scope(cluster_entry):
			continue
		eligible_templates.append(cluster_entry)
		total_weight += maxf(float(cluster_entry.get("weight", 0.0)), 0.0)
	if total_weight <= 0.0:
		return {}
	var roll: float = rng.randf() * total_weight
	var cumulative: float = 0.0
	for cluster_entry: Dictionary in cluster_types:
		if not bool(cluster_entry.get("enabled", true)):
			continue
		if not _is_cluster_template_global_scope(cluster_entry):
			continue
		cumulative += maxf(float(cluster_entry.get("weight", 0.0)), 0.0)
		if roll <= cumulative:
			return cluster_entry.duplicate(true)
	return (
		eligible_templates[eligible_templates.size() - 1] as Dictionary
	).duplicate(true)


func _is_cluster_template_global_scope(cluster_template: Dictionary) -> bool:
	var spawn_scope: String = str(cluster_template.get("spawn_scope", "global"))
	return spawn_scope.begins_with("global")


func _grow_cluster_from_seed(
	map_data: WdcMapGenerationTypes.MapData,
	seed_cell: Vector2i,
	config: WdcMapGenerationTypes.MapConfig,
	cluster_template: Dictionary,
	rng: RandomNumberGenerator
) -> int:
	var min_size: int = maxi(int(cluster_template.get("min_cluster_size", 1)), 1)
	var max_size: int = maxi(int(cluster_template.get("max_cluster_size", min_size)), min_size)
	var target_size: int = rng.randi_range(min_size, max_size)
	var generated_cells: Array[Vector2i] = []
	if not _place_cluster_cell(map_data, seed_cell, cluster_template):
		return 0
	generated_cells.append(seed_cell)
	while generated_cells.size() < target_size:
		var candidates_by_key: Dictionary = {}
		for generated_cell: Vector2i in generated_cells:
			for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var candidate: Vector2i = generated_cell + dir
				var candidate_key: String = _key(candidate.x, candidate.y)
				if candidates_by_key.has(candidate_key):
					continue
				if not _is_valid_cluster_candidate(map_data, candidate, config, cluster_template):
					continue
				candidates_by_key[candidate_key] = candidate
		if candidates_by_key.is_empty():
			break
		var candidate_cells: Array[Vector2i] = []
		for candidate_value: Variant in candidates_by_key.values():
			if candidate_value is Vector2i:
				candidate_cells.append(candidate_value as Vector2i)
		_shuffle_vector2i_array(candidate_cells, rng)
		var generated_this_round: bool = false
		for candidate_cell: Vector2i in candidate_cells:
			if generated_cells.size() >= target_size:
				break
			if rng.randf() > clampf(float(cluster_template.get("spawn_probability", 0.0)), 0.0, 1.0):
				continue
			if _place_cluster_cell(map_data, candidate_cell, cluster_template):
				generated_cells.append(candidate_cell)
				generated_this_round = true
		if not generated_this_round:
			break
	return generated_cells.size()


func _is_valid_global_cluster_seed_cell(
	cell: WdcMapGenerationTypes.CellData,
	config: WdcMapGenerationTypes.MapConfig
) -> bool:
	if cell == null:
		return false
	if cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
		return false
	if cell.has_mineral or cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
		return false
	if not config.mineral_allow_clusters_inside_poi_rooms and cell.poi_type != WdcMapGenerationTypes.PoiType.NONE:
		return false
	return true


func _is_cluster_seed_too_close(
	candidate: Vector2i,
	placed_seed_cells: Array[Vector2i],
	min_distance_cells: int
) -> bool:
	if min_distance_cells <= 0:
		return false
	for existing_seed: Vector2i in placed_seed_cells:
		if existing_seed.distance_to(candidate) < float(min_distance_cells):
			return true
	return false


func _is_valid_cluster_candidate(
	map_data: WdcMapGenerationTypes.MapData,
	candidate: Vector2i,
	config: WdcMapGenerationTypes.MapConfig,
	cluster_template: Dictionary
) -> bool:
	if not map_data.is_in_bounds(candidate.x, candidate.y):
		return false
	var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(candidate.x, candidate.y)
	if cell == null:
		return false
	if cell.has_mineral or cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
		return false
	if not config.mineral_allow_clusters_inside_poi_rooms and cell.poi_type != WdcMapGenerationTypes.PoiType.NONE:
		return false
	if bool(cluster_template.get("require_stone", true)):
		return cell.cell_type == WdcMapGenerationTypes.CellType.WALL
	return (
		cell.cell_type == WdcMapGenerationTypes.CellType.WALL
		or cell.cell_type == WdcMapGenerationTypes.CellType.FLOOR
	)


func _place_cluster_cell(
	map_data: WdcMapGenerationTypes.MapData,
	target_cell: Vector2i,
	cluster_template: Dictionary
) -> bool:
	if not map_data.is_in_bounds(target_cell.x, target_cell.y):
		return false
	var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(target_cell.x, target_cell.y)
	if cell == null or cell.has_mineral or cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
		return false
	var tile_type_id: String = str(cluster_template.get("tile_type_id", ""))
	cell.cell_type = WdcMapGenerationTypes.CellType.WALL
	cell.has_mineral = false
	cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.NONE
	match tile_type_id:
		"rare_mineral_wall":
			cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.RARE_MINERAL
		"turquoise_ore":
			cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.TURQUOISE
		"amethyst_ore":
			cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.AMETHYST
		"gold_block":
			cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.GOLD
		_:
			cell.has_mineral = true
	return true


func _shuffle_vector2i_array(cells: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for index: int in range(cells.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var temp: Vector2i = cells[index]
		cells[index] = cells[swap_index]
		cells[swap_index] = temp


func _generate_poi_special_blocks(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	var cells_by_poi_type: Dictionary = {
		WdcMapGenerationTypes.PoiType.LARGE_RUIN: [],
		WdcMapGenerationTypes.PoiType.MEDIUM_BIOME: [],
		WdcMapGenerationTypes.PoiType.SMALL_ORE: []
	}
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null or cell.poi_type == WdcMapGenerationTypes.PoiType.NONE:
				continue
			var cells: Array = cells_by_poi_type.get(cell.poi_type, [])
			cells.append(cell)
			cells_by_poi_type[cell.poi_type] = cells
	_assign_special_blocks_for_poi_cells(
		map_data,
		cells_by_poi_type.get(WdcMapGenerationTypes.PoiType.SMALL_ORE, []),
		WdcMapGenerationTypes.PoiType.SMALL_ORE,
		WdcMapGenerationTypes.SpecialBlockType.TURQUOISE,
		config.small_poi_special_block_count,
		rng
	)
	_assign_special_blocks_for_poi_cells(
		map_data,
		cells_by_poi_type.get(WdcMapGenerationTypes.PoiType.MEDIUM_BIOME, []),
		WdcMapGenerationTypes.PoiType.MEDIUM_BIOME,
		WdcMapGenerationTypes.SpecialBlockType.AMETHYST,
		config.medium_poi_special_block_count,
		rng
	)
	_assign_special_blocks_for_poi_cells(
		map_data,
		cells_by_poi_type.get(WdcMapGenerationTypes.PoiType.LARGE_RUIN, []),
		WdcMapGenerationTypes.PoiType.LARGE_RUIN,
		WdcMapGenerationTypes.SpecialBlockType.GOLD,
		config.large_poi_special_block_count,
		rng
	)


func _assign_special_blocks_for_poi_cells(
	map_data: WdcMapGenerationTypes.MapData,
	candidate_cells: Array,
	poi_type: int,
	special_block_type: int,
	special_block_count_per_poi: int,
	rng: RandomNumberGenerator
) -> void:
	if candidate_cells.is_empty() or special_block_count_per_poi <= 0:
		return
	for poi_center: Dictionary in map_data.poi_centers:
		if int(poi_center.get("type", WdcMapGenerationTypes.PoiType.NONE)) != poi_type:
			continue
		var center: Vector2i = Vector2i(
			int(poi_center.get("x", 0)),
			int(poi_center.get("y", 0))
		)
		for _special_index: int in range(special_block_count_per_poi):
			var chosen_cell: WdcMapGenerationTypes.CellData = _pick_special_block_cell_for_poi(
				candidate_cells,
				center,
				rng
			)
			if chosen_cell == null:
				break
			chosen_cell.cell_type = WdcMapGenerationTypes.CellType.WALL
			chosen_cell.has_mineral = false
			chosen_cell.special_block_type = special_block_type


func _pick_special_block_cell_for_poi(
	candidate_cells: Array,
	center: Vector2i,
	rng: RandomNumberGenerator
) -> WdcMapGenerationTypes.CellData:
	var best_cell: WdcMapGenerationTypes.CellData = null
	var best_distance_sq: float = INF
	for cell_value: Variant in candidate_cells:
		var cell: WdcMapGenerationTypes.CellData = cell_value as WdcMapGenerationTypes.CellData
		if cell == null or cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
			continue
		var distance_sq: float = Vector2(float(cell.x - center.x), float(cell.y - center.y)).length_squared()
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_cell = cell
		elif is_equal_approx(distance_sq, best_distance_sq) and rng.randf() < 0.5:
			best_cell = cell
	return best_cell


func _is_exposed_wall(map_data: WdcMapGenerationTypes.MapData, x: int, y: int) -> bool:
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for dir: Vector2i in dirs:
		var nx: int = x + dir.x
		var ny: int = y + dir.y
		if not map_data.is_in_bounds(nx, ny):
			continue
		var neighbor: WdcMapGenerationTypes.CellData = map_data.get_cell(nx, ny)
		if neighbor != null and neighbor.cell_type == WdcMapGenerationTypes.CellType.FLOOR:
			return true
	return false


func _resolve_layer_for_cell(
	config: WdcMapGenerationTypes.MapConfig,
	map_data: WdcMapGenerationTypes.MapData,
	cell: Vector2i
) -> Dictionary:
	if config == null or config.map_layers.is_empty():
		return {}
	var width: int = map_data.width if map_data != null else config.width
	var height: int = map_data.height if map_data != null else config.height
	var center: Vector2 = Vector2((float(width) - 1.0) * 0.5, (float(height) - 1.0) * 0.5)
	var distance: float = Vector2(float(cell.x), float(cell.y)).distance_to(center)
	for layer: Dictionary in config.map_layers:
		if distance <= _resolve_layer_boundary_radius(config, layer, cell):
			return layer
	return config.map_layers[config.map_layers.size() - 1] as Dictionary


func _resolve_layer_boundary_radius(
	config: WdcMapGenerationTypes.MapConfig,
	layer: Dictionary,
	cell: Vector2i
) -> float:
	var base_radius: float = float(layer.get("max_radius_cells", INF))
	var amplitude: float = maxf(float(layer.get("boundary_noise_amplitude_cells", 0.0)), 0.0)
	if amplitude <= 0.0:
		return base_radius
	var scale_cells: float = maxf(float(layer.get("boundary_noise_scale_cells", 16.0)), 1.0)
	var octaves: int = clampi(int(layer.get("boundary_noise_octaves", 1)), 1, 6)
	var persistence: float = clampf(float(layer.get("boundary_noise_persistence", 0.5)), 0.0, 1.0)
	var base_seed: int = last_resolved_seed if last_resolved_seed != 0 else maxi(config.seed, 1)
	var seed: int = base_seed + int(layer.get("boundary_noise_seed_offset", 0))
	return base_radius + _sample_layer_boundary_noise(cell, scale_cells, octaves, persistence, seed) * amplitude


func _sample_layer_boundary_noise(
	cell: Vector2i,
	scale_cells: float,
	octaves: int,
	persistence: float,
	seed: int
) -> float:
	var total: float = 0.0
	var amplitude: float = 1.0
	var amplitude_sum: float = 0.0
	var frequency: float = 1.0
	for octave: int in range(octaves):
		total += _sample_value_noise_2d(
			float(cell.x) * frequency / scale_cells,
			float(cell.y) * frequency / scale_cells,
			seed + octave * 1013
		) * amplitude
		amplitude_sum += amplitude
		frequency *= 2.0
		amplitude *= persistence
	if amplitude_sum <= 0.0:
		return 0.0
	return total / amplitude_sum


func _sample_value_noise_2d(sample_x: float, sample_y: float, seed: int) -> float:
	var x0: int = int(floor(sample_x))
	var y0: int = int(floor(sample_y))
	var x1: int = x0 + 1
	var y1: int = y0 + 1
	var tx: float = _smooth_noise_step(sample_x - float(x0))
	var ty: float = _smooth_noise_step(sample_y - float(y0))
	var top: float = lerpf(
		_hash_noise_2d(x0, y0, seed),
		_hash_noise_2d(x1, y0, seed),
		tx
	)
	var bottom: float = lerpf(
		_hash_noise_2d(x0, y1, seed),
		_hash_noise_2d(x1, y1, seed),
		tx
	)
	return lerpf(top, bottom, ty)


func _smooth_noise_step(value: float) -> float:
	var clamped_value: float = clampf(value, 0.0, 1.0)
	return clamped_value * clamped_value * (3.0 - 2.0 * clamped_value)


func _hash_noise_2d(x: int, y: int, seed: int) -> float:
	var seed_value: int = abs(seed) % 104729
	var raw_value: float = sin(
		float(x) * 127.1 + float(y) * 311.7 + float(seed_value) * 74.7
	) * 43758.5453123
	var unit_value: float = raw_value - floor(raw_value)
	return unit_value * 2.0 - 1.0


func _resolve_layer_for_rect_center(
	config: WdcMapGenerationTypes.MapConfig,
	map_data: WdcMapGenerationTypes.MapData,
	rect: Rect2i
) -> Dictionary:
	return _resolve_layer_for_cell(config, map_data, _rect_center_cell(rect))


func _is_cell_in_target_layer(
	config: WdcMapGenerationTypes.MapConfig,
	map_data: WdcMapGenerationTypes.MapData,
	cell: Vector2i,
	target_layer_id: String
) -> bool:
	if target_layer_id.is_empty():
		return true
	var layer: Dictionary = _resolve_layer_for_cell(config, map_data, cell)
	return str(layer.get("id", "")) == target_layer_id


func _resolve_layer_weight_for_cell(
	config: WdcMapGenerationTypes.MapConfig,
	map_data: WdcMapGenerationTypes.MapData,
	cell: Vector2i,
	weight_key: String
) -> float:
	var layer: Dictionary = _resolve_layer_for_cell(config, map_data, cell)
	if layer.is_empty():
		return 1.0
	return maxf(float(layer.get(weight_key, 1.0)), 0.0)


func _split_layer_budget_counts(
	total_count: int,
	config: WdcMapGenerationTypes.MapConfig,
	weight_key: String
) -> Dictionary:
	var counts: Dictionary = {}
	if config == null or config.map_layers.is_empty() or total_count <= 0:
		return counts
	var weighted_entries: Array[Dictionary] = []
	var total_weight: float = 0.0
	for layer: Dictionary in config.map_layers:
		var layer_id: String = str(layer.get("id", ""))
		var weight: float = maxf(float(layer.get(weight_key, 1.0)), 0.0)
		total_weight += weight
		weighted_entries.append({
			"id": layer_id,
			"weight": weight,
			"count": 0,
			"remainder": 0.0,
		})
	if total_weight <= 0.0:
		total_weight = float(weighted_entries.size())
		for entry: Dictionary in weighted_entries:
			entry["weight"] = 1.0
	var assigned: int = 0
	for entry: Dictionary in weighted_entries:
		var raw_count: float = float(total_count) * float(entry.get("weight", 0.0)) / total_weight
		var floored_count: int = int(floor(raw_count))
		entry["count"] = floored_count
		entry["remainder"] = raw_count - float(floored_count)
		assigned += floored_count
	weighted_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("remainder", 0.0)) > float(b.get("remainder", 0.0))
	)
	var remaining: int = maxi(total_count - assigned, 0)
	var cursor: int = 0
	while remaining > 0 and not weighted_entries.is_empty():
		var entry: Dictionary = weighted_entries[cursor % weighted_entries.size()]
		entry["count"] = int(entry.get("count", 0)) + 1
		remaining -= 1
		cursor += 1
	for entry: Dictionary in weighted_entries:
		counts[str(entry.get("id", ""))] = int(entry.get("count", 0))
	return counts


func _apply_layer_durability_overrides(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig
) -> void:
	if map_data == null or config == null:
		return
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			if not _cell_uses_layer_durability(cell):
				cell.durability_override_max_hit_points = 0
				WdcMapGenerationTileRules.refresh_cell_runtime_state(cell)
				continue
			var layer: Dictionary = _resolve_layer_for_cell(config, map_data, Vector2i(x, y))
			cell.durability_override_max_hit_points = maxi(
				int(layer.get("stone_max_hit_points", 1)),
				1
			)
			WdcMapGenerationTileRules.refresh_cell_runtime_state(cell)


func _cell_uses_layer_durability(cell: WdcMapGenerationTypes.CellData) -> bool:
	if cell == null or cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
		return false
	if cell.special_block_type == WdcMapGenerationTypes.SpecialBlockType.NONE:
		return true
	match cell.special_block_type:
		WdcMapGenerationTypes.SpecialBlockType.RARE_MINERAL:
			return true
		WdcMapGenerationTypes.SpecialBlockType.TURQUOISE:
			return true
		WdcMapGenerationTypes.SpecialBlockType.AMETHYST:
			return true
		WdcMapGenerationTypes.SpecialBlockType.GOLD:
			return true
	return false


func _recalculate_stats(map_data: WdcMapGenerationTypes.MapData) -> void:
	map_data.total_floor = 0
	map_data.large_pois = 0
	map_data.medium_pois = 0
	map_data.small_pois = 0
	for poi_center: Dictionary in map_data.poi_centers:
		var poi_type: int = poi_center.get("type", WdcMapGenerationTypes.PoiType.NONE) as int
		match poi_type:
			WdcMapGenerationTypes.PoiType.LARGE_RUIN:
				map_data.large_pois += 1
			WdcMapGenerationTypes.PoiType.MEDIUM_BIOME:
				map_data.medium_pois += 1
			WdcMapGenerationTypes.PoiType.SMALL_ORE:
				map_data.small_pois += 1
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell.cell_type == WdcMapGenerationTypes.CellType.FLOOR:
				map_data.total_floor += 1


const TRAP_SPIKE_PATCH_COUNT: int = 4
const TRAP_SPIKE_PATCH_MIN_SIZE: int = 2
const TRAP_SPIKE_PATCH_MAX_SIZE: int = 4
const TRAP_SPIKE_PATCH_SPACING: int = 4


func _generate_environmental_traps(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator
) -> void:
	var high_density: bool = config.traps_high_density
	var spike_count: int = _resolve_trap_count(
		config.traps_spike_max_count,
		TRAP_SPIKE_PATCH_COUNT,
		TRAP_SPIKE_PATCH_COUNT * 4 if high_density else TRAP_SPIKE_PATCH_COUNT
	)
	var explosive_count: int = _resolve_trap_count(
		config.traps_explosive_chain_count,
		TRAP_EXPLOSIVE_ORE_CHAIN_COUNT,
		TRAP_EXPLOSIVE_ORE_CHAIN_COUNT * 4 if high_density else TRAP_EXPLOSIVE_ORE_CHAIN_COUNT
	)
	var arrow_count: int = _resolve_trap_count(
		config.traps_arrow_slit_max_count,
		TRAP_ARROW_SLIT_MAX_COUNT,
		TRAP_ARROW_SLIT_MAX_COUNT * 3 if high_density else TRAP_ARROW_SLIT_MAX_COUNT
	)
	var mimic_count: int = _resolve_trap_count(
		config.traps_mimic_ore_max_count,
		TRAP_MIMIC_ORE_MAX_COUNT,
		TRAP_MIMIC_ORE_MAX_COUNT * 3 if high_density else TRAP_MIMIC_ORE_MAX_COUNT
	)
	var plate_count: int = _resolve_trap_count(
		config.traps_pressure_plate_max_count,
		TRAP_PRESSURE_PLATE_MAX_COUNT,
		TRAP_PRESSURE_PLATE_MAX_COUNT * 4 if high_density else TRAP_PRESSURE_PLATE_MAX_COUNT
	)
	for layer: Dictionary in config.map_layers:
		var layer_id: String = str(layer.get("id", ""))
		_place_spike_patches(
			map_data,
			config,
			rng,
			int(_split_layer_budget_counts(spike_count, config, "trap_budget_weight").get(layer_id, 0)),
			_resolve_trap_spacing(
				config.traps_spike_min_spacing,
				TRAP_SPIKE_PATCH_SPACING,
				max(2, TRAP_SPIKE_PATCH_SPACING - 2) if high_density else TRAP_SPIKE_PATCH_SPACING
			),
			layer_id
		)
		_place_explosive_ore_chains(
			map_data,
			config,
			rng,
			int(_split_layer_budget_counts(explosive_count, config, "trap_budget_weight").get(layer_id, 0)),
			_resolve_trap_spacing(
				config.traps_explosive_chain_spacing,
				TRAP_EXPLOSIVE_ORE_CHAIN_SPACING,
				max(2, TRAP_EXPLOSIVE_ORE_CHAIN_SPACING - 4) if high_density else TRAP_EXPLOSIVE_ORE_CHAIN_SPACING
			),
			layer_id
		)
		_place_arrow_slits(
			map_data,
			config,
			rng,
			int(_split_layer_budget_counts(arrow_count, config, "trap_budget_weight").get(layer_id, 0)),
			_resolve_trap_spacing(
				config.traps_arrow_slit_min_spacing,
				TRAP_ARROW_SLIT_MIN_SPACING,
				max(1, TRAP_ARROW_SLIT_MIN_SPACING - 1) if high_density else TRAP_ARROW_SLIT_MIN_SPACING
			),
			layer_id
		)
		_place_mimic_ores(
			map_data,
			config,
			rng,
			int(_split_layer_budget_counts(mimic_count, config, "trap_budget_weight").get(layer_id, 0)),
			_resolve_trap_spacing(
				config.traps_mimic_ore_min_spacing,
				TRAP_MIMIC_ORE_MIN_SPACING,
				max(2, TRAP_MIMIC_ORE_MIN_SPACING - 2) if high_density else TRAP_MIMIC_ORE_MIN_SPACING
			),
			layer_id
		)
		_place_pressure_plates(
			map_data,
			config,
			rng,
			int(_split_layer_budget_counts(plate_count, config, "trap_budget_weight").get(layer_id, 0)),
			_resolve_trap_spacing(
				config.traps_pressure_plate_min_spacing,
				TRAP_PRESSURE_PLATE_MIN_SPACING,
				max(2, TRAP_PRESSURE_PLATE_MIN_SPACING - 2) if high_density else TRAP_PRESSURE_PLATE_MIN_SPACING
			),
			layer_id
		)


# 解析陷阱数量参数：显式 >= 0 时用显式值；否则用 fallback（高密度模式或默认）。
func _resolve_trap_count(explicit_value: int, _default_value: int, fallback_value: int) -> int:
	if explicit_value >= 0:
		return explicit_value
	return fallback_value


func _resolve_trap_spacing(explicit_value: int, _default_value: int, fallback_value: int) -> int:
	if explicit_value >= 0:
		return explicit_value
	return fallback_value


func _collect_spike_candidate_cells_from_pois(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	target_layer_id: String
) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	if map_data == null:
		return candidates
	var seen_keys: Dictionary = {}
	for poi_instance: Dictionary in map_data.poi_instances:
		var poi_layer_id: String = str(poi_instance.get("layer_id", ""))
		if not target_layer_id.is_empty() and not poi_layer_id.is_empty() and poi_layer_id != target_layer_id:
			continue
		_append_spike_candidates_from_rect(
			map_data,
			config,
			_dict_to_rect2i(poi_instance.get("main_room", {}) as Dictionary),
			target_layer_id,
			seen_keys,
			candidates
		)
		var sub_rooms: Array = poi_instance.get("sub_rooms", []) as Array
		for sub_room_value: Variant in sub_rooms:
			if not (sub_room_value is Dictionary):
				continue
			_append_spike_candidates_from_rect(
				map_data,
				config,
				_dict_to_rect2i(sub_room_value as Dictionary),
				target_layer_id,
				seen_keys,
				candidates
			)
		var corridors: Array = poi_instance.get("corridors", []) as Array
		for corridor_value: Variant in corridors:
			if not (corridor_value is Dictionary):
				continue
			var corridor: Dictionary = corridor_value as Dictionary
			var cells: Array = corridor.get("cells", []) as Array
			for cell_value: Variant in cells:
				if not (cell_value is Dictionary):
					continue
				var cell_dict: Dictionary = cell_value as Dictionary
				_append_spike_candidate_cell(
					map_data,
					config,
					Vector2i(int(cell_dict.get("x", -1)), int(cell_dict.get("y", -1))),
					target_layer_id,
					seen_keys,
					candidates
				)
	return candidates


func _append_spike_candidates_from_rect(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	room_rect: Rect2i,
	target_layer_id: String,
	seen_keys: Dictionary,
	candidates: Array[Vector2i]
) -> void:
	if room_rect.size.x <= 0 or room_rect.size.y <= 0:
		return
	for y: int in range(room_rect.position.y, room_rect.position.y + room_rect.size.y):
		for x: int in range(room_rect.position.x, room_rect.position.x + room_rect.size.x):
			_append_spike_candidate_cell(
				map_data,
				config,
				Vector2i(x, y),
				target_layer_id,
				seen_keys,
				candidates
			)


func _append_spike_candidate_cell(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	candidate: Vector2i,
	target_layer_id: String,
	seen_keys: Dictionary,
	candidates: Array[Vector2i]
) -> void:
	if not map_data.is_in_bounds(candidate.x, candidate.y):
		return
	var candidate_key: String = _key(candidate.x, candidate.y)
	if seen_keys.has(candidate_key):
		return
	var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(candidate.x, candidate.y)
	if cell == null:
		return
	if cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR:
		return
	if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
		return
	if not _is_cell_in_target_layer(config, map_data, candidate, target_layer_id):
		return
	seen_keys[candidate_key] = true
	candidates.append(candidate)


func _dict_to_rect2i(rect_dict: Dictionary) -> Rect2i:
	if rect_dict.is_empty():
		return Rect2i()
	return Rect2i(
		int(rect_dict.get("x", 0)),
		int(rect_dict.get("y", 0)),
		int(rect_dict.get("width", 0)),
		int(rect_dict.get("height", 0))
	)


func _place_spike_patches(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator,
	max_count: int = TRAP_SPIKE_PATCH_COUNT,
	spacing: int = TRAP_SPIKE_PATCH_SPACING,
	target_layer_id: String = ""
) -> void:
	if max_count <= 0:
		return
	var floor_cells: Array[Vector2i] = _collect_spike_candidate_cells_from_pois(
		map_data,
		config,
		target_layer_id
	)
	if floor_cells.is_empty():
		return
	_shuffle_vector2i_array(floor_cells, rng)
	var allowed_cells: Dictionary = {}
	for floor_cell: Vector2i in floor_cells:
		allowed_cells[_key(floor_cell.x, floor_cell.y)] = true
	var placed_cells: Array[Vector2i] = []
	var patches_placed: int = 0
	for seed_cell: Vector2i in floor_cells:
		if patches_placed >= max_count:
			break
		if _is_too_close_to_existing_spike(seed_cell, placed_cells, spacing):
			continue
		var patch_size: int = rng.randi_range(TRAP_SPIKE_PATCH_MIN_SIZE, TRAP_SPIKE_PATCH_MAX_SIZE)
		var patch_cells: Array[Vector2i] = _grow_spike_patch(
			map_data,
			seed_cell,
			patch_size,
			rng,
			allowed_cells
		)
		if patch_cells.size() < TRAP_SPIKE_PATCH_MIN_SIZE:
			continue
		for patch_cell: Vector2i in patch_cells:
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(patch_cell.x, patch_cell.y)
			cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.SPIKE
			placed_cells.append(patch_cell)
			map_data.trap_sites.append({
				"trap_kind": "spike",
				"cell": _vector2i_to_dict(patch_cell),
				"metadata": {},
				"layer_id": target_layer_id,
			})
		patches_placed += 1


func _grow_spike_patch(
	map_data: WdcMapGenerationTypes.MapData,
	seed_cell: Vector2i,
	target_size: int,
	rng: RandomNumberGenerator,
	allowed_cells: Dictionary = {}
) -> Array[Vector2i]:
	var patch_cells: Array[Vector2i] = [seed_cell]
	var visited: Dictionary = {}
	visited[_key(seed_cell.x, seed_cell.y)] = true
	var frontier: Array[Vector2i] = [seed_cell]
	while patch_cells.size() < target_size and not frontier.is_empty():
		var pivot_index: int = rng.randi_range(0, frontier.size() - 1)
		var pivot: Vector2i = frontier[pivot_index]
		frontier.remove_at(pivot_index)
		var directions: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
		]
		_shuffle_vector2i_array(directions, rng)
		for direction: Vector2i in directions:
			if patch_cells.size() >= target_size:
				break
			var neighbor: Vector2i = pivot + direction
			var neighbor_key: String = _key(neighbor.x, neighbor.y)
			if visited.has(neighbor_key):
				continue
			visited[neighbor_key] = true
			if not allowed_cells.is_empty() and not allowed_cells.has(neighbor_key):
				continue
			if not map_data.is_in_bounds(neighbor.x, neighbor.y):
				continue
			var neighbor_cell: WdcMapGenerationTypes.CellData = map_data.get_cell(neighbor.x, neighbor.y)
			if neighbor_cell == null:
				continue
			if neighbor_cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR:
				continue
			if neighbor_cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
				continue
			patch_cells.append(neighbor)
			frontier.append(neighbor)
	return patch_cells


func _is_too_close_to_existing_spike(
	candidate: Vector2i,
	placed_cells: Array[Vector2i],
	spacing: int
) -> bool:
	for placed: Vector2i in placed_cells:
		var dx: int = absi(candidate.x - placed.x)
		var dy: int = absi(candidate.y - placed.y)
		if dx + dy < spacing:
			return true
	return false


const TRAP_EXPLOSIVE_ORE_CHAIN_COUNT: int = 3
const TRAP_EXPLOSIVE_ORE_CHAIN_LENGTH: int = 3
const TRAP_EXPLOSIVE_ORE_CHAIN_SPACING: int = 8


func _place_explosive_ore_chains(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator,
	max_count: int = TRAP_EXPLOSIVE_ORE_CHAIN_COUNT,
	spacing: int = TRAP_EXPLOSIVE_ORE_CHAIN_SPACING,
	target_layer_id: String = ""
) -> void:
	if max_count <= 0:
		return
	var wall_cells: Array[Vector2i] = []
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			if cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
				continue
			if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
				continue
			if not _is_cell_in_target_layer(config, map_data, Vector2i(x, y), target_layer_id):
				continue
			wall_cells.append(Vector2i(x, y))
	if wall_cells.is_empty():
		return
	_shuffle_vector2i_array(wall_cells, rng)
	var placed_chain_anchor_cells: Array[Vector2i] = []
	var chains_placed: int = 0
	for seed_cell: Vector2i in wall_cells:
		if chains_placed >= max_count:
			break
		if _is_too_close_to_existing_chain(
			seed_cell,
			placed_chain_anchor_cells,
			spacing
		):
			continue
		var chain_cells: Array[Vector2i] = _try_grow_explosive_ore_chain(
			map_data,
			seed_cell,
			TRAP_EXPLOSIVE_ORE_CHAIN_LENGTH
		)
		if chain_cells.size() < TRAP_EXPLOSIVE_ORE_CHAIN_LENGTH:
			continue
		var chain_node_dicts: Array = []
		for chain_cell: Vector2i in chain_cells:
			var node_cell: WdcMapGenerationTypes.CellData = map_data.get_cell(chain_cell.x, chain_cell.y)
			node_cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.EXPLOSIVE_ORE
			node_cell.has_mineral = false
			placed_chain_anchor_cells.append(chain_cell)
			chain_node_dicts.append(_vector2i_to_dict(chain_cell))
		map_data.trap_sites.append({
			"trap_kind": "explosive_ore_chain",
			"nodes": chain_node_dicts,
			"metadata": {},
			"layer_id": target_layer_id,
		})
		chains_placed += 1


func _try_grow_explosive_ore_chain(
	map_data: WdcMapGenerationTypes.MapData,
	seed_cell: Vector2i,
	target_length: int
) -> Array[Vector2i]:
	var direction: Vector2i = Vector2i.RIGHT
	var chain_cells: Array[Vector2i] = []
	for step: int in range(target_length):
		var candidate: Vector2i = seed_cell + direction * step
		if not map_data.is_in_bounds(candidate.x, candidate.y):
			return []
		var candidate_cell: WdcMapGenerationTypes.CellData = map_data.get_cell(candidate.x, candidate.y)
		if candidate_cell == null:
			return []
		if candidate_cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
			return []
		if candidate_cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
			return []
		chain_cells.append(candidate)
	return chain_cells


func _is_too_close_to_existing_chain(
	candidate: Vector2i,
	placed_cells: Array[Vector2i],
	spacing: int
) -> bool:
	for placed: Vector2i in placed_cells:
		var dx: int = absi(candidate.x - placed.x)
		var dy: int = absi(candidate.y - placed.y)
		if dx + dy < spacing:
			return true
	return false


const TRAP_ARROW_SLIT_MAX_COUNT: int = 6
const TRAP_ARROW_SLIT_MIN_SPACING: int = 3
const TRAP_ARROW_SLIT_REQUIRED_FORWARD_CLEAR: int = 3

const TRAP_MIMIC_ORE_MAX_COUNT: int = 5
const TRAP_MIMIC_ORE_MIN_SPACING: int = 4
const TRAP_MIMIC_ORE_MONSTER_ID: String = "ghoul"

const TRAP_PRESSURE_PLATE_MAX_COUNT: int = 4
const TRAP_PRESSURE_PLATE_MIN_SPACING: int = 4


func _place_pressure_plates(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator,
	max_count: int = TRAP_PRESSURE_PLATE_MAX_COUNT,
	spacing: int = TRAP_PRESSURE_PLATE_MIN_SPACING,
	target_layer_id: String = ""
) -> void:
	if max_count <= 0:
		return
	var floor_cells: Array[Vector2i] = []
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			if cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR:
				continue
			if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
				continue
			if not _is_cell_in_target_layer(config, map_data, Vector2i(x, y), target_layer_id):
				continue
			floor_cells.append(Vector2i(x, y))
	if floor_cells.is_empty():
		return
	_shuffle_vector2i_array(floor_cells, rng)
	var placed_cells: Array[Vector2i] = []
	var plates_placed: int = 0
	for candidate_cell: Vector2i in floor_cells:
		if plates_placed >= max_count:
			break
		if _is_too_close_to_existing_chain(
			candidate_cell,
			placed_cells,
			spacing
		):
			continue
		var cell_data: WdcMapGenerationTypes.CellData = map_data.get_cell(
			candidate_cell.x,
			candidate_cell.y
		)
		cell_data.special_block_type = WdcMapGenerationTypes.SpecialBlockType.PRESSURE_PLATE
		placed_cells.append(candidate_cell)
		map_data.trap_sites.append({
			"trap_kind": "pressure_plate",
			"cell": _vector2i_to_dict(candidate_cell),
			"metadata": {},
			"layer_id": target_layer_id,
		})
		plates_placed += 1


func _place_mimic_ores(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator,
	max_count: int = TRAP_MIMIC_ORE_MAX_COUNT,
	spacing: int = TRAP_MIMIC_ORE_MIN_SPACING,
	target_layer_id: String = ""
) -> void:
	if max_count <= 0:
		return
	var mineral_cells: Array[Vector2i] = []
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			if cell.cell_type != WdcMapGenerationTypes.CellType.WALL:
				continue
			if not cell.has_mineral:
				continue
			if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
				continue
			if not _is_cell_in_target_layer(config, map_data, Vector2i(x, y), target_layer_id):
				continue
			mineral_cells.append(Vector2i(x, y))
	if mineral_cells.is_empty():
		return
	_shuffle_vector2i_array(mineral_cells, rng)
	var placed_cells: Array[Vector2i] = []
	var mimics_placed: int = 0
	for candidate_cell: Vector2i in mineral_cells:
		if mimics_placed >= max_count:
			break
		if _is_too_close_to_existing_chain(
			candidate_cell,
			placed_cells,
			spacing
		):
			continue
		var variant: String = "explosive" if (mimics_placed % 2) == 0 else "mimic_monster"
		placed_cells.append(candidate_cell)
		var metadata: Dictionary = {"variant": variant}
		if variant == "mimic_monster":
			metadata["monster_id"] = TRAP_MIMIC_ORE_MONSTER_ID
		map_data.trap_sites.append({
			"trap_kind": "mimic_ore",
			"cell": _vector2i_to_dict(candidate_cell),
			"metadata": metadata,
			"layer_id": target_layer_id,
		})
		mimics_placed += 1


func _place_arrow_slits(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	rng: RandomNumberGenerator,
	max_count: int = TRAP_ARROW_SLIT_MAX_COUNT,
	spacing: int = TRAP_ARROW_SLIT_MIN_SPACING,
	target_layer_id: String = ""
) -> void:
	if max_count <= 0:
		return
	var poi_wall_cells: Array[Vector2i] = []
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			if cell == null:
				continue
			if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.POI_WALL:
				continue
			if not _is_cell_in_target_layer(config, map_data, Vector2i(x, y), target_layer_id):
				continue
			poi_wall_cells.append(Vector2i(x, y))
	if poi_wall_cells.is_empty():
		return
	_shuffle_vector2i_array(poi_wall_cells, rng)
	var placed_cells: Array[Vector2i] = []
	var slits_placed: int = 0
	for candidate_cell: Vector2i in poi_wall_cells:
		if slits_placed >= max_count:
			break
		if _is_too_close_to_existing_chain(
			candidate_cell,
			placed_cells,
			spacing
		):
			continue
		var facing_direction: Vector2i = _resolve_arrow_slit_facing(map_data, candidate_cell)
		if facing_direction == Vector2i.ZERO:
			continue
		var cell_data: WdcMapGenerationTypes.CellData = map_data.get_cell(
			candidate_cell.x,
			candidate_cell.y
		)
		cell_data.special_block_type = WdcMapGenerationTypes.SpecialBlockType.ARROW_SLIT
		placed_cells.append(candidate_cell)
		map_data.trap_sites.append({
			"trap_kind": "arrow_slit",
			"cell": _vector2i_to_dict(candidate_cell),
			"metadata": {
				"facing_x": facing_direction.x,
				"facing_y": facing_direction.y
			},
			"layer_id": target_layer_id,
		})
		slits_placed += 1


func _resolve_arrow_slit_facing(
	map_data: WdcMapGenerationTypes.MapData,
	candidate_cell: Vector2i
) -> Vector2i:
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
	]
	var empty_directions: Array[Vector2i] = []
	for direction: Vector2i in directions:
		var neighbor: Vector2i = candidate_cell + direction
		if not map_data.is_in_bounds(neighbor.x, neighbor.y):
			continue
		var neighbor_cell: WdcMapGenerationTypes.CellData = map_data.get_cell(neighbor.x, neighbor.y)
		if neighbor_cell == null:
			continue
		if neighbor_cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR:
			continue
		if neighbor_cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
			continue
		empty_directions.append(direction)
	if empty_directions.size() != 1:
		return Vector2i.ZERO
	var facing: Vector2i = empty_directions[0]
	for step: int in range(1, TRAP_ARROW_SLIT_REQUIRED_FORWARD_CLEAR + 1):
		var probe: Vector2i = candidate_cell + facing * step
		if not map_data.is_in_bounds(probe.x, probe.y):
			return Vector2i.ZERO
		var probe_cell: WdcMapGenerationTypes.CellData = map_data.get_cell(probe.x, probe.y)
		if probe_cell == null:
			return Vector2i.ZERO
		if probe_cell.cell_type != WdcMapGenerationTypes.CellType.FLOOR:
			return Vector2i.ZERO
		if probe_cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
			return Vector2i.ZERO
	return facing


func _random_direction(rng: RandomNumberGenerator) -> Vector2i:
	return _sanitize_direction(Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1)), rng)


func _sanitize_direction(dir: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var sx: int = signi(dir.x)
	var sy: int = signi(dir.y)
	if sx == 0 and sy == 0:
		if rng.randf() < 0.5:
			sx = 1 if rng.randf() < 0.5 else -1
		else:
			sy = 1 if rng.randf() < 0.5 else -1
	return Vector2i(sx, sy)


func _generate_spawn_and_extraction_sites(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig
) -> void:
	if map_data == null or config == null:
		return
	map_data.player_spawn_points.clear()
	map_data.extraction_sites.clear()
	var empty_avoid_cells: Array[Vector2i] = []
	var spawn_cells: Array[Vector2i] = _select_layer_site_cells(
		map_data,
		config,
		config.player_spawn_layer_id,
		config.player_spawn_count,
		config.player_spawn_edge_margin_cells,
		config.player_spawn_clearance_radius_cells,
		config.player_spawn_min_clearance_ratio,
		config.player_spawn_min_distance_between_spawns_cells,
		empty_avoid_cells,
		0.0,
		"player_spawn"
	)
	for spawn_cell: Vector2i in spawn_cells:
		map_data.player_spawn_points.append(
			_build_site_entry(map_data, config, spawn_cell, "player_spawn", config.player_spawn_layer_id)
		)
	var reserved_cells: Array[Vector2i] = _duplicate_vector2i_array(spawn_cells)
	var extraction_layer_counts: Array[Dictionary] = _resolve_site_layer_count_entries(
		config.extraction_site_count,
		config.extraction_site_layer_distribution
	)
	for layer_count_entry: Dictionary in extraction_layer_counts:
		var layer_id: String = str(layer_count_entry.get("layer_id", ""))
		var target_count: int = int(layer_count_entry.get("count", 0))
		if target_count <= 0:
			continue
		var extraction_cells: Array[Vector2i] = _select_layer_site_cells(
			map_data,
			config,
			layer_id,
			target_count,
			config.extraction_site_edge_margin_cells,
			config.extraction_site_clearance_radius_cells,
			config.extraction_site_min_clearance_ratio,
			config.extraction_site_min_distance_between_sites_cells,
			reserved_cells,
			config.extraction_site_min_distance_from_player_spawns_cells,
			"extraction"
		)
		for extraction_cell: Vector2i in extraction_cells:
			map_data.extraction_sites.append(
				_build_site_entry(map_data, config, extraction_cell, "extraction", layer_id)
			)
			reserved_cells.append(extraction_cell)


func _select_layer_site_cells(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	target_layer_id: String,
	target_count: int,
	edge_margin_cells: int,
	clearance_radius_cells: int,
	min_clearance_ratio: float,
	min_distance_between_sites_cells: float,
	avoid_cells: Array[Vector2i],
	min_distance_from_avoid_cells: float,
	site_kind: String
) -> Array[Vector2i]:
	var selected_cells: Array[Vector2i] = []
	if map_data == null or target_count <= 0:
		return selected_cells
	var layer_id: String = target_layer_id.strip_edges()
	var candidates: Array[Dictionary] = _collect_layer_site_candidates(
		map_data,
		config,
		layer_id,
		edge_margin_cells,
		clearance_radius_cells,
		min_clearance_ratio,
		avoid_cells,
		min_distance_from_avoid_cells
	)
	if candidates.is_empty():
		return selected_cells
	var used_keys: Dictionary = _cell_key_lookup(avoid_cells)
	var passes: Array[Dictionary] = [
		{
			"require_floor": true,
			"require_clearance": true,
			"require_avoid_distance": true,
			"enforce_between_distance": true,
			"fallback_reason": "",
		},
		{
			"require_floor": true,
			"require_clearance": false,
			"require_avoid_distance": true,
			"enforce_between_distance": true,
			"fallback_reason": "relaxed_clearance",
		},
		{
			"require_floor": true,
			"require_clearance": false,
			"require_avoid_distance": false,
			"enforce_between_distance": true,
			"fallback_reason": "relaxed_source_distance",
		},
		{
			"require_floor": false,
			"require_clearance": false,
			"require_avoid_distance": false,
			"enforce_between_distance": false,
			"fallback_reason": "carved_layer_cell",
		},
	]
	for pass_config: Dictionary in passes:
		_append_site_cells_from_pass(
			map_data,
			candidates,
			selected_cells,
			used_keys,
			target_count,
			min_distance_between_sites_cells,
			bool(pass_config.get("require_floor", true)),
			bool(pass_config.get("require_clearance", true)),
			bool(pass_config.get("require_avoid_distance", true)),
			bool(pass_config.get("enforce_between_distance", true)),
			str(pass_config.get("fallback_reason", "")),
			site_kind
		)
		if selected_cells.size() >= target_count:
			break
	if site_kind == "player_spawn" and selected_cells.size() < target_count:
		map_data.set_meta(
			"player_spawn_shortfall",
			maxi(target_count - selected_cells.size(), 0)
		)
		push_warning(
			"WdcMapGenerationGenerator: 玩家出生锚点不足 actual=%d target=%d hard_distance=%.2f"
			% [selected_cells.size(), target_count, PLAYER_SPAWN_HARD_MIN_DISTANCE_CELLS]
		)
	return selected_cells


func _collect_layer_site_candidates(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	target_layer_id: String,
	edge_margin_cells: int,
	clearance_radius_cells: int,
	min_clearance_ratio: float,
	avoid_cells: Array[Vector2i],
	min_distance_from_avoid_cells: float
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var min_avoid_distance_sq: float = min_distance_from_avoid_cells * min_distance_from_avoid_cells
	var resolved_edge_margin: int = maxi(edge_margin_cells, 0)
	var center: Vector2 = Vector2((float(map_data.width) - 1.0) * 0.5, (float(map_data.height) - 1.0) * 0.5)
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			if (
				x < resolved_edge_margin
				or y < resolved_edge_margin
				or x >= map_data.width - resolved_edge_margin
				or y >= map_data.height - resolved_edge_margin
			):
				continue
			var cell_coord: Vector2i = Vector2i(x, y)
			var layer: Dictionary = _resolve_layer_for_cell(config, map_data, cell_coord)
			var layer_id: String = str(layer.get("id", ""))
			if not target_layer_id.is_empty() and layer_id != target_layer_id:
				continue
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			var is_clean_floor: bool = _is_site_floor_cell(cell)
			var clearance_ratio: float = _compute_site_clearance_ratio(
				map_data,
				cell_coord,
				clearance_radius_cells
			)
			var avoid_distance_ok: bool = true
			if not avoid_cells.is_empty() and min_avoid_distance_sq > 0.0:
				for avoid_cell: Vector2i in avoid_cells:
					var candidate_point: Vector2 = Vector2(float(cell_coord.x), float(cell_coord.y))
					var avoid_point: Vector2 = Vector2(float(avoid_cell.x), float(avoid_cell.y))
					if candidate_point.distance_squared_to(avoid_point) < min_avoid_distance_sq:
						avoid_distance_ok = false
						break
			candidates.append({
				"cell": cell_coord,
				"layer_id": layer_id,
				"is_floor": is_clean_floor,
				"clearance_ok": clearance_ratio >= min_clearance_ratio,
				"avoid_distance_ok": avoid_distance_ok,
				"clearance_ratio": clearance_ratio,
				"center_distance_sq": Vector2(float(x), float(y)).distance_squared_to(center),
				"tie": _stable_site_tie_breaker(cell_coord, target_layer_id),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var clearance_delta: float = float(b.get("clearance_ratio", 0.0)) - float(a.get("clearance_ratio", 0.0))
		if absf(clearance_delta) > 0.0001:
			return float(a.get("clearance_ratio", 0.0)) > float(b.get("clearance_ratio", 0.0))
		var target_is_outer: bool = target_layer_id == "outer"
		var a_distance: float = float(a.get("center_distance_sq", 0.0))
		var b_distance: float = float(b.get("center_distance_sq", 0.0))
		if absf(a_distance - b_distance) > 0.0001:
			return a_distance > b_distance if target_is_outer else a_distance < b_distance
		return int(a.get("tie", 0)) < int(b.get("tie", 0))
	)
	return candidates


func _append_site_cells_from_pass(
	map_data: WdcMapGenerationTypes.MapData,
	candidates: Array[Dictionary],
	selected_cells: Array[Vector2i],
	used_keys: Dictionary,
	target_count: int,
	min_distance_between_sites_cells: float,
	require_floor: bool,
	require_clearance: bool,
	require_avoid_distance: bool,
	enforce_between_distance: bool,
	fallback_reason: String,
	site_kind: String
) -> void:
	var ordered_candidates: Array[Dictionary] = candidates
	if target_count == 1 and site_kind == "player_spawn":
		ordered_candidates = candidates.duplicate(true)
		ordered_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_tie: int = int(a.get("tie", 0))
			var b_tie: int = int(b.get("tie", 0))
			if a_tie != b_tie:
				return a_tie < b_tie
			var a_cell: Vector2i = a.get("cell", Vector2i.ZERO)
			var b_cell: Vector2i = b.get("cell", Vector2i.ZERO)
			return a_cell.y < b_cell.y if a_cell.y != b_cell.y else a_cell.x < b_cell.x
		)
	var resolved_enforce_between_distance: bool = enforce_between_distance
	var resolved_min_distance_between_sites_cells: float = min_distance_between_sites_cells
	if site_kind == "player_spawn":
		resolved_min_distance_between_sites_cells = maxf(
			(
				resolved_min_distance_between_sites_cells
				if resolved_enforce_between_distance
				else 0.0
			),
			PLAYER_SPAWN_HARD_MIN_DISTANCE_CELLS
		)
		resolved_enforce_between_distance = true
		_append_player_spawn_cells_max_min_from_pass(
			map_data,
			ordered_candidates,
			selected_cells,
			used_keys,
			target_count,
			resolved_min_distance_between_sites_cells,
			require_floor,
			require_clearance,
			require_avoid_distance,
			resolved_enforce_between_distance,
			fallback_reason,
			site_kind
		)
		return
	var min_between_sq: float = (
		resolved_min_distance_between_sites_cells
		* resolved_min_distance_between_sites_cells
	)
	for candidate: Dictionary in candidates:
		if selected_cells.size() >= target_count:
			return
		if require_floor and not bool(candidate.get("is_floor", false)):
			continue
		if require_clearance and not bool(candidate.get("clearance_ok", false)):
			continue
		if require_avoid_distance and not bool(candidate.get("avoid_distance_ok", false)):
			continue
		var cell: Vector2i = candidate.get("cell", Vector2i(-1, -1))
		var key: String = _key(cell.x, cell.y)
		if bool(used_keys.get(key, false)):
			continue
		if resolved_enforce_between_distance and min_between_sq > 0.0:
			var too_close: bool = false
			for selected_cell: Vector2i in selected_cells:
				var candidate_point: Vector2 = Vector2(float(cell.x), float(cell.y))
				var selected_point: Vector2 = Vector2(float(selected_cell.x), float(selected_cell.y))
				if candidate_point.distance_squared_to(selected_point) < min_between_sq:
					too_close = true
					break
			if too_close:
				continue
		if not bool(candidate.get("is_floor", false)):
			_carve_site_floor_cell(map_data, cell)
		used_keys[key] = true
		selected_cells.append(cell)
		if not fallback_reason.is_empty():
			_record_site_fallback_reason(map_data, cell, site_kind, fallback_reason)


## 方法职责：在同一 fallback pass 内以 max-min 规则选择玩家出生锚点。
## 边界约束：候选排序只负责首点与同分决胜，后续点优先最大化到已选点的最小距离。
func _append_player_spawn_cells_max_min_from_pass(
	map_data: WdcMapGenerationTypes.MapData,
	candidates: Array[Dictionary],
	selected_cells: Array[Vector2i],
	used_keys: Dictionary,
	target_count: int,
	min_distance_between_sites_cells: float,
	require_floor: bool,
	require_clearance: bool,
	require_avoid_distance: bool,
	enforce_between_distance: bool,
	fallback_reason: String,
	site_kind: String
) -> void:
	var min_between_sq: float = min_distance_between_sites_cells * min_distance_between_sites_cells
	while selected_cells.size() < target_count:
		var best_candidate: Dictionary = {}
		var best_min_distance_sq: float = -1.0
		for candidate: Dictionary in candidates:
			if require_floor and not bool(candidate.get("is_floor", false)):
				continue
			if require_clearance and not bool(candidate.get("clearance_ok", false)):
				continue
			if require_avoid_distance and not bool(candidate.get("avoid_distance_ok", false)):
				continue
			var cell: Vector2i = candidate.get("cell", Vector2i(-1, -1))
			if bool(used_keys.get(_key(cell.x, cell.y), false)):
				continue
			var nearest_selected_distance_sq: float = INF
			for selected_cell: Vector2i in selected_cells:
				nearest_selected_distance_sq = minf(
					nearest_selected_distance_sq,
					Vector2(float(cell.x), float(cell.y)).distance_squared_to(
						Vector2(float(selected_cell.x), float(selected_cell.y))
					)
				)
			if selected_cells.is_empty():
				nearest_selected_distance_sq = 0.0
			elif enforce_between_distance and nearest_selected_distance_sq < min_between_sq:
				continue
			if best_candidate.is_empty() or nearest_selected_distance_sq > best_min_distance_sq:
				best_candidate = candidate
				best_min_distance_sq = nearest_selected_distance_sq
		if best_candidate.is_empty():
			return
		var selected_cell: Vector2i = best_candidate.get("cell", Vector2i(-1, -1))
		if not bool(best_candidate.get("is_floor", false)):
			_carve_site_floor_cell(map_data, selected_cell)
		used_keys[_key(selected_cell.x, selected_cell.y)] = true
		selected_cells.append(selected_cell)
		if not fallback_reason.is_empty():
			_record_site_fallback_reason(map_data, selected_cell, site_kind, fallback_reason)


func _build_site_entry(
	map_data: WdcMapGenerationTypes.MapData,
	config: WdcMapGenerationTypes.MapConfig,
	cell: Vector2i,
	site_kind: String,
	requested_layer_id: String
) -> Dictionary:
	var layer: Dictionary = _resolve_layer_for_cell(config, map_data, cell)
	var entry: Dictionary = {
		"x": cell.x,
		"y": cell.y,
		"site_kind": site_kind,
		"layer_id": str(layer.get("id", "")),
		"requested_layer_id": requested_layer_id,
	}
	var fallback_key: String = _site_fallback_meta_key(site_kind, cell)
	if map_data.has_meta(fallback_key):
		entry["fallback_reason"] = str(map_data.get_meta(fallback_key))
	return entry


func _record_site_fallback_reason(
	map_data: WdcMapGenerationTypes.MapData,
	cell: Vector2i,
	site_kind: String,
	fallback_reason: String
) -> void:
	if map_data == null or fallback_reason.is_empty():
		return
	map_data.set_meta(_site_fallback_meta_key(site_kind, cell), fallback_reason)


func _site_fallback_meta_key(site_kind: String, cell: Vector2i) -> String:
	return "%s_%d_%d" % [site_kind, cell.x, cell.y]


func _is_site_floor_cell(cell: WdcMapGenerationTypes.CellData) -> bool:
	return (
		cell != null
		and cell.cell_type == WdcMapGenerationTypes.CellType.FLOOR
		and cell.special_block_type == WdcMapGenerationTypes.SpecialBlockType.NONE
	)


func _carve_site_floor_cell(
	map_data: WdcMapGenerationTypes.MapData,
	cell_coord: Vector2i
) -> void:
	if map_data == null or not map_data.is_in_bounds(cell_coord.x, cell_coord.y):
		return
	var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(cell_coord.x, cell_coord.y)
	if cell == null:
		return
	cell.cell_type = WdcMapGenerationTypes.CellType.FLOOR
	cell.has_mineral = false
	cell.special_block_type = WdcMapGenerationTypes.SpecialBlockType.NONE
	cell.poi_type = WdcMapGenerationTypes.PoiType.NONE
	cell.trace_type = WdcMapGenerationTypes.PoiType.NONE
	cell.is_poi_protected = false
	WdcMapGenerationTileRules.refresh_cell_runtime_state(cell)


func _compute_site_clearance_ratio(
	map_data: WdcMapGenerationTypes.MapData,
	center_cell: Vector2i,
	radius_cells: int
) -> float:
	var radius: int = maxi(radius_cells, 0)
	if radius <= 0:
		var center_data: WdcMapGenerationTypes.CellData = map_data.get_cell(center_cell.x, center_cell.y)
		return 1.0 if _is_site_floor_cell(center_data) else 0.0
	var total_count: int = 0
	var floor_count: int = 0
	for y: int in range(center_cell.y - radius, center_cell.y + radius + 1):
		for x: int in range(center_cell.x - radius, center_cell.x + radius + 1):
			total_count += 1
			if not map_data.is_in_bounds(x, y):
				continue
			if _is_site_floor_cell(map_data.get_cell(x, y)):
				floor_count += 1
	if total_count <= 0:
		return 0.0
	return float(floor_count) / float(total_count)


func _resolve_site_layer_count_entries(
	total_count: int,
	distribution: Array[Dictionary]
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if total_count <= 0:
		return entries
	var total_ratio: float = 0.0
	for distribution_entry: Dictionary in distribution:
		var layer_id: String = str(distribution_entry.get("layer_id", "")).strip_edges()
		var ratio: float = maxf(float(distribution_entry.get("ratio", 0.0)), 0.0)
		if layer_id.is_empty() or ratio <= 0.0:
			continue
		total_ratio += ratio
		entries.append({
			"layer_id": layer_id,
			"ratio": ratio,
			"count": 0,
			"remainder": 0.0,
		})
	if entries.is_empty():
		entries.append({
			"layer_id": "inner",
			"ratio": 1.0,
			"count": total_count,
			"remainder": 0.0,
		})
		return entries
	var assigned: int = 0
	for entry: Dictionary in entries:
		var exact_count: float = float(total_count) * float(entry.get("ratio", 0.0)) / total_ratio
		var base_count: int = int(floor(exact_count))
		entry["count"] = base_count
		entry["remainder"] = exact_count - float(base_count)
		assigned += base_count
	if total_count >= entries.size():
		for entry: Dictionary in entries:
			if int(entry.get("count", 0)) > 0:
				continue
			entry["count"] = 1
			assigned += 1
	while assigned > total_count:
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.get("count", 0)) == int(b.get("count", 0)):
				return float(a.get("ratio", 0.0)) < float(b.get("ratio", 0.0))
			return int(a.get("count", 0)) > int(b.get("count", 0))
		)
		for entry: Dictionary in entries:
			if int(entry.get("count", 0)) > 0:
				entry["count"] = int(entry["count"]) - 1
				assigned -= 1
				break
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a.get("remainder", 0.0)) - float(b.get("remainder", 0.0))) > 0.0001:
			return float(a.get("remainder", 0.0)) > float(b.get("remainder", 0.0))
		return float(a.get("ratio", 0.0)) > float(b.get("ratio", 0.0))
	)
	while assigned < total_count:
		for entry: Dictionary in entries:
			if assigned >= total_count:
				break
			entry["count"] = int(entry.get("count", 0)) + 1
			assigned += 1
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("layer_id", "")).nocasecmp_to(str(b.get("layer_id", ""))) < 0
	)
	return entries


func _cell_key_lookup(cells: Array[Vector2i]) -> Dictionary:
	var lookup: Dictionary = {}
	for cell: Vector2i in cells:
		lookup[_key(cell.x, cell.y)] = true
	return lookup


func _duplicate_vector2i_array(cells: Array[Vector2i]) -> Array[Vector2i]:
	var duplicated: Array[Vector2i] = []
	for cell: Vector2i in cells:
		duplicated.append(cell)
	return duplicated


func _stable_site_tie_breaker(cell: Vector2i, salt: String) -> int:
	var base_seed: int = last_resolved_seed if last_resolved_seed != 0 else 1
	var salt_hash: int = abs(salt.hash())
	return abs(
		int(cell.x * 73856093)
		^ int(cell.y * 19349663)
		^ int(base_seed * 83492791)
		^ salt_hash
	)


func _stable_four_region_site_tie_breaker(
	cell: Vector2i,
	salt: String,
	resolved_seed: int,
	attempt_index: int
) -> int:
	return abs(
		int(cell.x * 73856093)
		^ int(cell.y * 19349663)
		^ int(maxi(resolved_seed, 1) * 83492791)
		^ int((attempt_index + 1) * 265443576)
		^ abs(salt.hash())
	)


func _key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


func _build_server_tile_matrix(map_data: WdcMapGenerationTypes.MapData) -> Array[Array]:
	var matrix: Array[Array] = []
	matrix.resize(map_data.height)
	for y: int in range(map_data.height):
		var row: Array = []
		row.resize(map_data.width)
		for x: int in range(map_data.width):
			var cell: WdcMapGenerationTypes.CellData = map_data.get_cell(x, y)
			row[x] = _encode_server_tile(cell)
		matrix[y] = row
	return matrix


func _encode_server_tile(cell: WdcMapGenerationTypes.CellData) -> int:
	return WdcMapGenerationTypes.encode_server_tile(cell)
