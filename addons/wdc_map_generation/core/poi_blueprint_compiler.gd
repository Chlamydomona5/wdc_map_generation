class_name WdcPoiBlueprintCompiler
extends RefCounted

## 房间与组合的纯校验入口；源文档与编译产物不依赖 Godot 场景。
const KINDS: Array[String] = ["torch", "prop", "monster_pack", "nest", "camp", "mineral", "trap"]
const ROTATIONS: Array[int] = [0, 90, 180, 270]


static func compile_bundle(rooms: Dictionary, compositions: Dictionary) -> Dictionary:
	var issues: Array[Dictionary] = []
	var normalized_rooms: Dictionary = {}
	var normalized_compositions: Dictionary = {}
	var room_ids: Array = rooms.keys()
	room_ids.sort()
	for id_value: Variant in room_ids:
		var id: String = str(id_value)
		if not rooms[id_value] is Dictionary:
			issue(issues, "rooms.%s" % id, "图纸必须是对象")
			continue
		var room: Dictionary = (rooms[id_value] as Dictionary).duplicate(true)
		_validate_room(room, id, issues)
		normalized_rooms[id] = room
	var composition_ids: Array = compositions.keys()
	composition_ids.sort()
	for id_value: Variant in composition_ids:
		var id: String = str(id_value)
		if not compositions[id_value] is Dictionary:
			issue(issues, "compositions.%s" % id, "组合必须是对象")
			continue
		var composition: Dictionary = (compositions[id_value] as Dictionary).duplicate(true)
		_validate_composition(composition, id, normalized_rooms, issues)
		normalized_compositions[id] = composition
	return {
		"valid": issues.is_empty(), "rooms": normalized_rooms,
		"compositions": normalized_compositions, "issues": issues, "dependencies": [],
		"content_hash": JSON.stringify([normalized_rooms, normalized_compositions], "", true).sha256_text(),
	}


static func _validate_room(room: Dictionary, id: String, issues: Array[Dictionary]) -> void:
	var path: String = "rooms.%s" % id
	keys(room, ["schema_version", "id", "display_name", "purpose", "cells", "rotations", "anchors", "ports", "slots", "keep_clear"], path, issues)
	_header(room, id, path, issues)
	room["purpose"] = _string(room.get("purpose", ""), path + ".purpose", issues)
	var rows: Variant = room.get("cells")
	if not rows is Array or (rows as Array).is_empty() or (rows as Array).size() > 128:
		issue(issues, path + ".cells", "图纸需要 1–128 行格子")
		room.merge({"cells": [], "rotations": [0], "anchors": {}, "ports": [], "slots": [], "keep_clear": []}, true)
		return
	var written: Dictionary = {}
	var floors: Dictionary = {}
	for y: int in range(rows.size()):
		if not rows[y] is String or str(rows[y]).length() > 128:
			issue(issues, path + ".cells[%d]" % y, "每行必须是最多 128 格的字符串")
			continue
		var line: String = rows[y]
		for x: int in range(line.length()):
			var character: String = line.substr(x, 1)
			if character not in ["#", ".", " "]:
				issue(issues, path + ".cells[%d]" % y, "只允许 # 墙、. 地板与空格")
			if character != " ":
				written[cell_key(Vector2i(x, y))] = character
			if character == ".":
				floors[cell_key(Vector2i(x, y))] = true
	if floors.is_empty():
		issue(issues, path + ".cells", "图纸至少需要一格地板")
	room["rotations"] = _rotations(room.get("rotations", [0]), path + ".rotations", issues)
	var anchors: Variant = room.get("anchors", {})
	if not anchors is Dictionary:
		issue(issues, path + ".anchors", "锚点必须是具名对象")
		anchors = {}
	for anchor_id: Variant in anchors:
		var anchor_path: String = path + ".anchors." + str(anchor_id)
		if not _valid_id(str(anchor_id)) or not valid_cell(anchors[anchor_id]):
			issue(issues, anchor_path, "锚点需要合法 id 和整数坐标")
		elif not floors.has(cell_key(vec(anchors[anchor_id]))):
			# 特殊奖励门锚点可以落在明确的墙格上。
			if not str(anchor_id).begins_with("reward_gate") or not written.has(cell_key(vec(anchors[anchor_id]))):
				issue(issues, anchor_path, "普通锚点必须位于地板，奖励门锚点必须位于显式格子")
	room["anchors"] = anchors
	var ports: Array = _array(room.get("ports", []), path + ".ports", issues)
	var port_ids: Dictionary = {}
	var port_cells: Dictionary = {}
	for index: int in range(ports.size()):
		var port_path: String = path + ".ports[%d]" % index
		if not ports[index] is Dictionary:
			issue(issues, port_path, "连接口必须是对象")
			continue
		var port: Dictionary = ports[index]
		keys(port, ["id", "cells", "normal", "kind", "group", "unused"], port_path, issues)
		_unique_id(port, port_ids, port_path, issues)
		var normal: Vector2i = vec(port.get("normal"))
		if not valid_cell(port.get("normal")) or absi(normal.x) + absi(normal.y) != 1:
			issue(issues, port_path + ".normal", "法向必须是一个正交单位方向")
		var cells: Array = _cells(port.get("cells"), port_path + ".cells", issues)
		if cells.is_empty() or cells.size() > 8:
			issue(issues, port_path + ".cells", "连接口宽度必须为 1–8 格")
		var values: Array[int] = []
		var normal_axis: int = 0
		for cell_index: int in range(cells.size()):
			var point: Vector2i = vec(cells[cell_index])
			var key: String = cell_key(point)
			if port_cells.has(key):
				issue(issues, port_path, "不同连接口不能共用开口格")
			port_cells[key] = true
			if str(port.get("kind", "passage")) == "reward_gate":
				if written.get(key) != "#" or not floors.has(cell_key(point - normal)) or not floors.has(cell_key(point + normal)):
					issue(issues, port_path, "奖励门必须是两侧都有显式地板的墙格")
			elif not written.has(key) or not floors.has(cell_key(point - normal)) or written.has(cell_key(point + normal)):
				issue(issues, port_path, "开口必须位于图纸外边界，内侧是地板，外侧未写入")
			var axis: int = point.x if normal.x != 0 else point.y
			if cell_index == 0:
				normal_axis = axis
			elif axis != normal_axis:
				issue(issues, port_path, "开口格必须排列在垂直于法向的直线上")
			values.append(point.y if normal.x != 0 else point.x)
		values.sort()
		for value_index: int in range(1, values.size()):
			if values[value_index] != values[value_index - 1] + 1:
				issue(issues, port_path, "开口格必须连续")
		port["cells"] = cells
		port["kind"] = _string(port.get("kind", "passage"), port_path + ".kind", issues)
		port["group"] = _string(port.get("group", ""), port_path + ".group", issues)
		port["unused"] = _string(port.get("unused", "wall"), port_path + ".unused", issues)
		if port.unused not in ["wall", "open"] or port.kind.is_empty():
			issue(issues, port_path, "连接口类型不能为空，未使用处理必须为 wall/open")
		if port.kind == "reward_gate" and port.unused != "wall":
			issue(issues, port_path + ".unused", "奖励门初始必须封闭")
	room["ports"] = ports.filter(func(value: Variant) -> bool: return value is Dictionary)
	var clear_cells: Array = _cells(room.get("keep_clear", []), path + ".keep_clear", issues)
	for point: Variant in clear_cells:
		if not floors.has(cell_key(vec(point))):
			issue(issues, path + ".keep_clear", "保留通路必须位于显式地板")
	room["keep_clear"] = clear_cells
	var slots: Array = _array(room.get("slots", []), path + ".slots", issues)
	var slot_ids: Dictionary = {}
	for index: int in range(slots.size()):
		var slot_path: String = path + ".slots[%d]" % index
		if not slots[index] is Dictionary:
			issue(issues, slot_path, "内容槽必须是对象")
			continue
		var slot: Dictionary = slots[index]
		keys(slot, ["id", "kind", "points", "region", "entries", "min_count", "max_count", "required", "rotation", "group_members", "footprint", "clearance", "exclusive_group", "constraints", "guard_points"], slot_path, issues)
		_unique_id(slot, slot_ids, slot_path, issues)
		slot["kind"] = _string(slot.get("kind", ""), slot_path + ".kind", issues)
		if str(slot.get("kind", "")) not in KINDS:
			issue(issues, slot_path + ".kind", "未知内容种类")
		var points: Array = _cells(slot.get("points", []), slot_path + ".points", issues)
		var region: Array = _cells(slot.get("region", []), slot_path + ".region", issues)
		if points.is_empty() and region.is_empty():
			issue(issues, slot_path, "内容槽必须提供锚点或候选区域")
		for point: Variant in points + region:
			if not written.has(cell_key(vec(point))) or (slot.get("kind") not in ["mineral", "trap"] and not floors.has(cell_key(vec(point)))):
				issue(issues, slot_path, "内容候选点与其地形要求不符")
		slot["points"] = points
		slot["region"] = region
		slot["entries"] = _weighted(slot.get("entries", []), slot_path + ".entries", issues, false)
		_counts(slot, slot_path, issues, 64, 1)
		slot["required"] = _boolean(slot.get("required", true), slot_path + ".required", issues)
		if slot.required and int(slot.min_count) == 0:
			issue(issues, slot_path + ".min_count", "必需槽的最少数量必须大于零")
		slot["rotation"] = _rotation(slot.get("rotation", 0), slot_path + ".rotation", issues)
		slot["footprint"] = _cells(slot.get("footprint", [{"x": 0, "y": 0}]), slot_path + ".footprint", issues)
		slot["clearance"] = _cells(slot.get("clearance", []), slot_path + ".clearance", issues)
		slot["guard_points"] = _cells(slot.get("guard_points", []), slot_path + ".guard_points", issues)
		if slot.kind != "camp" and not slot.guard_points.is_empty():
			issue(issues, slot_path + ".guard_points", "只有营地槽能够声明守卫点")
		slot["exclusive_group"] = _string(slot.get("exclusive_group", ""), slot_path + ".exclusive_group", issues)
		var constraints: Variant = slot.get("constraints", {})
		if not constraints is Dictionary:
			issue(issues, slot_path + ".constraints", "槽位条件必须是对象")
			constraints = {}
		keys(constraints, ["near_wall", "min_distance_from_ports_cells", "face_port"], slot_path + ".constraints", issues)
		var distance: Variant = constraints.get("min_distance_from_ports_cells", 0)
		if not _integer(distance) or int(distance) < 0:
			issue(issues, slot_path + ".constraints", "离门距离不能为负数")
		constraints["min_distance_from_ports_cells"] = int(distance) if _integer(distance) else 0
		constraints["near_wall"] = _boolean(constraints.get("near_wall", false), slot_path + ".constraints.near_wall", issues)
		constraints["face_port"] = _string(constraints.get("face_port", ""), slot_path + ".constraints.face_port", issues)
		if not str(constraints.get("face_port", "")).is_empty() and not port_ids.has(str(constraints.face_port)):
			issue(issues, slot_path + ".constraints.face_port", "朝向接口不存在")
		slot["constraints"] = constraints
		var members: Array = _array(slot.get("group_members", []), slot_path + ".group_members", issues)
		for member_index: int in range(members.size()):
			var member_path: String = slot_path + ".group_members[%d]" % member_index
			if not members[member_index] is Dictionary:
				issue(issues, member_path, "成组成员必须是对象")
				continue
			var member: Dictionary = members[member_index]
			keys(member, ["kind", "id", "offset", "rotation", "required"], member_path, issues)
			if str(member.get("kind", "")) not in KINDS or not _valid_id(str(member.get("id", ""))) or not valid_cell(member.get("offset")):
				issue(issues, member_path, "成组成员的种类、内容 id 或偏移无效")
			member["rotation"] = _rotation(member.get("rotation", 0), member_path + ".rotation", issues)
			member["required"] = _boolean(member.get("required", true), member_path + ".required", issues)
		slot["group_members"] = members.filter(func(value: Variant) -> bool: return value is Dictionary)
	room["slots"] = slots.filter(func(value: Variant) -> bool: return value is Dictionary)


static func _validate_composition(document: Dictionary, id: String, rooms: Dictionary, issues: Array[Dictionary]) -> void:
	var path: String = "compositions.%s" % id
	keys(document, ["schema_version", "id", "display_name", "nodes", "connections", "primary", "reward_recipe_id"], path, issues)
	_header(document, id, path, issues)
	if document.has("reward_recipe_id"):
		document["reward_recipe_id"] = _string(document.reward_recipe_id, path + ".reward_recipe_id", issues)
	var nodes: Array = _array(document.get("nodes"), path + ".nodes", issues)
	if nodes.is_empty() or nodes.size() > 32:
		issue(issues, path + ".nodes", "组合必须包含 1–32 个节点")
	var by_id: Dictionary = {}
	var max_total: int = 0
	for index: int in range(nodes.size()):
		var node_path: String = path + ".nodes[%d]" % index
		if not nodes[index] is Dictionary:
			issue(issues, node_path, "节点必须是对象")
			continue
		var node: Dictionary = nodes[index]
		keys(node, ["id", "purpose", "blueprints", "min_count", "max_count", "rotations", "position", "rotation"], node_path, issues)
		_unique_id(node, by_id, node_path, issues)
		if node.has("purpose"):
			node["purpose"] = _string(node.purpose, node_path + ".purpose", issues)
		_counts(node, node_path, issues, 32, 1)
		max_total += int(node.max_count)
		node["rotations"] = _rotations(node.get("rotations", ROTATIONS), node_path + ".rotations", issues)
		node["blueprints"] = _weighted(node.get("blueprints", []), node_path + ".blueprints", issues, true)
		for entry: Dictionary in node.blueprints:
			if not rooms.has(entry.id):
				issue(issues, node_path + ".blueprints", "房间引用不存在：%s" % entry.id, "unknown_poi_reference")
				continue
			var allowed: Array = []
			for rotation: int in node.rotations:
				if (rooms[entry.id] as Dictionary).get("rotations", []).has(rotation):
					allowed.append(rotation)
			if allowed.is_empty():
				issue(issues, node_path + ".rotations", "节点与候选图纸没有共同允许的旋转")
		if node.has("position") and (int(node.max_count) != 1 or not valid_cell(node.position)):
			issue(issues, node_path + ".position", "只有单实例节点可指定整数固定位置")
		var capacity: int = 0
		for entry: Dictionary in node.blueprints:
			if float(entry.weight) > 0.0:
				capacity += int(node.max_count) if int(entry.max_instances) == 0 else int(entry.max_instances)
			if node.has("position") and rooms.has(entry.id) and not rooms[entry.id].get("anchors", {}).has("primary"):
				issue(issues, node_path + ".position", "固定位置的候选图纸必须声明 primary 锚点")
		if capacity < int(node.min_count):
			issue(issues, node_path + ".blueprints", "图纸重复容量小于节点最少数量", "poi_port_capacity")
		if node.has("rotation"):
			node["rotation"] = _rotation(node.rotation, node_path + ".rotation", issues)
			if not node.rotations.has(node.rotation):
				issue(issues, node_path + ".rotation", "固定旋转不在节点允许范围内")
			for entry: Dictionary in node.blueprints:
				if rooms.has(entry.id) and not rooms[entry.id].get("rotations", []).has(node.rotation):
					issue(issues, node_path + ".rotation", "固定旋转不在候选图纸允许范围内")
		by_id[str(node.get("id", ""))] = node
	if max_total > 64:
		issue(issues, path + ".nodes", "单 POI 最多 64 个实例")
	var primary: Variant = document.get("primary", {})
	if not primary is Dictionary:
		issue(issues, path + ".primary", "组合必须声明唯一核心锚点")
		primary = {}
	keys(primary, ["node", "anchor"], path + ".primary", issues)
	var primary_node: String = str(primary.get("node", ""))
	var anchor_id: String = str(primary.get("anchor", ""))
	if not by_id.has(primary_node):
		issue(issues, path + ".primary", "核心节点不存在")
	else:
		var root: Dictionary = by_id[primary_node]
		if int(root.min_count) != 1 or int(root.max_count) != 1:
			issue(issues, path + ".primary", "核心锚点来源必须是必需单实例节点")
		for entry: Dictionary in root.blueprints:
			if rooms.has(entry.id) and not (rooms[entry.id] as Dictionary).get("anchors", {}).has(anchor_id):
				issue(issues, path + ".primary.anchor", "所有核心候选图纸必须具有同名锚点")
	var connections: Array = _array(document.get("connections", []), path + ".connections", issues)
	if connections.size() > 128:
		issue(issues, path + ".connections", "一个组合最多 128 条连接规则")
	var connection_ids: Dictionary = {}
	for index: int in range(connections.size()):
		var connection_path: String = path + ".connections[%d]" % index
		if not connections[index] is Dictionary:
			issue(issues, connection_path, "连接规则必须是对象")
			continue
		var connection: Dictionary = connections[index]
		keys(connection, ["id", "mode", "from", "to", "required", "probability", "style", "max_length_cells", "width_cells", "directions"], connection_path, issues)
		_unique_id(connection, connection_ids, connection_path, issues)
		connection["mode"] = str(connection.get("mode", "pair"))
		connection["required"] = _boolean(connection.get("required", true), connection_path + ".required", issues)
		var probability: Variant = connection.get("probability", 1.0)
		if typeof(probability) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(probability)):
			issue(issues, connection_path + ".probability", "概率必须为有限数")
			probability = 0.0
		connection["probability"] = float(probability)
		connection["style"] = str(connection.get("style", "corridor"))
		var length: Variant = connection.get("max_length_cells", 24)
		if not _integer(length):
			issue(issues, connection_path + ".max_length_cells", "连接长度必须为整数")
		connection["max_length_cells"] = int(length) if _integer(length) else 0
		if connection.has("width_cells") and (not _integer(connection.width_cells) or int(connection.width_cells) < 1 or int(connection.width_cells) > 8):
			issue(issues, connection_path + ".width_cells", "显式通道宽度必须为 1–8 格")
		if connection.has("directions"):
			connection["directions"] = _cells(connection.directions, connection_path + ".directions", issues)
			if connection.directions.is_empty() or connection.directions.size() > 4:
				issue(issues, connection_path + ".directions", "方向集合必须含 1–4 个正交单位方向")
			for direction: Variant in connection.directions:
				var vector: Vector2i = vec(direction)
				if absi(vector.x) + absi(vector.y) != 1:
					issue(issues, connection_path + ".directions", "方向必须是正交单位方向")
		if connection.mode not in ["pair", "fan_out", "chain"] or connection.style not in ["direct", "corridor"]:
			issue(issues, connection_path, "未知连接模式或连接样式")
		if connection.probability < 0.0 or connection.probability > 1.0 or (connection.required and connection.probability != 1.0):
			issue(issues, connection_path + ".probability", "概率必须为 0–1，必需连接不能依赖概率")
		if connection.max_length_cells < 1 or connection.max_length_cells > 128:
			issue(issues, connection_path + ".max_length_cells", "连接长度限制必须为 1–128 格")
		for side: String in ["from", "to"]:
			_validate_endpoint(connection.get(side), connection, by_id, rooms, connection_path + "." + side, issues)
		if connection.get("from") is Dictionary and connection.get("to") is Dictionary:
			var a: String = str(connection.from.get("node", ""))
			var b: String = str(connection.to.get("node", ""))
			if connection.mode == "chain" and a != b:
				issue(issues, connection_path, "顺序串联的两个端点必须属于同一重复组")
			if connection.mode == "fan_out" and by_id.has(a) and by_id.has(b):
				if int(by_id[a].max_count) != 1 and int(by_id[b].max_count) != 1:
					issue(issues, connection_path, "逐个接入至少有一个单实例中心节点")
			_validate_connection_ports(connection, by_id, rooms, connection_path, issues)
	document["nodes"] = nodes.filter(func(value: Variant) -> bool: return value is Dictionary)
	document["connections"] = connections.filter(func(value: Variant) -> bool: return value is Dictionary)
	document["primary"] = primary


static func _validate_endpoint(value: Variant, connection: Dictionary, nodes: Dictionary, rooms: Dictionary, path: String, issues: Array[Dictionary]) -> void:
	if not value is Dictionary:
		issue(issues, path, "端点必须是对象")
		return
	var endpoint: Dictionary = value
	keys(endpoint, ["node", "port", "group", "instance"], path, issues)
	for field: String in ["node", "port", "group"]:
		if endpoint.has(field) and (not endpoint[field] is String or not _valid_id(str(endpoint[field]))):
			issue(issues, path + "." + field, "端点引用必须为合法字符串 id")
	var id: String = str(endpoint.get("node", ""))
	if not nodes.has(id):
		issue(issues, path + ".node", "连接引用的节点不存在")
		return
	var node: Dictionary = nodes[id]
	if bool(connection.required) and int(node.min_count) == 0:
		issue(issues, path, "必需连接不能引用可能不存在的节点")
	if endpoint.has("port") == endpoint.has("group"):
		issue(issues, path, "端点必须且只能指定 port 或 group")
	if endpoint.has("instance") and endpoint.instance not in ["first", "last"]:
		issue(issues, path + ".instance", "实例选择只支持 first/last")
	if endpoint.has("instance") and connection.mode != "pair":
		issue(issues, path + ".instance", "只有一对一规则可指定 first/last")
	if connection.mode == "pair" and int(node.max_count) > 1 and not endpoint.has("instance"):
		issue(issues, path, "一对一连接引用重复组时必须指定 first/last")
	for entry: Dictionary in node.blueprints:
		if not rooms.has(entry.id):
			continue
		var matched: bool = false
		for port: Dictionary in rooms[entry.id].get("ports", []):
			if (endpoint.has("port") and port.id == endpoint.port) or (endpoint.has("group") and port.group == endpoint.group):
				matched = true
				if port.kind == "reward_gate":
					issue(issues, path, "奖励门由专用奖励契约管理，不能用作普通房间连接")
		if not matched:
			issue(issues, path, "候选图纸 %s 没有指定接口" % entry.id)


static func _endpoint_ports(endpoint: Dictionary, node: Dictionary, rooms: Dictionary) -> Array:
	var result: Array = []
	for entry: Dictionary in node.blueprints:
		if not rooms.has(entry.id) or float(entry.weight) <= 0.0:
			continue
		for port: Dictionary in rooms[entry.id].get("ports", []):
			if (endpoint.has("port") and port.id == endpoint.port) or (endpoint.has("group") and port.group == endpoint.group):
				result.append(port)
	return result


static func _validate_connection_ports(connection: Dictionary, nodes: Dictionary, rooms: Dictionary, path: String, issues: Array[Dictionary]) -> void:
	var a: String = str(connection.from.get("node", ""))
	var b: String = str(connection.to.get("node", ""))
	if not nodes.has(a) or not nodes.has(b):
		return
	var matched: bool = false
	for from_port: Dictionary in _endpoint_ports(connection.from, nodes[a], rooms):
		for to_port: Dictionary in _endpoint_ports(connection.to, nodes[b], rooms):
			if from_port.kind == to_port.kind and from_port.cells.size() == to_port.cells.size():
				matched = matched or not connection.has("width_cells") or connection.width_cells == from_port.cells.size()
	if not matched:
		issue(issues, path, "两端没有类型与宽度一致的接口", "poi_port_mismatch")
	if connection.mode != "fan_out" or not connection.required:
		return
	var center: Dictionary = nodes[a] if int(nodes[a].max_count) == 1 else nodes[b]
	var leaf: Dictionary = nodes[b] if int(nodes[a].max_count) == 1 else nodes[a]
	var endpoint: Dictionary = connection.from if int(nodes[a].max_count) == 1 else connection.to
	for entry: Dictionary in center.blueprints:
		if not rooms.has(entry.id) or float(entry.weight) <= 0.0:
			continue
		var count: int = 0
		for port: Dictionary in rooms[entry.id].get("ports", []):
			if (endpoint.has("port") and endpoint.port == port.id) or (endpoint.has("group") and endpoint.group == port.group):
				count += 1
		if count < int(leaf.min_count):
			issue(issues, path, "中心图纸 %s 的接口容量 %d 少于必需实例 %d" % [entry.id, count, int(leaf.min_count)], "poi_port_capacity")


static func _header(document: Dictionary, id: String, path: String, issues: Array[Dictionary]) -> void:
	if not _integer(document.get("schema_version")) or int(document.get("schema_version", 0)) != 1:
		issue(issues, path + ".schema_version", "只支持图纸/组合 schema_version=1")
	if not document.get("id") is String or str(document.get("id", "")) != id or not _valid_id(id):
		issue(issues, path + ".id", "资源 id 必须与库键一致且只包含字母数字、下划线或连字符")
	document["display_name"] = _string(document.get("display_name", id), path + ".display_name", issues)


static func _unique_id(value: Dictionary, seen: Dictionary, path: String, issues: Array[Dictionary]) -> void:
	var id: String = str(value.get("id", ""))
	if not value.get("id") is String or not _valid_id(id) or seen.has(id):
		issue(issues, path + ".id", "id 无效或重复")
	value["id"] = id
	seen[id] = true


static func _counts(value: Dictionary, path: String, issues: Array[Dictionary], limit: int, default_count: int) -> void:
	for field: String in ["min_count", "max_count"]:
		var raw: Variant = value.get(field, default_count)
		if not _integer(raw) or int(raw) < 0 or int(raw) > limit:
			issue(issues, path + "." + field, "数量必须是 0–%d 的整数" % limit)
		value[field] = int(raw) if _integer(raw) else 0
	if int(value.min_count) > int(value.max_count):
		issue(issues, path, "最少数量不能超过最多数量")


static func _weighted(value: Variant, path: String, issues: Array[Dictionary], blueprint: bool) -> Array:
	var result: Array = _array(value, path, issues)
	var seen: Dictionary = {}
	var positive: bool = false
	for index: int in range(result.size()):
		if not result[index] is Dictionary:
			issue(issues, path, "候选必须是对象")
			continue
		var entry: Dictionary = result[index]
		keys(entry, ["id", "weight", "max_instances"] if blueprint else ["id", "weight"], path, issues)
		_unique_id(entry, seen, path + "[%d]" % index, issues)
		var weight: Variant = entry.get("weight", 1.0)
		if typeof(weight) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(weight)) or float(weight) < 0.0:
			issue(issues, path, "候选权重必须是非负有限数")
			weight = 0.0
		entry["weight"] = float(weight)
		positive = positive or float(weight) > 0.0
		if blueprint:
			var maximum: Variant = entry.get("max_instances", 0)
			if not _integer(maximum) or int(maximum) < 0:
				issue(issues, path, "图纸重复上限必须是非负整数")
			entry["max_instances"] = int(maximum) if _integer(maximum) else 0
	if not positive:
		issue(issues, path, "至少需要一个正权重候选")
	return result.filter(func(entry: Variant) -> bool: return entry is Dictionary)


static func _rotations(value: Variant, path: String, issues: Array[Dictionary]) -> Array:
	var raw: Array = _array(value, path, issues)
	var result: Array = []
	if raw.is_empty():
		issue(issues, path, "至少允许一个旋转")
	for rotation: Variant in raw:
		var angle: int = _rotation(rotation, path, issues)
		if result.has(angle):
			issue(issues, path, "允许旋转不能重复")
		else:
			result.append(angle)
	return result


static func _boolean(value: Variant, path: String, issues: Array[Dictionary]) -> bool:
	if not value is bool:
		issue(issues, path, "字段必须为布尔值")
		return false
	return value


static func _string(value: Variant, path: String, issues: Array[Dictionary]) -> String:
	if not value is String:
		issue(issues, path, "字段必须为字符串")
		return ""
	return value


static func _rotation(value: Variant, path: String, issues: Array[Dictionary]) -> int:
	if not _integer(value) or int(value) not in ROTATIONS:
		issue(issues, path, "旋转只支持 0/90/180/270 度")
		return 0
	return int(value)


static func _array(value: Variant, path: String, issues: Array[Dictionary]) -> Array:
	if not value is Array:
		issue(issues, path, "字段必须是数组")
		return []
	return value


static func _cells(value: Variant, path: String, issues: Array[Dictionary]) -> Array:
	var result: Array = _array(value, path, issues)
	var seen: Dictionary = {}
	for point: Variant in result:
		if not valid_cell(point):
			issue(issues, path, "格子必须包含整数 x/y")
			continue
		var key: String = cell_key(vec(point))
		if seen.has(key):
			issue(issues, path, "格子不能重复")
		seen[key] = true
	return result.filter(func(point: Variant) -> bool: return valid_cell(point))


static func keys(value: Dictionary, allowed: Array, path: String, issues: Array[Dictionary]) -> void:
	for field: Variant in value:
		if not allowed.has(str(field)):
			issue(issues, path + "." + str(field), "未声明字段")


static func valid_cell(value: Variant) -> bool:
	return value is Dictionary and (value as Dictionary).size() == 2 and _integer(value.get("x")) and _integer(value.get("y"))


static func _integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value)


static func _valid_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code in [45, 95]):
			return false
	return true


static func vec(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)) if _integer(value.get("x")) else 0, int(value.get("y", 0)) if _integer(value.get("y")) else 0)
	return Vector2i.ZERO


static func cell(value: Vector2i) -> Dictionary:
	return {"x": value.x, "y": value.y}


static func cell_key(value: Vector2i) -> String:
	return "%d,%d" % [value.x, value.y]


static func issue(issues: Array[Dictionary], path: String, message: String, code: String = "invalid_poi_definition") -> void:
	issues.append({"code": code, "path": path, "message": message})
