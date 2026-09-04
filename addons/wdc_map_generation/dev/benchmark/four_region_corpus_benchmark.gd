extends SceneTree

const CONFIG_CATALOG = preload("../../config/data_generated_map_config_catalog.gd")
const MAP_TYPES = preload("../../core/generated_map_types.gd")
const GENERATOR_SCRIPT = preload("../../core/generated_map_generator.gd")
const LAYOUT_PRODUCER_SCRIPT = preload("../../core/four_region_layout_producer.gd")

const CONFIG_FILENAME: String = "ancient_old_mine"
const FIRST_SEED: int = 1
const LAST_SEED: int = 32

var _failures: Array[Dictionary] = []
var _samples: Array[Dictionary] = []


func _init() -> void:
	var raw_config: Dictionary = CONFIG_CATALOG.load_config_dict_by_filename(
		CONFIG_FILENAME
	)
	if raw_config.is_empty():
		_failures.append({"seed": 0, "reason": "canonical config missing"})
		_finish()
		return
	var parse_result: Variant = CONFIG_CATALOG.parse_and_normalize_config(raw_config)
	if parse_result == null or parse_result.call("is_success") != true:
		_failures.append({
			"seed": 0,
			"reason": "canonical config parse failed",
			"issues": parse_result.call("get_issues") if parse_result != null else [],
		})
		_finish()
		return
	var base_config: Variant = parse_result.get("config")
	var max_attempts: int = int(
		LAYOUT_PRODUCER_SCRIPT.new().call("get_max_attempts", base_config)
	)
	for seed_value: int in range(FIRST_SEED, LAST_SEED + 1):
		_run_seed(base_config, seed_value, max_attempts)
	_finish()


func _run_seed(base_config: Variant, seed_value: int, max_attempts: int) -> void:
	var config: Variant = base_config.call("deep_clone")
	config.set("seed", seed_value)
	var generator: RefCounted = GENERATOR_SCRIPT.new()
	var generation_started_usec: int = Time.get_ticks_usec()
	var map_data: Variant = generator.call("generate_full", config)
	var generation_usec: int = Time.get_ticks_usec() - generation_started_usec
	var success_attempt: int = int(generator.get("last_four_region_success_attempt"))
	if map_data == null or success_attempt < 0 or success_attempt >= max_attempts:
		_failures.append({
			"seed": seed_value,
			"reason": "generation failed or attempt out of range",
			"success_attempt": success_attempt,
			"max_attempts": max_attempts,
			"issues": generator.call("get_last_generation_issues"),
		})
		return

	var encode_started_usec: int = Time.get_ticks_usec()
	var payload: Variant = MAP_TYPES.build_server_payload_from_runtime(
		map_data,
		[],
		1.0,
		seed_value,
		1,
		map_data.get("extraction_sites")
	)
	if payload == null or payload.get("is_valid") != true:
		_failures.append({
			"seed": seed_value,
			"reason": "payload build failed",
			"issues": payload.call("get_issues") if payload != null else [],
		})
		return
	var payload_dict: Dictionary = payload.call("to_dict") as Dictionary
	var payload_raw: PackedByteArray = var_to_bytes(payload_dict)
	var payload_wire: PackedByteArray = payload_raw.compress(
		FileAccess.COMPRESSION_FASTLZ
	)
	var region_plan_dict: Dictionary = payload_dict.get("region_plan", {}) as Dictionary
	var region_plan_raw: PackedByteArray = var_to_bytes(region_plan_dict)
	var region_plan_wire: PackedByteArray = region_plan_raw.compress(
		FileAccess.COMPRESSION_FASTLZ
	)
	var encode_usec: int = Time.get_ticks_usec() - encode_started_usec

	var decode_started_usec: int = Time.get_ticks_usec()
	var decoded_raw: PackedByteArray = payload_wire.decompress(
		payload_raw.size(),
		FileAccess.COMPRESSION_FASTLZ
	)
	var decoded_variant: Variant = bytes_to_var(decoded_raw)
	var decoded_payload: Variant = MAP_TYPES.server_payload_from_variant(decoded_variant)
	var decode_usec: int = Time.get_ticks_usec() - decode_started_usec
	if decoded_payload == null or decoded_payload.get("is_valid") != true:
		_failures.append({
			"seed": seed_value,
			"reason": "payload decode failed",
			"issues": (
				decoded_payload.call("get_issues") if decoded_payload != null else []
			),
		})
		return

	_samples.append({
		"seed": seed_value,
		"success_attempt": success_attempt,
		"generation_usec": generation_usec,
		"full_payload_raw_bytes": payload_raw.size(),
		"full_payload_wire_bytes": payload_wire.size(),
		"region_plan_raw_bytes": region_plan_raw.size(),
		"region_plan_wire_bytes": region_plan_wire.size(),
		"encode_usec": encode_usec,
		"decode_usec": decode_usec,
	})


func _finish() -> void:
	var result: Dictionary = {
		"benchmark": "ancient_old_mine_four_region_corpus",
		"config_filename": CONFIG_FILENAME,
		"seed_range": {"first": FIRST_SEED, "last": LAST_SEED},
		"sample_count": _samples.size(),
		"failure_count": _failures.size(),
		"samples": _samples,
		"failures": _failures,
		"summary": _build_summary(),
		"acceptance": {
			"passed": _failures.is_empty()
			and _samples.size() == LAST_SEED - FIRST_SEED + 1,
			"required_successful_seeds": LAST_SEED - FIRST_SEED + 1,
		},
	}
	var output_path: String = _resolve_output_path()
	if not output_path.is_empty():
		var output_dir: String = output_path.get_base_dir()
		var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(output_dir)
		if make_dir_error != OK:
			_failures.append({
				"seed": 0,
				"reason": "cannot create output directory",
				"error": make_dir_error,
			})
			result["failures"] = _failures
			(result["acceptance"] as Dictionary)["passed"] = false
		else:
			var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
			if file == null:
				_failures.append({
					"seed": 0,
					"reason": "cannot open output file",
				})
				result["failures"] = _failures
				(result["acceptance"] as Dictionary)["passed"] = false
			else:
				file.store_string(JSON.stringify(result, "\t"))
				file.flush()
				file = null
	print("FourRegionCorpusBenchmark: %s" % JSON.stringify(result))
	if (result.get("acceptance", {}) as Dictionary).get("passed", false) == true:
		quit(0)
		return
	push_error("FourRegionCorpusBenchmark: seeds 1..32 未全部通过")
	quit(1)


func _build_summary() -> Dictionary:
	if _samples.is_empty():
		return {}
	var metric_names: Array[String] = [
		"success_attempt",
		"generation_usec",
		"full_payload_raw_bytes",
		"full_payload_wire_bytes",
		"region_plan_raw_bytes",
		"region_plan_wire_bytes",
		"encode_usec",
		"decode_usec",
	]
	var summary: Dictionary = {}
	for metric_name: String in metric_names:
		var minimum_value: int = 9223372036854775807
		var maximum_value: int = -9223372036854775807
		var total_value: int = 0
		for sample: Dictionary in _samples:
			var metric_value: int = int(sample.get(metric_name, 0))
			minimum_value = mini(minimum_value, metric_value)
			maximum_value = maxi(maximum_value, metric_value)
			total_value += metric_value
		summary[metric_name] = {
			"min": minimum_value,
			"max": maximum_value,
			"average": float(total_value) / float(_samples.size()),
		}
	return summary


func _resolve_output_path() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=").strip_edges()
	return ""
