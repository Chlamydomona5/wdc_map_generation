namespace Wdc.MapGeneration.Tests;

public sealed class TileRulesTests
{
    public static TheoryData<CellData, ServerTileType> Encodings => new()
    {
        { new CellData { CellType = CellType.Floor }, ServerTileType.Empty },
        { new CellData { CellType = CellType.Wall }, ServerTileType.Wall },
        { new CellData { CellType = CellType.Wall, HasMineral = true }, ServerTileType.MineralWall },
        { Wall(SpecialBlockType.RareMineral), ServerTileType.RareMineralWall },
        { Wall(SpecialBlockType.Turquoise), ServerTileType.TurquoiseOre },
        { Wall(SpecialBlockType.Amethyst), ServerTileType.AmethystOre },
        { Wall(SpecialBlockType.Gold), ServerTileType.GoldBlock },
        { Wall(SpecialBlockType.PoiWall), ServerTileType.PoiWall },
        { Floor(SpecialBlockType.Spike), ServerTileType.SpikeTile },
        { Wall(SpecialBlockType.ExplosiveOre), ServerTileType.ExplosiveOreTile },
        { Wall(SpecialBlockType.ArrowSlit), ServerTileType.ArrowSlitTile },
        { Floor(SpecialBlockType.PressurePlate), ServerTileType.PressurePlateTile },
    };

    [Theory]
    [MemberData(nameof(Encodings))]
    public void EncodeServerTileCoversEveryStableTileType(CellData cell, ServerTileType expected)
    {
        Assert.Equal(expected, TileRules.EncodeServerTile(cell));
    }

    [Fact]
    public void TileMatrixUsesHeightThenWidthAndStableEnumValues()
    {
        var map = new MapData(2, 1, 1);
        map.GetCell(0, 0).CellType = CellType.Floor;
        map.GetCell(1, 0).SpecialBlockType = SpecialBlockType.Gold;

        var matrix = map.ToTileMatrix();

        Assert.Single(matrix);
        Assert.Equal(2, matrix[0].Length);
        Assert.Equal(ServerTileType.Empty, matrix[0][0]);
        Assert.Equal(ServerTileType.GoldBlock, matrix[0][1]);
        Assert.Equal(0, (int)ServerTileType.Empty);
        Assert.Equal(11, (int)ServerTileType.PressurePlateTile);
    }

    private static CellData Wall(SpecialBlockType type) => new() { CellType = CellType.Wall, SpecialBlockType = type };
    private static CellData Floor(SpecialBlockType type) => new() { CellType = CellType.Floor, SpecialBlockType = type };
}
