using System;
using System.Collections.Generic;
using System.Linq;
using Godot;

namespace Pixula.Mechanics
{
    public class Wood(MainSharp main) : MaterialMechanic(main)
    {
        private const int MIN_ROOT_GROWTH = -1;
        private const int MAX_ROOT_GROWTH = -10;
        private const int MIN_STICK_GROWTH = 1;
        private const int MAX_STICK_GROWTH = 3;

        private readonly GrowthMechanic growing = new(main);

        private static readonly Vector2I[] ROOT_DIRECTIONS = 
        {
            new(0, 1),   // Down
            new(-1, 1),  // Down-left
            new(1, 1),   // Down-right
        };

        private static readonly Dictionary<Vector2I, float> STICK_GROWTH_CHANCES = new()
        {
            { new Vector2I(0, -1), 0.7f },  // UP
            { new Vector2I(-1, -1), 0.5f }, // UP LEFT
            { new Vector2I(1, -1), 0.5f },  // UP RIGHT
        };

        private static readonly Vector2I[] GROWTH_CHECK_POSITIONS = 
        {
            new(0, 0),    // Above
            new(-2, -1),  // Two left and up
            new(2, -1),   // Two right and up
            new(2, -2),   // Two right and 2 up
            new(-2, -2),  // Two left and 2 up
            new(0, -4),   // Four up
            new(0, -6),   // Six up
        };

        public override bool Update(int x, int y, MaterialType material)
        {
            Main.ActivateCell(new Vector2I(x, y));
            
            if (FallAsGroup(x, y, material))
                return false;

            Pixel sourcePixel = Main.GetPixel(x, y, Main.CurrentPixels);

            if (sourcePixel.various == 0)
                sourcePixel = InitializeGrowthDirection(sourcePixel, x, y);
            
            if (sourcePixel.various > 0)
                growing.TryAbsorb(x, y, ref sourcePixel, MIN_STICK_GROWTH, MAX_STICK_GROWTH);
            else if (sourcePixel.various < 0)
                growing.TryAbsorb(x, y, ref sourcePixel, MIN_ROOT_GROWTH, MAX_ROOT_GROWTH);

            if (growing.IsDisabled(sourcePixel.various))
                return true;

            if (sourcePixel.various > 0 )
                ProcessStickGrowth(x, y, sourcePixel);

            if (sourcePixel.various < 0)
                ProcessRootGrowth(x, y, sourcePixel);

            return growing.ShareGrowthToNeighbor(x, y, ref sourcePixel);
        }

        private Pixel InitializeGrowthDirection(Pixel pixel, int x, int y)
        {
            if (IsRootable(Main.GetMaterialAt(x, y + 1)))
                pixel.various = MAX_ROOT_GROWTH;
            
            if (IsStickable(Main.GetMaterialAt(x, y - 1)))
                pixel.various = MAX_STICK_GROWTH;

            Main.SetPixelAt(x, y, pixel, Main.NextPixels);
            return pixel;
        }

        private bool ProcessStickGrowth(int x, int y, Pixel sourcePixel)
        {
            if (sourcePixel.various <= MIN_STICK_GROWTH)
            {
                growing.Disable(x, y, ref sourcePixel);
                return false;
            }

            Vector2I stickDir = STICK_GROWTH_CHANCES.Keys.ToArray()[GD.RandRange(0, STICK_GROWTH_CHANCES.Count - 1)];
            Vector2I growthPos = new Vector2I(x, y) + stickDir;

            if (!STICK_GROWTH_CHANCES.TryGetValue(stickDir, out float chance) || !Chance(chance))
                return true;

            if (!CanGrowAt(growthPos, 1) || !IsStickable(Main.GetMaterialAt(growthPos.X, growthPos.Y)))
                return false;

            return GrowWood(x, y, growthPos, sourcePixel.various - 1);
        }

        private bool ProcessRootGrowth(int x, int y, Pixel sourcePixel)
        {
            if (sourcePixel.various >= MIN_ROOT_GROWTH)
            {
                growing.Disable(x, y, ref sourcePixel);
                return false;
            }

            Vector2I rootDir = ROOT_DIRECTIONS[GD.RandRange(0, ROOT_DIRECTIONS.Length - 1)];
            Vector2I growthPos = new Vector2I(x, y) + rootDir;

            if (!CanGrowAt(growthPos, -1) || !IsRootable(Main.GetMaterialAt(growthPos.X, growthPos.Y)))
                return false;

            return GrowWood(x, y, growthPos, sourcePixel.various + 1);
        }

        private bool GrowWood(int x, int y, Vector2I target, int growthValue)
        {
            // Create new wood with new growthValue
            Pixel newWood = new(MaterialType.Wood, Main.GetRandomVariant(MaterialType.Wood), growthValue);
            Main.SetPixelAt(target.X, target.Y, newWood, Main.NextPixels);

            // Disable Source pixel
            Pixel sourcePixel = Main.GetPixel(x, y, Main.CurrentPixels);
            growing.Disable(x, y, ref sourcePixel);
            return true;
        }


        private bool CanGrowAt(Vector2I growPos, int upDirection)
        {
            foreach (var checkOffset in GROWTH_CHECK_POSITIONS)
            {
                var checkPos = growPos + checkOffset * upDirection;
                if (Main.GetMaterialAt(checkPos.X, checkPos.Y) == MaterialType.Wood)
                    return false;
            }
            return true;
        }

        private static bool IsRootable(MaterialType material) => 
            material is MaterialType.Sand or MaterialType.Rock;

        private static bool IsStickable(MaterialType material) => 
            material is MaterialType.Air or MaterialType.Plant;
    }
}