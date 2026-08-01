using System.Text.Json.Nodes;

namespace Wdc.MapGeneration.Tests;

public sealed class MapConfigLoaderTests
{
    [Fact]
    public void LoadDefaultConfigPreservesExistingCatalogValues()
    {
        var path = FixturePaths.Config("default_generated_map.json");
        var source = JsonNode.Parse(File.ReadAllText(path))!.AsObject();

        var config = MapConfigLoader.Load(path);

        Assert.Equal(source["map"]!["width_cells"]!.GetValue<double>(), config.Width);
        Assert.Equal(source["map"]!["height_cells"]!.GetValue<double>(), config.Height);
        Assert.Equal(3, config.MapLayers.Count);
        Assert.NotEmpty(config.MineralClusterTypes);
        Assert.NotEmpty(config.MineralClusterOverrides);
        Assert.NotEmpty(config.PoiTemplates);
        Assert.True(config.PlayerSpawnCount > 0);
        Assert.True(config.ExtractionSiteCount > 0);
    }

    [Fact]
    public void LoadAcceptsIntegralJsonFloatingPointValues()
    {
        var root = JsonNode.Parse("""
            {
              "map": {
                "width_cells": 40.0,
                "height_cells": 32.0,
                "seed": { "mode": "fixed", "fixed_value": 123.0 },
                "player_spawn": { "count": 3.0 }
              },
              "terrain": { "smooth_iterations": 2.0 }
            }
            """)!.AsObject();

        var config = MapConfigLoader.Load(root);

        Assert.Equal(40, config.Width);
        Assert.Equal(32, config.Height);
        Assert.Equal(123, config.Seed);
        Assert.Equal(3, config.PlayerSpawnCount);
        Assert.Equal(2, config.SmoothIterations);
    }

    [Fact]
    public void LoadMissingFileReportsResolvedPath()
    {
        var path = Path.Combine(Path.GetTempPath(), $"wdc-missing-{Guid.NewGuid():N}.json");

        var exception = Assert.Throws<FileNotFoundException>(() => MapConfigLoader.Load(path));

        Assert.Contains(Path.GetFullPath(path), exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("{")]
    [InlineData("[]")]
    public void LoadInvalidDocumentReportsFileContext(string json)
    {
        var path = Path.Combine(Path.GetTempPath(), $"wdc-invalid-{Guid.NewGuid():N}.json");
        try
        {
            File.WriteAllText(path, json);

            var exception = Assert.Throws<InvalidDataException>(() => MapConfigLoader.Load(path));

            Assert.Contains(Path.GetFullPath(path), exception.Message, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            File.Delete(path);
        }
    }
}
