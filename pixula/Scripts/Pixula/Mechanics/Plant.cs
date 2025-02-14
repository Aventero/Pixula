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
        private const int GROWTH = 3;

        private readonly GrowthMechanic growing = new(main);

        public override bool Update(int x, int y, MaterialType material)
        {
            Main.ActivateCell(new Vector2I(x, y));

            if (FallAsGroup(x, y, material))
                return true;

            Pixel sourcePixel = Main.GetPixel(x, y, Main.CurrentPixels);

            if (sourcePixel.various == 0)
            {
                InitializeNewPlant(x, y, sourcePixel);
                return true;
            }

            if (growing.TryAbsorb(x, y, ref sourcePixel, 2, GROWTH))
                return true;

            if (growing.ShouldStopGrowing(ref sourcePixel))
                growing.Disable(x, y, ref sourcePixel);

            if (growing.IsDisabled(sourcePixel.various))
                return true;

            if (TryGrowPlant(x, y, ref sourcePixel))
            {
                growing.Disable(x, y, ref sourcePixel);
                return true;
            }

            growing.ShareGrowthToNeighbor(x, y, ref sourcePixel);
            return true;
        }

        private bool TryGrowPlant(int x, int y, ref Pixel sourcePlant)
        {
            foreach (Vector2I direction in plantGrowingDirections)
            {
                Vector2I targetPos = new Vector2I(x, y) + direction;
                
                if (!CanGrowAt(targetPos, direction))
                    continue;

                if (GrowPlant(targetPos.X, targetPos.Y, ref sourcePlant))
                    return true;
            }

            return false;
        }

        private bool GrowPlant(int targetX, int targetY, ref Pixel sourcePlant)
        {
            Pixel targetPixel = Main.GetPixel(targetX, targetY, Main.CurrentPixels);
            
            if (!Main.IsEmpty(targetPixel.material))
                return false;

            sourcePlant.various -= 1;
            Pixel newPlant = new(MaterialType.Plant, Main.GetRandomVariant(MaterialType.Plant), sourcePlant.various);
            Main.SetPixelAt(targetX, targetY, newPlant, Main.NextPixels);
            return true;
        }

        private void InitializeNewPlant(int x, int y, Pixel plant)
        {
            plant.various = GD.RandRange(2, GROWTH);
            Main.SetPixelAt(x, y, plant, Main.NextPixels);
        }

        private bool CanGrowAt(Vector2I growCheck, Vector2I growingDirection)
        {
             if (!plantGrowingDirectionsChance.TryGetValue(growingDirection, out float growChance))
                 return false;

             if (!Chance(growChance))
                 return false;

            // Check standard 8 surrounding positions offset up by 1
            foreach (Vector2I direction in growthChecks)
            {
                Vector2I checkPos = growCheck + direction;
                if (Main.GetMaterialAt(checkPos.X, checkPos.Y) == MaterialType.Plant)
                    return false;
            }

            return true;
        }

 
        private static Dictionary<Vector2I, float> plantGrowingDirectionsChance = new()
        {
            { new Vector2I(0, -1), 0.2f}, // UP
            { new Vector2I(0, 1), 1.0f}, // DOWN

            { new Vector2I(-1, -1), 0.5f}, // UP LEFT
            { new Vector2I(1, -1), 0.5f}, // UP RIGHT
        };

        private static Vector2I[] plantGrowingDirections =
        [
            new Vector2I(0, -1),   // UP
            new Vector2I(0, 1),   // DOWN

            new Vector2I(-1, -1),  // UP-left
            new Vector2I(1, -1),   // UP-right
        ];

        Vector2I[] growthChecks = 
        [
            new Vector2I(0, 0), // Above
            new Vector2I(1, 0), // Above Right
            new Vector2I(-1, 0), // Above Left

            new Vector2I(0, -1), // Above Grow Spot
            new Vector2I(1, -1), // One Right and up
            new Vector2I(-1, -1), // One left and up
            new Vector2I(-2, -1), // Two left and up
            new Vector2I(2, -1),   // Two right and up
        ];

    }
}