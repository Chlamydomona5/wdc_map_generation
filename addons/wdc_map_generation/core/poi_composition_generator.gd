class_name WdcPoiCompositionGenerator
extends RefCounted

## 图纸组装的唯一纯生成入口；预算分配与 authority 实体化由调用方负责。
const C = preload("poi_blueprint_compiler.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const ALGORITHM_VERSION: int = 2


static func generate(composition_id: String, bundle: Dictionary, seed: int, request: Dictionary = {}) -> Dictionary:
	if not bool(bundle.get("valid", false)):
		return {"valid": false, "plan": {}, "issues": bundle.get("issues", [])}
	if not bundle.get("compositions", {}).has(composition_id):
		return _failure("compositions." + composition_id, "组合不存在", "unknown_poi_reference")
	var composition: Dictionary = bundle.compositions[composition_id]
	var limits: Dictionary = {
		"attempts": clampi(int(request.get("max_attempts", 8)), 1, 32),
		"search": clampi(int(request.get("max_search_nodes", 1024)), 1, 16384),
		"corridor": clampi(int(request.get("max_corridor_steps", 4096)), 1, 65536),
		"radius": clampi(int(request.get("max_radius_cells", 96)), 1, 512),
		"depth": clampi(int(request.get("max_backtrack_depth", 128)), 1, 256),
	}
	var origin: Vector2i = C.vec(request.get("origin", {}))
	var diagnostic: Dictionary = {"attempts": 0, "search_nodes": 0, "corridor_steps": 0, "last_reason": "没有可行组装", "last_path": "compositions." + composition_id, "exhausted_budget": "", "max_depth": 0}
	for attempt: int in range(limits.attempts):
		diagnostic.attempts = attempt + 1
		diagnostic.exhausted_budget = ""
		var expansion: Dictionary = _expand(composition, bundle.rooms, seed, attempt, attempt == limits.attempts - 1)
		if not expansion.valid:
			diagnostic.last_reason = expansion.message
			continue
		var context: Dictionary = {
			"composition": composition, "instances": expansion.instances, "edges": expansion.edges,
			"origin": origin, "allowed": _cell_set(request.get("allowed_cells", [])), "blocked": _cell_set(request.get("blocked_cells", [])),
			"limits": limits, "diagnostic": diagnostic, "attempt_nodes": 0, "corridor_steps": 0,
		}
		var state: Dictionary = {"rooms": {}, "occupied": {}, "clearance": {}, "used": {}, "connections": [], "done": {}}
		var solved: Dictionary = _place_roots(state, context)
		if solved.is_empty():
			continue
		var result: Dictionary = _finalize(solved, context, bundle, seed, request)
		if result.valid:
			result.plan["diagnostics"] = diagnostic.duplicate(true)
			result.plan["composition_id"] = composition_id
			result.plan["algorithm_version"] = ALGORITHM_VERSION
			return result
		diagnostic.last_reason = str(result.issues[0].message)
		diagnostic.last_path = str(result.issues[0].path)
	var failed: Dictionary = _failure(str(diagnostic.last_path), "组装失败：%s" % diagnostic.last_reason, "poi_search_exhausted")
	failed["diagnostics"] = diagnostic
	return failed


static func _expand(composition: Dictionary, rooms: Dictionary, seed: int, attempt: int, minimum: bool) -> Dictionary:
	var instances: Dictionary = {}
	var groups: Dictionary = {}
	for node: Dictionary in composition.nodes:
		var rng: RandomNumberGenerator = _rng(seed, "layout:%s:%d" % [node.id, attempt])
		var count: int = int(node.min_count) if minimum else rng.randi_range(int(node.min_count), int(node.max_count))
		var counts: Dictionary = {}
		groups[node.id] = []
		for index: int in range(count):
			var candidates: Array = []
			for entry: Dictionary in node.blueprints:
				if float(entry.weight) > 0.0 and (int(entry.max_instances) == 0 or int(counts.get(entry.id, 0)) < int(entry.max_instances)):
					candidates.append(entry)
			if candidates.is_empty():
				return {"valid": false, "message": "节点 %s 的图纸重复上限不足" % node.id}
			var selected: Dictionary = _weighted(candidates, rng)
			counts[selected.id] = int(counts.get(selected.id, 0)) + 1
			var source: Dictionary = rooms[selected.id]
			var rotations: Array = []
			for angle: Variant in node.rotations:
				if source.rotations.has(angle) and (not node.has("rotation") or int(node.rotation) == int(angle)):
					rotations.append(int(angle))
			_shuffle(rotations, rng)
			var id: String = "%s:%d" % [node.id, index]
			instances[id] = {"id": id, "node": node, "source": source, "rotations": rotations}
			groups[node.id].append(id)
	var edges: Array = []
	for rule: Dictionary in composition.connections:
		var rng: RandomNumberGenerator = _rng(seed, "connection:%s:%d" % [rule.id, attempt])
		if not rule.required and rng.randf() >= float(rule.probability):
			continue
		var from_ids: Array = groups[rule.from.node]
		var to_ids: Array = groups[rule.to.node]
		if from_ids.is_empty() or to_ids.is_empty():
			continue
		if rule.mode == "chain":
			for index: int in range(from_ids.size() - 1):
				edges.append(_edge(rule, from_ids[index], from_ids[index + 1], index))
		elif rule.mode == "fan_out":
			if from_ids.size() == 1:
				for index: int in range(to_ids.size()):
					edges.append(_edge(rule, from_ids[0], to_ids[index], index))
			else:
				for index: int in range(from_ids.size()):
					edges.append(_edge(rule, from_ids[index], to_ids[0], index))
		else:
			var a: String = from_ids.back() if rule.from.get("instance", "first") == "last" else from_ids.front()
			var b: String = to_ids.back() if rule.to.get("instance", "first") == "last" else to_ids.front()
			edges.append(_edge(rule, a, b, 0))
	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.id) < str(b.id) if a.required == b.required else bool(a.required))
	return {"valid": true, "instances": instances, "edges": edges}


static func _edge(rule: Dictionary, a: String, b: String, index: int) -> Dictionary:
	return {"id": "%s:%d" % [rule.id, index], "rule_id": rule.id, "a": a, "b": b,
		"from": rule.from, "to": rule.to, "required": rule.required, "style": rule.style, "max_length": rule.max_length_cells,
		"width": int(rule.get("width_cells", 0)), "directions": _vectors(rule.get("directions", [C.cell(Vector2i.RIGHT), C.cell(Vector2i.DOWN), C.cell(Vector2i.LEFT), C.cell(Vector2i.UP)]))}


static func _place_roots(state: Dictionary, context: Dictionary) -> Dictionary:
	var primary: Dictionary = context.composition.primary
	var root_id: String = str(primary.node) + ":0"
	var ordered: Array = [root_id]
	for id: String in context.instances:
		if id != root_id and context.instances[id].node.has("position"):
			ordered.append(id)
	return _search_roots(state, context, ordered, 0)


static func _search_roots(state: Dictionary, context: Dictionary, ordered: Array, index: int) -> Dictionary:
	if index == ordered.size():
		return _search(state, context)
	var id: String = ordered[index]
	var instance: Dictionary = context.instances[id]
	var primary: Dictionary = context.composition.primary
	var anchor: Vector2i = C.vec(instance.source.anchors.get(primary.anchor if index == 0 else "primary", {}))
	var target: Vector2i = context.origin if index == 0 else context.origin + C.vec(instance.node.position)
	for rotation: int in instance.rotations:
		if int(context.attempt_nodes) >= int(context.limits.search):
			_exhausted(context, "search_nodes", "房间候选搜索额度耗尽")
			return {}
		context.attempt_nodes += 1
		context.diagnostic.search_nodes += 1
		var room: Dictionary = _transform(instance, rotation, target - _rotate(anchor, rotation))
		if not _fits(room, state, context):
			context.diagnostic.last_reason = "固定房间 %s 与占地限制冲突" % id
			context.diagnostic.last_path = "compositions.%s.nodes.%s" % [context.composition.id, instance.node.id]
			continue
		var next: Dictionary = state.duplicate(true)
		_add_room(next, room)
		var solved: Dictionary = _search_roots(next, context, ordered, index + 1)
		if not solved.is_empty():
			return solved
	return {}


static func _search(state: Dictionary, context: Dictionary) -> Dictionary:
	context.diagnostic.max_depth = maxi(int(context.diagnostic.max_depth), state.done.size())
	if state.done.size() > int(context.limits.depth):
		_exhausted(context, "backtrack_depth", "连接回退深度额度耗尽")
		return {}
	var selected: Dictionary = {}
	# 必需连接先解；选择已落位端点可向外展开的连接。
	for edge: Dictionary in context.edges:
		if not state.done.has(edge.id) and (state.rooms.has(edge.a) or state.rooms.has(edge.b)):
			selected = edge
			break
	if selected.is_empty():
		var counts: Dictionary = {}
		for room: Dictionary in state.rooms.values():
			var node_id: String = str(context.instances[room.id].node.id)
			counts[node_id] = int(counts.get(node_id, 0)) + 1
		for node: Dictionary in context.composition.nodes:
			if int(counts.get(node.id, 0)) < int(node.min_count):
				context.diagnostic.last_reason = "节点 %s 缺少必需实例或与核心断开" % node.id
				context.diagnostic.last_path = "compositions.%s.nodes.%s" % [context.composition.id, node.id]
				return {}
		for edge: Dictionary in context.edges:
			if edge.required and not state.done.has(edge.id) and (state.rooms.has(edge.a) or state.rooms.has(edge.b)):
				context.diagnostic.last_reason = "必需连接 %s 未完成" % edge.id
				return {}
		return state
	var edge: Dictionary = selected
	if int(context.attempt_nodes) >= int(context.limits.search):
		_exhausted(context, "search_nodes", "房间候选搜索额度耗尽")
		if not edge.required:
			var skipped: Dictionary = state.duplicate(true)
			skipped.done[edge.id] = true
			return _search(skipped, context)
		return {}
	context.diagnostic.last_path = "compositions.%s.connections.%s" % [context.composition.id, edge.rule_id]
	var reverse: bool = not state.rooms.has(edge.a)
	var known_id: String = edge.b if reverse else edge.a
	var other_id: String = edge.a if reverse else edge.b
	var known_endpoint: Dictionary = edge.to if reverse else edge.from
	var other_endpoint: Dictionary = edge.from if reverse else edge.to
	var known: Dictionary = state.rooms[known_id]
	for port: Dictionary in _ports(known, known_endpoint, state.used):
		if (edge.width != 0 and edge.width != port.points.size()) or not edge.directions.has(-port.direction if reverse else port.direction):
			continue
		if state.rooms.has(other_id):
			var other: Dictionary = state.rooms[other_id]
			for other_port: Dictionary in _ports(other, other_endpoint, state.used):
				var solved: Dictionary = _try_connection(state, context, edge, known, port, other, other_port, false, reverse)
				if not solved.is_empty():
					return solved
		else:
			var instance: Dictionary = context.instances[other_id]
			for angle: int in instance.rotations:
				var local_room: Dictionary = _transform(instance, angle, Vector2i.ZERO)
				for local_port: Dictionary in _ports(local_room, other_endpoint, state.used):
					if not _compatible(port, local_port):
						continue
					var width: int = port.points.size()
					var gap: int = maxi(width, 2)
					var distances: Array = [1] if edge.style == "direct" else [gap + 1, gap + 3, gap + 5, gap + 7]
					var tangents: Array = [0] if edge.style == "direct" else [0, width + 1, -width - 1, width * 2 + 2, -width * 2 - 2]
					for distance: int in distances:
						if distance > int(edge.max_length):
							continue
						for tangent: int in tangents:
							if int(context.attempt_nodes) >= int(context.limits.search):
								break
							var offset: Vector2i = _minimum(port.points) - _minimum(local_port.points) + port.direction * distance
							offset += Vector2i(-port.direction.y, port.direction.x) * tangent
							var candidate: Dictionary = _transform(instance, angle, offset)
							var candidate_port: Dictionary = candidate.ports[str(local_port.id)]
							var solved: Dictionary = _try_connection(state, context, edge, known, port, candidate, candidate_port, true, reverse)
							if not solved.is_empty():
								return solved
	if not edge.required:
		var skipped: Dictionary = state.duplicate(true)
		skipped.done[edge.id] = true
		return _search(skipped, context)
	if str(context.diagnostic.exhausted_budget).is_empty():
		context.diagnostic.last_reason = "连接 %s 无兼容接口、剩余容量或通路" % edge.id
	return {}


static func _try_connection(state: Dictionary, context: Dictionary, edge: Dictionary, known: Dictionary, port: Dictionary, other: Dictionary, other_port: Dictionary, add_room: bool, reverse: bool) -> Dictionary:
	if int(context.attempt_nodes) >= int(context.limits.search):
		_exhausted(context, "search_nodes", "房间候选搜索额度耗尽")
		return {}
	context.attempt_nodes += 1
	context.diagnostic.search_nodes += 1
	if not _compatible(port, other_port) or known.id == other.id:
		return {}
	if add_room and not _fits(other, state, context):
		return {}
	var next: Dictionary = state.duplicate(true)
	if add_room:
		_add_room(next, other)
	var route: Dictionary = _route(port, other_port, edge, next, context)
	if not route.valid:
		return {}
	next.used[str(known.id) + "/" + str(port.id)] = true
	next.used[str(other.id) + "/" + str(other_port.id)] = true
	next.done[edge.id] = true
	next.connections.append({"id": edge.id, "rule_id": edge.rule_id, "required": edge.required,
		"from": {"room_instance_id": other.id if reverse else known.id, "port_id": other_port.id if reverse else port.id},
		"to": {"room_instance_id": known.id if reverse else other.id, "port_id": port.id if reverse else other_port.id},
		"style": edge.style, "width_cells": port.points.size(), "corridor_cells": _json_cells(route.points),
		"corridor_wall_cells": _json_cells(route.get("walls", [])),
		"port_cells": _json_cells(port.points + other_port.points)})
	# 走廊地板和包边墙共同占地；后续走廊可相交，后续房间不能覆盖侧墙。
	for point: Vector2i in route.points:
		next.occupied[point] = "corridor"
	for point: Vector2i in route.get("walls", []):
		if not next.occupied.has(point):
			next.occupied[point] = "corridor_wall"
	return _search(next, context)


static func _route(a: Dictionary, b: Dictionary, edge: Dictionary, state: Dictionary, context: Dictionary) -> Dictionary:
	var adjacent: bool = true
	var b_set: Dictionary = _vector_cell_set(b.points)
	for point: Vector2i in a.points:
		adjacent = adjacent and b_set.has(point + a.direction)
	if adjacent:
		return {"valid": edge.style == "direct", "points": []}
	if edge.style == "direct":
		return {"valid": false}
	var width: int = a.points.size()
	var apertures: Dictionary = _vector_cell_set(a.points + b.points)
	for port: Dictionary in [a, b]:
		for point: Vector2i in port.points:
			apertures[point + port.direction] = true
	var start: Vector2i = _brush_start(a)
	var finish: Vector2i = _brush_start(b)
	if _manhattan(start, finish) + width > int(edge.max_length):
		return {"valid": false}
	# 快路径覆盖直线和两个直角；有障碍再进入有界正交 BFS。
	for bend: Vector2i in [Vector2i(finish.x, start.y), Vector2i(start.x, finish.y)]:
		var path: Array = _line(start, bend)
		var tail: Array = _line(bend, finish)
		tail.pop_front()
		path.append_array(tail)
		var valid: bool = true
		for base: Vector2i in path:
			if not _brush_fits(base, width, state, context, apertures):
				valid = false
				break
		if valid:
			return _corridor_result(path, width, state, apertures)
	if not _brush_fits(start, width, state, context, apertures) or not _brush_fits(finish, width, state, context, apertures):
		return {"valid": false}
	var queue: Array[Vector2i] = [start]
	var previous: Dictionary = {start: start}
	var distances: Dictionary = {start: 0}
	var cursor: int = 0
	while cursor < queue.size() and int(context.corridor_steps) < int(context.limits.corridor):
		var point: Vector2i = queue[cursor]
		cursor += 1
		context.diagnostic.corridor_steps += 1
		context.corridor_steps += 1
		if point == finish:
			var path: Array = [finish]
			while path.back() != start:
				path.append(previous[path.back()])
			return _corridor_result(path, width, state, apertures)
		for direction: Vector2i in DIRECTIONS:
			var next: Vector2i = point + direction
			var distance: int = int(distances[point]) + 1
			if previous.has(next) or distance + _manhattan(next, finish) + width > int(edge.max_length):
				continue
			if _brush_fits(next, width, state, context, apertures):
				previous[next] = point
				distances[next] = distance
				queue.append(next)
	if cursor < queue.size():
		_exhausted(context, "corridor_steps", "通道正交寻路额度耗尽")
	return {"valid": false}


static func _brush_start(port: Dictionary) -> Vector2i:
	var point: Vector2i = _minimum(port.points)
	var width: int = port.points.size()
	if port.direction.x > 0:
		point.x += 1
	elif port.direction.x < 0:
		point.x -= width
	elif port.direction.y > 0:
		point.y += 1
	else:
		point.y -= width
	return point


static func _brush_fits(base: Vector2i, width: int, state: Dictionary, context: Dictionary, apertures: Dictionary) -> bool:
	for y: int in range(width):
		for x: int in range(width):
			var point: Vector2i = base + Vector2i(x, y)
			if (state.occupied.has(point) and state.occupied[point] not in ["corridor", "corridor_wall"]) or not _in_bounds(point, context):
				return false
	# 每段寻路同时检查一格包边，拐角也保留结构墙；只在声明的门口接入房间。
	for y: int in range(-1, width + 1):
		for x: int in range(-1, width + 1):
			if x >= 0 and x < width and y >= 0 and y < width:
				continue
			var point: Vector2i = base + Vector2i(x, y)
			if apertures.has(point):
				continue
			if not _in_bounds(point, context):
				return false
			var owner: String = str(state.occupied.get(point, ""))
			if owner in ["corridor", "corridor_wall"]:
				continue
			if state.clearance.has(point):
				return false
			if not owner.is_empty():
				var room: Dictionary = state.rooms[owner]
				if room.raster[point] != "#":
					return false
				for port: Dictionary in room.ports.values():
					if port.points.has(point) and (port.unused == "open" or state.used.has(owner + "/" + str(port.id))):
						return false
	return true


static func _corridor_result(path: Array, width: int, state: Dictionary, apertures: Dictionary) -> Dictionary:
	var points: Array = _brush_path(path, width)
	if points.size() < width * 2:
		return {"valid": false}
	var floors: Dictionary = _vector_cell_set(points)
	var walls: Dictionary = {}
	for point: Vector2i in points:
		for y: int in range(-1, 2):
			for x: int in range(-1, 2):
				var neighbor: Vector2i = point + Vector2i(x, y)
				if floors.has(neighbor) or apertures.has(neighbor) or state.occupied.get(neighbor, "") == "corridor":
					continue
				walls[neighbor] = true
	return {"valid": true, "points": points, "walls": walls.keys()}


static func _brush_path(path: Array, width: int) -> Array:
	var cells: Dictionary = {}
	for point: Vector2i in path:
		for y: int in range(width):
			for x: int in range(width):
				cells[point + Vector2i(x, y)] = true
	return cells.keys()


static func _transform(instance: Dictionary, rotation: int, offset: Vector2i) -> Dictionary:
	var source: Dictionary = instance.source
	var raster: Dictionary = {}
	for y: int in range(source.cells.size()):
		for x: int in range(str(source.cells[y]).length()):
			var character: String = str(source.cells[y]).substr(x, 1)
			if character != " ":
				raster[_rotate(Vector2i(x, y), rotation) + offset] = character
	var ports: Dictionary = {}
	for port: Dictionary in source.ports:
		ports[port.id] = {"id": port.id, "kind": port.kind, "group": port.group, "unused": port.unused,
			"points": _transform_cells(port.cells, rotation, offset), "direction": _rotate(C.vec(port.normal), rotation)}
	var anchors: Dictionary = {}
	for id: String in source.anchors:
		anchors[id] = _rotate(C.vec(source.anchors[id]), rotation) + offset
	return {"id": instance.id, "blueprint_id": source.id, "purpose": instance.node.get("purpose", source.get("purpose", "")),
		"raster": raster, "ports": ports, "anchors": anchors, "rotation": rotation, "offset": offset, "source": source}


static func _fits(room: Dictionary, state: Dictionary, context: Dictionary) -> bool:
	for point: Vector2i in room.raster:
		if state.occupied.has(point) or not _in_bounds(point, context):
			return false
	return true


static func _in_bounds(point: Vector2i, context: Dictionary) -> bool:
	var delta: Vector2i = point - context.origin
	return absi(delta.x) <= int(context.limits.radius) and absi(delta.y) <= int(context.limits.radius) and not context.blocked.has(point) and (context.allowed.is_empty() or context.allowed.has(point))


static func _add_room(state: Dictionary, room: Dictionary) -> void:
	state.rooms[room.id] = room
	for point: Vector2i in room.raster:
		state.occupied[point] = room.id
	for point: Vector2i in _transform_cells(room.source.keep_clear, room.rotation, room.offset):
		state.clearance[point] = true
	for port: Dictionary in room.ports.values():
		if port.unused == "open":
			for point: Vector2i in port.points:
				state.clearance[point + port.direction] = true


static func _ports(room: Dictionary, endpoint: Dictionary, used: Dictionary) -> Array:
	var result: Array = []
	var ids: Array = room.ports.keys()
	ids.sort()
	for id: String in ids:
		var port: Dictionary = room.ports[id]
		if used.has(str(room.id) + "/" + id):
			continue
		if (endpoint.has("port") and endpoint.port == id) or (endpoint.has("group") and endpoint.group == port.group):
			result.append(port)
	return result


static func _compatible(a: Dictionary, b: Dictionary) -> bool:
	return a.kind == b.kind and a.points.size() == b.points.size() and a.direction == -b.direction


static func _finalize(state: Dictionary, context: Dictionary, bundle: Dictionary, seed: int, request: Dictionary) -> Dictionary:
	var floor_cells: Dictionary = {}
	var wall_cells: Dictionary = {}
	var keep_clear: Dictionary = {context.origin: true}
	var gate_cells: Dictionary = {}
	var named: Dictionary = {}
	var rooms: Array = []
	var exterior_entries: Array = []
	var root_id: String = str(context.composition.primary.node) + ":0"
	var ids: Array = state.rooms.keys()
	ids.sort()
	for id: String in ids:
		var room: Dictionary = state.rooms[id]
		var raster: Dictionary = room.raster.duplicate()
		var ports: Array = []
		for port: Dictionary in room.ports.values():
			var used: bool = state.used.has(id + "/" + str(port.id))
			for point: Vector2i in port.points:
				raster[point] = "." if used or port.unused == "open" else "#"
				if used or port.unused == "open":
					keep_clear[point] = true
					keep_clear[point - port.direction] = true
				if port.kind == "reward_gate":
					gate_cells[point] = true
				elif not used and port.unused == "open":
					exterior_entries.append({"cell": point + port.direction, "path": "rooms.%s.ports.%s" % [room.blueprint_id, port.id]})
			ports.append({"id": port.id, "kind": port.kind, "group": port.group, "unused": port.unused,
				"consumed": used, "cells": _json_cells(port.points), "normal": C.cell(port.direction), "width_cells": port.points.size()})
		var room_floors: Array = []
		var room_walls: Array = []
		for point: Vector2i in raster:
			if raster[point] == ".":
				floor_cells[point] = true
				room_floors.append(point)
			else:
				wall_cells[point] = true
				room_walls.append(point)
		for point: Vector2i in _transform_cells(room.source.keep_clear, room.rotation, room.offset):
			keep_clear[point] = true
		var anchors: Dictionary = {}
		for anchor: String in room.anchors:
			anchors[anchor] = C.cell(room.anchors[anchor])
			named[id + "." + anchor] = anchors[anchor]
			if id == root_id:
				named[anchor] = anchors[anchor]
		rooms.append({"id": id, "room_instance_id": id, "blueprint_id": room.blueprint_id, "purpose": room.purpose,
			"transform": {"rotation": room.rotation, "origin": C.cell(room.offset)}, "anchors": anchors, "ports": ports,
			"floor_cells": _json_cells(room_floors), "wall_cells": _json_cells(room_walls), "footprint_cells": _json_cells(raster.keys())})
	for connection: Dictionary in state.connections:
		for point: Vector2i in _vectors(connection.corridor_cells):
			floor_cells[point] = true
			keep_clear[point] = true
	for connection: Dictionary in state.connections:
		var walls: Array[Vector2i] = []
		for point: Vector2i in _vectors(connection.get("corridor_wall_cells", [])):
			if not floor_cells.has(point):
				wall_cells[point] = true
				walls.append(point)
		connection["corridor_wall_cells"] = _json_cells(walls)
	for entrance: Dictionary in exterior_entries:
		if wall_cells.has(entrance.cell) or not _in_bounds(entrance.cell, context):
			return _failure(entrance.path, "外部入口被其他房墙或占地边界封住", "poi_port_clearance")
	var walkable: Dictionary = floor_cells.duplicate()
	walkable.merge(gate_cells, true)
	var reachable: Dictionary = _flood(context.origin, walkable, {})
	if reachable.size() != walkable.size():
		return _failure("compositions." + str(context.composition.id), "图纸或连接存在与核心不连通的地板", "poi_disconnected")
	named["primary"] = C.cell(context.origin)
	var content: Dictionary = _resolve_content(state, floor_cells, wall_cells, keep_clear, walkable, context.origin, bundle, seed, request)
	if not content.valid:
		return content
	var footprint: Dictionary = floor_cells.duplicate()
	footprint.merge(wall_cells, true)
	return {"valid": true, "issues": [], "plan": {"rooms": rooms, "connections": state.connections,
		"floor_cells": _json_cells(floor_cells.keys()), "wall_cells": _json_cells(wall_cells.keys()),
		"footprint_cells": _json_cells(footprint.keys()), "keep_clear": _json_cells(keep_clear.keys()),
		"anchors": named, "primary_anchor": C.cell(context.origin), "content_requests": content.requests, "bounds": _bounds(footprint.keys())}}


static func _resolve_content(state: Dictionary, floors: Dictionary, walls: Dictionary, keep_clear: Dictionary, walkable: Dictionary, origin: Vector2i, bundle: Dictionary, seed: int, request: Dictionary) -> Dictionary:
	var capabilities: Dictionary = {}
	for entry: Dictionary in bundle.get("capabilities", {}).get("entries", []):
		capabilities[str(entry.kind) + "/" + str(entry.id)] = entry
	var slots: Array = []
	for room: Dictionary in state.rooms.values():
		for source: Dictionary in room.source.slots:
			slots.append({"room": room, "source": source, "id": str(room.id) + "/" + str(source.id)})
	slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.id) < str(b.id) if a.source.required == b.source.required else bool(a.source.required))
	var occupied: Dictionary = {}
	var clearance: Dictionary = {}
	var solid: Dictionary = {}
	var exclusive: Dictionary = {}
	var requests: Array = []
	for item: Dictionary in slots:
		var slot: Dictionary = item.source
		var room: Dictionary = item.room
		var path: String = "rooms.%s.slots.%s" % [room.blueprint_id, slot.id]
		var group: String = str(room.id) + "/" + str(slot.exclusive_group)
		if not str(slot.exclusive_group).is_empty() and exclusive.has(group):
			if slot.required:
				return _failure(path, "必需槽位互斥组冲突", "poi_slot_conflict")
			continue
		var entries: Array = _content_entries(slot.kind, slot.entries, request, capabilities)
		if entries.is_empty():
			if slot.required:
				return _failure(path, "必需内容无可用候选或不被当前区域允许", "poi_content_unavailable")
			continue
		var rng: RandomNumberGenerator = _rng(seed, "content:" + str(item.id))
		var count: int = rng.randi_range(int(slot.min_count), int(slot.max_count))
		var points: Array = _transform_cells(slot.points + slot.region, room.rotation, room.offset)
		points = _vector_cell_set(points).keys()
		_shuffle(points, rng)
		var placed: int = 0
		for anchor: Vector2i in points:
			if placed >= count:
				break
			if not _slot_conditions(anchor, slot, room, walls):
				continue
			var rotation: int = posmod(int(slot.rotation) + int(room.rotation), 360)
			var face: String = str(slot.constraints.get("face_port", ""))
			if not face.is_empty():
				var delta: Vector2i = _minimum(room.ports[face].points) - anchor
				rotation = (90 if delta.x < 0 else 270) if absi(delta.x) > absi(delta.y) else (0 if delta.y >= 0 else 180)
			var main: Dictionary = _content_request(slot.kind, entries, anchor, rotation, slot, room, capabilities, rng)
			var candidates: Array = [main]
			var local_occupied: Dictionary = occupied.duplicate()
			var local_clearance: Dictionary = clearance.duplicate()
			if not _reserve(main, floors, walls, keep_clear, local_occupied, local_clearance):
				continue
			var group_valid: bool = true
			for member_index: int in range(slot.group_members.size()):
				var member: Dictionary = slot.group_members[member_index]
				var member_entries: Array = _content_entries(member.kind, [{"id": member.id, "weight": 1.0}], request, capabilities)
				var member_slot: Dictionary = {"id": "%s.member_%d" % [slot.id, member_index], "required": bool(slot.required) and bool(member.required), "member_required": bool(member.required)}
				var member_anchor: Vector2i = anchor + _rotate(C.vec(member.offset), rotation)
				var member_request: Dictionary = {} if member_entries.is_empty() else _content_request(member.kind, member_entries, member_anchor, posmod(rotation + int(member.rotation), 360), member_slot, room, capabilities, rng)
				if member_request.is_empty() or not _reserve(member_request, floors, walls, keep_clear, local_occupied, local_clearance):
					if member.required:
						group_valid = false
						break
					continue
				candidates.append(member_request)
			if not group_valid:
				continue
			var candidate_solid: Dictionary = solid.duplicate()
			for candidate: Dictionary in candidates:
				if candidate.kind in ["prop", "camp", "nest"]:
					for point: Vector2i in _vectors(candidate.placement_footprint):
						if not candidate.get("guard_cells", []).has(C.cell(point)):
							candidate_solid[point] = true
			var accessible: Dictionary = _flood(origin, walkable, candidate_solid)
			var blocked_floor_count: int = 0
			for point: Vector2i in candidate_solid:
				if walkable.has(point):
					blocked_floor_count += 1
			var access_valid: bool = accessible.size() + blocked_floor_count == walkable.size()
			for point: Vector2i in keep_clear:
				access_valid = access_valid and accessible.has(point)
			for candidate: Dictionary in requests + candidates:
				var footprint: Dictionary = _cell_set(candidate.placement_footprint)
				var has_access: bool = false
				for point: Vector2i in footprint:
					for direction: Vector2i in DIRECTIONS:
						if accessible.has(point + direction) and not footprint.has(point + direction):
							has_access = true
				access_valid = access_valid and has_access
			if not access_valid:
				continue
			var group_id: String = "%s/%s:%d" % [room.id, slot.id, placed]
			var required_group: bool = bool(slot.required) and placed < int(slot.min_count)
			for candidate_index: int in range(candidates.size()):
				var candidate: Dictionary = candidates[candidate_index]
				var required_member: bool = bool(candidate.get("member_required", true))
				candidate["group_instance_id"] = group_id
				candidate["group_required"] = required_group
				candidate["member_required"] = required_member
				candidate["required"] = required_group and required_member
				candidate["request_id"] = "%s/%s" % [group_id, candidate.slot_id]
			occupied = local_occupied
			clearance = local_clearance
			solid = candidate_solid
			requests.append_array(candidates)
			placed += 1
		if placed < int(slot.min_count) and slot.required:
			return _failure(path, "必需槽位占地、通路、净空或成组成员无法满足", "poi_slot_conflict")
		if placed > 0 and not str(slot.exclusive_group).is_empty():
			exclusive[group] = true
	return {"valid": true, "requests": requests}


static func _content_entries(kind: String, entries: Array, request: Dictionary, capabilities: Dictionary) -> Array:
	var result: Array = []
	var allowed: Variant = request.get("content_entries_by_kind", {}).get(kind)
	var allowed_ids: Dictionary = {}
	if allowed is Array:
		for entry: Variant in allowed:
			allowed_ids[str(entry.get("id", entry.get("content_id", ""))) if entry is Dictionary else str(entry)] = true
	for entry: Dictionary in entries:
		var key: String = kind + "/" + str(entry.id)
		if float(entry.weight) <= 0.0 or (allowed is Array and not allowed_ids.has(str(entry.id))):
			continue
		if not capabilities.is_empty() and (not capabilities.has(key) or not bool(capabilities[key].get("available", false))):
			continue
		result.append(entry.duplicate(true))
	return result


static func _content_request(kind: String, entries: Array, anchor: Vector2i, rotation: int, slot: Dictionary, room: Dictionary, capabilities: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var footprint: Dictionary = {}
	var clearance: Dictionary = {}
	var surfaces: Dictionary = {}
	# 预留所有候选的并集，后续区域预算重选 id 不会放大实际占地。
	for entry: Dictionary in entries:
		var capability: Dictionary = capabilities.get(kind + "/" + str(entry.id), {})
		for point: Vector2i in _transform_cells(capability.get("footprint_cells", [{"x": 0, "y": 0}]), rotation, anchor):
			footprint[point] = true
		for point: Vector2i in _transform_cells(capability.get("clearance_cells", []), rotation, anchor):
			clearance[point] = true
		surfaces[str(capability.get("placement_surface", "wall" if kind == "mineral" else "floor"))] = true
	for point: Vector2i in _transform_cells(slot.get("footprint", []), rotation, anchor):
		footprint[point] = true
	for point: Vector2i in _transform_cells(slot.get("clearance", []), rotation, anchor):
		clearance[point] = true
	var guards: Array = _transform_cells(slot.get("guard_points", []), rotation, anchor)
	for point: Vector2i in guards:
		footprint[point] = true
	var selected: Dictionary = _weighted(entries, rng)
	return {"kind": kind, "content_id": selected.id, "entries": entries.duplicate(true), "cell": C.cell(anchor),
		"rotation": rotation, "slot_id": slot.id, "room_instance_id": room.id, "required": slot.get("required", true),
		"member_required": slot.get("member_required", true),
		"placement_footprint": _json_cells(footprint.keys()), "clearance_cells": _json_cells(clearance.keys()),
		"guard_cells": _json_cells(guards), "placement_surfaces": surfaces.keys()}


static func _reserve(candidate: Dictionary, floors: Dictionary, walls: Dictionary, keep_clear: Dictionary, occupied: Dictionary, clearance: Dictionary) -> bool:
	var footprint: Dictionary = _cell_set(candidate.placement_footprint)
	for point: Vector2i in footprint:
		if occupied.has(point) or clearance.has(point) or keep_clear.has(point):
			return false
		for surface: String in candidate.placement_surfaces:
			if (surface == "wall" and not walls.has(point)) or (surface == "floor" and not floors.has(point)):
				return false
	for point: Vector2i in _vectors(candidate.clearance_cells):
		if not floors.has(point) or occupied.has(point) or footprint.has(point):
			return false
	occupied.merge(footprint, true)
	clearance.merge(_cell_set(candidate.clearance_cells), true)
	return true


static func _slot_conditions(anchor: Vector2i, slot: Dictionary, room: Dictionary, walls: Dictionary) -> bool:
	if bool(slot.constraints.get("near_wall", false)):
		var near: bool = false
		for direction: Vector2i in DIRECTIONS:
			near = near or walls.has(anchor + direction)
		if not near:
			return false
	var minimum: int = int(slot.constraints.get("min_distance_from_ports_cells", 0))
	for port: Dictionary in room.ports.values():
		for point: Vector2i in port.points:
			if _manhattan(point, anchor) < minimum:
				return false
	return true


static func _flood(start: Vector2i, floors: Dictionary, blocked: Dictionary) -> Dictionary:
	var seen: Dictionary = {}
	if not floors.has(start) or blocked.has(start):
		return seen
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	var cursor: int = 0
	while cursor < queue.size():
		var point: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in DIRECTIONS:
			var next: Vector2i = point + direction
			if floors.has(next) and not blocked.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen


static func _rng(seed: int, stage: String) -> RandomNumberGenerator:
	var result: RandomNumberGenerator = RandomNumberGenerator.new()
	result.seed = hash("%d:%d:%s" % [ALGORITHM_VERSION, seed, stage])
	return result


static func _weighted(entries: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total: float = 0.0
	for entry: Dictionary in entries:
		total += float(entry.weight)
	var roll: float = rng.randf() * total
	for entry: Dictionary in entries:
		roll -= float(entry.weight)
		if roll < 0.0:
			return entry
	return entries.back()


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[other]
		values[other] = value


static func _rotate(point: Vector2i, angle: int) -> Vector2i:
	match posmod(angle, 360):
		90: return Vector2i(-point.y, point.x)
		180: return -point
		270: return Vector2i(point.y, -point.x)
	return point


static func _vectors(cells: Array) -> Array:
	var result: Array = []
	for point: Variant in cells:
		result.append(Vector2i(int(point[0]), int(point[1])) if point is Array else C.vec(point))
	return result


static func _transform_cells(cells: Array, angle: int, offset: Vector2i) -> Array:
	var result: Array = []
	for point: Vector2i in _vectors(cells):
		result.append(_rotate(point, angle) + offset)
	return result


static func _cell_set(cells: Array) -> Dictionary:
	return _vector_cell_set(_vectors(cells))


static func _vector_cell_set(cells: Array) -> Dictionary:
	var result: Dictionary = {}
	for point: Vector2i in cells:
		result[point] = true
	return result


static func _json_cells(cells: Array) -> Array:
	var points: Array = cells.duplicate()
	points.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x if a.y == b.y else a.y < b.y)
	var result: Array = []
	for point: Vector2i in points:
		result.append(C.cell(point))
	return result


static func _minimum(points: Array) -> Vector2i:
	var result: Vector2i = points.front()
	for point: Vector2i in points:
		result = result.min(point)
	return result


static func _bounds(points: Array) -> Dictionary:
	var low: Vector2i = _minimum(points)
	var high: Vector2i = low
	for point: Vector2i in points:
		high = high.max(point)
	return {"x": low.x, "y": low.y, "width": high.x - low.x + 1, "height": high.y - low.y + 1}


static func _line(a: Vector2i, b: Vector2i) -> Array:
	var result: Array = [a]
	var step: Vector2i = Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	while a != b:
		a += step
		result.append(a)
	return result


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _failure(path: String, message: String, code: String) -> Dictionary:
	return {"valid": false, "plan": {}, "issues": [{"path": path, "message": message, "code": code}]}


static func _exhausted(context: Dictionary, budget: String, message: String) -> void:
	context.diagnostic.exhausted_budget = budget
	context.diagnostic.last_reason = message
