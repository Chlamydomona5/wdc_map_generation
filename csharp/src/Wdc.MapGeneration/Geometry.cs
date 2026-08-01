namespace Wdc.MapGeneration;

public readonly record struct Int2(int X, int Y)
{
    public static Int2 Zero => new(0, 0);
    public static Int2 Right => new(1, 0);
    public static Int2 Left => new(-1, 0);
    public static Int2 Down => new(0, 1);
    public static Int2 Up => new(0, -1);

    public static Int2 operator +(Int2 left, Int2 right) => new(left.X + right.X, left.Y + right.Y);
    public static Int2 operator -(Int2 left, Int2 right) => new(left.X - right.X, left.Y - right.Y);
    public static Int2 operator *(Int2 value, int scalar) => new(value.X * scalar, value.Y * scalar);

    public double DistanceTo(Int2 other) => Math.Sqrt(DistanceSquaredTo(other));

    public long DistanceSquaredTo(Int2 other)
    {
        var dx = (long)X - other.X;
        var dy = (long)Y - other.Y;
        return dx * dx + dy * dy;
    }

    public int ManhattanDistanceTo(Int2 other) => Math.Abs(X - other.X) + Math.Abs(Y - other.Y);
}

public readonly record struct IntRect(Int2 Position, Int2 Size)
{
    public IntRect(int x, int y, int width, int height) : this(new Int2(x, y), new Int2(width, height))
    {
    }

    public static IntRect Empty => new(0, 0, 0, 0);
    public bool IsEmpty => Size.X <= 0 || Size.Y <= 0;
    public int Left => Position.X;
    public int Top => Position.Y;
    public int RightExclusive => Position.X + Size.X;
    public int BottomExclusive => Position.Y + Size.Y;
    public Int2 CenterCell => new(
        Position.X + (int)Math.Floor(Size.X * 0.5),
        Position.Y + (int)Math.Floor(Size.Y * 0.5));

    public bool Contains(Int2 cell) =>
        cell.X >= Left && cell.Y >= Top && cell.X < RightExclusive && cell.Y < BottomExclusive;

    public bool Intersects(IntRect other) =>
        Left < other.RightExclusive && RightExclusive > other.Left &&
        Top < other.BottomExclusive && BottomExclusive > other.Top;

    public IntRect Grow(int margin) => new(
        Position.X - margin,
        Position.Y - margin,
        Size.X + margin * 2,
        Size.Y + margin * 2);
}
