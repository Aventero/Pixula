using System;
using System.Numerics;
using Godot;
using GodotPlugins.Game;

namespace Pixula.Mechanics
{
    public class GrowthMechanic(MainSharp main)
    {
        private readonly MainSharp main = main;

        private static readonly Vector2I[] ABSORB_DIRECTIONS = 
        [
            new Vector2I(0, -1),
            new Vector2I(0, 1),
            new Vector2I(-1, 0),
            new Vector2I(1, 0)
        ];

        private static readonly Vector2I[] GROWTH_SHARE_DIRECTIONS = 
        [
            // new Vector2I(-1, 1),  // DOWN-left
            // new Vector2I(1, 1),   // DOWN-right
            // new Vector2I(0, 1),   // DOWN
            new Vector2I(0, -1),   // UP
            new Vector2I(-1, -1),  // UP-left
            new Vector2I(1, -1),   // UP-right
            new Vector2I(1, 0),   // RIGHT
            new Vector2I(-1, 0),   // LEFT

            new Vector2I(0, -2),   // UP
            new Vector2I(-2, -2),  // UP-left
            new Vector2I(2, -2),   // UP-right
        ];

        public Pixel TryAbsorb(int x, int y, Pixel sourcePixel, int minGrowth, int maxGrowth)
        {
            // Pick randomly around source pixel
            Vector2I absorbPosition = ABSORB_DIRECTIONS[GD.RandRange(0, ABSORB_DIRECTIONS.Length - 1)] + new Vector2I(x, y);
            MaterialType targetMaterial = main.GetNewMaterialAt(absorbPosition.X, absorbPosition.Y);

            if (!CanAbsorb(targetMaterial)) return sourcePixel; 
            
            // Absorb into the source pixel
            sourcePixel.various = GD.RandRange(minGrowth, maxGrowth);
            main.SetPixelAt(x, y, sourcePixel, main.NextPixels);

            // Convert absorbed material to air
            main.ConvertTo(absorbPosition.X, absorbPosition.Y, MaterialType.Air);
            
            return sourcePixel;
        }

        public Pixel Disable(int x, int y, Pixel growable)
        {
            growable.various = 100 * Math.Sign(growable.various);
            main.SetPixelAt(x, y, growable, main.NextPixels);
            return growable;
        }

        public bool IsDisabled(int various) => various < -99 || various >= 99;

        public bool IsNew(int various) => various == 0;

        private bool IsGrowthSharable(MaterialType material)
        {
            return material switch
            {
                MaterialType.Wood => true,
                MaterialType.Plant => true,
                _ => false
            };
        }

        public bool ShareGrowthToNeighbor(int x, int y, Pixel sourcePixel)
        {
            if (MaterialMechanic.Chance(0.01f)) 
            {
                Disable(x, y, sourcePixel);
                return false;
            }

            int growDir = Math.Sign(sourcePixel.various);
            Vector2I checkPos = growDir * GROWTH_SHARE_DIRECTIONS[Random.Shared.Next(0, GROWTH_SHARE_DIRECTIONS.Length)] + new Vector2I(x, y);
            MaterialType checkMaterial = main.GetMaterialAt(checkPos.X, checkPos.Y);

            if (!IsGrowthSharable(checkMaterial)) 
                return false;

            Pixel growable = main.GetPixel(checkPos.X, checkPos.Y, main.CurrentPixels);
            growable.various = sourcePixel.various;
            main.SetPixelAt(checkPos.X, checkPos.Y, growable, main.NextPixels);
            Disable(x, y, sourcePixel);
            return true;
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
