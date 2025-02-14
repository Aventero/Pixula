using System;
using System.Collections.Generic;
using System.Linq;
using Godot;

namespace Pixula.Mechanics
{
    public class Wood(MainSharp main) : MaterialMechanic(main)
    {
        private const int MAX_ROOT_GROWTH = -10;
        private const int MAX_STICK_GROWTH = 10;

        private readonly GrowthMechanic growing = new(main);

        private static Vector2I[] ROOT_GROW_DIRECTIONS =
        [
            new Vector2I(0, 1), // DOWN
            new Vector2I(-1, 1), // DOWN LEFT
            new Vector2I(1, 1), // DOWN RIGHT
        ];

        private static Vector2I[] STICK_GROW_DIRECTIONS =
        [
            new Vector2I(0, -1), // DOWN
            new Vector2I(-1, -1), // DOWN LEFT
            new Vector2I(1, -1), // DOWN RIGHT
        ];

        private static readonly Dictionary<Vector2I, float> GROWTH_CHANCES = new()
        {
            { new Vector2I(0, -1), 0.7f },  // UP
            { new Vector2I(-1, -1), 0.5f }, // UP LEFT
            { new Vector2I(1, -1), 0.5f },  // UP RIGHT
            { new Vector2I(0, 1), 0.7f },  // DOWN
            { new Vector2I(-1, 1), 0.5f }, // DOWN LEFT
            { new Vector2I(1, 1), 0.5f },  // DOWN RIGHT
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
            {
                InitializeGrowthDirection(x, y, ref sourcePixel);
                return true;
            }
            
            if (sourcePixel.various > 0)
                growing.TryAbsorb(x, y, ref sourcePixel, 2, MAX_STICK_GROWTH);
            else if (sourcePixel.various < 0)
                growing.TryAbsorb(x, y, ref sourcePixel, -2, MAX_ROOT_GROWTH);

            if (GrowthMechanic.ShouldStopGrowing(ref sourcePixel))
                growing.Disable(x, y, ref sourcePixel);

            if (GrowthMechanic.IsDisabled(sourcePixel.various))
                return true;

            if (TryGrowWood(x, y, ref sourcePixel))
            {
                growing.Disable(x, y, ref sourcePixel);
                return true;
            }
            
            return growing.ShareGrowthToNeighbor(x, y, ref sourcePixel);
        }

        private void InitializeGrowthDirection(int x, int y, ref Pixel pixel)
        {
            if (IsRootable(Main.GetMaterialAt(x, y + 1)))
                pixel.various = MAX_ROOT_GROWTH;
            
            if (IsStickable(Main.GetMaterialAt(x, y - 1)))
                pixel.various = MAX_STICK_GROWTH;

            Main.SetPixelAt(x, y, pixel, Main.NextPixels);
        }


        private bool TryGrowWood(int x, int y, ref Pixel sourcePixel)
        {
            int upDirection = Mathf.Sign(sourcePixel.various);
            Vector2I woodDir;
            if (upDirection == 1)
                woodDir = STICK_GROW_DIRECTIONS[GD.RandRange(0, STICK_GROW_DIRECTIONS.Length - 1)];
            else
                woodDir = ROOT_GROW_DIRECTIONS[GD.RandRange(0, ROOT_GROW_DIRECTIONS.Length - 1)];

            Vector2I growthPos = woodDir + new Vector2I(x, y);

            if (!GROWTH_CHANCES.TryGetValue(woodDir, out float chance))
                return false;
            
            if (!Chance(chance))
                return false;

            if (!CanGrowAt(growthPos, upDirection))
                return false;
            
            GrowWood(growthPos, ref sourcePixel);
            return true;
        }

        private void GrowWood(Vector2I target, ref Pixel sourcePixel)
        {
            sourcePixel.various -= Math.Sign(sourcePixel.various);
            
            // Create new wood with new growthValue
            Pixel newWood = new(MaterialType.Wood, Main.GetRandomVariant(MaterialType.Wood), sourcePixel.various);
            Main.SetPixelAt(target.X, target.Y, newWood, Main.NextPixels);
        }

        private bool CanGrowAt(Vector2I growPos, int upDirection)
        {
            MaterialType materialAtGrowthSpot = Main.GetMaterialAt(growPos.X, growPos.Y);

            if (!IsStickable(materialAtGrowthSpot) && !IsRootable(materialAtGrowthSpot))
                return false;

            foreach (Vector2I checkOffset in GROWTH_CHECK_POSITIONS)
            {
                Vector2I checkPos = growPos + checkOffset * upDirection;
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