using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using Godot;
using GodotPlugins.Game;
using Pixula;


namespace Pixula.Mechanics
{
    public class Plant(MainSharp main) : MaterialMechanic(main) 
    {
        private const int MAX_GROWTH = 10;

        private static readonly Vector2I[] NEIGHBOR_DIRECTIONS =
        [
            new Vector2I(0, -1),   // Up
            new Vector2I(0, 1),    // Down
            new Vector2I(-1, 0),   // Left
            new Vector2I(1, 0),    // Right
        ];

        public override bool Update(int x, int y, MaterialType material)
        {
            Main.ActivateCell(new Vector2I(x, y));

            if (FallAsGroup(x, y, material))
                return true;

            Pixel plant = Main.GetPixel(x, y, Main.CurrentPixels);
            
            if (IsNewPlant(plant))
                return InitializeNewPlant(x, y, plant);

            TryAbsorbSurroundings(x, y, plant);

            if (IsDeadPlant(plant))
                return true;

            return TryGrowPlant(x, y, plant);
        }

        private bool IsNewPlant(Pixel plant) => plant.various == 0;
        private bool IsDeadPlant(Pixel plant) => plant.various < 0;

        private bool InitializeNewPlant(int x, int y, Pixel plant)
        {
            plant.various = GD.RandRange(2, MAX_GROWTH);
            Main.SetPixelAt(x, y, plant, Main.NextPixels);
            return true;
        }

        private void TryAbsorbSurroundings(int x, int y, Pixel sourcePlant)
        {
            Vector2I absorbPosition = NEIGHBOR_DIRECTIONS[GD.RandRange(0, NEIGHBOR_DIRECTIONS.Length - 1)] + new Vector2I(x, y);

            if (CanAbsorb(Main.GetMaterialAt(absorbPosition.X, absorbPosition.Y)))
            {
                sourcePlant.various = GD.RandRange(0, MAX_GROWTH);
                Main.SetPixelAt(x, y, sourcePlant, Main.NextPixels);
                Main.ConvertTo(absorbPosition.X, absorbPosition.Y, MaterialType.Air);
            }
        }

        private bool TryGrowPlant(int x, int y, Pixel plant)
        {
            if (plant.various <= 1)
                return true;

            foreach (var direction in plantGrowingDirections)
            {
                Vector2I targetPos = new Vector2I(x, y) + direction;
                
                if (!plantGrowingDirectionsChance.TryGetValue(direction, out float growChance))
                    continue;

                if (!Chance(growChance))
                    continue;

                if (TryGrowNewPlant(targetPos.X, targetPos.Y, plant))
                {
                    DisablePlant(x, y, plant);
                    return true;
                }
            }

            return ShareGrowthWithNeighbors(x, y, plant);
        }

        private bool CanAbsorb(MaterialType material)
        {
            return material switch 
            {
                MaterialType.Seed => true,
                MaterialType.Water => true,
                _ => false
            };
        }


        private bool TryGrowNewPlant(int targetX, int targetY, Pixel sourcePlant)
        {
            if (!CanGrowAt(new Vector2I(targetX, targetY)))
                return false;

            Pixel targetPixel = Main.GetPixel(targetX, targetY, Main.CurrentPixels);
            
            if (!IsEmpty(targetPixel.material))
                return false;

            int newGrowth = sourcePlant.various - 1;
            Pixel newPlant = new(MaterialType.Plant, Main.GetRandomVariant(MaterialType.Plant), newGrowth);
            Main.SetPixelAt(targetX, targetY, newPlant, Main.NextPixels);
            return true;
        }

        private bool CanGrowAt(Vector2I growCheck)
        {
            // X <- P -> X
            return  Main.GetMaterialAt(growCheck.X - 1, growCheck.Y) != MaterialType.Plant && 
                    Main.GetMaterialAt(growCheck.X + 1, growCheck.Y) != MaterialType.Plant;
        }

        private bool ShareGrowthWithNeighbors(int x, int y, Pixel sourcePlant)
        {
            Vector2I checkPos = Main.Directions[GD.RandRange(0, Main.Directions.Length - 1)] + new Vector2I(x, y);
            
            MaterialType checkMaterial = Main.GetMaterialAt(checkPos.X, checkPos.Y);
            if (!IsGrowable(checkMaterial))
                return false;

            Pixel neighborPlant = Main.GetPixel(checkPos.X, checkPos.Y, Main.CurrentPixels);
            if (neighborPlant.various >= sourcePlant.various)
                return false;

            neighborPlant.various = sourcePlant.various;
            Main.SetPixelAt(checkPos.X, checkPos.Y, neighborPlant, Main.NextPixels);
            DisablePlant(x, y, sourcePlant);
            return true;
        }

        private void DisablePlant(int x, int y, Pixel plant)
        {
            plant.various = -1;
            Main.SetPixelAt(x, y, plant, Main.NextPixels);
        }

        private static Dictionary<Vector2I, float> plantGrowingDirectionsChance = new()
        {
            { new Vector2I(0, -1), 0.5f}, // UP
            { new Vector2I(-1, -1), 0.5f}, // UP LEFT
            { new Vector2I(1, -1), 0.5f}, // UP RIGHT
            { new Vector2I(-1, 0), 0.1f}, // LEFT
            { new Vector2I(1, 0), 0.1f}, // RIGHT
            { new Vector2I(0, 1), 0.2f}, // DOWN
        };

        private static Vector2I[] plantGrowingDirections =
        [
            new Vector2I(0, -1),   // UP
            new Vector2I(-1, -1),  // UP-left
            new Vector2I(1, -1),   // UP-right
            new Vector2I(-1, 0),   // Left
            new Vector2I(1, 0),   // Right
        ];

        private bool IsEmpty(MaterialType materialType) => materialType == MaterialType.Air;
        private bool IsGrowable(MaterialType materialType) => materialType == MaterialType.Plant;
    }
}