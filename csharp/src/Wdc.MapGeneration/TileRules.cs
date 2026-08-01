namespace Wdc.MapGeneration;

public static class TileRules
{
    public static int GetTileMaxHitPoints(ServerTileType tileType) => tileType switch
    {
        ServerTileType.MineralWall => 2,
        ServerTileType.RareMineralWall => 3,
        ServerTileType.TurquoiseOre => 3,
        ServerTileType.AmethystOre => 4,
        ServerTileType.GoldBlock => 5,
        ServerTileType.PoiWall => 2,
        ServerTileType.SpikeTile => 2,
        ServerTileType.ExplosiveOreTile => 2,
        ServerTileType.ArrowSlitTile => 1,
        ServerTileType.PressurePlateTile => 1,
        ServerTileType.Empty => 0,
        _ => 1,
    };

    public static ServerTileType EncodeServerTile(CellData? cell)
    {
        if (cell is null)
        {
            return ServerTileType.Wall;
        }

        if (cell.CellType == CellType.Floor)
        {
            return cell.SpecialBlockType switch
            {
                SpecialBlockType.Spike => ServerTileType.SpikeTile,
                SpecialBlockType.PressurePlate => ServerTileType.PressurePlateTile,
                _ => ServerTileType.Empty,
            };
        }

        return cell.SpecialBlockType switch
        {
            SpecialBlockType.RareMineral => ServerTileType.RareMineralWall,
            SpecialBlockType.Turquoise => ServerTileType.TurquoiseOre,
            SpecialBlockType.Amethyst => ServerTileType.AmethystOre,
            SpecialBlockType.Gold => ServerTileType.GoldBlock,
            SpecialBlockType.PoiWall => ServerTileType.PoiWall,
            SpecialBlockType.ExplosiveOre => ServerTileType.ExplosiveOreTile,
            SpecialBlockType.ArrowSlit => ServerTileType.ArrowSlitTile,
            _ => cell.HasMineral ? ServerTileType.MineralWall : ServerTileType.Wall,
        };
    }

    public static void RefreshCellRuntimeState(CellData cell)
    {
        var tileType = EncodeServerTile(cell);
        var maxHitPoints = UsesLayerDurability(tileType) && cell.DurabilityOverrideMaxHitPoints > 0
            ? cell.DurabilityOverrideMaxHitPoints
            : GetTileMaxHitPoints(tileType);
        cell.MaxHitPoints = maxHitPoints;
        if (maxHitPoints <= 0)
        {
            cell.CurrentHitPoints = 0;
        }
        else if (cell.DurabilityTileType != tileType)
        {
            cell.CurrentHitPoints = maxHitPoints;
        }
        else
        {
            cell.CurrentHitPoints = Math.Clamp(cell.CurrentHitPoints, 1, maxHitPoints);
        }

        cell.DurabilityTileType = tileType;
    }

    public static bool UsesLayerDurability(ServerTileType tileType) => tileType is
        ServerTileType.Wall or
        ServerTileType.MineralWall or
        ServerTileType.RareMineralWall or
        ServerTileType.TurquoiseOre or
        ServerTileType.AmethystOre or
        ServerTileType.GoldBlock;
}
