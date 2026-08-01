using System.Text.Json.Nodes;

namespace Wdc.MapGeneration;

public sealed partial class MapGenerator
{
    private void PlaceAllPois(MapData map, MapConfig config, Random random)
    {
        if (config.PoiTemplates.Count > 0)
        {
            PlaceConfiguredPois(map, config, random);
            return;
        }

        PlaceLegacyPoiKind(map, PoiType.LargeRuin, config.LargePoiCount, config.LargePoiMinDistance, config.LargePoiRadius, config.LargePoiIrregularity, random);
        PlaceLegacyPoiKind(map, PoiType.MediumBiome, config.MediumPoiCount, config.MediumPoiMinDistance, config.MediumPoiRadius, config.MediumPoiIrregularity, random);
        PlaceLegacyPoiKind(map, PoiType.SmallOre, config.SmallPoiCount, config.SmallPoiMinDistance, config.SmallPoiRadius, config.SmallPoiIrregularity, random);
    }

    private static void PlaceLegacyPoiKind(
        MapData map,
        PoiType poiType,
        int targetCount,
        double minimumDistance,
        int radius,
        double irregularity,
        Random random)
    {
        var placed = 0;
        var attempts = 0;
        var maxAttempts = Math.Max(targetCount * 50, 0);
        while (placed < targetCount && attempts < maxAttempts)
        {
            attempts++;
            if (TryPlaceLegacyPoi(map, poiType, minimumDistance, radius, irregularity, random))
            {
                placed++;
            }
        }
    }

    private static bool TryPlaceLegacyPoi(
        MapData map,
        PoiType poiType,
        double minimumDistance,
        int radius,
        double irregularity,
        Random random)
    {
        var minimumX = radius;
        var maximumX = map.Width - 1 - radius;
        var minimumY = radius;
        var maximumY = map.Height - 1 - radius;
        if (minimumX > maximumX || minimumY > maximumY)
        {
            return false;
        }

        var center = new Int2(NextInclusive(random, minimumX, maximumX), NextInclusive(random, minimumY, maximumY));
        if (map.PoiCenters.Any(existing => existing.Cell.DistanceTo(center) < minimumDistance))
        {
            return false;
        }

        var worldCells = new List<Int2>();
        foreach (var offset in GenerateCaShape(radius, irregularity, random))
        {
            var worldCell = center + offset;
            if (!map.IsInBounds(worldCell) || map.GetCell(worldCell).PoiType != PoiType.None)
            {
                return false;
            }

            worldCells.Add(worldCell);
        }

        foreach (var worldCell in worldCells)
        {
            var cell = map.GetCell(worldCell);
            cell.CellType = CellType.Floor;
            cell.PoiType = poiType;
            cell.IsPoiProtected = true;
        }

        map.PoiCenters.Add(new PoiCenter(center, poiType, string.Empty, string.Empty));
        return true;
    }

    private static List<Int2> GenerateCaShape(int radius, double irregularity, Random random)
    {
        if (radius <= 0)
        {
            return [Int2.Zero];
        }

        if (irregularity < 0.05)
        {
            return GenerateCircleShape(radius);
        }

        var localSize = radius * 2 + 3;
        var center = localSize / 2;
        var alive = new HashSet<Int2>();
        var protectedRadius = Math.Max(1, radius * (1 - irregularity * 0.55));
        for (var y = 0; y < localSize; y++)
        {
            for (var x = 0; x < localSize; x++)
            {
                var deltaX = x - center;
                var deltaY = y - center;
                var distance = Math.Sqrt(deltaX * deltaX + deltaY * deltaY);
                if (distance > radius + 0.6)
                {
                    continue;
                }

                var noiseBand = Math.Clamp((distance - protectedRadius) / Math.Max(radius + 0.6 - protectedRadius, double.Epsilon), 0, 1);
                var keepChance = Lerp(1 - irregularity * 0.15, 1 - irregularity, noiseBand);
                if (distance <= protectedRadius || random.NextDouble() < keepChance)
                {
                    alive.Add(new Int2(x, y));
                }
            }
        }

        for (var iteration = 0; iteration < 3; iteration++)
        {
            var next = new HashSet<Int2>();
            for (var y = 0; y < localSize; y++)
            {
                for (var x = 0; x < localSize; x++)
                {
                    var deltaX = x - center;
                    var deltaY = y - center;
                    var distance = Math.Sqrt(deltaX * deltaX + deltaY * deltaY);
                    if (distance > radius + 0.8)
                    {
                        continue;
                    }

                    var position = new Int2(x, y);
                    var neighbors = CountAliveNeighbors(alive, position);
                    var keep = alive.Contains(position);
                    if (neighbors > 4)
                    {
                        keep = true;
                    }
                    else if (neighbors < 4)
                    {
                        keep = false;
                    }

                    if (distance <= protectedRadius)
                    {
                        keep = true;
                    }

                    if (keep)
                    {
                        next.Add(position);
                    }
                }
            }

            alive = next;
        }

        var result = alive.OrderBy(cell => cell.Y).ThenBy(cell => cell.X)
            .Select(cell => new Int2(cell.X - center, cell.Y - center)).ToList();
        return result.Count == 0 ? GenerateCircleShape(radius) : result;
    }

    private static List<Int2> GenerateCircleShape(int radius)
    {
        var offsets = new List<Int2>();
        for (var y = -radius; y <= radius; y++)
        {
            for (var x = -radius; x <= radius; x++)
            {
                if (x * x + y * y <= radius * radius)
                {
                    offsets.Add(new Int2(x, y));
                }
            }
        }

        return offsets;
    }

    private static int CountAliveNeighbors(HashSet<Int2> alive, Int2 cell)
    {
        var count = 0;
        for (var y = -1; y <= 1; y++)
        {
            for (var x = -1; x <= 1; x++)
            {
                if ((x != 0 || y != 0) && alive.Contains(cell + new Int2(x, y)))
                {
                    count++;
                }
            }
        }

        return count;
    }

    private void PlaceConfiguredPois(MapData map, MapConfig config, Random random)
    {
        for (var templateIndex = 0; templateIndex < config.PoiTemplates.Count; templateIndex++)
        {
            var template = config.PoiTemplates[templateIndex];
            if (!template.Enabled)
            {
                continue;
            }

            var targetCount = Math.Max(template.Count, 0);
            var maximumAttempts = Math.Max(template.Placement.PoiAttempts, 1);
            var poiType = ResolveCompatPoiType(templateIndex);
            var placedTotal = 0;
            var layerBudget = SplitLayerBudget(targetCount, config, layer => layer.PoiBudgetWeight);
            foreach (var layer in config.MapLayers)
            {
                var layerTarget = layerBudget.GetValueOrDefault(layer.Id);
                var placedInLayer = 0;
                var attempts = 0;
                while (placedInLayer < layerTarget && attempts < maximumAttempts * Math.Max(layerTarget, 1))
                {
                    attempts++;
                    if (TryPlaceConfiguredPoi(map, config, template, poiType, random, layer.Id))
                    {
                        placedInLayer++;
                        placedTotal++;
                    }
                }
            }

            var fallbackAttempts = 0;
            while (placedTotal < targetCount && fallbackAttempts < maximumAttempts * Math.Max(targetCount, 1))
            {
                fallbackAttempts++;
                if (TryPlaceConfiguredPoi(map, config, template, poiType, random, string.Empty))
                {
                    placedTotal++;
                }
            }
        }
    }

    private static PoiType ResolveCompatPoiType(int templateIndex) => templateIndex switch
    {
        0 => PoiType.LargeRuin,
        1 => PoiType.MediumBiome,
        _ => PoiType.SmallOre,
    };

    private bool TryPlaceConfiguredPoi(
        MapData map,
        MapConfig config,
        PoiTemplateConfig template,
        PoiType poiType,
        Random random,
        string targetLayerId)
    {
        var mainMargin = Math.Max(template.SubRooms.PlacementRadiusMaxCells, Math.Max(template.Placement.FootprintPaddingCells, 0)) + 1;
        var mainRoom = SampleRoomRect(map, template.MainRoom, random, mainMargin);
        if (mainRoom.IsEmpty)
        {
            return false;
        }

        if (targetLayerId.Length > 0 && ResolveLayer(config, map, mainRoom.CenterCell).Id != targetLayerId)
        {
            return false;
        }

        var rooms = new List<IntRect> { mainRoom };
        var subCount = template.SubRooms.CountMax > 0
            ? NextInclusive(random, Math.Max(template.SubRooms.CountMin, 0), Math.Max(template.SubRooms.CountMax, template.SubRooms.CountMin))
            : 0;
        var placedSubRooms = 0;
        for (var index = 0; index < subCount; index++)
        {
            var room = SampleSubRoomRect(map, rooms, mainRoom, template.SubRooms, random);
            if (!room.IsEmpty)
            {
                rooms.Add(room);
                placedSubRooms++;
            }
        }

        if (placedSubRooms < Math.Max(template.SubRooms.CountMin, 0))
        {
            return false;
        }

        var edges = BuildPoiConnectivityEdges(rooms, template, random);
        if (edges.Count == 0 && rooms.Count > 1)
        {
            return false;
        }

        var corridors = BuildCorridorPlansForEdges(rooms, edges, template);
        var corridorCells = corridors.SelectMany(corridor => corridor.Cells).Distinct().OrderBy(cell => cell.Y).ThenBy(cell => cell.X).ToList();
        if (corridorCells.Count == 0 && rooms.Count > 1)
        {
            return false;
        }

        var bounds = ComputeTotalPoiBounds(rooms, corridorCells, template.Placement.FootprintPaddingCells);
        if (!IsPoiBoundsValid(map, bounds) || map.PoiInstances.Any(instance => bounds.Intersects(instance.Bounds)))
        {
            return false;
        }

        var contentPlans = BuildRoomContentPlans(rooms, corridors, template, config, random);
        if (contentPlans.Any(plan => plan.IsInvalid))
        {
            return false;
        }

        CarvePoiRoomsAndCorridors(map, rooms, corridorCells, poiType);
        PlacePoiOuterWalls(map, rooms, corridorCells, poiType);
        var layerId = ResolveLayer(config, map, mainRoom.CenterCell).Id;
        map.PoiCenters.Add(new PoiCenter(mainRoom.CenterCell, poiType, template.Id, layerId));
        var instance = new PoiInstance
        {
            TemplateId = template.Id,
            PoiType = poiType,
            LayerId = layerId,
            Bounds = bounds,
            MainRoom = mainRoom,
            CenterCell = mainRoom.CenterCell,
        };
        instance.SubRooms.AddRange(rooms.Skip(1));
        instance.Corridors.AddRange(corridors);
        instance.TorchSites.AddRange(BuildMainRoomTorchSites(mainRoom, template.Torch));
        instance.RoomContentPlans.AddRange(contentPlans);
        map.PoiInstances.Add(instance);
        AppendRoomContentSites(map, contentPlans, config, template.Id);
        PlacePoiCenterCluster(map, mainRoom, template, config, random, contentPlans);
        return true;
    }

    private static IntRect SampleRoomRect(MapData map, RoomSizeConfig room, Random random, int extraMargin)
    {
        var width = NextInclusive(random, Math.Max(room.WidthMin, 1), Math.Max(room.WidthMax, room.WidthMin));
        var height = NextInclusive(random, Math.Max(room.HeightMin, 1), Math.Max(room.HeightMax, room.HeightMin));
        if (width + extraMargin * 2 >= map.Width || height + extraMargin * 2 >= map.Height)
        {
            return IntRect.Empty;
        }

        var minimumX = Math.Max(extraMargin, 1);
        var minimumY = Math.Max(extraMargin, 1);
        var maximumX = Math.Max(map.Width - width - extraMargin, minimumX);
        var maximumY = Math.Max(map.Height - height - extraMargin, minimumY);
        return new IntRect(
            NextInclusive(random, minimumX, maximumX),
            NextInclusive(random, minimumY, maximumY),
            width,
            height);
    }

    private static IntRect SampleSubRoomRect(
        MapData map,
        IReadOnlyList<IntRect> existingRooms,
        IntRect mainRoom,
        SubRoomConfig config,
        Random random)
    {
        var attempts = Math.Max(config.PlacementAttemptsPerRoom, 12);
        var widthMin = Math.Max(config.WidthMin, 1);
        var widthMax = Math.Max(config.WidthMax, widthMin);
        var heightMin = Math.Max(config.HeightMin, 1);
        var heightMax = Math.Max(config.HeightMax, heightMin);
        var gap = Math.Max(config.MinGapFromRoomsCells, 0);
        var radiusMin = Math.Max(config.PlacementRadiusMinCells, 1);
        var radiusMax = Math.Max(config.PlacementRadiusMaxCells, radiusMin);
        foreach (var candidate in BuildPreferredSubRoomCandidates(mainRoom, widthMin, widthMax, heightMin, heightMax, gap, radiusMin, random))
        {
            if (IsRoomRectInBounds(map, candidate) && existingRooms.All(existing => !RectIntersectsWithMargin(candidate, existing, gap)))
            {
                return candidate;
            }
        }

        for (var attempt = 0; attempt < attempts; attempt++)
        {
            var width = NextInclusive(random, widthMin, widthMax);
            var height = NextInclusive(random, heightMin, heightMax);
            var radius = NextInclusive(random, radiusMin, radiusMax);
            var angle = random.NextDouble() * Math.Tau;
            var centerX = (int)Math.Round(mainRoom.CenterCell.X + Math.Cos(angle) * radius, MidpointRounding.AwayFromZero);
            var centerY = (int)Math.Round(mainRoom.CenterCell.Y + Math.Sin(angle) * radius, MidpointRounding.AwayFromZero);
            var candidate = new IntRect(
                centerX - (int)Math.Floor(width * 0.5),
                centerY - (int)Math.Floor(height * 0.5),
                width,
                height);
            if (IsRoomRectInBounds(map, candidate) && existingRooms.All(existing => !RectIntersectsWithMargin(candidate, existing, gap)))
            {
                return candidate;
            }
        }

        return IntRect.Empty;
    }

    private static List<IntRect> BuildPreferredSubRoomCandidates(
        IntRect mainRoom,
        int widthMin,
        int widthMax,
        int heightMin,
        int heightMax,
        int gap,
        int radiusMin,
        Random random)
    {
        var width = NextInclusive(random, widthMin, widthMax);
        var height = NextInclusive(random, heightMin, heightMax);
        var horizontalOffset = (int)Math.Ceiling(mainRoom.Size.X * 0.5) + (int)Math.Ceiling(width * 0.5) + gap + radiusMin;
        var verticalOffset = (int)Math.Ceiling(mainRoom.Size.Y * 0.5) + (int)Math.Ceiling(height * 0.5) + gap + radiusMin;
        var center = mainRoom.CenterCell;
        return
        [
            new IntRect(center.X + horizontalOffset - (int)Math.Floor(width * 0.5), center.Y - (int)Math.Floor(height * 0.5), width, height),
            new IntRect(center.X - horizontalOffset - (int)Math.Floor(width * 0.5), center.Y - (int)Math.Floor(height * 0.5), width, height),
            new IntRect(center.X - (int)Math.Floor(width * 0.5), center.Y + verticalOffset - (int)Math.Floor(height * 0.5), width, height),
            new IntRect(center.X - (int)Math.Floor(width * 0.5), center.Y - verticalOffset - (int)Math.Floor(height * 0.5), width, height),
        ];
    }

    private static List<PoiEdge> BuildPoiConnectivityEdges(
        IReadOnlyList<IntRect> rooms,
        PoiTemplateConfig template,
        Random random)
    {
        if (rooms.Count <= 1)
        {
            return [];
        }

        var neighborLimit = Math.Max(template.Connectivity.CandidateNeighborsPerRoom, 1);
        var candidates = new List<PoiEdge>();
        var seen = new HashSet<(int, int)>();
        for (var roomIndex = 0; roomIndex < rooms.Count; roomIndex++)
        {
            var distances = Enumerable.Range(0, rooms.Count)
                .Where(other => other != roomIndex)
                .Select(other => new PoiEdge(roomIndex, other, rooms[roomIndex].CenterCell.ManhattanDistanceTo(rooms[other].CenterCell)))
                .OrderBy(edge => edge.Distance)
                .ThenBy(edge => edge.To)
                .Take(neighborLimit);
            foreach (var edge in distances)
            {
                var key = EdgeKey(edge.From, edge.To);
                if (seen.Add(key))
                {
                    candidates.Add(edge);
                }
            }
        }

        for (var index = 0; index < rooms.Count - 1; index++)
        {
            var key = EdgeKey(index, index + 1);
            if (seen.Add(key))
            {
                candidates.Add(new PoiEdge(index, index + 1, rooms[index].CenterCell.ManhattanDistanceTo(rooms[index + 1].CenterCell)));
            }
        }

        var selected = BuildMstEdges(rooms.Count, candidates);
        var selectedKeys = selected.Select(edge => EdgeKey(edge.From, edge.To)).ToHashSet();
        var extras = candidates.Where(edge => !selectedKeys.Contains(EdgeKey(edge.From, edge.To)))
            .OrderBy(edge => edge.From).ThenBy(edge => edge.To).ToList();
        Shuffle(extras, random);
        foreach (var edge in extras)
        {
            if (selected.Count >= rooms.Count - 1 + template.Connectivity.MaxExtraConnections)
            {
                break;
            }

            if (random.NextDouble() <= Math.Clamp(template.Connectivity.ExtraConnectionChance, 0, 1))
            {
                selected.Add(edge);
            }
        }

        return selected;
    }

    private static List<PoiEdge> BuildMstEdges(int roomCount, IEnumerable<PoiEdge> candidateEdges)
    {
        var parent = Enumerable.Range(0, roomCount).ToArray();
        var result = new List<PoiEdge>();
        foreach (var edge in candidateEdges.OrderBy(edge => edge.Distance).ThenBy(edge => edge.From).ThenBy(edge => edge.To))
        {
            var rootA = FindSetRoot(parent, edge.From);
            var rootB = FindSetRoot(parent, edge.To);
            if (rootA == rootB)
            {
                continue;
            }

            parent[rootB] = rootA;
            result.Add(edge);
            if (result.Count >= roomCount - 1)
            {
                break;
            }
        }

        return result;
    }

    private static int FindSetRoot(int[] parent, int node)
    {
        var root = node;
        while (parent[root] != root)
        {
            root = parent[root];
        }

        return root;
    }

    private static List<CorridorData> BuildCorridorPlansForEdges(
        IReadOnlyList<IntRect> rooms,
        IEnumerable<PoiEdge> edges,
        PoiTemplateConfig template)
    {
        var result = new List<CorridorData>();
        foreach (var edge in edges)
        {
            var doorPair = SelectCorridorDoorwayPair(rooms[edge.From], rooms[edge.To], template.Corridor);
            var cells = BuildLShapedCorridor(doorPair.From, doorPair.To, template.Corridor.WidthCells, template.Corridor.BendOrderMode);
            if (cells.Count == 0)
            {
                return [];
            }

            var corridor = new CorridorData
            {
                FromRoom = edge.From,
                ToRoom = edge.To,
                FromDoor = doorPair.From,
                ToDoor = doorPair.To,
            };
            corridor.Cells.AddRange(cells);
            result.Add(corridor);
        }

        return result;
    }

    private static (Int2 From, Int2 To) SelectCorridorDoorwayPair(
        IntRect roomA,
        IntRect roomB,
        PoiCorridorConfig config)
    {
        var centerA = roomA.CenterCell;
        var centerB = roomB.CenterCell;
        var deltaX = centerB.X - centerA.X;
        var deltaY = centerB.Y - centerA.Y;
        if (Math.Abs(deltaX) >= Math.Abs(deltaY))
        {
            return (
                DoorwayOnHorizontalSide(roomA, deltaX >= 0, centerB.Y, config.DoorMarginFromCornerCells),
                DoorwayOnHorizontalSide(roomB, deltaX < 0, centerA.Y, config.DoorMarginFromCornerCells));
        }

        return (
            DoorwayOnVerticalSide(roomA, deltaY >= 0, centerB.X, config.DoorMarginFromCornerCells),
            DoorwayOnVerticalSide(roomB, deltaY < 0, centerA.X, config.DoorMarginFromCornerCells));
    }

    private static Int2 DoorwayOnHorizontalSide(IntRect room, bool rightSide, int preferredY, int margin)
    {
        var minimumY = room.Top + Math.Max(margin, 0);
        var maximumY = room.BottomExclusive - 1 - Math.Max(margin, 0);
        if (minimumY > maximumY)
        {
            minimumY = room.Top;
            maximumY = room.BottomExclusive - 1;
        }

        return new Int2(rightSide ? room.RightExclusive - 1 : room.Left, Math.Clamp(preferredY, minimumY, maximumY));
    }

    private static Int2 DoorwayOnVerticalSide(IntRect room, bool bottomSide, int preferredX, int margin)
    {
        var minimumX = room.Left + Math.Max(margin, 0);
        var maximumX = room.RightExclusive - 1 - Math.Max(margin, 0);
        if (minimumX > maximumX)
        {
            minimumX = room.Left;
            maximumX = room.RightExclusive - 1;
        }

        return new Int2(Math.Clamp(preferredX, minimumX, maximumX), bottomSide ? room.BottomExclusive - 1 : room.Top);
    }

    private static List<Int2> BuildLShapedCorridor(Int2 from, Int2 to, int width, string bendOrderMode)
    {
        var horizontalFirst = bendOrderMode != "vertical_first" &&
            (bendOrderMode != "random" || Math.Abs(from.X - to.X) >= Math.Abs(from.Y - to.Y));
        var radius = Math.Max((int)Math.Floor((Math.Max(width, 1) - 1) * 0.5), 0);
        var cells = new List<Int2>();
        if (horizontalFirst)
        {
            AppendCorridorLine(cells, from, new Int2(to.X, from.Y), radius);
            AppendCorridorLine(cells, new Int2(to.X, from.Y), to, radius);
        }
        else
        {
            AppendCorridorLine(cells, from, new Int2(from.X, to.Y), radius);
            AppendCorridorLine(cells, new Int2(from.X, to.Y), to, radius);
        }

        return cells;
    }

    private static void AppendCorridorLine(List<Int2> cells, Int2 from, Int2 to, int radius)
    {
        if (from.X == to.X)
        {
            for (var y = Math.Min(from.Y, to.Y); y <= Math.Max(from.Y, to.Y); y++)
            {
                for (var x = from.X - radius; x <= from.X + radius; x++)
                {
                    cells.Add(new Int2(x, y));
                }
            }
        }
        else
        {
            for (var x = Math.Min(from.X, to.X); x <= Math.Max(from.X, to.X); x++)
            {
                for (var y = from.Y - radius; y <= from.Y + radius; y++)
                {
                    cells.Add(new Int2(x, y));
                }
            }
        }
    }

    private static void CarvePoiRoomsAndCorridors(MapData map, IEnumerable<IntRect> rooms, IEnumerable<Int2> corridors, PoiType poiType)
    {
        foreach (var room in rooms)
        {
            for (var y = room.Top; y < room.BottomExclusive; y++)
            {
                for (var x = room.Left; x < room.RightExclusive; x++)
                {
                    if (map.IsInBounds(x, y))
                    {
                        SetPoiFloor(map.GetCell(x, y), poiType);
                    }
                }
            }
        }

        foreach (var corridor in corridors.Where(map.IsInBounds))
        {
            SetPoiFloor(map.GetCell(corridor), poiType);
        }
    }

    private static void SetPoiFloor(CellData cell, PoiType poiType)
    {
        cell.CellType = CellType.Floor;
        cell.PoiType = poiType;
        cell.IsPoiProtected = true;
    }

    private static void PlacePoiOuterWalls(MapData map, IEnumerable<IntRect> rooms, IEnumerable<Int2> corridors, PoiType poiType)
    {
        var roomList = rooms.ToList();
        var corridorList = corridors.ToList();
        var interior = new HashSet<Int2>(corridorList);
        foreach (var room in roomList)
        {
            for (var y = room.Top; y < room.BottomExclusive; y++)
            {
                for (var x = room.Left; x < room.RightExclusive; x++)
                {
                    interior.Add(new Int2(x, y));
                }
            }
        }

        var shell = new HashSet<Int2>();
        foreach (var room in roomList)
        {
            for (var y = room.Top - 1; y <= room.BottomExclusive; y++)
            {
                for (var x = room.Left - 1; x <= room.RightExclusive; x++)
                {
                    var cell = new Int2(x, y);
                    if (!interior.Contains(cell) && map.IsInBounds(cell))
                    {
                        shell.Add(cell);
                    }
                }
            }
        }

        foreach (var corridor in corridorList)
        {
            for (var y = -1; y <= 1; y++)
            {
                for (var x = -1; x <= 1; x++)
                {
                    var cell = corridor + new Int2(x, y);
                    if (!interior.Contains(cell) && map.IsInBounds(cell))
                    {
                        shell.Add(cell);
                    }
                }
            }
        }

        foreach (var position in shell.OrderBy(cell => cell.Y).ThenBy(cell => cell.X))
        {
            var cell = map.GetCell(position);
            cell.CellType = CellType.Wall;
            cell.PoiType = poiType;
            cell.IsPoiProtected = true;
            cell.HasMineral = false;
            cell.SpecialBlockType = SpecialBlockType.PoiWall;
        }
    }

    private static IntRect ComputeTotalPoiBounds(IEnumerable<IntRect> rooms, IEnumerable<Int2> corridors, int padding)
    {
        var roomList = rooms.ToList();
        var corridorList = corridors.ToList();
        var minimumX = roomList.Min(room => room.Left);
        var minimumY = roomList.Min(room => room.Top);
        var maximumX = roomList.Max(room => room.RightExclusive - 1);
        var maximumY = roomList.Max(room => room.BottomExclusive - 1);
        if (corridorList.Count > 0)
        {
            minimumX = Math.Min(minimumX, corridorList.Min(cell => cell.X));
            minimumY = Math.Min(minimumY, corridorList.Min(cell => cell.Y));
            maximumX = Math.Max(maximumX, corridorList.Max(cell => cell.X));
            maximumY = Math.Max(maximumY, corridorList.Max(cell => cell.Y));
        }

        padding = Math.Max(padding, 0);
        return new IntRect(
            minimumX - padding,
            minimumY - padding,
            maximumX - minimumX + 1 + padding * 2,
            maximumY - minimumY + 1 + padding * 2);
    }

    private static bool IsPoiBoundsValid(MapData map, IntRect bounds) =>
        bounds.Left >= 0 && bounds.Top >= 0 && bounds.RightExclusive <= map.Width && bounds.BottomExclusive <= map.Height;

    private static bool IsRoomRectInBounds(MapData map, IntRect room) =>
        !room.IsEmpty && room.Left >= 1 && room.Top >= 1 && room.RightExclusive < map.Width && room.BottomExclusive < map.Height;

    private static bool RectIntersectsWithMargin(IntRect first, IntRect second, int margin) => first.Intersects(second.Grow(Math.Max(margin, 0)));

    private static (int, int) EdgeKey(int first, int second) => (Math.Min(first, second), Math.Max(first, second));

    private static List<Int2> BuildMainRoomTorchSites(IntRect room, TorchConfig config)
    {
        if (!config.Enabled || config.MaxTorchCount <= 0)
        {
            return [];
        }

        var inset = Math.Max(config.WallInsetCells, 0);
        var candidates = new List<Int2>
        {
            new(room.Left + inset, room.Top + inset),
            new(room.RightExclusive - 1 - inset, room.Top + inset),
            new(room.Left + inset, room.BottomExclusive - 1 - inset),
            new(room.RightExclusive - 1 - inset, room.BottomExclusive - 1 - inset),
        };
        if (room.Size.X >= 10)
        {
            candidates.Add(new Int2(room.CenterCell.X, room.Top + inset));
            candidates.Add(new Int2(room.CenterCell.X, room.BottomExclusive - 1 - inset));
        }

        if (room.Size.Y >= 10)
        {
            candidates.Add(new Int2(room.Left + inset, room.CenterCell.Y));
            candidates.Add(new Int2(room.RightExclusive - 1 - inset, room.CenterCell.Y));
        }

        return candidates.Where(room.Contains).Distinct().Take(config.MaxTorchCount).ToList();
    }

    private List<RoomContentPlan> BuildRoomContentPlans(
        IReadOnlyList<IntRect> rooms,
        IReadOnlyList<CorridorData> corridors,
        PoiTemplateConfig template,
        MapConfig config,
        Random random)
    {
        var plans = new List<RoomContentPlan>();
        for (var roomIndex = 0; roomIndex < rooms.Count; roomIndex++)
        {
            var roomKind = roomIndex == 0 ? "main" : "sub";
            var rollConfig = roomIndex == 0 ? template.MainRoomRoll : template.SubRoomRoll;
            var doorCells = corridors.Where(corridor => corridor.FromRoom == roomIndex || corridor.ToRoom == roomIndex)
                .Select(corridor => corridor.FromRoom == roomIndex ? corridor.FromDoor : corridor.ToDoor).ToList();
            plans.Add(RollRoomContentPlan(
                roomIndex,
                roomKind,
                rooms[roomIndex],
                rollConfig,
                roomIndex == 0 ? template.CenterOreCluster : new CenterOreClusterConfig(),
                doorCells,
                config,
                random));
        }

        return plans;
    }

    private RoomContentPlan RollRoomContentPlan(
        int roomIndex,
        string roomKind,
        IntRect room,
        RoomContentRollConfig rollConfig,
        CenterOreClusterConfig centerCluster,
        IReadOnlyList<Int2> doorCells,
        MapConfig config,
        Random random)
    {
        var noneWeight = Math.Max(rollConfig.NoneWeight, 0);
        var monsterWeight = rollConfig.MonsterEntries.Sum(entry => Math.Max(entry.Weight, 0));
        var nestWeight = rollConfig.NestEntries.Sum(entry => Math.Max(entry.Weight, 0));
        var campWeight = rollConfig.CampEntries.Sum(entry => Math.Max(entry.Weight, 0));
        var layer = ResolveLayer(config, null, room.CenterCell);
        var danger = Math.Max(layer.RoomContentDangerMultiplier, 0);
        if (danger > 0)
        {
            monsterWeight *= danger;
            nestWeight *= danger;
            campWeight *= danger;
            noneWeight /= danger;
        }

        var contentKind = "none";
        var templateId = string.Empty;
        CampEntryConfig? campEntry = null;
        var total = noneWeight + monsterWeight + nestWeight + campWeight;
        if (total > 0)
        {
            var roll = random.NextDouble() * total;
            if (roll <= noneWeight)
            {
                contentKind = "none";
            }
            else if (roll <= noneWeight + monsterWeight)
            {
                contentKind = "monster_pack";
                templateId = PickWeighted(rollConfig.MonsterEntries, entry => entry.Weight, random)?.Id ?? string.Empty;
            }
            else if (roll <= noneWeight + monsterWeight + nestWeight)
            {
                contentKind = "nest";
                templateId = PickWeighted(rollConfig.NestEntries, entry => entry.Weight, random)?.Id ?? string.Empty;
            }
            else
            {
                contentKind = "locked_treasure_camp";
                campEntry = PickWeighted(rollConfig.CampEntries, entry => entry.Weight, random);
                templateId = campEntry?.Id ?? string.Empty;
            }
        }

        var plan = new RoomContentPlan
        {
            RoomIndex = roomIndex,
            RoomKind = roomKind,
            RoomRect = room,
            ContentKind = contentKind,
            TemplateId = templateId,
            AnchorCell = ResolveRoomContentAnchor(
                room,
                doorCells,
                Math.Max(rollConfig.MinDistanceFromDoorCells, 0),
                Math.Max(centerCluster.AvoidRadiusCells, 0),
                roomKind == "main"),
            LayerId = layer.Id,
        };
        if (contentKind == "locked_treasure_camp")
        {
            ApplyLockedTreasureCampPlan(plan, room, doorCells, rollConfig, campEntry, config, random);
        }

        return plan;
    }

    private static Int2 ResolveRoomContentAnchor(
        IntRect room,
        IReadOnlyList<Int2> doors,
        int minimumDoorDistance,
        int centerAvoidRadius,
        bool avoidCenter)
    {
        if (IsValidRoomContentAnchor(room.CenterCell, room, doors, minimumDoorDistance, centerAvoidRadius, avoidCenter))
        {
            return room.CenterCell;
        }

        var candidates = new List<Int2>();
        for (var y = room.Top; y < room.BottomExclusive; y++)
        {
            for (var x = room.Left; x < room.RightExclusive; x++)
            {
                var candidate = new Int2(x, y);
                if (IsValidRoomContentAnchor(candidate, room, doors, minimumDoorDistance, centerAvoidRadius, avoidCenter))
                {
                    candidates.Add(candidate);
                }
            }
        }

        return candidates.OrderBy(cell => cell.DistanceSquaredTo(room.CenterCell)).ThenBy(cell => cell.Y).ThenBy(cell => cell.X).FirstOrDefault(room.CenterCell);
    }

    private static bool IsValidRoomContentAnchor(
        Int2 candidate,
        IntRect room,
        IEnumerable<Int2> doors,
        int minimumDoorDistance,
        int centerAvoidRadius,
        bool avoidCenter) =>
        room.Contains(candidate) &&
        (!avoidCenter || centerAvoidRadius <= 0 || candidate.DistanceTo(room.CenterCell) > centerAvoidRadius) &&
        doors.All(door => candidate.DistanceTo(door) >= minimumDoorDistance);

    private static void ApplyLockedTreasureCampPlan(
        RoomContentPlan plan,
        IntRect room,
        IReadOnlyList<Int2> doors,
        RoomContentRollConfig rollConfig,
        CampEntryConfig? camp,
        MapConfig config,
        Random random)
    {
        if (camp is null)
        {
            plan.IsInvalid = true;
            return;
        }

        var chest = room.CenterCell;
        var guardMinimum = Math.Max(camp.GuardCountMin, 1);
        var guardMaximum = Math.Max(camp.GuardCountMax, guardMinimum);
        var requestedGuardCount = NextInclusive(random, guardMinimum, guardMaximum);
        var guards = PickCampGuardCells(
            room,
            doors,
            chest,
            Math.Max(camp.MinDistanceFromDoorCells ?? rollConfig.MinDistanceFromDoorCells, 0),
            Math.Max(camp.ChestAvoidRadiusCells, 0),
            requestedGuardCount,
            random);
        if (guards.Count < guardMinimum)
        {
            plan.IsInvalid = true;
            return;
        }

        foreach (var guardCell in guards.Take(requestedGuardCount))
        {
            var guardEntry = PickWeighted(camp.GuardEntries, entry => entry.Weight, random);
            var templateId = guardEntry?.Id ?? string.Empty;
            var monsterId = config.IsolatedSpawnTemplates.FirstOrDefault(template => template.Id == templateId)?.MonsterId ?? string.Empty;
            if (monsterId.Length == 0)
            {
                plan.IsInvalid = true;
                return;
            }

            plan.GuardSites.Add(new GuardSite { Cell = guardCell, MonsterId = monsterId, TemplateId = templateId });
        }

        plan.ChestCell = chest;
        plan.LootContainer = NormalizeCampLootContainer(camp.LootContainer);
        plan.LockedPromptText = camp.LockedPromptText;
    }

    private static List<Int2> PickCampGuardCells(
        IntRect room,
        IReadOnlyList<Int2> doors,
        Int2 chest,
        int minimumDoorDistance,
        int chestAvoidRadius,
        int guardCount,
        Random random)
    {
        var candidates = new List<Int2>();
        for (var y = room.Top; y < room.BottomExclusive; y++)
        {
            for (var x = room.Left; x < room.RightExclusive; x++)
            {
                var candidate = new Int2(x, y);
                if (candidate != chest && candidate.DistanceTo(chest) > chestAvoidRadius &&
                    doors.All(door => candidate.DistanceTo(door) >= minimumDoorDistance))
                {
                    candidates.Add(candidate);
                }
            }
        }

        var selected = new List<Int2>();
        while (candidates.Count > 0 && selected.Count < guardCount)
        {
            var index = NextInclusive(random, 0, candidates.Count - 1);
            selected.Add(candidates[index]);
            candidates.RemoveAt(index);
        }

        return selected;
    }

    private static JsonObject NormalizeCampLootContainer(JsonObject source)
    {
        var output = (source.DeepClone() as JsonObject) ?? [];
        output["container_kind"] ??= "loot_container";
        output["container_title"] ??= "营地宝箱";
        output["visual_kind"] ??= "treasure_chest";
        output["grid_width"] = Math.Max(output.Int("grid_width", 4), 1);
        output["grid_height"] = Math.Max(output.Int("grid_height", 2), 1);
        output["slot_columns"] = Math.Max(output.Int("slot_columns", output.Int("grid_width", 4)), 1);
        output["blocked_cells"] ??= new JsonArray();
        output["slot_snapshots"] ??= new JsonArray();
        output["placement_snapshots"] ??= output["placements"]?.DeepClone() ?? new JsonArray();
        output["destroy_when_empty"] ??= false;
        output["empty_cleanup_delay_sec"] ??= 8.0;
        return output;
    }

    private static void AppendRoomContentSites(
        MapData map,
        IEnumerable<RoomContentPlan> plans,
        MapConfig config,
        string poiTemplateId)
    {
        foreach (var plan in plans)
        {
            if (plan.ContentKind == "monster_pack")
            {
                var template = config.IsolatedSpawnTemplates.FirstOrDefault(item => item.Id == plan.TemplateId);
                if (template is not null)
                {
                    map.MonsterSites.Add(new MonsterSite
                    {
                        SiteKind = "isolated",
                        RoomKind = plan.RoomKind,
                        Cell = plan.AnchorCell,
                        TemplateId = plan.TemplateId,
                        MonsterId = template.MonsterId,
                        LayerId = plan.LayerId,
                    });
                }
            }
            else if (plan.ContentKind == "nest")
            {
                var template = config.NestTemplates.FirstOrDefault(item => item.Id == plan.TemplateId);
                if (template is not null)
                {
                    map.MonsterSites.Add(new MonsterSite
                    {
                        SiteKind = "nest",
                        RoomKind = plan.RoomKind,
                        Cell = plan.AnchorCell,
                        TemplateId = plan.TemplateId,
                        NestUnitId = template.NestUnitId,
                        MonsterId = template.MonsterId,
                        LootTableId = template.LootTableId,
                        ActivationRadiusM = template.ActivationRadiusM,
                        SpawnIntervalSec = template.SpawnIntervalSec,
                        MaxAliveChildren = template.MaxAliveChildren,
                        MaxHitPoints = template.MaxHitPoints,
                        LayerId = plan.LayerId,
                    });
                }
            }
            else if (plan.ContentKind == "locked_treasure_camp" && plan.ChestCell is { } chest)
            {
                var encounter = new CampEncounter
                {
                    EncounterId = plan.EncounterId.Length > 0 ? plan.EncounterId : $"camp_{map.CampEncounters.Count + 1:000}",
                    PoiTemplateId = poiTemplateId,
                    LayerId = plan.LayerId,
                    RoomIndex = plan.RoomIndex,
                    RoomKind = plan.RoomKind,
                    RoomRect = plan.RoomRect,
                    ChestCell = chest,
                    LootContainer = (plan.LootContainer.DeepClone() as JsonObject) ?? [],
                    LockedPromptText = plan.LockedPromptText,
                };
                encounter.GuardSites.AddRange(plan.GuardSites);
                map.CampEncounters.Add(encounter);
            }
        }
    }

    private static void PlacePoiCenterCluster(
        MapData map,
        IntRect mainRoom,
        PoiTemplateConfig template,
        MapConfig config,
        Random random,
        IEnumerable<RoomContentPlan> plans)
    {
        if (plans.Any(plan => plan.RoomIndex == 0 && plan.ContentKind == "locked_treasure_camp") ||
            !template.CenterOreCluster.Enabled || template.CenterOreCluster.ClusterOverrideId.Length == 0)
        {
            return;
        }

        var cluster = config.MineralClusterOverrides.FirstOrDefault(item => item.Id == template.CenterOreCluster.ClusterOverrideId);
        if (cluster is not null)
        {
            GrowClusterFromSeed(map, mainRoom.CenterCell, config, cluster, random);
        }
    }

    private void GenerateTraces(MapData map, MapConfig config, Random random)
    {
        foreach (var center in map.PoiCenters)
        {
            var trace = config.PoiTemplates.FirstOrDefault(template => template.Id == center.TemplateId)?.Trace ??
                LegacyTrace(config, center.PoiType);
            if (!trace.Enabled || trace.RadiusCells <= 0)
            {
                continue;
            }

            var integerRadius = (int)Math.Ceiling(trace.RadiusCells);
            for (var y = center.Cell.Y - integerRadius; y <= center.Cell.Y + integerRadius; y++)
            {
                for (var x = center.Cell.X - integerRadius; x <= center.Cell.X + integerRadius; x++)
                {
                    if (!map.IsInBounds(x, y))
                    {
                        continue;
                    }

                    var cell = map.GetCell(x, y);
                    if (cell.PoiType != PoiType.None || cell.SpecialBlockType != SpecialBlockType.None ||
                        (cell.CellType == CellType.Wall && cell.HasMineral))
                    {
                        continue;
                    }

                    var deltaX = x - center.Cell.X;
                    var deltaY = y - center.Cell.Y;
                    var distance = Math.Sqrt(deltaX * deltaX + deltaY * deltaY);
                    if (distance <= 0 || distance > trace.RadiusCells)
                    {
                        continue;
                    }

                    var ratio = distance / trace.RadiusCells;
                    var angle = Math.Atan2(deltaY, deltaX);
                    var wave = 0.5 + 0.5 * Math.Sin(angle * trace.Rays + ratio * trace.Twist * Math.Tau);
                    var chance = trace.DensityRatio * (1 - ratio) * (0.6 + wave * 0.4);
                    if (random.NextDouble() < chance)
                    {
                        cell.TraceType = center.PoiType;
                    }
                }
            }
        }
    }

    private static TraceConfig LegacyTrace(MapConfig config, PoiType poiType) => poiType switch
    {
        PoiType.LargeRuin => new TraceConfig { RadiusCells = config.TraceLargeRadius, DensityRatio = config.TraceLargeDensity, Rays = config.TraceLargeRays, Twist = config.TraceLargeTwist },
        PoiType.MediumBiome => new TraceConfig { RadiusCells = config.TraceMediumRadius, DensityRatio = config.TraceMediumDensity, Rays = config.TraceMediumRays, Twist = config.TraceMediumTwist },
        _ => new TraceConfig { RadiusCells = config.TraceSmallRadius, DensityRatio = config.TraceSmallDensity, Rays = config.TraceSmallRays, Twist = config.TraceSmallTwist },
    };

    private static void GeneratePoiSpecialBlocks(MapData map, MapConfig config, Random random)
    {
        AssignSpecialBlocks(map, PoiType.SmallOre, SpecialBlockType.Turquoise, config.SmallPoiSpecialBlockCount, random);
        AssignSpecialBlocks(map, PoiType.MediumBiome, SpecialBlockType.Amethyst, config.MediumPoiSpecialBlockCount, random);
        AssignSpecialBlocks(map, PoiType.LargeRuin, SpecialBlockType.Gold, config.LargePoiSpecialBlockCount, random);
    }

    private static void AssignSpecialBlocks(
        MapData map,
        PoiType poiType,
        SpecialBlockType specialType,
        int countPerPoi,
        Random random)
    {
        if (countPerPoi <= 0)
        {
            return;
        }

        var candidates = new List<CellData>();
        for (var y = 0; y < map.Height; y++)
        {
            for (var x = 0; x < map.Width; x++)
            {
                if (map.GetCell(x, y).PoiType == poiType)
                {
                    candidates.Add(map.GetCell(x, y));
                }
            }
        }

        foreach (var center in map.PoiCenters.Where(item => item.PoiType == poiType))
        {
            for (var index = 0; index < countPerPoi; index++)
            {
                CellData? selected = null;
                long bestDistance = long.MaxValue;
                foreach (var candidate in candidates.Where(cell => cell.SpecialBlockType == SpecialBlockType.None))
                {
                    var distance = new Int2(candidate.X, candidate.Y).DistanceSquaredTo(center.Cell);
                    if (distance < bestDistance || (distance == bestDistance && random.NextDouble() < 0.5))
                    {
                        selected = candidate;
                        bestDistance = distance;
                    }
                }

                if (selected is null)
                {
                    break;
                }

                selected.CellType = CellType.Wall;
                selected.HasMineral = false;
                selected.SpecialBlockType = specialType;
            }
        }
    }

    private sealed record PoiEdge(int From, int To, int Distance);
}
