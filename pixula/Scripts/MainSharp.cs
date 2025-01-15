using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

[GlobalClass]
public partial class MainSharp : Node2D
{
	// External nodes
	[Export] public TextureRect worldTextureRect;
	[Export] public TextureRect debugTextureRect;
	[Export] public Texture2D colorAtlas;

	private Image colorAtlasImage;

	// Drawing
	private Image worldImage;
	private ImageTexture worldTexture;
	private Image debugImage;

	// Pixel State
	private int[][] currentPixels;
	private int[][] nextPixels;
	private HashSet<Vector2I> processedPixels = [];

	// Simulation
	[Export] public bool EnableDebug { get; set; } = false;
	private int cellSize { get; set; } = 3;

	// Window
	private int width { get; set; } = 1600;
	private int height { get; set; } = 900;
	private int gridWidth;
	private int gridHeight;

	// Pixel Logic
	private const int MaterialBitsStart = 5;
	private const int MaterialBitsMask = 0b1111; // 4 Bit = 16 materials
	private const int VariantBitsStart = 13;
	private const int VariantBitsMask = 0b1111111; // 7 Bit "of color"

	// Benchmarking
	private bool isBenchmark = false;
	private float highestSimulationTime = 0;
	private float totalSimulationTime = 0;
	private int totalFrames = 0;

	// Debug
	private int totalParticles = 0;
	private int lastParticleCount = 0;

	// Grid cells
	private int circleSize { get; set; } = 3;
	private int pixelSize { get; set; } = 5;
	private Dictionary<Vector2I, bool> currentActiveCells = [];
	private Dictionary<Vector2I, bool> nextActiveCells = [];

	private static readonly Random rand = new();

	public enum MaterialType
	{
		Air = 0,
		Sand = 1,
		Water = 2,
		Rock = 3,
		Wall = 4,
		Wood = 5,
		Fire = 6,
		Vapor = 7,
		Cloud = 8,
		Lava = 9,
	}

	private readonly Dictionary<MaterialType, int[]> ColorRanges = new()
	{
		{ MaterialType.Air, new[] { 36, 37 } },
		{ MaterialType.Sand, new[] { 19, 23 } },
		{ MaterialType.Water, new[] { 3, 5 } },
		{ MaterialType.Rock, new[] { 15, 16 } },
		{ MaterialType.Wall, new[] { 38, 39 } },
		{ MaterialType.Wood, new[] { 12, 13} },
		{ MaterialType.Fire, new[] { 27, 29} },
		{ MaterialType.Vapor, new[] { 44, 45} },
		{ MaterialType.Cloud, new[] { 1, 2} },
		{ MaterialType.Lava, new[] { 25, 26} },

	};

	// Next idea: Material -> SwapRules and each Rule contains a callable (being what should be done)
	private readonly Dictionary<MaterialType, MaterialType[]> SwapRules = new()
	{
		{ MaterialType.Air, Array.Empty<MaterialType>() },
		{ MaterialType.Sand, new[] { MaterialType.Air, MaterialType.Water, MaterialType.Vapor, MaterialType.Cloud, MaterialType.Lava  } },
		{ MaterialType.Water, new[] { MaterialType.Air, MaterialType.Vapor, MaterialType.Cloud } },
		{ MaterialType.Rock, new[] { MaterialType.Air, MaterialType.Sand, MaterialType.Water, MaterialType.Vapor, MaterialType.Cloud, MaterialType.Fire } },
		{ MaterialType.Wall, Array.Empty<MaterialType>() },
		{ MaterialType.Wood, Array.Empty<MaterialType>() },
		{ MaterialType.Fire, new[] { MaterialType.Air, MaterialType.Vapor, MaterialType.Cloud } },
		{ MaterialType.Vapor, new[] { MaterialType.Air } },
		{ MaterialType.Cloud, new[] { MaterialType.Air }},
		{ MaterialType.Lava, new[] { MaterialType.Air, MaterialType.Vapor, MaterialType.Cloud }},
	};

	// TODO: Cloud formation, look for other clouds
	// TODO: Acid
	// TODO: Poison: Turns things into CRUST, very flammable!
	// TODO: Acid Vapor 
	// TODO: Acid Cloud from the Acid vapor
	private readonly Vector2I[] directions = {
		new(-1, 1),
		new(0, 1),
		new(1, 1),
		new(1, 0),
		new(1, -1),
		new(0, -1),
		new(-1, -1),
		new(-1, 0),
	};

	public void Initialize(int width, int height, int pixelSize, int cellSize, int spawnRadius)
	{
		this.width = width;
		this.height = height;
		this.gridWidth = width / pixelSize;
		this.gridHeight = height / pixelSize;
		this.pixelSize = pixelSize;
		this.circleSize = spawnRadius;
		this.cellSize = cellSize;
		colorAtlasImage = colorAtlas.GetImage();

		SetupImages();
		SetupDebug();
		SetupPixels();
	}

	private void SetupImages()
	{
		worldImage = Image.CreateEmpty(gridWidth, gridHeight, true, Image.Format.Rgbaf);
		worldImage.Fill(Colors.Transparent);
		worldTexture = ImageTexture.CreateFromImage(worldImage);
		worldTextureRect.Texture = worldTexture;
		worldTextureRect.CustomMinimumSize = new Vector2(width, height);
	}

	private void SetupDebug()
	{
		debugImage = Image.CreateEmpty(gridWidth * pixelSize, gridHeight * pixelSize, false, Image.Format.Rgba8);
		worldImage.Fill(Colors.Transparent);
		var debugTexture = ImageTexture.CreateFromImage(debugImage);
		debugTextureRect.Texture = debugTexture;
	}

	private void DebugDrawActiveCells()
	{
		debugImage.Fill(Colors.Transparent);
		var red = new Color(Colors.Red, 1);
		var blue = new Color(Colors.Blue, 1);
		foreach (var pos in nextActiveCells.Keys)
		{
			DebugDrawCell(pos, red);
		}
	}

	private void DebugDrawCell(Vector2I cellPos, Color color)
	{
		Vector2I pixelDrawPos = cellPos * cellSize * pixelSize;
		int cellDrawSize = cellSize * pixelSize;
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
		var rect = new Rect2I(pos * pixelSize, new Vector2I(pixelSize, pixelSize));
		rect = rect.Intersection(new Rect2I(0, 0, debugImage.GetWidth(), debugImage.GetHeight()));
		debugImage.FillRect(rect, color);
	}

	private void SimulateActive()
	{
		// Copy current frame state
		nextPixels = currentPixels.Select(row => row.ToArray()).ToArray();
		currentActiveCells = new Dictionary<Vector2I, bool>(nextActiveCells);
		nextActiveCells.Clear();

		List<Vector2I> pixelsToSimulate = [];
		foreach (Vector2I cell in currentActiveCells.Keys)
		{
			int cellX = cell.X * cellSize;
			int cellY = cell.Y * cellSize;
			for (int x = cellX; x < cellX + cellSize; x++)
			{
				for (int y = cellY; y < cellY + cellSize; y++)
				{
					if (IsValidPosition(x, y))
						pixelsToSimulate.Add(new Vector2I(x, y));
				}
			}
		}

		// Randomize to avoid directional bias
		pixelsToSimulate = pixelsToSimulate.OrderBy(_ => Guid.NewGuid()).ToList();

		// Simulate
		foreach (var pixelPos in pixelsToSimulate)
		{
			// The return in the machanic states if a change happend that requires the surrounding cells to be activated.
			// Like MoveTo, Removal of an Material etc.
			if (SimulateMaterialAt(pixelPos.X, pixelPos.Y))
				ActivateNeighboringCells(pixelPos.X, pixelPos.Y);
		}

		processedPixels.Clear();

		// Cool swap.
		(nextPixels, currentPixels) = (currentPixels, nextPixels);
	}

	private void ActivateNeighboringCells(int x, int y)
	{
		var cellPos = GetCell(new Vector2I(x, y));
		var posInCell = new Vector2I(x % cellSize, y % cellSize);
		var edgesToActivate = new List<Vector2I>();

		if (posInCell.X == 0)
			edgesToActivate.Add(Vector2I.Left);
		else if (posInCell.X == cellSize - 1)
			edgesToActivate.Add(Vector2I.Right);

		if (posInCell.Y == 0)
			edgesToActivate.Add(Vector2I.Up);
		else if (posInCell.Y == cellSize - 1)
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

	private bool SimulateMaterialAt(int x, int y)
	{
		var currentMaterial = GetMaterialAt(x, y);

		if (currentMaterial == MaterialType.Air)
			return false;

		if (WasProcessed(new Vector2I(x, y)))
			return false;

		return currentMaterial switch
		{
			MaterialType.Sand => SandMechanic(x, y, currentMaterial),
			MaterialType.Water => WaterMechanic(x, y, currentMaterial),
			MaterialType.Rock => MoveDown(x, y, currentMaterial),
			MaterialType.Fire => FireMechanic(x, y, currentMaterial),
			MaterialType.Vapor => VaporMechanics(x, y, currentMaterial),
			MaterialType.Cloud => CloudMechanics(x, y, currentMaterial),
			MaterialType.Lava => LavaMechanics(x, y, currentMaterial),
			MaterialType.Wood => WoodMechanics(x, y, currentMaterial),
			_ => false
		};
	}

    private bool WoodMechanics(int x, int y, MaterialType currentMaterial)
    {

		// Very high chance to do nothing
		if (Random.Shared.NextDouble() < 0.995f)
		{
			ActivateCell(new Vector2I(x, y));
			return true;
		}
		
		// GROW!
		int randomDirection = Random.Shared.Next(0, directions.Length);
		Vector2I checkPosition = directions[randomDirection] + new Vector2I(x, y);

		if (!IsValidPosition(checkPosition.X, checkPosition.Y))
			return false;
		

		MaterialType mat = GetMaterialAt(checkPosition.X, checkPosition.Y);
		if (mat is MaterialType.Air or MaterialType.Sand or MaterialType.Water or MaterialType.Rock)
		{
			ConvertTo(checkPosition.X, checkPosition.Y, MaterialType.Wood);
			return true;
		}

		return false;
    }

    private bool SandMechanic(int x, int y, MaterialType processMaterial)
	{
		return MoveDown(x, y, processMaterial) || MoveDiagonalDown(x, y, processMaterial);
	}

	private bool WaterMechanic(int x, int y, MaterialType processMaterial)
	{
		return MoveDown(x, y, processMaterial) ||
			   MoveDiagonalDown(x, y, processMaterial) ||
			   MoveHorizontal(x, y, processMaterial);
	}

	private bool FireMechanic(int x, int y, MaterialType processMaterial)
	{
		// Always keep fire active!
		ActivateCell(new Vector2I(x, y));

		// Chance to go out
		if (Random.Shared.NextDouble() < 0.025f)
		{
			ConvertTo(x, y, MaterialType.Air);
			return true;
		}

		// Look for neighboring Water.
		if (ExtinguishFire(x, y))
			return true;

		// Spread to flammable materials
		SpreadFire(x, y);

		// Do nothing
		if (Random.Shared.NextDouble() < 0.3f)
			return true;

		// Try to move
		if (Random.Shared.NextDouble() < 0.1f && MoveDown(x, y, processMaterial))
			return true;

		// Try to move
		if (Random.Shared.NextDouble() < 0.6f && MoveUp(x, y, processMaterial))
			return true;
			
		if (MoveDiagonalUp(x, y, processMaterial))
			return true;
		
		if (MoveHorizontal(x, y, processMaterial))
			return true;

		return false;
	}

	private bool LavaMechanics(int x, int y, MaterialType processMaterial)
	{

		// Look for neighboring Water.
		if (ExtinguishLava(x, y))
			return false; // was extinguished

		// Spread to flammable materials
		SpreadFire(x, y);

		// Do nothing 90% of time
		if (Random.Shared.NextDouble() < 0.7f)
		{
			ActivateCell(new Vector2I(x, y));
			return false;
		}

		return MoveDown(x, y, processMaterial) || MoveDiagonalDown(x, y, processMaterial) || MoveHorizontal(x, y, processMaterial);
	}

	private bool VaporMechanics(int x, int y, MaterialType processMaterial) 
	{
		ActivateCell(new Vector2I(x, y));

		// Small chance to disappear
		if (Random.Shared.NextDouble() < 0.01f) 
		{
			SetMaterialAt(x, y, MaterialType.Air, nextPixels);
			return true;
		}

		for (int i = 0; i < 2; i++) 
		{
			if (AttractTowardsMaterial(x, y, 2, 12, MaterialType.Vapor))
				return true;
		}

		// Chance to turn itself to cloud, based on surroundings
		FormCloud(x, y);

		return MoveUp(x, y, processMaterial) || MoveDiagonalUp(x, y, processMaterial) || MoveHorizontal(x, y, processMaterial);
	}

	private static Vector2I GetRandomRingPosition(int centerX, int centerY, int minDist, int maxDist) 
	{
		// 360° Degrees around the pixel are possible 
		// 0 - 1 * 2PI 
		double radians = Random.Shared.NextDouble() * Math.PI * 2;

		// 0 - 1 * (area) + offset
		double distance = Random.Shared.NextDouble() * (maxDist - minDist) + minDist;

		int x = centerX + (int)(Math.Cos(radians) * distance);
		int y = centerY + (int)(Math.Sin(radians) * distance);

		return new Vector2I(x, y);
	}

	private bool AttractTowardsMaterial(int x, int y, int rangeMin, int rangeMax, MaterialType materialType)
	{
		Vector2I pos = GetRandomRingPosition(x, y, rangeMin, rangeMax);
		if (IsValidPosition(pos.X, pos.Y) && GetMaterialAt(pos.X, pos.Y) == materialType)
		{
			Vector2I direction = new(Math.Sign(pos.X - x), Math.Sign(pos.Y -y));
			return MoveTo(x, y, x + direction.X, y + direction.Y, materialType);
		}

		return false;
	}

	private bool CloudMechanics(int x, int y, MaterialType processMaterial)
	{
		ActivateCell(new Vector2I(x, y));

		// Chance to spawn water underneath
		if (Random.Shared.NextDouble() < 0.005f) 
		{
			// Check if space below is empty
			if (GetMaterialAt(x, y + 1) == MaterialType.Air)
				ConvertTo(x, y + 1, MaterialType.Water);
		}

		for (int i = 0; i < 2; i++) 
		{
			if (AttractTowardsMaterial(x, y, 2, 8, MaterialType.Cloud))
				return true;
		}

		// Dying with 0.5% chance per update
		if (Random.Shared.NextDouble() < 0.005f)
		{
			ConvertTo(x, y, MaterialType.Air);
			return true;
		}

		// Do nothing
		if (Random.Shared.NextDouble() < 0.6f)
			return true;

		return MoveUp(x, y, processMaterial) || MoveDiagonalUp(x, y, processMaterial);
	}

	private bool FormCloud(int x, int y) 
	{
		int vaporCount = 0;
		foreach (Vector2I direction in directions) 
		{
			var checkX = x + direction.X;
			var checkY = y + direction.Y;
			if (!IsValidPosition(checkX, checkY))
				continue;

			if (GetMaterialAt(checkX, checkY) == MaterialType.Vapor)
				vaporCount++;
		}

		// Make me a CLOUD
		if (vaporCount >= 4 && Random.Shared.NextDouble() < 0.1f) 
		{
			ConvertTo(x, y, MaterialType.Cloud);
			return true;
		}

		return false;
	}

	private bool ExtinguishFire(int x, int y) 
	{
		foreach (Vector2I direction in directions) 
		{
			var checkX = x + direction.X;
			var checkY = y + direction.Y;
			if (!IsValidPosition(checkX, checkY))
				continue;
			
			if (GetMaterialAt(checkX, checkY) == MaterialType.Water)
			{
				ConvertTo(x, y, MaterialType.Vapor);
				ConvertTo(checkX, checkY, MaterialType.Vapor);
				return true;
			} 
		}
		return false;
	}

	private bool ExtinguishLava(int x, int y) 
	{
		foreach (Vector2I direction in directions) 
		{
			var checkX = x + direction.X;
			var checkY = y + direction.Y;
			if (!IsValidPosition(checkX, checkY))
				continue;
			
			if (GetMaterialAt(checkX, checkY) == MaterialType.Water)
			{
				ConvertTo(x, y, MaterialType.Rock);
				ConvertTo(checkX, checkY, MaterialType.Vapor);
				return true;
			} 
		}
		return false;
	}

	private void SpreadFire(int x, int y)
	{
		foreach (Vector2I direction in directions) 
		{
			var checkX = x + direction.X;
			var checkY = y + direction.Y;
			if (!IsValidPosition(checkX, checkY))
				continue;
			var material = GetMaterialAt(checkX, checkY);

			// 5% chance to burn something!
			if (IsFlammable(material) && Random.Shared.NextDouble() < 0.07f) 
				ConvertTo(checkX, checkY, MaterialType.Fire);
		}
	}

	private bool MoveHorizontal(int x, int y, MaterialType processMaterial)
	{
		var xDirection = y % 2 == 0 ? 1 : -1;
		return MoveTo(x, y, x + xDirection, y, processMaterial);
	}

	private bool MoveDown(int x, int y, MaterialType processMaterial)
	{
		return MoveTo(x, y, x, y + 1, processMaterial);
	}

	private bool MoveUp(int x, int y, MaterialType processMaterial)
	{
		return MoveTo(x, y, x, y - 1, processMaterial);
	}

	private bool MoveDiagonalDown(int x, int y, MaterialType processMaterial)
	{
		var direction = (x + y) % 2 == 0 ? new Vector2I(-1, 1) : new Vector2I(1, 1);
		var newPos = new Vector2I(x, y) + direction;
		return MoveTo(x, y, newPos.X, newPos.Y, processMaterial);
	}

	private bool MoveDiagonalUp(int x, int y, MaterialType processMaterial)
	{
		var direction = (x + y) % 2 == 0 ? new Vector2I(-1, -1) : new Vector2I(1, -1);
		var newPos = new Vector2I(x, y) + direction;
		return MoveTo(x, y, newPos.X, newPos.Y, processMaterial);
	}

	private static bool IsFlammable(MaterialType processMaterial) 
	{
		return processMaterial switch
		{
			MaterialType.Wood => true,
			_ => false
		};
	}

	private bool MoveTo(int x, int y, int newX, int newY, MaterialType processMaterial) 
	{
		if (!IsValidPosition(newX, newY))
			return false;

		if (!CanSwap(processMaterial, GetMaterialAt(newX, newY)))
			return false;
		SwapParticle(x, y, newX, newY);
		return true;
	}

	private Color GetEmission(MaterialType currentMaterial, Color materialColor)
	{
		return currentMaterial switch
		{
			MaterialType.Fire => new Color(
				materialColor.R * 5.5f,  
				materialColor.G * 1.2f, 
				materialColor.B * 1.3f,  
				materialColor.A
			),
			MaterialType.Lava => new Color(
				materialColor.R * 3.0f,
				materialColor.G * 1.5f,
				materialColor.B * 1.0f,
				materialColor.A
			),
			_ => materialColor
		};
	}

	private void DrawPixelAt(int x, int y, int[][] pixelArray)
	{
		int variant = GetVarantAt(x, y, pixelArray);
		MaterialType materialType = GetNewMaterialAt(x, y);
		Color color = GetColorForVariant(variant);
		color = GetEmission(materialType, color);
		worldImage.SetPixel(x, y, color);
	}

	public void DrawSpawnRadiusPreview(int centerX, int centerY, int radius)
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
					DrawRectFilled(new Vector2I(x, y), new Color(Colors.White, 0.3f));
			}
		}

		DrawRectFilled(new Vector2I(centerX, centerY), new Color(Colors.White, 0.9f));

		ImageTexture texture = debugTextureRect.Texture as ImageTexture;
		texture.Update(debugImage);
	}

	static private int GetVarantAt(int x, int y, int[][] pixelArray)
	{
		return (pixelArray[y][x] >> VariantBitsStart) & VariantBitsMask;
	}

	private Color GetColorForVariant(int variant)
	{
		return colorAtlasImage.GetPixel(variant, 0);
	}

	public void ChangeSize(int newPixelSize, int width, int height, int gridWidth, int gridHeight)
	{
		pixelSize = newPixelSize;
		this.width = width;
		this.height = height;
		this.gridWidth = gridWidth;
		this.gridHeight = gridHeight;

		// Recreate images with new dimensions
		worldImage = Image.CreateEmpty(gridWidth, gridHeight, false, Image.Format.Rgba8);
		worldImage.Fill(Colors.Transparent);
		worldTexture = ImageTexture.CreateFromImage(worldImage);
		worldTextureRect.Texture = worldTexture;

		debugImage = Image.CreateEmpty(gridWidth * pixelSize, gridHeight * pixelSize, false, Image.Format.Rgba8);
		debugImage.Fill(Colors.Transparent);
		var debugTexture = ImageTexture.CreateFromImage(debugImage);
		debugTextureRect.Texture = debugTexture;

		// Reset pixel arrays and active cells
		SetupPixels();
		currentActiveCells.Clear();
		nextActiveCells.Clear();
		processedPixels.Clear();

		// Update UI size
		worldTextureRect.CustomMinimumSize = new Vector2(width, height);
	}

	private void SwapParticle(int sourceX, int sourceY, int destinationX, int destinationY)
	{
		var temp = nextPixels[destinationY][destinationX];
		nextPixels[destinationY][destinationX] = currentPixels[sourceY][sourceX];
		nextPixels[sourceY][sourceX] = temp;

		DrawPixelAt(sourceX, sourceY, nextPixels);
		DrawPixelAt(destinationX, destinationY, nextPixels);

		var source = new Vector2I(sourceX, sourceY);
		var destination = new Vector2I(destinationX, destinationY);

		processedPixels.Add(source);
		processedPixels.Add(destination);

		ActivateCell(source);
		ActivateCell(destination);
	}

	private void ConvertTo(int x, int y, MaterialType materialType) 
	{
		SetMaterialAt(x, y, materialType, nextPixels);
		processedPixels.Add(new Vector2I(x, y));
	}
	// called in gd script
	public void Simulate()
	{

		// CheckMouseInput();
		debugImage.Fill(Colors.Transparent);
		var startTime = Time.GetTicksMsec();

		SimulateActive();
		worldTexture.Update(worldImage);

		if (isBenchmark)
			BenchmarkActive(startTime);

		if (EnableDebug)
			DebugDrawActiveCells();

		GetWindow().Title = Engine.GetFramesPerSecond().ToString();
		ImageTexture texture = debugTextureRect.Texture as ImageTexture;
		texture.Update(debugImage);
	}

	public void SpawnInRadius(int centerX, int centerY, int radius, MaterialType materialType)
	{
		for (int y = Math.Max(0, centerY - radius); y < Math.Min(gridHeight, centerY + radius + 1); y++)
		{
			for (int x = Math.Max(0, centerX - radius); x < Math.Min(gridWidth, centerX + radius + 1); x++)
			{
				var distance = new Vector2(centerX - x, centerY - y).Length();
				if (distance <= radius)
				{
					SetMaterialAt(x, y, materialType, currentPixels);
					SetMaterialAt(x, y, materialType, nextPixels);
					ActivateCell(new Vector2I(x, y));
				}
			}
		}
	}


	// Helper methods
	private bool IsValidPosition(int x, int y) =>
		x >= 0 && x < gridWidth && y >= 0 && y < gridHeight;

	private bool IsValidCell(Vector2I cellPos) =>
		cellPos.X >= 0 && cellPos.X < gridWidth/cellSize &&
		cellPos.Y >= 0 && cellPos.Y < gridHeight/cellSize;

	private Vector2I GetCell(Vector2I pos) =>
		new(pos.X / cellSize, pos.Y / cellSize);

	private void ActivateCell(Vector2I pos)
	{
		var cellPos = GetCell(pos);
		nextActiveCells[cellPos] = true;
	}

	private MaterialType GetMaterialAt(int x, int y) =>
		(MaterialType)((currentPixels[y][x] >> MaterialBitsStart) & MaterialBitsMask);

	private MaterialType GetNewMaterialAt(int x, int y) =>
		(MaterialType)((nextPixels[y][x] >> MaterialBitsStart) & MaterialBitsMask);

	private bool WasProcessed(Vector2I position) =>
		processedPixels.Contains(position);

	private bool CanSwap(MaterialType source, MaterialType swappingPartner) =>
		SwapRules.TryGetValue(source, out var rules) && rules.Contains(swappingPartner);

	private void SetupPixels()
	{
		// Initialize coloum
		currentPixels = new int[gridHeight][];
		nextPixels = new int[gridHeight][]; 

		for (int y = 0; y < gridHeight; y++)
		{
			// Initialize Rows
			currentPixels[y] = new int[gridWidth];
			nextPixels[y] = new int[gridWidth]; 
			for (int x = 0; x < gridWidth; x++)
				SetMaterialAt(x, y, MaterialType.Air, currentPixels);
			Array.Copy(currentPixels[y], nextPixels[y], gridWidth);
		}
	}

	private int GetRandomVariant(MaterialType materialType)
	{
		var variants = ColorRanges[materialType];
		return GD.RandRange(variants[0], variants[1]);
	}

	// Event handlers and input processing
	public override void _Input(InputEvent @event)
	{
		if (@event is InputEventMouseButton mouseEvent)
		{
			if (mouseEvent.Pressed)
				Input.MouseMode = Input.MouseModeEnum.Hidden;
		}

		if (@event.IsActionReleased("STATS"))
		{
			InitializeBenchmarkParticles();
		}
	}

	private void InitializeBenchmarkParticles()
	{
		// Clear benchmarking stats
		totalFrames = 0;
		totalSimulationTime = 0;
		highestSimulationTime = 0;
		SetupPixels();
		currentActiveCells.Clear();
		nextActiveCells.Clear();

		// Spawn benchmark particles
		var particlesSpawned = 0;
		const int benchmarkParticleCount = 8000;
		GD.Print($"Benchmark with: {benchmarkParticleCount}");

		var random = new Random();
		while (particlesSpawned < benchmarkParticleCount)
		{
			var x = random.Next(0, gridWidth);
			var y = random.Next(0, gridHeight);
			if (GetMaterialAt(x, y) == MaterialType.Air)
			{
				SetMaterialAt(x, y, MaterialType.Sand, currentPixels);
				particlesSpawned++;
			}
		}

		isBenchmark = true;
	}

	private void SetMaterialAt(int x, int y, MaterialType materialType, int[][] pixelArray)
	{
		if (!IsValidPosition(x, y))
			return;

		pixelArray[y][x] = (((int)materialType) << MaterialBitsStart) |
							(GetRandomVariant(materialType) << VariantBitsStart);
		ActivateCell(new Vector2I(x, y));
		DrawPixelAt(x, y, pixelArray);
	}

	private void BenchmarkActive(ulong startTime)
	{
		var endTime = Time.GetTicksMsec();
		var currentSimulationTime = endTime - startTime;
		totalSimulationTime += currentSimulationTime;
		totalFrames++;

		if (highestSimulationTime < currentSimulationTime)
			highestSimulationTime = currentSimulationTime;

		if (currentActiveCells.Count == 0 && nextActiveCells.Count == 0)
		{
			isBenchmark = false;
			var averageTime = totalSimulationTime / totalFrames;
			GD.Print($"Total: {totalSimulationTime}ms | Average: {averageTime}ms | " +
					$"Highest: {highestSimulationTime}ms | FPS: {Engine.GetFramesPerSecond()}");
		}
	}
}
