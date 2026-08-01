using System.Text.Json.Nodes;

namespace Wdc.MapGeneration.Tests;

internal static class TestConfigFactory
{
    public static MapConfig CreateMinimal(int seed)
    {
        return new MapConfig
        {
            Width = 48,
            Height = 48,
            Seed = seed,
            FillPercent = 0.58,
            SmoothIterations = 2,
            CorridorCount = 3,
            LargePoiCount = 0,
            MediumPoiCount = 0,
            SmallPoiCount = 0,
            MineralBaseChance = 0.08,
            MineralExposedChance = 0.15,
            TrapsSpikeMaxCount = 0,
            TrapsExplosiveChainCount = 0,
            TrapsArrowSlitMaxCount = 0,
            TrapsMimicOreMaxCount = 0,
            TrapsPressurePlateMaxCount = 0,
            PlayerSpawnCount = 2,
            ExtractionSiteCount = 2,
        };
    }

    public static MapConfig CreateFeatureRich()
    {
        var config = new MapConfig
        {
            Width = 96,
            Height = 96,
            Seed = 20260801,
            FillPercent = 0.62,
            SmoothIterations = 3,
            CorridorCount = 8,
            CorridorWidth = 3,
            MineralBaseChance = 0.35,
            MineralExposedChance = 0.65,
            MineralMinDistanceBetweenClusterSeedsCells = 1,
            TrapsSpikeMaxCount = 18,
            TrapsSpikeMinSpacing = 1,
            TrapsExplosiveChainCount = 18,
            TrapsExplosiveChainSpacing = 1,
            TrapsArrowSlitMaxCount = 18,
            TrapsArrowSlitMinSpacing = 1,
            TrapsMimicOreMaxCount = 18,
            TrapsMimicOreMinSpacing = 1,
            TrapsPressurePlateMaxCount = 18,
            TrapsPressurePlateMinSpacing = 1,
            PlayerSpawnCount = 4,
            PlayerSpawnLayerId = "outer",
            PlayerSpawnEdgeMarginCells = 2,
            PlayerSpawnMinDistanceBetweenSpawnsCells = 4,
            PlayerSpawnClearanceRadiusCells = 1,
            PlayerSpawnMinClearanceRatio = 0.2,
            ExtractionSiteCount = 3,
            ExtractionSiteEdgeMarginCells = 2,
            ExtractionSiteMinDistanceFromPlayerSpawnsCells = 4,
            ExtractionSiteMinDistanceBetweenSitesCells = 3,
            ExtractionSiteClearanceRadiusCells = 1,
            ExtractionSiteMinClearanceRatio = 0.2,
        };
        config.ExtractionSiteLayerDistribution.Clear();
        config.ExtractionSiteLayerDistribution.Add(new SiteLayerRatio { LayerId = "inner", Ratio = 2 });
        config.ExtractionSiteLayerDistribution.Add(new SiteLayerRatio { LayerId = "middle", Ratio = 1 });
        config.MineralClusterTypes.Add(new MineralClusterConfig
        {
            Id = "ordinary",
            TileTypeId = "mineral_wall",
            SpawnScope = "global",
            Weight = 1,
            MinClusterSize = 2,
            MaxClusterSize = 4,
            RequireStone = true,
            SpawnProbability = 1,
        });
        config.MineralClusterOverrides.Add(new MineralClusterConfig
        {
            Id = "gold_core",
            TileTypeId = "gold_block",
            SpawnScope = "poi",
            Weight = 1,
            MinClusterSize = 3,
            MaxClusterSize = 5,
            RequireStone = false,
            SpawnProbability = 1,
        });
        config.IsolatedSpawnTemplates.Add(new IsolatedSpawnTemplate { Id = "guard", MonsterId = "ghoul" });
        config.NestTemplates.Add(new NestTemplate
        {
            Id = "nest",
            NestUnitId = "ghoul_nest",
            MonsterId = "ghoul",
            LootTableId = "nest_loot",
            MaxHitPoints = 40,
            MaxAliveChildren = 3,
        });

        var template = new PoiTemplateConfig
        {
            Id = "camp_dungeon",
            Count = 1,
            MainRoom = new RoomSizeConfig { WidthMin = 15, WidthMax = 15, HeightMin = 15, HeightMax = 15 },
            SubRooms = new SubRoomConfig
            {
                CountMin = 2,
                CountMax = 2,
                WidthMin = 7,
                WidthMax = 7,
                HeightMin = 7,
                HeightMax = 7,
                MinGapFromRoomsCells = 2,
                PlacementRadiusMinCells = 8,
                PlacementRadiusMaxCells = 14,
                PlacementAttemptsPerRoom = 80,
            },
            Placement = new PoiPlacementConfig
            {
                FootprintPaddingCells = 2,
                MinDistanceFromOtherPoisCells = 4,
                PoiAttempts = 300,
                RoomAttempts = 80,
            },
            Connectivity = new PoiConnectivityConfig
            {
                CandidateNeighborsPerRoom = 3,
                ExtraConnectionChance = 1,
                MaxExtraConnections = 1,
            },
            Corridor = new PoiCorridorConfig
            {
                WidthCells = 2,
                RetryDoorwayCount = 4,
                DoorMarginFromCornerCells = 1,
                BendOrderMode = "horizontal_first",
            },
            Torch = new TorchConfig { Enabled = true, MaxTorchCount = 8, WallInsetCells = 1 },
            CenterOreCluster = new CenterOreClusterConfig
            {
                Enabled = false,
                ClusterOverrideId = "gold_core",
                AvoidRadiusCells = 1,
            },
        };
        template.MainRoomRoll.CampEntries.Add(new CampEntryConfig
        {
            Id = "locked_camp",
            Weight = 1,
            GuardCountMin = 2,
            GuardCountMax = 2,
            ChestAvoidRadiusCells = 2,
            LootContainer = new JsonObject { ["grid_width"] = 5, ["grid_height"] = 3 },
            LockedPromptText = "清除守卫",
        });
        template.MainRoomRoll.CampEntries[0].GuardEntries.Add(new WeightedTemplateEntry { Id = "guard", Weight = 1 });
        template.SubRoomRoll.MonsterEntries.Add(new WeightedTemplateEntry { Id = "guard", Weight = 1 });
        template.SubRoomRoll.NestEntries.Add(new WeightedTemplateEntry { Id = "nest", Weight = 1 });
        config.PoiTemplates.Add(template);
        return config;
    }
}
