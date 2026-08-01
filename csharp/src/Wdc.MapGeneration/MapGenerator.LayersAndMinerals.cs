namespace Wdc.MapGeneration;

public sealed partial class MapGenerator
{
    private void GenerateMinerals(MapData map, MapConfig config, Random random)
    {
        ClearAllMineralCells(map);
        if (config.MineralClusterTypes.Count > 0)
        {
            GenerateMineralClusters(map, config, random);
            return;
        }

        for (var y = 0; y < map.Height; y++)
        {
            for (var x = 0; x < map.Width; x++)
            {
                var cell = map.GetCell(x, y);
                if (cell.CellType != CellType.Wall)
                {
                    cell.HasMineral = false;
                    continue;
                }

                var chance = IsExposedWall(map, x, y) ? config.MineralExposedChance : config.MineralBaseChance;
                chance *= ResolveLayerWeight(config, map, new Int2(x, y), layer => layer.MineralBudgetWeight);
                cell.HasMineral = random.NextDouble() < Math.Clamp(chance, 0, 1);
            }
        }
    }

    private static void ClearAllMineralCells(MapData map)
    {
        for (var y = 0; y < map.Height; y++)
        {
            for (var x = 0; x < map.Width; x++)
            {
                var cell = map.GetCell(x, y);
                cell.HasMineral = false;
                if (cell.SpecialBlockType != SpecialBlockType.None)
                {
                    cell.SpecialBlockType = SpecialBlockType.None;
                }
            }
        }
    }

    private void GenerateMineralClusters(MapData map, MapConfig config, Random random)
    {
        var placedSeeds = new List<Int2>();
        for (var y = 0; y < map.Height; y++)
        {
            for (var x = 0; x < map.Width; x++)
            {
                var position = new Int2(x, y);
                var cell = map.GetCell(position);
                if (!IsValidGlobalClusterSeedCell(cell, config) ||
                    IsClusterSeedTooClose(position, placedSeeds, config.MineralMinDistanceBetweenClusterSeedsCells))
                {
                    continue;
                }

                var chance = IsExposedWall(map, x, y) ? config.MineralExposedChance : config.MineralBaseChance;
                chance *= ResolveLayerWeight(config, map, position, layer => layer.MineralBudgetWeight);
                if (random.NextDouble() > Math.Clamp(chance, 0, 1))
                {
                    continue;
                }

                var template = PickWeighted(
                    config.MineralClusterTypes.Where(cluster => cluster.Enabled && cluster.SpawnScope.StartsWith("global", StringComparison.Ordinal)).ToList(),
                    cluster => cluster.Weight,
                    random);
                if (template is not null && GrowClusterFromSeed(map, position, config, template, random) > 0)
                {
                    placedSeeds.Add(position);
                }
            }
        }
    }

    private static int GrowClusterFromSeed(
        MapData map,
        Int2 seed,
        MapConfig config,
        MineralClusterConfig template,
        Random random)
    {
        var targetSize = NextInclusive(random, Math.Max(template.MinClusterSize, 1), Math.Max(template.MaxClusterSize, template.MinClusterSize));
        var generated = new List<Int2>();
        if (!PlaceClusterCell(map, seed, template))
        {
            return 0;
        }

        generated.Add(seed);
        while (generated.Count < targetSize)
        {
            var candidates = new HashSet<Int2>();
            foreach (var generatedCell in generated)
            {
                foreach (var direction in CardinalDirections)
                {
                    var candidate = generatedCell + direction;
                    if (IsValidClusterCandidate(map, candidate, config, template))
                    {
                        candidates.Add(candidate);
                    }
                }
            }

            if (candidates.Count == 0)
            {
                break;
            }

            var orderedCandidates = candidates.OrderBy(cell => cell.Y).ThenBy(cell => cell.X).ToList();
            Shuffle(orderedCandidates, random);
            var generatedThisRound = false;
            foreach (var candidate in orderedCandidates)
            {
                if (generated.Count >= targetSize)
                {
                    break;
                }

                if (random.NextDouble() <= Math.Clamp(template.SpawnProbability, 0, 1) &&
                    PlaceClusterCell(map, candidate, template))
                {
                    generated.Add(candidate);
                    generatedThisRound = true;
                }
            }

            if (!generatedThisRound)
            {
                break;
            }
        }

        return generated.Count;
    }

    private static bool IsValidGlobalClusterSeedCell(CellData cell, MapConfig config) =>
        cell.CellType == CellType.Wall &&
        !cell.HasMineral &&
        cell.SpecialBlockType == SpecialBlockType.None &&
        (config.MineralAllowClustersInsidePoiRooms || cell.PoiType == PoiType.None);

    private static bool IsClusterSeedTooClose(Int2 candidate, IEnumerable<Int2> placed, int minimumDistance) =>
        minimumDistance > 0 && placed.Any(existing => existing.DistanceTo(candidate) < minimumDistance);

    private static bool IsValidClusterCandidate(
        MapData map,
        Int2 candidate,
        MapConfig config,
        MineralClusterConfig template)
    {
        if (!map.IsInBounds(candidate))
        {
            return false;
        }

        var cell = map.GetCell(candidate);
        if (cell.HasMineral || cell.SpecialBlockType != SpecialBlockType.None ||
            (!config.MineralAllowClustersInsidePoiRooms && cell.PoiType != PoiType.None))
        {
            return false;
        }

        return template.RequireStone ? cell.CellType == CellType.Wall : cell.CellType is CellType.Wall or CellType.Floor;
    }

    private static bool PlaceClusterCell(MapData map, Int2 target, MineralClusterConfig template)
    {
        if (!map.IsInBounds(target))
        {
            return false;
        }

        var cell = map.GetCell(target);
        if (cell.HasMineral || cell.SpecialBlockType != SpecialBlockType.None)
        {
            return false;
        }

        cell.CellType = CellType.Wall;
        cell.HasMineral = false;
        cell.SpecialBlockType = template.TileTypeId switch
        {
            "rare_mineral_wall" => SpecialBlockType.RareMineral,
            "turquoise_ore" => SpecialBlockType.Turquoise,
            "amethyst_ore" => SpecialBlockType.Amethyst,
            "gold_block" => SpecialBlockType.Gold,
            _ => SpecialBlockType.None,
        };
        if (cell.SpecialBlockType == SpecialBlockType.None)
        {
            cell.HasMineral = true;
        }

        return true;
    }

    private static bool IsExposedWall(MapData map, int x, int y) => CardinalDirections.Any(direction =>
    {
        var neighbor = new Int2(x, y) + direction;
        return map.IsInBounds(neighbor) && map.GetCell(neighbor).CellType == CellType.Floor;
    });

    private MapLayerConfig ResolveLayer(MapConfig config, MapData? map, Int2 cell)
    {
        var width = map?.Width ?? config.Width;
        var height = map?.Height ?? config.Height;
        var centerX = (width - 1) * 0.5;
        var centerY = (height - 1) * 0.5;
        var distance = Math.Sqrt(Math.Pow(cell.X - centerX, 2) + Math.Pow(cell.Y - centerY, 2));
        foreach (var layer in config.MapLayers)
        {
            if (distance <= ResolveLayerBoundaryRadius(config, layer, cell))
            {
                return layer;
            }
        }

        return config.MapLayers[^1];
    }

    private double ResolveLayerBoundaryRadius(MapConfig config, MapLayerConfig layer, Int2 cell)
    {
        if (layer.BoundaryNoiseAmplitudeCells <= 0)
        {
            return layer.MaxRadiusCells;
        }

        var seed = LastResolvedSeed + layer.BoundaryNoiseSeedOffset;
        return layer.MaxRadiusCells + SampleLayerBoundaryNoise(
            cell,
            layer.BoundaryNoiseScaleCells,
            layer.BoundaryNoiseOctaves,
            layer.BoundaryNoisePersistence,
            seed) * layer.BoundaryNoiseAmplitudeCells;
    }

    private static double SampleLayerBoundaryNoise(Int2 cell, double scale, int octaves, double persistence, int seed)
    {
        var total = 0.0;
        var amplitude = 1.0;
        var amplitudeSum = 0.0;
        var frequency = 1.0;
        for (var octave = 0; octave < octaves; octave++)
        {
            total += SampleValueNoise2D(cell.X * frequency / scale, cell.Y * frequency / scale, seed + octave * 1013) * amplitude;
            amplitudeSum += amplitude;
            frequency *= 2;
            amplitude *= persistence;
        }

        return amplitudeSum <= 0 ? 0 : total / amplitudeSum;
    }

    private static double SampleValueNoise2D(double x, double y, int seed)
    {
        var x0 = (int)Math.Floor(x);
        var y0 = (int)Math.Floor(y);
        var tx = SmoothNoiseStep(x - x0);
        var ty = SmoothNoiseStep(y - y0);
        var top = Lerp(HashNoise2D(x0, y0, seed), HashNoise2D(x0 + 1, y0, seed), tx);
        var bottom = Lerp(HashNoise2D(x0, y0 + 1, seed), HashNoise2D(x0 + 1, y0 + 1, seed), tx);
        return Lerp(top, bottom, ty);
    }

    private static double SmoothNoiseStep(double value)
    {
        var clamped = Math.Clamp(value, 0, 1);
        return clamped * clamped * (3 - 2 * clamped);
    }

    private static double HashNoise2D(int x, int y, int seed)
    {
        var seedValue = Math.Abs((long)seed) % 104729;
        var raw = Math.Sin(x * 127.1 + y * 311.7 + seedValue * 74.7) * 43758.5453123;
        return (raw - Math.Floor(raw)) * 2 - 1;
    }

    private static double Lerp(double start, double end, double amount) => start + (end - start) * amount;

    private double ResolveLayerWeight(
        MapConfig config,
        MapData map,
        Int2 cell,
        Func<MapLayerConfig, double> selector) => Math.Max(selector(ResolveLayer(config, map, cell)), 0);

    private static Dictionary<string, int> SplitLayerBudget(
        int totalCount,
        MapConfig config,
        Func<MapLayerConfig, double> selector)
    {
        var result = new Dictionary<string, int>(StringComparer.Ordinal);
        if (totalCount <= 0 || config.MapLayers.Count == 0)
        {
            return result;
        }

        var entries = config.MapLayers.Select(layer => new LayerBudgetEntry(layer.Id, Math.Max(selector(layer), 0))).ToList();
        var totalWeight = entries.Sum(entry => entry.Weight);
        if (totalWeight <= 0)
        {
            totalWeight = entries.Count;
            entries = entries.Select(entry => entry with { Weight = 1 }).ToList();
        }

        var assigned = 0;
        for (var index = 0; index < entries.Count; index++)
        {
            var raw = totalCount * entries[index].Weight / totalWeight;
            var count = (int)Math.Floor(raw);
            entries[index] = entries[index] with { Count = count, Remainder = raw - count };
            assigned += count;
        }

        entries.Sort((a, b) =>
        {
            var remainder = b.Remainder.CompareTo(a.Remainder);
            return remainder != 0 ? remainder : string.CompareOrdinal(a.Id, b.Id);
        });
        var cursor = 0;
        while (assigned < totalCount)
        {
            var index = cursor % entries.Count;
            entries[index] = entries[index] with { Count = entries[index].Count + 1 };
            assigned++;
            cursor++;
        }

        foreach (var entry in entries)
        {
            result[entry.Id] = entry.Count;
        }

        return result;
    }

    private void ApplyLayerDurabilityOverrides(MapData map, MapConfig config)
    {
        for (var y = 0; y < map.Height; y++)
        {
            for (var x = 0; x < map.Width; x++)
            {
                var cell = map.GetCell(x, y);
                var tileType = TileRules.EncodeServerTile(cell);
                cell.DurabilityOverrideMaxHitPoints = TileRules.UsesLayerDurability(tileType)
                    ? Math.Max(ResolveLayer(config, map, new Int2(x, y)).StoneMaxHitPoints, 1)
                    : 0;
                TileRules.RefreshCellRuntimeState(cell);
            }
        }
    }

    private static void RecalculateStats(MapData map)
    {
        map.TotalFloor = 0;
        map.LargePois = map.PoiCenters.Count(center => center.PoiType == PoiType.LargeRuin);
        map.MediumPois = map.PoiCenters.Count(center => center.PoiType == PoiType.MediumBiome);
        map.SmallPois = map.PoiCenters.Count(center => center.PoiType == PoiType.SmallOre);
        for (var y = 0; y < map.Height; y++)
        {
            for (var x = 0; x < map.Width; x++)
            {
                if (map.GetCell(x, y).CellType == CellType.Floor)
                {
                    map.TotalFloor++;
                }
            }
        }
    }

    private static T? PickWeighted<T>(IReadOnlyList<T> values, Func<T, double> weightSelector, Random random)
        where T : class
    {
        var total = values.Sum(value => Math.Max(weightSelector(value), 0));
        if (total <= 0)
        {
            return null;
        }

        var roll = random.NextDouble() * total;
        var cumulative = 0.0;
        foreach (var value in values)
        {
            cumulative += Math.Max(weightSelector(value), 0);
            if (roll <= cumulative)
            {
                return value;
            }
        }

        return values[^1];
    }

    private sealed record LayerBudgetEntry(string Id, double Weight, int Count = 0, double Remainder = 0);
}
