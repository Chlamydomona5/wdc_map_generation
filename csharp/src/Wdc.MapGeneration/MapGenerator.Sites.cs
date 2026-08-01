namespace Wdc.MapGeneration;

public sealed partial class MapGenerator
{
    private void GenerateSpawnAndExtractionSites(MapData map, MapConfig config)
    {
        map.PlayerSpawnPoints.Clear();
        map.ExtractionSites.Clear();
        var spawnCells = SelectLayerSiteCells(
            map,
            config,
            config.PlayerSpawnLayerId,
            config.PlayerSpawnCount,
            config.PlayerSpawnEdgeMarginCells,
            config.PlayerSpawnClearanceRadiusCells,
            config.PlayerSpawnMinClearanceRatio,
            config.PlayerSpawnMinDistanceBetweenSpawnsCells,
            [],
            0,
            "player_spawn");
        foreach (var selected in spawnCells)
        {
            map.PlayerSpawnPoints.Add(BuildSite(map, config, selected.Cell, "player_spawn", config.PlayerSpawnLayerId, selected.FallbackReason));
        }

        var reserved = spawnCells.Select(selected => selected.Cell).ToList();
        foreach (var layerEntry in ResolveSiteLayerCounts(config.ExtractionSiteCount, config.ExtractionSiteLayerDistribution))
        {
            var extractionCells = SelectLayerSiteCells(
                map,
                config,
                layerEntry.LayerId,
                layerEntry.Count,
                config.ExtractionSiteEdgeMarginCells,
                config.ExtractionSiteClearanceRadiusCells,
                config.ExtractionSiteMinClearanceRatio,
                config.ExtractionSiteMinDistanceBetweenSitesCells,
                reserved,
                config.ExtractionSiteMinDistanceFromPlayerSpawnsCells,
                "extraction");
            foreach (var selected in extractionCells)
            {
                map.ExtractionSites.Add(BuildSite(map, config, selected.Cell, "extraction", layerEntry.LayerId, selected.FallbackReason));
                reserved.Add(selected.Cell);
            }
        }
    }

    private List<SelectedSite> SelectLayerSiteCells(
        MapData map,
        MapConfig config,
        string targetLayerId,
        int targetCount,
        int edgeMargin,
        int clearanceRadius,
        double minimumClearance,
        double minimumBetweenDistance,
        IReadOnlyList<Int2> avoidCells,
        double minimumAvoidDistance,
        string siteKind)
    {
        if (targetCount <= 0)
        {
            return [];
        }

        var candidates = CollectLayerSiteCandidates(
            map,
            config,
            targetLayerId,
            edgeMargin,
            clearanceRadius,
            minimumClearance,
            avoidCells,
            minimumAvoidDistance);
        var selected = new List<SelectedSite>();
        var used = avoidCells.ToHashSet();
        var passes = new[]
        {
            new SitePass(true, true, true, true, string.Empty),
            new SitePass(true, false, true, true, "relaxed_clearance"),
            new SitePass(true, false, false, true, "relaxed_source_distance"),
            new SitePass(false, false, false, false, "carved_layer_cell"),
        };
        foreach (var pass in passes)
        {
            foreach (var candidate in candidates)
            {
                if (selected.Count >= targetCount)
                {
                    break;
                }

                if ((pass.RequireFloor && !candidate.IsFloor) ||
                    (pass.RequireClearance && !candidate.ClearanceOk) ||
                    (pass.RequireAvoidDistance && !candidate.AvoidDistanceOk) ||
                    used.Contains(candidate.Cell))
                {
                    continue;
                }

                var minimumBetweenSquared = minimumBetweenDistance * minimumBetweenDistance;
                if (pass.EnforceBetweenDistance && selected.Any(item => item.Cell.DistanceSquaredTo(candidate.Cell) < minimumBetweenSquared))
                {
                    continue;
                }

                if (!candidate.IsFloor)
                {
                    CarveSiteFloorCell(map, candidate.Cell);
                }

                used.Add(candidate.Cell);
                selected.Add(new SelectedSite(candidate.Cell, pass.FallbackReason));
            }

            if (selected.Count >= targetCount)
            {
                break;
            }
        }

        return selected;
    }

    private List<SiteCandidate> CollectLayerSiteCandidates(
        MapData map,
        MapConfig config,
        string targetLayerId,
        int edgeMargin,
        int clearanceRadius,
        double minimumClearance,
        IReadOnlyList<Int2> avoidCells,
        double minimumAvoidDistance)
    {
        var result = new List<SiteCandidate>();
        var centerX = (map.Width - 1) * 0.5;
        var centerY = (map.Height - 1) * 0.5;
        var avoidDistanceSquared = minimumAvoidDistance * minimumAvoidDistance;
        var margin = Math.Max(edgeMargin, 0);
        for (var y = 0; y < map.Height; y++)
        {
            for (var x = 0; x < map.Width; x++)
            {
                if (x < margin || y < margin || x >= map.Width - margin || y >= map.Height - margin)
                {
                    continue;
                }

                var position = new Int2(x, y);
                var layerId = ResolveLayer(config, map, position).Id;
                if (targetLayerId.Length > 0 && layerId != targetLayerId)
                {
                    continue;
                }

                var isFloor = IsCleanSiteFloor(map.GetCell(position));
                var clearance = ComputeSiteClearanceRatio(map, position, clearanceRadius);
                var avoidOk = avoidCells.Count == 0 || minimumAvoidDistance <= 0 ||
                              avoidCells.All(cell => cell.DistanceSquaredTo(position) >= avoidDistanceSquared);
                var centerDistanceSquared = Math.Pow(x - centerX, 2) + Math.Pow(y - centerY, 2);
                result.Add(new SiteCandidate(
                    position,
                    isFloor,
                    clearance >= minimumClearance,
                    avoidOk,
                    clearance,
                    centerDistanceSquared,
                    StableSiteTieBreaker(position, targetLayerId)));
            }
        }

        var outer = targetLayerId == "outer";
        result.Sort((first, second) =>
        {
            var clearance = second.ClearanceRatio.CompareTo(first.ClearanceRatio);
            if (clearance != 0)
            {
                return clearance;
            }

            var distance = outer
                ? second.CenterDistanceSquared.CompareTo(first.CenterDistanceSquared)
                : first.CenterDistanceSquared.CompareTo(second.CenterDistanceSquared);
            if (distance != 0)
            {
                return distance;
            }

            var tie = first.Tie.CompareTo(second.Tie);
            if (tie != 0)
            {
                return tie;
            }

            var y = first.Cell.Y.CompareTo(second.Cell.Y);
            return y != 0 ? y : first.Cell.X.CompareTo(second.Cell.X);
        });
        return result;
    }

    private static bool IsCleanSiteFloor(CellData cell) =>
        cell.CellType == CellType.Floor && cell.SpecialBlockType == SpecialBlockType.None;

    private static void CarveSiteFloorCell(MapData map, Int2 position)
    {
        var cell = map.GetCell(position);
        cell.CellType = CellType.Floor;
        cell.HasMineral = false;
        cell.SpecialBlockType = SpecialBlockType.None;
        cell.PoiType = PoiType.None;
        cell.TraceType = PoiType.None;
        cell.IsPoiProtected = false;
        cell.DurabilityOverrideMaxHitPoints = 0;
        TileRules.RefreshCellRuntimeState(cell);
    }

    private static double ComputeSiteClearanceRatio(MapData map, Int2 center, int radius)
    {
        radius = Math.Max(radius, 0);
        if (radius == 0)
        {
            return IsCleanSiteFloor(map.GetCell(center)) ? 1 : 0;
        }

        var total = 0;
        var floor = 0;
        for (var y = center.Y - radius; y <= center.Y + radius; y++)
        {
            for (var x = center.X - radius; x <= center.X + radius; x++)
            {
                total++;
                if (map.IsInBounds(x, y) && IsCleanSiteFloor(map.GetCell(x, y)))
                {
                    floor++;
                }
            }
        }

        return total == 0 ? 0 : (double)floor / total;
    }

    private static List<SiteLayerCount> ResolveSiteLayerCounts(int totalCount, IReadOnlyList<SiteLayerRatio> distribution)
    {
        if (totalCount <= 0)
        {
            return [];
        }

        var entries = distribution.Where(entry => entry.Ratio > 0 && entry.LayerId.Length > 0)
            .Select(entry => new SiteLayerAllocation(entry.LayerId, entry.Ratio)).ToList();
        if (entries.Count == 0)
        {
            return [new SiteLayerCount("inner", totalCount)];
        }

        var totalRatio = entries.Sum(entry => entry.Ratio);
        var assigned = 0;
        for (var index = 0; index < entries.Count; index++)
        {
            var exact = totalCount * entries[index].Ratio / totalRatio;
            var count = (int)Math.Floor(exact);
            entries[index] = entries[index] with { Count = count, Remainder = exact - count };
            assigned += count;
        }

        if (totalCount >= entries.Count)
        {
            for (var index = 0; index < entries.Count; index++)
            {
                if (entries[index].Count == 0)
                {
                    entries[index] = entries[index] with { Count = 1 };
                    assigned++;
                }
            }
        }

        while (assigned > totalCount)
        {
            var index = entries.Select((entry, i) => (entry, i))
                .Where(pair => pair.entry.Count > 0)
                .OrderByDescending(pair => pair.entry.Count)
                .ThenBy(pair => pair.entry.Ratio)
                .ThenBy(pair => pair.entry.LayerId, StringComparer.Ordinal)
                .First().i;
            entries[index] = entries[index] with { Count = entries[index].Count - 1 };
            assigned--;
        }

        var ordered = entries.OrderByDescending(entry => entry.Remainder)
            .ThenByDescending(entry => entry.Ratio)
            .ThenBy(entry => entry.LayerId, StringComparer.Ordinal).ToList();
        var cursor = 0;
        while (assigned < totalCount)
        {
            var index = cursor % ordered.Count;
            ordered[index] = ordered[index] with { Count = ordered[index].Count + 1 };
            assigned++;
            cursor++;
        }

        return ordered.OrderBy(entry => entry.LayerId, StringComparer.Ordinal)
            .Select(entry => new SiteLayerCount(entry.LayerId, entry.Count)).ToList();
    }

    private MapSite BuildSite(
        MapData map,
        MapConfig config,
        Int2 cell,
        string kind,
        string requestedLayer,
        string fallbackReason)
    {
        return new MapSite
        {
            Cell = cell,
            SiteKind = kind,
            LayerId = ResolveLayer(config, map, cell).Id,
            RequestedLayerId = requestedLayer,
            FallbackReason = fallbackReason,
        };
    }

    private int StableSiteTieBreaker(Int2 cell, string salt)
    {
        unchecked
        {
            uint hash = 2166136261;
            foreach (var character in salt)
            {
                hash ^= character;
                hash *= 16777619;
            }

            return (int)(
                ((uint)cell.X * 73856093u) ^
                ((uint)cell.Y * 19349663u) ^
                ((uint)LastResolvedSeed * 83492791u) ^ hash);
        }
    }

    private sealed record SiteCandidate(
        Int2 Cell,
        bool IsFloor,
        bool ClearanceOk,
        bool AvoidDistanceOk,
        double ClearanceRatio,
        double CenterDistanceSquared,
        int Tie);

    private sealed record SitePass(
        bool RequireFloor,
        bool RequireClearance,
        bool RequireAvoidDistance,
        bool EnforceBetweenDistance,
        string FallbackReason);

    private sealed record SelectedSite(Int2 Cell, string FallbackReason);
    private sealed record SiteLayerCount(string LayerId, int Count);
    private sealed record SiteLayerAllocation(string LayerId, double Ratio, int Count = 0, double Remainder = 0);
}
