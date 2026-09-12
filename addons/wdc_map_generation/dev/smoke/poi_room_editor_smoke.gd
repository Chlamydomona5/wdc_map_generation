extends SceneTree

const DOCUMENT = preload("../../preview/scripts/poi_editor_document.gd")
const STORE = preload("../../preview/scripts/poi_editor_file_store.gd")
const EDITOR = preload("../../preview/scripts/poi_room_editor.gd")
const COMPILER = preload("../../core/poi_blueprint_compiler.gd")
const CATALOG = preload("../../config/poi_resource_catalog.gd")
const PREVIEW = preload("../../preview/scenes/map_generation_preview.tscn")
const CONFIG_CATALOG = preload("../../config/data_generated_map_config_catalog.gd")
var _failures: Array[String] = []
var _capture_directory: String = ""

class FailingDraftStore:
	extends RefCounted
	var reload_attempted: bool = false

	func save_draft(_snapshot: Dictionary) -> Error:
		return ERR_CANT_CREATE

	func recover_transaction() -> Dictionary:
		reload_attempted = true
		return {"ok": false, "issues": []}

class RecordingGameLauncher:
	extends RefCounted
	var filenames: Array[String] = []

	func launch_saved_map_test(filename: String) -> Dictionary:
		filenames.append(filename)
		return {"ok": true, "pid": 1, "error": ""}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			_capture_directory = argument.trim_prefix("--capture-dir=")
	if not _capture_directory.is_empty():
		root.size = Vector2i(1440, 1000)
		DirAccess.make_dir_recursive_absolute(_capture_directory)
	_test_document_history()
	_test_storage()
	await _test_editor()
	await _test_formal_entry()
	await _test_poi_only_workflow()
	if _failures.is_empty():
		print("poi_room_editor_smoke: PASS document / gesture / raster / rotation / structured creation / local conflicts / save reload / multi-seed / full map hash / source navigation / POI Only preview-save-launch / conflict / recovery / formal entry")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("poi_room_editor_smoke: " + failure)
		quit(1)


func _test_document_history() -> void:
	var document = DOCUMENT.new()
	document.load_documents({"room/demo": {"id": "demo", "cells": ["..."]}}, {"room/demo": "baseline"})
	document.begin_gesture()
	document.replace_document("room/demo", {"id": "demo", "cells": ["#.."]})
	document.replace_document("room/demo", {"id": "demo", "cells": ["##."]})
	document.end_gesture()
	_expect(document.undo(), "连续手势必须可撤销")
	_expect(document.get_document("room/demo").cells == ["..."], "一次撤销必须回到整段手势之前")
	_expect(not document.can_undo(), "一次手势只能留下一个历史项")
	_expect(document.redo() and document.get_document("room/demo").cells == ["##."], "手势重做必须恢复整个结果")
	document.begin_gesture()
	document.replace_document("room/demo", document.get_document("room/demo"))
	document.end_gesture()
	document.undo()
	_expect(not document.can_undo(), "空操作不能进入历史")
	document.remove_document("room/demo")
	_expect(document.dependency_overrides().rooms.has("demo") and document.dependency_overrides().rooms.demo == null, "删除资源必须明确覆盖磁盘资源")
	var restored = DOCUMENT.new()
	_expect(restored.restore_draft(document.draft_snapshot()) and restored.baseline_hashes.get("room/demo") == "baseline", "恢复草稿必须保留冲突检测基线")


func _test_storage() -> void:
	var storage = STORE.new()
	var directory: String = "user://poi_editor_smoke/%d" % Time.get_ticks_usec()
	storage.configure(directory.path_join("config"), directory.path_join("recovery"))
	var documents: Dictionary = {"room/demo": {"schema_version": 1, "id": "demo", "cells": ["..."]}, "composition/demo": {"schema_version": 1, "id": "demo"}}
	var saved: Dictionary = storage.save_project(documents, ["room/demo", "composition/demo"], {})
	_expect(bool(saved.get("ok", false)), "首个多文件事务必须成功")
	if not bool(saved.get("ok", false)):
		return
	var loaded: Dictionary = storage.load_project()
	_expect(_same(loaded.documents, documents), "保存重载必须保留完整字段")
	var room_path: String = storage.document_path("room/demo")
	var external_text: String = "{\"id\":\"external\"}\n"
	storage._write_atomic(room_path, external_text)
	documents["room/demo"]["display_name"] = "新名字"
	var conflict: Dictionary = storage.save_project(documents, ["room/demo"], saved.hashes)
	_expect(not bool(conflict.get("ok", false)) and FileAccess.get_file_as_string(room_path) == external_text, "外部改动不能被覆盖")
	var before: String = external_text
	var after: String = "{\"id\":\"partial_transaction\"}\n"
	var journal: Dictionary = {"schema_version": 1, "root": storage.content_root, "entries": [{"key": "room/demo", "before_exists": true, "before": before, "before_hash": before.sha256_text(), "after_exists": true, "after": after, "after_hash": after.sha256_text()}]}
	storage._write_atomic(storage._journal_path(), JSON.stringify(journal))
	storage._write_atomic(room_path, after)
	var recovered: Dictionary = storage.recover_transaction()
	_expect(bool(recovered.get("ok", false)) and bool(recovered.get("recovered", false)) and FileAccess.get_file_as_string(room_path) == before, "中断的多文件保存必须恢复原值")
	_expect(storage.document_path("room/../outside").is_empty(), "资源路径不能越出配置根")
	storage.save_tool_state({"room": "room/demo"}, {"graph": {"x": 10, "y": 20}})
	_expect(storage.load_tool_state().view_state.graph.x == 10, "只改变图排版也必须能够独立恢复工具状态")


func _test_editor() -> void:
	var bundle: Dictionary = CATALOG.load_bundle()
	_expect(bool(bundle.get("valid", false)), "正式资源库必须可编译：%s" % str(bundle.get("issues", [])))
	if not bundle.get("rooms", {}).has("miner_house_a"):
		_failures.append("缺少首批房间样例")
		return
	var room: Dictionary = bundle.rooms.miner_house_a.duplicate(true)
	var composition: Dictionary = bundle.compositions.room_showcase.duplicate(true)
	var editor = EDITOR.new()
	editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(editor)
	var directory: String = "user://poi_editor_smoke/ui/%d" % Time.get_ticks_usec()
	editor.store.configure(directory.path_join("config"), directory.path_join("recovery"))
	editor.model.load_documents({"room/miner_house_a": room, "composition/room_showcase": composition})
	editor._room_key = "room/miner_house_a"
	editor._composition_key = "composition/room_showcase"
	editor._refresh_all()
	await process_frame
	_expect(editor._tabs.get_tab_count() == 3, "工具必须包含房间、组装、验证三个工作页")
	editor.model.begin_gesture()
	editor._paint_cells([{"x": 1, "y": 1}, {"x": 2, "y": 1}], "wall")
	editor.model.end_gesture()
	_expect(editor.model.get_document("room/miner_house_a").cells[1].substr(1, 2) == "##", "结构画笔必须写入房间图纸")
	editor._undo()
	_expect(_same(editor.model.get_document("room/miner_house_a"), room), "撤销画格必须恢复相同文档")
	for index: int in range(4):
		editor._rotate_room()
	_expect(_same(editor.model.get_document("room/miner_house_a"), room), "四次旋转必须还原墙、门、锚点、槽朝向和净空")
	editor._room_path = ["slots", 0]
	editor._paint_cells([{"x": 2, "y": 2}], "slot_region")
	_expect(editor.model.get_document("room/miner_house_a").slots[0].region.has({"x": 2, "y": 2}), "区域槽画笔必须写入对应槽")
	editor._undo()
	editor._room_json.text = JSON.stringify(room)
	editor._apply_json("room")
	_expect(_same(editor.model.get_document("room/miner_house_a"), room), "JSON 必须修改同一个文档模型")
	editor._validate_room()
	_expect(editor._validation_label.text.contains("局部校验通过"), "单房校验必须明确为局部结论")
	var overlap: Dictionary = room.duplicate(true)
	var duplicate_slot: Dictionary = overlap.slots[0].duplicate(true)
	duplicate_slot.id = "overlap_slot"
	overlap.slots.append(duplicate_slot)
	editor.model.replace_document("room/miner_house_a", overlap)
	editor._validate_room()
	_expect(editor._validation_label.text.contains("失败") and editor._result_canvas.display_plan.is_empty(), "同格必需内容重叠必须在单房试生成阶段失败")
	editor.model.replace_document("room/miner_house_a", room)
	var unavailable: Dictionary = room.duplicate(true)
	unavailable.slots[0].entries[0].id = "missing_capability"
	editor.model.replace_document("room/miner_house_a", unavailable)
	editor._validate_room()
	_expect(editor._validation_label.text.contains("失败") and not editor._issue_values.is_empty(), "未知内容能力必须在单房阶段失败")
	editor.model.replace_document("room/miner_house_a", room)
	editor._seed_count.value = 2
	await editor._validate_composition()
	_expect(editor._results.size() == 2, "多种子验证必须使用正式组装器逐个产生结果")
	for result: Dictionary in editor._results:
		_expect(bool(result.get("valid", false)), "样例 POI 局部生成失败：%s" % str(result.get("issues", [])))
	_expect(editor._result_canvas.display_plan.get("slots", []).all(func(slot: Dictionary) -> bool: return not slot.get("cells", []).is_empty()), "结果画布必须显示正式内容请求的实际位置")
	_test_source_navigation(editor)
	await _test_structured_creation(editor)
	_test_failed_draft_reload(editor)
	editor.queue_free()
	await process_frame


func _test_source_navigation(editor: Control) -> void:
	var canvas: Control = editor._result_canvas
	var rooms: Array = canvas.display_plan.get("rooms", [])
	_expect(not rooms.is_empty(), "局部结果必须保留房间来源")
	if rooms.is_empty():
		return
	var room: Dictionary = rooms[0]
	var point: Variant = room.floor_cells[0]
	var cell: Vector2i = Vector2i(int(point.x), int(point.y))
	var source: Dictionary = canvas._source_at_cell(cell)
	var before: Dictionary = editor.model.documents.duplicate(true)
	var revision: int = editor.model.revision
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.double_click = true
	click.position = (Vector2(cell) + Vector2.ONE * 0.5) * canvas.zoom + canvas.pan
	canvas._gui_input(click)
	_expect(editor._tabs.current_tab == 0 and editor._room_key == "room/" + str(room.blueprint_id), "双击只读结果必须跳回来源图纸")
	_expect(editor._room_canvas.selection_rect.position == source.get("local_cell"), "来源定位必须还原房间局部格")
	_expect(editor.model.revision == revision and _same(editor.model.documents, before), "浏览生成结果不能修改编辑文档")
	var local: Vector2i = source.local_cell
	var blueprint: Dictionary = editor.model.get_document(editor._room_key)
	_expect(local.y >= 0 and local.y < blueprint.cells.size() and local.x >= 0 and local.x < str(blueprint.cells[local.y]).length() and str(blueprint.cells[local.y]).substr(local.x, 1) == ".", "逆变换后的来源格必须是图纸的实际地板")


func _test_failed_draft_reload(editor: Control) -> void:
	var storage: RefCounted = editor.store
	var failing: FailingDraftStore = FailingDraftStore.new()
	var before: Dictionary = editor.model.documents.duplicate(true)
	editor.store = failing
	editor._request_reload()
	_expect(not failing.reload_attempted and _same(before, editor.model.documents), "草稿保存失败必须保留编辑文档并停止重载")
	_expect(editor._status.text.contains("草稿保存失败"), "草稿保存失败必须明确显示原因")
	editor.store = storage


func _test_structured_creation(editor: Control) -> void:
	editor._create_kind = "room"
	editor._create_copy = false
	editor._name_input.text = "smoke_drawn_room"
	editor._confirm_create()
	var key: String = editor._room_key
	_expect(key == "room/smoke_drawn_room", "新建必须产生独立稳定 ID")
	editor._paint_cells([{"x": 0, "y": 0}], "erase")
	editor._paint_cells([{"x": 3, "y": 2}], "clearance")
	editor.model.selection.cell = {"x": 0, "y": 3}
	editor._add_room_member("ports")
	editor._change_field(key, ["ports", 1, "normal"], {"x": -1, "y": 0})
	editor._change_field(key, ["ports", 1, "unused"], "open")
	editor.model.selection.cell = {"x": 1, "y": 1}
	editor._add_room_member("slots")
	editor._apply_capability_footprint()
	var compiled: Dictionary = COMPILER.compile_bundle({"smoke_drawn_room": editor.model.get_document(key)}, {})
	_expect(bool(compiled.get("valid", false)), "新建、非矩形画格、门、槽与净空无需 JSON 即可通过编译：%s" % str(compiled.get("issues", [])))
	var original: Dictionary = editor.model.get_document(key)
	editor._room_canvas.selection_rect = Rect2i(0, 0, 7, 7)
	editor._move_selection(Vector2i(-1, 0), false)
	_expect(_same(original, editor.model.get_document(key)), "越界移动不能裁掉地形或移动元数据")
	editor._move_selection(Vector2i(8, 0), true)
	var copied: Dictionary = editor.model.get_document(key)
	_expect(copied.ports.size() == original.ports.size() * 2 and copied.slots.size() == original.slots.size() * 2 and copied.keep_clear.size() == original.keep_clear.size() * 2, "复制完整选区必须同时复制门、槽与净空，并生成独立 ID")
	editor._undo()
	editor._create_copy = true
	editor._name_input.text = "smoke_drawn_variant"
	editor._confirm_create()
	var variant: Dictionary = editor.model.get_document(editor._room_key)
	_expect(variant.cells == original.cells and variant.ports == original.ports and variant.slots == original.slots, "复制变体必须完整保留几何与内容规则")
	editor._create_kind = "composition"
	editor._create_copy = false
	editor._name_input.text = "smoke_drawn_composition"
	editor._confirm_create()
	var composition_key: String = editor._composition_key
	editor._add_array_field(composition_key, ["nodes", 0, "blueprints"], {"id": "smoke_drawn_room", "weight": 2.0, "max_instances": 1})
	editor._change_field(composition_key, ["nodes", 0, "rotations"], [0, 90])
	editor._seed_count.value = 4
	await editor._validate_composition()
	_expect(editor._results.size() == 4 and editor._results.all(func(result: Dictionary) -> bool: return result.get("valid", false)), "新建组合及候选池必须通过多个种子：%s" % str(editor._issue_values))
	editor._save_project()
	_expect(not editor.model.is_dirty(), "有效的关联图纸 / 组合必须能通过 UI 保存项目：%s" % str(editor._issue_values))
	var loaded: Dictionary = editor.store.load_project()
	_expect(loaded.documents.has(key) and loaded.documents.has(composition_key), "关联保存重载必须包含新增图纸和组合")
	editor._change_field(composition_key, ["nodes", 0, "blueprints", 0, "id"], "missing_room")
	await editor._validate_composition()
	_expect(editor._results.is_empty() and editor._result_canvas.display_plan.is_empty(), "重新生成失败必须清除上次成功结果")
	_expect(not editor._issue_values.is_empty(), "非法引用必须显示具体问题")
	if not editor._issue_values.is_empty():
		editor._locate_issue(0)
		_expect(editor._tabs.current_tab == 1 and editor._composition_path == ["nodes", 0], "点击问题必须定位组合节点")


func _test_formal_entry() -> void:
	var preview: Control = PREVIEW.instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame
	var editor: Control = preview._poi_room_editor
	editor._draft_timer.stop()
	editor.store.configure(editor.store.content_root, "user://poi_editor_smoke/formal/%d" % Time.get_ticks_usec())
	_expect(not editor.model.is_dirty(), "打开正式入口不能把未编辑参数写回为草稿改动")
	var selected_room: String = editor._room_key
	for key: String in editor.model.list_keys("room"):
		editor._room_key = key
		editor._validate_room()
		_expect(editor._validation_label.text.contains("局部校验通过"), "正式图纸应通过单房真实试生成：%s %s %s" % [key, editor._validation_label.text, str(editor._issue_values)])
	editor._room_key = selected_room
	editor._refresh_all()
	_expect(not editor.model.is_dirty(), "单房辅助组合和锚点不能进入编辑文档")
	var room_page: Control = editor._tabs.get_child(0)
	_expect(room_page.get_child_count() == 2 and room_page.get_child(1).get_child_count() == 2, "三栏必须使用嵌套分栏，保证属性与画布都有可用布局")
	_expect(editor._room_canvas.size.x >= 300 and editor._room_properties.size.x > 100, "正式入口画布和属性栏必须获得实际尺寸")
	editor._tabs.current_tab = 0
	await _capture("01-room-layout.png")
	editor._tabs.current_tab = 1
	await process_frame
	await process_frame
	editor._composition_canvas.fit_content()
	await _capture("02-composition.png")
	editor._seed_count.value = 4
	await editor._validate_composition()
	await _capture("03-seed-comparison.png")
	var unrelated: Dictionary = editor.model.get_document("room/miner_house_a")
	unrelated.id = "smoke_unused_hash_room"
	editor.model.replace_document("room/smoke_unused_hash_room", unrelated)
	var parsed = CONFIG_CATALOG.parse_and_normalize_config(editor.model.get_document(editor._map_key), editor.model.dependency_overrides())
	var expected_hash: String = str(parsed.config.get_meta("poi_resource_bundle", {}).get("content_hash", ""))
	var emitted_hash: Dictionary = {}
	editor.full_map_generated.connect(func(_data: RefCounted, _seed: int, _source: Dictionary, dependency_hash: String) -> void: emitted_hash.value = dependency_hash)
	await editor._validate_full_map()
	_expect(editor._validation_label.text.contains("完整地图通过") and preview._current_map_data != null, "完整地图校验必须接回正式预览：%s" % editor._validation_label.text)
	_expect(not expected_hash.is_empty() and emitted_hash.get("value") == expected_hash, "整图显示与输出的哈希必须来自实际地图依赖闭包")
	_test_source_navigation(editor)
	editor._tabs.current_tab = 2
	preview._workspace_tabs.current_tab = 0
	await _capture("04-full-map.png")
	var map_source: Dictionary = editor.model.get_document(editor._map_key)
	map_source.schema_version = 999
	editor.model.replace_document(editor._map_key, map_source)
	_expect(preview._current_map_data == null, "草稿改动必须使完整地图结果失效")
	await editor._validate_full_map()
	_expect(preview._current_map_data == null and editor._result_canvas.display_plan.is_empty(), "完整地图失败不能继续展示旧结果")
	editor._draft_timer.stop()
	preview.queue_free()
	await process_frame


func _test_poi_only_workflow() -> void:
	var preview: Control = PREVIEW.instantiate()
	root.add_child(preview)
	await process_frame
	var editor: Control = preview._poi_room_editor
	var documents: Dictionary = editor.model.documents.duplicate(true)
	# 正式项目附带同名示例，沙盒仍从尚未保存测试图的状态验证新建流程。
	documents.erase("map/poi_test_refining_workshop")
	var directory: String = "user://poi_editor_smoke/poi_only/%d" % Time.get_ticks_usec()
	editor._draft_timer.stop()
	editor.store.configure(directory.path_join("config"), directory.path_join("recovery"))
	var keys: Array[String] = []
	keys.assign(documents.keys())
	var saved: Dictionary = editor.store.save_project(documents, keys, {})
	_expect(bool(saved.get("ok", false)), "POI Only 测试沙盒必须建立完整依赖")
	if not saved.get("ok", false):
		preview.queue_free()
		await process_frame
		return
	editor.model.load_documents(documents, saved.hashes)
	editor._map_key = "map/ancient_old_mine"
	editor._composition_key = "composition/refining_workshop"
	editor._refresh_all()
	var template_id: String = ""
	for template: Dictionary in documents[editor._map_key].get("poi_generation", {}).get("poi_types", []):
		if template.get("composition_id", "") == "refining_workshop":
			template_id = str(template.id)
	for index: int in range(editor._template_selector.item_count):
		if str(editor._template_selector.get_item_metadata(index)) == template_id:
			editor._template_selector.select(index)
	var launcher: RecordingGameLauncher = RecordingGameLauncher.new()
	editor.game_launcher = launcher
	var generated: bool = await editor._generate_poi_only_map()
	_expect(generated, "POI Only 编辑器生成必须通过：%s %s" % [editor._validation_label.text, str(editor._issue_values)])
	if not generated:
		preview.queue_free()
		await process_frame
		return
	var test_key: String = "map/poi_test_refining_workshop"
	var config: Dictionary = editor.model.get_document(test_key)
	_expect(config.get("region_layout", {}).get("mode") == "poi_only_v1" and config.poi_only.source_template_id == template_id, "测试配置必须保留选中的源条目")
	_expect(preview._current_config_filename == "poi_test_refining_workshop" and preview._current_map_data.poi_instances.size() == 1, "整图预览必须显示真实单 POI 测试地图及其文件名")
	_expect(str(preview._config_selector.get_item_metadata(preview._config_selector.selected)) == "poi_test_refining_workshop", "整图下拉框必须同步为当前生成的测试地图")
	_expect(editor._map_key == "map/ancient_old_mine" and str(editor._template_selector.get_item_metadata(editor._template_selector.selected)) == template_id, "生成测试图不能替换源地图或丢失所选条目")
	_expect(not FileAccess.file_exists(editor.store.document_path(test_key)) and launcher.filenames.is_empty(), "仅生成预览不能提前写正式文件或启动游戏")
	await process_frame
	await process_frame
	var canvas: Control = editor._result_canvas
	var fits: bool = true
	for cell: Dictionary in canvas.display_plan.get("wall_cells", []):
		var pixel: Vector2 = canvas.pan + Vector2(float(cell.x), float(cell.y)) * canvas.zoom
		fits = fits and pixel.x >= 0 and pixel.y >= 0 and pixel.x + canvas.zoom <= canvas.size.x and pixel.y + canvas.zoom <= canvas.size.y
	_expect(fits, "长说明换行调整布局后，只读结果必须重新适配画布，不能裁切房间")
	await _capture("05-poi-only-preview.png")
	preview._workspace_tabs.current_tab = 0
	await _capture("06-poi-only-map.png")
	preview._workspace_tabs.current_tab = 1
	var baseline_hash: String = editor.model.baseline_hashes["map/ancient_old_mine"]
	editor.model.baseline_hashes["map/ancient_old_mine"] = "external_change"
	await editor._save_and_launch_poi_only()
	_expect(launcher.filenames.is_empty() and not FileAccess.file_exists(editor.store.document_path(test_key)), "关联保存冲突必须阻止启动正式游戏")
	editor.model.baseline_hashes["map/ancient_old_mine"] = baseline_hash
	await editor._save_and_launch_poi_only()
	_expect(launcher.filenames == ["poi_test_refining_workshop"] and not editor.model.is_dirty(), "保存成功后应只把测试文件名交给正式启动器")
	var reloaded: Dictionary = editor.store.load_project()
	_expect(reloaded.documents.has(test_key) and reloaded.documents[test_key].poi_only.composition_id == "refining_workshop", "关联事务必须保存可重新加载的测试地图")
	editor._draft_timer.stop()
	preview.queue_free()
	await process_frame


func _capture(filename: String) -> void:
	if _capture_directory.is_empty():
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	_expect(screenshot.save_png(_capture_directory.path_join(filename)) == OK, "工具入口截图必须成功：" + filename)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _same(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))
