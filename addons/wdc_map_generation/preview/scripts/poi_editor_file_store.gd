extends RefCounted

## 项目保存先校验指纹，再通过带回滚记录的事务替换；草稿从不写入项目。
const RECOVERY_ROOT: String = "user://poi_room_editor"
var content_root: String = ""
var recovery_root: String = RECOVERY_ROOT


func configure(root_path: String, draft_root: String = RECOVERY_ROOT) -> void:
	content_root = ProjectSettings.globalize_path(root_path).replace("\\", "/").trim_suffix("/")
	recovery_root = draft_root
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(recovery_root))


func document_path(key: String) -> String:
	var parts: PackedStringArray = key.split("/")
	if parts.size() != 2 or not _valid_id(parts[1]):
		return ""
	var folder: String = {"room": "poi_rooms", "composition": "poi_compositions", "map": "generated_map_configs"}.get(parts[0], "")
	if folder.is_empty():
		return ""
	return "%s/%s/%s.json" % [content_root, folder, parts[1]]


func load_project() -> Dictionary:
	var documents: Dictionary = {}
	var hashes: Dictionary = {}
	var issues: Array[Dictionary] = []
	for kind: String in ["room", "composition", "map"]:
		var folder: String = document_path(kind + "/probe").get_base_dir()
		var directory: DirAccess = DirAccess.open(folder)
		if directory == null:
			continue
		for filename: String in directory.get_files():
			if not filename.ends_with(".json"):
				continue
			var key: String = kind + "/" + filename.get_basename()
			var path: String = document_path(key)
			if path.is_empty():
				continue
			var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if source is Dictionary:
				documents[key] = source
				hashes[key] = FileAccess.get_sha256(path)
			else:
				issues.append({"document": key, "path": "", "message": "文件不是有效 JSON 对象"})
	return {"documents": documents, "hashes": hashes, "issues": issues}


func save_draft(snapshot: Dictionary) -> Error:
	return _write_atomic(recovery_root.path_join("draft.json"), JSON.stringify(snapshot, "  "))


func load_draft() -> Dictionary:
	var path: String = recovery_root.path_join("draft.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func save_tool_state(selection: Dictionary, view_state: Dictionary) -> Error:
	return _write_atomic(recovery_root.path_join("tool_state.json"), JSON.stringify({"selection": selection, "view_state": view_state}, "  "))


func load_tool_state() -> Dictionary:
	var path: String = recovery_root.path_join("tool_state.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func save_project(documents: Dictionary, changed_keys: Array[String], baseline_hashes: Dictionary) -> Dictionary:
	var recovery: Dictionary = recover_transaction()
	if not bool(recovery.get("ok", false)):
		return recovery
	# 本次校验使用了整份会话快照；依赖文件外部变化后不能继续按旧快照保存关联规则。
	if not changed_keys.is_empty():
		for key: String in baseline_hashes:
			var path: String = document_path(key)
			var current_hash: String = FileAccess.get_sha256(path) if not path.is_empty() and FileAccess.file_exists(path) else ""
			if current_hash != str(baseline_hashes[key]):
				return _failure("关联文件已由外部修改；请保存草稿并重新载入后校验", key)
	var entries: Array[Dictionary] = []
	for key: String in changed_keys:
		var path: String = document_path(key)
		if path.is_empty():
			return _failure("非法文档 ID", key)
		var current_hash: String = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
		if current_hash != str(baseline_hashes.get(key, "")):
			return _failure("文件已由外部修改；请保存草稿并重新载入，不能覆盖外部版本", key)
		var after_text: String = JSON.stringify(documents[key], "  ", true) + "\n" if documents.has(key) else ""
		entries.append({"key": key, "before_exists": FileAccess.file_exists(path), "before": FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "", "before_hash": current_hash, "after_exists": documents.has(key), "after": after_text, "after_hash": after_text.sha256_text() if documents.has(key) else ""})
	if entries.is_empty():
		return {"ok": true, "hashes": baseline_hashes.duplicate(true)}
	var journal: Dictionary = {"schema_version": 1, "root": content_root, "entries": entries}
	if _write_atomic(_journal_path(), JSON.stringify(journal, "  ")) != OK:
		return _failure("无法写入保存事务记录，项目文件未修改")
	for entry: Dictionary in entries:
		var path: String = document_path(str(entry["key"]))
		var write_error: Error = OK
		if bool(entry["after_exists"]):
			write_error = _write_atomic(path, str(entry["after"]))
		elif FileAccess.file_exists(path):
			write_error = DirAccess.remove_absolute(path)
		if write_error != OK:
			var rollback: Dictionary = recover_transaction()
			return _failure("写入失败，%s" % ("已恢复原文件" if bool(rollback.get("ok", false)) else "恢复记录已保留，需解决磁盘或外部文件冲突"), str(entry["key"]))
	var hashes: Dictionary = baseline_hashes.duplicate(true)
	for entry: Dictionary in entries:
		if bool(entry["after_exists"]):
			hashes[entry["key"]] = entry["after_hash"]
		else:
			hashes.erase(entry["key"])
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(_journal_path())) != OK:
		# 未清除事务记录不能报告提交完成；下次打开会回滚。
		recover_transaction()
		return _failure("事务记录无法清除，保存已回滚")
	return {"ok": true, "hashes": hashes}


func recover_transaction() -> Dictionary:
	if not FileAccess.file_exists(_journal_path()):
		return {"ok": true, "recovered": false}
	var journal: Variant = JSON.parse_string(FileAccess.get_file_as_string(_journal_path()))
	if not journal is Dictionary or str(journal.get("root", "")) != content_root:
		return _failure("保存事务归属不匹配；恢复记录保留")
	var entries: Array = journal.get("entries", [])
	for entry: Dictionary in entries:
		var path: String = document_path(str(entry.get("key", "")))
		if path.is_empty():
			return _failure("保存事务含非法文档路径；恢复记录保留")
		var actual_hash: String = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
		if actual_hash not in [str(entry.get("before_hash", "")), str(entry.get("after_hash", ""))]:
			return _failure("待恢复文件再次被外部修改；请先解决冲突，恢复记录保留", str(entry["key"]))
	for entry: Dictionary in entries:
		var path: String = document_path(str(entry["key"]))
		var error: Error = OK
		if bool(entry.get("before_exists", false)):
			error = _write_atomic(path, str(entry["before"]))
		elif FileAccess.file_exists(path):
			error = DirAccess.remove_absolute(path)
		if error != OK:
			return _failure("恢复保存事务失败，记录保留", str(entry["key"]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_journal_path()))
	return {"ok": true, "recovered": true}


func _write_atomic(path: String, contents: String) -> Error:
	var absolute: String = ProjectSettings.globalize_path(path)
	var folder_error: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if folder_error != OK:
		return folder_error
	var temporary: String = absolute + ".poi-tmp"
	var stream: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if stream == null:
		return FileAccess.get_open_error()
	stream.store_string(contents)
	stream.flush()
	var write_error: Error = stream.get_error()
	stream.close()
	if write_error != OK:
		return write_error
	return DirAccess.rename_absolute(temporary, absolute)


func _journal_path() -> String:
	return recovery_root.path_join("save_transaction.json")


func _valid_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in range(value.length()):
		var character: int = value.unicode_at(index)
		if not (character >= 48 and character <= 57 or character >= 65 and character <= 90 or character >= 97 and character <= 122 or character in [45, 95]):
			return false
	return true


func _failure(message: String, key: String = "") -> Dictionary:
	return {"ok": false, "issues": [{"document": key, "path": "", "message": message}]}
