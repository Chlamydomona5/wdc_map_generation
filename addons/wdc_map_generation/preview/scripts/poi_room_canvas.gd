extends Control

signal gesture_started()
signal gesture_finished()
signal cells_edited(cells: Array, brush: String)
signal cell_selected(cell: Vector2i)
signal selection_changed(cells: Rect2i)
signal view_changed()
signal source_activated(blueprint_id: String, local_cell: Vector2i)

var brush: String = "floor"
var editable: bool = true
var display_plan: Dictionary = {}
var selected_id: String = ""
var selected_cell: Vector2i = Vector2i.ZERO
var selection_rect: Rect2i = Rect2i()
var zoom: float = 24.0
var pan: Vector2 = Vector2(80, 80)
var _painting: bool = false
var _panning: bool = false
var _rectangle_start: Vector2i = Vector2i.ZERO
var _last_cell: Vector2i = Vector2i.ZERO
var _hover_cell: Vector2i = Vector2i.ZERO
var _has_hover: bool = false
var _rectangle: bool = false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(360, 300)
	resized.connect(func() -> void:
		if editable:
			queue_redraw()
		else:
			fit_content())
	mouse_exited.connect(func() -> void: _has_hover = false; queue_redraw())


func show_plan(plan: Dictionary) -> void:
	display_plan = plan.duplicate(true)
	queue_redraw()


func fit_content() -> void:
	var cells: Array = display_plan.get("floor_cells", []).duplicate()
	cells.append_array(display_plan.get("wall_cells", []))
	if cells.is_empty():
		pan = Vector2(80, 80)
		zoom = 24.0
		queue_redraw()
		return
	var minimum: Vector2i = _cell(cells[0])
	var maximum: Vector2i = minimum
	for value: Variant in cells:
		minimum = minimum.min(_cell(value))
		maximum = maximum.max(_cell(value))
	var extent: Vector2 = Vector2(maximum - minimum + Vector2i(3, 3))
	zoom = clampf(minf(size.x / extent.x, size.y / extent.y), 4.0, 40.0)
	pan = (size - Vector2(maximum - minimum + Vector2i.ONE) * zoom) * 0.5 - Vector2(minimum) * zoom
	queue_redraw()
	view_changed.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and button.pressed:
			var previous: float = zoom
			zoom = clampf(zoom * (1.15 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 4.0, 80.0)
			pan = button.position - (button.position - pan) * zoom / previous
			queue_redraw()
			view_changed.emit()
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_MIDDLE or button.button_index == MOUSE_BUTTON_LEFT and (Input.is_key_pressed(KEY_SPACE) or _panning):
			_panning = button.pressed
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT and editable:
			grab_focus()
			if button.pressed:
				_painting = true
				_rectangle = button.shift_pressed or brush.begins_with("rectangle") or brush == "select"
				_rectangle_start = _to_cell(button.position)
				_last_cell = _rectangle_start
				selected_cell = _last_cell
				cell_selected.emit(selected_cell)
				gesture_started.emit()
				if not _rectangle:
					cells_edited.emit([_dictionary(_last_cell)], brush)
			elif _painting:
				_painting = false
				if _rectangle:
					var end: Vector2i = _to_cell(button.position)
					selection_rect = Rect2i(_rectangle_start.min(end), _rectangle_start.max(end) - _rectangle_start.min(end) + Vector2i.ONE)
					selection_changed.emit(selection_rect)
					if brush != "select":
						var cells: Array = []
						for y: int in range(selection_rect.position.y, selection_rect.end.y):
							for x: int in range(selection_rect.position.x, selection_rect.end.x):
								cells.append({"x": x, "y": y})
						cells_edited.emit(cells, brush.trim_prefix("rectangle_"))
				gesture_finished.emit()
			queue_redraw()
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT and not editable and button.pressed:
			var cell: Vector2i = _to_cell(button.position)
			selection_rect = Rect2i(cell, Vector2i.ONE)
			if button.double_click:
				var source: Dictionary = _source_at_cell(cell)
				if not source.is_empty():
					source_activated.emit(str(source.blueprint_id), source.local_cell)
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		_hover_cell = _to_cell(motion.position)
		_has_hover = true
		if _panning:
			pan += motion.relative
			view_changed.emit()
		elif _painting and not _rectangle and _hover_cell != _last_cell:
			var distance: int = maxi(absi(_hover_cell.x - _last_cell.x), absi(_hover_cell.y - _last_cell.y))
			var cells: Array = []
			for step: int in range(1, distance + 1):
				cells.append(_dictionary(Vector2i(Vector2(_last_cell).lerp(Vector2(_hover_cell), float(step) / distance).round())))
			cells_edited.emit(cells, brush)
			_last_cell = _hover_cell
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111b24"))
	var start: Vector2i = _to_cell(Vector2.ZERO)
	var finish: Vector2i = _to_cell(size) + Vector2i.ONE
	if zoom >= 10.0:
		for x: int in range(start.x, finish.x + 1):
			draw_line(Vector2(x * zoom + pan.x, 0), Vector2(x * zoom + pan.x, size.y), Color(0.18, 0.25, 0.31, 0.55))
		for y: int in range(start.y, finish.y + 1):
			draw_line(Vector2(0, y * zoom + pan.y), Vector2(size.x, y * zoom + pan.y), Color(0.18, 0.25, 0.31, 0.55))
	_draw_cells(display_plan.get("floor_cells", []), Color("334f54"))
	_draw_cells(display_plan.get("wall_cells", []), Color("8a9cab"))
	_draw_cells(display_plan.get("keep_clear", []), Color(0.25, 0.85, 0.95, 0.32))
	_draw_cells(display_plan.get("corridor_cells", []), Color("407d85"))
	for port: Dictionary in display_plan.get("ports", []):
		_draw_cells(port.get("cells", []), Color("e9b54a"))
		if not port.get("cells", []).is_empty():
			var point: Vector2 = _center(_cell(port["cells"][0]))
			var normal: Vector2 = Vector2(_cell(port.get("normal", {"x": 0, "y": -1})))
			_draw_arrow(point, point + normal * zoom * 1.1, Color("ffd77d"))
			if _should_label(_cell(port["cells"][0])):
				_draw_label(str(port.get("id", "")), point + Vector2(6, -7), Color("ffd77d"))
	var anchors: Variant = display_plan.get("anchors", {})
	if anchors is Dictionary:
		for id: String in anchors:
			var point: Vector2 = _center(_cell(anchors[id]))
			draw_circle(point, maxf(3.0, zoom * 0.20), Color("f8cb73"))
			if id == "primary" or _should_label(_cell(anchors[id])):
				_draw_label(id, point + Vector2(6, 14), Color("f8cb73"))
	for slot: Dictionary in display_plan.get("slots", []):
		_draw_cells(slot.get("footprint_cells", []), Color(0.78, 0.44, 0.52, 0.36))
		_draw_cells(slot.get("clearance_cells", []), Color(0.25, 0.85, 0.95, 0.22))
		var slot_cells: Array = slot.get("cells", slot.get("points", []))
		_draw_cells(slot_cells, Color(0.66, 0.41, 0.86, 0.50))
		for value: Variant in slot_cells:
			var point: Vector2 = _center(_cell(value))
			draw_rect(Rect2(point - Vector2.ONE * zoom * 0.32, Vector2.ONE * zoom * 0.64), Color("d6a1f0"), false, 1.5)
		if not slot_cells.is_empty() and _should_label(_cell(slot_cells[0])):
			_draw_label(str(slot.get("id", "")), _center(_cell(slot_cells[0])) + Vector2(6, -8), Color("ddaaff"))
	if selection_rect.has_area():
		draw_rect(Rect2(Vector2(selection_rect.position) * zoom + pan, Vector2(selection_rect.size) * zoom), Color("f4f7fc"), false, 2.0)
	if _painting and _rectangle:
		var low: Vector2i = _rectangle_start.min(_hover_cell)
		var high: Vector2i = _rectangle_start.max(_hover_cell) + Vector2i.ONE
		draw_rect(Rect2(Vector2(low) * zoom + pan, Vector2(high - low) * zoom), Color(0.7, 0.9, 1.0, 0.3))
	if _has_hover:
		draw_rect(Rect2(Vector2(_hover_cell) * zoom + pan, Vector2.ONE * zoom), Color("8cdce9"), false, 2)
		_draw_label("(%d, %d)" % [_hover_cell.x, _hover_cell.y], Vector2(10, size.y - 12), Color("d7e7ef"))
	_draw_label("左键编辑 · Shift 矩形 · 中键 / 空格平移 · 滚轮缩放" if editable else "只读结果 · 双击房间定位图纸 · 中键平移 · 滚轮缩放", Vector2(10, 20), Color("b6c8d4"))


func _source_at_cell(cell: Vector2i) -> Dictionary:
	for room: Dictionary in display_plan.get("rooms", []):
		var occupied: bool = false
		for point: Variant in room.get("floor_cells", []) + room.get("wall_cells", []):
			if _cell(point) == cell:
				occupied = true
				break
		if not occupied:
			continue
		var transform: Dictionary = room.get("transform", {})
		var local_cell: Vector2i = cell - _cell(transform.get("origin", {}))
		for turn: int in range(posmod(-int(transform.get("rotation", 0)), 360) / 90):
			local_cell = Vector2i(-local_cell.y, local_cell.x)
		return {"blueprint_id": str(room.get("blueprint_id", "")), "local_cell": local_cell}
	return {}


func _should_label(cell: Vector2i) -> bool:
	return editable or zoom >= 32.0 or _has_hover and _hover_cell.distance_to(cell) <= 1.0


func _draw_cells(cells: Array, color: Color) -> void:
	for value: Variant in cells:
		var position: Vector2 = Vector2(_cell(value)) * zoom + pan
		draw_rect(Rect2(position + Vector2.ONE, Vector2.ONE * maxf(1.0, zoom - 1.0)), color)


func _draw_label(text: String, position: Vector2, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)


func _draw_arrow(start: Vector2, end: Vector2, color: Color) -> void:
	draw_line(start, end, color, 2)
	var direction: Vector2 = (end - start).normalized()
	draw_line(end, end - direction.rotated(0.5) * 7, color, 2)
	draw_line(end, end - direction.rotated(-0.5) * 7, color, 2)


func _to_cell(position: Vector2) -> Vector2i:
	return Vector2i(((position - pan) / zoom).floor())


func _center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2.ONE * 0.5) * zoom + pan


func _cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO


func _dictionary(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}
