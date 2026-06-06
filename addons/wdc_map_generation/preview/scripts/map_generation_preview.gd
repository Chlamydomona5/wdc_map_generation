extends Control

const CONFIG_CATALOG = preload("../../config/data_generated_map_config_catalog.gd")
const MAP_TYPES = preload("../../core/generated_map_types.gd")
const GENERATOR_SCRIPT = preload("../../core/generated_map_generator.gd")
const TILE_RULES = preload("../../core/generated_map_tile_rules.gd")
const WdcMapGenerationTypes = MAP_TYPES
const WdcMapGenerationGenerator = GENERATOR_SCRIPT

const COLOR_FLOOR: Color = Color(0.18, 0.18, 0.18, 1.0)
const COLOR_WALL: Color = Color(0.24, 0.24, 0.24, 1.0)
const COLOR_MINERAL_WALL: Color = Color(0.30, 0.52, 0.62, 1.0)
const COLOR_RARE_MINERAL: Color = Color(0.72, 0.62, 0.22, 1.0)
const COLOR_TURQUOISE: Color = Color(0.08, 0.82, 0.66, 1.0)
const COLOR_AMETHYST: Color = Color(0.66, 0.32, 0.85, 1.0)
const COLOR_GOLD: Color = Color(0.96, 0.78, 0.22, 1.0)
const COLOR_POI_WALL: Color = Color(0.16, 0.16, 0.18, 1.0)
const COLOR_POI_LARGE: Color = Color(0.39, 0.26, 0.08, 1.0)
const COLOR_POI_MEDIUM: Color = Color(0.24, 0.13, 0.32, 1.0)
const COLOR_POI_SMALL: Color = Color(0.08, 0.26, 0.21, 1.0)
const COLOR_TRACE_LARGE: Color = Color(0.30, 0.22, 0.11, 1.0)
const COLOR_TRACE_MEDIUM: Color = Color(0.24, 0.16, 0.31, 1.0)
const COLOR_TRACE_SMALL: Color = Color(0.08, 0.22, 0.20, 1.0)
const COLOR_PLAYER_SPAWN: Color = Color(0.95, 0.95, 0.95, 1.0)
const COLOR_MONSTER_SITE: Color = Color(0.24, 0.95, 0.40, 1.0)
const COLOR_NEST_SITE: Color = Color(0.92, 0.24, 0.24, 1.0)
const COLOR_TRAP: Color = Color(0.95, 0.35, 0.20, 1.0)
const EDITOR_TAB_PARAMETERS: int = 0
const EDITOR_TAB_JSON: int = 1
const PARAMETER_LABELS: Dictionary = {
	"activation_radius_m": "激活半径",
	"allow_clusters_inside_poi_rooms": "允许矿簇进入 POI 房间",
	"allow_clusters_under_poi_corridors": "允许矿簇位于 POI 走廊下",
	"allow_room_reentry": "允许走廊回接房间",
	"ambient_isolated_sites": "环境独立怪物点",
	"ambient_nests": "环境巢穴点",
	"attempts": "尝试次数",
	"author": "作者",
	"avoid_radius_cells": "避让半径",
	"base_candidate_chance": "基础候选概率",
	"base_cluster_type_id": "基础矿簇类型 ID",
	"bend_order_mode": "转弯顺序模式",
	"candidate_neighbors_per_room": "每房间候选邻居数",
	"cell_size_m": "单格尺寸",
	"center_ore_cluster": "中心矿簇",
	"cluster_override_id": "矿簇覆盖 ID",
	"cluster_overrides": "矿簇覆盖列表",
	"cluster_types": "矿簇类型列表",
	"connectivity": "连通性",
	"content": "内容配置",
	"corridor": "走廊配置",
	"count": "数量",
	"count_max": "最大数量",
	"count_min": "最小数量",
	"coverage_radius_cells": "覆盖半径",
	"debug": "调试配置",
	"debug_show_spawn_sites_by_default": "默认显示刷怪点调试",
	"dedicated_mineral_id": "专属矿物 ID",
	"default_min_distance_between_pois_cells": "默认 POI 最小间距",
	"default_room_content_anchor_search_radius_cells": "默认房间内容锚点搜索半径",
	"density_ratio": "密度比例",
	"description": "配置描述",
	"display_name": "显示名称",
	"door_margin_from_corner_cells": "门距拐角边距",
	"edge_margin_cells": "边缘留白",
	"enabled": "是否启用",
	"entries": "权重条目",
	"exposed_wall_candidate_chance": "暴露墙候选概率",
	"extra_connection_chance": "额外连接概率",
	"fixed_value": "固定种子值",
	"footprint_padding_cells": "占地外扩留白",
	"global": "全局配置",
	"global_corridors": "全局走廊",
	"global_distribution": "全局分布",
	"height_cells": "地图高度格数",
	"height_max": "最大高度",
	"height_min": "最小高度",
	"id": "配置 ID",
	"isolated_spawn_templates": "独立刷怪模板",
	"length_factor": "长度系数",
	"loot_table_id": "掉落表 ID",
	"main_room": "主房间",
	"main_room_roll": "主房间内容随机表",
	"map": "地图基础配置",
	"map_layers": "地图分层",
	"map_view": "地图预览",
	"max_alive_children": "最大存活子怪数",
	"max_cluster_size": "最大矿簇尺寸",
	"max_extra_connections": "最大额外连接数",
	"max_hit_points": "最大生命值",
	"max_radius_ratio": "最大半径比例",
	"max_torch_count": "最大火把数",
	"meta": "元数据",
	"min_cluster_size": "最小矿簇尺寸",
	"min_distance_between_cluster_seeds_cells": "矿簇种子最小间距",
	"min_distance_between_nests_cells": "巢穴最小间距",
	"min_distance_between_sites_cells": "点位最小间距",
	"min_distance_between_spawns_cells": "出生点最小间距",
	"min_distance_from_door_cells": "距门最小距离",
	"min_distance_from_other_pois_cells": "距其他 POI 最小距离",
	"min_distance_from_player_spawns_cells": "距玩家出生点最小距离",
	"min_gap_from_rooms_cells": "房间最小间隙",
	"mineral_budget_weight": "矿物预算权重",
	"minerals": "矿物配置",
	"mode": "模式",
	"monster_budget_weight": "怪物预算权重",
	"monster_entries": "怪物权重条目",
	"monster_generation": "怪物生成",
	"monster_id": "怪物 ID",
	"nest_entries": "巢穴权重条目",
	"nest_template_id": "巢穴模板 ID",
	"nest_templates": "巢穴模板列表",
	"nest_unit_id": "巢穴单位 ID",
	"noise_fill_percent": "噪声填充比例",
	"none_weight": "空结果权重",
	"notes": "备注",
	"placement": "放置配置",
	"placement_attempts_per_poi": "每个 POI 放置尝试次数",
	"placement_radius_max_cells": "最大放置半径",
	"placement_radius_min_cells": "最小放置半径",
	"player_spawn": "玩家出生点",
	"poi_attempts": "POI 尝试次数",
	"poi_budget_weight": "POI 预算权重",
	"poi_generation": "POI 生成",
	"poi_types": "POI 类型列表",
	"prefer_perimeter": "优先贴边",
	"radius_cells": "半径格数",
	"rays": "射线数量",
	"require_stone": "要求石头格",
	"retry_doorway_count": "门口重试次数",
	"reuse_existing_corridors": "复用已有走廊",
	"room_attempts": "房间尝试次数",
	"room_content_danger_multiplier": "房间内容危险倍率",
	"schema_version": "配置架构版本",
	"seed": "随机种子",
	"show_cluster_bounds": "显示矿簇边界",
	"show_corridor_doors": "显示走廊门",
	"show_poi_graph": "显示 POI 图",
	"show_room_labels": "显示房间标签",
	"show_spawn_sites": "显示刷怪点",
	"smooth_iterations": "平滑迭代次数",
	"spawn_interval_sec": "生成间隔秒数",
	"spawn_probability": "生成概率",
	"spawn_scope": "生成作用域",
	"spawn_template_id": "刷怪模板 ID",
	"stone_max_hit_points": "石头最大生命值",
	"style": "样式",
	"sub_room_roll": "子房间内容随机表",
	"sub_rooms": "子房间",
	"tags": "标签",
	"terrain": "地形配置",
	"tile_type_id": "格子类型 ID",
	"torch": "火把配置",
	"trace": "痕迹配置",
	"trap_budget_weight": "陷阱预算权重",
	"twist": "扭曲强度",
	"wall_inset_cells": "墙内缩距离",
	"weight": "权重",
	"width_cells": "地图宽度格数",
	"width_max": "最大宽度",
	"width_min": "最小宽度",
	"wobble_chance": "摇摆概率"
}
const PARAMETER_DESCRIPTIONS: Dictionary = {
	"map.width_cells": "生成地图的横向格子数量，会影响预览贴图宽度和实际地图尺寸。",
	"map.height_cells": "生成地图的纵向格子数量，会影响预览贴图高度和实际地图尺寸。",
	"map.seed.mode": "控制预览和生成使用随机种子还是固定种子。",
	"map.seed.fixed_value": "当种子模式为 fixed 时使用的固定种子值。",
	"map_layers": "以地图几何中心为圆心的内、中、外三层配置。",
	"map_layers[].max_radius_ratio": "该层覆盖的最大半径比例，数值越小越靠近地图中心。",
	"map_layers[].stone_max_hit_points": "该层普通石头和矿墙类格子的最大生命值。",
	"map_layers[].mineral_budget_weight": "该层获得矿物生成预算的相对权重。",
	"map_layers[].poi_budget_weight": "该层获得 POI 生成预算的相对权重。",
	"map_layers[].trap_budget_weight": "该层获得陷阱生成预算的相对权重。",
	"map_layers[].monster_budget_weight": "该层获得怪物点位预算的相对权重。",
	"map_layers[].room_content_danger_multiplier": "该层 POI 房间内容危险度倍率。",
	"terrain.noise_fill_percent": "基础噪声填充比例，影响洞穴墙体和空地的初始分布。",
	"terrain.smooth_iterations": "洞穴地形平滑迭代次数。",
	"minerals.global_distribution.base_candidate_chance": "普通墙成为矿物候选点的基础概率。",
	"minerals.global_distribution.exposed_wall_candidate_chance": "靠近空地的暴露墙成为矿物候选点的概率。",
	"poi_generation.poi_types[].count": "该 POI 模板希望生成的总数量。",
	"monster_generation.ambient_isolated_sites.attempts": "独立怪物点位的放置尝试次数。",
	"monster_generation.ambient_nests.attempts": "环境巢穴点位的放置尝试次数。"
}

var _config_selector: OptionButton = null
var _filename_input: LineEdit = null
var _editor_tabs: TabContainer = null
var _parameter_editor_root: VBoxContainer = null
var _parameter_fields: Dictionary = {}
var _config_editor: TextEdit = null
var _preview_viewport: Control = null
var _texture_rect: TextureRect = null
var _hover_cell_rect: ColorRect = null
var _hover_tile_label: Label = null
var _status_label: Label = null
var _seed_label: Label = null
var _current_config_filename: String = ""
var _current_config_dict: Dictionary = {}
var _preview_seed: int = 0
var _generator: WdcMapGenerationGenerator = GENERATOR_SCRIPT.new()
var _current_map_data: WdcMapGenerationTypes.MapData = null
var _preview_zoom: float = 1.0
var _preview_pan: Vector2 = Vector2.ZERO
var _preview_dragging: bool = false
var _preview_drag_start_mouse: Vector2 = Vector2.ZERO
var _preview_drag_start_pan: Vector2 = Vector2.ZERO
var _syncing_parameter_editor: bool = false
var _parameter_editor_dirty: bool = false
var _parameter_editor_parse_error: bool = false
var _syncing_config_editor: bool = false
var _config_editor_dirty: bool = false


func _ready() -> void:
	_build_ui()
	_load_config_list()
	_rebuild_preview(false)


func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	root.add_child(toolbar)
	_config_selector = OptionButton.new()
	_config_selector.custom_minimum_size = Vector2(260.0, 0.0)
	_config_selector.item_selected.connect(_on_config_selected)
	toolbar.add_child(_config_selector)
	_filename_input = LineEdit.new()
	_filename_input.placeholder_text = "config filename"
	_filename_input.custom_minimum_size = Vector2(220.0, 0.0)
	toolbar.add_child(_filename_input)
	var save_button: Button = Button.new()
	save_button.text = "Save Current Config"
	save_button.pressed.connect(_on_save_current_config_pressed)
	toolbar.add_child(save_button)
	var apply_button: Button = Button.new()
	apply_button.text = "Apply Editor Changes"
	apply_button.pressed.connect(_on_apply_config_editor_pressed)
	toolbar.add_child(apply_button)
	var rebuild_button: Button = Button.new()
	rebuild_button.text = "Rebuild Current Seed"
	rebuild_button.pressed.connect(_on_rebuild_current_seed_pressed)
	toolbar.add_child(rebuild_button)
	var random_button: Button = Button.new()
	random_button.text = "Rebuild Random Seed"
	random_button.pressed.connect(_on_rebuild_random_seed_pressed)
	toolbar.add_child(random_button)
	_seed_label = Label.new()
	toolbar.add_child(_seed_label)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)
	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	_editor_tabs = TabContainer.new()
	_editor_tabs.custom_minimum_size = Vector2(420.0, 520.0)
	_editor_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_tabs.tab_changed.connect(_on_editor_tab_changed)
	split.add_child(_editor_tabs)
	var parameter_scroll: ScrollContainer = ScrollContainer.new()
	parameter_scroll.name = "参数编辑"
	parameter_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parameter_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_tabs.add_child(parameter_scroll)
	_parameter_editor_root = VBoxContainer.new()
	_parameter_editor_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parameter_editor_root.add_theme_constant_override("separation", 6)
	parameter_scroll.add_child(_parameter_editor_root)
	_build_parameter_editor_controls()
	_config_editor = TextEdit.new()
	_config_editor.name = "JSON"
	_config_editor.custom_minimum_size = Vector2(420.0, 520.0)
	_config_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_config_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_config_editor.text_changed.connect(_on_config_editor_text_changed)
	_editor_tabs.add_child(_config_editor)
	var preview_panel: PanelContainer = PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.custom_minimum_size = Vector2(720.0, 520.0)
	split.add_child(preview_panel)
	_preview_viewport = Control.new()
	_preview_viewport.clip_contents = true
	_preview_viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_viewport.gui_input.connect(_on_preview_viewport_gui_input)
	_preview_viewport.mouse_exited.connect(_on_preview_viewport_mouse_exited)
	_preview_viewport.resized.connect(_on_preview_viewport_resized)
	preview_panel.add_child(_preview_viewport)
	_texture_rect = TextureRect.new()
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture_rect.custom_minimum_size = Vector2(720.0, 520.0)
	_preview_viewport.add_child(_texture_rect)
	_hover_cell_rect = ColorRect.new()
	_hover_cell_rect.color = Color(1.0, 1.0, 1.0, 0.25)
	_hover_cell_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_cell_rect.visible = false
	_preview_viewport.add_child(_hover_cell_rect)
	_hover_tile_label = Label.new()
	_hover_tile_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_tile_label.visible = false
	_hover_tile_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_hover_tile_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	_hover_tile_label.add_theme_constant_override("shadow_offset_x", 1)
	_hover_tile_label.add_theme_constant_override("shadow_offset_y", 1)
	_preview_viewport.add_child(_hover_tile_label)


func _build_parameter_editor_controls() -> void:
	if _parameter_editor_root == null:
		return
	for child: Node in _parameter_editor_root.get_children():
		child.queue_free()
	_parameter_fields.clear()
	_syncing_parameter_editor = true
	if _current_config_dict.is_empty():
		_add_parameter_group(_parameter_editor_root, "未加载配置", "未加载配置", 0, 0)
	else:
		_build_parameter_node(_parameter_editor_root, "", [], _current_config_dict, 0)
	_syncing_parameter_editor = false
	_parameter_editor_dirty = false


func _build_parameter_node(
	parent: VBoxContainer,
	field_key: String,
	json_path: Array,
	value: Variant,
	depth: int
) -> void:
	if value is Dictionary:
		var content_parent: VBoxContainer = parent
		if not field_key.is_empty():
			content_parent = _add_parameter_group(
				parent,
				_parameter_display_name(field_key),
				_build_parameter_tooltip(field_key),
				depth,
				(value as Dictionary).size()
			)
		var dict_value: Dictionary = value as Dictionary
		for key: Variant in dict_value.keys():
			var child_key: String = str(key)
			var child_path: Array = json_path.duplicate()
			child_path.append(child_key)
			var child_field_key: String = child_key if field_key.is_empty() else "%s.%s" % [field_key, child_key]
			_build_parameter_node(content_parent, child_field_key, child_path, dict_value[key], depth + 1)
		return
	if value is Array:
		var array_value: Array = value as Array
		var array_parent: VBoxContainer = _add_parameter_group(
			parent,
			"%s（%d 项）" % [_parameter_display_name(field_key), array_value.size()],
			_build_parameter_tooltip(field_key),
			depth,
			array_value.size()
		)
		for item_index: int in range(array_value.size()):
			var item_path: Array = json_path.duplicate()
			item_path.append(item_index)
			var item_field_key: String = "%s[%d]" % [field_key, item_index]
			_build_parameter_node(array_parent, item_field_key, item_path, array_value[item_index], depth + 1)
		return
	_add_variant_parameter(parent, field_key, json_path, value, depth)


func _add_parameter_group(
	parent: VBoxContainer,
	title: String,
	tooltip: String,
	depth: int,
	child_count: int
) -> VBoxContainer:
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", maxi(depth - 1, 0) * 9)
	parent.add_child(margin)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_group_style(depth))
	margin.add_child(panel)
	var panel_box: VBoxContainer = VBoxContainer.new()
	panel_box.add_theme_constant_override("separation", 4)
	panel.add_child(panel_box)
	var header: Button = Button.new()
	var open_title: String = "▼ %s" % title
	var closed_title: String = "▶ %s" % title
	if child_count > 0:
		open_title = "%s  ·  %d 项" % [open_title, child_count]
		closed_title = "%s  ·  %d 项" % [closed_title, child_count]
	header.text = open_title
	header.tooltip_text = tooltip
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	panel_box.add_child(header)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	panel_box.add_child(content)
	header.pressed.connect(_on_parameter_group_header_pressed.bind(header, content, open_title, closed_title))
	return content


func _add_variant_parameter(
	parent: VBoxContainer,
	field_key: String,
	json_path: Array,
	value: Variant,
	depth: int
) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label: Label = Label.new()
	label.text = _parameter_display_name(field_key)
	label.tooltip_text = _build_parameter_tooltip(field_key)
	label.custom_minimum_size = Vector2(230.0, 0.0)
	row.add_child(label)
	var control: Control = _create_parameter_value_control(field_key, json_path, value)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	_parameter_fields[field_key] = control


func _create_parameter_value_control(field_key: String, json_path: Array, value: Variant) -> Control:
	var value_type: int = typeof(value)
	match value_type:
		TYPE_BOOL:
			var checkbox: CheckBox = CheckBox.new()
			checkbox.button_pressed = bool(value)
			checkbox.toggled.connect(_on_parameter_bool_toggled.bind(field_key))
			_configure_parameter_control(checkbox, json_path, "bool", field_key)
			return checkbox
		TYPE_INT:
			var int_spin_box: SpinBox = SpinBox.new()
			int_spin_box.min_value = -1000000.0
			int_spin_box.max_value = 1000000.0
			int_spin_box.step = 1.0
			int_spin_box.value = float(value)
			int_spin_box.value_changed.connect(_on_parameter_field_value_changed.bind(field_key))
			_configure_parameter_control(int_spin_box, json_path, "int", field_key)
			return int_spin_box
		TYPE_FLOAT:
			var float_spin_box: SpinBox = SpinBox.new()
			float_spin_box.min_value = -1000000.0
			float_spin_box.max_value = 1000000.0
			float_spin_box.step = 0.01
			float_spin_box.value = float(value)
			float_spin_box.value_changed.connect(_on_parameter_field_value_changed.bind(field_key))
			_configure_parameter_control(float_spin_box, json_path, "float", field_key)
			return float_spin_box
		TYPE_STRING:
			var line_edit: LineEdit = LineEdit.new()
			line_edit.text = str(value)
			line_edit.text_changed.connect(_on_parameter_text_changed.bind(field_key))
			_configure_parameter_control(line_edit, json_path, "string", field_key)
			return line_edit
	var text_edit: TextEdit = TextEdit.new()
	text_edit.custom_minimum_size = Vector2(240.0, 70.0)
	text_edit.text = JSON.stringify(value, "  ")
	text_edit.text_changed.connect(_on_parameter_json_text_changed.bind(field_key))
	_configure_parameter_control(text_edit, json_path, "json", field_key)
	return text_edit


func _configure_parameter_control(
	control: Control,
	json_path: Array,
	value_kind: String,
	field_key: String,
) -> void:
	control.tooltip_text = ""
	control.set_meta("json_path", json_path.duplicate())
	control.set_meta("value_kind", value_kind)


func _make_group_style(depth: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	var shade: float = clampf(0.12 + float(depth) * 0.025, 0.12, 0.24)
	style.bg_color = Color(shade, shade, shade, 1.0)
	style.border_color = Color(0.34, 0.34, 0.34, 1.0)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 14.0 + float(maxi(depth - 1, 0)) * 2.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 6.0
	return style


func _on_parameter_group_header_pressed(
	header: Button,
	content: Control,
	open_title: String,
	closed_title: String
) -> void:
	content.visible = not content.visible
	header.text = open_title if content.visible else closed_title


func _parameter_display_name(field_key: String) -> String:
	var leaf: String = _leaf_name(field_key)
	var index: int = _trailing_array_index(leaf)
	if index >= 0:
		var base_name: String = leaf.substr(0, leaf.find("["))
		var base_label: String = _parameter_key_label(base_name)
		return "%s 第 %d 项" % [base_label, index + 1]
	return _parameter_key_label(leaf)


func _leaf_name(field_key: String) -> String:
	var dot_index: int = field_key.rfind(".")
	if dot_index >= 0:
		return field_key.substr(dot_index + 1)
	return field_key


func _trailing_array_index(text: String) -> int:
	var start_index: int = text.rfind("[")
	var end_index: int = text.rfind("]")
	if start_index < 0 or end_index <= start_index:
		return -1
	return int(text.substr(start_index + 1, end_index - start_index - 1))


func _parameter_key_label(key: String) -> String:
	var base_key: String = key
	var bracket_index: int = base_key.find("[")
	if bracket_index >= 0:
		base_key = base_key.substr(0, bracket_index)
	if PARAMETER_LABELS.has(base_key):
		return str(PARAMETER_LABELS[base_key])
	return "配置项"


func _build_parameter_tooltip(field_key: String) -> String:
	var normalized_key: String = _normalize_parameter_path(field_key)
	var description: String = ""
	if PARAMETER_DESCRIPTIONS.has(normalized_key):
		description = str(PARAMETER_DESCRIPTIONS[normalized_key])
	elif PARAMETER_DESCRIPTIONS.has(_leaf_name(normalized_key)):
		description = str(PARAMETER_DESCRIPTIONS[_leaf_name(normalized_key)])
	else:
		description = "用于配置“%s”对应的 generated-map 参数。" % _parameter_display_name(field_key)
	return "%s\n英文名：%s" % [description, field_key]


func _normalize_parameter_path(field_key: String) -> String:
	var normalized: String = ""
	var cursor: int = 0
	while cursor < field_key.length():
		var index_start: int = field_key.find("[", cursor)
		if index_start < 0:
			normalized += field_key.substr(cursor)
			break
		normalized += field_key.substr(cursor, index_start - cursor)
		var index_end: int = field_key.find("]", index_start)
		if index_end < 0:
			normalized += field_key.substr(index_start)
			break
		normalized += "[]"
		cursor = index_end + 1
	return normalized


func _load_config_list() -> void:
	_config_selector.clear()
	var configs: Array[Dictionary] = CONFIG_CATALOG.list_available_configs()
	for config_entry: Dictionary in configs:
		var filename: String = str(config_entry.get("filename", ""))
		_config_selector.add_item(str(config_entry.get("display_name", filename)))
		_config_selector.set_item_metadata(_config_selector.item_count - 1, filename)
	if _config_selector.item_count > 0:
		_config_selector.select(0)
		_current_config_filename = str(_config_selector.get_item_metadata(0))
		_filename_input.text = _current_config_filename
		_load_current_config_into_editor()


func _on_config_selected(index: int) -> void:
	_current_config_filename = str(_config_selector.get_item_metadata(index))
	_filename_input.text = _current_config_filename
	_preview_seed = 0
	_load_current_config_into_editor()
	_rebuild_preview(false)


func _on_save_current_config_pressed() -> void:
	if not _sync_current_config_from_editor():
		return
	var filename: String = CONFIG_CATALOG.normalize_config_filename_input(_filename_input.text)
	if filename.is_empty():
		_set_status("Save failed: empty filename")
		return
	var path: String = CONFIG_CATALOG.build_config_resource_path(filename)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Save failed: %s" % path)
		return
	file.store_string(JSON.stringify(_current_config_dict, "  "))
	file.flush()
	file = null
	_current_config_filename = filename
	_filename_input.text = filename
	_set_status("Saved: %s" % path)
	_load_config_list()
	for item_index: int in range(_config_selector.item_count):
		if str(_config_selector.get_item_metadata(item_index)) == filename:
			_config_selector.select(item_index)
			break


func _on_apply_config_editor_pressed() -> void:
	if not _sync_current_config_from_editor():
		return
	_preview_seed = 0
	_rebuild_preview(false)


func _on_rebuild_current_seed_pressed() -> void:
	_rebuild_preview(false)


func _on_rebuild_random_seed_pressed() -> void:
	_rebuild_preview(true)


func _rebuild_preview(randomize_seed: bool) -> void:
	if not _sync_current_config_from_editor():
		return
	if _current_config_dict.is_empty():
		_set_status("Preview failed: missing config")
		return
	var map_config: WdcMapGenerationTypes.MapConfig = MAP_TYPES.MapConfig.new()
	CONFIG_CATALOG.apply_config_dict_to_legacy_map_config(map_config, _current_config_dict)
	map_config.seed = _resolve_preview_seed(_current_config_dict, randomize_seed)
	var map_data: WdcMapGenerationTypes.MapData = _generator.generate_full(map_config)
	if map_data == null:
		_set_status("Preview failed: generator returned null")
		return
	_current_map_data = map_data
	_preview_seed = _generator.last_resolved_seed
	_texture_rect.texture = ImageTexture.create_from_image(_build_map_preview_image(map_data))
	_fit_preview_to_viewport()
	_seed_label.text = "Seed: %d" % _preview_seed
	_set_status(
		"Preview rebuilt: file=%s size=%sx%s"
		% [_current_config_filename, map_data.width, map_data.height]
	)


func _fit_preview_to_viewport() -> void:
	if _preview_viewport == null or _texture_rect == null or _current_map_data == null:
		return
	if _preview_viewport.size.x <= 1.0 or _preview_viewport.size.y <= 1.0:
		call_deferred("_fit_preview_to_viewport")
		return
	var map_size: Vector2 = Vector2(float(_current_map_data.width), float(_current_map_data.height))
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		return
	_preview_zoom = maxf(minf(_preview_viewport.size.x / map_size.x, _preview_viewport.size.y / map_size.y), 1.0)
	_preview_pan = (_preview_viewport.size - map_size * _preview_zoom) * 0.5
	_apply_preview_transform()
	_hide_hover_cell()


func _apply_preview_transform() -> void:
	if _texture_rect == null or _current_map_data == null:
		return
	_texture_rect.position = _preview_pan
	_texture_rect.size = Vector2(float(_current_map_data.width), float(_current_map_data.height)) * _preview_zoom


func _on_preview_viewport_resized() -> void:
	_fit_preview_to_viewport()


func _on_preview_viewport_gui_input(event: InputEvent) -> void:
	if _current_map_data == null:
		return
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_zoom_preview_at(mouse_button.position, _preview_zoom * 1.18)
			_update_hover_from_mouse(mouse_button.position)
			return
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_zoom_preview_at(mouse_button.position, _preview_zoom / 1.18)
			_update_hover_from_mouse(mouse_button.position)
			return
		if mouse_button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_preview_dragging = mouse_button.pressed
			_preview_drag_start_mouse = mouse_button.position
			_preview_drag_start_pan = _preview_pan
			if not _preview_dragging:
				_update_hover_from_mouse(mouse_button.position)
			return
	if event is InputEventMouseMotion:
		var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _preview_dragging:
			_preview_pan = _preview_drag_start_pan + mouse_motion.position - _preview_drag_start_mouse
			_clamp_preview_pan()
			_apply_preview_transform()
		_update_hover_from_mouse(mouse_motion.position)


func _zoom_preview_at(mouse_position: Vector2, new_zoom: float) -> void:
	if _current_map_data == null:
		return
	var old_zoom: float = maxf(_preview_zoom, 0.001)
	var map_local: Vector2 = (mouse_position - _preview_pan) / old_zoom
	_preview_zoom = clampf(new_zoom, 1.0, 48.0)
	_preview_pan = mouse_position - map_local * _preview_zoom
	_clamp_preview_pan()
	_apply_preview_transform()


func _clamp_preview_pan() -> void:
	if _preview_viewport == null or _current_map_data == null:
		return
	var display_size: Vector2 = Vector2(float(_current_map_data.width), float(_current_map_data.height)) * _preview_zoom
	if display_size.x <= _preview_viewport.size.x:
		_preview_pan.x = (_preview_viewport.size.x - display_size.x) * 0.5
	else:
		_preview_pan.x = clampf(_preview_pan.x, _preview_viewport.size.x - display_size.x, 0.0)
	if display_size.y <= _preview_viewport.size.y:
		_preview_pan.y = (_preview_viewport.size.y - display_size.y) * 0.5
	else:
		_preview_pan.y = clampf(_preview_pan.y, _preview_viewport.size.y - display_size.y, 0.0)


func _on_preview_viewport_mouse_exited() -> void:
	_preview_dragging = false
	_hide_hover_cell()


func _update_hover_from_mouse(mouse_position: Vector2) -> void:
	var cell: Vector2i = _map_cell_from_preview_mouse(mouse_position)
	if cell.x < 0:
		_hide_hover_cell()
		return
	var image_y: int = _current_map_data.height - 1 - cell.y
	_hover_cell_rect.position = _preview_pan + Vector2(float(cell.x), float(image_y)) * _preview_zoom
	_hover_cell_rect.size = Vector2.ONE * maxf(_preview_zoom, 1.0)
	_hover_cell_rect.visible = true
	var cell_data: WdcMapGenerationTypes.CellData = _current_map_data.get_cell(cell.x, cell.y)
	_hover_tile_label.text = "(%d, %d) %s" % [cell.x, cell.y, _resolve_cell_display_name(cell_data)]
	_hover_tile_label.position = _fit_hover_label_position(mouse_position + Vector2(12.0, 12.0))
	_hover_tile_label.visible = true


func _map_cell_from_preview_mouse(mouse_position: Vector2) -> Vector2i:
	if _current_map_data == null or _preview_zoom <= 0.0:
		return Vector2i(-1, -1)
	var image_position: Vector2 = (mouse_position - _preview_pan) / _preview_zoom
	var image_x: int = int(floor(image_position.x))
	var image_y: int = int(floor(image_position.y))
	if image_x < 0 or image_y < 0 or image_x >= _current_map_data.width or image_y >= _current_map_data.height:
		return Vector2i(-1, -1)
	return Vector2i(image_x, _current_map_data.height - 1 - image_y)


func _fit_hover_label_position(target_position: Vector2) -> Vector2:
	if _hover_tile_label == null or _preview_viewport == null:
		return target_position
	var label_size: Vector2 = _hover_tile_label.get_minimum_size()
	var fitted: Vector2 = target_position
	if fitted.x + label_size.x > _preview_viewport.size.x:
		fitted.x = maxf(0.0, _preview_viewport.size.x - label_size.x - 8.0)
	if fitted.y + label_size.y > _preview_viewport.size.y:
		fitted.y = maxf(0.0, _preview_viewport.size.y - label_size.y - 8.0)
	return fitted


func _hide_hover_cell() -> void:
	if _hover_cell_rect != null:
		_hover_cell_rect.visible = false
	if _hover_tile_label != null:
		_hover_tile_label.visible = false


func _resolve_cell_display_name(cell: WdcMapGenerationTypes.CellData) -> String:
	if cell == null:
		return "未知方块"
	match cell.special_block_type:
		WdcMapGenerationTypes.SpecialBlockType.RARE_MINERAL:
			return "稀有矿墙"
		WdcMapGenerationTypes.SpecialBlockType.TURQUOISE:
			return "绿松石矿"
		WdcMapGenerationTypes.SpecialBlockType.AMETHYST:
			return "紫水晶矿"
		WdcMapGenerationTypes.SpecialBlockType.GOLD:
			return "金矿块"
		WdcMapGenerationTypes.SpecialBlockType.POI_WALL:
			return "POI 墙体"
		WdcMapGenerationTypes.SpecialBlockType.SPIKE:
			return "尖刺陷阱"
		WdcMapGenerationTypes.SpecialBlockType.EXPLOSIVE_ORE:
			return "爆炸矿陷阱"
		WdcMapGenerationTypes.SpecialBlockType.ARROW_SLIT:
			return "箭孔陷阱"
		WdcMapGenerationTypes.SpecialBlockType.PRESSURE_PLATE:
			return "压力板陷阱"
	if cell.has_mineral:
		return "普通矿墙"
	if cell.cell_type == WdcMapGenerationTypes.CellType.FLOOR:
		match cell.poi_type:
			WdcMapGenerationTypes.PoiType.LARGE_RUIN:
				return "大型 POI 地面"
			WdcMapGenerationTypes.PoiType.MEDIUM_BIOME:
				return "中型 POI 地面"
			WdcMapGenerationTypes.PoiType.SMALL_ORE:
				return "小型 POI 地面"
		return "空地"
	if cell.trace_type != WdcMapGenerationTypes.PoiType.NONE:
		return "POI 痕迹墙"
	return "普通石头"


func _resolve_preview_seed(config_dict: Dictionary, randomize_seed: bool) -> int:
	if randomize_seed:
		return _random_seed()
	if _preview_seed > 0:
		return _preview_seed
	if CONFIG_CATALOG.extract_seed_mode(config_dict) == "fixed":
		return maxi(CONFIG_CATALOG.extract_fixed_seed(config_dict), 1)
	return _random_seed()


func _random_seed() -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var resolved: int = int(rng.randi() & 0x7fffffff)
	if resolved == 0:
		resolved = int(Time.get_ticks_usec() & 0x7fffffff)
	return maxi(resolved, 1)


func _build_map_preview_image(map_data: WdcMapGenerationTypes.MapData) -> Image:
	var image: Image = Image.create(map_data.width, map_data.height, false, Image.FORMAT_RGBA8)
	for y: int in range(map_data.height):
		for x: int in range(map_data.width):
			image.set_pixel(x, map_data.height - 1 - y, _resolve_map_cell_color(map_data.get_cell(x, y)))
	for poi_center_value: Variant in map_data.poi_centers:
		if poi_center_value is Dictionary:
			var poi_center: Dictionary = poi_center_value as Dictionary
			_paint_cross(image, Vector2i(int(poi_center.get("x", 0)), int(poi_center.get("y", 0))), COLOR_GOLD, map_data.height)
	for site_value: Variant in map_data.monster_sites:
		if site_value is Dictionary:
			var site: Dictionary = site_value as Dictionary
			var site_color: Color = COLOR_NEST_SITE if str(site.get("site_kind", "")) == "nest" else COLOR_MONSTER_SITE
			_paint_cross(image, _vector2i_from_variant(site.get("cell", Vector2i.ZERO)), site_color, map_data.height)
	for trap_site_value: Variant in map_data.trap_sites:
		if trap_site_value is Dictionary:
			var trap_site: Dictionary = trap_site_value as Dictionary
			if str(trap_site.get("trap_kind", "")) == "explosive_ore_chain":
				for node_value: Variant in trap_site.get("nodes", []) as Array:
					_paint_cross(image, _vector2i_from_variant(node_value), COLOR_TRAP, map_data.height)
			else:
				_paint_cross(image, _vector2i_from_variant(trap_site.get("cell", Vector2i.ZERO)), COLOR_TRAP, map_data.height)
	return image


func _resolve_map_cell_color(cell: WdcMapGenerationTypes.CellData) -> Color:
	if cell == null:
		return COLOR_WALL
	if cell.poi_type == WdcMapGenerationTypes.PoiType.NONE and cell.trace_type != WdcMapGenerationTypes.PoiType.NONE:
		return _resolve_trace_color(cell.trace_type)
	if cell.special_block_type != WdcMapGenerationTypes.SpecialBlockType.NONE:
		match cell.special_block_type:
			WdcMapGenerationTypes.SpecialBlockType.RARE_MINERAL:
				return _apply_durability_shade(COLOR_RARE_MINERAL, cell)
			WdcMapGenerationTypes.SpecialBlockType.TURQUOISE:
				return _apply_durability_shade(COLOR_TURQUOISE, cell)
			WdcMapGenerationTypes.SpecialBlockType.AMETHYST:
				return _apply_durability_shade(COLOR_AMETHYST, cell)
			WdcMapGenerationTypes.SpecialBlockType.GOLD:
				return _apply_durability_shade(COLOR_GOLD, cell)
			WdcMapGenerationTypes.SpecialBlockType.POI_WALL:
				return COLOR_POI_WALL
	if cell.has_mineral:
		return _apply_durability_shade(COLOR_MINERAL_WALL, cell)
	if cell.cell_type == WdcMapGenerationTypes.CellType.FLOOR:
		match cell.poi_type:
			WdcMapGenerationTypes.PoiType.LARGE_RUIN:
				return COLOR_POI_LARGE
			WdcMapGenerationTypes.PoiType.MEDIUM_BIOME:
				return COLOR_POI_MEDIUM
			WdcMapGenerationTypes.PoiType.SMALL_ORE:
				return COLOR_POI_SMALL
		return COLOR_FLOOR
	match cell.trace_type:
		WdcMapGenerationTypes.PoiType.LARGE_RUIN:
			return COLOR_TRACE_LARGE
		WdcMapGenerationTypes.PoiType.MEDIUM_BIOME:
			return COLOR_TRACE_MEDIUM
		WdcMapGenerationTypes.PoiType.SMALL_ORE:
			return COLOR_TRACE_SMALL
	return _apply_durability_shade(COLOR_WALL, cell)


func _load_current_config_into_editor() -> void:
	if _current_config_filename.is_empty():
		_current_config_dict.clear()
		_populate_parameter_editor_from_config()
		_set_config_editor_text("")
		return
	var config_dict: Dictionary = CONFIG_CATALOG.load_config_dict_by_filename(_current_config_filename)
	_current_config_dict = config_dict.duplicate(true) if not config_dict.is_empty() else {}
	_populate_parameter_editor_from_config()
	_set_config_editor_text(JSON.stringify(_current_config_dict, "  ") if not _current_config_dict.is_empty() else "")


func _set_config_editor_text(text_value: String) -> void:
	if _config_editor == null:
		return
	_syncing_config_editor = true
	_config_editor.text = text_value
	_syncing_config_editor = false
	_config_editor_dirty = false


func _on_config_editor_text_changed() -> void:
	if _syncing_config_editor:
		return
	_config_editor_dirty = true


func _on_parameter_field_value_changed(_value: float, _field_key: String) -> void:
	if _syncing_parameter_editor:
		return
	_parameter_editor_dirty = true


func _on_parameter_bool_toggled(_value: bool, _field_key: String) -> void:
	if _syncing_parameter_editor:
		return
	_parameter_editor_dirty = true


func _on_parameter_text_changed(_value: String, _field_key: String) -> void:
	if _syncing_parameter_editor:
		return
	_parameter_editor_dirty = true


func _on_parameter_json_text_changed(_field_key: String) -> void:
	if _syncing_parameter_editor:
		return
	_parameter_editor_dirty = true


func _on_editor_tab_changed(tab_index: int) -> void:
	if tab_index == EDITOR_TAB_PARAMETERS:
		if _config_editor_dirty and _sync_current_config_from_json_editor():
			_populate_parameter_editor_from_config()
		return
	if tab_index == EDITOR_TAB_JSON:
		if _parameter_editor_dirty:
			_sync_current_config_from_parameter_editor()
		elif not _current_config_dict.is_empty():
			_set_config_editor_text(JSON.stringify(_current_config_dict, "  "))


func _sync_current_config_from_editor() -> bool:
	if _editor_tabs != null and _editor_tabs.current_tab == EDITOR_TAB_PARAMETERS:
		return _sync_current_config_from_parameter_editor()
	return _sync_current_config_from_json_editor()


func _sync_current_config_from_json_editor() -> bool:
	if _config_editor == null:
		if _current_config_dict.is_empty():
			_load_current_config_into_editor()
		return not _current_config_dict.is_empty()
	var raw_text: String = _config_editor.text.strip_edges()
	if raw_text.is_empty():
		_set_status("Preview failed: empty config JSON")
		return false
	var parsed: Variant = JSON.parse_string(raw_text)
	if not (parsed is Dictionary):
		_set_status("Preview failed: invalid config JSON")
		return false
	_current_config_dict = (parsed as Dictionary).duplicate(true)
	_config_editor_dirty = false
	_populate_parameter_editor_from_config()
	return true


func _sync_current_config_from_parameter_editor() -> bool:
	if _parameter_fields.is_empty():
		if _current_config_dict.is_empty():
			_load_current_config_into_editor()
		return not _current_config_dict.is_empty()
	if _current_config_dict.is_empty():
		_set_status("Preview failed: missing config")
		return false
	var config_dict: Dictionary = _current_config_dict.duplicate(true)
	_parameter_editor_parse_error = false
	for field_key: Variant in _parameter_fields.keys():
		var control: Control = _parameter_fields[field_key] as Control
		if control == null:
			continue
		var json_path: Array = control.get_meta("json_path", []) as Array
		if json_path.is_empty():
			continue
		var value: Variant = _read_parameter_control_value(control, str(field_key))
		if _parameter_editor_parse_error:
			return false
		_set_value_at_json_path(config_dict, json_path, value)
	_current_config_dict = config_dict
	_parameter_editor_dirty = false
	_set_config_editor_text(JSON.stringify(_current_config_dict, "  "))
	return true


func _populate_parameter_editor_from_config() -> void:
	_build_parameter_editor_controls()


func _read_parameter_control_value(control: Control, field_key: String) -> Variant:
	var value_kind: String = str(control.get_meta("value_kind", "json"))
	match value_kind:
		"bool":
			return (control as CheckBox).button_pressed
		"int":
			return int(round((control as SpinBox).value))
		"float":
			return float((control as SpinBox).value)
		"string":
			return (control as LineEdit).text
		"json":
			var json_parser: JSON = JSON.new()
			var error: Error = json_parser.parse((control as TextEdit).text)
			if error != OK:
				_parameter_editor_parse_error = true
				_set_status("Preview failed: invalid JSON value at %s" % field_key)
				return null
			return json_parser.data
	return null


func _set_value_at_json_path(root: Variant, json_path: Array, value: Variant) -> void:
	var cursor: Variant = root
	for path_index: int in range(json_path.size() - 1):
		var path_part: Variant = json_path[path_index]
		if path_part is int:
			cursor = (cursor as Array)[int(path_part)]
		else:
			cursor = (cursor as Dictionary)[str(path_part)]
	var last_part: Variant = json_path[json_path.size() - 1]
	if last_part is int:
		var array_cursor: Array = cursor as Array
		array_cursor[int(last_part)] = value
	else:
		var dict_cursor: Dictionary = cursor as Dictionary
		dict_cursor[str(last_part)] = value


func _apply_durability_shade(base_color: Color, cell: WdcMapGenerationTypes.CellData) -> Color:
	var max_hit_points: int = TILE_RULES.get_cell_max_hit_points(cell)
	var darkness: float = clampf(float(max_hit_points - 1) / 4.0, 0.0, 1.0) * 0.58
	return base_color.darkened(darkness)


func _resolve_trace_color(trace_type: int) -> Color:
	match trace_type:
		WdcMapGenerationTypes.PoiType.LARGE_RUIN:
			return COLOR_TRACE_LARGE
		WdcMapGenerationTypes.PoiType.MEDIUM_BIOME:
			return COLOR_TRACE_MEDIUM
		WdcMapGenerationTypes.PoiType.SMALL_ORE:
			return COLOR_TRACE_SMALL
	return COLOR_WALL


func _paint_cross(image: Image, cell: Vector2i, color: Color, map_height: int) -> void:
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var target: Vector2i = cell + offset
		if target.x < 0 or target.y < 0 or target.x >= image.get_width() or target.y >= image.get_height():
			continue
		image.set_pixel(target.x, map_height - 1 - target.y, color)


func _vector2i_from_variant(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Dictionary:
		var dict_value: Dictionary = value as Dictionary
		return Vector2i(int(dict_value.get("x", 0)), int(dict_value.get("y", 0)))
	return Vector2i.ZERO


func _set_status(text_value: String) -> void:
	if _status_label != null:
		_status_label.text = text_value
