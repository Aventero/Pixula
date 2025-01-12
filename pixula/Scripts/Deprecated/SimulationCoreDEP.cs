using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Pixula {

[GlobalClass]
public partial class SimulationCore : Node2D
{
    private int[][] currentPixels;
    private int[][] nextPixels;
    private readonly HashSet<Vector2I> movedPixels = new();
    private Dictionary<Vector2I, bool> currentActiveCells = new();
    private readonly Dictionary<Vector2I, bool> nextActiveCells = new();
    
    public enum MaterialType
    {
        Air = 0,
        Sand = 1,
        Water = 2,
        Rock = 3,
        Wall = 4
    }

    private readonly Dictionary<MaterialType, MaterialType[]> SwapRules = new()
    {
        { MaterialType.Air, Array.Empty<MaterialType>() },
        { MaterialType.Sand, new[] { MaterialType.Air, MaterialType.Water } },
        { MaterialType.Water, new[] { MaterialType.Air } },
        { MaterialType.Rock, new[] { MaterialType.Air, MaterialType.Sand, MaterialType.Water } },
        { MaterialType.Wall, Array.Empty<MaterialType>() }
    };

    private const int MaterialBitsStart = 5;
    private const int MaterialBitsMask = 0b1111;
    private const int VariantBitsStart = 13;
    private const int VariantBitsMask = 0b1111111;

    [Export] public int GridWidth { get; private set; }
    [Export] public int GridHeight { get; private set; }
    [Export] public int CellSize { get; private set; } = 5;

    public int PixelSize {get; private set; } = 10;

    private SimulationRenderer renderer;

    public void Initialize(int width, int height, SimulationRenderer renderer)
    {
        this.renderer = renderer;
        GridWidth = width;
        GridHeight = height;
        SetupPixels();
    }

    private void SetupPixels()
    {
        currentPixels = new int[GridHeight][];
        for (int y = 0; y < GridHeight; y++)
        {
            currentPixels[y] = new int[GridWidth];
            for (int x = 0; x < GridWidth; x++)
                SetStateAt(x, y, MaterialType.Air, renderer.GetRandomVariant(MaterialType.Air));
        }
        nextPixels = currentPixels.Select(row => row.ToArray()).ToArray();
    }

    public void SimulateActive()
    {
        // Copy current frame state
        nextPixels = currentPixels.Select(row => row.ToArray()).ToArray();
        currentActiveCells = new Dictionary<Vector2I, bool>(nextActiveCells);
        nextActiveCells.Clear();

        List<Vector2I> pixelsToSimulate = new();
        foreach (Vector2I cell in currentActiveCells.Keys)
        {
            int cellX = cell.X * CellSize;
            int cellY = cell.Y * CellSize;
            for (int x = cellX; x < cellX + CellSize; x++)
            {
                for (int y = cellY; y < cellY + CellSize; y++)
                {
                    if (IsValidPosition(x, y))
                        pixelsToSimulate.Add(new Vector2I(x, y));
                }
            }
        }

        // Randomize to avoid directional bias
        pixelsToSimulate = pixelsToSimulate.OrderBy(_ => Guid.NewGuid()).ToList();
        foreach (var pixelPos in pixelsToSimulate)
        {
            if (Simulate(pixelPos.X, pixelPos.Y))
                ActivateNeighboringCells(pixelPos.X, pixelPos.Y);
        }

        movedPixels.Clear();
        (nextPixels, currentPixels) = (currentPixels, nextPixels);
        renderer.UpdateTexture();
    }

    private bool Simulate(int x, int y)
    {
        var currentMaterial = GetMaterialAt(x, y);

        if (currentMaterial == MaterialType.Air)
            return false;

        if (HasMoved(new Vector2I(x, y)))
            return false;

        return currentMaterial switch
        {
            MaterialType.Sand => SandMechanic(x, y, currentMaterial),
            MaterialType.Water => WaterMechanic(x, y, currentMaterial),
            MaterialType.Rock => MoveDown(x, y, MaterialType.Rock),
            _ => false
        };
    }

    private bool SandMechanic(int x, int y, MaterialType processMaterial)
    {
        return MoveDown(x, y, processMaterial) || MoveDiagonal(x, y, processMaterial);
    }

    private bool WaterMechanic(int x, int y, MaterialType processMaterial)
    {
        return MoveDown(x, y, processMaterial) ||
               MoveDiagonal(x, y, processMaterial) ||
               MoveHorizontal(x, y, processMaterial);
    }

    private bool MoveDown(int x, int y, MaterialType processMaterial)
    {
        if (!IsValidPosition(x, y + 1))
            return false;

        if (CanSwap(processMaterial, GetMaterialAt(x, y + 1)))
        {
            SwapParticle(x, y, x, y + 1);
            return true;
        }

        return false;
    }

    private bool MoveDiagonal(int x, int y, MaterialType processMaterial)
    {
        var direction = (x + y) % 2 == 0 ? new Vector2I(-1, 1) : new Vector2I(1, 1);
        var newPos = new Vector2I(x, y) + direction;

        if (!IsValidPosition(newPos.X, newPos.Y))
            return false;

        if (CanSwap(processMaterial, GetMaterialAt(newPos.X, newPos.Y)))
        {
            SwapParticle(x, y, newPos.X, newPos.Y);
            return true;
        }

        return false;
    }

    private bool MoveHorizontal(int x, int y, MaterialType processMaterial)
    {
        var xDirection = y % 2 == 0 ? 1 : -1;
        var newX = x + xDirection;

        if (!IsValidPosition(newX, y))
            return false;

        if (CanSwap(processMaterial, GetMaterialAt(newX, y)))
        {
            SwapParticle(x, y, newX, y);
            return true;
        }

        return false;
    }

    private void SwapParticle(int sourceX, int sourceY, int destinationX, int destinationY)
    {
        var temp = nextPixels[destinationY][destinationX];
        nextPixels[destinationY][destinationX] = currentPixels[sourceY][sourceX];
        nextPixels[sourceY][sourceX] = temp;

        renderer.DrawPixel(sourceX, sourceY, GetVariant(sourceX, sourceY, nextPixels));
        renderer.DrawPixel(destinationX, destinationY, GetVariant(destinationX, destinationY, nextPixels));

        var source = new Vector2I(sourceX, sourceY);
        var destination = new Vector2I(destinationX, destinationY);

        movedPixels.Add(source);
        movedPixels.Add(destination);

        ActivateCell(source);
        ActivateCell(destination);
    }

    public void SetStateAt(int x, int y, MaterialType materialType, int variant)
    {
        if (!IsValidPosition(x, y))
            return;

        currentPixels[y][x] = (((int)materialType) << MaterialBitsStart) |
                             (variant << VariantBitsStart);
        ActivateCell(new Vector2I(x, y));
        renderer.DrawPixel(x, y, GetVariant(x, y, currentPixels));
    }

    private void ActivateNeighboringCells(int x, int y)
    {
        var cellPos = GetCell(new Vector2I(x, y));
        var posInCell = new Vector2I(x % CellSize, y % CellSize);
        var edgesToActivate = new List<Vector2I>();

        if (posInCell.X == 0)
            edgesToActivate.Add(Vector2I.Left);
        else if (posInCell.X == CellSize - 1)
            edgesToActivate.Add(Vector2I.Right);

        if (posInCell.Y == 0)
            edgesToActivate.Add(Vector2I.Up);
        else if (posInCell.Y == CellSize - 1)
            edgesToActivate.Add(Vector2I.Down);

        foreach (var edge in edgesToActivate)
        {
            var neighbor = cellPos + edge;
            if (IsValidCell(neighbor))
                nextActiveCells[neighbor] = true;
        }
    }

    private void ActivateCell(Vector2I pos)
    {
        var cellPos = GetCell(pos);
        nextActiveCells[cellPos] = true;
    }

    public bool IsValidPosition(int x, int y) =>
        x >= 0 && x < GridWidth && y >= 0 && y < GridHeight;

    private bool IsValidCell(Vector2I cellPos) =>
        cellPos.X >= 0 && cellPos.X < GridWidth/CellSize &&
        cellPos.Y >= 0 && cellPos.Y < GridHeight/CellSize;

    private Vector2I GetCell(Vector2I pos) =>
        new(pos.X / CellSize, pos.Y / CellSize);

    public MaterialType GetMaterialAt(int x, int y) =>
        (MaterialType)((currentPixels[y][x] >> MaterialBitsStart) & MaterialBitsMask);

    private bool HasMoved(Vector2I position) =>
        movedPixels.Contains(position);

    private bool CanSwap(MaterialType source, MaterialType swappingPartner) =>
        SwapRules.TryGetValue(source, out var rules) && rules.Contains(swappingPartner);
    
    static private int GetVariant(int x, int y, int[][] pixelArray)
    {
        return (pixelArray[y][x] >> VariantBitsStart) & VariantBitsMask;
    }

    public void ChangePixelSize(int newPixelSize)
	{
		PixelSize = newPixelSize;

		// Recalculate grid dimensions
        renderer.Initialize(GridWidth, GridHeight, PixelSize);

		// Reset pixel arrays and active cells
		SetupPixels();
		currentActiveCells.Clear();
		nextActiveCells.Clear();
		movedPixels.Clear();
	}

    public void SpawnInRadius(int centerX, int centerY, int radius, MaterialType materialType)
	{
		for (int y = Math.Max(0, centerY - radius); y < Math.Min(GridHeight, centerY + radius + 1); y++)
		{
			for (int x = Math.Max(0, centerX - radius); x < Math.Min(GridWidth, centerX + radius + 1); x++)
			{
				var distance = new Vector2(centerX - x, centerY - y).Length();
				if (distance <= radius)
				{
					SetStateAt(x, y, materialType, renderer.GetRandomVariant(materialType));
					ActivateCell(new Vector2I(x, y));
				}
			}
		}
	}

}
}

