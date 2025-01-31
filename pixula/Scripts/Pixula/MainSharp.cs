using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Pixula.Mechanics;

namespace Pixula {

public struct Pixel(MaterialType material, Vector2I variantPos, int various)
{
	public MaterialType material = material;
	public Vector2I variantPos = variantPos;
	public int various = various;
}

public enum MaterialType
{
	Air = 0,
	Sand = 1,
	Water = 2,
	Rock = 3,
	Wall = 4,
	Wood = 5,
	Fire = 6,
	WaterVapor = 7,
	WaterCloud = 8,
	Lava = 9,
	Acid = 10,
	AcidVapor = 11,
	AcidCloud = 12,
	Void = 13,
	Mimic = 14,
	Seed = 15,
	Plant = 16,
	Poison = 17,
	Fluff = 18,
	Ember = 19,

	// Seed -> Grows when on top of soil 
	// Seed -> ALSO grows wood under it
	// Seed -> Can absorb water
	// Poison -> Eats through things turning them into highly flammable fluff
	// FLUFF -> Very flammable stuff
	// Coal? -> Burns for long
	// EMBER -> Hot Coal basically, can put stuff on fire
}


[GlobalClass]
public partial class MainSharp : Node2D
{
	// External nodes
	[Export] public Texture2D colorAtlas;
	private Image colorAtlasImage;

	[Export] public TextureRect worldTextureRect;
	private Image worldImage;
	private ImageTexture worldTexture;

	[Export] public TextureRect debugTextureRect;
	private Image debugImage;
	private ImageTexture debugTexture;

	// Pixel State
	public Pixel[] CurrentPixels;
	public Pixel[] NextPixels;

	// Simulation
	[Export] public bool EnableDebug { get; set; } = false;
	public int CellSize { get; set; } = 3;

	// Window
	private int width { get; set; } = 1600;
	private int height { get; set; } = 900;
	private int gridWidth;
	private int gridHeight;

	// Grid cells
	public int SpawnRadius { get; set; } = 3;
	public int PixelSize { get; set; } = 20;
	private Dictionary<Vector2I, bool> currentActiveCells = [];
	private Dictionary<Vector2I, bool> nextActiveCells = [];
	private HashSet<Vector2I> processedPositions = [];
	private Dictionary<Vector2I, Color> positionColors = new();
	private bool shouldAttract;
	private Vector2I attractPosition;
	public Vector2I MousePosition {get; set; }


	// Array depicts the start in the color map and how far
	// -> Color pos + width (normally 1 as it only needs one column)
	private readonly Dictionary<MaterialType, int[]> ColorRanges = new()
	{
		{ MaterialType.Air, new[] { 36, 0 } },
		{ MaterialType.Sand, new[] { 22, 1 } },
		{ MaterialType.Water, new[] { 2, 1 } },
		{ MaterialType.Rock, new[] { 18, 0 } },
		{ MaterialType.Wall, new[] { 38, 0 } },
		{ MaterialType.Wood, new[] { 12, 1} },
		{ MaterialType.Fire, new[] { 27, 1} },
		{ MaterialType.WaterVapor, new[] { 44, 1} },
		{ MaterialType.WaterCloud, new[] { 1, 0} },
		{ MaterialType.Lava, new[] { 25, 1} },
		{ MaterialType.Acid, new[] { 9, 1} },
		{ MaterialType.AcidVapor, new[] { 10, 0} },
		{ MaterialType.AcidCloud, new[] { 6, 0} },
		{ MaterialType.Void, new[] { 30, 0} },
		{ MaterialType.Mimic, new[] { 31, 0} },
		{ MaterialType.Seed, new[] { 14, 0} },
		{ MaterialType.Plant, new[] { 7, 1} },
		{ MaterialType.Poison, new[] { 33, 0} },
		{ MaterialType.Fluff, new[] { 15, 0} },
		{ MaterialType.Ember, new[] { 27, 0} },
	};

	private readonly Dictionary<MaterialType, Mechanics.MaterialMechanic> mechanics;


	private readonly Dictionary<MaterialType, MaterialType[]> SwapRules = new()
	{
		{ MaterialType.Sand, new[] { MaterialType.Air, MaterialType.Water, MaterialType.WaterVapor, MaterialType.WaterCloud, MaterialType.Lava, MaterialType.Acid, MaterialType.AcidVapor, MaterialType.AcidCloud} },
		{ MaterialType.Water, new[] { MaterialType.Air, MaterialType.WaterVapor, MaterialType.WaterCloud, MaterialType.Acid, MaterialType.AcidVapor, MaterialType.AcidCloud } },
		{ MaterialType.Rock, new[] { MaterialType.Air, MaterialType.Sand, MaterialType.Water, MaterialType.WaterVapor, MaterialType.WaterCloud, MaterialType.Fire, MaterialType.Acid, MaterialType.AcidVapor, MaterialType.AcidCloud, MaterialType.Lava } },
		{ MaterialType.Fire, new[] { MaterialType.Air, MaterialType.WaterVapor, MaterialType.WaterCloud, MaterialType.AcidVapor, MaterialType.AcidCloud } },
		{ MaterialType.WaterVapor, new[] { MaterialType.Air } },
		{ MaterialType.WaterCloud, new[] { MaterialType.Air }},
		{ MaterialType.Lava, new[] { MaterialType.Air, MaterialType.WaterVapor, MaterialType.WaterCloud, MaterialType.Acid, MaterialType.AcidVapor, MaterialType.AcidCloud}},
		{ MaterialType.Acid, new[] { MaterialType.Air, MaterialType.AcidVapor, MaterialType.WaterVapor }},
		{ MaterialType.AcidVapor, new[] { MaterialType.Air }},
		{ MaterialType.AcidCloud, new[] { MaterialType.Air }},
		{ MaterialType.Seed, new[] { MaterialType.Air, MaterialType.Water, MaterialType.Lava, MaterialType.Acid }},
		{ MaterialType.Plant, new[] { MaterialType.Air }},
	};

	private readonly Dictionary<MaterialType, float> FluidViscosity = new()
	{
		{ MaterialType.Water, 0.1f},
		{ MaterialType.Lava, 0.01f},
		{ MaterialType.Acid, 0.02f},
	};

	private readonly Dictionary<MaterialType, float> SolidWeight = new()
	{
		{ MaterialType.Sand, 1.0f},
		{ MaterialType.Rock, 4.0f},
		{ MaterialType.Seed, 1.5f},
		{ MaterialType.Wall, 0},
		{ MaterialType.Wood, 0},
	};

	public enum MaterialState
	{
		Solid,
		Liquid,
		Gas
	}

	private MaterialState GetMaterialState(MaterialType material)
	{
		return material switch
		{
			MaterialType.Sand => MaterialState.Solid,
			MaterialType.Rock => MaterialState.Solid,
			MaterialType.Wall => MaterialState.Solid,
			MaterialType.Wood => MaterialState.Solid,
			MaterialType.Seed => MaterialState.Solid,
			MaterialType.Mimic => MaterialState.Solid,
			MaterialType.Void => MaterialState.Solid,
			
			MaterialType.Water => MaterialState.Liquid,
			MaterialType.Lava => MaterialState.Liquid,
			MaterialType.Acid => MaterialState.Liquid,
			
			MaterialType.WaterVapor => MaterialState.Gas, 
			MaterialType.WaterCloud => MaterialState.Gas,
			MaterialType.AcidVapor => MaterialState.Gas,
			MaterialType.AcidCloud => MaterialState.Gas,
			MaterialType.Fire => MaterialState.Gas,
			
			_ => MaterialState.Solid
		};
	}

	private static bool IsFlammable(MaterialType processMaterial) 
	{
		return processMaterial switch
		{
			MaterialType.Wood => true,
			MaterialType.Seed => true,
			_ => false
		};
	}

	public static bool IsDissolvable(MaterialType processMaterial) 
	{
		return processMaterial switch
		{
			MaterialType.Acid => false,
			MaterialType.Water => false,
			MaterialType.Lava => false,
			MaterialType.Air => false,
			MaterialType.Wall => false,
			MaterialType.Mimic => false,
			MaterialType.Void => false,
			_ => true
		};
	}

	public readonly Vector2I[] Directions = {
		new(-1, 1),
		new(0, 1),
		new(1, 1),
		new(1, 0),
		new(1, -1),
		new(0, -1),
		new(-1, -1),
		new(-1, 0),
	};

	public MainSharp()
	{
		mechanics = new() 
		{
			{ MaterialType.Sand, new Sand(this) },
			{ MaterialType.Water, new Water(this) },
			{ MaterialType.Rock, new Rock(this) },
			{ MaterialType.Fire, new Fire(this) },
			{ MaterialType.WaterVapor, new Vapor(this) },
			{ MaterialType.WaterCloud, new Cloud(this) },
			{ MaterialType.Lava, new Lava(this) },
			{ MaterialType.Wood, new Wood(this) },
			{ MaterialType.Acid, new Acid(this) },
			{ MaterialType.AcidVapor, new AcidVapor(this) },
			{ MaterialType.AcidCloud, new AcidCloud(this) },
			{ MaterialType.Mimic, new Mimic(this) },
			{ MaterialType.Void, new Mechanics.Void(this) },
			{ MaterialType.Seed, new Seed(this) },
			{ MaterialType.Plant, new Plant(this) },
		};
	}

	public void Initialize(int width, int height, int pixelSize, int cellSize, int spawnRadius)
	{
		this.CellSize = cellSize;
		this.SpawnRadius = spawnRadius;
		colorAtlasImage = colorAtlas.GetImage();
		
		ChangeSize(pixelSize, width, height, width/pixelSize, height/pixelSize);
		DrawWorld();
	}

	private bool SimulateMaterialAt(int x, int y)
	{
		MaterialType currentMaterial = GetMaterialAt(x, y);

		if (currentMaterial == MaterialType.Air)
			return false;

		if (processedPositions.Contains(new Vector2I(x, y)))
			return false;

		return mechanics.TryGetValue(currentMaterial, out MaterialMechanic mechanic) && mechanic.Update(x, y, currentMaterial);
	}

	
	public void Simulate()
	{
		SimulateActive();
		GetWindow().Title = Engine.GetFramesPerSecond().ToString();
	}

    private void SimulateActive()
	{
		processedPositions.Clear();
		Array.Copy(CurrentPixels, NextPixels, CurrentPixels.Length);
		currentActiveCells = new Dictionary<Vector2I, bool>(nextActiveCells);
		nextActiveCells.Clear();

		List<Vector2I> pixelsToSimulate = [];
		foreach (Vector2I cell in currentActiveCells.Keys)
		{
			int cellX = cell.X * CellSize;
			int cellY = cell.Y * CellSize;
			for (int y = cellY; y < cellY + CellSize; y++)
			{
				for (int x = cellX; x < cellX + CellSize; x++)
				{
					if (IsInBounds(x, y))
						pixelsToSimulate.Add(new Vector2I(x, y));
				}
			}
		}

		// Randomize to avoid directional bias
		pixelsToSimulate = pixelsToSimulate.OrderBy(_ => Guid.NewGuid()).ToList();

		if (shouldAttract)
		{
			AttractToCursor(attractPosition);
			shouldAttract = false;
		}

		// Simulate
		foreach (var pixelPos in pixelsToSimulate)
		{
			if (SimulateMaterialAt(pixelPos.X, pixelPos.Y))
				ActivateNeighboringCells(pixelPos.X, pixelPos.Y);
		}

		// Cool swap.
		(NextPixels, CurrentPixels) = (CurrentPixels, NextPixels);
	}

	public void DrawWorld()
	{
		foreach (var positionColor in positionColors)
			worldImage.SetPixel(positionColor.Key.X, positionColor.Key.Y, positionColor.Value);

		worldTexture.Update(worldImage);
		positionColors.Clear();
	}

	public void DrawDebug()
	{
		debugImage.Fill(Colors.Transparent);
		DrawSpawnRadiusPreview(MousePosition.X, MousePosition.Y, SpawnRadius);
		if (EnableDebug) 
			DebugDrawActiveCells();
		debugTexture.Update(debugImage);
	}

	public void RequestAttraction(Vector2I mousePos)
	{
		shouldAttract = true;
		attractPosition = mousePos;
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

		if (edgesToActivate.Count == 2)
		{
			var diagonal = edgesToActivate[0] + edgesToActivate[1];
			var neighbor = cellPos + diagonal;
			if (IsValidCell(neighbor))
				nextActiveCells[neighbor] = true;
		}
	}

	private static Vector2I GetRandomRingPosition(int centerX, int centerY, int minDist, int maxDist) 
	{
		// 360° Degrees around the pixel are possible 
		// 0 - 1 * 2PI 
		double radians = Random.Shared.NextSingle() * Math.PI * 2;

		// 0 - 1 * (area) + offset
		double distance = Random.Shared.NextSingle() * (maxDist - minDist) + minDist;

		int x = centerX + (int)(Math.Cos(radians) * distance);
		int y = centerY + (int)(Math.Sin(radians) * distance);

		return new Vector2I(x, y);
	}

	public bool AttractTowardsMaterial(int x, int y, int rangeMin, int rangeMax, MaterialType materialType)
	{
		Vector2I pos = GetRandomRingPosition(x, y, rangeMin, rangeMax);
		if (IsInBounds(pos.X, pos.Y) && GetMaterialAt(pos.X, pos.Y) == materialType)
		{
			Vector2I direction = new(Math.Sign(pos.X - x), Math.Sign(pos.Y -y));
			return MoveTo(x, y, x + direction.X, y + direction.Y, materialType);
		}

		return false;
	}

	public void AttractToCursor(Vector2I mousePos) 
	{
		for (int y = Math.Max(0, mousePos.Y - SpawnRadius); y < Math.Min(gridHeight, mousePos.Y + SpawnRadius + 1); y++)
		{
			for (int x = Math.Max(0, mousePos.X - SpawnRadius); x < Math.Min(gridWidth, mousePos.X + SpawnRadius + 1); x++)
			{
				float distance = new Vector2I(mousePos.X - x, mousePos.Y - y).Length();
				
				if (distance < SpawnRadius)
				{
					MaterialType material = GetMaterialAt(x, y);
					
					if (material == MaterialType.Air || material == MaterialType.Wall)
						continue;
					
					// Calculate strength based on distance
					int moveStrength = Math.Min(2, (int)(distance / 2));
					if (MaterialMechanic.Chance(0.4f))
					{
						// Move toward cursor
						Vector2I direction = new(Math.Sign(mousePos.X - x), Math.Sign(mousePos.Y - y));
						MoveTo(x, y, x + direction.X * moveStrength, y + direction.Y * moveStrength, material);
						continue;
					}

					// angle to cursor
					float angle = (float)Math.Atan2(mousePos.Y - y, mousePos.X - x);
					
					// Add 90° (π/2)
					angle += MathF.PI / 2f;
					Vector2I rotateDirection = new(
						(int)Math.Round(Math.Cos(angle)),
						(int)Math.Round(Math.Sin(angle))
					);

					MoveTo(x, y, x + rotateDirection.X * moveStrength, y + rotateDirection.Y * moveStrength, material);
				}
			}
		}
	}

	public bool FormCloud(int x, int y, MaterialType vaporType, MaterialType cloudType) 
	{
		// Random chance to not form a cloud
		if (Random.Shared.NextSingle() > (0.015f * (1 - y / (float)gridHeight)))
			return false;

		int vaporCount = 0;
		foreach (Vector2I direction in Directions) 
		{
			var checkX = x + direction.X;
			var checkY = y + direction.Y;
			if (!IsInBounds(checkX, checkY))
				continue;

			if (GetMaterialAt(checkX, checkY) == vaporType)
				vaporCount++;
		}

		// Make me a CLOUD
		if (vaporCount >= 4) 
		{
			ConvertTo(x, y, cloudType);
			return true;
		}

		return false;
	}

	public void SpreadFire(int x, int y)
	{
		foreach (Vector2I direction in Directions) 
		{
			int checkX = x + direction.X;
			int checkY = y + direction.Y;
			if (!IsInBounds(checkX, checkY))
				continue;
			MaterialType material = GetMaterialAt(checkX, checkY);

			// 5% chance to burn something!
			if (IsFlammable(material) && MaterialMechanic.Chance(0.07f)) 
				ConvertTo(checkX, checkY, MaterialType.Fire);
		}
	}

	public bool MoveTo(int x, int y, int newX, int newY, MaterialType processMaterial) 
	{
		Vector2I source = new(x, y);
		Vector2I destination = new(newX, newY);

		if (!IsInBounds(newX, newY))
			return false;

		MaterialType targetMaterial = GetMaterialAt(newX, newY);
		if (!CanSwap(processMaterial, targetMaterial))
			return false;

		if (GetMaterialState(processMaterial) == MaterialState.Solid && GetMaterialState(targetMaterial) == MaterialState.Liquid)
		{
			// Wait if a solid is being swapped with a liquid based on the weight and viscosity
			// The multiplied value should be low (0.5 or lower)
			ActivateCell(new Vector2I(x, y));
			if (Random.Shared.NextSingle() > Mathf.Min(SolidWeight[processMaterial] * FluidViscosity[targetMaterial], 1))
				return false;
		}

		SwapParticle(x, y, newX, newY);
		DrawPixelAt(x, y, NextPixels);
		DrawPixelAt(newX, newY, NextPixels);

		processedPositions.Add(source);
		processedPositions.Add(destination);

		ActivateCell(source);
		ActivateCell(destination);

		return true;
	}

	private static Color GetColorRevamp(MaterialType currentMaterial, Color materialColor)
	{
		return currentMaterial switch
		{
			MaterialType.Fire => new Color(
				materialColor.R * 6.5f,  
				materialColor.G * 1.5f, 
				materialColor.B * 1.3f,  
				materialColor.A
			),
			MaterialType.Lava => new Color(
				materialColor.R * 12.0f,
				materialColor.G * 1.5f,
				materialColor.B * 1.2f,
				materialColor.A
			),
			MaterialType.Acid => new Color(
				materialColor.R * 1.0f,
				materialColor.G * 3.15f,
				materialColor.B * 1.0f,
				materialColor.A
			),
			MaterialType.AcidVapor => new Color(
				materialColor.R,
				materialColor.G,
				materialColor.B,
				materialColor.A * 0.5f
			),
			MaterialType.WaterVapor => new Color(
				materialColor.R,
				materialColor.G,
				materialColor.B,
				materialColor.A * 0.5f
			),
			_ => materialColor
		};
	}

	private void DrawPixelAt(int x, int y, Pixel[] pixelArray)
	{
		Vector2I variantPos = GetPixel(x, y, pixelArray).variantPos;
		MaterialType materialType = GetNewMaterialAt(x, y);
		Color color = GetColorForVariant(variantPos.X, variantPos.Y);
		color = GetColorRevamp(materialType, color);
		positionColors[new Vector2I(x, y)] =  color;
	}

	public void DrawSpawnRadiusPreview(int centerX, int centerY, int radius)
	{
		if (radius <= 1) return;

		int startX = Math.Max(0, centerX - radius);
		int startY = Math.Max(0, centerY - radius);
		int endX = Math.Min(gridWidth, centerX + radius + 1);
		int endY = Math.Min(gridHeight, centerY + radius + 1);

		for (int y = startY; y < endY; y++)
		{
			for (int x = startX; x < endX; x++)
			{
				float distance = new Vector2I(centerX, centerY).DistanceTo(new Vector2I(x, y));

				if (distance < radius)
					DrawRectFilled(new Vector2I(x, y), new Color(Colors.White, 0.1f));
			}
		}
	}

	private Color GetColorForVariant(int atlasX, int atlasY)
	{
		Color color = colorAtlasImage.GetPixel(atlasX, atlasY);
		return color.SrgbToLinear(); // THIS IS VERY IMPORTANT FOR HDR.
	}

	public void ChangeSize(int newPixelSize, int width, int height, int gridWidth, int gridHeight)
	{
		PixelSize = newPixelSize;
		this.width = width;
		this.height = height;
		this.gridWidth = (int)Math.Floor((float)width / newPixelSize);
		this.gridHeight = (int)Math.Floor((float)height / newPixelSize);

		// Reset pixel arrays and active cells
		SetupImages();
		SetupDebug();
		SetupPixels();
		currentActiveCells.Clear();
		nextActiveCells.Clear();

		// Update UI size
		worldTextureRect.CustomMinimumSize = new Vector2(width, height);
	}

	private void SwapParticle(int sourceX, int sourceY, int destinationX, int destinationY)
	{
		Pixel temp = GetPixel(destinationX, destinationY, NextPixels);
		SetPixel(destinationX, destinationY, GetPixel(sourceX, sourceY, CurrentPixels), NextPixels);
		SetPixel(sourceX, sourceY, temp, NextPixels);
	}

	public void ConvertTo(int x, int y, MaterialType materialType) 
	{
		SetMaterialAt(x, y, materialType, NextPixels);
	}

	public void SpawnInRadius(int centerX, int centerY, int radius, MaterialType materialType)
	{
		for (int y = Math.Max(0, centerY - radius); y < Math.Min(gridHeight, centerY + radius + 1); y++)
		{
			for (int x = Math.Max(0, centerX - radius); x < Math.Min(gridWidth, centerX + radius + 1); x++)
			{
				var distance = new Vector2(centerX - x, centerY - y).Length();
				if (distance < radius)
				{
					SetMaterialAt(x, y, materialType, CurrentPixels);
					SetMaterialAt(x, y, materialType, NextPixels);
					ActivateCell(new Vector2I(x, y));
				}
			}
		}
	}

	// Helper methods
	public bool IsInBounds(int x, int y) =>
		x >= 0 && x < gridWidth && y >= 0 && y < gridHeight;

	private bool IsValidCell(Vector2I cellPos)
	{
		int maxCellX = (gridWidth - 1) / CellSize;
		int maxCellY = (gridHeight - 1) / CellSize;
		return cellPos.X >= 0 && cellPos.X <= maxCellX &&
			cellPos.Y >= 0 && cellPos.Y <= maxCellY;
	}

	private Vector2I GetCell(Vector2I pos) =>
		new(pos.X / CellSize, pos.Y / CellSize);

	public void ActivateCell(Vector2I pos)
	{
		var cellPos = GetCell(pos);
		nextActiveCells[cellPos] = true;
	}

	public MaterialType GetMaterialAt(int x, int y) 
	{
		return GetPixel(x, y, CurrentPixels).material;
	}

	private MaterialType GetNewMaterialAt(int x, int y) => GetPixel(x, y, NextPixels).material;

	private bool CanSwap(MaterialType source, MaterialType swappingPartner) =>
		SwapRules.TryGetValue(source, out var rules) && rules.Contains(swappingPartner);

	private void SetupPixels()
	{
		// Initialize coloum
		CurrentPixels = new Pixel[gridHeight * gridWidth];
		NextPixels = new Pixel[gridHeight * gridWidth]; 

		for (int y = 0; y < gridHeight; y++)
		{
			for (int x = 0; x < gridWidth; x++)
			{
				SetMaterialAt(x, y, MaterialType.Air, CurrentPixels);
				SetMaterialAt(x, y, MaterialType.Air, NextPixels);
			}
		}
	}

	private Vector2I GetRandomVariant(MaterialType materialType)
	{
		int start = ColorRanges[materialType][0];
		int stride = ColorRanges[materialType][1];
		return new Vector2I(GD.RandRange(start, start + stride), GD.RandRange(0, 1));
	}

	public Color GetColorAt(int x, int y)
	{
		if (!IsInBounds(x, y))
			return Colors.Transparent;
			
		return worldImage.GetPixel(x, y);
	}

	public void SetMaterialAt(int x, int y, MaterialType materialType, Pixel[] pixelArray)
	{
		if (!IsInBounds(x, y))
			return;
		
		SetPixel(x, y, new Pixel(materialType, GetRandomVariant(materialType), (int)MaterialType.Air), pixelArray);
		ActivateCell(new Vector2I(x, y));
		DrawPixelAt(x, y, pixelArray);
	}

	public Pixel GetPixel(int x, int y, Pixel[] pixelArray) 
	{
		return pixelArray[x + gridWidth * y];
	}

	public void SetPixel(int x, int y, Pixel pixel, Pixel[] pixelArray) 
	{
		pixelArray[x + gridWidth * y] = pixel;
	}


	private void SetupImages()
	{
		// First create in RGBA8 to get automatic conversion
		worldImage = Image.CreateEmpty(gridWidth, gridHeight, true, Image.Format.Rgbaf);
		worldImage.Fill(Colors.White);
		worldTexture = ImageTexture.CreateFromImage(worldImage);
		worldTextureRect.Texture = worldTexture;
	}

	private void SetupDebug()
	{
		debugImage = Image.CreateEmpty(gridWidth * PixelSize, gridHeight * PixelSize, false, Image.Format.Rgbaf);
		debugImage.Fill(Colors.White);
		debugTexture = ImageTexture.CreateFromImage(debugImage);
		debugTextureRect.Texture = debugTexture;
		worldTextureRect.CustomMinimumSize = new Vector2(width, height);
	}

	private void DebugDrawActiveCells()
	{
		var red = new Color(Colors.Red, 1);
		var blue = new Color(Colors.Blue, 1);
		foreach (var pos in nextActiveCells.Keys)
		{
			DebugDrawCell(pos, red);
		}
	}

	private void DebugDrawCell(Vector2I cellPos, Color color)
	{
		Vector2I pixelDrawPos = cellPos * CellSize * PixelSize;
		int cellDrawSize = CellSize * PixelSize;
		Rect2I rect = new(pixelDrawPos, new Vector2I(cellDrawSize, cellDrawSize));
		DrawRectOutline(debugImage, rect, color);
	}

	static private void DrawRectOutline(Image image, Rect2I rect, Color color)
	{
		Rect2I r = rect.Intersection(new Rect2I(0, 0, image.GetWidth(), image.GetHeight()));

		for (int x = r.Position.X; x < r.Position.X + r.Size.X; x++)
		{
			image.SetPixel(x, r.Position.Y, color);
			image.SetPixel(x, r.Position.Y + r.Size.Y - 1, color);
		}

		for (int y = r.Position.Y; y < r.Position.Y + r.Size.Y; y++)
		{
			image.SetPixel(r.Position.X, y, color);
			image.SetPixel(r.Position.X + r.Size.X - 1, y, color);
		}
	}

	private void DrawRectFilled(Vector2I pos, Color color)
	{
		var rect = new Rect2I(pos * PixelSize, new Vector2I(PixelSize, PixelSize));
		rect = rect.Intersection(new Rect2I(0, 0, debugImage.GetWidth(), debugImage.GetHeight()));
		debugImage.FillRect(rect, color);
	}
}
}
