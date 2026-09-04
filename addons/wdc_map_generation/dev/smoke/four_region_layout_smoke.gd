extends SceneTree

const CONFIG_CATALOG = preload("../../config/data_generated_map_config_catalog.gd")
const MAP_TYPES = preload("../../core/generated_map_types.gd")
const LAYOUT_PRODUCER_SCRIPT = preload("../../core/four_region_layout_producer.gd")
const LAYOUT_VALIDATOR_SCRIPT = preload("../../core/four_region_layout_validator.gd")

var _failures: Array[String] = []


func _init() -> void:
	var raw_config: Dictionary = CONFIG_CATALOG.load_config_dict_by_filename("ancient_old_mine")
	var parse_result = CONFIG_CATALOG.parse_and_normalize_config(raw_config)
	_expect(
		parse_result.is_success(),
		"ancient_old_mine 布局 smoke 配置解析失败：%s" % str(parse_result.get_issues())
	)
	if parse_result.is_success():
		_test_seed_corpus(parse_result.config)
		_test_map_sizes(parse_result.config)
		_test_retry_exhaustion(parse_result.config)
	_test_canonical_center_tie_break()
	_finish()


func _test_seed_corpus(config: Variant) -> void:
	var producer = LAYOUT_PRODUCER_SCRIPT.new()
	var validator = LAYOUT_VALIDATOR_SCRIPT.new()
	var non_regular_center_seed: int = -1
	for seed: int in range(1, 33):
		var first = _first_successful_draft(producer, config, seed)
		_expect(first != null, "seed %d 必须在 max_attempts 内生成合法布局" % seed)
		if first == null:
			continue
		var second = _first_successful_draft(producer, config, seed)
		_expect(second != null, "seed %d 重复生成不得失败" % seed)
		if second == null:
			continue
		_expect(first.attempt_index == second.attempt_index, "seed %d 成功 attempt 必须稳定" % seed)
		_expect(first.membership == second.membership, "seed %d membership 必须稳定" % seed)
		_expect(first.centers_by_role == second.centers_by_role, "seed %d canonical center 必须稳定" % seed)
		var issues: Array = validator.validate(first.map_size, first.membership)
		_expect(issues.is_empty(), "seed %d 空间不变量失败：%s" % [seed, issues])
		_validate_edge_margins_and_boundaries(
			config,
			validator,
			first.map_size,
			first.membership,
			seed
		)
		var geometry_center: Vector2i = Vector2i(first.map_size.x / 2, first.map_size.y / 2)
		var center_region_index: int = int(
			first.membership[geometry_center.y * first.map_size.x + geometry_center.x]
		)
		if center_region_index != 0 and non_regular_center_seed < 0:
			non_regular_center_seed = seed
	_expect(
		non_regular_center_seed > 0,
		"固定 seeds 1..32 中至少一个布局的地图几何中心必须落入非 regular，证明中心无特殊语义"
	)
	if non_regular_center_seed > 0:
		print("four_region_layout_smoke: non_regular_center_seed=%d" % non_regular_center_seed)


func _validate_edge_margins_and_boundaries(
	config: Variant,
	validator: Variant,
	map_size: Vector2i,
	membership: PackedInt32Array,
	seed: int
) -> void:
	for region_index: int in range(1, MAP_TYPES.REGION_ROLE_ORDER.size()):
		var role: String = MAP_TYPES.REGION_ROLE_ORDER[region_index]
		var slot: Dictionary = config.region_layout.get(role, {}) as Dictionary
		var profile: Dictionary = config.try_get_region_layout_profile(
			str(slot.get("layout_profile_id", ""))
		)
		var margin: int = int(profile.get("edge_margin_cells", 0))
		var cell_count: int = 0
		for flat_index: int in range(membership.size()):
			if int(membership[flat_index]) != region_index:
				continue
			cell_count += 1
			var cell: Vector2i = Vector2i(flat_index % map_size.x, flat_index / map_size.x)
			_expect(
				cell.x >= margin
				and cell.y >= margin
				and cell.x < map_size.x - margin
				and cell.y < map_size.y - margin,
				"seed %d 的 %s 越过 regular edge margin" % [seed, role]
			)
		_expect(cell_count > 0, "seed %d 的 %s 不得为空" % [seed, role])
		_expect(
			not validator.collect_regular_boundary_cells(
				map_size,
				membership,
				region_index
			).is_empty(),
			"seed %d 的 %s 必须拥有独立 regular 接触边界" % [seed, role]
		)


func _test_map_sizes(config: Variant) -> void:
	var producer = LAYOUT_PRODUCER_SCRIPT.new()
	var validator = LAYOUT_VALIDATOR_SCRIPT.new()
	for map_size: Vector2i in [
		Vector2i(128, 128),
		Vector2i(144, 128),
		Vector2i(160, 144),
	]:
		var sized_config = config.deep_clone()
		sized_config.width = map_size.x
		sized_config.height = map_size.y
		var draft = _first_successful_draft(producer, sized_config, 17)
		_expect(draft != null, "尺寸 %s 必须在 max_attempts 内生成合法布局" % map_size)
		if draft == null:
			continue
		_expect(draft.map_size == map_size, "尺寸 %s 的布局结果尺寸不一致" % map_size)
		_expect(
			validator.validate(draft.map_size, draft.membership).is_empty(),
			"尺寸 %s 的布局必须满足空间不变量" % map_size
		)


func _test_retry_exhaustion(config: Variant) -> void:
	var impossible_config = config.deep_clone()
	for profile: Dictionary in impossible_config.region_generation.get("layout_profiles", []) as Array:
		profile["min_size_cells"] = {"x": 512, "y": 512}
		profile["max_size_cells"] = {"x": 512, "y": 512}
		profile["max_attempts"] = 3
	var producer = LAYOUT_PRODUCER_SCRIPT.new()
	var max_attempts: int = producer.get_max_attempts(impossible_config)
	_expect(max_attempts == 3, "重试耗尽 smoke 必须使用有界 max_attempts")
	for attempt_index: int in range(max_attempts):
		var draft = producer.build_attempt(impossible_config, 7, attempt_index)
		_expect(not draft.is_success(), "不可能布局的 attempt %d 不得成功" % attempt_index)
		_expect(
			_has_issue(draft.get_issues(), "region_partition_failed"),
			"不可能布局的 attempt %d 必须返回 region_partition_failed" % attempt_index
		)


func _test_canonical_center_tie_break() -> void:
	var map_size: Vector2i = Vector2i(4, 4)
	var membership: PackedInt32Array = PackedInt32Array()
	membership.resize(map_size.x * map_size.y)
	membership.fill(0)
	for cell: Vector2i in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]:
		membership[cell.y * map_size.x + cell.x] = 1
	var centers: Dictionary = LAYOUT_VALIDATOR_SCRIPT.new().compute_canonical_centers(
		map_size,
		membership
	)
	_expect(
		centers.get(MAP_TYPES.REGION_ROLE_HIGH_1, Vector2i(-1, -1)) == Vector2i(1, 1),
		"canonical center 等距时必须先按 y、再按 x 选择"
	)


func _first_successful_draft(producer: Variant, config: Variant, seed: int) -> Variant:
	for attempt_index: int in range(producer.get_max_attempts(config)):
		var draft = producer.build_attempt(config, seed, attempt_index)
		if draft.is_success():
			return draft
	return null


func _has_issue(issues_value: Variant, code: String) -> bool:
	if not (issues_value is Array):
		return false
	for issue_value: Variant in issues_value as Array:
		if issue_value is Dictionary and str((issue_value as Dictionary).get("code", "")) == code:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("four_region_layout_smoke: %s" % failure)
		quit(1)
		return
	print("four_region_layout_smoke: PASS")
	quit(0)
