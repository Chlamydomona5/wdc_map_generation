using System.Security.Cryptography;

namespace Wdc.MapGeneration;

public sealed partial class MapGenerator
{
    private static readonly Int2[] CardinalDirections = [Int2.Left, Int2.Right, Int2.Up, Int2.Down];

    public int LastResolvedSeed { get; private set; }

    public MapData Generate(MapConfig config)
    {
        ArgumentNullException.ThrowIfNull(config);
        config.Normalize();
        LastResolvedSeed = ResolveSeed(config.Seed);
        var random = new Random(LastResolvedSeed);
        var map = new MapData(config.Width, config.Height, LastResolvedSeed);

        FillNoise(map, config.FillPercent, random);
        SmoothCaves(map, config.SmoothIterations);
        DigCorridors(map, config, random);
        GenerateMinerals(map, config, random);
        PlaceAllPois(map, config, random);
        GenerateTraces(map, config, random);
        GeneratePoiSpecialBlocks(map, config, random);
        GenerateEnvironmentalTraps(map, config, random);
        ApplyLayerDurabilityOverrides(map, config);
        GenerateSpawnAndExtractionSites(map, config);
        RecalculateStats(map);
        return map;
    }

    private static int ResolveSeed(int inputSeed) =>
        inputSeed != 0 ? inputSeed : RandomNumberGenerator.GetInt32(1, int.MaxValue);

    private static int NextInclusive(Random random, int minimum, int maximum)
    {
        if (minimum > maximum)
        {
            throw new ArgumentOutOfRangeException(nameof(minimum));
        }

        return random.NextInt64(minimum, (long)maximum + 1) is var value ? checked((int)value) : minimum;
    }

    private static void Shuffle<T>(IList<T> values, Random random)
    {
        for (var index = values.Count - 1; index > 0; index--)
        {
            var swapIndex = NextInclusive(random, 0, index);
            (values[index], values[swapIndex]) = (values[swapIndex], values[index]);
        }
    }

    private static Int2 RandomDirection(Random random) =>
        SanitizeDirection(new Int2(NextInclusive(random, -1, 1), NextInclusive(random, -1, 1)), random);

    private static Int2 SanitizeDirection(Int2 direction, Random random)
    {
        var x = Math.Sign(direction.X);
        var y = Math.Sign(direction.Y);
        if (x == 0 && y == 0)
        {
            if (random.NextDouble() < 0.5)
            {
                x = random.NextDouble() < 0.5 ? 1 : -1;
            }
            else
            {
                y = random.NextDouble() < 0.5 ? 1 : -1;
            }
        }

        return new Int2(x, y);
    }
}
