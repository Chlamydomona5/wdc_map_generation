class_name WdcAuthoredPoiContentAllocator
extends RefCounted

const POPULATION = preload("poi_population_contract.gd")

const SECTIONS: Dictionary = {"prop": "furnishings", "torch": "torches", "mineral": "minerals",
	"monster_pack": "monster_sites", "nest": "nests", "camp": "camps", "trap": "traps"}
const ENTRY_KEYS: Dictionary = {"prop": "content_id", "torch": "content_id", "mineral": "cluster_type_id",
	"monster_pack": "spawn_template_id", "nest": "nest_template_id", "camp": "camp_id", "trap": "trap_kind"}


## 布局已确定，按来源稳定排序分配区域额度；任何失败都由外层整图事务丢弃。
static func allocate(map_data: Variant, resolver: Variant, seed_value: int, population_limits: Dictionary = {}) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	for poi_index: int in range(map_data.poi_instances.size()):
		var poi: Dictionary = map_data.poi_instances[poi_index]
		if str(poi.get("layout_kind", "")) != "authored_rooms":
			continue
		poi["content_plans"] = []
		for source: Dictionary in poi.get("content_requests", []):
			var request: Dictionary = source.duplicate(true)
			request["poi_index"] = poi_index
			request["source_poi_id"] = str(poi.instance_id)
			request["region_role"] = str(poi.region_role)
			request["region_index"] = int(poi.region_index)
			request["plan_id"] = "%s:%s" % [poi.instance_id, request.get("request_id", "%s:%s:%d" % [request.get("room_instance_id", ""), request.get("slot_id", ""), requests.size()])]
			requests.append(request)
	requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.get("required", false)) != bool(b.get("required", false)):
			return bool(a.get("required", false))
		return str(a.plan_id) < str(b.plan_id))
	var groups: Dictionary = {}
	for request: Dictionary in requests:
		var group_id: String = "%s:%s" % [request.source_poi_id, request.get("group_instance_id", request.plan_id)]
		if not groups.has(group_id):
			groups[group_id] = []
		(groups[group_id] as Array).append(request)
	var mandatory: Array = []
	var optional: Array = []
	# 必需组的可选成员延后处理，不能抢占另一必需组的额度。
	for members: Array in groups.values():
		if bool(members[0].get("group_required", members[0].get("required", false))):
			var required_members: Array = []
			for member: Dictionary in members:
				if bool(member.get("member_required", true)):
					required_members.append(member)
				else:
					var extra: Dictionary = member.duplicate(true)
					extra["group_required"] = false
					optional.append([extra])
			mandatory.append(required_members)
		else:
			optional.append(members)
	var population: Dictionary = POPULATION.collect_usage(map_data)
	var minimum_costs: Dictionary = {}
	var future_costs: Dictionary = {}
	var future_counts: Dictionary = {}
	var required_population: Dictionary = population.duplicate(true)
	for members: Array in mandatory:
		for member: Dictionary in members:
			var role: String = str(member.region_role)
			var section: String = str(SECTIONS.get(str(member.kind), ""))
			var minimum_cost: int = _minimum_request_cost(member, resolver)
			if minimum_cost < 0:
				return [_issue(member, "required_slot_budget_unavailable", "必需内容缺少区域允许候选或明确成本")]
			if not POPULATION.reserve(required_population, member, map_data, population_limits):
				return [_issue(member, "required_slot_population_unavailable", "必需内容的总人口预留超过实际额度")]
			minimum_costs[member.plan_id] = minimum_cost
			var budget: String = "mineral_value_budget" if member.kind == "mineral" else "reward_value_budget"
			var role_costs: Dictionary = future_costs.get(role, {})
			role_costs[budget] = int(role_costs.get(budget, 0)) + minimum_cost
			future_costs[role] = role_costs
			var role_counts: Dictionary = future_counts.get(role, {})
			role_counts[section] = int(role_counts.get(section, 0)) + 1
			if member.kind in ["monster_pack", "nest", "camp"]:
				role_counts["room_contents"] = int(role_counts.get("room_contents", 0)) + 1
			future_counts[role] = role_counts
	for members: Array in mandatory + optional:
		var role: String = str(members[0].region_role)
		var group_required: bool = bool(members[0].get("group_required", members[0].get("required", false)))
		var held_costs: Dictionary = future_costs.get(role, {}).duplicate(true)
		var held_counts: Dictionary = future_counts.get(role, {}).duplicate(true)
		if group_required:
			for member: Dictionary in members:
				var section: String = str(SECTIONS[member.kind])
				var budget: String = "mineral_value_budget" if member.kind == "mineral" else "reward_value_budget"
				future_costs[role][budget] -= int(minimum_costs[member.plan_id])
				future_counts[role][section] -= 1
				if member.kind in ["monster_pack", "nest", "camp"]:
					future_counts[role]["room_contents"] -= 1
		var committed: bool = false
		var population_failed: bool = false
		for attempt: int in range(8):
			var plans: Array[Dictionary] = []
			var counts: Dictionary = {}
			var costs: Dictionary = {}
			var valid: bool = true
			var candidate_population: Dictionary = population.duplicate(true)
			var remaining_costs: Dictionary = held_costs.duplicate(true)
			var remaining_counts: Dictionary = held_counts.duplicate(true)
			for request: Dictionary in members:
				if group_required:
					var section: String = str(SECTIONS[request.kind])
					var budget: String = "mineral_value_budget" if request.kind == "mineral" else "reward_value_budget"
					remaining_costs[budget] -= int(minimum_costs[request.plan_id])
					remaining_counts[section] -= 1
					if request.kind in ["monster_pack", "nest", "camp"]:
						remaining_counts["room_contents"] -= 1
				var selected: Dictionary = _select_request(request, resolver, seed_value, attempt, _sum(counts, remaining_counts), _sum(costs, remaining_costs))
				if not selected.is_empty() and not POPULATION.reserve(candidate_population, selected, map_data, population_limits):
					population_failed = true
					selected = {}
				if selected.is_empty():
					if bool(request.get("member_required", true)):
						valid = false
						break
					continue
				plans.append(selected)
				var section: String = SECTIONS[str(selected.kind)]
				counts[section] = int(counts.get(section, 0)) + 1
				if str(selected.kind) in ["monster_pack", "nest", "camp"]:
					counts["room_contents"] = int(counts.get("room_contents", 0)) + 1
				costs[selected.budget_name] = int(costs.get(selected.budget_name, 0)) + int(selected.budget_cost)
			if valid and resolver.reserve_authored_content(role, counts, costs):
				population = candidate_population
				for plan: Dictionary in plans:
					var poi: Dictionary = map_data.poi_instances[int(plan.poi_index)]
					(poi.content_plans as Array).append(plan)
				committed = true
				break
		if not committed and group_required:
			if population_failed:
				return [_issue(members[0], "required_slot_population_unavailable", "必需槽位组超过怪物、巢穴、单 POI 或总安全人口额度")]
			return [_issue(members[0], "required_slot_budget_unavailable", "必需槽位组没有符合区域候选、数量及价值额度的完整方案")]
	return []


static func _select_request(request: Dictionary, resolver: Variant, seed_value: int, attempt: int, pending_counts: Dictionary, pending_costs: Dictionary) -> Dictionary:
		var kind: String = str(request.get("kind", ""))
		var role: String = str(request.region_role)
		var section: String = str(SECTIONS.get(kind, ""))
		if section.is_empty():
			return {}
		var sections: Array[String] = [section]
		if kind in ["monster_pack", "nest", "camp"]:
			sections.append("room_contents")
		for section_name: String in sections:
			if resolver.get_reserved_count(role, section_name) + int(pending_counts.get(section_name, 0)) >= int(resolver.get_section_for_role(role, section_name).get("target_count", 0)):
				return {}
		var eligible: Array[Dictionary] = []
		var declared: Array = request.get("entries", [{"id": request.get("content_id", ""), "weight": 1}])
		var allowed: Array = resolver.get_weighted_entries(role, section)
		var room_cost: int = 0
		if kind in ["monster_pack", "nest", "camp"]:
			room_cost = -1
			for room_entry: Dictionary in resolver.get_weighted_entries(role, "room_contents"):
				if str(room_entry.get("content_kind", "")) == kind:
					room_cost = int(room_entry.get("value_cost", -1))
		for entry: Dictionary in declared:
			if float(entry.get("weight", 0)) <= 0 or room_cost < 0:
				continue
			for permitted: Dictionary in allowed:
				if not permitted.has("value_cost"):
					continue
				if str(entry.get("id", "")) != str(permitted.get(ENTRY_KEYS[kind], "")):
					continue
				var candidate: Dictionary = entry.duplicate(true)
				candidate["value_cost"] = int(permitted.get("value_cost", 0)) + room_cost
				var budget: String = "mineral_value_budget" if kind == "mineral" else "reward_value_budget"
				if resolver.can_spend_value_budget(role, budget, int(candidate.value_cost) + int(pending_costs.get(budget, 0))):
					eligible.append(candidate)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = maxi(abs(("%d:content:v1:%s:%d" % [seed_value, request.plan_id, attempt]).hash()), 1)
		var selected: Dictionary = resolver.pick_weighted_from_entries(eligible, rng)
		var budget_name: String = "mineral_value_budget" if kind == "mineral" else "reward_value_budget"
		if selected.is_empty():
			return {}
		var plan: Dictionary = request.duplicate(true)
		plan["content_id"] = str(selected.id)
		plan["budget_cost"] = int(selected.value_cost)
		plan["budget_name"] = budget_name
		plan["room_content_value_cost"] = room_cost
		return plan


static func _sum(a: Dictionary, b: Dictionary) -> Dictionary:
	var result: Dictionary = a.duplicate(true)
	for key: Variant in b:
		result[key] = int(result.get(key, 0)) + int(b[key])
	return result


static func _minimum_request_cost(request: Dictionary, resolver: Variant) -> int:
	var kind: String = str(request.kind)
	var section: String = str(SECTIONS.get(kind, ""))
	if section.is_empty():
		return -1
	var room_cost: int = 0
	if kind in ["monster_pack", "nest", "camp"]:
		room_cost = -1
		for entry: Dictionary in resolver.get_weighted_entries(str(request.region_role), "room_contents"):
			if str(entry.get("content_kind", "")) == kind and entry.has("value_cost"):
				room_cost = int(entry.value_cost)
	if room_cost < 0:
		return -1
	var minimum: int = -1
	for entry: Dictionary in request.get("entries", []):
		if float(entry.get("weight", 0)) <= 0:
			continue
		for permitted: Dictionary in resolver.get_weighted_entries(str(request.region_role), section):
			if entry.id == permitted.get(ENTRY_KEYS[kind]) and permitted.has("value_cost"):
				var cost: int = int(permitted.value_cost) + room_cost
				minimum = cost if minimum < 0 else mini(minimum, cost)
	return minimum


static func _issue(request: Dictionary, code: String, message: String) -> Dictionary:
	return {"code": code, "path": "poi_instances.%s.rooms.%s.slots.%s" % [request.get("source_poi_id", ""),
		request.get("room_instance_id", ""), request.get("slot_id", "")], "role": request.get("region_role", ""), "message": message}
