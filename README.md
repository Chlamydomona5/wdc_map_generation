# WDC Map Generation

这是 WDC 地图生成的独立工作区，目标是作为主游戏仓库的 `map_generation/` submodule 使用。

## 独立预览

用 Godot 打开本目录的 `project.godot`，会进入 `map_generation_preview` 场景。预览场景支持：

- 从 `addons/wdc_map_generation/config/generated_map_configs/` 读取地图配置。
- 使用当前 seed 重新生成。
- 使用随机 seed 重新生成。
- 显示地板、墙体、矿物、POI、trace、玩家出生点与怪物点位。

## POI 房间配置器

同一入口的“POI 房间配置器”包含房间布局、POI 组装和生成验证三个工作页。主仓 `map_view` 使用相同入口。

1. 在房间库“新建”稳定 ID，用地板、墙和擦除画笔绘制空间；Shift 绘制矩形。选择门、槽或锚点后在画布布点，右栏设置用途、法向、候选内容、数量及净空。中键或空格拖动平移，滚轮缩放。
2. 使用“复制变体”制作其他户型。在组装页添加房间节点和候选图纸，设置权重、数量、重复上限与正交旋转；添加一对一、逐个接入或顺序串联连接，选择具名门或接口组。重复组可使用首、尾实例。
3. 先运行单房和单 POI 多 seed 验证，再选择地图及 POI 条目，“绑定当前组合”后执行完整地图验证。最后“校验并保存到项目”；错误会定位到房间、端口、槽或组合节点。

生成结果保持只读，双击房间可跳回来源图纸并选中对应局部格；旋转后的房间也会还原原图纸坐标。单房验证同样使用正式组装器检查内容可用性、占地、净空与房内通路。守卫相对点只用于营地内容槽。

连接选择“走廊（含侧墙）”时，在房间门口之间生成至少两格长的通行地板及一格厚的侧墙、拐角包边；宽度与接口一致。侧墙参与占地与路径搜索，不能穿过房间、外部入口或必要净空。显式“直接对接”仍表示两个门口相邻拼接。矿工聚落和精炼车间的默认组合均使用走廊。

画布与属性面板共用文档模型，支持撤销、重做和草稿恢复。图节点拖动只改变图的排版；实际生成位置由“固定空间位置”约束控制。项目保存会检查引用和外部文件冲突，失败不会写入不完整资源。高级 JSON 编辑也通过同一文档模型提交。

重新载入项目之前会保存当前草稿；保存失败时保留编辑内容并停止重载。完整地图预览显示实际使用的地图依赖闭包哈希，未被该地图引用的图纸不影响此哈希。

房间允许非矩形地板、显式墙、未写入地形和开放侧；坐标使用 0–127 整数格，变换使用 0/90/180/270 度。房间保存到 `config/poi_rooms/`，组合保存到 `config/poi_compositions/`，地图 schema v3 通过 `layout_kind=authored_rooms` 和 `composition_id` 引用组合。上述 `config/` 均位于 `addons/wdc_map_generation/`。v1/v2 的旧矩形地图继续按原有语义运行。

首批内容包括矿工聚落的围院/沿巷、精炼车间的直列/U 形，以及使用具名出生、奖励门和奖励装置锚点的总控金库。床铺、餐桌、公共炉灶、熔炉、工作台和物资木箱通过主仓正式实体表现。配置器只选择已接入的内容；能力快照 `config/poi_capabilities/content_capabilities.json` 由主仓 `tools/export_poi_content_capabilities_tool.gd` 从主仓配置表与本目录四区域档案导出，不在工具里修改内容实现。

单房和单 POI 验证只检查局部组装；区域数量、价值预算和人口上限须通过完整地图验证。BOSS 可编辑已存在的受约束奖励配方引用及具名锚点，不能创建任意运行脚本或奖励规则。正式战局在开局读取依赖快照，保存图纸不改变已经开始的战局。

### POI Only 测试地图

在“生成验证”页选择源地图和 POI 条目，使用当前组合及 seed 点击“生成 POI Only 测试地图”。工具生成一个真实 POI、外围出生区和撤离点，沿用所选条目的内容规则、预算及人口上限，不补充随机环境内容；结果可在整图预览中查看。

点击“保存并启动正式测试”会重新验证当前配置，将 `poi_test_<composition_id>.json` 与相关图纸、组合一起保存（档案在 `config/generated_map_configs/`），再启动 WDC 主干正式入口（`scenes/app/main.tscn`），附带 `--map-profile=poi_test_<composition_id>` 与当前 `--map-seed`。从封面进入基地大厅后点击 Solo 或 Host，生成地图开局就使用这份档案。主干只从 `config/generated_map_configs/` 读取生成参数档案，保存后无需复制。保存失败不会启动游戏；找不到 WDC 主干（含 `scenes/app/main.tscn` 与 `map_generation/` 的上级目录）或档案不是四区域 / POI Only 布局时会显示原因，已保存配置仍可保留。

项目附带 `poi_test_miners_settlement.json` 和 `poi_test_refining_workshop.json` 两份 seed 1 示例，分别继承古老矿区的矿工聚落与精炼车间内容条目，可用主干启动参数 `-- --map-profile=<文件名>` 测试。

## 验证

使用 `godot --headless --path . --script res://addons/wdc_map_generation/dev/smoke/<文件名>` 运行 `poi_composition_smoke.gd`、`poi_room_editor_smoke.gd`、`poi_only_smoke.gd` 和 `authored_poi_pipeline_smoke.gd`。编辑器另需有窗检查真实布局；完整地图继续由 `ancient_old_mine_smoke.gd` 与 `dev/benchmark/four_region_corpus_benchmark.gd` 守门，旧行为由 `legacy_fixed_seed_golden_smoke.gd` 守门。正式游戏内效果由主仓的 Solo/Host/Join 流程验收。

## 主仓接入

主仓应通过 `map_generation/addons/wdc_map_generation/` 引用生成能力，并保留 gameplay runtime adapter。正式战局的地图真相仍由主仓 authority runtime 持有，submodule 只提供纯生成、配置和预览工具能力。

