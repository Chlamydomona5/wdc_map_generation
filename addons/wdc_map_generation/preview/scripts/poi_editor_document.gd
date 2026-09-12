extends RefCounted

## 房间、组合和地图引用的唯一可编辑真相；控件与 JSON 都提交同一文档。
signal changed(revision: int)

const HISTORY_LIMIT: int = 100
var documents: Dictionary = {}
var baseline_documents: Dictionary = {}
var baseline_hashes: Dictionary = {}
var revision: int = 0
var selection: Dictionary = {}
var view_state: Dictionary = {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _gesture_before: Dictionary = {}
var _gesture_active: bool = false


func load_documents(source: Dictionary, hashes: Dictionary = {}) -> void:
	documents = source.duplicate(true)
	baseline_documents = source.duplicate(true)
	baseline_hashes = hashes.duplicate(true)
	_undo.clear()
	_redo.clear()
	_gesture_active = false
	revision += 1
	changed.emit(revision)


func get_document(key: String) -> Dictionary:
	return (documents.get(key, {}) as Dictionary).duplicate(true)


func list_keys(kind: String) -> Array[String]:
	var result: Array[String] = []
	for key: String in documents:
		if key.begins_with(kind + "/"):
			result.append(key)
	result.sort()
	return result


func replace_document(key: String, source: Dictionary) -> bool:
	var next: Dictionary = documents.duplicate(true)
	next[key] = source.duplicate(true)
	return _replace_all(next)


func remove_document(key: String) -> bool:
	var next: Dictionary = documents.duplicate(true)
	next.erase(key)
	return _replace_all(next)


func begin_gesture() -> void:
	if _gesture_active:
		return
	_gesture_before = documents.duplicate(true)
	_gesture_active = true


func end_gesture() -> void:
	if not _gesture_active:
		return
	_gesture_active = false
	if _signature(_gesture_before) != _signature(documents):
		_push_undo(_gesture_before)
	_gesture_before = {}


func cancel_gesture() -> void:
	if not _gesture_active:
		return
	documents = _gesture_before.duplicate(true)
	_gesture_active = false
	_gesture_before = {}
	_notify()


func undo() -> bool:
	end_gesture()
	if _undo.is_empty():
		return false
	_redo.append(documents.duplicate(true))
	documents = _undo.pop_back()
	_notify()
	return true


func redo() -> bool:
	end_gesture()
	if _redo.is_empty():
		return false
	_undo.append(documents.duplicate(true))
	documents = _redo.pop_back()
	_notify()
	return true


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func is_dirty(key: String = "") -> bool:
	if key.is_empty():
		return _signature(documents) != _signature(baseline_documents)
	return _signature(documents.get(key)) != _signature(baseline_documents.get(key))


func get_changed_keys() -> Array[String]:
	var keys: Dictionary = {}
	for key: String in documents:
		keys[key] = true
	for key: String in baseline_documents:
		keys[key] = true
	var changed_keys: Array[String] = []
	for key: String in keys:
		if is_dirty(key):
			changed_keys.append(key)
	changed_keys.sort()
	return changed_keys


func mark_saved(hashes: Dictionary) -> void:
	baseline_documents = documents.duplicate(true)
	baseline_hashes = hashes.duplicate(true)
	_notify()


func dependency_overrides() -> Dictionary:
	var rooms: Dictionary = {}
	var compositions: Dictionary = {}
	for key: String in documents:
		if key.begins_with("room/"):
			rooms[key.trim_prefix("room/")] = documents[key].duplicate(true)
		elif key.begins_with("composition/"):
			compositions[key.trim_prefix("composition/")] = documents[key].duplicate(true)
	for key: String in baseline_documents:
		if documents.has(key):
			continue
		if key.begins_with("room/"):
			rooms[key.trim_prefix("room/")] = null
		elif key.begins_with("composition/"):
			compositions[key.trim_prefix("composition/")] = null
	return {"rooms": rooms, "compositions": compositions}


func draft_snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"documents": documents.duplicate(true),
		"baseline_documents": baseline_documents.duplicate(true),
		"baseline_hashes": baseline_hashes.duplicate(true),
		"selection": selection.duplicate(true),
		"view_state": view_state.duplicate(true),
	}


func restore_draft(snapshot: Dictionary) -> bool:
	if int(snapshot.get("schema_version", 0)) != 1 or not snapshot.get("documents") is Dictionary:
		return false
	documents = snapshot["documents"].duplicate(true)
	baseline_documents = snapshot.get("baseline_documents", {}).duplicate(true)
	baseline_hashes = snapshot.get("baseline_hashes", {}).duplicate(true)
	selection = snapshot.get("selection", {}).duplicate(true)
	view_state = snapshot.get("view_state", {}).duplicate(true)
	_undo.clear()
	_redo.clear()
	_gesture_active = false
	_notify()
	return true


func find_references(kind: String, id: String, member_id: String = "") -> Array[Dictionary]:
	var references: Array[Dictionary] = []
	for key: String in documents:
		_find_references_in_value(documents[key], "", key, kind, id, member_id, references)
	return references


func _find_references_in_value(value: Variant, path: String, key: String, kind: String, id: String, member_id: String, result: Array[Dictionary]) -> void:
	if value is Dictionary:
		for field: String in value:
			var child_path: String = field if path.is_empty() else path + "." + field
			if (kind == "room" and (field == "blueprint_id" or field == "id" and path.contains("blueprints")) or kind == "composition" and field == "composition_id") and str(value[field]) == id:
				result.append({"document": key, "path": child_path})
			elif not member_id.is_empty() and str(value[field]) == member_id and field in ["port", "port_id", "port_group", "anchor", "anchor_id", "inlet", "outlet"]:
				result.append({"document": key, "path": child_path})
			_find_references_in_value(value[field], child_path, key, kind, id, member_id, result)
	elif value is Array:
		for index: int in range(value.size()):
			_find_references_in_value(value[index], "%s[%d]" % [path, index], key, kind, id, member_id, result)


func _replace_all(next: Dictionary) -> bool:
	if _signature(documents) == _signature(next):
		return false
	if not _gesture_active:
		_push_undo(documents)
	documents = next
	_notify()
	return true


func _push_undo(previous: Dictionary) -> void:
	_undo.append(previous.duplicate(true))
	if _undo.size() > HISTORY_LIMIT:
		_undo.pop_front()
	_redo.clear()


func _notify() -> void:
	revision += 1
	changed.emit(revision)


func _signature(value: Variant) -> String:
	return JSON.stringify(value, "", true)
