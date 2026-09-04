class_name WdcFourRegionLayoutProducer
extends RefCounted

const WdcMapGenerationTypes = preload("generated_map_types.gd")
const WdcFourRegionLayoutValidator = preload("four_region_layout_validator.gd")
const NOISY_ELLIPSE_BOUNDARY_AMPLITUDE: float = 0.16
const NOISY_ELLIPSE_BOUNDARY_SCALE: float = 1.85
const NOISY_ELLIPSE_BOUNDARY_OCTAVES: int = 3
const NOISY_ELLIPSE_BOUNDARY_PERSISTENCE: float = 0.55


class RegionLayoutDraftResult:
	extends RefCounted

	var map_size: Vector2i = Vector2i.ZERO
	var membership: PackedInt32Array = PackedInt32Array()
	var centers_by_role: Dictionary = {}
	var attempt_index: int = -1
	var issues: Array[Dictionary] = []

	func is_success() -> bool:
		return issues.is_empty() and not membership.is_empty()

	func get_issues() -> Array[Dictionary]:
		return issues.duplicate(true)


func get_max_attempts(config: WdcMapGenerationTypes.MapConfig) -> int:
	var max_attempts: int = 1
	for role: String in [
		WdcMapGenerationTypes.REGION_ROLE_HIGH_1,
		WdcMapGenerationTypes.REGION_ROLE_HIGH_2,
		WdcMapGenerationTypes.REGION_ROLE_BOSS,
	]:
		var profile: Dictionary = _resolve_layout_profile(config, role)
		max_attempts = maxi(max_attempts, int(profile.get("max_attempts", 1)))
	return maxi(max_attempts, 1)


func build_attempt(
	config: WdcMapGenerationTypes.MapConfig,
	resolved_seed: int,
	attempt_index: int
) -> RegionLayoutDraftResult:
	var result: RegionLayoutDraftResult = RegionLayoutDraftResult.new()
	result.map_size = Vector2i(config.width, config.height)
	result.attempt_index = attempt_index
	if result.map_size.x <= 0 or result.map_size.y <= 0:
		result.issues.append(_issue(
			"region_partition_failed",
			"map",
			"",
			"四区域地图尺寸无效"
		))
		return result
	result.membership.resize(result.map_size.x * result.map_size.y)
	result.membership.fill(0)
	var occupied_regions: Array[Dictionary] = []
	for region_index: int in range(1, WdcMapGenerationTypes.REGION_ROLE_ORDER.size()):
		var role: String = WdcMapGenerationTypes.REGION_ROLE_ORDER[region_index]
		var profile: Dictionary = _resolve_layout_profile(config, role)
		if profile.is_empty():
			result.issues.append(_issue(
				"region_partition_failed",
				"region_layout.%s.layout_profile_id" % role,
				role,
				"无法解析区域 layout profile"
			))
			return result
		var shape_algorithm: String = str(profile.get("shape_algorithm", "")).strip_edges()
		if shape_algorithm not in ["rectangle", "rounded_rectangle", "noisy_ellipse"]:
			result.issues.append(_issue(
				"region_partition_failed",
				"region_generation.layout_profiles.shape_algorithm",
				role,
				"不支持的四区域 shape_algorithm：%s" % shape_algorithm
			))
			return result
		var role_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		role_rng.seed = _derive_seed(
			resolved_seed,
			int(profile.get("seed_salt", 0)),
			attempt_index,
			region_index
		)
		var size: Vector2i = _sample_region_size(profile, result.map_size, role_rng, role)
		var placement: Dictionary = _place_region_mask(
			result.map_size,
			result.membership,
			occupied_regions,
			region_index,
			size,
			profile,
			role_rng
		)
		if placement.is_empty():
			result.issues.append(_issue(
				"region_partition_failed",
				"region_generation.layout_profiles",
				role,
				"当前 attempt 无法放置满足 margin/moat 的高风险区域"
			))
			return result
		for cell_value: Variant in placement.get("cells", []):
			var cell: Vector2i = cell_value as Vector2i
			result.membership[cell.y * result.map_size.x + cell.x] = region_index
		occupied_regions.append({
			"bounds": placement.get("bounds", Rect2i()),
			"moat": maxi(int(profile.get("regular_moat_cells", 1)), 1),
		})
	var validator: WdcFourRegionLayoutValidator = WdcFourRegionLayoutValidator.new()
	result.issues = validator.validate(result.map_size, result.membership)
	if result.issues.is_empty():
		result.centers_by_role = validator.compute_canonical_centers(
			result.map_size,
			result.membership
		)
	return result


func _place_region_mask(
	map_size: Vector2i,
	_membership: PackedInt32Array,
	occupied_regions: Array[Dictionary],
	region_index: int,
	size: Vector2i,
	profile: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var margin: int = maxi(int(profile.get("edge_margin_cells", 2)), 1)
	var moat: int = maxi(int(profile.get("regular_moat_cells", 1)), 1)
	var core_padding: int = maxi(int(profile.get("core_poi_padding_cells", 0)), 0)
	var required_margin: int = margin + core_padding
	if size.x + required_margin * 2 > map_size.x or size.y + required_margin * 2 > map_size.y:
		return {}
	var candidates: Array[Vector2i] = _build_center_candidates(map_size, size, required_margin, rng)
	for center: Vector2i in candidates:
		var bounds: Rect2i = Rect2i(
			center.x - int(floor(float(size.x) * 0.5)),
			center.y - int(floor(float(size.y) * 0.5)),
			size.x,
			size.y
		)
		var overlaps: bool = false
		for occupied: Dictionary in occupied_regions:
			var occupied_bounds: Rect2i = occupied.get("bounds", Rect2i())
			var required_moat: int = maxi(moat, int(occupied.get("moat", 1)))
			var expanded: Rect2i = Rect2i(
				bounds.position - Vector2i(required_moat, required_moat),
				bounds.size + Vector2i(required_moat * 2, required_moat * 2)
			)
			if expanded.intersects(occupied_bounds):
				overlaps = true
				break
		if overlaps:
			continue
		var mask_cells: Array[Vector2i] = _build_mask_cells(
			bounds,
			str(profile.get("shape_algorithm", "rounded_rect")),
			rng
		)
		if mask_cells.is_empty():
			continue
		return {"cells": mask_cells, "bounds": bounds, "region_index": region_index}
	return {}


func _build_center_candidates(
	map_size: Vector2i,
	size: Vector2i,
	margin: int,
	rng: RandomNumberGenerator
) -> Array[Vector2i]:
	var min_x: int = margin + int(ceili(float(size.x) * 0.5))
	var min_y: int = margin + int(ceili(float(size.y) * 0.5))
	var max_x: int = map_size.x - margin - int(ceili(float(size.x) * 0.5))
	var max_y: int = map_size.y - margin - int(ceili(float(size.y) * 0.5))
	if min_x > max_x or min_y > max_y:
		return []
	var normalized_anchors: Array[Vector2] = [
		Vector2(0.25, 0.25),
		Vector2(0.75, 0.25),
		Vector2(0.25, 0.75),
		Vector2(0.75, 0.75),
		Vector2(0.50, 0.50),
		Vector2(0.50, 0.25),
		Vector2(0.25, 0.50),
		Vector2(0.75, 0.50),
		Vector2(0.50, 0.75),
	]
	var result: Array[Vector2i] = []
	var seen: Dictionary = {}
	for anchor: Vector2 in normalized_anchors:
		var candidate: Vector2i = Vector2i(
			clampi(int(roundf(anchor.x * float(map_size.x - 1))), min_x, max_x),
			clampi(int(roundf(anchor.y * float(map_size.y - 1))), min_y, max_y)
		)
		_append_unique_cell(result, seen, candidate)
	var random_attempts: int = mini(maxi(map_size.x * map_size.y / 32, 64), 384)
	for _attempt: int in range(random_attempts):
		_append_unique_cell(
			result,
			seen,
			Vector2i(rng.randi_range(min_x, max_x), rng.randi_range(min_y, max_y))
		)
	# 固定锚点只用于保证有足够的稳定候选，不能永远先于随机候选被 first-fit 消费，
	# 否则外围锚点会隐式让地图几何中心长期保持 regular。
	_shuffle_variant_array(result, rng)
	return result


func _build_mask_cells(
	bounds: Rect2i,
	shape_algorithm: String,
	rng: RandomNumberGenerator
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var center: Vector2 = Vector2(bounds.get_center()) - Vector2(0.5, 0.5)
	var radius_x: float = maxf(float(bounds.size.x) * 0.5, 1.0)
	var radius_y: float = maxf(float(bounds.size.y) * 0.5, 1.0)
	var normalized_shape: String = shape_algorithm.strip_edges().to_lower()
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var include: bool = true
			if normalized_shape in ["ellipse", "noisy_ellipse"]:
				var normalized_x: float = (float(x) + 0.5 - center.x) / radius_x
				var normalized_y: float = (float(y) + 0.5 - center.y) / radius_y
				var normalized_radius: float = sqrt(
					normalized_x * normalized_x + normalized_y * normalized_y
				)
				var limit: float = 1.0
				if normalized_shape == "noisy_ellipse":
					var angle: float = atan2(normalized_y, normalized_x)
					limit += _sample_noisy_ellipse_boundary(angle, int(rng.seed)) * (
						NOISY_ELLIPSE_BOUNDARY_AMPLITUDE
					)
				include = normalized_radius <= limit
			elif normalized_shape == "rounded_rectangle":
				var corner_radius: float = maxf(minf(radius_x, radius_y) * 0.35, 1.0)
				var inner_x: float = radius_x - corner_radius
				var inner_y: float = radius_y - corner_radius
				var delta_x: float = maxf(abs(float(x) + 0.5 - center.x) - inner_x, 0.0)
				var delta_y: float = maxf(abs(float(y) + 0.5 - center.y) - inner_y, 0.0)
				include = delta_x * delta_x + delta_y * delta_y <= corner_radius * corner_radius
			if include:
				result.append(Vector2i(x, y))
	return result


## 方法职责：沿椭圆极角采样连续、首尾闭合的多频噪声，形成不规则但无孔洞的圆形边界。
## 边界约束：噪声只改变径向阈值，不改变中心和单值 membership，因此区域保持星形连通。
func _sample_noisy_ellipse_boundary(angle: float, seed: int) -> float:
	var direction: Vector2 = Vector2(cos(angle), sin(angle))
	var offset_x: float = float(_mix_u31(seed ^ 0x2f6e2b1) % 4096) / 257.0
	var offset_y: float = float(_mix_u31(seed ^ 0x5bd1e995) % 4096) / 263.0
	var total: float = 0.0
	var amplitude: float = 1.0
	var amplitude_sum: float = 0.0
	var frequency: float = 1.0
	for octave: int in range(NOISY_ELLIPSE_BOUNDARY_OCTAVES):
		var sample_position: Vector2 = direction * NOISY_ELLIPSE_BOUNDARY_SCALE * frequency
		total += _sample_value_noise_2d(
			sample_position.x + offset_x,
			sample_position.y + offset_y,
			seed + octave * 1013
		) * amplitude
		amplitude_sum += amplitude
		frequency *= 2.0
		amplitude *= NOISY_ELLIPSE_BOUNDARY_PERSISTENCE
	return total / amplitude_sum if amplitude_sum > 0.0 else 0.0


func _sample_value_noise_2d(sample_x: float, sample_y: float, seed: int) -> float:
	var x0: int = int(floor(sample_x))
	var y0: int = int(floor(sample_y))
	var x1: int = x0 + 1
	var y1: int = y0 + 1
	var tx: float = _smooth_noise_step(sample_x - float(x0))
	var ty: float = _smooth_noise_step(sample_y - float(y0))
	var top: float = lerpf(_hash_noise_2d(x0, y0, seed), _hash_noise_2d(x1, y0, seed), tx)
	var bottom: float = lerpf(_hash_noise_2d(x0, y1, seed), _hash_noise_2d(x1, y1, seed), tx)
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


func _sample_region_size(
	profile: Dictionary,
	map_size: Vector2i,
	rng: RandomNumberGenerator,
	role: String
) -> Vector2i:
	var default_ratio: float = 0.10
	match role:
		WdcMapGenerationTypes.REGION_ROLE_HIGH_1:
			default_ratio = 0.18
		WdcMapGenerationTypes.REGION_ROLE_HIGH_2:
			default_ratio = 0.14
		WdcMapGenerationTypes.REGION_ROLE_BOSS:
			default_ratio = 0.10
	var target_ratio: float = clampf(float(profile.get("target_area_ratio", default_ratio)), 0.01, 0.45)
	var derived_side: int = maxi(int(roundf(sqrt(float(map_size.x * map_size.y) * target_ratio))), 5)
	var min_size: Vector2i = _size_from_variant(
		profile.get("min_size_cells", {}),
		Vector2i(derived_side, derived_side)
	)
	var max_size: Vector2i = _size_from_variant(
		profile.get("max_size_cells", {}),
		min_size
	)
	max_size.x = maxi(max_size.x, min_size.x)
	max_size.y = maxi(max_size.y, min_size.y)
	return Vector2i(
		rng.randi_range(maxi(min_size.x, 3), maxi(max_size.x, 3)),
		rng.randi_range(maxi(min_size.y, 3), maxi(max_size.y, 3))
	)


func _resolve_layout_profile(
	config: WdcMapGenerationTypes.MapConfig,
	role: String
) -> Dictionary:
	var slot_value: Variant = config.region_layout.get(role, null)
	if not (slot_value is Dictionary):
		return {}
	var profile_id: String = str((slot_value as Dictionary).get("layout_profile_id", ""))
	var generation_value: Variant = config.get("region_generation")
	if not (generation_value is Dictionary):
		return {}
	var profiles_value: Variant = (generation_value as Dictionary).get("layout_profiles", [])
	if not (profiles_value is Array):
		return {}
	for profile_value: Variant in profiles_value as Array:
		if profile_value is Dictionary and str((profile_value as Dictionary).get("id", "")) == profile_id:
			return (profile_value as Dictionary).duplicate(true)
	return {}


func _size_from_variant(value: Variant, fallback: Vector2i) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Dictionary:
		return Vector2i(
			maxi(int((value as Dictionary).get("x", fallback.x)), 1),
			maxi(int((value as Dictionary).get("y", fallback.y)), 1)
		)
	if value is Array and (value as Array).size() == 2:
		return Vector2i(maxi(int((value as Array)[0]), 1), maxi(int((value as Array)[1]), 1))
	return fallback


func _append_unique_cell(
	output: Array[Vector2i],
	seen: Dictionary,
	cell: Vector2i
) -> void:
	var key: String = "%d:%d" % [cell.x, cell.y]
	if seen.has(key):
		return
	seen[key] = true
	output.append(cell)


func _shuffle_variant_array(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var temp: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temp


func _derive_seed(base_seed: int, profile_salt: int, attempt_index: int, role_index: int) -> int:
	var mixed: int = _mix_u31(base_seed)
	mixed = _mix_u31(mixed ^ profile_salt)
	mixed = _mix_u31(mixed ^ (attempt_index + 1) * 1103515245)
	mixed = _mix_u31(mixed ^ (role_index + 1) * 265443576)
	return maxi(mixed, 1)


func _mix_u31(value: int) -> int:
	var mixed: int = value & 0x7fffffff
	mixed = (mixed ^ (mixed >> 16)) * 1103515245
	mixed = mixed & 0x7fffffff
	mixed = mixed ^ (mixed >> 13)
	return mixed & 0x7fffffff


func _issue(code: String, path: String, role: String, message: String) -> Dictionary:
	return WdcMapGenerationTypes.make_generation_issue(code, path, role, message)
