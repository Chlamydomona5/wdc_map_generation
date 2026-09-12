class_name WdcPoiPopulationContract
extends RefCounted

const KEYS: Dictionary = {
	"poi_initial_live_cap": ["poi_initial", "live_cap"],
	"poi_initial_per_poi_cap": ["poi_initial", "per_poi_cap"],
	"nest_site_cap": ["nests", "site_cap"],
	"ordinary_initial_target": ["ordinary", "initial_target"],
	"ordinary_live_cap": ["ordinary", "live_cap"],
	"auto_initial_target_divisor": ["ordinary", "auto_initial_target_divisor"],
	"auto_live_cap_area_divisor_cells": ["ordinary", "auto_live_cap_area_divisor_cells"],
	"total_live_monster_safety_cap": ["safety", "total_live_monster_safety_cap"],
}


static func resolve_limits(raw_budgets: Dictionary, defaults: Dictionary) -> Dictionary:
	var limits: Dictionary = defaults.duplicate(true)
	for key: String in KEYS:
		var path: Array = KEYS[key]
		limits[key] = maxf(float(raw_budgets.get(path[0], {}).get(path[1], raw_budgets.get(key, limits.get(key, 0)))), 0.0)
	return limits


static func ordinary_initial_count(map_data: Variant, limits: Dictionary) -> int:
	if str(map_data.layout_mode) == "poi_only_v1":
		return 0
	var area: int = map_data.width * map_data.height
	var density: float = clampf(float(limits.get("monster_density_multiplier", 1.0)), 0.5, 2.0)
	var base_target: int = int(limits.get("ordinary_initial_target", 0))
	if base_target <= 0:
		base_target = int(floor(float(area) / maxf(float(limits.get("auto_initial_target_divisor", 1)), 1.0)))
	var base_cap: int = int(limits.get("ordinary_live_cap", 0))
	if base_cap <= 0:
		base_cap = int(floor(float(area) / maxf(float(limits.get("auto_live_cap_area_divisor_cells", 1)), 1.0)))
	return mini(maxi(int(round(base_target * density)), 1), maxi(int(round(base_cap * density)), 1))


static func empty_usage() -> Dictionary:
	return {"poi_initial": 0, "nests": 0, "by_poi": {}}


## 规划与实体化后的检查使用相同单位：孤立怪一只，营地为实际守卫数，巢穴为实体数。
static func reserve(usage: Dictionary, request: Dictionary, map_data: Variant, limits: Dictionary) -> bool:
	var kind: String = str(request.get("kind", ""))
	var source: String = str(request.get("source_poi_id", request.get("poi_instance_id", "")))
	var monsters: int = 1 if kind == "monster_pack" else (request.get("guard_cells", []) as Array).size() if kind == "camp" else 0
	var nests: int = 1 if kind == "nest" else 0
	var total: int = int(usage.poi_initial) + monsters
	var per_poi: int = int(usage.by_poi.get(source, 0)) + monsters
	if not limits.is_empty():
		if limits.has("poi_initial_live_cap") and total > int(limits.poi_initial_live_cap):
			return false
		if int(limits.get("poi_initial_per_poi_cap", 0)) > 0 and per_poi > int(limits.poi_initial_per_poi_cap):
			return false
		if limits.has("nest_site_cap") and int(usage.nests) + nests > int(limits.nest_site_cap):
			return false
		var safety: int = int(limits.get("total_live_monster_safety_cap", 0))
		if safety > 0 and total + ordinary_initial_count(map_data, limits) > safety:
			return false
	usage.poi_initial = total
	usage.nests = int(usage.nests) + nests
	usage.by_poi[source] = per_poi
	return true


static func collect_usage(map_data: Variant, include_plans: bool = false, camp_definitions: Array = []) -> Dictionary:
	var usage: Dictionary = empty_usage()
	var seen: Dictionary = {}
	for site: Dictionary in map_data.monster_sites:
		var kind: String = "nest" if str(site.get("site_kind", "")) == "nest" else "monster_pack" if str(site.get("site_source", "")) == "poi_room" else ""
		var source: String = str(site.get("source_poi_id", site.get("source_poi_instance_id", "")))
		reserve(usage, {"kind": kind, "source_poi_id": source}, map_data, {})
		seen[str(site.get("source_room_content_plan_id", ""))] = true
	for camp: Dictionary in map_data.camp_encounters:
		var source: String = str(camp.get("source_poi_id", camp.get("source_poi_instance_id", "")))
		reserve(usage, {"kind": "camp", "source_poi_id": source, "guard_cells": camp.get("guard_sites", [])}, map_data, {})
		seen[str(camp.get("source_room_content_plan_id", ""))] = true
	if include_plans:
		for poi: Dictionary in map_data.poi_instances:
			for plan: Dictionary in poi.get("content_plans", []) + poi.get("room_content_plans", []):
				if seen.has(str(plan.get("plan_id", ""))):
					continue
				var request: Dictionary = plan.duplicate(true)
				request["source_poi_id"] = str(poi.get("instance_id", ""))
				request["kind"] = str(plan.get("kind", plan.get("content_kind", "")))
				if request.kind == "camp" and not request.has("guard_cells"):
					var count: int = 1
					for definition: Dictionary in camp_definitions:
						if str(definition.get("id", "")) == str(plan.get("camp_id", "")):
							count = int(definition.get("guard_count_max", definition.get("guard_count_min", 1)))
					request["guard_cells"] = range(count)
				reserve(usage, request, map_data, {})
	return usage


## 工具和 authority 均在发布前执行，不以实体化时裁剪替代已承诺槽位。
static func validate(map_data: Variant, limits: Dictionary) -> Array[Dictionary]:
	if limits.is_empty():
		return []
	var authored: Dictionary = {}
	for poi: Dictionary in map_data.poi_instances:
		if str(poi.get("layout_kind", "")) == "authored_rooms":
			authored[str(poi.instance_id)] = true
	if authored.is_empty():
		return []
	var counts: Dictionary = {}
	var total: int = 0
	var nests: int = 0
	var authored_nest: bool = false
	for site: Dictionary in map_data.monster_sites:
		var source: String = str(site.get("source_poi_id", site.get("source_poi_instance_id", "")))
		if str(site.get("site_kind", "")) == "nest":
			nests += 1
			authored_nest = authored_nest or authored.has(source)
		elif str(site.get("site_source", "")) == "poi_room":
			total += 1
			counts[source] = int(counts.get(source, 0)) + 1
	for camp: Dictionary in map_data.camp_encounters:
		var source: String = str(camp.get("source_poi_id", camp.get("source_poi_instance_id", "")))
		var size: int = (camp.get("guard_sites", []) as Array).size()
		total += size
		counts[source] = int(counts.get(source, 0)) + size
	if total > int(limits.get("poi_initial_live_cap", 0)):
		return [_issue("poi_initial.live_cap", "POI 怪物和守卫共 %d，超过实际初始人口上限 %d" % [total, int(limits.get("poi_initial_live_cap", 0))])]
	var per_poi_cap: int = int(limits.get("poi_initial_per_poi_cap", 0))
	for source: String in authored:
		if per_poi_cap > 0 and int(counts.get(source, 0)) > per_poi_cap:
			return [_issue("poi_initial.per_poi_cap", "%s 的已承诺怪物数量超过单 POI 上限 %d" % [source, per_poi_cap])]
	if authored_nest and nests > int(limits.get("nest_site_cap", 0)):
		return [_issue("nests.site_cap", "已承诺巢穴超过实体数量上限")]
	var ordinary: int = ordinary_initial_count(map_data, limits)
	var safety: int = int(limits.get("total_live_monster_safety_cap", 0))
	if safety > 0 and total + ordinary > safety:
		return [_issue("safety.total_live_monster_cap", "普通开局人口与已承诺 POI 内容超过总安全上限")]
	return []


static func _issue(path: String, message: String) -> Dictionary:
	return {"code": "authored_population_exceeds_cap", "path": "monster_generation.population_budgets." + path,
		"role": "", "message": message}
