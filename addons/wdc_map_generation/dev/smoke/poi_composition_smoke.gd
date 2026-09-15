extends SceneTree

const CATALOG = preload("../../config/poi_resource_catalog.gd")
const GENERATOR = preload("../../core/poi_composition_generator.gd")
const COMPILER = preload("../../core/poi_blueprint_compiler.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var bundle: Dictionary = CATALOG.load_bundle()
	_check(bundle.valid, "内容库编译：" + JSON.stringify(bundle.issues))
	if not bundle.valid:
		_finish()
		return
	var start: int = Time.get_ticks_msec()
	var attempts: int = 0
	for id: String in bundle.compositions:
		for seed_value: int in range(1, 33):
			var result: Dictionary = GENERATOR.generate(id, bundle, seed_value)
			_check(result.valid, "%s seed=%d：%s" % [id, seed_value, JSON.stringify(result.issues)])
			if result.valid:
				_check_corridor_enclosure(result.plan)
				attempts += int(result.plan.diagnostics.attempts)
				_check(result.plan.primary_anchor == {"x": 0, "y": 0}, "核心锚点应精确落位")
	print("POI_CORPUS ", JSON.stringify({"elapsed_ms": Time.get_ticks_msec() - start, "attempts": attempts, "compositions": bundle.compositions.size(), "seeds": 32}))
	var original: Dictionary = GENERATOR.generate("miners_settlement", bundle, 17)
	var repeated: Dictionary = GENERATOR.generate("miners_settlement", bundle, 17)
	_check(JSON.stringify(original, "", true) == JSON.stringify(repeated, "", true), "相同输入应完全复现")
	var changed: Dictionary = bundle.duplicate(true)
	changed.rooms.miner_house_a.slots.append({"id": "optional_decoration", "kind": "prop", "points": [{"x": 2, "y": 5}], "region": [], "entries": [{"id": "crates", "weight": 1}], "min_count": 0, "max_count": 1, "required": false, "rotation": 0, "footprint": [], "clearance": [], "guard_points": [], "exclusive_group": "", "group_members": [], "constraints": {}})
	var decorated: Dictionary = GENERATOR.generate("miners_settlement", changed, 17)
	_check(decorated.valid and JSON.stringify(original.plan.rooms) == JSON.stringify(decorated.plan.rooms), "纯装饰变化不能洗牌房间布局")
	_test_geometry()
	_test_connections(bundle)
	_test_search_and_rotation()
	_test_invalid()
	_finish()


func _room(id: String, width: int = 5, height: int = 5) -> Dictionary:
	var rows: Array = []
	for y: int in range(height):
		rows.append("#".repeat(width) if y == 0 or y == height - 1 else "#" + ".".repeat(width - 2) + "#")
	return {"schema_version": 1, "id": id, "cells": rows, "rotations": [0, 90, 180, 270], "anchors": {"primary": {"x": 2, "y": 2}}, "ports": [], "slots": [], "keep_clear": []}


func _composition(nodes: Array, connections: Array = []) -> Dictionary:
	return {"schema_version": 1, "id": "test", "nodes": nodes, "connections": connections, "primary": {"node": "a", "anchor": "primary"}}


func _node(id: String, room: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"id": id, "blueprints": [{"id": room, "weight": 1}], "min_count": 1, "max_count": 1}
	result.merge(extra, true)
	return result


func _port(id: String, points: Array, normal: Dictionary) -> Dictionary:
	return {"id": id, "cells": points, "normal": normal, "kind": "passage", "unused": "wall"}


func _test_geometry() -> void:
	var a: Dictionary = _room("a")
	var b: Dictionary = _room("b")
	a.ports.append(_port("exit", [{"x": 4, "y": 1}, {"x": 4, "y": 2}], {"x": 1, "y": 0}))
	b.ports.append(_port("entry", [{"x": 0, "y": 1}, {"x": 0, "y": 2}], {"x": -1, "y": 0}))
	var connection: Dictionary = {"id": "link", "from": {"node": "a", "port": "exit"}, "to": {"node": "b", "port": "entry"}, "style": "corridor", "max_length_cells": 24}
	var composition: Dictionary = _composition([_node("a", "a", {"rotation": 0}), _node("b", "b", {"rotation": 0, "position": {"x": 9, "y": 0}})], [connection])
	var bundle: Dictionary = COMPILER.compile_bundle({"a": a, "b": b}, {"test": composition})
	var result: Dictionary = GENERATOR.generate("test", bundle, 3)
	_check(result.valid, "偶数宽通道应该成功：" + JSON.stringify(result.issues))
	if result.valid:
		var corridor: Array = result.plan.connections[0].corridor_cells
		_check(corridor.size() == 8, "两格宽直通道应为 4×2 格，不能膨胀为三格宽")
		_check(result.plan.connections[0].width_cells == 2, "实际连接必须保留宽度")
		_check_corridor_enclosure(result.plan)
	composition.nodes[1].position = {"x": 15, "y": 0}
	bundle = COMPILER.compile_bundle({"a": a, "b": b}, {"test": composition})
	var obstacle: Array = [{"x": 7, "y": -1}, {"x": 7, "y": 0}]
	var detour: Dictionary = GENERATOR.generate("test", bundle, 3, {"blocked_cells": obstacle})
	_check(detour.valid and detour.plan.connections[0].corridor_cells.size() > 8, "通道应绕过障碍且不穿房墙")
	if detour.valid:
		_check_corridor_enclosure(detour.plan)
	var blocked_side: Dictionary = GENERATOR.generate("test", bundle, 3, {"blocked_cells": [{"x": 3, "y": -2}]})
	_check(not blocked_side.valid, "门外侧墙占地被阻挡时不能发布敞开走廊")
	var failed: Dictionary = GENERATOR.generate("test", bundle, 3, {"max_search_nodes": 1, "max_corridor_steps": 1, "blocked_cells": obstacle, "max_attempts": 1})
	_check(not failed.valid, "搜索额度耗尽应明确失败")
	connection.style = "direct"
	composition.nodes[1].position = {"x": 5, "y": 0}
	bundle = COMPILER.compile_bundle({"a": a, "b": b}, {"test": composition})
	result = GENERATOR.generate("test", bundle, 4)
	_check(result.valid and result.plan.connections[0].corridor_cells.is_empty(), "直连接缝应相邻逐格打开")
	connection.style = "corridor"
	bundle = COMPILER.compile_bundle({"a": a, "b": b}, {"test": composition})
	_check(not GENERATOR.generate("test", bundle, 4).valid, "走廊不能退化为房间直接拼接")
	var non_rect: Dictionary = _room("hole")
	non_rect.cells = ["#####", "#...#", "#.#.#", "#...#", "###  "]
	non_rect.anchors.primary = {"x": 1, "y": 1}
	non_rect.slots = [{"id": "crate", "kind": "prop", "points": [{"x": 3, "y": 1}], "entries": [{"id": "crates", "weight": 1}]}]
	bundle = COMPILER.compile_bundle({"hole": non_rect}, {"test": _composition([_node("a", "hole", {"rotation": 90})])})
	result = GENERATOR.generate("test", bundle, 1, {"origin": {"x": 20, "y": 30}})
	_check(result.valid, "非矩形旋转生成应成功：" + JSON.stringify(result.issues))
	if result.valid:
		_check(result.plan.footprint_cells.size() == 23, "未写入格不能进入 footprint")
		_check(result.plan.wall_cells.has({"x": 19, "y": 31}), "内部墙必须随旋转保留")
		_check(result.plan.content_requests[0].cell == {"x": 20, "y": 32}, "物件锚点必须旋转和平移")
		_check(result.plan.content_requests[0].rotation == 90, "物件朝向必须旋转")
		_check(result.plan.content_requests[0].group_instance_id == "a:0/crate:0", "请求应有稳定组来源")


func _check_corridor_enclosure(plan: Dictionary) -> void:
	for connection: Dictionary in plan.connections:
		if connection.style != "corridor":
			continue
		_check(connection.corridor_cells.size() >= int(connection.width_cells) * 2, "走廊至少保留两格长度")
		_check(not connection.get("corridor_wall_cells", []).is_empty(), "走廊应记录实际侧墙")
		for value: Dictionary in connection.corridor_cells:
			var cell := Vector2i(value.x, value.y)
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Dictionary = COMPILER.cell(cell + direction)
				_check(plan.floor_cells.has(neighbor) or plan.wall_cells.has(neighbor), "走廊存在无墙侧边")
		for wall: Dictionary in connection.corridor_wall_cells:
			_check(plan.wall_cells.has(wall) and plan.footprint_cells.has(wall) and not plan.floor_cells.has(wall), "走廊侧墙必须进入真实墙体和占地")


func _test_invalid() -> void:
	var room: Dictionary = _room("a")
	var composition: Dictionary = _composition([_node("a", "a")])
	for malformed: Variant in [null, [], "bad", true, {"x": []}, -1.5]:
		var bad: Dictionary = room.duplicate(true)
		bad.ports = [malformed]
		bad.slots = [{"id": "s", "kind": "prop", "points": [malformed], "entries": [malformed], "required": malformed, "constraints": {"min_distance_from_ports_cells": malformed}, "group_members": [malformed]}]
		_check(not COMPILER.compile_bundle({"a": bad}, {"test": composition}).valid, "错误槽位输入必须返回问题")
		var bad_composition: Dictionary = composition.duplicate(true)
		bad_composition.nodes[0].blueprints = [malformed]
		bad_composition.connections = [{"id": "bad", "probability": malformed, "max_length_cells": malformed, "from": malformed, "to": malformed}]
		_check(not COMPILER.compile_bundle({"a": room}, {"test": bad_composition}).valid, "错误组合输入必须返回问题")
	var bad_primary: Dictionary = composition.duplicate(true)
	bad_primary.nodes[0].min_count = 0
	bad_primary.nodes[0].max_count = 2
	_check(not COMPILER.compile_bundle({"a": room}, {"test": bad_primary}).valid, "核心来源必须是必需单实例")
	var unknown: Dictionary = room.duplicate(true)
	unknown.surprise = true
	_check(not COMPILER.compile_bundle({"a": unknown}, {}).valid, "未知生成字段应报错")
	for field: String in ["id", "display_name", "purpose"]:
		var bad_string: Dictionary = room.duplicate(true)
		bad_string[field] = ["invalid"]
		_check(not COMPILER.compile_bundle({"a": bad_string}, {}).valid, "字符串字段不能静默转换：" + field)
	var unavailable: Dictionary = room.duplicate(true)
	unavailable.slots = [{"id": "unsupported", "kind": "monster", "points": [{"x": 1, "y": 1}], "entries": [{"id": "stone_golem", "weight": 1}]}]
	_check(not COMPILER.compile_bundle({"a": unavailable}, {}).valid, "直接怪物类型没有生成消费者时必须拒绝")
	var subset: Dictionary = CATALOG.load_bundle({}, ["room_showcase"])
	_check(subset.valid and subset.rooms.size() == 1 and subset.compositions.size() == 1, "运行时内容快照只含引用闭包")
	_check(subset.dependencies.size() == 3, "依赖闭包包含组合、房间与内容能力")
	var repaired: Dictionary = CATALOG.load_bundle({"rooms": {"miner_house_a": room}}, ["room_showcase"])
	_check(not repaired.valid, "编辑覆盖 id 不匹配应报错")
	var missing_capabilities: Dictionary = subset.duplicate(true)
	missing_capabilities.capabilities = {}
	_check(not CATALOG.select_bundle(missing_capabilities, ["room_showcase"]).valid, "内容槽不能在缺少正式能力快照时激活")
	var repeated_capability: Dictionary = subset.duplicate(true)
	repeated_capability.capabilities.entries.append(repeated_capability.capabilities.entries[0])
	_check(not CATALOG.select_bundle(repeated_capability, ["room_showcase"]).valid, "能力重复键必须拒绝")


func _test_connections(bundle: Dictionary) -> void:
	var result: Dictionary = GENERATOR.generate("refining_workshop_u", bundle, 3)
	_check(result.valid, "U 型工作间应生成")
	if result.valid:
		var links: Dictionary = {}
		for link: Dictionary in result.plan.connections:
			links[link.rule_id] = link
		_check(links.input.to.room_instance_id == "work:0", "first 应选择稳定首实例")
		_check(links.storage.from.room_instance_id == "work:1", "last 应选择稳定尾实例")
		_check(links.processing.from.room_instance_id == "work:0" and links.processing.to.room_instance_id == "work:1", "串联应按稳定序号展开")
		var rooms: Dictionary = {}
		for item: Dictionary in result.plan.rooms:
			rooms[item.id] = item
		_check(posmod(int(rooms["work:0"].transform.rotation) - int(rooms["work:1"].transform.rotation), 360) == 90, "U 型工作间应连续两次转向")
	for id: String in ["miners_settlement", "miners_settlement_alley"]:
		result = GENERATOR.generate(id, bundle, 9)
		var consumed: Dictionary = {}
		var home_links: int = 0
		for link: Dictionary in result.plan.connections:
			for endpoint: Dictionary in [link.from, link.to]:
				var key: String = endpoint.room_instance_id + "/" + endpoint.port_id
				_check(not consumed.has(key), "实际接口只能消费一次：" + key)
				consumed[key] = true
			if link.rule_id == "homes":
				home_links += 1
		_check(home_links >= 3 and home_links <= 4, "住宅组最少三栋且逐个接入")
		for item: Dictionary in result.plan.rooms:
			for port: Dictionary in item.ports:
				for point: Dictionary in port.cells:
					_check(result.plan.floor_cells.has(point) if port.consumed or port.unused == "open" else result.plan.wall_cells.has(point), "未使用接口必须落实声明的开闭状态")
	var invalid: Dictionary = bundle.compositions.miners_settlement.duplicate(true)
	invalid.nodes[1].min_count = 5
	invalid.nodes[1].max_count = 5
	var bad: Dictionary = COMPILER.compile_bundle(bundle.rooms, {"miners_settlement": invalid})
	_check(not bad.valid and _has_issue(bad, "poi_port_capacity"), "中心容量不足应直接定位连接规则")
	invalid = bundle.compositions.refining_workshop.duplicate(true)
	invalid.connections[1].from.instance = "first"
	_check(not COMPILER.compile_bundle(bundle.rooms, {"refining_workshop": invalid}).valid, "串联不能静默忽略 first/last")
	invalid = bundle.compositions.refining_workshop.duplicate(true)
	invalid.connections[0].width_cells = 1
	_check(not COMPILER.compile_bundle(bundle.rooms, {"refining_workshop": invalid}).valid, "显式宽度应与端口完全一致")
	for angle: int in [0, 90, 180, 270]:
		var rotated: Dictionary = bundle.duplicate(true)
		rotated.compositions.boss_control_vault.nodes[0].rotation = angle
		result = GENERATOR.generate("boss_control_vault", rotated, 9)
		_check(result.valid, "奖励房旋转应成功")
		if result.valid:
			_check(result.plan.wall_cells.has(result.plan.anchors.reward_gate_0), "奖励门旋转后必须保留实体墙")
			for reward_id: String in ["supply", "mineral", "armory", "reliquary"]:
				_check(result.plan.floor_cells.has(result.plan.anchors["reward_device_" + reward_id]), "奖励具名锚点应保持地板语义")


func _test_search_and_rotation() -> void:
	var a: Dictionary = _room("a", 7, 5)
	var allowed: Array = []
	for y: int in range(-2, 3):
		for x: int in range(-2, 5):
			allowed.append({"x": x, "y": y})
	var bundle: Dictionary = COMPILER.compile_bundle({"a": a}, {"test": _composition([_node("a", "a")])})
	for seed_value: int in range(1, 9):
		var result: Dictionary = GENERATOR.generate("test", bundle, seed_value, {"max_attempts": 1, "allowed_cells": allowed})
		_check(result.valid and result.plan.rooms[0].transform.rotation == 0, "同次尝试必须枚举固定根节点旋转")
	a = _room("a")
	var b: Dictionary = _room("b")
	a.ports.append(_port("exit", [{"x": 4, "y": 2}], {"x": 1, "y": 0}))
	b.ports.append(_port("entry", [{"x": 0, "y": 2}], {"x": -1, "y": 0}))
	var connection: Dictionary = {"id": "link", "from": {"node": "a", "port": "exit"}, "to": {"node": "b", "port": "entry"}, "style": "direct", "directions": [{"x": -1, "y": 0}], "width_cells": 1}
	var composition: Dictionary = _composition([_node("a", "a", {"rotation": 0}), _node("b", "b", {"rotation": 0})], [connection])
	bundle = COMPILER.compile_bundle({"a": a, "b": b}, {"test": composition})
	var failed: Dictionary = GENERATOR.generate("test", bundle, 1, {"max_attempts": 1})
	_check(not failed.valid and str(failed.issues[0].path).contains("link"), "相对方向约束应执行并定位连接")
	connection.directions = [{"x": 1, "y": 0}]
	bundle = COMPILER.compile_bundle({"a": a, "b": b}, {"test": composition})
	failed = GENERATOR.generate("test", bundle, 1, {"max_attempts": 1, "max_search_nodes": 1})
	_check(not failed.valid and failed.diagnostics.exhausted_budget == "search_nodes", "候选额度耗尽应报告具体预算")
	var clear_failed: Dictionary = GENERATOR.generate("room_showcase", CATALOG.load_bundle(), 1, {"max_radius_cells": 1, "max_attempts": 1})
	_check(not clear_failed.valid, "占地边界必须阻止不合法房间")


func _has_issue(result: Dictionary, code: String) -> bool:
	for item: Dictionary in result.issues:
		if item.code == code:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	print("POI_COMPOSITION_SMOKE ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
