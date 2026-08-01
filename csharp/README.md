# WDC C# Map Generation

这是 generated-map 算法的纯 .NET 8 移植版，可用于不启动 Godot 的工具、服务和离线分析程序。

## 使用

```csharp
using Wdc.MapGeneration;

var config = MapConfigLoader.Load(
    "addons/wdc_map_generation/config/generated_map_configs/default_generated_map.json");
config.Seed = 12345;

var map = new MapGenerator().Generate(config);
ServerTileType[][] tiles = map.ToTileMatrix();

Console.WriteLine($"{map.Width}x{map.Height}, seed={map.ResolvedSeed}");
```

`MapData` 除 tile matrix 外，还保留 POI、走廊、火把、房间内容、怪物与巢穴点位、营地、陷阱、玩家出生点、撤离点、分层耐久和统计信息。配置 seed 为 `0` 时，生成结果的 `ResolvedSeed` 可用于重放本次结果。

## 项目结构

- `src/Wdc.MapGeneration/`：`net8.0` 类库，仅依赖 .NET 标准库。
- `tests/Wdc.MapGeneration.Tests/`：xUnit 行为测试，直接读取 submodule 现有 JSON 配置作为 fixture。
- `Wdc.MapGeneration.sln`：构建和测试入口。

## 边界

- 固定 seed 只保证同一 C# 实现内可复现，不保证与 GDScript 逐格一致。
- 本实现不依赖 Godot 或 GodotSharp，也不替换现有 GDScript 生成入口。
- 不包含 ambient monster 后处理、tile loot、网络与 runtime payload、spawn runtime、visibility、preview UI 或 authority 集成。
- GDScript 算法规则发生变化时，需要同步评估并更新 C# 移植版。

## 验证

在 `map_generation/` 目录运行：

```powershell
dotnet restore csharp/Wdc.MapGeneration.sln
dotnet build csharp/Wdc.MapGeneration.sln --configuration Release --no-restore
dotnet test csharp/Wdc.MapGeneration.sln --configuration Release --no-build
```
