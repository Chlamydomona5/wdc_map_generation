namespace Wdc.MapGeneration;

public sealed partial class MapGenerator
{
    private static void FillNoise(MapData map, double fillPercent, Random random)
    {
        for (var y = 0; y < map.Height; y++)
        {
            for (var x = 0; x < map.Width; x++)
            {
                var cell = map.GetCell(x, y);
                if (!cell.IsPoiProtected)
                {
                    cell.CellType = random.NextDouble() < fillPercent ? CellType.Wall : CellType.Floor;
                }
            }
        }
    }

    private static void SmoothCaves(MapData map, int iterations)
    {
        for (var iteration = 0; iteration < iterations; iteration++)
        {
            var next = new CellType[map.Height, map.Width];
            for (var y = 0; y < map.Height; y++)
            {
                for (var x = 0; x < map.Width; x++)
                {
                    var cell = map.GetCell(x, y);
                    if (cell.IsPoiProtected)
                    {
                        next[y, x] = cell.CellType;
                        continue;
                    }

                    var wallNeighbors = CountWallNeighbors(map, x, y);
                    next[y, x] = wallNeighbors switch
                    {
                        > 4 => CellType.Wall,
                        < 4 => CellType.Floor,
                        _ => cell.CellType,
                    };
                }
            }

            for (var y = 0; y < map.Height; y++)
            {
                for (var x = 0; x < map.Width; x++)
                {
                    if (!map.GetCell(x, y).IsPoiProtected)
                    {
                        map.GetCell(x, y).CellType = next[y, x];
                    }
                }
            }
        }
    }

    private static int CountWallNeighbors(MapData map, int x, int y)
    {
        var walls = 0;
        for (var offsetY = -1; offsetY <= 1; offsetY++)
        {
            for (var offsetX = -1; offsetX <= 1; offsetX++)
            {
                if (offsetX == 0 && offsetY == 0)
                {
                    continue;
                }

                var neighborX = x + offsetX;
                var neighborY = y + offsetY;
                if (!map.IsInBounds(neighborX, neighborY) || map.GetCell(neighborX, neighborY).CellType == CellType.Wall)
                {
                    walls++;
                }
            }
        }

        return walls;
    }

    private static void DigCorridors(MapData map, MapConfig config, Random random)
    {
        if (config.CorridorCount <= 0)
        {
            return;
        }

        var corridorSteps = Math.Max(
            (int)Math.Round(Math.Max(map.Width, map.Height) * config.CorridorLength, MidpointRounding.AwayFromZero),
            1);
        var radius = Math.Max((int)Math.Floor((config.CorridorWidth - 1) * 0.5), 0);
        for (var corridorIndex = 0; corridorIndex < config.CorridorCount; corridorIndex++)
        {
            var position = new Int2(
                NextInclusive(random, 0, map.Width - 1),
                NextInclusive(random, 0, map.Height - 1));
            var direction = RandomDirection(random);
            for (var step = 0; step < corridorSteps; step++)
            {
                if (!map.IsInBounds(position))
                {
                    break;
                }

                CarveDisc(map, position, radius);
                if (random.NextDouble() < config.CorridorWobble)
                {
                    if (random.NextDouble() < 0.5)
                    {
                        direction = SanitizeDirection(
                            direction + new Int2(NextInclusive(random, -1, 1), NextInclusive(random, -1, 1)),
                            random);
                    }
                    else
                    {
                        var side = NextInclusive(random, -1, 1);
                        position = direction.X == 0
                            ? position with { X = position.X + side }
                            : position with { Y = position.Y + side };
                    }
                }

                position += direction;
                if (position.X <= 0 || position.X >= map.Width - 1 || position.Y <= 0 || position.Y >= map.Height - 1)
                {
                    break;
                }
            }
        }
    }

    private static void CarveDisc(MapData map, Int2 center, int radius)
    {
        for (var y = center.Y - radius; y <= center.Y + radius; y++)
        {
            for (var x = center.X - radius; x <= center.X + radius; x++)
            {
                if (!map.IsInBounds(x, y))
                {
                    continue;
                }

                var dx = x - center.X;
                var dy = y - center.Y;
                if (radius > 0 && dx * dx + dy * dy > radius * radius)
                {
                    continue;
                }

                var cell = map.GetCell(x, y);
                if (!cell.IsPoiProtected)
                {
                    cell.CellType = CellType.Floor;
                }
            }
        }
    }
}
