using System;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;
using Godot;
using GodotPlugins.Game;

namespace Pixula.Mechanics
{
    public class GrowthMechanic(MainSharp main)
    {
        private readonly MainSharp Main = main;

        private static readonly Vector2I[] ABSORB_DIRECTIONS = 
        [
            new Vector2I(0, -1),
            new Vector2I(0, 1),
            new Vector2I(-1, 0),
            new Vector2I(1, 0)
        ];

        private static readonly Vector2I[] GROWTH_SHARE_DIRECTIONS = 
        [
            new Vector2I(0, -1),   // UP
            new Vector2I(-1, -1),  // UP-left
            new Vector2I(1, -1),   // UP-right
            new Vector2I(1, 0),   // RIGHT
            new Vector2I(-1, 0),   // LEFT

            new Vector2I(0, -2),   // UP
            new Vector2I(-2, -2),  // UP-left
            new Vector2I(2, -2),   // UP-right
        ];

        public bool TryAbsorb(int x, int y, ref Pixel sourcePixel, int minGrowth, int maxGrowth)
        {

            // Pick randomly around source pixel
            Vector2I absorbPosition = ABSORB_DIRECTIONS[GD.RandRange(0, ABSORB_DIRECTIONS.Length - 1)] + new Vector2I(x, y);
            MaterialType targetMaterial = Main.GetMaterialAt(absorbPosition.X, absorbPosition.Y);

            if (!CanAbsorb(targetMaterial)) 
                return false; 
            
            // Absorb into the source pixel
            sourcePixel.various = GD.RandRange(minGrowth, maxGrowth);
            Main.SetPixelAt(x, y, sourcePixel, Main.NextPixels);

            // Convert absorbed material to air
            Main.ConvertTo(absorbPosition.X, absorbPosition.Y, MaterialType.Air);
            return true;
        }

        public bool ShareGrowthToNeighbor(int x, int y, ref Pixel sourcePixel)
        {
            // Random chance to disable
            if (MaterialMechanic.Chance(0.01f)) 
            {
                Disable(x, y, ref sourcePixel);
                return false;
            }

            // Check if source is now dry then disable
            if (Math.Abs(sourcePixel.various) <= 1)
            {
                Disable(x, y, ref sourcePixel);
                return true;
            }

            // Find all valid neighbors first
            List<Vector2I> validNeighbors = new();
            foreach (Vector2I dir in GROWTH_SHARE_DIRECTIONS.OrderBy(_ => Random.Shared.Next()))
            {
                Vector2I checkPos = new(x + dir.X, y + dir.Y);
                if (IsGrowthSharable(Main.GetMaterialAt(checkPos.X, checkPos.Y)))
                    validNeighbors.Add(checkPos);
            }

            if (validNeighbors.Count == 0)
                return false;

            int shareAmount = Math.Sign(sourcePixel.various);
            foreach (Vector2I neighborPos in validNeighbors)
            {
                Pixel neighbor = Main.GetPixel(neighborPos.X, neighborPos.Y, Main.CurrentPixels);

                // Has to be enabled and set with some growth
                if (IsDisabled(neighbor.various))
                {
                    neighbor.various = shareAmount;
                    Main.SetPixelAt(neighborPos.X, neighborPos.Y, neighbor, Main.NextPixels);
                }
                
                neighbor.various += shareAmount;
                sourcePixel.various -= shareAmount;
                Main.SetPixelAt(neighborPos.X, neighborPos.Y, neighbor, Main.NextPixels);

                // Check if source is now dry then disable
                if (ShouldStopGrowing(ref sourcePixel))
                {
                    Disable(x, y, ref sourcePixel);
                    return true;
                }
            }

            // Still has juice left, just set.
            Main.SetPixelAt(x, y, sourcePixel, Main.NextPixels);

            // Check if source is now dry then disable
            if (Math.Abs(sourcePixel.various) <= 0)
            {
                Disable(x, y, ref sourcePixel);
                return true;
            }
            return true;
        }

        public bool ShouldStopGrowing(ref Pixel sourcePixel)
        {
            return Math.Abs(sourcePixel.various) <= 1;
        }

        public Pixel Disable(int x, int y, ref Pixel sourcePixel)
        {
            sourcePixel.various = 100 * Math.Sign(sourcePixel.various);
            Main.SetPixelAt(x, y, sourcePixel, Main.NextPixels);
            return sourcePixel;
        }

        public bool IsDisabled(int value) => Math.Abs(value) >= 100;

        private bool IsGrowthSharable(MaterialType material)
        {
            return material switch
            {
                MaterialType.Wood => true,
                MaterialType.Plant => true,
                _ => false
            };
        }



        private static bool CanAbsorb(MaterialType material)
        {
            return material switch 
            {
                MaterialType.Water => true,
                MaterialType.Seed => true,
                _ => false
            };
        }
    }
}
