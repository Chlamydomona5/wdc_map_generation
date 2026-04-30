extends Control

const CONFIG_CATALOG = preload("../../config/data_generated_map_config_catalog.gd")
const MAP_TYPES = preload("../../core/generated_map_types.gd")
const GENERATOR_SCRIPT = preload("../../core/generated_map_generator.gd")

const COLOR_FLOOR: Color = Color(0.18, 0.18, 0.18, 1.0)
const COLOR_WALL: Color = Color(0.06, 0.06, 0.06, 1.0)
const COLOR_MINERAL_WALL: Color = Color(0.18, 0.35, 0.45, 1.0)
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

var _config_selector: OptionButton = null
var _filename_input: LineEdit = null
var _texture_rect: TextureRect = null
var _status_label: Label = null
var _seed_label: Label = null
var _current_config_filename: String = ""
var _current_config_dict: Dictionary = {}
var _preview_seed: int = 0
var _generator: WdcMapGenerationGenerator = GENERATOR_SCRIPT.new()


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
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	_texture_rect = TextureRect.new()
	_texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(_texture_rect)


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


func _on_config_selected(index: int) -> void:
	_current_config_filename = str(_config_selector.get_item_metadata(index))
	_filename_input.text = _current_config_filename
	_preview_seed = 0
	_rebuild_preview(false)


func _on_save_current_config_pressed() -> void:
	if _current_config_dict.is_empty():
		_set_status("Save failed: no current config")
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
	_current_config_filename = filename
	_filename_input.text = filename
	_set_status("Saved: %s" % path)
	_load_config_list()
	for item_index: int in range(_config_selector.item_count):
		if str(_config_selector.get_item_metadata(item_index)) == filename:
			_config_selector.select(item_index)
			break


func _on_rebuild_current_seed_pressed() -> void:
	_rebuild_preview(false)


func _on_rebuild_random_seed_pressed() -> void:
	_rebuild_preview(true)


func _rebuild_preview(randomize_seed: bool) -> void:
	if _current_config_filename.is_empty():
		_set_status("Preview failed: missing config")
		return
	var config_dict: Dictionary = CONFIG_CATALOG.load_config_dict_by_filename(_current_config_filename)
	if config_dict.is_empty():
		_set_status("Preview failed: missing config %s" % _current_config_filename)
		return
	_current_config_dict = config_dict.duplicate(true)
	var map_config: WdcMapGenerationTypes.MapConfig = MAP_TYPES.MapConfig.new()
	CONFIG_CATALOG.apply_config_dict_to_legacy_map_config(map_config, config_dict)
	map_config.seed = _resolve_preview_seed(config_dict, randomize_seed)
	var map_data: WdcMapGenerationTypes.MapData = _generator.generate_full(map_config)
	if map_data == null:
		_set_status("Preview failed: generator returned null")
		return
	_preview_seed = _generator.last_resolved_seed
	_texture_rect.texture = ImageTexture.create_from_image(_build_map_preview_image(map_data))
	_seed_label.text = "Seed: %d" % _preview_seed
	_set_status(
		"Preview rebuilt: file=%s size=%sx%s"
		% [_current_config_filename, map_data.width, map_data.height]
	)


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
				return COLOR_RARE_MINERAL
			WdcMapGenerationTypes.SpecialBlockType.TURQUOISE:
				return COLOR_TURQUOISE
			WdcMapGenerationTypes.SpecialBlockType.AMETHYST:
				return COLOR_AMETHYST
			WdcMapGenerationTypes.SpecialBlockType.GOLD:
				return COLOR_GOLD
			WdcMapGenerationTypes.SpecialBlockType.POI_WALL:
				return COLOR_POI_WALL
	if cell.has_mineral:
		return COLOR_MINERAL_WALL
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
	return COLOR_WALL


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
