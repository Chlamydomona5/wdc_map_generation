extends SceneTree

const CONFIG_CATALOG = preload("../../config/data_generated_map_config_catalog.gd")
const MAP_TYPES = preload("../../core/generated_map_types.gd")
const GENERATOR_SCRIPT = preload("../../core/generated_map_generator.gd")
const PREVIEW_SCENE = preload("../../preview/scenes/map_generation_preview.tscn")
const WdcMapGenerationTypes = MAP_TYPES
const WdcMapGenerationGenerator = GENERATOR_SCRIPT


func _init() -> void:
	var implicit_config: WdcMapGenerationTypes.MapConfig = MAP_TYPES.MapConfig.new()
	CONFIG_CATALOG.apply_config_dict_to_legacy_map_config(implicit_config, {"map": {}})
	implicit_config.normalize()
	if (
		implicit_config.player_spawn_count != 1
		or implicit_config.extraction_site_count != 1
		or str(implicit_config.extraction_site_layer_distribution[0].get("layer_id", "")) != "inner"
	):
		push_error("map_generation_preview_smoke: 缺失站点字段的默认归一化不一致")
		quit(1)
		return
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
	if (
		config.player_spawn_count != 1
		or map_data.player_spawn_points.size() != 1
		or str(map_data.player_spawn_points[0].get("layer_id", "")) != "outer"
		or config.extraction_site_count != 1
		or map_data.extraction_sites.size() != 1
		or str(map_data.extraction_sites[0].get("layer_id", "")) != "inner"
	):
		push_error("map_generation_preview_smoke: 正式配置站点摘要不是单外围出生点与单内圈撤离点")
		quit(1)
		return
	var preview_node: Node = PREVIEW_SCENE.instantiate()
	if preview_node == null:
		push_error("map_generation_preview_smoke: preview scene did not instantiate")
		quit(1)
		return
	root.add_child(preview_node)
	var site_summary_value: Variant = preview_node.call("_build_site_status_summary", map_data)
	if not (site_summary_value is Dictionary):
		push_error("map_generation_preview_smoke: 预览站点摘要不可用")
		quit(1)
		return
	var site_summary: Dictionary = site_summary_value as Dictionary
	if (
		int(site_summary.get("spawn_count", 0)) != 1
		or int(site_summary.get("extraction_count", 0)) != 1
		or int(site_summary.get("inner_count", 0)) != 1
		or int(site_summary.get("middle_count", 0)) != 0
	):
		push_error("map_generation_preview_smoke: 预览站点摘要数量或层级错误")
		quit(1)
		return
	print("map_generation_preview_smoke: PASS %sx%s seed=%s" % [map_data.width, map_data.height, generator.last_resolved_seed])
	quit(0)
