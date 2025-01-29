using System;
using System.Collections.Generic;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Wood(MainSharp main) : MaterialMechanic(main) 
    {

        // Lower limit (not zero as that would mean its initialized)
        private int MinRootGrowStop = -1;
        private int MaxRootGrowths = -3;

        private int MinStickGrowStop = 1;
        private int MaxStickGrowths = 3;
        public override bool Update(int x, int y, MaterialType material)
        {
            return WoodMechanics(x, y, material);
        }

        private bool WoodMechanics(int x, int y, MaterialType currentMaterial)
        {

            // Very high chance to do nothing
            if (Chance(0.95f))
            {
                Main.ActivateCell(new Vector2I(x, y));
                return true;
            }


            // This Wood, where wood is growing from.
            Pixel sourcePixel = Main.GetPixel(x, y, Main.CurrentPixels);

            // This tells if it will grow Sticks or Roots
            if (sourcePixel.various == 0)
            {
                if (Main.IsInBounds(x, y + 1) && IsRootable(Main.GetMaterialAt(x, y + 1)))
                    sourcePixel.various = MaxRootGrowths;
            }

            if (sourcePixel.various > 0)
            {
                // GROW UP
            }

            if (sourcePixel.various < 0)
            {
                // GROW DOWN
                Vector2I growCheck =  new Vector2I(x, y) + rootDirections[GD.RandRange(0, rootDirections.Length - 1)];
                if (!Main.IsInBounds(growCheck.X, growCheck.Y))
                    return false;

                if (!CanGrowAt(growCheck))
                    return false;

                MaterialType mat = Main.GetMaterialAt(growCheck.X, growCheck.Y);
                if (IsRootable(mat))
                {
                    if (sourcePixel.various < MinRootGrowStop) 
                    {
                        // Update source pixel
                        sourcePixel.various += 1;
                        Main.SetPixel(x, y, sourcePixel, Main.NextPixels);

                        // Grow a new pixel at the growth position
                        if (Chance(0.55f))
                            Main.ConvertTo(growCheck.X, growCheck.Y, MaterialType.Wood);

                        return true;
                    }

                    // Has Grown MaxPossibleGrowths
                    return true;
                }
            }

            return false;
        }

        private bool CanGrowAt(Vector2I growCheck)
        {
            // S = Soil, W = Wood
            // S W W -> NO
            // W W S -> NO
            // S W S -> YES

            return Main.IsInBounds(growCheck.X - 1, growCheck.Y) && 
                    Main.IsInBounds(growCheck.X + 1, growCheck.Y) && 
                    Main.GetMaterialAt(growCheck.X - 1, growCheck.Y) != MaterialType.Wood && 
                    Main.GetMaterialAt(growCheck.X + 1, growCheck.Y) != MaterialType.Wood;
        }

        public static bool IsRootable(MaterialType materialToTest)
        {
            return materialToTest switch 
            {
                MaterialType.Sand => true,
                MaterialType.Rock => true,
                _ => false
            };
        }

        private static Vector2I[] rootDirections =
        [
            new Vector2I(0, 1),   // Down
            new Vector2I(-1, 1),  // Down-left
            new Vector2I(1, 1),   // Down-right
            new Vector2I(-1, 0),   // Left
            new Vector2I(1, 0),   // Right
        ];

        private static Vector2I[] stickDirections =
        [
            new Vector2I(0, -1),   // UP
            new Vector2I(-1, -1),  // UP-left
            new Vector2I(1, -1),   // UP-right
            new Vector2I(-1, 0),   // Left
            new Vector2I(1, 0),   // Right
        ];
    }
}
