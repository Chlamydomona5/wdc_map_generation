class_name WdcRegionContentResolver
extends RefCounted

const WdcMapGenerationTypes = preload("generated_map_types.gd")

var _config: WdcMapGenerationTypes.MapConfig = null
var _region_plan: Variant = null
var _profiles_by_id: Dictionary = {}
var _remaining_budgets_by_role: Dictionary = {}


func _init(
	config: WdcMapGenerationTypes.MapConfig = null,
	region_plan: Variant = null
) -> void:
	_config = config
	_region_plan = region_plan
	_index_profiles()


func is_ready() -> bool:
	return (
		_config != null
		and _region_plan is WdcMapGenerationTypes.RegionPlan
		and not _profiles_by_id.is_empty()
	)


func resolve_cell(cell: Vector2i) -> Dictionary:
	if not is_ready():
		return _failure("region_content_resolver_not_ready", "RegionContentResolver 尚未初始化")
	var region = (_region_plan as WdcMapGenerationTypes.RegionPlan).try_get_at(cell)
	if region == null:
		return _failure("region_membership_missing", "坐标不属于任何区域")
	return _resolve_region_snapshot(region)


func resolve_role(role: String) -> Dictionary:
	if not is_ready():
		return _failure("region_content_resolver_not_ready", "RegionContentResolver 尚未初始化")
	var region = (_region_plan as WdcMapGenerationTypes.RegionPlan).try_get_by_role(role)
	if region == null:
		return _failure("region_role_missing", "RegionPlan 缺少目标区域：%s" % role)
	return _resolve_region_snapshot(region)


func is_cell_in_role(cell: Vector2i, role: String) -> bool:
	var resolved: Dictionary = resolve_cell(cell)
	return bool(resolved.get("valid", false)) and str(resolved.get("role", "")) == role


func resolve_footprint_for_role(cells: Array, role: String) -> Dictionary:
	var resolved: Dictionary = resolve_footprint(cells)
	if not bool(resolved.get("valid", false)):
		return resolved
	if str(resolved.get("role", "")) != role:
		return _failure(
			"content_footprint_role_mismatch",
			"内容 footprint 不属于目标区域：%s" % role
		)
	return resolved


func filter_cells_for_role(role: String, cells: Array) -> Array[Vector2i]:
	var filtered: Array[Vector2i] = []
	for cell_value: Variant in cells:
		if not (cell_value is Vector2i):
			continue
		var cell: Vector2i = cell_value as Vector2i
		if is_cell_in_role(cell, role):
			filtered.append(cell)
	return filtered


func _resolve_region_snapshot(region: Variant) -> Dictionary:
	var profile_value: Variant = _profiles_by_id.get(region.content_profile_id, null)
	if not (profile_value is Dictionary):
		return _failure("unknown_content_profile_reference", "区域引用的 content profile 不存在")
	return {
		"valid": true,
		"region_index": region.index,
		"region_id": region.id,
		"role": region.role,
		"difficulty_rank": region.difficulty_rank,
		"content_profile_id": region.content_profile_id,
		"profile": (profile_value as Dictionary).duplicate(true),
	}


func resolve_footprint(cells: Array) -> Dictionary:
	if cells.is_empty():
		return _failure("empty_region_footprint", "内容 footprint 不能为空")
	if not (cells[0] is Vector2i):
		return _failure("invalid_region_footprint", "内容 footprint 必须由 Vector2i 坐标组成")
	var resolved: Dictionary = resolve_cell(cells[0] as Vector2i)
	if not bool(resolved.get("valid", false)):
		return resolved
	var expected_index: int = int(resolved.get("region_index", -1))
	for cell_value: Variant in cells:
		if not (cell_value is Vector2i):
			return _failure("invalid_region_footprint", "内容 footprint 必须由 Vector2i 坐标组成")
		var cell: Vector2i = cell_value as Vector2i
		var current: Dictionary = resolve_cell(cell)
		if not bool(current.get("valid", false)):
			return current
		if int(current.get("region_index", -1)) != expected_index:
			return _failure("content_footprint_crosses_region", "内容 footprint 不得跨越区域边界")
	return resolved


func get_profile_for_role(role: String) -> Dictionary:
	if not is_ready():
		return {}
	var region = (_region_plan as WdcMapGenerationTypes.RegionPlan).try_get_by_role(role)
	if region == null:
		return {}
	var profile_value: Variant = _profiles_by_id.get(region.content_profile_id, null)
	return (profile_value as Dictionary).duplicate(true) if profile_value is Dictionary else {}


func get_section_for_role(role: String, section_name: String) -> Dictionary:
	var profile: Dictionary = get_profile_for_role(role)
	var section_value: Variant = profile.get(section_name, null)
	return (section_value as Dictionary).duplicate(true) if section_value is Dictionary else {}


func get_wall_hit_points(cell: Vector2i, wall_kind: String) -> int:
	var resolved: Dictionary = resolve_cell(cell)
	if not bool(resolved.get("valid", false)):
		return 1
	var profile: Dictionary = resolved.get("profile", {}) as Dictionary
	var durability: Dictionary = profile.get("wall_durability", {}) as Dictionary
	match wall_kind:
		"mineral":
			return maxi(int(durability.get("mineral_max_hit_points", 1)), 1)
		"poi":
			return maxi(int(durability.get("poi_max_hit_points", 1)), 1)
		_:
			return maxi(int(durability.get("ordinary_max_hit_points", 1)), 1)


func get_value_budget(role: String, budget_name: String) -> int:
	var profile: Dictionary = get_profile_for_role(role)
	if budget_name not in ["mineral_value_budget", "reward_value_budget"]:
		return 0
	return maxi(int(profile.get(budget_name, 0)), 0)


func get_remaining_value_budget(role: String, budget_name: String) -> int:
	if budget_name not in ["mineral_value_budget", "reward_value_budget"]:
		return 0
	var role_budgets_value: Variant = _remaining_budgets_by_role.get(role, null)
	if not (role_budgets_value is Dictionary):
		return get_value_budget(role, budget_name)
	return maxi(int((role_budgets_value as Dictionary).get(budget_name, 0)), 0)


func can_spend_value_budget(role: String, budget_name: String, value_cost: int) -> bool:
	return value_cost >= 0 and value_cost <= get_remaining_value_budget(role, budget_name)


func try_spend_value_budget(role: String, budget_name: String, value_cost: int) -> bool:
	if not can_spend_value_budget(role, budget_name, value_cost):
		return false
	var role_budgets: Dictionary = (
		_remaining_budgets_by_role.get(role, {}) as Dictionary
	).duplicate(true)
	role_budgets[budget_name] = get_remaining_value_budget(role, budget_name) - value_cost
	_remaining_budgets_by_role[role] = role_budgets
	return true


func select_candidates(
	role: String,
	section_name: String,
	candidates: Array[Dictionary],
	seed_salt: int = 0
) -> Dictionary:
	var section: Dictionary = get_section_for_role(role, section_name)
	if section.is_empty():
		return {
			"success": false,
			"selected": [],
			"issues": [_issue(
				"unknown_content_profile_section",
				"region_generation.content_profiles.%s" % section_name,
				role,
				"区域 content profile 缺少内容分组"
			)],
		}
	var target_count: int = maxi(int(section.get("target_count", 0)), 0)
	var minimum_count: int = clampi(int(section.get("minimum_count", 0)), 0, target_count)
	if target_count == 0:
		return {"success": true, "selected": [], "issues": []}
	var ordered: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		var copied: Dictionary = candidate.duplicate(true)
		copied["_stable_order"] = _stable_candidate_order(candidate, seed_salt)
		ordered.append(copied)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var order_a: int = int(a.get("_stable_order", 0))
		var order_b: int = int(b.get("_stable_order", 0))
		if order_a != order_b:
			return order_a < order_b
		return _candidate_identity(a) < _candidate_identity(b)
	)
	var selected: Array[Dictionary] = []
	for candidate: Dictionary in ordered:
		if selected.size() >= target_count:
			break
		candidate.erase("_stable_order")
		selected.append(candidate)
	if selected.size() < minimum_count:
		return {
			"success": false,
			"selected": [],
			"issues": [_issue(
				"content_minimum_not_met",
				"region_generation.content_profiles.%s" % section_name,
				role,
				"候选数量低于 minimum_count：%d < %d" % [selected.size(), minimum_count]
			)],
		}
	return {"success": true, "selected": selected, "issues": []}


func get_weighted_entries(role: String, section_name: String) -> Array[Dictionary]:
	var section: Dictionary = get_section_for_role(role, section_name)
	var entries_value: Variant = section.get("entries", [])
	var result: Array[Dictionary] = []
	if entries_value is Array:
		for entry_value: Variant in entries_value as Array:
			if entry_value is Dictionary:
				var entry: Dictionary = (entry_value as Dictionary).duplicate(true)
				if float(entry.get("weight", 0.0)) > 0.0:
					result.append(entry)
	return result


func filter_entries_by_value_budget(
	role: String,
	section_name: String,
	remaining_value_budget: int,
	value_field: String = "value_cost"
) -> Array[Dictionary]:
	return _filter_entries_by_value_budget(
		get_weighted_entries(role, section_name),
		remaining_value_budget,
		value_field
	)


func pick_weighted_entry(
	role: String,
	section_name: String,
	rng: RandomNumberGenerator,
	remaining_value_budget: int = -1,
	value_field: String = "value"
) -> Dictionary:
	return pick_weighted_from_entries(
		get_weighted_entries(role, section_name),
		rng,
		remaining_value_budget,
		value_field
	)


func pick_weighted_from_entries(
	entries: Array[Dictionary],
	rng: RandomNumberGenerator,
	remaining_value_budget: int = -1,
	value_field: String = "value"
) -> Dictionary:
	var eligible: Array[Dictionary] = _filter_entries_by_value_budget(
		entries,
		remaining_value_budget,
		value_field
	)
	var total_weight: float = 0.0
	for entry: Dictionary in eligible:
		total_weight += maxf(float(entry.get("weight", 0.0)), 0.0)
	if eligible.is_empty() or total_weight <= 0.0:
		return {}
	var roll: float = rng.randf() * total_weight
	for entry: Dictionary in eligible:
		roll -= maxf(float(entry.get("weight", 0.0)), 0.0)
		if roll <= 0.0:
			return entry.duplicate(true)
	return eligible.back().duplicate(true)


func _filter_entries_by_value_budget(
	entries: Array[Dictionary],
	remaining_value_budget: int,
	value_field: String
) -> Array[Dictionary]:
	var eligible: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var entry_value: int = maxi(int(entry.get(value_field, 1)), 0)
		if remaining_value_budget >= 0 and entry_value > remaining_value_budget:
			continue
		var weight: float = maxf(float(entry.get("weight", 0.0)), 0.0)
		if weight <= 0.0:
			continue
		eligible.append(entry.duplicate(true))
	return eligible


func _index_profiles() -> void:
	_profiles_by_id.clear()
	_remaining_budgets_by_role.clear()
	if _config == null:
		return
	var generation_value: Variant = _config.get("region_generation")
	if not (generation_value is Dictionary):
		return
	var profiles_value: Variant = (generation_value as Dictionary).get("content_profiles", [])
	if not (profiles_value is Array):
		return
	for profile_value: Variant in profiles_value as Array:
		if not (profile_value is Dictionary):
			continue
		var profile: Dictionary = profile_value as Dictionary
		var profile_id: String = str(profile.get("id", ""))
		if not profile_id.is_empty():
			_profiles_by_id[profile_id] = profile.duplicate(true)
	if not is_ready():
		return
	for role: String in WdcMapGenerationTypes.REGION_ROLE_ORDER:
		_remaining_budgets_by_role[role] = {
			"mineral_value_budget": get_value_budget(role, "mineral_value_budget"),
			"reward_value_budget": get_value_budget(role, "reward_value_budget"),
		}


func _stable_candidate_order(candidate: Dictionary, seed_salt: int) -> int:
	var identity: String = "%s|%d" % [_candidate_identity(candidate), seed_salt]
	var hash_value: int = 2166136261
	for index: int in range(identity.length()):
		hash_value = hash_value ^ identity.unicode_at(index)
		hash_value = int((hash_value * 16777619) & 0x7fffffff)
	return hash_value


func _candidate_identity(candidate: Dictionary) -> String:
	if candidate.has("instance_id"):
		return str(candidate.get("instance_id", ""))
	if candidate.has("id"):
		return str(candidate.get("id", ""))
	var cell_value: Variant = candidate.get("cell", candidate.get("position", null))
	if cell_value is Vector2i:
		var cell: Vector2i = cell_value as Vector2i
		return "%d:%d" % [cell.x, cell.y]
	if cell_value is Dictionary:
		return "%d:%d" % [
			int((cell_value as Dictionary).get("x", 0)),
			int((cell_value as Dictionary).get("y", 0)),
		]
	return str(candidate)


func _failure(code: String, message: String) -> Dictionary:
	return {"valid": false, "issue": _issue(code, "region_content", "", message)}


func _issue(code: String, path: String, role: String, message: String) -> Dictionary:
	return WdcMapGenerationTypes.make_generation_issue(code, path, role, message)
