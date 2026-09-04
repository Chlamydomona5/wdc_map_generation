class_name WdcGeneratedMapRegionRockStyleCatalog
extends RefCounted

const ROCK_STYLE_WEATHERED_SLATE: String = "weathered_slate"
const ROCK_STYLE_OCHRE_SHALE: String = "ochre_shale"
const ROCK_STYLE_RUST_IRONSTONE: String = "rust_ironstone"
const ROCK_STYLE_VAULT_OBSIDIAN: String = "vault_obsidian"
const DEFAULT_STYLE_ID: String = ROCK_STYLE_WEATHERED_SLATE

const STYLE_ORDER: Array[String] = [
	ROCK_STYLE_WEATHERED_SLATE,
	ROCK_STYLE_OCHRE_SHALE,
	ROCK_STYLE_RUST_IRONSTONE,
	ROCK_STYLE_VAULT_OBSIDIAN,
]
const REGION_ID_TO_STYLE_ID: Dictionary = {
	"ancient_old_mine_regular": ROCK_STYLE_WEATHERED_SLATE,
	"ancient_old_mine_miner_settlement": ROCK_STYLE_OCHRE_SHALE,
	"ancient_old_mine_refinery": ROCK_STYLE_RUST_IRONSTONE,
	"ancient_old_mine_command_vault": ROCK_STYLE_VAULT_OBSIDIAN,
}
const ROLE_TO_FALLBACK_STYLE_ID: Dictionary = {
	"regular": ROCK_STYLE_WEATHERED_SLATE,
	"high_1": ROCK_STYLE_OCHRE_SHALE,
	"high_2": ROCK_STYLE_RUST_IRONSTONE,
	"boss": ROCK_STYLE_VAULT_OBSIDIAN,
}
const STYLES: Dictionary = {
	ROCK_STYLE_WEATHERED_SLATE: {
		"display_name": "风化褐灰岩",
		"wall_color": Color(0.22, 0.20, 0.18, 1.0),
		"mineral_wall_color": Color(0.26, 0.35, 0.42, 1.0),
	},
	ROCK_STYLE_OCHRE_SHALE: {
		"display_name": "赭黄页岩",
		"wall_color": Color(0.48, 0.36, 0.18, 1.0),
		"mineral_wall_color": Color(0.45, 0.46, 0.24, 1.0),
	},
	ROCK_STYLE_RUST_IRONSTONE: {
		"display_name": "锈红铁岩",
		"wall_color": Color(0.50, 0.22, 0.14, 1.0),
		"mineral_wall_color": Color(0.50, 0.32, 0.20, 1.0),
	},
	ROCK_STYLE_VAULT_OBSIDIAN: {
		"display_name": "紫黑金库岩",
		"wall_color": Color(0.44, 0.26, 0.50, 1.0),
		"mineral_wall_color": Color(0.48, 0.30, 0.60, 1.0),
	},
}


static func get_style_ids() -> Array[String]:
	return STYLE_ORDER.duplicate()


static func resolve_style_id(region_id: String, role: String) -> String:
	var exact_style_id: String = str(REGION_ID_TO_STYLE_ID.get(region_id, ""))
	if STYLES.has(exact_style_id):
		return exact_style_id
	var fallback_style_id: String = str(ROLE_TO_FALLBACK_STYLE_ID.get(role, DEFAULT_STYLE_ID))
	return fallback_style_id if STYLES.has(fallback_style_id) else DEFAULT_STYLE_ID


static func get_display_name(style_id: String) -> String:
	return str(_resolve_style(style_id).get("display_name", "风化褐灰岩"))


static func get_wall_color(style_id: String, mineral_wall: bool = false) -> Color:
	var style: Dictionary = _resolve_style(style_id)
	var color_key: String = "mineral_wall_color" if mineral_wall else "wall_color"
	return style.get(color_key, STYLES[DEFAULT_STYLE_ID][color_key]) as Color


static func _resolve_style(style_id: String) -> Dictionary:
	var resolved_style_id: String = style_id if STYLES.has(style_id) else DEFAULT_STYLE_ID
	return STYLES.get(resolved_style_id, STYLES[DEFAULT_STYLE_ID]) as Dictionary
