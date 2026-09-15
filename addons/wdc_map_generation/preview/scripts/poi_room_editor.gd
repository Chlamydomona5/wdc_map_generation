extends VBoxContainer

## 正式工具入口使用 canonical 编译器与组合生成器，编辑器只负责文档和交互。
signal full_map_generated(map_data: RefCounted, seed: int, source: Dictionary, dependency_hash: String)
signal full_map_invalidated()
signal show_full_map_requested()

const DOCUMENT = preload("poi_editor_document.gd")
const FILE_STORE = preload("poi_editor_file_store.gd")
const ROOM_CANVAS = preload("poi_room_canvas.gd")
const COMPOSITION_CANVAS = preload("poi_composition_canvas.gd")
const COMPILER = preload("../../core/poi_blueprint_compiler.gd")
const RESOURCE_CATALOG = preload("../../config/poi_resource_catalog.gd")
const ASSEMBLER = preload("../../core/poi_composition_generator.gd")
const CONFIG_CATALOG = preload("../../config/data_generated_map_config_catalog.gd")
const MAP_GENERATOR = preload("../../core/generated_map_generator.gd")
const POPULATION_CONTRACT = preload("../../core/poi_population_contract.gd")
const GAME_LAUNCHER = preload("poi_test_game_launcher.gd")

const LABELS: Dictionary = {
	"display_name": "中文名称", "purpose": "用途", "id": "稳定 ID", "schema_version": "格式版本",
	"rotations": "允许旋转", "rotation": "朝向", "anchors": "具名锚点", "ports": "连接口", "slots": "内容槽",
	"normal": "外法向", "kind": "种类", "group": "接口组", "unused": "未连接处理", "cells": "开口格",
	"points": "固定 / 有限候选点", "region": "绘制候选区", "entries": "内容候选池", "weight": "权重",
	"min_count": "最少数量", "max_count": "最多数量", "required": "必需", "exclusive_group": "互斥组",
	"footprint": "相对占地", "clearance": "相对交互净空", "constraints": "选点条件", "near_wall": "靠墙",
	"min_distance_from_ports_cells": "距门最少格数", "face_port": "朝向连接口", "group_members": "成组成员",
	"offset": "相对位置", "guard_points": "守卫相对点", "nodes": "房间节点", "blueprints": "图纸候选池",
	"max_instances": "单图纸上限（0 不限）", "position": "固定空间偏移", "primary": "核心锚点",
	"node": "节点", "anchor": "锚点", "connections": "连接规则", "mode": "展开规则", "from": "起点",
	"to": "终点", "port": "指定连接口", "instance": "重复组端点", "probability": "概率", "style": "连接样式",
	"max_length_cells": "最大通道长度", "reward_recipe_id": "BOSS 奖励配方", "x": "X", "y": "Y",
	"width_cells": "通道宽度（格）", "directions": "允许朝外方向", "keep_clear": "通路净空",
}
const KIND_LABELS: Dictionary = {"prop": "道具", "torch": "火把", "monster_pack": "怪物点", "nest": "巢穴", "camp": "营地", "mineral": "矿物", "trap": "陷阱"}

var model = DOCUMENT.new()
var store = FILE_STORE.new()
var game_launcher = GAME_LAUNCHER
var _tabs: TabContainer
var _status: Label
var _issues: ItemList
var _issue_values: Array = []
var _room_selector: OptionButton
var _composition_selector: OptionButton
var _map_selector: OptionButton
var _room_tree: Tree
var _composition_tree: Tree
var _room_properties: VBoxContainer
var _composition_properties: VBoxContainer
var _room_json: TextEdit
var _composition_json: TextEdit
var _room_canvas: Control
var _composition_canvas: Control
var _result_canvas: Control
var _result_list: ItemList
var _validation_label: Label
var _population_label: Label
var _seed_input: SpinBox
var _seed_count: SpinBox
var _template_selector: OptionButton
var _capabilities: Dictionary = {}
var _room_key: String = ""
var _composition_key: String = ""
var _map_key: String = ""
var _result_map_key: String = ""
var _poi_test_key: String = ""
var _room_path: Array = []
var _composition_path: Array = []
var _refreshing: bool = false
var _draft_timer: Timer
var _preview_revision: int = -1
var _results: Array[Dictionary] = []
var _validating: bool = false
var _cancel_validation: bool = false
var _name_dialog: ConfirmationDialog
var _name_input: LineEdit
var _create_kind: String = "room"
var _create_copy: bool = false
var _delete_dialog: ConfirmationDialog
var _delete_key: String = ""


func _ready() -> void:
	name = "POI 房间配置器"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 7)
	store.configure(str(RESOURCE_CATALOG.get_resource_directories().rooms).get_base_dir())
	_build_ui()
	model.changed.connect(_on_document_changed)
	_draft_timer = Timer.new()
	_draft_timer.one_shot = true
	_draft_timer.wait_time = 1.0
	_draft_timer.timeout.connect(_save_recovery_draft)
	add_child(_draft_timer)
	_load_project()


func _build_ui() -> void:
	var toolbar: HBoxContainer = HBoxContainer.new()
	add_child(toolbar)
	_button(toolbar, "撤销", _undo)
	_button(toolbar, "重做", _redo)
	_button(toolbar, "保存草稿", _save_draft)
	_button(toolbar, "恢复草稿", _restore_draft)
	_button(toolbar, "校验并保存到项目", _save_project)
	_button(toolbar, "重新载入项目", _request_reload)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toolbar.add_child(_status)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	_build_room_page()
	_build_composition_page()
	_build_validation_page()
	_issues = ItemList.new()
	_issues.custom_minimum_size.y = 105
	_issues.item_selected.connect(_locate_issue)
	add_child(_issues)
	_name_dialog = ConfirmationDialog.new()
	_name_dialog.title = "创建资源：稳定 ID 只允许字母、数字、下划线和连字符"
	_name_dialog.min_size = Vector2i(570, 130)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "例如 miner_home_variant"
	_name_dialog.add_child(_name_input)
	_name_dialog.confirmed.connect(_confirm_create)
	add_child(_name_dialog)
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "删除资源"
	_delete_dialog.confirmed.connect(func() -> void: model.remove_document(_delete_key); _refresh_all())
	add_child(_delete_dialog)


func _build_room_page() -> void:
	var split: HSplitContainer = HSplitContainer.new()
	split.name = "房间布局"
	_tabs.add_child(split)
	var library: VBoxContainer = _library_column(split)
	_label(library, "房间图纸库")
	_room_selector = OptionButton.new()
	_room_selector.item_selected.connect(func(index: int) -> void: _room_key = str(_room_selector.get_item_metadata(index)); _room_path = []; _refresh_room(); _room_canvas.fit_content())
	library.add_child(_room_selector)
	var actions: HBoxContainer = HBoxContainer.new()
	library.add_child(actions)
	_button(actions, "新建", func() -> void: _show_create("room", false))
	_button(actions, "复制变体", func() -> void: _show_create("room", true))
	_button(actions, "删除", func() -> void: _request_delete(_room_key))
	_room_tree = Tree.new()
	_room_tree.hide_root = true
	_room_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_tree.item_selected.connect(_on_room_tree_selected)
	library.add_child(_room_tree)
	_button(library, "添加连接口", func() -> void: _add_room_member("ports"))
	_button(library, "添加内容槽", func() -> void: _add_room_member("slots"))
	_button(library, "添加具名锚点", func() -> void: _add_room_member("anchors"))
	_button(library, "删除所选项", _remove_room_member)
	var editing: HSplitContainer = HSplitContainer.new()
	editing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(editing)
	var work: VBoxContainer = VBoxContainer.new()
	work.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editing.add_child(work)
	var paint: HFlowContainer = HFlowContainer.new()
	work.add_child(paint)
	for entry: Array in [["选择", "select"], ["地板", "floor"], ["墙 / 柱", "wall"], ["未写入", "erase"], ["净空", "clearance"], ["清除净空", "clear_clearance"], ["连接口", "port"], ["槽候选点", "slot"], ["槽区域", "slot_region"], ["锚点", "anchor"]]:
		var brush_id: String = str(entry[1])
		_button(paint, str(entry[0]), func() -> void: _room_canvas.brush = brush_id; _set_status("当前工具：%s；Shift 拖动绘制矩形" % str(entry[0])))
	var edit_actions: HFlowContainer = HFlowContainer.new()
	work.add_child(edit_actions)
	_button(edit_actions, "包边墙", _add_border_walls)
	_button(edit_actions, "整图旋转 90°", _rotate_room)
	_button(edit_actions, "复制选区到右侧", func() -> void: _move_selection(Vector2i(maxi(_room_canvas.selection_rect.size.x, 1) + 1, 0), true))
	for entry: Array in [["←", Vector2i(-1, 0)], ["→", Vector2i(1, 0)], ["↑", Vector2i(0, -1)], ["↓", Vector2i(0, 1)]]:
		var delta: Vector2i = entry[1]
		_button(edit_actions, str(entry[0]), func() -> void: _move_selection(delta, false))
	_button(edit_actions, "适应画布", func() -> void: _room_canvas.fit_content())
	_room_canvas = ROOM_CANVAS.new()
	_room_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_canvas.gesture_started.connect(model.begin_gesture)
	_room_canvas.gesture_finished.connect(func() -> void: model.end_gesture(); _refresh_property_panels())
	_room_canvas.cells_edited.connect(_paint_cells)
	_room_canvas.cell_selected.connect(func(cell: Vector2i) -> void: model.selection["cell"] = {"x": cell.x, "y": cell.y})
	_room_canvas.view_changed.connect(_save_canvas_state)
	work.add_child(_room_canvas)
	var property_tabs: TabContainer = _property_tabs(editing)
	_room_properties = _property_container(property_tabs)
	_room_json = _json_page(property_tabs, "room")


func _build_composition_page() -> void:
	var split: HSplitContainer = HSplitContainer.new()
	split.name = "POI 组装"
	_tabs.add_child(split)
	var library: VBoxContainer = _library_column(split)
	_label(library, "POI 组合库")
	_composition_selector = OptionButton.new()
	_composition_selector.item_selected.connect(func(index: int) -> void: _composition_key = str(_composition_selector.get_item_metadata(index)); _composition_path = []; _refresh_composition())
	library.add_child(_composition_selector)
	var actions: HBoxContainer = HBoxContainer.new()
	library.add_child(actions)
	_button(actions, "新建", func() -> void: _show_create("composition", false))
	_button(actions, "复制", func() -> void: _show_create("composition", true))
	_button(actions, "删除", func() -> void: _request_delete(_composition_key))
	_composition_tree = Tree.new()
	_composition_tree.hide_root = true
	_composition_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_composition_tree.item_selected.connect(_on_composition_tree_selected)
	library.add_child(_composition_tree)
	_button(library, "添加房间节点", func() -> void: _add_composition_member("nodes"))
	_button(library, "添加连接规则", func() -> void: _add_composition_member("connections"))
	_button(library, "删除所选项", _remove_composition_member)
	_button(library, "适应组装图", func() -> void: _composition_canvas.fit_content())
	var editing: HSplitContainer = HSplitContainer.new()
	editing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(editing)
	_composition_canvas = COMPOSITION_CANVAS.new()
	_composition_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_composition_canvas.node_selected.connect(_select_graph_node)
	_composition_canvas.node_position_changed.connect(func(id: String, position: Vector2) -> void:
		var positions: Dictionary = model.view_state.get(_composition_key, {})
		positions[id] = {"x": position.x, "y": position.y}
		model.view_state[_composition_key] = positions
		_draft_timer.start()
	)
	_composition_canvas.view_changed.connect(func(state: Dictionary) -> void:
		model.view_state["graph/" + _composition_key] = state
		_draft_timer.start()
	)
	editing.add_child(_composition_canvas)
	var property_tabs: TabContainer = _property_tabs(editing)
	_composition_properties = _property_container(property_tabs)
	_composition_json = _json_page(property_tabs, "composition")


func _build_validation_page() -> void:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "生成验证"
	_tabs.add_child(page)
	var toolbar: HFlowContainer = HFlowContainer.new()
	page.add_child(toolbar)
	_button(toolbar, "单房校验", _validate_room)
	_button(toolbar, "单 POI 多种子", _validate_composition)
	_label(toolbar, "起始 seed")
	_seed_input = _spin(1, 2147483647, 1)
	_seed_input.value = 1
	toolbar.add_child(_seed_input)
	_label(toolbar, "数量")
	_seed_count = _spin(1, 64, 1)
	_seed_count.value = 8
	toolbar.add_child(_seed_count)
	_button(toolbar, "取消验证", func() -> void: _cancel_validation = true)
	var binding: HFlowContainer = HFlowContainer.new()
	page.add_child(binding)
	_label(binding, "地图配置")
	_map_selector = OptionButton.new()
	_map_selector.custom_minimum_size.x = 220
	_map_selector.item_selected.connect(func(index: int) -> void: _map_key = str(_map_selector.get_item_metadata(index)); _refresh_map_templates())
	binding.add_child(_map_selector)
	_template_selector = OptionButton.new()
	_template_selector.custom_minimum_size.x = 200
	binding.add_child(_template_selector)
	_button(binding, "绑定当前组合到 POI 条目", _bind_composition)
	_button(binding, "完整地图验证", _validate_full_map)
	_button(binding, "查看完整地图结果", func() -> void: show_full_map_requested.emit())
	var testing: HFlowContainer = HFlowContainer.new()
	page.add_child(testing)
	_button(testing, "生成 POI Only 测试地图", _generate_poi_only_map)
	_button(testing, "保存并启动正式测试", _save_and_launch_poi_only)
	_label(testing, "沿用上方源地图与 POI 条目预算，只生成当前组合及出生 / 撤离。")
	_validation_label = _label(page, "单房 / 单 POI 只验证局部结构。完整地图另行验证区域占地、预算与实际人口限制。")
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_population_label = _label(page, "")
	_population_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(split)
	_result_list = ItemList.new()
	_result_list.custom_minimum_size.x = 230
	_result_list.item_selected.connect(_select_result)
	split.add_child(_result_list)
	_result_canvas = ROOM_CANVAS.new()
	_result_canvas.editable = false
	_result_canvas.source_activated.connect(_jump_to_source_room)
	_result_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_result_canvas)


func _load_project() -> void:
	var recovery: Dictionary = store.recover_transaction()
	if not bool(recovery.get("ok", false)):
		_set_issues(recovery.get("issues", []))
		return
	var loaded: Dictionary = store.load_project()
	model.load_documents(loaded.documents, loaded.hashes)
	var bundle: Dictionary = RESOURCE_CATALOG.load_bundle()
	_capabilities = bundle.get("capabilities", {}).duplicate(true)
	_room_key = "room/miner_house_a" if model.documents.has("room/miner_house_a") else ""
	_composition_key = "composition/miners_settlement" if model.documents.has("composition/miners_settlement") else ""
	_map_key = "map/ancient_old_mine" if model.documents.has("map/ancient_old_mine") else ""
	var tool_state: Dictionary = store.load_tool_state()
	model.selection = tool_state.get("selection", {}).duplicate(true)
	model.view_state = tool_state.get("view_state", {}).duplicate(true)
	_room_key = str(model.selection.get("room", _room_key))
	_composition_key = str(model.selection.get("composition", _composition_key))
	_room_path = model.selection.get("room_path", []).duplicate()
	_composition_path = model.selection.get("composition_path", []).duplicate()
	_refresh_all()
	_set_issues(loaded.get("issues", []))
	_set_status("已载入项目内容%s%s" % ["；已恢复中断的保存" if bool(recovery.get("recovered", false)) else "", "；检测到恢复草稿，可点击“恢复草稿”" if not store.load_draft().is_empty() else ""])
	if not model.view_state.has("canvas/" + _room_key):
		_room_canvas.call_deferred("fit_content")


func _request_reload() -> void:
	if model.is_dirty() and not _save_draft():
		return
	_load_project()


func _refresh_all() -> void:
	_refreshing = true
	_room_key = _fill_selector(_room_selector, "room", _room_key)
	_composition_key = _fill_selector(_composition_selector, "composition", _composition_key)
	_map_key = _fill_selector(_map_selector, "map", _map_key)
	_refreshing = false
	_refresh_room()
	_refresh_composition()
	_refresh_map_templates()


func _fill_selector(selector: OptionButton, kind: String, selected: String) -> String:
	selector.clear()
	var keys: Array[String] = model.list_keys(kind)
	if not keys.has(selected):
		selected = keys[0] if not keys.is_empty() else ""
	for key: String in keys:
		var source: Dictionary = model.get_document(key)
		selector.add_item("%s%s" % [str(source.get("display_name", source.get("meta", {}).get("display_name", key.get_file()))), " *" if model.is_dirty(key) else ""])
		var index: int = selector.item_count - 1
		selector.set_item_metadata(index, key)
		if key == selected:
			selector.select(index)
	return selected


func _refresh_room() -> void:
	_refreshing = true
	var source: Dictionary = model.get_document(_room_key)
	_room_tree.clear()
	var root: TreeItem = _room_tree.create_item()
	_select_tree_item(_tree_item(_room_tree, root, "房间属性", []), [], _room_path)
	for field: String in ["anchors", "ports", "slots"]:
		var group: TreeItem = _tree_item(_room_tree, root, str(LABELS[field]), [])
		if field == "anchors":
			for id: String in source.get(field, {}):
				_select_tree_item(_tree_item(_room_tree, group, id, [field, id]), [field, id], _room_path)
		else:
			for index: int in range(source.get(field, []).size()):
				_select_tree_item(_tree_item(_room_tree, group, str(source[field][index].get("id", "?")), [field, index]), [field, index], _room_path)
	_refreshing = false
	_room_canvas.show_plan(_room_display(source))
	_room_json.text = JSON.stringify(source, "  ")
	_build_room_properties()
	model.selection["room"] = _room_key
	model.selection["room_path"] = _room_path.duplicate()
	var canvas_state: Dictionary = model.view_state.get("canvas/" + _room_key, {})
	if not canvas_state.is_empty():
		_room_canvas.zoom = float(canvas_state.get("zoom", 24.0))
		_room_canvas.pan = Vector2(float(canvas_state.get("x", 80)), float(canvas_state.get("y", 80)))
	if _draft_timer != null:
		_draft_timer.start()


func _refresh_composition() -> void:
	_refreshing = true
	var source: Dictionary = model.get_document(_composition_key)
	_composition_tree.clear()
	var root: TreeItem = _composition_tree.create_item()
	_select_tree_item(_tree_item(_composition_tree, root, "组合属性与核心锚点", []), [], _composition_path)
	for field: String in ["nodes", "connections"]:
		var group: TreeItem = _tree_item(_composition_tree, root, str(LABELS[field]), [])
		for index: int in range(source.get(field, []).size()):
			_select_tree_item(_tree_item(_composition_tree, group, str(source[field][index].get("id", "?")), [field, index]), [field, index], _composition_path)
	_refreshing = false
	_composition_canvas.show_composition(source, model.view_state.get(_composition_key, {}))
	var graph_state: Dictionary = model.view_state.get("graph/" + _composition_key, {})
	_composition_canvas.zoom = float(graph_state.get("zoom", 1.0))
	_composition_canvas.pan = Vector2(float(graph_state.get("x", 0)), float(graph_state.get("y", 0)))
	_composition_json.text = JSON.stringify(source, "  ")
	_build_composition_properties()
	model.selection["composition"] = _composition_key
	model.selection["composition_path"] = _composition_path.duplicate()
	if _draft_timer != null:
		_draft_timer.start()


func _on_room_tree_selected() -> void:
	if _refreshing or _room_tree.get_selected() == null:
		return
	_room_path = _room_tree.get_selected().get_metadata(0)
	model.selection["room_path"] = _room_path.duplicate()
	_draft_timer.start()
	_build_room_properties()
	if not _room_path.is_empty():
		_room_canvas.brush = {"anchors": "anchor", "ports": "port", "slots": "slot"}.get(str(_room_path[0]), "select")


func _on_composition_tree_selected() -> void:
	if _refreshing or _composition_tree.get_selected() == null:
		return
	_composition_path = _composition_tree.get_selected().get_metadata(0)
	model.selection["composition_path"] = _composition_path.duplicate()
	_draft_timer.start()
	_build_composition_properties()


func _select_graph_node(id: String) -> void:
	var nodes: Array = model.get_document(_composition_key).get("nodes", [])
	for index: int in range(nodes.size()):
		if str(nodes[index].get("id", "")) == id:
			_composition_path = ["nodes", index]
			_refresh_composition()
			return


func _build_room_properties() -> void:
	_clear_children(_room_properties)
	var source: Dictionary = _source_for_properties(_room_key)
	var selected: Variant = _read_path(source, _room_path)
	if selected == null:
		_room_path = []
		selected = source
	if _room_path.is_empty():
		_label(_room_properties, "地形由画布编辑；空格保持原地形。")
		for field: String in ["id", "schema_version", "display_name", "purpose", "rotations"]:
			_build_field(_room_properties, source.get(field, _default_value(field)), [field], _room_key)
		return
	_label(_room_properties, "选择的来源：%s" % _path_text(_room_path))
	if _room_path[0] == "anchors":
		_label(_room_properties, "锚点：%s（在画布点击可移动）" % str(_room_path[1]))
		var rename: LineEdit = LineEdit.new()
		rename.text = str(_room_path[1])
		rename.placeholder_text = "输入稳定名称后按回车"
		rename.text_submitted.connect(_rename_anchor)
		_room_properties.add_child(rename)
	_build_field(_room_properties, selected, _room_path, _room_key)
	if _room_path[0] == "slots":
		_button(_room_properties, "使用所选内容的真实占地 / 净空", _apply_capability_footprint)
		if selected.get("kind", "") == "camp":
			_button(_room_properties, "添加守卫相对点", func() -> void: _add_array_field(_room_key, _room_path + ["guard_points"], {"x": 1, "y": 0}))


func _build_composition_properties() -> void:
	_clear_children(_composition_properties)
	var source: Dictionary = _source_for_properties(_composition_key)
	var selected: Variant = _read_path(source, _composition_path)
	if selected == null:
		_composition_path = []
		selected = source
	if _composition_path.is_empty():
		for field: String in ["id", "schema_version", "display_name", "primary"]:
			_build_field(_composition_properties, source.get(field, _default_value(field)), [field], _composition_key)
		if source.has("reward_recipe_id"):
			_build_field(_composition_properties, source.reward_recipe_id, ["reward_recipe_id"], _composition_key)
		return
	_label(_composition_properties, "选择的来源：%s" % _path_text(_composition_path))
	_build_field(_composition_properties, selected, _composition_path, _composition_key)
	if _composition_path[0] == "nodes":
		var pinned: CheckBox = CheckBox.new()
		pinned.text = "固定空间位置（相对核心锚点）"
		pinned.button_pressed = selected.has("position")
		pinned.toggled.connect(func(enabled: bool) -> void:
			var document: Dictionary = model.get_document(_composition_key)
			var node: Dictionary = _read_path(document, _composition_path)
			if enabled:
				node["position"] = {"x": 0, "y": 0}
				node["rotation"] = 0
			else:
				node.erase("position")
				node.erase("rotation")
			model.replace_document(_composition_key, document)
			_build_composition_properties()
		)
		_composition_properties.add_child(pinned)
	if _composition_path[0] == "connections":
		var width_toggle: CheckBox = CheckBox.new()
		width_toggle.text = "显式限制通道宽度（否则按接口宽度匹配）"
		width_toggle.button_pressed = selected.has("width_cells")
		width_toggle.toggled.connect(func(enabled: bool) -> void: _toggle_connection_width(enabled))
		_composition_properties.add_child(width_toggle)
		if not selected.has("directions"):
			_button(_composition_properties, "添加允许朝外方向", func() -> void: _add_array_field(_composition_key, _composition_path + ["directions"], {"x": 0, "y": -1}))
		for side: String in ["from", "to"]:
			var endpoint_path: Array = _composition_path + [side]
			_button(_composition_properties, "%s：切换指定门 / 接口组" % LABELS[side], func() -> void: _toggle_endpoint_group(endpoint_path))
			if selected.get("mode", "pair") == "pair":
				_button(_composition_properties, "%s：切换自动 / 首 / 尾端点" % LABELS[side], func() -> void: _toggle_endpoint_instance(endpoint_path))


func _build_field(parent: VBoxContainer, value: Variant, path: Array, key: String) -> void:
	var field: String = str(path.back()) if not path.is_empty() else ""
	if value is Dictionary:
		var group: VBoxContainer = VBoxContainer.new()
		group.add_theme_constant_override("separation", 5)
		parent.add_child(group)
		_label(group, str(LABELS.get(field, field)))
		for child: String in value:
			if child == "guard_points" and value.get("kind", "") != "camp" and value[child].is_empty():
				continue
			_build_field(group, value[child], path + [child], key)
		return
	if value is Array:
		var header: HBoxContainer = HBoxContainer.new()
		parent.add_child(header)
		_label(header, "%s（%d）" % [str(LABELS.get(field, field)), value.size()])
		_button(header, "+", func() -> void: _add_array_field(key, path, _new_array_entry(field, key, path)))
		if value.size() > 24 and field in ["region", "points", "cells", "footprint", "clearance", "guard_points"]:
			_label(parent, "在画布编辑此区域；高级 JSON 可检查全部坐标。")
			_button(parent, "清空该区域", func() -> void: _change_field(key, path, []); _refresh_property_panels())
			return
		for index: int in range(value.size()):
			var row: HBoxContainer = HBoxContainer.new()
			parent.add_child(row)
			var content: VBoxContainer = VBoxContainer.new()
			content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(content)
			_build_field(content, value[index], path + [index], key)
			_button(row, "−", func() -> void: _remove_array_entry(key, path, index))
		return
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	var label: Label = _label(row, str(LABELS.get(field, field)))
	label.custom_minimum_size.x = 95
	label.tooltip_text = _path_text(path)
	if path.size() == 1 and field in ["id", "schema_version"]:
		_label(row, str(value))
		return
	if value is bool:
		var checkbox: CheckBox = CheckBox.new()
		checkbox.button_pressed = value
		checkbox.toggled.connect(func(next: bool) -> void: _change_field(key, path, next))
		row.add_child(checkbox)
		return
	var options: Array = _field_options(key, path)
	if not options.is_empty():
		var selector: OptionButton = OptionButton.new()
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var found: bool = false
		for option: Variant in options:
			var option_value: Variant = option.get("value", "") if option is Dictionary else option
			selector.add_item(str(option.get("label", option_value)) if option is Dictionary else str(option))
			selector.set_item_metadata(selector.item_count - 1, option_value)
			if str(option_value) == str(value):
				selector.select(selector.item_count - 1)
				found = true
			if option is Dictionary and not bool(option.get("available", true)):
				selector.set_item_disabled(selector.item_count - 1, true)
		if not found:
			selector.add_item("%s（当前值不在候选库）" % str(value))
			selector.set_item_metadata(selector.item_count - 1, value)
			selector.select(selector.item_count - 1)
		selector.item_selected.connect(func(index: int) -> void: _change_field(key, path, selector.get_item_metadata(index)))
		row.add_child(selector)
	elif value is int or value is float:
		var number: SpinBox = _spin(-128, 4096, 0.1 if field in ["weight", "probability"] else 1)
		number.value = float(value)
		number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		number.value_changed.connect(func(next: float) -> void: _change_field(key, path, next if field in ["weight", "probability"] else int(next)))
		row.add_child(number)
	else:
		var input: LineEdit = LineEdit.new()
		input.text = str(value)
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.text_submitted.connect(func(next: String) -> void: _change_field(key, path, next))
		input.focus_exited.connect(func() -> void: if is_instance_valid(input): _change_field(key, path, input.text))
		row.add_child(input)


func _field_options(key: String, path: Array) -> Array:
	var field: String = str(path.back())
	if field == "rotation" or path.has("rotations"):
		return [0, 90, 180, 270]
	if field == "unused":
		return [{"value": "wall", "label": "封墙"}, {"value": "open", "label": "保留外部入口"}]
	if field == "mode":
		return [{"value": "pair", "label": "一对一"}, {"value": "fan_out", "label": "逐个接入"}, {"value": "chain", "label": "顺序串联"}]
	if field == "style":
		return [{"value": "direct", "label": "直接对接"}, {"value": "corridor", "label": "走廊（含侧墙）"}]
	if field == "instance":
		return ["first", "last"]
	if field == "kind" and path.has("slots"):
		var choices: Array = []
		for id: String in KIND_LABELS:
			choices.append({"value": id, "label": KIND_LABELS[id]})
		return choices
	if field == "id" and path.has("blueprints"):
		var choices: Array = []
		for room_key: String in model.list_keys("room"):
			choices.append({"value": room_key.get_file(), "label": "%s · %s" % [model.get_document(room_key).get("display_name", room_key.get_file()), room_key.get_file()]})
		return choices
	if field == "node":
		var choices: Array = []
		for node: Dictionary in model.get_document(key).get("nodes", []):
			choices.append(str(node.get("id", "")))
		return choices
	if field in ["port", "group", "anchor"] and key.begins_with("composition/"):
		var owner: Variant = _read_path(model.get_document(key), path.slice(0, path.size() - 1))
		if owner is Dictionary and owner.has("node"):
			return _node_member_options(key, str(owner.node), field)
	if field == "face_port":
		var choices: Array = [""]
		for port: Dictionary in model.get_document(key).get("ports", []):
			choices.append(str(port.get("id", "")))
		return choices
	if field == "id" and (path.has("entries") or path.has("group_members")):
		var owner_path: Array = path.slice(0, path.find("entries") if path.has("entries") else path.size() - 1)
		var owner: Variant = _read_path(model.get_document(key), owner_path)
		var kind: String = str(owner.get("kind", "")) if owner is Dictionary else ""
		var choices: Array = []
		for entry: Dictionary in _capabilities.get("entries", []):
			if str(entry.get("kind", "")) == kind:
				choices.append({"value": entry.get("id", ""), "label": "%s%s" % [entry.get("display_name", entry.get("id", "")), "（不可用）" if not bool(entry.get("available", false)) else ""], "available": bool(entry.get("available", false))})
		return choices
	return []


func _node_member_options(key: String, node_id: String, field: String) -> Array:
	var choices: Array = []
	for node: Dictionary in model.get_document(key).get("nodes", []):
		if str(node.get("id", "")) != node_id:
			continue
		for entry: Dictionary in node.get("blueprints", []):
			var room: Dictionary = model.get_document("room/" + str(entry.get("id", "")))
			var values: Array = room.get("anchors", {}).keys() if field == "anchor" else room.get("ports", []).map(func(port: Dictionary) -> String: return str(port.get("id" if field == "port" else "group", "")))
			for value: Variant in values:
				if not str(value).is_empty() and not choices.has(value):
					choices.append(value)
	choices.sort()
	return choices


func _change_field(key: String, path: Array, value: Variant) -> void:
	if _refreshing:
		return
	var source: Dictionary = model.get_document(key)
	if _read_path(source, path) == value:
		return
	var before: Variant = _read_path(source, path)
	if not _write_path(source, path, value):
		return
	if path.back() == "mode" and value != "pair":
		var connection: Dictionary = _read_path(source, path.slice(0, path.size() - 1))
		for side: String in ["from", "to"]:
			connection.get(side, {}).erase("instance")
	if path.back() == "kind" and path.has("slots"):
		var owner: Dictionary = _read_path(source, path.slice(0, path.size() - 1))
		if path.has("group_members"):
			owner["id"] = _default_content_id(str(value))
		else:
			owner["entries"] = [{"id": _default_content_id(str(value)), "weight": 1.0}]
			if value != "camp":
				owner.erase("guard_points")
	if path.back() == "id" and before != null:
		var references: Array = model.find_references(key.get_slice("/", 0), key.get_file(), str(before))
		if not references.is_empty():
			_set_issues(references.map(func(reference: Dictionary) -> Dictionary: return {"document": reference.document, "path": reference.path, "message": "已修改 ID，请修复此引用后保存项目"}))
	model.replace_document(key, source)
	if path.back() in ["kind", "mode", "node", "id"]:
		_refresh_property_panels.call_deferred()


func _read_path(source: Variant, path: Array) -> Variant:
	var value: Variant = source
	for part: Variant in path:
		if value is Dictionary and value.has(part):
			value = value[part]
		elif value is Array and part is int and part >= 0 and part < value.size():
			value = value[part]
		else:
			return null
	return value


func _write_path(source: Dictionary, path: Array, value: Variant) -> bool:
	if path.is_empty():
		return false
	var parent: Variant = source
	for index: int in range(path.size() - 1):
		var part: Variant = path[index]
		if parent is Dictionary:
			if not parent.has(part):
				parent[part] = [] if path[index + 1] is int else {}
			parent = parent[part]
		elif parent is Array and part is int and part >= 0 and part < parent.size():
			parent = parent[part]
		else:
			return false
	if not parent is Dictionary and not parent is Array:
		return false
	parent[path.back()] = value
	return true


func _source_for_properties(key: String) -> Dictionary:
	var source: Dictionary = model.get_document(key)
	if key.begins_with("room/") and not source.is_empty():
		var compiled: Dictionary = COMPILER.compile_bundle({key.get_file(): source}, {})
		return compiled.get("rooms", {}).get(key.get_file(), source)
	if key.begins_with("composition/") and not source.is_empty():
		var rooms: Dictionary = {}
		for room_key: String in model.list_keys("room"):
			rooms[room_key.get_file()] = model.get_document(room_key)
		var compiled: Dictionary = COMPILER.compile_bundle(rooms, {key.get_file(): source})
		return compiled.get("compositions", {}).get(key.get_file(), source)
	return source


func _on_document_changed(_revision: int) -> void:
	if _room_canvas == null:
		return
	_room_canvas.show_plan(_room_display(model.get_document(_room_key)))
	_composition_canvas.show_composition(model.get_document(_composition_key), model.view_state.get(_composition_key, {}))
	_set_status("草稿未保存 · %d 份文件有改动" % model.get_changed_keys().size() if model.is_dirty() else "已保存内容")
	if _preview_revision >= 0 and _preview_revision != model.revision:
		_validation_label.text = "结果已过期：文档已修改，请重新验证。单房 / 单 POI 通过不代表完整地图通过。"
		_result_canvas.modulate.a = 0.4
	full_map_invalidated.emit()
	if _draft_timer != null:
		_draft_timer.start()


func _undo() -> void:
	if model.undo():
		_refresh_all()


func _redo() -> void:
	if model.redo():
		_refresh_all()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed and event.keycode == KEY_Z:
		_redo() if event.shift_pressed else _undo()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_Y:
		_redo()
		get_viewport().set_input_as_handled()


func _paint_cells(cells: Array, brush_id: String) -> void:
	if _room_key.is_empty():
		return
	var source: Dictionary = model.get_document(_room_key)
	if brush_id in ["floor", "wall", "erase"]:
		var rows: Array = source.get("cells", []).duplicate()
		for value: Variant in cells:
			var cell: Vector2i = _cell(value)
			if cell.x < 0 or cell.y < 0 or cell.x >= 128 or cell.y >= 128:
				continue
			while rows.size() <= cell.y:
				rows.append("")
			var row: String = str(rows[cell.y]).rpad(cell.x + 1, " ")
			rows[cell.y] = row.substr(0, cell.x) + {"floor": ".", "wall": "#", "erase": " "}[brush_id] + row.substr(cell.x + 1)
		source["cells"] = rows
	elif brush_id in ["clearance", "clear_clearance"]:
		var clear: Array = source.get("keep_clear", []).duplicate(true)
		for value: Variant in cells:
			if brush_id == "clear_clearance":
				clear = clear.filter(func(candidate: Variant) -> bool: return _cell(candidate) != _cell(value))
			elif not _contains_cell(clear, _cell(value)):
				clear.append(value)
		source["keep_clear"] = clear
	elif brush_id == "anchor" and _room_path.size() == 2 and _room_path[0] == "anchors":
		source.anchors[_room_path[1]] = cells.back().duplicate(true)
	elif brush_id in ["port", "slot", "slot_region"]:
		var expected: String = "ports" if brush_id == "port" else "slots"
		if _room_path.size() != 2 or _room_path[0] != expected:
			_set_status("请先在左侧选择一个%s" % LABELS[expected])
			return
		var selected: Dictionary = _read_path(source, _room_path)
		var field: String = "cells" if brush_id == "port" else ("region" if brush_id == "slot_region" else "points")
		var points: Array = selected.get(field, []).duplicate(true)
		for value: Variant in cells:
			if not _contains_cell(points, _cell(value)):
				points.append(value)
		selected[field] = points
	else:
		return
	model.replace_document(_room_key, source)


func _room_display(source: Dictionary) -> Dictionary:
	var result: Dictionary = {"floor_cells": [], "wall_cells": [], "keep_clear": source.get("keep_clear", []).duplicate(true), "ports": source.get("ports", []).duplicate(true), "anchors": source.get("anchors", {}).duplicate(true), "slots": []}
	var rows: Array = source.get("cells", [])
	for y: int in range(rows.size()):
		for x: int in range(str(rows[y]).length()):
			var character: String = str(rows[y]).substr(x, 1)
			if character == ".":
				result.floor_cells.append({"x": x, "y": y})
			elif character == "#":
				result.wall_cells.append({"x": x, "y": y})
	for slot: Dictionary in source.get("slots", []):
		var points: Array = slot.get("points", []).duplicate(true) + slot.get("region", []).duplicate(true)
		var preview: Dictionary = {"id": slot.get("id", ""), "cells": points, "footprint_cells": [], "clearance_cells": []}
		for point: Variant in points:
			for field: String in ["footprint", "clearance"]:
				for offset: Variant in slot.get(field, []):
					var delta: Vector2i = _cell(offset)
					for turn: int in range(posmod(int(slot.get("rotation", 0)), 360) / 90):
						delta = Vector2i(-delta.y, delta.x)
					preview[field + "_cells"].append(_point(_cell(point) + delta))
		result.slots.append(preview)
	return result


func _add_border_walls() -> void:
	var source: Dictionary = model.get_document(_room_key)
	var display: Dictionary = _room_display(source)
	var occupied: Dictionary = {}
	for value: Variant in display.floor_cells + display.wall_cells:
		occupied[_cell(value)] = true
	var walls: Array = []
	for value: Variant in display.floor_cells:
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var cell: Vector2i = _cell(value) + direction
			if cell.x >= 0 and cell.y >= 0 and not occupied.has(cell):
				walls.append(_point(cell))
	model.begin_gesture()
	_paint_cells(walls, "wall")
	model.end_gesture()
	_refresh_room()


func _rotate_room() -> void:
	var source: Dictionary = model.get_document(_room_key)
	var rows: Array = source.get("cells", [])
	if rows.is_empty():
		return
	var width: int = 0
	for row: String in rows:
		width = maxi(width, row.length())
	var rotated: Array = []
	for x: int in range(width):
		var line: String = ""
		for y: int in range(rows.size() - 1, -1, -1):
			line += str(rows[y]).substr(x, 1) if x < str(rows[y]).length() else " "
		rotated.append(line)
	source.cells = rotated
	var shift: Vector2i = Vector2i(rows.size() - 1, 0)
	for id: String in source.get("anchors", {}):
		source.anchors[id] = _rotate_point(source.anchors[id], shift)
	source["keep_clear"] = _rotate_points(source.get("keep_clear", []), shift)
	for port: Dictionary in source.get("ports", []):
		port.cells = _rotate_points(port.get("cells", []), shift)
		port.normal = _rotate_point(port.get("normal", {}), Vector2i.ZERO)
	for slot: Dictionary in source.get("slots", []):
		for field: String in ["points", "region"]:
			slot[field] = _rotate_points(slot.get(field, []), shift)
		# 相对占地和成员偏移由槽位朝向一起旋转，不能重复旋转。
		slot["rotation"] = (int(slot.get("rotation", 0)) + 90) % 360
	model.replace_document(_room_key, source)
	_refresh_room()
	_room_canvas.fit_content()


func _move_selection(delta: Vector2i, copy: bool) -> void:
	var rectangle: Rect2i = _room_canvas.selection_rect
	if not rectangle.has_area():
		_set_status("先使用选择工具拖出选区")
		return
	var destination: Rect2i = Rect2i(rectangle.position + delta, rectangle.size)
	if destination.position.x < 0 or destination.position.y < 0 or destination.end.x > 128 or destination.end.y > 128:
		_set_status("选区移出 0–127 格编辑范围，未修改图纸")
		return
	var source: Dictionary = model.get_document(_room_key)
	var rows: Array = source.get("cells", [])
	var cells_by_brush: Dictionary = {"floor": [], "wall": [], "erase": []}
	for y: int in range(rectangle.position.y, rectangle.end.y):
		for x: int in range(rectangle.position.x, rectangle.end.x):
			var character: String = str(rows[y]).substr(x, 1) if y >= 0 and y < rows.size() and x >= 0 and x < str(rows[y]).length() else " "
			cells_by_brush[{".": "floor", "#": "wall", " ": "erase"}.get(character, "erase")].append(_point(Vector2i(x, y) + delta))
	model.begin_gesture()
	if not copy:
		var cleared: Array = []
		for y: int in range(rectangle.position.y, rectangle.end.y):
			for x: int in range(rectangle.position.x, rectangle.end.x):
				cleared.append({"x": x, "y": y})
		_paint_cells(cleared, "erase")
	for brush_id: String in cells_by_brush:
		_paint_cells(cells_by_brush[brush_id], brush_id)
	source = model.get_document(_room_key)
	if not copy:
		for id: String in source.get("anchors", {}):
			if rectangle.has_point(_cell(source.anchors[id])):
				source.anchors[id] = _point(_cell(source.anchors[id]) + delta)
		for port: Dictionary in source.get("ports", []):
			port.cells = _move_points(port.get("cells", []), rectangle, delta)
		for slot: Dictionary in source.get("slots", []):
			for field: String in ["points", "region"]:
				slot[field] = _move_points(slot.get(field, []), rectangle, delta)
		source.keep_clear = _move_points(source.get("keep_clear", []), rectangle, delta)
		model.replace_document(_room_key, source)
	else:
		var copied_ports: Dictionary = {}
		for id: String in source.get("anchors", {}).keys():
			if rectangle.has_point(_cell(source.anchors[id])):
				source.anchors[_unique_id(id + "_copy", source.anchors.keys())] = _point(_cell(source.anchors[id]) + delta)
		for field: String in ["ports", "slots"]:
			var members: Array = source.get(field, [])
			for member: Dictionary in members.duplicate(true):
				var selected_points: Array = member.get("cells", []) if field == "ports" else member.get("points", []) + member.get("region", [])
				if selected_points.is_empty() or not selected_points.all(func(point: Variant) -> bool: return rectangle.has_point(_cell(point))):
					continue
				var previous_id: String = str(member.id)
				member.id = _unique_id(previous_id + "_copy", members.map(func(value: Dictionary) -> String: return str(value.get("id", ""))))
				if field == "ports":
					copied_ports[previous_id] = member.id
				elif copied_ports.has(str(member.get("constraints", {}).get("face_port", ""))):
					member.constraints.face_port = copied_ports[str(member.constraints.face_port)]
				for coordinate_field: String in (["cells"] if field == "ports" else ["points", "region"]):
					member[coordinate_field] = _move_points(member.get(coordinate_field, []), rectangle, delta)
				members.append(member)
			source[field] = members
		var clear: Array = source.get("keep_clear", []).duplicate(true)
		for point: Variant in source.get("keep_clear", []):
			var moved: Vector2i = _cell(point) + delta
			if rectangle.has_point(_cell(point)) and not _contains_cell(clear, moved):
				clear.append(_point(moved))
		source.keep_clear = clear
		model.replace_document(_room_key, source)
	model.end_gesture()
	_room_canvas.selection_rect.position += delta
	_refresh_room()


func _add_room_member(field: String) -> void:
	var source: Dictionary = model.get_document(_room_key)
	if source.is_empty():
		return
	var point: Dictionary = model.selection.get("cell", {"x": 3, "y": 3}).duplicate(true)
	if field == "anchors":
		var anchors: Dictionary = source.get("anchors", {})
		var id: String = _unique_id("anchor", anchors.keys())
		anchors[id] = point
		source.anchors = anchors
		_room_path = [field, id]
	else:
		var values: Array = source.get(field, [])
		var id: String = _unique_id("port" if field == "ports" else "slot", values.map(func(value: Dictionary) -> String: return str(value.get("id", ""))))
		if field == "ports":
			values.append({"id": id, "cells": [point], "normal": {"x": 0, "y": -1}, "kind": "passage", "group": "entrances", "unused": "wall"})
		else:
			values.append({"id": id, "kind": "torch", "points": [point], "region": [], "entries": [{"id": _default_content_id("torch"), "weight": 1.0}], "min_count": 1, "max_count": 1, "required": true, "rotation": 0, "footprint": [{"x": 0, "y": 0}], "clearance": [], "exclusive_group": "", "constraints": {"near_wall": false, "min_distance_from_ports_cells": 0, "face_port": ""}, "group_members": []})
		source[field] = values
		_room_path = [field, values.size() - 1]
	model.replace_document(_room_key, source)
	_refresh_room()
	_room_canvas.brush = "anchor" if field == "anchors" else ("port" if field == "ports" else "slot")


func _rename_anchor(next_id: String) -> void:
	if _room_path.size() != 2 or _room_path[0] != "anchors":
		return
	var source: Dictionary = model.get_document(_room_key)
	var previous: String = str(_room_path[1])
	if next_id == previous:
		return
	if not store._valid_id(next_id) or source.get("anchors", {}).has(next_id):
		_set_status("锚点名称必须唯一，且只包含字母、数字、下划线或连字符")
		return
	var references: Array = model.find_references("room", _room_key.get_file(), previous)
	source.anchors[next_id] = source.anchors[previous]
	source.anchors.erase(previous)
	_room_path = ["anchors", next_id]
	model.replace_document(_room_key, source)
	_refresh_room()
	if not references.is_empty():
		_set_issues(references.map(func(reference: Dictionary) -> Dictionary: return {"document": reference.document, "path": reference.path, "message": "锚点已重命名，请修复引用后保存项目"}))


func _remove_room_member() -> void:
	if _room_path.size() != 2:
		return
	var source: Dictionary = model.get_document(_room_key)
	var selected: Variant = _read_path(source, _room_path)
	var id: String = str(_room_path[1]) if _room_path[0] == "anchors" else str(selected.get("id", ""))
	var references: Array = model.find_references("room", _room_key.get_file(), id)
	if _room_path[0] == "anchors":
		source.anchors.erase(_room_path[1])
	else:
		source[_room_path[0]].remove_at(_room_path[1])
	model.replace_document(_room_key, source)
	_room_path = []
	_refresh_room()
	if not references.is_empty():
		_set_issues(references.map(func(reference: Dictionary) -> Dictionary: return {"document": reference.document, "path": reference.path, "message": "删除成员后请修复引用；当前内容可保存为草稿"}))


func _add_composition_member(field: String) -> void:
	var source: Dictionary = model.get_document(_composition_key)
	if source.is_empty():
		return
	var values: Array = source.get(field, [])
	var id: String = _unique_id("room" if field == "nodes" else "link", values.map(func(value: Dictionary) -> String: return str(value.get("id", ""))))
	if field == "nodes":
		values.append({"id": id, "purpose": "", "blueprints": [{"id": _room_key.get_file(), "weight": 1.0, "max_instances": 0}], "min_count": 1, "max_count": 1, "rotations": [0, 90, 180, 270]})
	else:
		var nodes: Array = source.get("nodes", [])
		var first: String = str(nodes[0].get("id", "")) if not nodes.is_empty() else ""
		var last: String = str(nodes.back().get("id", "")) if not nodes.is_empty() else ""
		values.append({"id": id, "mode": "pair", "from": {"node": first, "port": "front"}, "to": {"node": last, "port": "front"}, "required": true, "probability": 1.0, "style": "corridor", "max_length_cells": 24})
	source[field] = values
	_composition_path = [field, values.size() - 1]
	model.replace_document(_composition_key, source)
	_refresh_composition()


func _remove_composition_member() -> void:
	if _composition_path.size() != 2:
		return
	_remove_array_entry(_composition_key, [_composition_path[0]], int(_composition_path[1]))
	_composition_path = []
	_refresh_composition()


func _toggle_endpoint_group(path: Array) -> void:
	var source: Dictionary = model.get_document(_composition_key)
	var endpoint: Dictionary = _read_path(source, path)
	if endpoint.has("port"):
		endpoint.erase("port")
		endpoint["group"] = "entrances"
	else:
		endpoint.erase("group")
		endpoint["port"] = "front"
	model.replace_document(_composition_key, source)
	_build_composition_properties()


func _toggle_endpoint_instance(path: Array) -> void:
	var source: Dictionary = model.get_document(_composition_key)
	var endpoint: Dictionary = _read_path(source, path)
	if endpoint.get("instance", "") == "last":
		endpoint.erase("instance")
	else:
		endpoint["instance"] = "last" if endpoint.get("instance", "") == "first" else "first"
	model.replace_document(_composition_key, source)
	_build_composition_properties()


func _toggle_connection_width(enabled: bool) -> void:
	var source: Dictionary = model.get_document(_composition_key)
	var connection: Dictionary = _read_path(source, _composition_path)
	if enabled:
		connection["width_cells"] = 1
	else:
		connection.erase("width_cells")
	model.replace_document(_composition_key, source)
	_build_composition_properties()


func _add_array_field(key: String, path: Array, entry: Variant) -> void:
	var source: Dictionary = model.get_document(key)
	var value: Variant = _read_path(source, path)
	var values: Array = value.duplicate(true) if value is Array else []
	values.append(entry)
	_write_path(source, path, values)
	model.replace_document(key, source)
	_refresh_property_panels()


func _remove_array_entry(key: String, path: Array, index: int) -> void:
	var source: Dictionary = model.get_document(key)
	var values: Variant = _read_path(source, path)
	if not values is Array or index < 0 or index >= values.size():
		return
	values.remove_at(index)
	model.replace_document(key, source)
	_refresh_property_panels()


func _new_array_entry(field: String, key: String, path: Array = []) -> Variant:
	if field == "blueprints":
		return {"id": _room_key.get_file(), "weight": 1.0, "max_instances": 0}
	if field == "entries":
		var owner: Variant = _read_path(model.get_document(key), path.slice(0, path.size() - 1))
		return {"id": _default_content_id(str(owner.get("kind", "torch")) if owner is Dictionary else "torch"), "weight": 1.0}
	if field == "group_members":
		return {"kind": "prop", "id": "crates", "offset": {"x": 1, "y": 0}, "rotation": 0, "required": true}
	if field == "rotations":
		return 0
	return {"x": 0, "y": 0}


func _default_content_id(kind: String) -> String:
	for entry: Dictionary in _capabilities.get("entries", []):
		if str(entry.get("kind", "")) == kind and bool(entry.get("available", false)):
			return str(entry.get("id", ""))
	return ""


func _apply_capability_footprint() -> void:
	if _room_path.size() != 2 or _room_path[0] != "slots":
		return
	var source: Dictionary = model.get_document(_room_key)
	var slot: Dictionary = _read_path(source, _room_path)
	var footprint: Array = []
	var clearance: Array = []
	for candidate: Dictionary in slot.get("entries", []):
		for entry: Dictionary in _capabilities.get("entries", []):
			if entry.get("kind") == slot.get("kind") and entry.get("id") == candidate.get("id"):
				for cell: Variant in entry.get("footprint_cells", []):
					if not _contains_cell(footprint, _cell(cell)):
						footprint.append(_point(_cell(cell)))
				for cell: Variant in entry.get("clearance_cells", []):
					if not _contains_cell(clearance, _cell(cell)):
						clearance.append(_point(_cell(cell)))
	if footprint.is_empty():
		_set_status("能力快照没有当前内容的占地信息")
		return
	slot.footprint = footprint
	slot.clearance = clearance
	model.replace_document(_room_key, source)
	_build_room_properties()


func _show_create(kind: String, copy: bool) -> void:
	_create_kind = kind
	_create_copy = copy
	var current: String = _room_key if kind == "room" else _composition_key
	_name_input.text = _unique_id(current.get_file() + "_variant" if copy else ("room" if kind == "room" else "poi"), model.list_keys(kind).map(func(key: String) -> String: return key.get_file()))
	_name_dialog.popup_centered()
	_name_input.grab_focus()
	_name_input.select_all()


func _confirm_create() -> void:
	var id: String = _name_input.text.strip_edges()
	var key: String = _create_kind + "/" + id
	if store.document_path(key).is_empty() or model.documents.has(key):
		_set_status("创建失败：ID 非法或已存在")
		return
	var source: Dictionary
	if _create_copy:
		source = model.get_document(_room_key if _create_kind == "room" else _composition_key)
	elif _create_kind == "room":
		source = {"schema_version": 1, "display_name": "新房间", "purpose": "home", "cells": ["#######", "#.....#", "#.....#", "#.....#", "#.....#", "#.....#", "#######"], "rotations": [0, 90, 180, 270], "anchors": {"primary": {"x": 3, "y": 3}}, "ports": [{"id": "front", "cells": [{"x": 3, "y": 6}], "normal": {"x": 0, "y": 1}, "kind": "passage", "group": "entrances", "unused": "open"}], "slots": [], "keep_clear": []}
	else:
		source = {"schema_version": 1, "display_name": "新 POI 组合", "nodes": [{"id": "root", "purpose": "", "blueprints": [{"id": _room_key.get_file(), "weight": 1.0, "max_instances": 0}], "min_count": 1, "max_count": 1, "rotations": [0, 90, 180, 270]}], "connections": [], "primary": {"node": "root", "anchor": "primary"}}
	source["id"] = id
	if _create_copy:
		source.display_name = str(source.get("display_name", id)) + " · 变体"
	model.replace_document(key, source)
	if _create_kind == "room":
		_room_key = key
		_room_path = []
	else:
		_composition_key = key
		_composition_path = []
	_refresh_all()


func _request_delete(key: String) -> void:
	if key.is_empty():
		return
	_delete_key = key
	var references: Array = model.find_references(key.get_slice("/", 0), key.get_file())
	var lines: PackedStringArray = ["删除 %s？" % key]
	if not references.is_empty():
		lines.append("以下引用会失效。删除后可保存草稿，修复引用后才能保存项目：")
		for reference: Dictionary in references:
			lines.append("%s · %s" % [reference.document, reference.path])
	_delete_dialog.dialog_text = "\n".join(lines)
	_delete_dialog.popup_centered(Vector2i(620, 260))


func _validate_room() -> void:
	if _validating:
		return
	_begin_validation()
	var source: Dictionary = model.get_document(_room_key)
	var bundle: Dictionary = COMPILER.compile_bundle({_room_key.get_file(): source}, {})
	if not bool(bundle.get("valid", false)):
		_set_issues(bundle.get("issues", []))
		_validation_label.text = "单房校验失败，当前结果已清除。"
		return
	# 单房使用内存中的单节点组合完成局部试生成；辅助锚点从不写回编辑文档。
	var preview_room: Dictionary = source.duplicate(true)
	var display: Dictionary = _room_display(source)
	var anchor_id: String = _unique_id("editor_preview_origin", preview_room.get("anchors", {}).keys())
	preview_room["anchors"] = preview_room.get("anchors", {}).duplicate(true)
	# 普通 primary 可以合法地放置陈设；局部验证从图纸声明的净空或门内通路起步。
	var origin: Variant = display.floor_cells[0]
	if not display.keep_clear.is_empty():
		origin = display.keep_clear[0]
	else:
		for port: Dictionary in source.get("ports", []):
			var normal: Dictionary = port.get("normal", {})
			var point: Dictionary = port.get("cells", [{}])[0]
			var inner: Dictionary = {"x": int(point.get("x", 0)) - int(normal.get("x", 0)), "y": int(point.get("y", 0)) - int(normal.get("y", 0))}
			if display.floor_cells.has(inner):
				origin = inner
				break
	preview_room.anchors[anchor_id] = origin
	var composition_id: String = "editor_single_room_preview"
	var overrides: Dictionary = model.dependency_overrides()
	overrides.rooms[_room_key.get_file()] = preview_room
	overrides.compositions[composition_id] = {"schema_version": 1, "id": composition_id, "nodes": [{"id": "room", "blueprints": [{"id": _room_key.get_file(), "weight": 1}], "min_count": 1, "max_count": 1}], "connections": [], "primary": {"node": "room", "anchor": anchor_id}}
	bundle = RESOURCE_CATALOG.load_bundle(overrides, [composition_id])
	if not bool(bundle.get("valid", false)):
		_set_issues(bundle.get("issues", []))
		_validation_label.text = "单房内容校验失败，当前结果已清除。"
		return
	var generated: Dictionary = ASSEMBLER.generate(composition_id, bundle, int(_seed_input.value))
	if not bool(generated.get("valid", false)):
		_set_issues(generated.get("issues", []))
		_validation_label.text = "单房局部试生成失败，当前结果已清除。"
		return
	var plan: Dictionary = generated.plan
	for id: String in plan.get("anchors", {}).keys():
		if id.ends_with("." + anchor_id):
			plan.anchors.erase(id)
	_results.append({"valid": true, "plan": plan, "issues": []})
	_select_result(0)
	_result_canvas.fit_content()
	_preview_revision = model.revision
	_validation_label.text = "单房局部校验通过：%s，内容可用性、占地、净空与房内通路已验证。区域预算、跨房组装和人口上限尚未验证。" % str(source.get("display_name", _room_key))
	_result_list.add_item("单房局部通过")


func _validate_composition() -> void:
	if _validating:
		return
	_begin_validation()
	var bundle: Dictionary = RESOURCE_CATALOG.load_bundle(model.dependency_overrides(), [_composition_key.get_file()])
	if not bool(bundle.get("valid", false)):
		_set_issues(bundle.get("issues", []))
		_validation_label.text = "图纸 / 组合校验失败，当前结果已清除。"
		return
	_validating = true
	_cancel_validation = false
	var version: int = model.revision
	var first_seed: int = int(_seed_input.value)
	var count: int = int(_seed_count.value)
	var failures: int = 0
	for offset: int in range(count):
		if _cancel_validation or version != model.revision:
			break
		var seed_value: int = first_seed + offset
		var generated: Dictionary = ASSEMBLER.generate(_composition_key.get_file(), bundle, seed_value, {"origin": {"x": 0, "y": 0}})
		var success: bool = bool(generated.get("valid", false))
		_results.append({"seed": seed_value, "valid": success, "plan": generated.get("plan", {}), "issues": generated.get("issues", [])})
		_result_list.add_item("seed %d · %s" % [seed_value, "局部通过" if success else "失败"])
		if not success:
			failures += 1
		_validation_label.text = "正在验证 %d / %d；失败 %d。%s" % [offset + 1, count, failures, "草稿预览" if model.is_dirty() else "已保存内容"]
		await get_tree().process_frame
	_validating = false
	if version != model.revision:
		_begin_validation()
		_validation_label.text = "验证期间文档已修改，旧结果已清除，请重新验证。"
		return
	_preview_revision = version
	if not _results.is_empty():
		_result_list.select(0)
		_select_result(0)
	_validation_label.text = "%s：单 POI %d 个种子，%d 个失败。依赖 %s；未验证实际区域预算 / 人口。" % ["已取消" if _cancel_validation or version != model.revision else "完成", _results.size(), failures, str(bundle.get("content_hash", "")).left(12)]


func _validate_full_map() -> void:
	if _validating:
		return
	_begin_validation()
	full_map_invalidated.emit()
	if _map_key.is_empty():
		_set_status("请选择地图配置")
		return
	_validation_label.text = "正在使用正式地图生成器验证区域、预算与完整产物……"
	_validating = true
	await get_tree().process_frame
	var source: Dictionary = model.get_document(_map_key)
	var overrides: Dictionary = model.dependency_overrides()
	var parsed = CONFIG_CATALOG.parse_and_normalize_config(source, overrides)
	if not parsed.is_success():
		_set_issues(parsed.get_issues())
		_validation_label.text = "完整地图解析失败，当前结果已清除。"
		_validating = false
		return
	parsed.config.seed = int(_seed_input.value)
	var generator = MAP_GENERATOR.new()
	var generated = generator.generate_full(parsed.config)
	_validating = false
	if generated == null:
		_set_issues(generator.get_last_generation_issues())
		_validation_label.text = "完整地图生成失败，当前结果已清除。"
		return
	var bundle: Dictionary = parsed.config.get_meta("poi_resource_bundle", {})
	var dependency_hash: String = str(bundle.get("content_hash", ""))
	_show_map_result(generated, generator.last_resolved_seed, source, dependency_hash, _map_key, "完整地图通过")


func _show_map_result(generated: RefCounted, seed_value: int, source: Dictionary, dependency_hash: String, map_key: String, title: String) -> void:
	_preview_revision = model.revision
	_result_map_key = map_key
	_validation_label.text = "%s：%s · seed %d · %d×%d · 依赖 %s。仅与相同配置、内容快照及运行参数的 authority 结果比较。" % [title, map_key.get_file(), seed_value, generated.width, generated.height, dependency_hash.left(12)]
	_result_list.add_item("%s · %d 个 POI" % [title, generated.poi_instances.size()])
	for poi: Dictionary in generated.poi_instances:
		if str(poi.get("layout_kind", "")) == "authored_rooms":
			var plan: Dictionary = {"rooms": poi.get("rooms", []).duplicate(true), "floor_cells": poi.get("floor_cells", []).duplicate(true), "wall_cells": poi.get("wall_cells", []).duplicate(true), "footprint_cells": poi.get("footprint_cells", []).duplicate(true), "ports": [], "anchors": poi.get("named_anchors", {}), "slots": []}
			for room: Dictionary in poi.get("rooms", []):
				plan.ports.append_array(room.get("ports", []))
			for request: Dictionary in poi.get("content_plans", []):
				plan.slots.append(_content_display(request))
			_result_canvas.show_plan(plan)
			_result_canvas.fit_content()
			break
	full_map_generated.emit(generated, seed_value, source, dependency_hash)


func _generate_poi_only_map() -> bool:
	if _validating:
		return false
	_begin_validation()
	full_map_invalidated.emit()
	if _map_key.is_empty() or _composition_key.is_empty() or _template_selector.item_count == 0:
		_set_status("请选择源地图、POI 条目与当前组合")
		return false
	_validating = true
	_validation_label.text = "正在生成 POI Only 测试地图，并检查源地图预算与完整内容……"
	await get_tree().process_frame
	var source_template: String = str(_template_selector.get_item_metadata(_template_selector.selected))
	var composition_id: String = _composition_key.get_file()
	var seed_value: int = int(_seed_input.value)
	var overrides: Dictionary = model.dependency_overrides()
	var built: Dictionary = CONFIG_CATALOG.build_poi_only_config(model.get_document(_map_key), composition_id, seed_value, overrides, "", source_template)
	if not bool(built.get("valid", false)):
		_validating = false
		_set_issues(built.get("issues", []))
		_validation_label.text = "POI Only 配置失败，当前结果已清除。"
		return false
	var source: Dictionary = built.config.duplicate(true)
	var filename: String = "poi_test_" + composition_id
	source["id"] = filename
	source["display_name"] = "POI 测试 · " + str(model.get_document(_composition_key).get("display_name", composition_id))
	var parsed = CONFIG_CATALOG.parse_and_normalize_config(source, overrides)
	if not parsed.is_success():
		_validating = false
		_set_issues(parsed.get_issues())
		_validation_label.text = "POI Only 解析失败，当前结果已清除。"
		return false
	var generator = MAP_GENERATOR.new()
	var generated = generator.generate_full(parsed.config)
	_validating = false
	if generated == null:
		_set_issues(generator.get_last_generation_issues())
		_validation_label.text = "POI Only 生成失败，当前结果已清除。"
		return false
	_poi_test_key = "map/" + filename
	source = CONFIG_CATALOG.serialize_normalized_config(parsed)
	model.replace_document(_poi_test_key, source)
	_refresh_all()
	var dependency_hash: String = str(parsed.config.get_meta("poi_resource_bundle", {}).get("content_hash", ""))
	_show_map_result(generated, generator.last_resolved_seed, source, dependency_hash, _poi_test_key, "POI Only 测试地图通过")
	_validation_label.text += " 源条目 %s；内容规则 %s。" % [source_template, str(source.get("poi_only", {}).get("content_profile_id", ""))]
	_set_status("已生成测试地图草稿 %s.json；可查看整图或保存后从正式主菜单开始测试" % filename)
	return true


func _save_and_launch_poi_only() -> void:
	if not await _generate_poi_only_map():
		return
	if not _save_project():
		return
	var launched: Dictionary = game_launcher.launch_saved_map_test(_poi_test_key.get_file())
	if not bool(launched.get("ok", false)):
		_set_status("测试地图已保存；启动失败：%s" % str(launched.get("error", "未知错误")))
		return
	_set_status("测试地图已保存，正式主菜单已预选 %s；点击 Solo 或 Host 开始测试" % _poi_test_key.get_file())


func _begin_validation() -> void:
	_tabs.current_tab = 2
	_result_canvas.modulate.a = 1.0
	_result_canvas.show_plan({})
	_result_list.clear()
	_results.clear()
	_set_issues([])
	_preview_revision = -1


func _select_result(index: int) -> void:
	if index < 0 or index >= _results.size():
		return
	var result: Dictionary = _results[index]
	_set_issues(result.get("issues", []))
	if not bool(result.get("valid", false)):
		_result_canvas.show_plan({})
		return
	var plan: Dictionary = result.get("plan", {}).duplicate(true)
	plan["ports"] = []
	plan["slots"] = []
	for room: Dictionary in plan.get("rooms", []):
		plan.ports.append_array(room.get("ports", []))
	for request: Dictionary in plan.get("content_requests", []):
		plan.slots.append(_content_display(request))
	_result_canvas.show_plan(plan)
	_result_canvas.fit_content()


func _content_display(request: Dictionary) -> Dictionary:
	return {"id": str(request.get("slot_id", "")), "cells": [request.cell] if request.has("cell") else [], "footprint_cells": request.get("placement_footprint", []), "clearance_cells": request.get("clearance_cells", [])}


func _jump_to_source_room(blueprint_id: String, local_cell: Vector2i) -> void:
	if _preview_revision != model.revision:
		_set_status("预览已过期，请重新验证后定位来源")
		return
	var key: String = "room/" + blueprint_id
	if not model.documents.has(key):
		_set_status("当前文档没有预览来源图纸：%s" % blueprint_id)
		return
	_room_key = key
	_room_path = []
	_tabs.current_tab = 0
	model.selection["cell"] = _point(local_cell)
	_refresh_all()
	_room_canvas.brush = "select"
	_room_canvas.selection_rect = Rect2i(local_cell, Vector2i.ONE)
	_room_canvas.fit_content()
	_set_status("来源图纸：%s · 局部格 (%d, %d)" % [blueprint_id, local_cell.x, local_cell.y])


func _refresh_map_templates() -> void:
	var selected_id: String = str(_template_selector.get_item_metadata(_template_selector.selected)) if _template_selector.selected >= 0 else ""
	_template_selector.clear()
	var source: Dictionary = model.get_document(_map_key)
	var limits: Dictionary = POPULATION_CONTRACT.resolve_limits(source.get("monster_generation", {}).get("population_budgets", {}), _capabilities.get("population_limits", {}))
	_population_label.text = "当前地图人口限制：POI 初始合计 %d · 单 POI %s · 巢穴 %d。内容能力 %s。" % [int(limits.get("poi_initial_live_cap", 0)), str(int(limits.get("poi_initial_per_poi_cap", 0))) if int(limits.get("poi_initial_per_poi_cap", 0)) > 0 else "不单独限制", int(limits.get("nest_site_cap", 0)), str(_capabilities.get("content_hash", "未载入")).left(12)]
	for entry: Dictionary in source.get("poi_generation", {}).get("poi_types", []):
		_template_selector.add_item(str(entry.get("id", "")))
		_template_selector.set_item_metadata(_template_selector.item_count - 1, str(entry.get("id", "")))
		if str(entry.get("id", "")) == selected_id:
			_template_selector.select(_template_selector.item_count - 1)


func _bind_composition() -> void:
	if _template_selector.item_count == 0 or _composition_key.is_empty():
		return
	var source: Dictionary = model.get_document(_map_key)
	var template_id: String = str(_template_selector.get_item_metadata(_template_selector.selected))
	for entry: Dictionary in source.get("poi_generation", {}).get("poi_types", []):
		if str(entry.get("id", "")) != template_id:
			continue
		entry["layout_kind"] = "authored_rooms"
		entry["composition_id"] = _composition_key.get_file()
		for field: String in ["main_room", "sub_rooms", "connectivity", "corridor"]:
			entry.erase(field)
		source["schema_version"] = 3
		model.replace_document(_map_key, source)
		_set_status("已在草稿中绑定 %s → %s；完整地图通过后保存到项目" % [template_id, _composition_key.get_file()])
		return


func _save_recovery_draft() -> void:
	store.save_tool_state(model.selection, model.view_state)
	if model.is_dirty():
		store.save_draft(model.draft_snapshot())


func _save_canvas_state() -> void:
	if _room_key.is_empty():
		return
	model.view_state["canvas/" + _room_key] = {"zoom": _room_canvas.zoom, "x": _room_canvas.pan.x, "y": _room_canvas.pan.y}
	if _draft_timer != null:
		_draft_timer.start()


func _save_draft() -> bool:
	var error: Error = store.save_draft(model.draft_snapshot())
	_set_status("草稿已保存到工具恢复目录，未改变项目文件" if error == OK else "草稿保存失败：%s" % error_string(error))
	return error == OK


func _restore_draft() -> void:
	var draft: Dictionary = store.load_draft()
	if draft.is_empty() or not model.restore_draft(draft):
		_set_status("没有可恢复的草稿")
		return
	_room_key = str(model.selection.get("room", _room_key))
	_composition_key = str(model.selection.get("composition", _composition_key))
	_room_path = model.selection.get("room_path", []).duplicate()
	_composition_path = model.selection.get("composition_path", []).duplicate()
	_refresh_all()
	_set_status("已恢复草稿；保存项目时仍会检测外部文件冲突")


func _save_project() -> bool:
	model.end_gesture()
	var overrides: Dictionary = model.dependency_overrides()
	var bundle: Dictionary = RESOURCE_CATALOG.load_bundle(overrides)
	if not bool(bundle.get("valid", false)):
		_set_issues(bundle.get("issues", []))
		_set_status("未保存：关联图纸 / 组合校验失败；可以保存草稿")
		return false
	var changed_keys: Array[String] = model.get_changed_keys()
	# 所有引用新组合的地图都校验，避免修改图纸后破坏另一张地图。
	for key: String in model.list_keys("map"):
		var source: Dictionary = model.get_document(key)
		var relevant: bool = changed_keys.has(key)
		for entry: Dictionary in source.get("poi_generation", {}).get("poi_types", []):
			if entry.get("layout_kind", "") == "authored_rooms":
				relevant = true
		if not relevant:
			continue
		var parsed = CONFIG_CATALOG.parse_and_normalize_config(source, overrides)
		if not parsed.is_success():
			_set_issues(parsed.get_issues())
			_set_status("未保存：关联地图 %s 校验失败" % key)
			return false
		if changed_keys.has(key):
			model.replace_document(key, CONFIG_CATALOG.serialize_normalized_config(parsed))
	# 编译器的规范源是项目保存真相；未编辑文件不因默认值注入而被改写。
	for key: String in changed_keys:
		if key.begins_with("room/") and bundle.rooms.has(key.get_file()):
			model.replace_document(key, bundle.rooms[key.get_file()])
		elif key.begins_with("composition/") and bundle.compositions.has(key.get_file()):
			model.replace_document(key, bundle.compositions[key.get_file()])
	var result: Dictionary = store.save_project(model.documents, model.get_changed_keys(), model.baseline_hashes)
	if not bool(result.get("ok", false)):
		_set_issues(result.get("issues", []))
		_set_status("项目保存失败；草稿保留")
		_save_recovery_draft()
		return false
	model.mark_saved(result.hashes)
	store.save_draft(model.draft_snapshot())
	_set_issues([])
	_refresh_all()
	_set_status("已保存 %d 份关联文件；正式战局下次开局读取此版本" % changed_keys.size())
	return true


func _apply_json(kind: String) -> void:
	var input: TextEdit = _room_json if kind == "room" else _composition_json
	var key: String = _room_key if kind == "room" else _composition_key
	var parser: JSON = JSON.new()
	if parser.parse(input.text) != OK or not parser.data is Dictionary:
		_set_issues([{"document": key, "path": "JSON:%d" % parser.get_error_line(), "message": parser.get_error_message()}])
		return
	if str(parser.data.get("id", "")) != key.get_file():
		_set_status("ID 不能通过 JSON 重命名；请使用复制变体保留引用")
		return
	model.replace_document(key, parser.data)
	_refresh_all()
	_set_status("JSON 已替换同一文档；尚未校验与保存")


func _set_issues(values: Array) -> void:
	_issue_values = values.duplicate(true)
	_issues.clear()
	for issue: Dictionary in values:
		_issues.add_item("%s %s · %s" % [str(issue.get("document", "")), str(issue.get("path", "")), str(issue.get("message", issue.get("code", "未知问题")))])
	if values.is_empty():
		_issues.add_item("问题列表为空；点击验证可检查当前草稿。")


func _locate_issue(index: int) -> void:
	if index < 0 or index >= _issue_values.size():
		return
	var issue: Dictionary = _issue_values[index]
	var path: String = str(issue.get("path", ""))
	var key: String = str(issue.get("document", ""))
	if key.is_empty() and path.begins_with("rooms."):
		key = "room/" + path.get_slice(".", 1).get_slice("[", 0)
	elif key.is_empty() and path.begins_with("compositions."):
		key = "composition/" + path.get_slice(".", 1).get_slice("[", 0)
	if key.begins_with("room/") and model.documents.has(key):
		_room_key = key
		_room_path = _issue_member_path(path, ["ports", "slots"], model.get_document(key))
		_tabs.current_tab = 0
	elif key.begins_with("composition/") and model.documents.has(key):
		_composition_key = key
		_composition_path = _issue_member_path(path, ["nodes", "connections"], model.get_document(key))
		_tabs.current_tab = 1
	_refresh_all()
	_set_status("定位：%s %s" % [key, path])


func _issue_member_path(path: String, fields: Array[String], source: Dictionary = {}) -> Array:
	for field: String in fields:
		var marker: String = field + "["
		var begin: int = path.find(marker)
		if begin >= 0:
			var index_text: String = path.substr(begin + marker.length()).get_slice("]", 0)
			if index_text.is_valid_int():
				return [field, int(index_text)]
		marker = field + "."
		begin = path.find(marker)
		if begin >= 0:
			var member_id: String = path.substr(begin + marker.length()).get_slice(".", 0)
			for index: int in range(source.get(field, []).size()):
				if str(source[field][index].get("id", "")) == member_id:
					return [field, index]
	return []


func _set_status(message: String) -> void:
	if _status != null:
		_status.text = message


func _refresh_property_panels() -> void:
	_build_room_properties()
	_build_composition_properties()
	_room_json.text = JSON.stringify(model.get_document(_room_key), "  ")
	_composition_json.text = JSON.stringify(model.get_document(_composition_key), "  ")


func _library_column(parent: Control) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size.x = 205
	parent.add_child(column)
	return column


func _property_tabs(parent: Control) -> TabContainer:
	var tabs: TabContainer = TabContainer.new()
	tabs.custom_minimum_size.x = 330
	parent.add_child(tabs)
	return tabs


func _property_container(parent: TabContainer) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "结构化属性"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)
	return content


func _json_page(parent: TabContainer, kind: String) -> TextEdit:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "高级 JSON"
	parent.add_child(page)
	var notice: Label = _label(page, "应用后替换同一编辑文档；未应用文本不参加预览或保存。")
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(page, "应用 JSON 到文档", func() -> void: _apply_json(kind))
	var input: TextEdit = TextEdit.new()
	input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	page.add_child(input)
	return input


func _button(parent: Node, title: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _label(parent: Node, text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _spin(minimum: float, maximum: float, step: float) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.custom_minimum_size.x = 85
	return spin


func _tree_item(tree: Tree, parent: TreeItem, title: String, path: Array) -> TreeItem:
	var item: TreeItem = tree.create_item(parent)
	item.set_text(0, title)
	item.set_metadata(0, path)
	return item


func _select_tree_item(item: TreeItem, path: Array, selected: Array) -> void:
	if path == selected:
		item.select(0)


func _clear_children(node: Node) -> void:
	for child: Node in node.get_children():
		child.propagate_call("set_block_signals", [true])
		node.remove_child(child)
		child.queue_free()


func _path_text(path: Array) -> String:
	var parts: PackedStringArray = []
	for part: Variant in path:
		parts.append(str(part))
	return ".".join(parts)


func _default_value(field: String) -> Variant:
	if field == "rotations":
		return [0, 90, 180, 270]
	if field == "schema_version":
		return 1
	if field == "primary":
		return {"node": "", "anchor": "primary"}
	return ""


func _unique_id(prefix: String, existing: Array) -> String:
	var index: int = 1
	var candidate: String = prefix
	while existing.has(candidate):
		candidate = "%s_%d" % [prefix, index]
		index += 1
	return candidate


func _cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	return Vector2i.ZERO


func _point(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}


func _contains_cell(values: Array, cell: Vector2i) -> bool:
	for value: Variant in values:
		if _cell(value) == cell:
			return true
	return false


func _rotate_point(value: Variant, shift: Vector2i) -> Dictionary:
	var cell: Vector2i = _cell(value)
	return _point(Vector2i(-cell.y, cell.x) + shift)


func _rotate_points(values: Array, shift: Vector2i) -> Array:
	return values.map(func(value: Variant) -> Dictionary: return _rotate_point(value, shift))


func _move_points(values: Array, rectangle: Rect2i, delta: Vector2i) -> Array:
	return values.map(func(value: Variant) -> Dictionary: return _point(_cell(value) + delta) if rectangle.has_point(_cell(value)) else _point(_cell(value)))
