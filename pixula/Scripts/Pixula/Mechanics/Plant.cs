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

        private readonly GrowthMechanic growing = new(main);

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
            
            if (growing.IsNew(plant.various))
                return InitializeNewPlant(x, y, plant);

            plant = growing.TryAbsorb(x, y, plant, 2, MAX_GROWTH);

            if (growing.IsDisabled(plant.various))
                return true;

            return TryGrowPlant(x, y, plant);
        }

        private bool InitializeNewPlant(int x, int y, Pixel plant)
        {
            plant.various = GD.RandRange(2, MAX_GROWTH);
            Main.SetPixelAt(x, y, plant, Main.NextPixels);
            return true;
        }

        private bool TryGrowPlant(int x, int y, Pixel sourcePlant)
        {
            if (sourcePlant.various <= 1)
            {
                growing.Disable(x, y, sourcePlant);
                return true;
            }

            foreach (Vector2I direction in plantGrowingDirections)
            {
                Vector2I targetPos = new Vector2I(x, y) + direction;
                
                if (!plantGrowingDirectionsChance.TryGetValue(direction, out float growChance))
                    continue;

                if (!Chance(growChance))
                    continue;

                if (TryGrowNewPlant(targetPos.X, targetPos.Y, sourcePlant))
                {
                    sourcePlant = growing.Disable(x, y, sourcePlant);
                    return true;
                }
            }

            return growing.ShareGrowthToNeighbor(x, y, sourcePlant);
        }

        private bool TryGrowNewPlant(int targetX, int targetY, Pixel sourcePlant)
        {
            if (!CanGrowAt(new Vector2I(targetX, targetY)))
                return false;

            Pixel targetPixel = Main.GetPixel(targetX, targetY, Main.CurrentPixels);
            
            if (!Main.IsEmpty(targetPixel.material))
                return false;

            int newGrowth = sourcePlant.various - 1;
            Pixel newPlant = new(MaterialType.Plant, Main.GetRandomVariant(MaterialType.Plant), newGrowth);
            Main.SetPixelAt(targetX, targetY, newPlant, Main.NextPixels);
            return true;
        }

        private bool CanGrowAt(Vector2I growCheck)
        {
            // Check additional positions further left and right
            // X   X  -2
            // XXXXX  -1
            //  XXX   0
            //   P

            Vector2I[] checks = 
            [
                new Vector2I(0, 0), // Above
                new Vector2I(1, 0), // Above Right
                new Vector2I(-1, 0), // Above Left

                new Vector2I(0, -1), // Above Grow Spot
                new Vector2I(1, -1), // One Right and up
                new Vector2I(-1, -1), // One left and up
                new Vector2I(-2, -1), // Two left and up
                new Vector2I(2, -1),   // Two right and up

                // new Vector2I(2, -2),   // Two right and 2 up
                // new Vector2I(-2, -2),   // Two right and 2 up

            ];

            // Check standard 8 surrounding positions offset up by 1
            foreach (Vector2I direction in checks)
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

    }
}