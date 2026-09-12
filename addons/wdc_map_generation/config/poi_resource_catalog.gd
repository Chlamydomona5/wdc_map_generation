class_name WdcPoiResourceCatalog
extends RefCounted

const COMPILER = preload("../core/poi_blueprint_compiler.gd")
const STANDALONE_ROOT: String = "res://addons/wdc_map_generation/config"
const PARENT_ROOT: String = "res://map_generation/addons/wdc_map_generation/config"


static func get_resource_directories() -> Dictionary:
	var root: String = STANDALONE_ROOT
	if FileAccess.file_exists(PARENT_ROOT + "/poi_resource_catalog.gd"):
		root = PARENT_ROOT
	return {"rooms": root + "/poi_rooms", "compositions": root + "/poi_compositions", "capabilities": root + "/poi_capabilities/content_capabilities.json"}


## 内存文档覆盖磁盘内容；空值表示草稿会话中删除资源。
static func load_bundle(overrides: Dictionary = {}, composition_ids: Array = []) -> Dictionary:
	var directories: Dictionary = get_resource_directories()
	var documents: Dictionary = {"rooms": {}, "compositions": {}}
	var paths: Dictionary = {"rooms": {}, "compositions": {}}
	var issues: Array[Dictionary] = []
	var needed_rooms: Dictionary = {}
	for kind: String in ["compositions", "rooms"]:
		var directory: DirAccess = DirAccess.open(directories[kind])
		if directory != null:
			var filenames: PackedStringArray = directory.get_files()
			filenames.sort()
			for filename: String in filenames:
				if not filename.ends_with(".json"):
					continue
				var filename_id: String = filename.get_basename()
				if not composition_ids.is_empty() and ((kind == "compositions" and not composition_ids.has(filename_id)) or (kind == "rooms" and not needed_rooms.has(filename_id))):
					continue
				if overrides.get(kind, {}) is Dictionary and overrides.get(kind, {}).has(filename_id):
					continue
				var path: String = str(directories[kind]).path_join(filename)
				var document: Dictionary = _read_document(path, issues)
				var id: String = str(document.get("id", filename.get_basename()))
				if filename.get_basename() != id or documents[kind].has(id):
					COMPILER.issue(issues, path, "文件名必须与唯一资源 id 一致", "ambiguous_poi_reference")
				documents[kind][id] = document
				paths[kind][id] = path
		var replacements: Variant = overrides.get(kind, {})
		if not replacements is Dictionary:
			COMPILER.issue(issues, kind, "资源覆盖必须是按 id 索引的对象")
			continue
		for id: Variant in replacements:
			if not composition_ids.is_empty() and ((kind == "compositions" and not composition_ids.has(id)) or (kind == "rooms" and not needed_rooms.has(id))):
				continue
			if replacements[id] == null:
				documents[kind].erase(id)
				paths[kind].erase(id)
			else:
				documents[kind][id] = replacements[id]
				paths[kind][id] = str(directories[kind]).path_join(str(id) + ".json")
		if kind == "compositions":
			for document: Variant in documents.compositions.values():
				if not document is Dictionary or not document.get("nodes", []) is Array:
					continue
				for node: Variant in document.get("nodes", []):
					if not node is Dictionary or not node.get("blueprints", []) is Array:
						continue
					for entry: Variant in node.get("blueprints", []):
						if entry is Dictionary:
							needed_rooms[str(entry.get("id", ""))] = true
	for id: Variant in composition_ids:
		if not documents.compositions.has(id):
			COMPILER.issue(issues, "compositions." + str(id), "地图引用的组合不存在", "unknown_poi_reference")
	var result: Dictionary = COMPILER.compile_bundle(documents.rooms, documents.compositions)
	result.issues.append_array(issues)
	result["valid"] = result.issues.is_empty()
	result["source_paths"] = paths
	result["capabilities"] = {}
	if FileAccess.file_exists(directories.capabilities):
		result.capabilities = _read_document(directories.capabilities, issues)
		result["capabilities_path"] = directories.capabilities
		_validate_content_references(result, issues)
	# 能力目录可能由主仓同步；空目录仍可验证不含道具的纯几何图纸。
	if not issues.is_empty():
		for issue_value: Dictionary in issues:
			if not result.issues.has(issue_value):
				result.issues.append(issue_value)
	result.valid = result.issues.is_empty()
	result["dependencies"] = collect_dependencies(result)
	result.content_hash = JSON.stringify([result.rooms, result.compositions, result.capabilities], "", true).sha256_text()
	return result


## 从已经载入的编辑会话取得一张地图的不可变依赖闭包。
static func select_bundle(bundle: Dictionary, composition_ids: Array) -> Dictionary:
	var rooms: Dictionary = {}
	var compositions: Dictionary = {}
	var issues: Array[Dictionary] = []
	for id: Variant in composition_ids:
		if not bundle.get("compositions", {}).has(id):
			COMPILER.issue(issues, "compositions." + str(id), "地图引用的组合不存在", "unknown_poi_reference")
			continue
		compositions[id] = bundle.compositions[id].duplicate(true)
		for node: Dictionary in compositions[id].get("nodes", []):
			for entry: Dictionary in node.get("blueprints", []):
				if bundle.get("rooms", {}).has(entry.id):
					rooms[entry.id] = bundle.rooms[entry.id].duplicate(true)
	var result: Dictionary = COMPILER.compile_bundle(rooms, compositions)
	result.issues.append_array(issues)
	result["source_paths"] = bundle.get("source_paths", {}).duplicate(true)
	result["capabilities"] = bundle.get("capabilities", {}).duplicate(true)
	result["capabilities_path"] = bundle.get("capabilities_path", "")
	_validate_content_references(result, issues)
	result.issues.append_array(issues.filter(func(value: Dictionary) -> bool: return not result.issues.has(value)))
	result["dependencies"] = collect_dependencies(result, composition_ids)
	result["content_hash"] = JSON.stringify([result.rooms, result.compositions, result.capabilities], "", true).sha256_text()
	result.valid = result.issues.is_empty()
	return result


static func _validate_content_references(bundle: Dictionary, issues: Array[Dictionary]) -> void:
	var document: Dictionary = bundle.get("capabilities", {})
	if document.is_empty():
		for room: Dictionary in bundle.rooms.values():
			if not room.get("slots", []).is_empty():
				COMPILER.issue(issues, "capabilities", "含内容槽的图纸必须加载正式内容能力快照", "invalid_poi_capabilities")
				break
		return
	if document.get("schema_version") != 1 or not document.get("entries") is Array:
		COMPILER.issue(issues, "capabilities", "内容能力快照格式无效", "invalid_poi_capabilities")
		return
	var available: Dictionary = {}
	var seen: Dictionary = {}
	for entry: Variant in document.entries:
		if not entry is Dictionary:
			COMPILER.issue(issues, "capabilities.entries", "能力条目必须是对象", "invalid_poi_capabilities")
			continue
		var key: String = str(entry.get("kind", "")) + "/" + str(entry.get("id", ""))
		var path: String = "capabilities.entries." + key
		if not entry.get("id") is String or str(entry.get("id", "")).is_empty() or not entry.get("kind") is String or seen.has(key):
			COMPILER.issue(issues, path, "能力 id/种类必须为字符串，且组合键不能重复", "invalid_poi_capabilities")
		seen[key] = true
		if not entry.get("available") is bool or entry.get("placement_surface") not in ["floor", "wall"]:
			COMPILER.issue(issues, path, "能力可用性和放置表面无效", "invalid_poi_capabilities")
		for field: String in ["footprint_cells", "clearance_cells"]:
			if not entry.get(field) is Array:
				COMPILER.issue(issues, path + "." + field, "能力占地与净空必须是整数格子数组", "invalid_poi_capabilities")
				continue
			if field == "footprint_cells" and entry[field].is_empty():
				COMPILER.issue(issues, path + "." + field, "能力占地不能为空", "invalid_poi_capabilities")
			var cells: Dictionary = {}
			for point: Variant in entry[field]:
				if not point is Array or point.size() != 2 or not COMPILER.valid_cell({"x": point[0], "y": point[1]}):
					COMPILER.issue(issues, path + "." + field, "能力格子必须是两个整数", "invalid_poi_capabilities")
					continue
				var cell_key: String = JSON.stringify(point)
				if cells.has(cell_key):
					COMPILER.issue(issues, path + "." + field, "能力格子不能重复", "invalid_poi_capabilities")
				cells[cell_key] = true
		if entry.get("available") is bool and entry.available:
			available[key] = true
	for room: Dictionary in bundle.rooms.values():
		for slot: Dictionary in room.get("slots", []):
			var path: String = "rooms.%s.slots.%s" % [room.id, slot.id]
			for entry: Dictionary in slot.get("entries", []):
				if not available.has(str(slot.get("kind", "")) + "/" + str(entry.id)):
					COMPILER.issue(issues, path + ".entries", "内容未接入或不可用：%s" % entry.id, "poi_content_unavailable")
			for member: Dictionary in slot.get("group_members", []):
				if not available.has(str(member.get("kind", "")) + "/" + str(member.get("id", ""))):
					COMPILER.issue(issues, path + ".group_members", "成组内容未接入或不可用：%s" % member.get("id", ""), "poi_content_unavailable")


static func collect_dependencies(bundle: Dictionary, composition_ids: Array = []) -> Array[String]:
	var selected: Dictionary = {}
	var paths: Dictionary = bundle.get("source_paths", {})
	var compositions: Dictionary = bundle.get("compositions", {})
	var ids: Array = composition_ids if not composition_ids.is_empty() else compositions.keys()
	for id: Variant in ids:
		if not compositions.has(id):
			continue
		var composition_path: String = str(paths.get("compositions", {}).get(id, ""))
		if not composition_path.is_empty():
			selected[composition_path] = true
		for node: Dictionary in compositions[id].get("nodes", []):
			for candidate: Dictionary in node.get("blueprints", []):
				var room_path: String = str(paths.get("rooms", {}).get(candidate.get("id"), ""))
				if not room_path.is_empty():
					selected[room_path] = true
	var capability_path: String = str(bundle.get("capabilities_path", ""))
	if not capability_path.is_empty():
		selected[capability_path] = true
	var result: Array[String] = []
	for path: Variant in selected:
		result.append(str(path))
	result.sort()
	return result


static func _read_document(path: String, issues: Array[Dictionary]) -> Dictionary:
	var parser: JSON = JSON.new()
	var error: Error = parser.parse(FileAccess.get_file_as_string(path))
	if error != OK or not parser.data is Dictionary:
		COMPILER.issue(issues, path, "JSON 解析失败：%s，行 %d" % [parser.get_error_message(), parser.get_error_line()], "invalid_poi_json")
		return {}
	return (parser.data as Dictionary).duplicate(true)
