using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using static Pixula.SimulationCore;

namespace Pixula {

[GlobalClass]
public partial class SimulationRenderer : Node2D
{
    [Export] public TextureRect textureRect;
    [Export] public TextureRect debugTextureRect;
    [Export] public Texture2D colorAtlasTexture;

    private Image colorAtlasImage;

    private Image worldImage;
    private ImageTexture worldTexture;
    private Image debugImage;
    private ImageTexture debugTexture;
    
    private readonly Dictionary<MaterialType, int[]> ColorRanges = new()
    {
        { MaterialType.Air, new[] { 36, 38 } },
        { MaterialType.Sand, new[] { 19, 23 } },
        { MaterialType.Water, new[] { 1, 5 } },
        { MaterialType.Rock, new[] { 12, 16 } },
        { MaterialType.Wall, new[] { 40, 44 } }
    };

    public override void _Ready()
    {
        colorAtlasImage = colorAtlasTexture.GetImage();
    }

    public void Initialize(int width, int height, int pixelSize)
    {
        // Main world rendering setup
        worldImage = Image.CreateEmpty(width, height, false, Image.Format.Rgba8);
        worldImage.Fill(Colors.Transparent);
        worldTexture = ImageTexture.CreateFromImage(worldImage);
        textureRect.Texture = worldTexture;
        textureRect.CustomMinimumSize = new Vector2(width * pixelSize, height * pixelSize);

        // Debug rendering setup
        debugImage = Image.CreateEmpty(width * pixelSize, height * pixelSize, false, Image.Format.Rgba8);
        debugImage.Fill(Colors.Transparent);
        debugTexture = ImageTexture.CreateFromImage(debugImage);
        debugTextureRect.Texture = debugTexture;
    }

    public void DrawPixel(int x, int y, int variant)
    {
        Color color = GetColorForVariant(variant);
        worldImage.SetPixel(x, y, color);
    }

    public void UpdateTexture()
    {
        worldTexture.Update(worldImage);
    }

    private Color GetColorForVariant(int variant)
    {
        return colorAtlasImage.GetPixel(variant, 0);
    }

    public int GetRandomVariant(MaterialType materialType)
    {
        var variants = ColorRanges[materialType];
        return GD.RandRange(variants[0], variants[1]);
    }


    public void DrawActiveCells(Dictionary<Vector2I, bool> cells, int cellSize, int pixelSize)
    {
        debugImage.Fill(Colors.Transparent);
        var red = new Color(Colors.Red, 1);
        
        foreach (var pos in cells.Keys)
        {
            DrawDebugCell(pos, red, cellSize, pixelSize);
        }
        
        debugTexture.Update(debugImage);
    }

    public void DrawSpawnPreview(int centerX, int centerY, int radius, int pixelSize, int gridWidth, int gridHeight)
    {
        int startX = Math.Max(0, centerX - radius);
        int startY = Math.Max(0, centerY - radius);
        int endX = Math.Min(gridWidth, centerX + radius + 1);
        int endY = Math.Min(gridHeight, centerY + radius + 1);

        for (int y = startY; y < endY; y++)
        {
            for (int x = startX; x < endX; x++)
            {
                float distance = new Vector2I(centerX, centerY).DistanceTo(new Vector2I(x, y));

                if (distance <= radius)
                    DrawDebugRect(new Vector2I(x, y), new Color(Colors.White, 0.3f), pixelSize);
            }
        }

        DrawDebugRect(new Vector2I(centerX, centerY), new Color(Colors.White, 0.9f), pixelSize);
        debugTexture.Update(debugImage);
    }

    private void DrawDebugCell(Vector2I cellPos, Color color, int cellSize, int pixelSize)
    {
        Vector2I pixelDrawPos = cellPos * cellSize * pixelSize;
        int cellDrawSize = cellSize * pixelSize;
        Rect2I rect = new(pixelDrawPos, new Vector2I(cellDrawSize, cellDrawSize));
        DrawRectOutline(rect, color);
    }

    private void DrawDebugRect(Vector2I pos, Color color, int pixelSize)
    {
        var rect = new Rect2I(pos * pixelSize, new Vector2I(pixelSize, pixelSize));
        rect = rect.Intersection(new Rect2I(0, 0, debugImage.GetWidth(), debugImage.GetHeight()));
        debugImage.FillRect(rect, color);
    }

    private void DrawRectOutline(Rect2I rect, Color color)
    {
        Rect2I r = rect.Intersection(new Rect2I(0, 0, debugImage.GetWidth(), debugImage.GetHeight()));

        for (int x = r.Position.X; x < r.Position.X + r.Size.X; x++)
        {
            debugImage.SetPixel(x, r.Position.Y, color);
            debugImage.SetPixel(x, r.Position.Y + r.Size.Y - 1, color);
        }

        for (int y = r.Position.Y; y < r.Position.Y + r.Size.Y; y++)
        {
            debugImage.SetPixel(r.Position.X, y, color);
            debugImage.SetPixel(r.Position.X + r.Size.X - 1, y, color);
        }
    }
    
    private void PrintSomething(string text) 
    {
        GD.Print(text);
    }
}
}