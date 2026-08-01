using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Wdc.MapGeneration;

public static class MapConfigLoader
{
    public static MapConfig Load(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var fullPath = Path.GetFullPath(path);
        if (!File.Exists(fullPath))
        {
            throw new FileNotFoundException($"地图配置文件不存在: {fullPath}", fullPath);
        }

        try
        {
            var root = JsonNode.Parse(File.ReadAllText(fullPath)) as JsonObject;
            if (root is null)
            {
                throw new InvalidDataException($"地图配置根节点必须是 JSON object: {fullPath}");
            }

            return Load(root);
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException($"地图配置 JSON 无法解析: {fullPath}", exception);
        }
    }

    public static MapConfig Load(JsonObject root)
    {
        ArgumentNullException.ThrowIfNull(root);
        var config = new MapConfig();
        ApplyMap(config, root.Object("map"));
        ApplyTerrain(config, root.Object("terrain"));
        ApplyMinerals(config, root.Object("minerals"));
        ApplyLayers(config, root.Array("map_layers"));
        ApplyMonsters(config, root.Object("monster_generation"));
        ApplyPois(config, root.Object("poi_generation"));
        ApplyTraps(config, root.Object("traps"));
        config.Normalize();
        return config;
    }

    private static void ApplyMap(MapConfig config, JsonObject map)
    {
        config.Width = map.Int("width_cells", config.Width);
        config.Height = map.Int("height_cells", config.Height);
        var seed = map.Object("seed");
        config.Seed = string.Equals(seed.String("mode", "random"), "fixed", StringComparison.Ordinal)
            ? Math.Max(seed.Int("fixed_value", 0), 0)
            : 0;

        var spawn = map.Object("player_spawn");
        config.PlayerSpawnCount = spawn.Int("count", config.PlayerSpawnCount);
        config.PlayerSpawnLayerId = spawn.String("layer_id", config.PlayerSpawnLayerId);
        config.PlayerSpawnEdgeMarginCells = spawn.Int("edge_margin_cells", config.PlayerSpawnEdgeMarginCells);
        config.PlayerSpawnMinDistanceBetweenSpawnsCells = spawn.Double(
            "min_distance_between_spawns_cells",
            config.PlayerSpawnMinDistanceBetweenSpawnsCells);
        config.PlayerSpawnClearanceRadiusCells = spawn.Int(
            "clearance_radius_cells",
            config.PlayerSpawnClearanceRadiusCells);
        config.PlayerSpawnMinClearanceRatio = spawn.Double(
            "min_clearance_ratio",
            config.PlayerSpawnMinClearanceRatio);

        var extraction = map.Object("extraction_sites");
        config.ExtractionSiteCount = extraction.Int("count", config.ExtractionSiteCount);
        config.ExtractionSiteMinDistanceFromPlayerSpawnsCells = extraction.Double(
            "min_distance_from_player_spawns_cells",
            config.ExtractionSiteMinDistanceFromPlayerSpawnsCells);
        config.ExtractionSiteMinDistanceBetweenSitesCells = extraction.Double(
            "min_distance_between_sites_cells",
            config.ExtractionSiteMinDistanceBetweenSitesCells);
        config.ExtractionSiteEdgeMarginCells = extraction.Int(
            "edge_margin_cells",
            config.ExtractionSiteEdgeMarginCells);
        config.ExtractionSiteClearanceRadiusCells = extraction.Int(
            "clearance_radius_cells",
            config.ExtractionSiteClearanceRadiusCells);
        config.ExtractionSiteMinClearanceRatio = extraction.Double(
            "min_clearance_ratio",
            config.ExtractionSiteMinClearanceRatio);
        var distribution = extraction.Array("layer_distribution");
        if (distribution.Count > 0)
        {
            config.ExtractionSiteLayerDistribution.Clear();
            foreach (var value in distribution.OfType<JsonObject>())
            {
                config.ExtractionSiteLayerDistribution.Add(new SiteLayerRatio
                {
                    LayerId = value.String("layer_id", value.String("id")),
                    Ratio = value.Double("ratio"),
                });
            }
        }
    }

    private static void ApplyTerrain(MapConfig config, JsonObject terrain)
    {
        config.FillPercent = terrain.Double("noise_fill_percent", config.FillPercent);
        config.SmoothIterations = terrain.Int("smooth_iterations", config.SmoothIterations);
        var corridors = terrain.Object("global_corridors");
        config.CorridorCount = corridors.Bool("enabled", true)
            ? corridors.Int("count", config.CorridorCount)
            : 0;
        config.CorridorWidth = corridors.Int("width_cells", config.CorridorWidth);
        config.CorridorLength = corridors.Double("length_factor", config.CorridorLength);
        config.CorridorWobble = corridors.Double("wobble_chance", config.CorridorWobble);
    }

    private static void ApplyMinerals(MapConfig config, JsonObject minerals)
    {
        var distribution = minerals.Object("global_distribution");
        config.MineralBaseChance = distribution.Double("base_candidate_chance", config.MineralBaseChance);
        config.MineralExposedChance = distribution.Double(
            "exposed_wall_candidate_chance",
            config.MineralExposedChance);
        config.MineralMinDistanceBetweenClusterSeedsCells = distribution.Int(
            "min_distance_between_cluster_seeds_cells",
            config.MineralMinDistanceBetweenClusterSeedsCells);
        config.MineralAllowClustersInsidePoiRooms = distribution.Bool(
            "allow_clusters_inside_poi_rooms",
            config.MineralAllowClustersInsidePoiRooms);
        config.MineralAllowClustersUnderPoiCorridors = distribution.Bool(
            "allow_clusters_under_poi_corridors",
            config.MineralAllowClustersUnderPoiCorridors);

        foreach (var node in minerals.Array("cluster_types").OfType<JsonObject>())
        {
            var cluster = ParseCluster(node);
            if (!string.IsNullOrWhiteSpace(cluster.Id))
            {
                config.MineralClusterTypes.Add(cluster);
            }
        }

        foreach (var node in minerals.Array("cluster_overrides").OfType<JsonObject>())
        {
            var baseId = node.String("base_cluster_type_id");
            var baseCluster = config.MineralClusterTypes.FirstOrDefault(cluster => cluster.Id == baseId);
            if (baseCluster is null)
            {
                continue;
            }

            var merged = CopyCluster(baseCluster);
            merged.Id = node.String("id");
            if (string.IsNullOrWhiteSpace(merged.Id))
            {
                continue;
            }

            merged.SpawnScope = node.String("spawn_scope", merged.SpawnScope);
            merged.TileTypeId = node.String("tile_type_id", merged.TileTypeId);
            merged.MinClusterSize = node.Int("min_cluster_size", merged.MinClusterSize);
            merged.MaxClusterSize = node.Int("max_cluster_size", merged.MaxClusterSize);
            merged.RequireStone = node.Bool("require_stone", merged.RequireStone);
            merged.SpawnProbability = node.Double("spawn_probability", merged.SpawnProbability);
            config.MineralClusterOverrides.Add(merged);
        }
    }

    private static MineralClusterConfig ParseCluster(JsonObject node) => new()
    {
        Id = node.String("id"),
        Enabled = node.Bool("enabled", true),
        TileTypeId = node.String("tile_type_id"),
        SpawnScope = node.String("spawn_scope", "global"),
        Weight = node.Double("weight"),
        MinClusterSize = node.Int("min_cluster_size", 1),
        MaxClusterSize = node.Int("max_cluster_size", node.Int("min_cluster_size", 1)),
        RequireStone = node.Bool("require_stone", true),
        SpawnProbability = node.Double("spawn_probability"),
    };

    private static MineralClusterConfig CopyCluster(MineralClusterConfig source) => new()
    {
        Id = source.Id,
        Enabled = source.Enabled,
        TileTypeId = source.TileTypeId,
        SpawnScope = source.SpawnScope,
        Weight = source.Weight,
        MinClusterSize = source.MinClusterSize,
        MaxClusterSize = source.MaxClusterSize,
        RequireStone = source.RequireStone,
        SpawnProbability = source.SpawnProbability,
    };

    private static void ApplyLayers(MapConfig config, JsonArray layers)
    {
        foreach (var node in layers.OfType<JsonObject>())
        {
            var id = node.String("id").Trim();
            if (id.Length == 0)
            {
                continue;
            }

            config.MapLayers.Add(new MapLayerConfig
            {
                Id = id,
                MaxRadiusCells = node.Double("max_radius_cells"),
                MaxRadiusRatio = node.Double("max_radius_ratio"),
                StoneMaxHitPoints = node.Int("stone_max_hit_points", 1),
                MineralBudgetWeight = node.Double("mineral_budget_weight", 1),
                PoiBudgetWeight = node.Double("poi_budget_weight", 1),
                TrapBudgetWeight = node.Double("trap_budget_weight", 1),
                MonsterBudgetWeight = node.Double("monster_budget_weight", 1),
                RoomContentDangerMultiplier = node.Double("room_content_danger_multiplier", 1),
                BoundaryNoiseAmplitudeCells = node.Double("boundary_noise_amplitude_cells"),
                BoundaryNoiseScaleCells = node.Double("boundary_noise_scale_cells", 16),
                BoundaryNoiseOctaves = node.Int("boundary_noise_octaves", 1),
                BoundaryNoisePersistence = node.Double("boundary_noise_persistence", 0.5),
                BoundaryNoiseSeedOffset = node.Int("boundary_noise_seed_offset"),
            });
        }
    }

    private static void ApplyMonsters(MapConfig config, JsonObject monsters)
    {
        foreach (var node in monsters.Array("isolated_spawn_templates").OfType<JsonObject>())
        {
            var template = new IsolatedSpawnTemplate
            {
                Id = node.String("id"),
                MonsterId = node.String("monster_id"),
            };
            if (template.Id.Length > 0 && template.MonsterId.Length > 0)
            {
                config.IsolatedSpawnTemplates.Add(template);
            }
        }

        foreach (var node in monsters.Array("nest_templates").OfType<JsonObject>())
        {
            var template = new NestTemplate
            {
                Id = node.String("id"),
                NestUnitId = node.String("nest_unit_id"),
                MonsterId = node.String("monster_id"),
                LootTableId = node.String("loot_table_id"),
                ActivationRadiusM = node.Double("activation_radius_m"),
                SpawnIntervalSec = node.Double("spawn_interval_sec"),
                MaxAliveChildren = node.Int("max_alive_children"),
                MaxHitPoints = node.Int("max_hit_points"),
            };
            if (template.Id.Length > 0 && template.NestUnitId.Length > 0)
            {
                config.NestTemplates.Add(template);
            }
        }
    }

    private static void ApplyPois(MapConfig config, JsonObject poiGeneration)
    {
        foreach (var node in poiGeneration.Array("poi_types").OfType<JsonObject>())
        {
            var template = ParsePoiTemplate(node);
            if (template.Id.Length > 0)
            {
                config.PoiTemplates.Add(template);
            }
        }

        for (var index = 0; index < Math.Min(config.PoiTemplates.Count, 3); index++)
        {
            ApplyLegacyPoiProjection(config, config.PoiTemplates[index], index);
        }
    }

    private static PoiTemplateConfig ParsePoiTemplate(JsonObject node)
    {
        var content = node.Object("content");
        return new PoiTemplateConfig
        {
            Id = node.String("id"),
            Enabled = node.Bool("enabled", true),
            Count = node.Int("count"),
            DedicatedMineralId = node.String("dedicated_mineral_id"),
            MainRoom = ParseRoomSize(node.Object("main_room")),
            SubRooms = ParseSubRooms(node.Object("sub_rooms")),
            Placement = ParsePlacement(node.Object("placement")),
            Connectivity = ParseConnectivity(node.Object("connectivity")),
            Corridor = ParseCorridor(node.Object("corridor")),
            Trace = ParseTrace(node.Object("trace")),
            Torch = ParseTorch(node.Object("torch")),
            MainRoomRoll = ParseRoomRoll(content.Object("main_room_roll")),
            SubRoomRoll = ParseRoomRoll(content.Object("sub_room_roll")),
            CenterOreCluster = ParseCenterOreCluster(content.Object("center_ore_cluster")),
        };
    }

    private static RoomSizeConfig ParseRoomSize(JsonObject node) => new()
    {
        WidthMin = node.Int("width_min", 1),
        WidthMax = node.Int("width_max", node.Int("width_min", 1)),
        HeightMin = node.Int("height_min", 1),
        HeightMax = node.Int("height_max", node.Int("height_min", 1)),
    };

    private static SubRoomConfig ParseSubRooms(JsonObject node) => new()
    {
        CountMin = node.Int("count_min"),
        CountMax = node.Int("count_max"),
        WidthMin = node.Int("width_min", 1),
        WidthMax = node.Int("width_max", node.Int("width_min", 1)),
        HeightMin = node.Int("height_min", 1),
        HeightMax = node.Int("height_max", node.Int("height_min", 1)),
        MinGapFromRoomsCells = node.Int("min_gap_from_rooms_cells", 1),
        PlacementRadiusMinCells = node.Int("placement_radius_min_cells", 1),
        PlacementRadiusMaxCells = node.Int("placement_radius_max_cells", 1),
        PlacementAttemptsPerRoom = node.Int("placement_attempts_per_room", 12),
    };

    private static PoiPlacementConfig ParsePlacement(JsonObject node) => new()
    {
        FootprintPaddingCells = node.Int("footprint_padding_cells"),
        MinDistanceFromOtherPoisCells = node.Double("min_distance_from_other_pois_cells"),
        PoiAttempts = node.Int("poi_attempts", 40),
        RoomAttempts = node.Int("room_attempts", 20),
    };

    private static PoiConnectivityConfig ParseConnectivity(JsonObject node) => new()
    {
        CandidateNeighborsPerRoom = node.Int("candidate_neighbors_per_room", 2),
        ExtraConnectionChance = node.Double("extra_connection_chance"),
        MaxExtraConnections = node.Int("max_extra_connections"),
    };

    private static PoiCorridorConfig ParseCorridor(JsonObject node) => new()
    {
        WidthCells = node.Int("width_cells", 1),
        RetryDoorwayCount = node.Int("retry_doorway_count", 1),
        DoorMarginFromCornerCells = node.Int("door_margin_from_corner_cells", 1),
        BendOrderMode = node.String("bend_order_mode", "random"),
    };

    private static TraceConfig ParseTrace(JsonObject node) => new()
    {
        Enabled = node.Bool("enabled", true),
        RadiusCells = node.Double("radius_cells"),
        DensityRatio = node.Double("density_ratio"),
        Rays = node.Double("rays", 1),
        Twist = node.Double("twist", 1),
    };

    private static TorchConfig ParseTorch(JsonObject node) => new()
    {
        Enabled = node.Bool("enabled"),
        CoverageRadiusCells = node.Int("coverage_radius_cells", 4),
        MaxTorchCount = node.Int("max_torch_count"),
        PreferPerimeter = node.Bool("prefer_perimeter", true),
        WallInsetCells = node.Int("wall_inset_cells", 1),
    };

    private static RoomContentRollConfig ParseRoomRoll(JsonObject node)
    {
        var roll = new RoomContentRollConfig
        {
            NoneWeight = node.Double("none_weight"),
            MinDistanceFromDoorCells = node.Int("min_distance_from_door_cells"),
        };
        ParseWeightedEntries(node.Array("monster_entries"), "spawn_template_id", roll.MonsterEntries);
        ParseWeightedEntries(node.Array("nest_entries"), "nest_template_id", roll.NestEntries);
        foreach (var campNode in node.Array("camp_entries").OfType<JsonObject>())
        {
            var camp = new CampEntryConfig
            {
                Id = campNode.String("id"),
                Weight = campNode.Double("weight"),
                GuardCountMin = campNode.Int("guard_count_min", 1),
                GuardCountMax = campNode.Int("guard_count_max", campNode.Int("guard_count_min", 1)),
                ChestAvoidRadiusCells = campNode.Int("chest_avoid_radius_cells", 1),
                MinDistanceFromDoorCells = campNode.ContainsKey("min_distance_from_door_cells")
                    ? campNode.Int("min_distance_from_door_cells")
                    : null,
                LootContainer = (campNode["loot_container"]?.DeepClone() as JsonObject) ?? [],
                LockedPromptText = campNode.String("locked_prompt_text", "需要击败房间中的所有怪物"),
            };
            ParseWeightedEntries(campNode.Array("guard_entries"), "spawn_template_id", camp.GuardEntries);
            roll.CampEntries.Add(camp);
        }

        return roll;
    }

    private static void ParseWeightedEntries(
        JsonArray values,
        string idKey,
        List<WeightedTemplateEntry> output)
    {
        foreach (var node in values.OfType<JsonObject>())
        {
            output.Add(new WeightedTemplateEntry
            {
                Id = node.String(idKey),
                Weight = Math.Max(node.Double("weight"), 0),
            });
        }
    }

    private static CenterOreClusterConfig ParseCenterOreCluster(JsonObject node) => new()
    {
        Enabled = node.Bool("enabled"),
        ClusterOverrideId = node.String("cluster_override_id"),
        AvoidRadiusCells = node.Int("avoid_radius_cells", 1),
    };

    private static void ApplyLegacyPoiProjection(MapConfig config, PoiTemplateConfig template, int index)
    {
        var derivedRadius = Math.Max(
            0,
            (int)Math.Round(
                (template.MainRoom.WidthMin + template.MainRoom.WidthMax +
                 template.MainRoom.HeightMin + template.MainRoom.HeightMax) / 8.0,
                MidpointRounding.AwayFromZero));
        switch (index)
        {
            case 0:
                config.LargePoiCount = template.Enabled ? Math.Max(template.Count, 0) : 0;
                config.LargePoiMinDistance = Math.Max(template.Placement.MinDistanceFromOtherPoisCells, 0);
                config.LargePoiRadius = derivedRadius;
                config.LargePoiIrregularity = 0;
                config.TraceLargeRadius = template.Trace.RadiusCells;
                config.TraceLargeDensity = template.Trace.DensityRatio;
                config.TraceLargeRays = template.Trace.Rays;
                config.TraceLargeTwist = template.Trace.Twist;
                break;
            case 1:
                config.MediumPoiCount = template.Enabled ? Math.Max(template.Count, 0) : 0;
                config.MediumPoiMinDistance = Math.Max(template.Placement.MinDistanceFromOtherPoisCells, 0);
                config.MediumPoiRadius = derivedRadius;
                config.MediumPoiIrregularity = 0;
                config.TraceMediumRadius = template.Trace.RadiusCells;
                config.TraceMediumDensity = template.Trace.DensityRatio;
                config.TraceMediumRays = template.Trace.Rays;
                config.TraceMediumTwist = template.Trace.Twist;
                break;
            default:
                config.SmallPoiCount = template.Enabled ? Math.Max(template.Count, 0) : 0;
                config.SmallPoiMinDistance = Math.Max(template.Placement.MinDistanceFromOtherPoisCells, 0);
                config.SmallPoiRadius = derivedRadius;
                config.SmallPoiIrregularity = 0;
                config.TraceSmallRadius = template.Trace.RadiusCells;
                config.TraceSmallDensity = template.Trace.DensityRatio;
                config.TraceSmallRays = template.Trace.Rays;
                config.TraceSmallTwist = template.Trace.Twist;
                break;
        }
    }

    private static void ApplyTraps(MapConfig config, JsonObject traps)
    {
        config.TrapsHighDensity = traps.Bool("high_density_mode");
        config.TrapsSpikeMaxCount = traps.Int("spike_max_count", -1);
        config.TrapsSpikeMinSpacing = traps.Int("spike_min_spacing", -1);
        config.TrapsExplosiveChainCount = traps.Int("explosive_chain_count", -1);
        config.TrapsExplosiveChainSpacing = traps.Int("explosive_chain_spacing", -1);
        config.TrapsArrowSlitMaxCount = traps.Int("arrow_slit_max_count", -1);
        config.TrapsArrowSlitMinSpacing = traps.Int("arrow_slit_min_spacing", -1);
        config.TrapsMimicOreMaxCount = traps.Int("mimic_ore_max_count", -1);
        config.TrapsMimicOreMinSpacing = traps.Int("mimic_ore_min_spacing", -1);
        config.TrapsPressurePlateMaxCount = traps.Int("pressure_plate_max_count", -1);
        config.TrapsPressurePlateMinSpacing = traps.Int("pressure_plate_min_spacing", -1);
    }
}

internal static class JsonObjectExtensions
{
    public static JsonObject Object(this JsonObject source, string name) => source[name] as JsonObject ?? [];
    public static JsonArray Array(this JsonObject source, string name) => source[name] as JsonArray ?? [];

    public static string String(this JsonObject source, string name, string fallback = "")
    {
        var node = source[name];
        if (node is null)
        {
            return fallback;
        }

        if (node is JsonValue value && value.TryGetValue<string>(out var text))
        {
            return text;
        }

        return fallback;
    }

    public static bool Bool(this JsonObject source, string name, bool fallback = false)
    {
        var node = source[name];
        if (node is not JsonValue value)
        {
            return fallback;
        }

        if (value.TryGetValue<bool>(out var boolean))
        {
            return boolean;
        }

        if (value.TryGetValue<string>(out var text) && bool.TryParse(text, out boolean))
        {
            return boolean;
        }

        return fallback;
    }

    public static int Int(this JsonObject source, string name, int fallback = 0)
    {
        var node = source[name];
        if (node is not JsonValue value)
        {
            return fallback;
        }

        if (value.TryGetValue<int>(out var integer))
        {
            return integer;
        }

        if (value.TryGetValue<long>(out var longInteger))
        {
            return checked((int)longInteger);
        }

        if (value.TryGetValue<double>(out var number))
        {
            return checked((int)number);
        }

        if (value.TryGetValue<string>(out var text) &&
            double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out number))
        {
            return checked((int)number);
        }

        return fallback;
    }

    public static double Double(this JsonObject source, string name, double fallback = 0)
    {
        var node = source[name];
        if (node is not JsonValue value)
        {
            return fallback;
        }

        if (value.TryGetValue<double>(out var number))
        {
            return number;
        }

        if (value.TryGetValue<long>(out var integer))
        {
            return integer;
        }

        if (value.TryGetValue<string>(out var text) &&
            double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out number))
        {
            return number;
        }

        return fallback;
    }
}
