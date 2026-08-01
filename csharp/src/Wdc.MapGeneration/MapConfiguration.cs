using System.Text.Json.Nodes;

namespace Wdc.MapGeneration;

public sealed class MapLayerConfig
{
    public string Id { get; set; } = string.Empty;
    public double MaxRadiusCells { get; set; }
    public double MaxRadiusRatio { get; set; }
    public int StoneMaxHitPoints { get; set; } = 1;
    public double MineralBudgetWeight { get; set; } = 1;
    public double PoiBudgetWeight { get; set; } = 1;
    public double TrapBudgetWeight { get; set; } = 1;
    public double MonsterBudgetWeight { get; set; } = 1;
    public double RoomContentDangerMultiplier { get; set; } = 1;
    public double BoundaryNoiseAmplitudeCells { get; set; }
    public double BoundaryNoiseScaleCells { get; set; } = 16;
    public int BoundaryNoiseOctaves { get; set; } = 1;
    public double BoundaryNoisePersistence { get; set; } = 0.5;
    public int BoundaryNoiseSeedOffset { get; set; }
}

public sealed class MineralClusterConfig
{
    public string Id { get; set; } = string.Empty;
    public bool Enabled { get; set; } = true;
    public string TileTypeId { get; set; } = string.Empty;
    public string SpawnScope { get; set; } = "global";
    public double Weight { get; set; }
    public int MinClusterSize { get; set; } = 1;
    public int MaxClusterSize { get; set; } = 1;
    public bool RequireStone { get; set; } = true;
    public double SpawnProbability { get; set; }
}

public class RoomSizeConfig
{
    public int WidthMin { get; set; } = 1;
    public int WidthMax { get; set; } = 1;
    public int HeightMin { get; set; } = 1;
    public int HeightMax { get; set; } = 1;
}

public sealed class SubRoomConfig : RoomSizeConfig
{
    public int CountMin { get; set; }
    public int CountMax { get; set; }
    public int MinGapFromRoomsCells { get; set; } = 1;
    public int PlacementRadiusMinCells { get; set; } = 1;
    public int PlacementRadiusMaxCells { get; set; } = 1;
    public int PlacementAttemptsPerRoom { get; set; } = 12;
}

public sealed class PoiPlacementConfig
{
    public int FootprintPaddingCells { get; set; }
    public double MinDistanceFromOtherPoisCells { get; set; }
    public int PoiAttempts { get; set; } = 40;
    public int RoomAttempts { get; set; } = 20;
}

public sealed class PoiConnectivityConfig
{
    public int CandidateNeighborsPerRoom { get; set; } = 2;
    public double ExtraConnectionChance { get; set; }
    public int MaxExtraConnections { get; set; }
}

public sealed class PoiCorridorConfig
{
    public int WidthCells { get; set; } = 1;
    public int RetryDoorwayCount { get; set; } = 1;
    public int DoorMarginFromCornerCells { get; set; } = 1;
    public string BendOrderMode { get; set; } = "random";
}

public sealed class TraceConfig
{
    public bool Enabled { get; set; } = true;
    public double RadiusCells { get; set; }
    public double DensityRatio { get; set; }
    public double Rays { get; set; } = 1;
    public double Twist { get; set; } = 1;
}

public sealed class TorchConfig
{
    public bool Enabled { get; set; }
    public int CoverageRadiusCells { get; set; } = 4;
    public int MaxTorchCount { get; set; }
    public bool PreferPerimeter { get; set; } = true;
    public int WallInsetCells { get; set; } = 1;
}

public sealed class WeightedTemplateEntry
{
    public string Id { get; set; } = string.Empty;
    public double Weight { get; set; }
}

public sealed class CampEntryConfig
{
    public string Id { get; set; } = string.Empty;
    public double Weight { get; set; }
    public int GuardCountMin { get; set; } = 1;
    public int GuardCountMax { get; set; } = 1;
    public int ChestAvoidRadiusCells { get; set; } = 1;
    public int? MinDistanceFromDoorCells { get; set; }
    public List<WeightedTemplateEntry> GuardEntries { get; } = [];
    public JsonObject LootContainer { get; set; } = [];
    public string LockedPromptText { get; set; } = "需要击败房间中的所有怪物";
}

public sealed class RoomContentRollConfig
{
    public double NoneWeight { get; set; }
    public int MinDistanceFromDoorCells { get; set; }
    public List<WeightedTemplateEntry> MonsterEntries { get; } = [];
    public List<WeightedTemplateEntry> NestEntries { get; } = [];
    public List<CampEntryConfig> CampEntries { get; } = [];
}

public sealed class CenterOreClusterConfig
{
    public bool Enabled { get; set; }
    public string ClusterOverrideId { get; set; } = string.Empty;
    public int AvoidRadiusCells { get; set; } = 1;
}

public sealed class PoiTemplateConfig
{
    public string Id { get; set; } = string.Empty;
    public bool Enabled { get; set; } = true;
    public int Count { get; set; }
    public string DedicatedMineralId { get; set; } = string.Empty;
    public RoomSizeConfig MainRoom { get; set; } = new();
    public SubRoomConfig SubRooms { get; set; } = new();
    public PoiPlacementConfig Placement { get; set; } = new();
    public PoiConnectivityConfig Connectivity { get; set; } = new();
    public PoiCorridorConfig Corridor { get; set; } = new();
    public TraceConfig Trace { get; set; } = new();
    public TorchConfig Torch { get; set; } = new();
    public RoomContentRollConfig MainRoomRoll { get; set; } = new();
    public RoomContentRollConfig SubRoomRoll { get; set; } = new();
    public CenterOreClusterConfig CenterOreCluster { get; set; } = new();
}

public sealed class IsolatedSpawnTemplate
{
    public string Id { get; set; } = string.Empty;
    public string MonsterId { get; set; } = string.Empty;
}

public sealed class NestTemplate
{
    public string Id { get; set; } = string.Empty;
    public string NestUnitId { get; set; } = string.Empty;
    public string MonsterId { get; set; } = string.Empty;
    public string LootTableId { get; set; } = string.Empty;
    public double ActivationRadiusM { get; set; }
    public double SpawnIntervalSec { get; set; }
    public int MaxAliveChildren { get; set; }
    public int MaxHitPoints { get; set; }
}

public sealed class SiteLayerRatio
{
    public string LayerId { get; set; } = string.Empty;
    public double Ratio { get; set; }
}

public sealed class MapConfig
{
    public int Width { get; set; } = 64;
    public int Height { get; set; } = 64;
    public int Seed { get; set; }
    public double FillPercent { get; set; } = 0.60;
    public int SmoothIterations { get; set; } = 4;
    public int LargePoiCount { get; set; } = 3;
    public double LargePoiMinDistance { get; set; } = 15;
    public int LargePoiRadius { get; set; } = 5;
    public double LargePoiIrregularity { get; set; } = 0.8;
    public int LargePoiSpecialBlockCount { get; set; } = 1;
    public int MediumPoiCount { get; set; } = 12;
    public double MediumPoiMinDistance { get; set; } = 10;
    public int MediumPoiRadius { get; set; } = 3;
    public double MediumPoiIrregularity { get; set; } = 0.5;
    public int MediumPoiSpecialBlockCount { get; set; } = 1;
    public int SmallPoiCount { get; set; } = 50;
    public double SmallPoiMinDistance { get; set; } = 2;
    public int SmallPoiRadius { get; set; }
    public double SmallPoiIrregularity { get; set; }
    public int SmallPoiSpecialBlockCount { get; set; } = 1;
    public int CorridorCount { get; set; } = 8;
    public int CorridorWidth { get; set; } = 3;
    public double CorridorLength { get; set; } = 0.6;
    public double CorridorWobble { get; set; } = 0.2;
    public double TraceLargeRadius { get; set; } = 15;
    public double TraceLargeDensity { get; set; } = 0.95;
    public double TraceLargeRays { get; set; } = 7;
    public double TraceLargeTwist { get; set; } = 1.2;
    public double TraceMediumRadius { get; set; } = 8;
    public double TraceMediumDensity { get; set; } = 0.70;
    public double TraceMediumRays { get; set; } = 5;
    public double TraceMediumTwist { get; set; } = 0.9;
    public double TraceSmallRadius { get; set; } = 4;
    public double TraceSmallDensity { get; set; } = 0.50;
    public double TraceSmallRays { get; set; } = 3;
    public double TraceSmallTwist { get; set; } = 1.4;
    public double MineralBaseChance { get; set; } = 0.02;
    public double MineralExposedChance { get; set; } = 0.08;
    public int MineralMinDistanceBetweenClusterSeedsCells { get; set; }
    public bool MineralAllowClustersInsidePoiRooms { get; set; }
    public bool MineralAllowClustersUnderPoiCorridors { get; set; }
    public List<MineralClusterConfig> MineralClusterTypes { get; } = [];
    public List<MineralClusterConfig> MineralClusterOverrides { get; } = [];
    public List<PoiTemplateConfig> PoiTemplates { get; } = [];
    public List<MapLayerConfig> MapLayers { get; } = [];
    public List<IsolatedSpawnTemplate> IsolatedSpawnTemplates { get; } = [];
    public List<NestTemplate> NestTemplates { get; } = [];
    public int PlayerSpawnCount { get; set; } = 2;
    public string PlayerSpawnLayerId { get; set; } = "outer";
    public int PlayerSpawnEdgeMarginCells { get; set; } = 6;
    public double PlayerSpawnMinDistanceBetweenSpawnsCells { get; set; } = 10;
    public int PlayerSpawnClearanceRadiusCells { get; set; } = 2;
    public double PlayerSpawnMinClearanceRatio { get; set; } = 0.65;
    public int ExtractionSiteCount { get; set; } = 3;
    public List<SiteLayerRatio> ExtractionSiteLayerDistribution { get; } =
    [
        new() { LayerId = "inner", Ratio = 0.8 },
        new() { LayerId = "middle", Ratio = 0.2 },
    ];
    public double ExtractionSiteMinDistanceFromPlayerSpawnsCells { get; set; } = 12;
    public double ExtractionSiteMinDistanceBetweenSitesCells { get; set; } = 10;
    public int ExtractionSiteEdgeMarginCells { get; set; } = 6;
    public int ExtractionSiteClearanceRadiusCells { get; set; } = 2;
    public double ExtractionSiteMinClearanceRatio { get; set; } = 0.65;
    public bool TrapsHighDensity { get; set; }
    public int TrapsSpikeMaxCount { get; set; } = -1;
    public int TrapsSpikeMinSpacing { get; set; } = -1;
    public int TrapsExplosiveChainCount { get; set; } = -1;
    public int TrapsExplosiveChainSpacing { get; set; } = -1;
    public int TrapsArrowSlitMaxCount { get; set; } = -1;
    public int TrapsArrowSlitMinSpacing { get; set; } = -1;
    public int TrapsMimicOreMaxCount { get; set; } = -1;
    public int TrapsMimicOreMinSpacing { get; set; } = -1;
    public int TrapsPressurePlateMaxCount { get; set; } = -1;
    public int TrapsPressurePlateMinSpacing { get; set; } = -1;

    public void Normalize()
    {
        Width = Math.Max(Width, 8);
        Height = Math.Max(Height, 8);
        FillPercent = Math.Clamp(FillPercent, 0, 1);
        SmoothIterations = Math.Max(SmoothIterations, 0);
        CorridorCount = Math.Max(CorridorCount, 0);
        CorridorWidth = Math.Max(CorridorWidth, 1);
        CorridorLength = Math.Clamp(CorridorLength, 0, 1.5);
        CorridorWobble = Math.Clamp(CorridorWobble, 0, 1);
        MineralBaseChance = Math.Clamp(MineralBaseChance, 0, 1);
        MineralExposedChance = Math.Clamp(MineralExposedChance, 0, 1);
        MineralMinDistanceBetweenClusterSeedsCells = Math.Max(MineralMinDistanceBetweenClusterSeedsCells, 0);
        PlayerSpawnCount = Math.Max(PlayerSpawnCount, 0);
        PlayerSpawnLayerId = string.IsNullOrWhiteSpace(PlayerSpawnLayerId) ? "outer" : PlayerSpawnLayerId.Trim();
        PlayerSpawnEdgeMarginCells = Math.Max(PlayerSpawnEdgeMarginCells, 0);
        PlayerSpawnMinDistanceBetweenSpawnsCells = Math.Max(PlayerSpawnMinDistanceBetweenSpawnsCells, 0);
        PlayerSpawnClearanceRadiusCells = Math.Max(PlayerSpawnClearanceRadiusCells, 0);
        PlayerSpawnMinClearanceRatio = Math.Clamp(PlayerSpawnMinClearanceRatio, 0, 1);
        ExtractionSiteCount = Math.Max(ExtractionSiteCount, 0);
        ExtractionSiteMinDistanceFromPlayerSpawnsCells = Math.Max(ExtractionSiteMinDistanceFromPlayerSpawnsCells, 0);
        ExtractionSiteMinDistanceBetweenSitesCells = Math.Max(ExtractionSiteMinDistanceBetweenSitesCells, 0);
        ExtractionSiteEdgeMarginCells = Math.Max(ExtractionSiteEdgeMarginCells, 0);
        ExtractionSiteClearanceRadiusCells = Math.Max(ExtractionSiteClearanceRadiusCells, 0);
        ExtractionSiteMinClearanceRatio = Math.Clamp(ExtractionSiteMinClearanceRatio, 0, 1);

        NormalizeLegacyPois();
        NormalizeLayers();
        NormalizeClusters(MineralClusterTypes);
        NormalizeClusters(MineralClusterOverrides);
        NormalizeExtractionDistribution();
    }

    private void NormalizeLegacyPois()
    {
        LargePoiCount = Math.Max(LargePoiCount, 0);
        LargePoiMinDistance = Math.Max(LargePoiMinDistance, 0);
        LargePoiRadius = Math.Max(LargePoiRadius, 0);
        LargePoiIrregularity = Math.Clamp(LargePoiIrregularity, 0, 1);
        LargePoiSpecialBlockCount = Math.Max(LargePoiSpecialBlockCount, 0);
        MediumPoiCount = Math.Max(MediumPoiCount, 0);
        MediumPoiMinDistance = Math.Max(MediumPoiMinDistance, 0);
        MediumPoiRadius = Math.Max(MediumPoiRadius, 0);
        MediumPoiIrregularity = Math.Clamp(MediumPoiIrregularity, 0, 1);
        MediumPoiSpecialBlockCount = Math.Max(MediumPoiSpecialBlockCount, 0);
        SmallPoiCount = Math.Max(SmallPoiCount, 0);
        SmallPoiMinDistance = Math.Max(SmallPoiMinDistance, 0);
        SmallPoiRadius = Math.Max(SmallPoiRadius, 0);
        SmallPoiIrregularity = Math.Clamp(SmallPoiIrregularity, 0, 1);
        SmallPoiSpecialBlockCount = Math.Max(SmallPoiSpecialBlockCount, 0);
    }

    private void NormalizeLayers()
    {
        var maxRadius = Math.Sqrt(Math.Pow(Width * 0.5, 2) + Math.Pow(Height * 0.5, 2));
        var supplied = MapLayers.ToDictionary(layer => layer.Id, StringComparer.Ordinal);
        var defaults = new[]
        {
            CreateDefaultLayer("inner", 0.34, 4, 2, 1.5),
            CreateDefaultLayer("middle", 0.67, 2, 1.25, 1.15),
            CreateDefaultLayer("outer", 1.01, 1, 0.75, 0.85),
        };

        MapLayers.Clear();
        foreach (var fallback in defaults)
        {
            var layer = supplied.GetValueOrDefault(fallback.Id) ?? fallback;
            layer.MaxRadiusCells = Math.Max(
                layer.MaxRadiusCells > 0 ? layer.MaxRadiusCells : layer.MaxRadiusRatio * maxRadius,
                0);
            layer.StoneMaxHitPoints = Math.Max(layer.StoneMaxHitPoints, 1);
            layer.MineralBudgetWeight = Math.Max(layer.MineralBudgetWeight, 0);
            layer.PoiBudgetWeight = Math.Max(layer.PoiBudgetWeight, 0);
            layer.TrapBudgetWeight = Math.Max(layer.TrapBudgetWeight, 0);
            layer.MonsterBudgetWeight = Math.Max(layer.MonsterBudgetWeight, 0);
            layer.RoomContentDangerMultiplier = Math.Max(layer.RoomContentDangerMultiplier, 0);
            layer.BoundaryNoiseAmplitudeCells = Math.Max(layer.BoundaryNoiseAmplitudeCells, 0);
            layer.BoundaryNoiseScaleCells = Math.Max(layer.BoundaryNoiseScaleCells, 1);
            layer.BoundaryNoiseOctaves = Math.Clamp(layer.BoundaryNoiseOctaves, 1, 6);
            layer.BoundaryNoisePersistence = Math.Clamp(layer.BoundaryNoisePersistence, 0, 1);
            MapLayers.Add(layer);
        }

        MapLayers.Sort((a, b) =>
        {
            var radius = a.MaxRadiusCells.CompareTo(b.MaxRadiusCells);
            return radius != 0 ? radius : string.CompareOrdinal(a.Id, b.Id);
        });
    }

    private static MapLayerConfig CreateDefaultLayer(
        string id,
        double ratio,
        int hitPoints,
        double budgetWeight,
        double dangerMultiplier) =>
        new()
        {
            Id = id,
            MaxRadiusRatio = ratio,
            StoneMaxHitPoints = hitPoints,
            MineralBudgetWeight = budgetWeight,
            PoiBudgetWeight = budgetWeight,
            TrapBudgetWeight = budgetWeight,
            MonsterBudgetWeight = budgetWeight,
            RoomContentDangerMultiplier = dangerMultiplier,
        };

    private static void NormalizeClusters(List<MineralClusterConfig> clusters)
    {
        foreach (var cluster in clusters)
        {
            cluster.Weight = Math.Max(cluster.Weight, 0);
            cluster.MinClusterSize = Math.Max(cluster.MinClusterSize, 1);
            cluster.MaxClusterSize = Math.Max(cluster.MaxClusterSize, cluster.MinClusterSize);
            cluster.SpawnProbability = Math.Clamp(cluster.SpawnProbability, 0, 1);
            cluster.SpawnScope = string.IsNullOrWhiteSpace(cluster.SpawnScope) ? "global" : cluster.SpawnScope.Trim();
        }
    }

    private void NormalizeExtractionDistribution()
    {
        ExtractionSiteLayerDistribution.RemoveAll(entry => string.IsNullOrWhiteSpace(entry.LayerId) || entry.Ratio <= 0);
        if (ExtractionSiteLayerDistribution.Count == 0)
        {
            ExtractionSiteLayerDistribution.Add(new SiteLayerRatio { LayerId = "inner", Ratio = 0.8 });
            ExtractionSiteLayerDistribution.Add(new SiteLayerRatio { LayerId = "middle", Ratio = 0.2 });
        }
    }
}
