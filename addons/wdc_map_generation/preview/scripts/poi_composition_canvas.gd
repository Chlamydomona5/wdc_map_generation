extends Control

signal node_selected(node_id: String)
signal node_position_changed(node_id: String, position: Vector2)
signal view_changed(state: Dictionary)

var composition: Dictionary = {}
var positions: Dictionary = {}
var selected_node_id: String = ""
var _dragging_id: String = ""
var _drag_offset: Vector2 = Vector2.ZERO
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var _panning: bool = false
const NODE_SIZE: Vector2 = Vector2(170, 86)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(360, 300)
	resized.connect(queue_redraw)


func show_composition(source: Dictionary, graph_positions: Dictionary) -> void:
	composition = source.duplicate(true)
	positions = graph_positions.duplicate(true)
	for index: int in range(composition.get("nodes", []).size()):
		var node: Dictionary = composition["nodes"][index]
		var id: String = str(node.get("id", ""))
		if not positions.has(id):
			positions[id] = {"x": 28 + (index % 2) * 320, "y": 70 + (index / 2) * 190}
	queue_redraw()


func fit_content() -> void:
	var bounds: Rect2 = Rect2()
	for id: String in positions:
		var rectangle: Rect2 = Rect2(_position(id), NODE_SIZE)
		bounds = rectangle if not bounds.has_area() else bounds.merge(rectangle)
	if not bounds.has_area():
		return
	zoom = clampf(minf((size.x - 60.0) / bounds.size.x, (size.y - 100.0) / bounds.size.y), 0.3, 1.2)
	pan = (size - bounds.size * zoom) * 0.5 - bounds.position * zoom
	view_changed.emit({"zoom": zoom, "x": pan.x, "y": pan.y})
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var previous: float = zoom
			zoom = clampf(zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.3, 2.0)
			pan = event.position - (event.position - pan) * zoom / previous
			view_changed.emit({"zoom": zoom, "x": pan.x, "y": pan.y})
			queue_redraw()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_LEFT and (Input.is_key_pressed(KEY_SPACE) or _panning):
			_panning = event.pressed
			accept_event()
			return
	if event is InputEventMouseMotion and _panning:
		pan += event.relative
		view_changed.emit({"zoom": zoom, "x": pan.x, "y": pan.y})
		queue_redraw()
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			for node: Dictionary in composition.get("nodes", []):
				var id: String = str(node.get("id", ""))
				var position: Vector2 = _position(id)
				if Rect2(position, NODE_SIZE).has_point((event.position - pan) / zoom):
					_dragging_id = id
					_drag_offset = (event.position - pan) / zoom - position
					selected_node_id = id
					node_selected.emit(id)
					queue_redraw()
					accept_event()
					return
		else:
			if not _dragging_id.is_empty():
				node_position_changed.emit(_dragging_id, _position(_dragging_id))
			_dragging_id = ""
	elif event is InputEventMouseMotion and not _dragging_id.is_empty():
		var position: Vector2 = (event.position - pan) / zoom - _drag_offset
		positions[_dragging_id] = {"x": position.x, "y": position.y}
		queue_redraw()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111b24"))
	draw_set_transform(pan, 0.0, Vector2.ONE * zoom)
	for connection: Dictionary in composition.get("connections", []):
		var from_id: String = _endpoint_node(connection.get("from", connection.get("hub", connection.get("node_id", ""))))
		var to_id: String = _endpoint_node(connection.get("to", connection.get("group", connection.get("node_id", ""))))
		if not positions.has(from_id) or not positions.has(to_id):
			continue
		var from: Vector2 = _position(from_id) + NODE_SIZE * 0.5
		var to: Vector2 = _position(to_id) + NODE_SIZE * 0.5
		if from_id == to_id:
			draw_arc(from + Vector2(0, -45), 38, -PI, 0.0, 24, Color("69afc1"), 2)
		else:
			draw_line(from, to, Color("69afc1"), 2)
		var mode: String = str(connection.get("mode", "pair"))
		var caption: String = "%s · %s" % [str(connection.get("id", "")), {"pair": "一对一", "fan_out": "逐个接入", "chain": "顺序串联"}.get(mode, mode)]
		var label_width: float = ThemeDB.fallback_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(ThemeDB.fallback_font, (from + to) * 0.5 + Vector2(-label_width * 0.5, -8), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("d0e5ef"))
	for node: Dictionary in composition.get("nodes", []):
		var id: String = str(node.get("id", ""))
		var position: Vector2 = _position(id)
		draw_rect(Rect2(position, NODE_SIZE), Color("284c59") if id == selected_node_id else Color("243442"))
		draw_rect(Rect2(position, NODE_SIZE), Color("79d6dc") if id == selected_node_id else Color("526d7e"), false, 2)
		draw_string(ThemeDB.fallback_font, position + Vector2(10, 23), id, HORIZONTAL_ALIGNMENT_LEFT, NODE_SIZE.x - 20, 15, Color("e5f2f7"))
		draw_string(ThemeDB.fallback_font, position + Vector2(10, 47), "数量 %d–%d" % [int(node.get("min_count", 1)), int(node.get("max_count", 1))], HORIZONTAL_ALIGNMENT_LEFT, NODE_SIZE.x - 20, 13, Color("b9d1dd"))
		draw_string(ThemeDB.fallback_font, position + Vector2(10, 69), "候选 %d · %s" % [node.get("blueprints", []).size(), str(node.get("purpose", ""))], HORIZONTAL_ALIGNMENT_LEFT, NODE_SIZE.x - 20, 12, Color("99b4c2"))
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(0, 0, size.x, 40), Color("111b24"))
	draw_string(ThemeDB.fallback_font, Vector2(18, 26), "拖动调整排版 · 中键 / 空格平移 · 滚轮缩放；固定位置请在属性中设置", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b5c7d3"))


func _position(id: String) -> Vector2:
	var value: Variant = positions.get(id, {})
	if value is Vector2:
		return value
	return Vector2(float(value.get("x", 0)), float(value.get("y", 0)))


func _endpoint_node(value: Variant) -> String:
	if value is Dictionary:
		return str(value.get("node_id", value.get("node", "")))
	return str(value).split(":")[0]
