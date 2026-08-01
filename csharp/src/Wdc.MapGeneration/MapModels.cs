using System.Text.Json.Nodes;

namespace Wdc.MapGeneration;

public enum CellType
{
    Wall,
    Floor,
}

public enum PoiType
{
    None,
    LargeRuin,
    MediumBiome,
    SmallOre,
}

public enum SpecialBlockType
{
    None,
    RareMineral,
    Turquoise,
    Amethyst,
    Gold,
    PoiWall,
    Spike,
    ExplosiveOre,
    ArrowSlit,
    PressurePlate,
}

public enum ServerTileType
{
    Empty,
    Wall,
    MineralWall,
    RareMineralWall,
    TurquoiseOre,
    AmethystOre,
    GoldBlock,
    PoiWall,
    SpikeTile,
    ExplosiveOreTile,
    ArrowSlitTile,
    PressurePlateTile,
}

public sealed class CellData
{
    public int X { get; init; }
    public int Y { get; init; }
    public CellType CellType { get; set; } = CellType.Wall;
    public PoiType PoiType { get; set; } = PoiType.None;
    public int BiomeId { get; set; } = -1;
    public PoiType TraceType { get; set; } = PoiType.None;
    public bool IsPoiProtected { get; set; }
    public bool HasMineral { get; set; }
    public SpecialBlockType SpecialBlockType { get; set; } = SpecialBlockType.None;
    public int CurrentHitPoints { get; set; }
    public int MaxHitPoints { get; set; }
    public ServerTileType? DurabilityTileType { get; set; }
    public int DurabilityOverrideMaxHitPoints { get; set; }
}

public sealed record PoiCenter(Int2 Cell, PoiType PoiType, string TemplateId, string LayerId);

public sealed class CorridorData
{
    public int FromRoom { get; init; }
    public int ToRoom { get; init; }
    public Int2 FromDoor { get; init; }
    public Int2 ToDoor { get; init; }
    public List<Int2> Cells { get; } = [];
}

public sealed class GuardSite
{
    public Int2 Cell { get; init; }
    public string MonsterId { get; init; } = string.Empty;
    public string TemplateId { get; init; } = string.Empty;
}

public sealed class RoomContentPlan
{
    public int RoomIndex { get; init; }
    public string RoomKind { get; init; } = string.Empty;
    public IntRect RoomRect { get; init; }
    public string ContentKind { get; set; } = "none";
    public string TemplateId { get; set; } = string.Empty;
    public Int2 AnchorCell { get; set; }
    public string LayerId { get; set; } = string.Empty;
    public string EncounterId { get; set; } = string.Empty;
    public Int2? ChestCell { get; set; }
    public List<GuardSite> GuardSites { get; } = [];
    public JsonObject LootContainer { get; set; } = [];
    public string LockedPromptText { get; set; } = "需要击败房间中的所有怪物";
    internal bool IsInvalid { get; set; }
}

public sealed class PoiInstance
{
    public string TemplateId { get; init; } = string.Empty;
    public PoiType PoiType { get; init; }
    public string LayerId { get; init; } = string.Empty;
    public IntRect Bounds { get; init; }
    public IntRect MainRoom { get; init; }
    public List<IntRect> SubRooms { get; } = [];
    public List<CorridorData> Corridors { get; } = [];
    public Int2 CenterCell { get; init; }
    public List<Int2> TorchSites { get; } = [];
    public List<RoomContentPlan> RoomContentPlans { get; } = [];
}

public sealed class MonsterSite
{
    public string SiteKind { get; init; } = string.Empty;
    public string RoomKind { get; init; } = string.Empty;
    public Int2 Cell { get; init; }
    public string TemplateId { get; init; } = string.Empty;
    public string MonsterId { get; init; } = string.Empty;
    public string NestUnitId { get; init; } = string.Empty;
    public string LootTableId { get; init; } = string.Empty;
    public double ActivationRadiusM { get; init; }
    public double SpawnIntervalSec { get; init; }
    public int MaxAliveChildren { get; init; }
    public int MaxHitPoints { get; init; }
    public string LayerId { get; init; } = string.Empty;
}

public sealed class CampEncounter
{
    public string EncounterId { get; init; } = string.Empty;
    public string PoiTemplateId { get; init; } = string.Empty;
    public string LayerId { get; init; } = string.Empty;
    public int RoomIndex { get; init; }
    public string RoomKind { get; init; } = string.Empty;
    public IntRect RoomRect { get; init; }
    public Int2 ChestCell { get; init; }
    public List<GuardSite> GuardSites { get; } = [];
    public JsonObject LootContainer { get; init; } = [];
    public string LockedPromptText { get; init; } = string.Empty;
}

public sealed class TrapSite
{
    public string TrapKind { get; init; } = string.Empty;
    public Int2? Cell { get; init; }
    public List<Int2> Nodes { get; } = [];
    public Dictionary<string, string> Metadata { get; } = new(StringComparer.Ordinal);
    public string LayerId { get; init; } = string.Empty;
}

public sealed class MapSite
{
    public Int2 Cell { get; init; }
    public string SiteKind { get; init; } = string.Empty;
    public string LayerId { get; init; } = string.Empty;
    public string RequestedLayerId { get; init; } = string.Empty;
    public string FallbackReason { get; init; } = string.Empty;
}

public sealed class MapData
{
    private readonly CellData[,] _grid;

    public MapData(int width, int height, int resolvedSeed)
    {
        if (width <= 0 || height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width), "地图尺寸必须为正数。");
        }

        Width = width;
        Height = height;
        ResolvedSeed = resolvedSeed;
        _grid = new CellData[height, width];
        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++)
            {
                _grid[y, x] = new CellData { X = x, Y = y };
            }
        }
    }

    public int Width { get; }
    public int Height { get; }
    public int ResolvedSeed { get; }
    public List<PoiCenter> PoiCenters { get; } = [];
    public List<PoiInstance> PoiInstances { get; } = [];
    public List<MapSite> PlayerSpawnPoints { get; } = [];
    public List<MapSite> ExtractionSites { get; } = [];
    public List<MonsterSite> MonsterSites { get; } = [];
    public List<CampEncounter> CampEncounters { get; } = [];
    public List<TrapSite> TrapSites { get; } = [];
    public int TotalFloor { get; internal set; }
    public int LargePois { get; internal set; }
    public int MediumPois { get; internal set; }
    public int SmallPois { get; internal set; }

    public bool IsInBounds(int x, int y) => x >= 0 && x < Width && y >= 0 && y < Height;
    public bool IsInBounds(Int2 cell) => IsInBounds(cell.X, cell.Y);

    public CellData GetCell(int x, int y) =>
        IsInBounds(x, y) ? _grid[y, x] : throw new ArgumentOutOfRangeException(nameof(x));

    public CellData GetCell(Int2 cell) => GetCell(cell.X, cell.Y);

    public ServerTileType[][] ToTileMatrix()
    {
        var matrix = new ServerTileType[Height][];
        for (var y = 0; y < Height; y++)
        {
            matrix[y] = new ServerTileType[Width];
            for (var x = 0; x < Width; x++)
            {
                matrix[y][x] = TileRules.EncodeServerTile(_grid[y, x]);
            }
        }

        return matrix;
    }
}
