using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

public partial class MainSharp : Node2D
{
    // External nodes
    private Timer timer;
    private Camera2D camera;
    private TextureRect textureRect;
    private Texture2D colorAtlas;
    private Image colorAtlasImage;

    // Drawing
    private Image worldImage;
    private ImageTexture worldTexture;
    private Image debugImage;

    // Pixel State
    private int[][] currentPixels;
    private int[][] nextPixels;
    private HashSet<Vector2I> movedPixels = new();

    // Simulation
    [Export] public bool EnableDebug { get; set; } = false;
    [Export(PropertyHint.Range, "0.001,2")] public float SimSpeedSeconds { get; set; } = 0.001f;
    [Export(PropertyHint.Range, "2,32")] public int CellSize { get; set; } = 5;

    // UI
    private Label spawnRadiusLabel;
    private HSlider spawnRadiusSlider;
    private Control mainContainer;
    private bool isPressingUi = false;
    private MaterialType selectedMaterial = MaterialType.Sand;

    // Window
    [Export] public int WindowWidth { get; set; } = 1600;
    [Export] public int WindowHeight { get; set; } = 900;
    private int gridWidth;
    private int gridHeight;
    private Vector2 baseWindowSize;

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
    [Export] public int CircleSize { get; set; } = 3;
    [Export] public int PixelSize { get; set; } = 5;
    private Dictionary<Vector2I, bool> currentActiveCells = new();
    private Dictionary<Vector2I, bool> nextActiveCells = new();

    public enum MaterialType
    {
        Air = 0,
        Sand = 1,
        Water = 2,
        Rock = 3,
        Wall = 4
    }

    private readonly Dictionary<MaterialType, int[]> ColorRanges = new()
    {
        { MaterialType.Air, new[] { 36, 38 } },
        { MaterialType.Sand, new[] { 19, 23 } },
        { MaterialType.Water, new[] { 1, 5 } },
        { MaterialType.Rock, new[] { 12, 16 } },
        { MaterialType.Wall, new[] { 40, 44 } }
    };

    private readonly Dictionary<MaterialType, MaterialType[]> SwapRules = new()
    {
        { MaterialType.Air, Array.Empty<MaterialType>() },
        { MaterialType.Sand, new[] { MaterialType.Air, MaterialType.Water } },
        { MaterialType.Water, new[] { MaterialType.Air } },
        { MaterialType.Rock, new[] { MaterialType.Air, MaterialType.Sand, MaterialType.Water } },
        { MaterialType.Wall, Array.Empty<MaterialType>() }
    };

    public override void _Ready()
    {
        timer = GetNode<Timer>("Timer");
        textureRect = GetNode<TextureRect>("World/WorldTexture");
        colorAtlas = GD.Load<Texture2D>("res://Images/apollo.png");
        colorAtlasImage = colorAtlas.GetImage();
        
        gridWidth = WindowWidth / PixelSize;
        gridHeight = WindowHeight / PixelSize;
        baseWindowSize = new Vector2(WindowWidth, WindowHeight);

        SetupUI();
        SetupImages();
        SetupDebug();
        GetWindow().Size = new Vector2I(WindowWidth, WindowHeight);
        SetupPixels();
    }

    private void SetupUI()
    {
        spawnRadiusLabel = GetNode<Label>("Overlay/MainPanelContainer/MarginContainer/VBoxContainer/HBoxContainer/Panel/SpawnRadius");
        spawnRadiusSlider = GetNode<HSlider>("Overlay/MainPanelContainer/MarginContainer/VBoxContainer/HBoxContainer/HSlider");
        mainContainer = GetNode<Control>("Overlay/MainPanelContainer");

        spawnRadiusSlider.ValueChanged += OnValueChanged;
        
        // Setup material buttons
        GetNode<Button>("Overlay/MainPanelContainer/MarginContainer/VBoxContainer/AirButton").Pressed += () => selectedMaterial = MaterialType.Air;
        GetNode<Button>("Overlay/MainPanelContainer/MarginContainer/VBoxContainer/SandButton").Pressed += () => selectedMaterial = MaterialType.Sand;
        GetNode<Button>("Overlay/MainPanelContainer/MarginContainer/VBoxContainer/WaterButton").Pressed += () => selectedMaterial = MaterialType.Water;
        GetNode<Button>("Overlay/MainPanelContainer/MarginContainer/VBoxContainer/RockButton").Pressed += () => selectedMaterial = MaterialType.Rock;
        GetNode<Button>("Overlay/MainPanelContainer/MarginContainer/VBoxContainer/WallButton").Pressed += () => selectedMaterial = MaterialType.Wall;

        SetMouseFilterOnUI(mainContainer);
    }

    private void SetMouseFilterOnUI(Node node)
    {
        if (node is Button button)
			button.GuiInput += OnGuiInput;
		
		if (node is Slider slider)
			 slider.MouseExited += OnMouseExit;

        foreach (var child in node.GetChildren())
            SetMouseFilterOnUI(child);
    }

    private void OnValueChanged(double value)
    {
        CircleSize = (int)value;
        spawnRadiusLabel.Text = CircleSize.ToString();
    }

    private void OnGuiInput(InputEvent @event)
    {
        if (@event is InputEventMouseButton mouseButton)
            isPressingUi = mouseButton.Pressed;
    }

    private void OnMouseExit()
    {
        isPressingUi = false;
    }

    private void SetupImages()
    {
        worldImage = Image.CreateEmpty(gridWidth, gridHeight, false, Image.Format.Rgba8);
        worldImage.Fill(Colors.Transparent);
        worldTexture = ImageTexture.CreateFromImage(worldImage);
        textureRect.Texture = worldTexture;
        textureRect.CustomMinimumSize = new Vector2(WindowWidth, WindowHeight);
    }

    private void SetupDebug()
    {
        debugImage = Image.CreateEmpty(gridWidth * PixelSize, gridHeight * PixelSize, false, Image.Format.Rgba8);
        worldImage.Fill(Colors.Transparent);
        var debugTexture = ImageTexture.CreateFromImage(debugImage);
        GetNode<TextureRect>("World/DebugLayer/DebugTexture").Texture = debugTexture;
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
        var pixelDrawPos = cellPos * CellSize * PixelSize;
        var cellDrawSize = CellSize * PixelSize;
        var rect = new Rect2I(pixelDrawPos, new Vector2I(cellDrawSize, cellDrawSize));
        DrawRectOutline(debugImage, rect, color);
    }

    private void DrawRectOutline(Image image, Rect2I rect, Color color)
    {
        var r = rect.Intersection(new Rect2I(0, 0, image.GetWidth(), image.GetHeight()));

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

    private void SimulateActive()
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

        // Simulate
        foreach (var pixelPos in pixelsToSimulate)
        {
            if (Simulate(pixelPos.X, pixelPos.Y))
                ActivateNeighboringCells(pixelPos.X, pixelPos.Y);
        }

        movedPixels.Clear();

        // Cool swap.
        (nextPixels, currentPixels) = (currentPixels, nextPixels);
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

	private void DrawPixelAt(int x, int y, int[][] pixelArray)
	{
		int variant = GetVarantAt(x, y, pixelArray);
		Color color = GetColorForVariant(variant);
		worldImage.SetPixel(x, y, color);
	}

    private void DrawSpawnRadiusPreview(int centerX, int centerY, int radius)
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

        ImageTexture texture = GetNode<TextureRect>("World/DebugLayer/DebugTexture").Texture as ImageTexture;
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


    private void SwapParticle(int sourceX, int sourceY, int destinationX, int destinationY)
    {
        var temp = nextPixels[destinationY][destinationX];
        nextPixels[destinationY][destinationX] = currentPixels[sourceY][sourceX];
        nextPixels[sourceY][sourceX] = temp;

        DrawPixelAt(sourceX, sourceY, nextPixels);
        DrawPixelAt(destinationX, destinationY, nextPixels);

        var source = new Vector2I(sourceX, sourceY);
        var destination = new Vector2I(destinationX, destinationY);

        movedPixels.Add(source);
        movedPixels.Add(destination);

        ActivateCell(source);
        ActivateCell(destination);
    }

    public override void _Process(double delta)
    {

        CheckMouseInput();
        debugImage.Fill(Colors.Transparent);
        timer.WaitTime = SimSpeedSeconds;
        var startTime = Time.GetTicksMsec();

        SimulateActive();
        worldTexture.Update(worldImage);

        if (isBenchmark)
            BenchmarkActive(startTime);

        if (EnableDebug)
            DebugDrawActiveCells();

        GetWindow().Title = Engine.GetFramesPerSecond().ToString();
        ImageTexture texture = GetNode<TextureRect>("World/DebugLayer/DebugTexture").Texture as ImageTexture;
		texture.Update(debugImage);
        Vector2I mousePosition = GetMouseTilePos();
        DrawSpawnRadiusPreview(mousePosition.X, mousePosition.Y, CircleSize);
    }

    private void CheckMouseInput() 
    {
        if (Input.IsActionPressed("SPAWN_SAND") && !isPressingUi)
        {
            Vector2I pos = GetMouseTilePos();
            SpawnInRadius(pos.X, pos.Y, CircleSize, selectedMaterial);
        }

        if (Input.IsActionPressed("SPAWN_WATER") && !isPressingUi)
        {
            Vector2I pos = GetMouseTilePos();
            SpawnInRadius(pos.X, pos.Y, CircleSize, MaterialType.Air);
        }
    }

	private void SpawnInRadius(int centerX, int centerY, int radius, MaterialType materialType)
	{
		for (int y = Math.Max(0, centerY - radius); y < Math.Min(gridHeight, centerY + radius + 1); y++)
		{
			for (int x = Math.Max(0, centerX - radius); x < Math.Min(gridWidth, centerX + radius + 1); x++)
			{
				var distance = new Vector2(centerX - x, centerY - y).Length();
				if (distance <= radius)
				{
					SetStateAt(x, y, materialType, GetRandomVariant(materialType));
					ActivateCell(new Vector2I(x, y));
				}
			}
		}
	}


    // Helper methods
    private bool IsValidPosition(int x, int y) => 
        x >= 0 && x < gridWidth && y >= 0 && y < gridHeight;

    private bool IsValidCell(Vector2I cellPos) => 
        cellPos.X >= 0 && cellPos.X < gridWidth/CellSize && 
        cellPos.Y >= 0 && cellPos.Y < gridHeight/CellSize;

    private Vector2I GetCell(Vector2I pos) => 
        new(pos.X / CellSize, pos.Y / CellSize);

    private void ActivateCell(Vector2I pos)
    {
        var cellPos = GetCell(pos);
        nextActiveCells[cellPos] = true;
    }

    private MaterialType GetMaterialAt(int x, int y) =>
        (MaterialType)((currentPixels[y][x] >> MaterialBitsStart) & MaterialBitsMask);

    private bool HasMoved(Vector2I position) => 
        movedPixels.Contains(position);

    private bool CanSwap(MaterialType source, MaterialType swappingPartner) =>
        SwapRules.TryGetValue(source, out var rules) && rules.Contains(swappingPartner);

    private void SetupPixels()
    {
        currentPixels = new int[gridHeight][];
        for (int y = 0; y < gridHeight; y++)
        {
            currentPixels[y] = new int[gridWidth];
            for (int x = 0; x < gridWidth; x++)
                SetStateAt(x, y, MaterialType.Air, GetRandomVariant(MaterialType.Air));
        }
        nextPixels = currentPixels.Select(row => row.ToArray()).ToArray();
    }

    private int GetRandomVariant(MaterialType materialType)
    {
        var variants = ColorRanges[materialType];
        return GD.RandRange(variants[0], variants[1]);
    }

    private Vector2I GetMouseTilePos()
    {
        var currentSize = DisplayServer.WindowGetSize();
        var scaleFactor = new Vector2(
            baseWindowSize.X / currentSize.X,
            baseWindowSize.Y / currentSize.Y
        );
        Vector2I mousePos = (Vector2I) (GetViewport().GetMousePosition() * scaleFactor / PixelSize).Abs();

        return mousePos.Clamp(Vector2I.Zero, new Vector2I(gridWidth - 1, gridHeight -1));
    }

    // Event handlers and input processing
    public override void _Input(InputEvent @event)
    {
        if (@event is InputEventMouseButton mouseEvent)
        {
            if (mouseEvent.Pressed)
                Input.MouseMode = Input.MouseModeEnum.Hidden;
        }

        if (@event.IsActionReleased("CHECK_MATERIAL"))
        {
            var mousePos = GetMouseTilePos();
            GD.Print(GetMaterialAt(mousePos.X, mousePos.Y));
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
				SetStateAt(x, y, MaterialType.Sand, GetRandomVariant(MaterialType.Sand));
				particlesSpawned++;
			}
		}

		isBenchmark = true;
	}

	private void SetStateAt(int x, int y, MaterialType materialType, int variant)
	{
		if (!IsValidPosition(x, y))
			return;

		currentPixels[y][x] = (((int)materialType) << MaterialBitsStart) |
							(variant << VariantBitsStart);
		ActivateCell(new Vector2I(x, y));
		DrawPixelAt(x, y, currentPixels);
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
