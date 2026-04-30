extends SceneTree

const CONFIG_CATALOG = preload("../../config/data_generated_map_config_catalog.gd")
const MAP_TYPES = preload("../../core/generated_map_types.gd")
const GENERATOR_SCRIPT = preload("../../core/generated_map_generator.gd")
const PREVIEW_SCENE = preload("../../preview/scenes/map_generation_preview.tscn")
const WdcMapGenerationTypes = MAP_TYPES
const WdcMapGenerationGenerator = GENERATOR_SCRIPT


func _init() -> void:
	var configs: Array[Dictionary] = CONFIG_CATALOG.list_available_configs()
	if configs.is_empty():
		push_error("map_generation_preview_smoke: missing generated-map configs")
		quit(1)
		return
	var config_dict: Dictionary = CONFIG_CATALOG.load_config_dict_by_filename(
		configs[0].get("filename", "")
	)
	var config: WdcMapGenerationTypes.MapConfig = MAP_TYPES.MapConfig.new()
	CONFIG_CATALOG.apply_config_dict_to_legacy_map_config(config, config_dict)
	config.seed = 12345
	var generator: WdcMapGenerationGenerator = GENERATOR_SCRIPT.new()
	var map_data: WdcMapGenerationTypes.MapData = generator.generate_full(config)
	if map_data == null or map_data.width <= 0 or map_data.height <= 0:
		push_error("map_generation_preview_smoke: generated map is empty")
		quit(1)
		return
	var preview_node: Node = PREVIEW_SCENE.instantiate()
	if preview_node == null:
		push_error("map_generation_preview_smoke: preview scene did not instantiate")
		quit(1)
		return
	root.add_child(preview_node)
	print("map_generation_preview_smoke: PASS %sx%s seed=%s" % [map_data.width, map_data.height, generator.last_resolved_seed])
	quit(0)
