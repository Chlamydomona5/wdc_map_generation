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
	if not _test_four_region_preview(preview_node):
		quit(1)
		return
	print("map_generation_preview_smoke: PASS %sx%s seed=%s" % [map_data.width, map_data.height, generator.last_resolved_seed])
	quit(0)


func _test_four_region_preview(preview_node: Node) -> bool:
	var raw_config: Dictionary = CONFIG_CATALOG.load_config_dict_by_filename("ancient_old_mine")
	var parse_result = CONFIG_CATALOG.parse_and_normalize_config(raw_config)
	if not parse_result.is_success():
		return _fail("古代旧矿预览配置解析失败：%s" % str(parse_result.get_issues()))
	var generator: WdcMapGenerationGenerator = GENERATOR_SCRIPT.new()
	var map_data: WdcMapGenerationTypes.MapData = generator.generate_full(parse_result.config)
	if map_data == null:
		return _fail("古代旧矿预览生成失败：%s" % str(generator.get_last_generation_issues()))
	if map_data.mineral_sites.is_empty():
		return _fail("古代旧矿预览测试缺少矿物站点")
	for mineral_site: Dictionary in map_data.mineral_sites:
		if mineral_site.has("region_index") or mineral_site.has("region_role"):
			return _fail("矿物站点不得保存派生区域缓存")
	var summary_value: Variant = preview_node.call("_build_site_status_summary", map_data)
	if not (summary_value is Dictionary):
		return _fail("四区域预览分区摘要不可用")
	var summary: Dictionary = summary_value as Dictionary
	var expected_counts: Dictionary = _expected_four_region_content_counts(map_data)
	for role: String in MAP_TYPES.REGION_ROLE_ORDER:
		var region = map_data.region_plan.try_get_by_role(role)
		if region == null or int(summary.get("%s_count" % role, -1)) != region.cell_count:
			return _fail("四区域预览面积统计错误：%s" % role)
		for content_kind: String in ["poi", "mineral", "trap", "monster"]:
			var key: String = "%s_%s_count" % [role, content_kind]
			if int(summary.get(key, -1)) != int(expected_counts.get(key, 0)):
				return _fail("四区域预览内容统计错误：%s" % key)
	if (
		int(summary.get("regular_trap_count", -1)) != 0
		or int(summary.get("regular_monster_count", -1)) != 0
	):
		return _fail("古代旧矿预览必须明确显示 regular 陷阱/怪物点为零")
	var stale_role_map: WdcMapGenerationTypes.MapData = map_data.deep_clone()
	var stale_mineral_site: Dictionary = stale_role_map.mineral_sites[0]
	var canonical_mineral_role: String = _resolve_mineral_region_role(
		stale_role_map,
		stale_mineral_site
	)
	if canonical_mineral_role not in MAP_TYPES.REGION_ROLE_ORDER:
		return _fail("矿物站点无法通过 site.cell 查询 RegionPlan")
	var stale_role: String = "regular"
	for candidate_role: String in MAP_TYPES.REGION_ROLE_ORDER:
		if candidate_role != canonical_mineral_role:
			stale_role = candidate_role
			break
	stale_mineral_site["region_role"] = stale_role
	var stale_summary_value: Variant = preview_node.call(
		"_build_site_status_summary",
		stale_role_map
	)
	if not (stale_summary_value is Dictionary):
		return _fail("带陈旧区域字段的矿物预览摘要不可用")
	var stale_summary: Dictionary = stale_summary_value as Dictionary
	for role: String in MAP_TYPES.REGION_ROLE_ORDER:
		var mineral_count_key: String = "%s_mineral_count" % role
		if int(stale_summary.get(mineral_count_key, -1)) != int(
			summary.get(mineral_count_key, -1)
		):
			return _fail("矿物统计错误信任了 site.region_role：%s" % role)
	var summary_text: String = str(
		preview_node.call("_format_four_region_content_summary", summary)
	)
	for required_text: String in [
		"regular[面积=",
		"high_1[面积=",
		"high_2[面积=",
		"boss[面积=",
		"普通POI=",
		"矿物=",
		"陷阱=",
		"怪物点=",
	]:
		if not summary_text.contains(required_text):
			return _fail("四区域预览摘要缺少字段：%s" % required_text)

	preview_node.set("_current_map_data", map_data)
	var core_instance: Dictionary = {}
	for poi_instance: Dictionary in map_data.poi_instances:
		if bool(poi_instance.get("is_core", false)):
			core_instance = poi_instance
			break
	if core_instance.is_empty():
		return _fail("四区域预览 hover 测试缺少核心 POI")
	var core_cell: Vector2i = _cell_from_variant(core_instance.get("center_cell", null))
	var core_region = map_data.region_plan.try_get_at(core_cell)
	var hover_text: String = str(
		preview_node.call("_resolve_cell_site_hover_info", core_cell)
	)
	for required_text: String in [
		"role=%s" % core_region.role,
		"id=%s" % core_region.id,
		"rank=%d" % core_region.difficulty_rank,
		"instance=%s" % str(core_instance.get("instance_id", "")),
	]:
		if not hover_text.contains(required_text):
			return _fail("四区域预览 hover 缺少字段：%s" % required_text)

	var image_value: Variant = preview_node.call("_build_map_preview_image", map_data)
	if not (image_value is Image):
		return _fail("四区域预览 overlay 图像不可用")
	var image: Image = image_value as Image
	var probe_cell: Vector2i = Vector2i.ZERO
	var probe_region = map_data.region_plan.try_get_at(probe_cell)
	var base_color: Color = preview_node.call(
		"_resolve_map_cell_color",
		map_data.get_cell(probe_cell.x, probe_cell.y)
	)
	var overlay_color: Color = preview_node.call("_region_overlay_color", probe_region.role)
	var expected_color: Color = base_color.lerp(overlay_color, 0.22)
	var actual_color: Color = image.get_pixel(
		probe_cell.x,
		map_data.height - 1 - probe_cell.y
	)
	if not _colors_close(actual_color, expected_color):
		return _fail("四区域预览图像没有消费 RegionPlan overlay")

	var texture_rect: TextureRect = TextureRect.new()
	var hover_rect: ColorRect = ColorRect.new()
	var hover_label: Label = Label.new()
	var seed_label: Label = Label.new()
	var status_label: Label = Label.new()
	preview_node.set("_texture_rect", texture_rect)
	preview_node.set("_hover_cell_rect", hover_rect)
	preview_node.set("_hover_tile_label", hover_label)
	preview_node.set("_seed_label", seed_label)
	preview_node.set("_status_label", status_label)
	texture_rect.texture = ImageTexture.create_from_image(image)
	hover_rect.visible = true
	hover_label.visible = true
	seed_label.text = "种子：240513"
	status_label.text = summary_text
	preview_node.call("_clear_preview_result")
	var issues: Array[Dictionary] = [{
		"code": "region_partition_failed",
		"path": "region_generation.layout_profiles",
		"message": "无法生成布局",
	}]
	preview_node.call(
		"_set_status",
		"预览失败：%s" % str(preview_node.call("_format_first_issue", issues))
	)
	if (
		preview_node.get("_current_map_data") != null
		or texture_rect.texture != null
		or hover_rect.visible
		or hover_label.visible
		or seed_label.text != "种子：-"
	):
		return _fail("四区域预览失败必须清空地图、overlay、hover 与 seed 成功状态")
	if (
		status_label.text.contains("regular[面积=")
		or not status_label.text.contains("region_partition_failed")
		or not status_label.text.contains("region_generation.layout_profiles")
		or not status_label.text.contains("无法生成布局")
	):
		return _fail("四区域预览失败必须清空旧统计并显示结构化 issue")
	texture_rect.free()
	hover_rect.free()
	hover_label.free()
	seed_label.free()
	status_label.free()
	return true


func _expected_four_region_content_counts(
	map_data: WdcMapGenerationTypes.MapData
) -> Dictionary:
	var result: Dictionary = {}
	for role: String in MAP_TYPES.REGION_ROLE_ORDER:
		for content_kind: String in ["poi", "mineral", "trap", "monster"]:
			result["%s_%s_count" % [role, content_kind]] = 0
	for poi_instance: Dictionary in map_data.poi_instances:
		if not bool(poi_instance.get("is_core", false)):
			_increment_expected_count(result, poi_instance, "poi")
	for mineral_site: Dictionary in map_data.mineral_sites:
		_increment_expected_count_by_role(
			result,
			_resolve_mineral_region_role(map_data, mineral_site),
			"mineral"
		)
	for trap_site: Dictionary in map_data.trap_sites:
		_increment_expected_count(result, trap_site, "trap")
	for monster_site: Dictionary in map_data.monster_sites:
		_increment_expected_count(result, monster_site, "monster")
	return result


func _increment_expected_count(
	counts: Dictionary,
	item: Dictionary,
	content_kind: String
) -> void:
	var role: String = str(item.get("region_role", ""))
	_increment_expected_count_by_role(counts, role, content_kind)


func _increment_expected_count_by_role(
	counts: Dictionary,
	role: String,
	content_kind: String
) -> void:
	if role not in MAP_TYPES.REGION_ROLE_ORDER:
		return
	var key: String = "%s_%s_count" % [role, content_kind]
	counts[key] = int(counts.get(key, 0)) + 1


func _resolve_mineral_region_role(
	map_data: WdcMapGenerationTypes.MapData,
	mineral_site: Dictionary
) -> String:
	if map_data.region_plan == null or not mineral_site.has("cell"):
		return ""
	var region = map_data.region_plan.try_get_at(
		_cell_from_variant(mineral_site.get("cell", null))
	)
	return region.role if region != null else ""


func _cell_from_variant(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Dictionary:
		return Vector2i(
			int((value as Dictionary).get("x", 0)),
			int((value as Dictionary).get("y", 0))
		)
	return Vector2i.ZERO


func _fail(message: String) -> bool:
	push_error("map_generation_preview_smoke: %s" % message)
	return false


func _colors_close(actual: Color, expected: Color) -> bool:
	var tolerance: float = 1.5 / 255.0
	return (
		absf(actual.r - expected.r) <= tolerance
		and absf(actual.g - expected.g) <= tolerance
		and absf(actual.b - expected.b) <= tolerance
		and absf(actual.a - expected.a) <= tolerance
	)
