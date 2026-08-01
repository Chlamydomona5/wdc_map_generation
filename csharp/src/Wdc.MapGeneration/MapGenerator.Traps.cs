namespace Wdc.MapGeneration;

public sealed partial class MapGenerator
{
    private const int SpikePatchCount = 4;
    private const int SpikePatchMinSize = 2;
    private const int SpikePatchMaxSize = 4;
    private const int SpikePatchSpacing = 4;
    private const int ExplosiveChainCount = 3;
    private const int ExplosiveChainLength = 3;
    private const int ExplosiveChainSpacing = 8;
    private const int ArrowSlitMaxCount = 6;
    private const int ArrowSlitMinSpacing = 3;
    private const int ArrowSlitRequiredForwardClear = 3;
    private const int MimicOreMaxCount = 5;
    private const int MimicOreMinSpacing = 4;
    private const int PressurePlateMaxCount = 4;
    private const int PressurePlateMinSpacing = 4;

    private void GenerateEnvironmentalTraps(MapData map, MapConfig config, Random random)
    {
        var highDensity = config.TrapsHighDensity;
        var spikeCount = ResolveConfiguredCount(config.TrapsSpikeMaxCount, highDensity ? SpikePatchCount * 4 : SpikePatchCount);
        var explosiveCount = ResolveConfiguredCount(config.TrapsExplosiveChainCount, highDensity ? ExplosiveChainCount * 4 : ExplosiveChainCount);
        var arrowCount = ResolveConfiguredCount(config.TrapsArrowSlitMaxCount, highDensity ? ArrowSlitMaxCount * 3 : ArrowSlitMaxCount);
        var mimicCount = ResolveConfiguredCount(config.TrapsMimicOreMaxCount, highDensity ? MimicOreMaxCount * 3 : MimicOreMaxCount);
        var plateCount = ResolveConfiguredCount(config.TrapsPressurePlateMaxCount, highDensity ? PressurePlateMaxCount * 4 : PressurePlateMaxCount);
        var spikeBudget = SplitLayerBudget(spikeCount, config, layer => layer.TrapBudgetWeight);
        var explosiveBudget = SplitLayerBudget(explosiveCount, config, layer => layer.TrapBudgetWeight);
        var arrowBudget = SplitLayerBudget(arrowCount, config, layer => layer.TrapBudgetWeight);
        var mimicBudget = SplitLayerBudget(mimicCount, config, layer => layer.TrapBudgetWeight);
        var plateBudget = SplitLayerBudget(plateCount, config, layer => layer.TrapBudgetWeight);
        foreach (var layer in config.MapLayers)
        {
            PlaceSpikePatches(
                map,
                config,
                random,
                spikeBudget.GetValueOrDefault(layer.Id),
                ResolveConfiguredSpacing(config.TrapsSpikeMinSpacing, highDensity ? Math.Max(2, SpikePatchSpacing - 2) : SpikePatchSpacing),
                layer.Id);
            PlaceExplosiveOreChains(
                map,
                config,
                random,
                explosiveBudget.GetValueOrDefault(layer.Id),
                ResolveConfiguredSpacing(config.TrapsExplosiveChainSpacing, highDensity ? Math.Max(2, ExplosiveChainSpacing - 4) : ExplosiveChainSpacing),
                layer.Id);
            PlaceArrowSlits(
                map,
                config,
                random,
                arrowBudget.GetValueOrDefault(layer.Id),
                ResolveConfiguredSpacing(config.TrapsArrowSlitMinSpacing, highDensity ? Math.Max(1, ArrowSlitMinSpacing - 1) : ArrowSlitMinSpacing),
                layer.Id);
            PlaceMimicOres(
                map,
                config,
                random,
                mimicBudget.GetValueOrDefault(layer.Id),
                ResolveConfiguredSpacing(config.TrapsMimicOreMinSpacing, highDensity ? Math.Max(2, MimicOreMinSpacing - 2) : MimicOreMinSpacing),
                layer.Id);
            PlacePressurePlates(
                map,
                config,
                random,
                plateBudget.GetValueOrDefault(layer.Id),
                ResolveConfiguredSpacing(config.TrapsPressurePlateMinSpacing, highDensity ? Math.Max(2, PressurePlateMinSpacing - 2) : PressurePlateMinSpacing),
                layer.Id);
        }
    }

    private static int ResolveConfiguredCount(int configured, int fallback) => configured >= 0 ? configured : fallback;
    private static int ResolveConfiguredSpacing(int configured, int fallback) => configured >= 0 ? configured : fallback;

    private void PlaceSpikePatches(
        MapData map,
        MapConfig config,
        Random random,
        int maximumCount,
        int spacing,
        string layerId)
    {
        if (maximumCount <= 0)
        {
            return;
        }

        var candidates = CollectPoiInteriorFloorCells(map)
            .Where(cell => ResolveLayer(config, map, cell).Id == layerId)
            .OrderBy(cell => cell.Y).ThenBy(cell => cell.X).ToList();
        Shuffle(candidates, random);
        var allowed = candidates.ToHashSet();
        var placed = new List<Int2>();
        var patches = 0;
        foreach (var seed in candidates)
        {
            if (patches >= maximumCount)
            {
                break;
            }

            if (IsTooCloseManhattan(seed, placed, spacing))
            {
                continue;
            }

            var patch = GrowSpikePatch(map, seed, NextInclusive(random, SpikePatchMinSize, SpikePatchMaxSize), random, allowed);
            if (patch.Count < SpikePatchMinSize)
            {
                continue;
            }

            foreach (var position in patch)
            {
                map.GetCell(position).SpecialBlockType = SpecialBlockType.Spike;
                placed.Add(position);
                map.TrapSites.Add(new TrapSite { TrapKind = "spike", Cell = position, LayerId = layerId });
            }

            patches++;
        }
    }

    private static List<Int2> CollectPoiInteriorFloorCells(MapData map)
    {
        var cells = new HashSet<Int2>();
        foreach (var instance in map.PoiInstances)
        {
            foreach (var room in instance.SubRooms.Prepend(instance.MainRoom))
            {
                for (var y = room.Top; y < room.BottomExclusive; y++)
                {
                    for (var x = room.Left; x < room.RightExclusive; x++)
                    {
                        var position = new Int2(x, y);
                        var cell = map.GetCell(position);
                        if (cell.CellType == CellType.Floor && cell.SpecialBlockType == SpecialBlockType.None)
                        {
                            cells.Add(position);
                        }
                    }
                }
            }

            foreach (var position in instance.Corridors.SelectMany(corridor => corridor.Cells))
            {
                if (map.IsInBounds(position))
                {
                    var cell = map.GetCell(position);
                    if (cell.CellType == CellType.Floor && cell.SpecialBlockType == SpecialBlockType.None)
                    {
                        cells.Add(position);
                    }
                }
            }
        }

        return cells.ToList();
    }

    private static List<Int2> GrowSpikePatch(
        MapData map,
        Int2 seed,
        int targetSize,
        Random random,
        HashSet<Int2> allowed)
    {
        var patch = new List<Int2> { seed };
        var visited = new HashSet<Int2> { seed };
        var frontier = new List<Int2> { seed };
        while (patch.Count < targetSize && frontier.Count > 0)
        {
            var pivotIndex = NextInclusive(random, 0, frontier.Count - 1);
            var pivot = frontier[pivotIndex];
            frontier.RemoveAt(pivotIndex);
            var directions = CardinalDirections.ToList();
            Shuffle(directions, random);
            foreach (var direction in directions)
            {
                if (patch.Count >= targetSize)
                {
                    break;
                }

                var candidate = pivot + direction;
                if (!visited.Add(candidate) || !allowed.Contains(candidate) || !map.IsInBounds(candidate))
                {
                    continue;
                }

                var cell = map.GetCell(candidate);
                if (cell.CellType != CellType.Floor || cell.SpecialBlockType != SpecialBlockType.None)
                {
                    continue;
                }

                patch.Add(candidate);
                frontier.Add(candidate);
            }
        }

        return patch;
    }

    private void PlaceExplosiveOreChains(
        MapData map,
        MapConfig config,
        Random random,
        int maximumCount,
        int spacing,
        string layerId)
    {
        var candidates = CollectCells(map, cell => cell.CellType == CellType.Wall && cell.SpecialBlockType == SpecialBlockType.None)
            .Where(position => ResolveLayer(config, map, position).Id == layerId).ToList();
        Shuffle(candidates, random);
        var placed = new List<Int2>();
        var count = 0;
        foreach (var seed in candidates)
        {
            if (count >= maximumCount)
            {
                break;
            }

            if (IsTooCloseManhattan(seed, placed, spacing))
            {
                continue;
            }

            var chain = TryGrowExplosiveChain(map, seed);
            if (chain.Count < ExplosiveChainLength)
            {
                continue;
            }

            var site = new TrapSite { TrapKind = "explosive_ore_chain", LayerId = layerId };
            foreach (var position in chain)
            {
                var cell = map.GetCell(position);
                cell.SpecialBlockType = SpecialBlockType.ExplosiveOre;
                cell.HasMineral = false;
                placed.Add(position);
                site.Nodes.Add(position);
            }

            map.TrapSites.Add(site);
            count++;
        }
    }

    private static List<Int2> TryGrowExplosiveChain(MapData map, Int2 seed)
    {
        var chain = new List<Int2>();
        for (var step = 0; step < ExplosiveChainLength; step++)
        {
            var position = seed + Int2.Right * step;
            if (!map.IsInBounds(position))
            {
                return [];
            }

            var cell = map.GetCell(position);
            if (cell.CellType != CellType.Wall || cell.SpecialBlockType != SpecialBlockType.None)
            {
                return [];
            }

            chain.Add(position);
        }

        return chain;
    }

    private void PlacePressurePlates(
        MapData map,
        MapConfig config,
        Random random,
        int maximumCount,
        int spacing,
        string layerId)
    {
        var candidates = CollectCells(map, cell => cell.CellType == CellType.Floor && cell.SpecialBlockType == SpecialBlockType.None)
            .Where(position => ResolveLayer(config, map, position).Id == layerId).ToList();
        Shuffle(candidates, random);
        var placed = new List<Int2>();
        foreach (var position in candidates)
        {
            if (placed.Count >= maximumCount)
            {
                break;
            }

            if (IsTooCloseManhattan(position, placed, spacing))
            {
                continue;
            }

            map.GetCell(position).SpecialBlockType = SpecialBlockType.PressurePlate;
            placed.Add(position);
            map.TrapSites.Add(new TrapSite { TrapKind = "pressure_plate", Cell = position, LayerId = layerId });
        }
    }

    private void PlaceMimicOres(
        MapData map,
        MapConfig config,
        Random random,
        int maximumCount,
        int spacing,
        string layerId)
    {
        var candidates = CollectCells(map, cell =>
                cell.CellType == CellType.Wall && cell.HasMineral && cell.SpecialBlockType == SpecialBlockType.None)
            .Where(position => ResolveLayer(config, map, position).Id == layerId).ToList();
        Shuffle(candidates, random);
        var placed = new List<Int2>();
        foreach (var position in candidates)
        {
            if (placed.Count >= maximumCount)
            {
                break;
            }

            if (IsTooCloseManhattan(position, placed, spacing))
            {
                continue;
            }

            var variant = placed.Count % 2 == 0 ? "explosive" : "mimic_monster";
            var site = new TrapSite { TrapKind = "mimic_ore", Cell = position, LayerId = layerId };
            site.Metadata["variant"] = variant;
            if (variant == "mimic_monster")
            {
                site.Metadata["monster_id"] = "ghoul";
            }

            placed.Add(position);
            map.TrapSites.Add(site);
        }
    }

    private void PlaceArrowSlits(
        MapData map,
        MapConfig config,
        Random random,
        int maximumCount,
        int spacing,
        string layerId)
    {
        var candidates = CollectCells(map, cell => cell.SpecialBlockType == SpecialBlockType.PoiWall)
            .Where(position => ResolveLayer(config, map, position).Id == layerId).ToList();
        Shuffle(candidates, random);
        var placed = new List<Int2>();
        foreach (var position in candidates)
        {
            if (placed.Count >= maximumCount)
            {
                break;
            }

            if (IsTooCloseManhattan(position, placed, spacing))
            {
                continue;
            }

            var facing = ResolveArrowSlitFacing(map, position);
            if (facing == Int2.Zero)
            {
                continue;
            }

            map.GetCell(position).SpecialBlockType = SpecialBlockType.ArrowSlit;
            placed.Add(position);
            var site = new TrapSite { TrapKind = "arrow_slit", Cell = position, LayerId = layerId };
            site.Metadata["facing_x"] = facing.X.ToString(System.Globalization.CultureInfo.InvariantCulture);
            site.Metadata["facing_y"] = facing.Y.ToString(System.Globalization.CultureInfo.InvariantCulture);
            map.TrapSites.Add(site);
        }
    }

    private static Int2 ResolveArrowSlitFacing(MapData map, Int2 position)
    {
        var emptyDirections = CardinalDirections.Where(direction =>
        {
            var neighbor = position + direction;
            return map.IsInBounds(neighbor) && map.GetCell(neighbor).CellType == CellType.Floor &&
                   map.GetCell(neighbor).SpecialBlockType == SpecialBlockType.None;
        }).ToList();
        if (emptyDirections.Count != 1)
        {
            return Int2.Zero;
        }

        var facing = emptyDirections[0];
        for (var step = 1; step <= ArrowSlitRequiredForwardClear; step++)
        {
            var probe = position + facing * step;
            if (!map.IsInBounds(probe) || map.GetCell(probe).CellType != CellType.Floor ||
                map.GetCell(probe).SpecialBlockType != SpecialBlockType.None)
            {
                return Int2.Zero;
            }
        }

        return facing;
    }

    private static List<Int2> CollectCells(MapData map, Func<CellData, bool> predicate)
    {
        var result = new List<Int2>();
        for (var y = 0; y < map.Height; y++)
        {
            for (var x = 0; x < map.Width; x++)
            {
                if (predicate(map.GetCell(x, y)))
                {
                    result.Add(new Int2(x, y));
                }
            }
        }

        return result;
    }

    private static bool IsTooCloseManhattan(Int2 candidate, IEnumerable<Int2> placed, int spacing) =>
        placed.Any(cell => candidate.ManhattanDistanceTo(cell) < spacing);
}
