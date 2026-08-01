using System.Text.Json;

namespace Wdc.MapGeneration.Tests;

public sealed class MapGeneratorTests
{
    [Fact]
    public void FixedSeedReproducesTileMatrixAndMetadata()
    {
        var config = MapConfigLoader.Load(FixturePaths.Config("smoke_generated_map.json"));

        var first = new MapGenerator().Generate(config);
        var second = new MapGenerator().Generate(config);

        Assert.Equal(first.ResolvedSeed, second.ResolvedSeed);
        Assert.Equal(Fingerprint(first), Fingerprint(second));
        Assert.NotEmpty(first.PoiInstances);
        Assert.NotEmpty(first.MonsterSites);
        Assert.Contains(AllCells(first), cell => cell.SpecialBlockType == SpecialBlockType.Gold);
    }

    [Fact]
    public void RandomSeedCanReplayGeneratedResult()
    {
        var randomConfig = TestConfigFactory.CreateMinimal(0);
        var first = new MapGenerator().Generate(randomConfig);
        var replayConfig = TestConfigFactory.CreateMinimal(first.ResolvedSeed);

        var replay = new MapGenerator().Generate(replayConfig);

        Assert.NotEqual(0, first.ResolvedSeed);
        Assert.Equal(Fingerprint(first), Fingerprint(replay));
    }

    [Fact]
    public void FeatureConfigGeneratesPoisCampsMineralsTrapsAndSites()
    {
        var map = new MapGenerator().Generate(TestConfigFactory.CreateFeatureRich());

        var poi = Assert.Single(map.PoiInstances);
        Assert.NotEmpty(poi.Corridors);
        Assert.NotEmpty(poi.TorchSites);
        var camp = Assert.Single(map.CampEncounters);
        Assert.Equal(2, camp.GuardSites.Count);
        Assert.Equal("清除守卫", camp.LockedPromptText);
        Assert.Equal(5, camp.LootContainer["grid_width"]!.GetValue<int>());
        Assert.Contains(map.MonsterSites, site => site.SiteKind is "isolated" or "nest");
        Assert.Contains(AllCells(map), cell => cell.HasMineral);

        var trapKinds = map.TrapSites.Select(site => site.TrapKind).ToHashSet(StringComparer.Ordinal);
        Assert.Contains("spike", trapKinds);
        Assert.Contains("explosive_ore_chain", trapKinds);
        Assert.Contains("arrow_slit", trapKinds);
        Assert.Contains("mimic_ore", trapKinds);
        Assert.Contains("pressure_plate", trapKinds);

        Assert.Equal(4, map.PlayerSpawnPoints.Count);
        Assert.Equal(3, map.ExtractionSites.Count);
        Assert.All(map.PlayerSpawnPoints, site => Assert.Equal("outer", site.RequestedLayerId));
        Assert.Equal(2, map.ExtractionSites.Count(site => site.RequestedLayerId == "inner"));
        Assert.Single(map.ExtractionSites, site => site.RequestedLayerId == "middle");
        Assert.All(map.PlayerSpawnPoints.Concat(map.ExtractionSites), site => Assert.True(map.IsInBounds(site.Cell)));
    }

    [Fact]
    public void LayerDurabilityUsesConfiguredRadialLayers()
    {
        var config = new MapConfig
        {
            Width = 64,
            Height = 64,
            Seed = 44,
            FillPercent = 1,
            SmoothIterations = 0,
            CorridorCount = 0,
            LargePoiCount = 0,
            MediumPoiCount = 0,
            SmallPoiCount = 0,
            MineralBaseChance = 0,
            MineralExposedChance = 0,
            PlayerSpawnCount = 0,
            ExtractionSiteCount = 0,
            TrapsSpikeMaxCount = 0,
            TrapsExplosiveChainCount = 0,
            TrapsArrowSlitMaxCount = 0,
            TrapsMimicOreMaxCount = 0,
            TrapsPressurePlateMaxCount = 0,
        };
        config.MapLayers.Add(new MapLayerConfig { Id = "inner", MaxRadiusRatio = 0.3, StoneMaxHitPoints = 9 });
        config.MapLayers.Add(new MapLayerConfig { Id = "middle", MaxRadiusRatio = 0.6, StoneMaxHitPoints = 5 });
        config.MapLayers.Add(new MapLayerConfig { Id = "outer", MaxRadiusRatio = 1.01, StoneMaxHitPoints = 2 });

        var map = new MapGenerator().Generate(config);

        Assert.Equal(9, map.GetCell(31, 31).MaxHitPoints);
        Assert.Equal(5, map.GetCell(51, 31).MaxHitPoints);
        Assert.Equal(2, map.GetCell(0, 0).MaxHitPoints);
    }

    private static string Fingerprint(MapData map) => JsonSerializer.Serialize(new
    {
        Tiles = map.ToTileMatrix(),
        map.PoiCenters,
        map.PoiInstances,
        map.PlayerSpawnPoints,
        map.ExtractionSites,
        map.MonsterSites,
        map.CampEncounters,
        map.TrapSites,
        map.TotalFloor,
        map.LargePois,
        map.MediumPois,
        map.SmallPois,
    });

    private static IEnumerable<CellData> AllCells(MapData map)
    {
        for (var y = 0; y < map.Height; y++)
        {
            for (var x = 0; x < map.Width; x++)
            {
                yield return map.GetCell(x, y);
            }
        }
    }
}
