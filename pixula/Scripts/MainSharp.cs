using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Pixula {


public struct Pixel
{
	public Pixel(MainSharp.MaterialType material, Vector2I variantPos, int various)
	{
		this.material = material;
		this.variantPos = variantPos;
		this.various = various;
	}

	public MainSharp.MaterialType material;
	public Vector2I variantPos;
	public int various;
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
	public Pixel[] currentPixels;
	public Pixel[] nextPixels;

	// Simulation
	[Export] public bool EnableDebug { get; set; } = false;
	private int cellSize { get; set; } = 3;

	// Window
	private int width { get; set; } = 1600;
	private int height { get; set; } = 900;
	private int gridWidth;
	private int gridHeight;

	// Benchmarking
	private bool isBenchmark = false;
	private float highestSimulationTime = 0;
	private float totalSimulationTime = 0;
	private int totalFrames = 0;

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
		Poison = 16,
		Fluff = 17,
		Ember = 18

		// VOID -> Removes particles touching it
		// REPEAT -> Spawns the same particle randomly around it or where it touched?
		// Seed -> Grows when on top of soil 
		// Seed -> ALSO grows wood under it
		// Seed -> Can absorb water
		// Poison -> Eats through things turning them into highly flammable fluff
		// FLUFF -> Very flammable stuff
		// Coal? -> Burns for long
		// EMBER -> Hot Coal basically, can put stuff on fire
	}

	// Array depicts the start in the color map and how far
	// -> Color pos + width (normally 1 as it only needs one column)
	private readonly Dictionary<MaterialType, int[]> ColorRanges = new()
	{
		{ MaterialType.Air, new[] { 36, 0 } },
		{ MaterialType.Sand, new[] { 22, 1 } },
		{ MaterialType.Water, new[] { 2, 1 } },
		{ MaterialType.Rock, new[] { 18, 0 } },
		{ MaterialType.Wall, new[] { 37, 0 } },
		{ MaterialType.Wood, new[] { 12, 1} },
		{ MaterialType.Fire, new[] { 27, 1} },
		{ MaterialType.WaterVapor, new[] { 44, 1} },
		{ MaterialType.WaterCloud, new[] { 1, 0} },
		{ MaterialType.Lava, new[] { 25, 1} },
		{ MaterialType.Acid, new[] { 10, 0} },
		{ MaterialType.AcidVapor, new[] { 10, 0} },
		{ MaterialType.AcidCloud, new[] { 6, 0} },
		{ MaterialType.Void, new[] { 6, 0} },
		{ MaterialType.Mimic, new[] { 6, 0} },
		{ MaterialType.Seed, new[] { 6, 0} },
		{ MaterialType.Poison, new[] { 34, 0} },
		{ MaterialType.Fluff, new[] { 6, 0} },
		{ MaterialType.Ember, new[] { 6, 0} },

	};

	private readonly Dictionary<MaterialType, MaterialType[]> SwapRules = new()
	{
		{ MaterialType.Air, Array.Empty<MaterialType>() },
		{ MaterialType.Sand, new[] { MaterialType.Air, MaterialType.Water, MaterialType.WaterVapor, MaterialType.WaterCloud, MaterialType.Lava, MaterialType.Acid, MaterialType.AcidVapor, MaterialType.AcidCloud} },
		{ MaterialType.Water, new[] { MaterialType.Air, MaterialType.WaterVapor, MaterialType.WaterCloud, MaterialType.Acid, MaterialType.AcidVapor, MaterialType.AcidCloud } },
		{ MaterialType.Rock, new[] { MaterialType.Air, MaterialType.Sand, MaterialType.Water, MaterialType.WaterVapor, MaterialType.WaterCloud, MaterialType.Fire, MaterialType.Acid, MaterialType.AcidVapor, MaterialType.AcidCloud, MaterialType.Lava } },
		{ MaterialType.Wall, Array.Empty<MaterialType>() },
		{ MaterialType.Wood, Array.Empty<MaterialType>() },
		{ MaterialType.Fire, new[] { MaterialType.Air, MaterialType.WaterVapor, MaterialType.WaterCloud, MaterialType.AcidVapor, MaterialType.AcidCloud } },
		{ MaterialType.WaterVapor, new[] { MaterialType.Air } },
		{ MaterialType.WaterCloud, new[] { MaterialType.Air }},
		{ MaterialType.Lava, new[] { MaterialType.Air, MaterialType.WaterVapor, MaterialType.WaterCloud, MaterialType.Acid, MaterialType.AcidVapor, MaterialType.AcidCloud}},
		{ MaterialType.Acid, new[] { MaterialType.Air, MaterialType.AcidVapor, MaterialType.WaterVapor }},
		{ MaterialType.AcidVapor, new[] { MaterialType.Air }},
		{ MaterialType.AcidCloud, new[] { MaterialType.Air }},
	};



	private static bool IsFlammable(MaterialType processMaterial) 
	{
		return processMaterial switch
		{
			MaterialType.Wood => true,
			_ => false
		};
	}

	private static bool IsDissolvable(MaterialType processMaterial) 
	{
		return processMaterial switch
		{
			MaterialType.Acid => false,
			MaterialType.Water => false,
			MaterialType.Lava => false,
			MaterialType.Air => false,
			MaterialType.Wall => false,
			_ => true
		};
	}

	public void Initialize(int width, int height, int pixelSize, int cellSize, int spawnRadius)
	{
		this.width = width;
		this.height = height;
		this.gridWidth = width / pixelSize;
		this.gridHeight = height / pixelSize;
		this.PixelSize = pixelSize;
		this.SpawnRadius = spawnRadius;
		this.cellSize = cellSize;
		colorAtlasImage = colorAtlas.GetImage();

		SetupImages();
		SetupDebug();
		SetupPixels();
		DrawImages();
	}


	private bool SimulateMaterialAt(int x, int y)
	{
		var currentMaterial = GetMaterialAt(x, y);

		if (currentMaterial == MaterialType.Air)
			return false;

		if (processedPositions.Contains(new Vector2I(x, y)))
			return false;

		return currentMaterial switch
		{
			MaterialType.Sand => SandMechanic(x, y, currentMaterial),
			MaterialType.Water => WaterMechanic(x, y, currentMaterial),
			MaterialType.Rock => RockMechanics(x, y, currentMaterial),
			MaterialType.Fire => FireMechanic(x, y, currentMaterial),
			MaterialType.WaterVapor => VaporMechanics(x, y, currentMaterial),
			MaterialType.WaterCloud => CloudMechanics(x, y, currentMaterial),
			MaterialType.Lava => LavaMechanics(x, y, currentMaterial),
			MaterialType.Wood => WoodMechanics(x, y, currentMaterial),
			MaterialType.Acid => AcidMechanics(x, y, currentMaterial),
			MaterialType.AcidVapor => AcidVaporMechanics(x, y, currentMaterial),
			MaterialType.AcidCloud => AcidCloudMechanics(x, y, currentMaterial),
			_ => false
		};
	}

	
	public void Simulate()
	{
		var startTime = Time.GetTicksMsec();
		SimulateActive();

		if (isBenchmark)
			BenchmarkActive(startTime);

		GetWindow().Title = Engine.GetFramesPerSecond().ToString();
	}

    private void SimulateActive()
	{
		processedPositions.Clear();
		Array.Copy(currentPixels, nextPixels, currentPixels.Length);
		currentActiveCells = new Dictionary<Vector2I, bool>(nextActiveCells);
		nextActiveCells.Clear();



		List<Vector2I> pixelsToSimulate = [];
		foreach (Vector2I cell in currentActiveCells.Keys)
		{
			int cellX = cell.X * cellSize;
			int cellY = cell.Y * cellSize;
			for (int y = cellY; y < cellY + cellSize; y++)
			{
				for (int x = cellX; x < cellX + cellSize; x++)
				{
					if (IsValidPosition(x, y))
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
			// The return in the machanic states if a change happend that requires the surrounding cells to be activated.
			// Like MoveTo, Removal of an Material etc.
			if (SimulateMaterialAt(pixelPos.X, pixelPos.Y))
				ActivateNeighboringCells(pixelPos.X, pixelPos.Y);
		}

		// // Cool swap.
		(nextPixels, currentPixels) = (currentPixels, nextPixels);
	}

	public void DrawImages()
	{
		debugImage.Fill(Colors.Transparent);
		foreach (var positionColor in positionColors)
			worldImage.SetPixel(positionColor.Key.X, positionColor.Key.Y, positionColor.Value);

		worldTexture.Update(worldImage);
		positionColors.Clear();

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

    private bool AcidMechanics(int x, int y, MaterialType currentMaterial)
	{

		// Do nothing
		if (Random.Shared.NextDouble() < 0.8f)
		{
			ActivateCell(new Vector2I(x, y));
			return false;
		}

		// Try moving down
		if (MoveDown(x, y, currentMaterial)) return true;

		// Can't move? Try dissolving what's below
		int newX = x;
		int newY = y + 1;
		if (Random.Shared.NextDouble() < 0.2f && IsValidPosition(newX, newY) && IsDissolvable(GetMaterialAt(newX, newY)))
		{
			ConvertTo(newX, newY, MaterialType.AcidVapor);

			// Chance to Disappear
			if (Random.Shared.NextDouble() < 0.25f) ConvertTo(x, y, MaterialType.Air);
			return true;
		}

		// Try diagonal movement/dissolving
		var direction = (x + y) % 2 == 0 ? new Vector2I(-1, 1) : new Vector2I(1, 1);
		var newPos = new Vector2I(x, y) + direction;
		if (MoveTo(x, y, newPos.X, newPos.Y, currentMaterial)) return true;
		if (IsValidPosition(newPos.X, newPos.Y) && IsDissolvable(GetMaterialAt(newPos.X, newPos.Y)))
		{
			ConvertTo(newPos.X, newPos.Y, MaterialType.AcidVapor);
			
			// Chance to Disappear
			if (Random.Shared.NextDouble() < 0.25f) ConvertTo(x, y, MaterialType.Air);
			return true;
		}

		// Try horizontal movement/dissolving
		int xDirection = y % 2 == 0 ? 1 : -1;
		newX = x + xDirection;
		if (MoveTo(x, y, newX, y, currentMaterial)) return true;
		if (IsValidPosition(newX, y) && IsDissolvable(GetMaterialAt(newX, y)))
		{
			ConvertTo(newX, y, MaterialType.AcidVapor);

			// Chance to Disappear
			if (Random.Shared.NextDouble() < 0.25f) ConvertTo(x, y, MaterialType.Air);
			return true;
		}

		return false;
	}

    private bool AcidVaporMechanics(int x, int y, MaterialType currentMaterial)
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
			if (AttractTowardsMaterial(x, y, 2, 12, MaterialType.WaterVapor))
				return true;
		}

		// Chance to turn itself to cloud, based on surroundings
		FormCloud(x, y, MaterialType.AcidVapor, MaterialType.AcidCloud);

		// Do nothing -> slow
		if (Random.Shared.NextDouble() < 0.5f) return true;

		if (Random.Shared.NextDouble() < 0.8f && MoveUp(x, y, currentMaterial)) return true; 

		return MoveDiagonalUp(x, y, currentMaterial) || MoveHorizontal(x, y, currentMaterial);
    }

	private bool AcidCloudMechanics(int x, int y, MaterialType processMaterial)
	{
		ActivateCell(new Vector2I(x, y));

		// Chance to spawn acid underneath
		if (Random.Shared.NextDouble() < 0.005f) 
		{
			// Check if space below is empty
			if (GetMaterialAt(x, y + 1) == MaterialType.Air)
				ConvertTo(x, y + 1, MaterialType.Acid);
		}

		for (int i = 0; i < 2; i++) 
		{
			if (AttractTowardsMaterial(x, y, 2, 8, MaterialType.AcidCloud))
				return true;
		}

		// Dying with 0.25% chance per update
		if (Random.Shared.NextDouble() < 0.0025f)
		{
			ConvertTo(x, y, MaterialType.Air);
			return true;
		}

		// Do nothing
		if (Random.Shared.NextDouble() < 0.4f)
			return true;

		return MoveUp(x, y, processMaterial) || MoveDiagonalUp(x, y, processMaterial);
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
		if (Random.Shared.NextDouble() < 0.1f && MoveDown(x, y, processMaterial)) return true;

		// Try to move
		if (Random.Shared.NextDouble() < 0.6f && MoveUp(x, y, processMaterial)) return true;
			
		if (MoveDiagonalUp(x, y, processMaterial)) return true;
		
		if (MoveHorizontal(x, y, processMaterial)) return true;

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

	private bool VaporMechanics(int x, int y, MaterialType currentMaterial) 
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
			if (AttractTowardsMaterial(x, y, 2, 12, MaterialType.WaterVapor))
				return true;
		}

		// Chance to turn itself to cloud, based on surroundings
		FormCloud(x, y, MaterialType.WaterVapor, MaterialType.WaterCloud);
		// Do nothing -> slow
		if (Random.Shared.NextDouble() < 0.5f) return true;

		if (Random.Shared.NextDouble() < 0.8f && MoveUp(x, y, currentMaterial)) return true; 

		return MoveDiagonalUp(x, y, currentMaterial) || MoveHorizontal(x, y, currentMaterial);
	}

	private bool RockMechanics(int x, int y, MaterialType currentMaterial)
	{
		if (IsValidPosition(x, y + 1) && GetMaterialAt(x, y + 1) == MaterialType.Lava)
		{
			// Slower in lava
			if (Random.Shared.NextSingle() < 0.03)
			{
				return MoveDown(x, y, currentMaterial);
			}
			ActivateCell(new Vector2I(x, y));
			return true;
		}
		
		// Normal!
		return MoveDown(x, y, currentMaterial);

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
					float rand = Random.Shared.NextSingle();
					if (rand < 0.4f)
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

	private bool CloudMechanics(int x, int y, MaterialType processMaterial)
	{
		ActivateCell(new Vector2I(x, y));

		// Chance to spawn water underneath
		if (Random.Shared.NextDouble() < 0.01f) 
		{
			// Check if space below is empty
			if (GetMaterialAt(x, y + 1) == MaterialType.Air)
				ConvertTo(x, y + 1, MaterialType.Water);
		}

		for (int i = 0; i < 2; i++) 
		{
			if (AttractTowardsMaterial(x, y, 2, 8, MaterialType.WaterCloud))
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

	private bool FormCloud(int x, int y, MaterialType vaporType, MaterialType cloudType) 
	{
		int vaporCount = 0;
		foreach (Vector2I direction in directions) 
		{
			var checkX = x + direction.X;
			var checkY = y + direction.Y;
			if (!IsValidPosition(checkX, checkY))
				continue;

			if (GetMaterialAt(checkX, checkY) == vaporType)
				vaporCount++;
		}

		// Make me a CLOUD
		if (vaporCount >= 4 && Random.Shared.NextDouble() < 0.1f) 
		{
			ConvertTo(x, y, cloudType);
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
				ConvertTo(x, y, MaterialType.WaterVapor);
				ConvertTo(checkX, checkY, MaterialType.WaterVapor);
				return true;
			} 
		}
		return false;
	}

	private bool ExtinguishLava(int x, int y) 
	{
		foreach (Vector2I direction in directions) 
		{
			int checkX = x + direction.X;
			int checkY = y + direction.Y;
			if (!IsValidPosition(checkX, checkY))
				continue;
			
			if (GetMaterialAt(checkX, checkY) == MaterialType.Water)
			{
				if (Random.Shared.NextSingle() < 0.1) ConvertTo(x, y, MaterialType.Rock);
				ConvertTo(checkX, checkY, MaterialType.WaterVapor);

				foreach (Vector2I dirAroundWater in directions)
				{
					int checkVaporX = checkX + dirAroundWater.X;
					int checkVaporY = checkY + dirAroundWater.Y;
					if (!IsValidPosition(checkVaporX, checkVaporY))
						continue;

					if (GetMaterialAt(checkVaporX, checkVaporY) == MaterialType.Air)
						ConvertTo(checkVaporX, checkVaporY, MaterialType.WaterVapor);
				}
				return true;
			} 
		}
		return false;
	}


	private void SpreadFire(int x, int y)
	{
		foreach (Vector2I direction in directions) 
		{
			int checkX = x + direction.X;
			int checkY = y + direction.Y;
			if (!IsValidPosition(checkX, checkY))
				continue;
			MaterialType material = GetMaterialAt(checkX, checkY);

			// 5% chance to burn something!
			if (IsFlammable(material) && Random.Shared.NextDouble() < 0.07f) 
				ConvertTo(checkX, checkY, MaterialType.Fire);
		}
	}

	private bool MoveHorizontal(int x, int y, MaterialType processMaterial)
	{
		// Direction not yet set.
		Pixel p = GetPixel(x, y, currentPixels);
		if (p.various == 0)
		{
			int xDirection = y % 2 == 0 ? 1 : -1;
			p.various = xDirection;
		}

		// Various is the direction
		// Try moving into the direction
		bool ableToMoveHorizontal = MoveTo(x, y, x + p.various, y, processMaterial);

		if (!ableToMoveHorizontal)
		{
			// Bounce!
			p.various *= -1;
			SetPixel(x, y, p, nextPixels);
			return true;
		}

		return ableToMoveHorizontal;
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
		Vector2I direction = (x + y) % 2 == 0 ? new Vector2I(-1, 1) : new Vector2I(1, 1);
		Vector2I newPos = new Vector2I(x, y) + direction;
		return MoveTo(x, y, newPos.X, newPos.Y, processMaterial);
	}

	private bool MoveDiagonalUp(int x, int y, MaterialType processMaterial)
	{
		Vector2I direction = (x + y) % 2 == 0 ? new Vector2I(-1, -1) : new Vector2I(1, -1);
		Vector2I newPos = new Vector2I(x, y) + direction;
		return MoveTo(x, y, newPos.X, newPos.Y, processMaterial);
	}

	private bool MoveTo(int x, int y, int newX, int newY, MaterialType processMaterial) 
	{
		Vector2I source = new(x, y);
		Vector2I destination = new(newX, newY);

		if (!IsValidPosition(newX, newY))
			return false;

		if (!CanSwap(processMaterial, GetMaterialAt(newX, newY)))
			return false;

		SwapParticle(x, y, newX, newY);
		DrawPixelAt(x, y, nextPixels);
		DrawPixelAt(newX, newY, nextPixels);

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
					DrawRectFilled(new Vector2I(x, y), new Color(Colors.White, 0.3f));
			}
		}

		DrawRectFilled(new Vector2I(centerX, centerY), new Color(Colors.White, 0.9f));
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
		this.gridWidth = gridWidth;
		this.gridHeight = gridHeight;

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
		Pixel temp = GetPixel(destinationX, destinationY, nextPixels);
		SetPixel(destinationX, destinationY, GetPixel(sourceX, sourceY, currentPixels), nextPixels);
		SetPixel(sourceX, sourceY, temp, nextPixels);
	}

	private void ConvertTo(int x, int y, MaterialType materialType) 
	{
		SetMaterialAt(x, y, materialType, nextPixels);
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

	private MaterialType GetMaterialAt(int x, int y) => GetPixel(x, y, currentPixels).material;

	private MaterialType GetNewMaterialAt(int x, int y) => GetPixel(x, y, nextPixels).material;

	private bool CanSwap(MaterialType source, MaterialType swappingPartner) =>
		SwapRules.TryGetValue(source, out var rules) && rules.Contains(swappingPartner);

	private void SetupPixels()
	{
		// Initialize coloum
		currentPixels = new Pixel[gridHeight * gridWidth];
		nextPixels = new Pixel[gridHeight * gridWidth]; 

		for (int y = 0; y < gridHeight; y++)
		{
			for (int x = 0; x < gridWidth; x++)
			{
				SetMaterialAt(x, y, MaterialType.Air, currentPixels);
				SetMaterialAt(x, y, MaterialType.Air, nextPixels);
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
		if (!IsValidPosition(x, y))
			return Colors.Transparent;
			
		return worldImage.GetPixel(x, y);
	}

	public void InitializeBenchmarkParticles()
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

	private void SetMaterialAt(int x, int y, MaterialType materialType, Pixel[] pixelArray)
	{
		if (!IsValidPosition(x, y))
			return;
		
		SetPixel(x, y, new Pixel(materialType, GetRandomVariant(materialType), 0), pixelArray);
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

	private Pixel GetPixel(int x, int y, Pixel[] pixelArray) 
	{
		return pixelArray[x + gridWidth * y];
	}

	private void SetPixel(int x, int y, Pixel pixel, Pixel[] pixelArray) 
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
		Vector2I pixelDrawPos = cellPos * cellSize * PixelSize;
		int cellDrawSize = cellSize * PixelSize;
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
