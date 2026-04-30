# WDC Map Generation

这是 WDC 地图生成的独立工作区，目标是作为主游戏仓库的 `map_generation/` submodule 使用。

## 独立预览

用 Godot 打开本目录的 `project.godot`，会进入 `map_generation_preview` 场景。预览场景支持：

- 从 `addons/wdc_map_generation/config/generated_map_configs/` 读取地图配置。
- 使用当前 seed 重新生成。
- 使用随机 seed 重新生成。
- 显示地板、墙体、矿物、POI、trace、玩家出生点与怪物点位。

## 主仓接入

主仓应通过 `map_generation/addons/wdc_map_generation/` 引用生成能力，并保留 gameplay runtime adapter。正式战局的地图真相仍由主仓 authority runtime 持有，submodule 只提供纯生成、配置和预览工具能力。

