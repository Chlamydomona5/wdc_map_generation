namespace Wdc.MapGeneration.Tests;

internal static class FixturePaths
{
    public static string Config(string fileName)
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            var path = Path.Combine(
                directory.FullName,
                "addons",
                "wdc_map_generation",
                "config",
                "generated_map_configs",
                fileName);
            if (File.Exists(path))
            {
                return path;
            }
        }

        throw new FileNotFoundException($"无法定位地图配置 fixture: {fileName}");
    }
}
