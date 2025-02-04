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
        private const int MAX_GROWTH = 3;
        private const float GROW_UP_CHANCE = 1.0f;
        private const float GROW_SIDE_CHANCE = 0.5f;

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

            TryAbsorbWater(x, y, plant);

            if (IsDeadPlant(plant))
                return true;
            

            return TryGrowPlant(x, y, plant);
        }

        private bool IsNewPlant(Pixel plant) => plant.various == 0;
        private bool IsDeadPlant(Pixel plant) => plant.various < 0;

        private bool InitializeNewPlant(int x, int y, Pixel plant)
        {
            plant.various = MAX_GROWTH;
            Main.SetPixelAt(x, y, plant, Main.NextPixels);
            return true;
        }

        private void TryAbsorbWater(int x, int y, Pixel sourcePlant)
        {
            Vector2I waterCheckPos = NEIGHBOR_DIRECTIONS[GD.RandRange(0, NEIGHBOR_DIRECTIONS.Length - 1)] + new Vector2I(x, y);

            if (!Main.IsInBounds(waterCheckPos.X, waterCheckPos.Y))
                return;

            if (Main.GetMaterialAt(waterCheckPos.X, waterCheckPos.Y) == MaterialType.Water)
            {
                sourcePlant.various = GD.RandRange(0, MAX_GROWTH);
                Main.SetPixelAt(x, y, sourcePlant, Main.NextPixels);
                Main.ConvertTo(waterCheckPos.X, waterCheckPos.Y, MaterialType.Air);
            }
        }

        private bool TryGrowPlant(int x, int y, Pixel plant)
        {
            if (plant.various <= 1 || !Chance(GROW_UP_CHANCE))
                return true;

            if (TryGrowNewPlant(x, y - 1, plant))
            {
                DisablePlant(x, y, plant);
                return true;
            }

            return ShareGrowthWithNeighbors(x, y, plant);
        }

        private bool TryGrowNewPlant(int targetX, int targetY, Pixel sourcePlant)
        {
            if (!Main.IsInBounds(targetX, targetY))
                return false;

            Pixel targetPixel = Main.GetPixel(targetX, targetY, Main.CurrentPixels);
            
            if (!IsEmpty(targetPixel.material))
                return false;

            int newGrowth = sourcePlant.various - 1;
            Pixel newPlant = new(MaterialType.Plant, Main.GetRandomVariant(MaterialType.Plant), newGrowth);
            Main.SetPixelAt(targetX, targetY, newPlant, Main.NextPixels);
            return true;
        }

        private bool ShareGrowthWithNeighbors(int x, int y, Pixel sourcePlant)
        {
            Vector2I checkPos = Main.Directions[GD.RandRange(0, Main.Directions.Length - 1)] + new Vector2I(x, y);
            
            if (!Main.IsInBounds(checkPos.X, checkPos.Y))
                return false;

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

        private bool CanGrowAt(Vector2I pos)
        {
            return Main.IsInBounds(pos.X - 1, pos.Y) && 
                Main.IsInBounds(pos.X + 1, pos.Y) && 
                Main.GetMaterialAt(pos.X - 1, pos.Y) != MaterialType.Plant && 
                Main.GetMaterialAt(pos.X + 1, pos.Y) != MaterialType.Plant;
        }

        private bool IsEmpty(MaterialType materialType) => materialType == MaterialType.Air;
        private bool IsGrowable(MaterialType materialType) => materialType == MaterialType.Plant;
    }
}