using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Text.RegularExpressions;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Seed(MainSharp main) : MaterialMechanic(main) 
    {
        public override bool Update(int x, int y, MaterialType material)
        {
            // Check below the seed for potential growth conditions
            int checkBelow = y + 1;
            if (!Main.IsInBounds(x, checkBelow))
                return true;

            MaterialType belowMaterial = Main.GetMaterialAt(x, checkBelow);

            // Much lower overall chance of seed survival/growth
            if (Chance(0.005f))
            {
                // Most seeds will simply disappear
                Main.SetMaterialAt(x, y, MaterialType.Air, Main.NextPixels);
                return true;
            }

            if (IsGrowable(belowMaterial) && Chance(0.1f))
            {
                // Grow wood underneath the seed
                Main.SetMaterialAt(x, checkBelow, MaterialType.Wood, Main.NextPixels);
                
                // Convert seed to plant
                Main.SetMaterialAt(x, y, MaterialType.Plant, Main.NextPixels);
                
                return true;
            }

            // Optional: Water interaction
            int waterNeighborCount = CountAdjacentMaterials(x, y, MaterialType.Water);
            if (Chance(0.15f * waterNeighborCount) && IsGrowable(belowMaterial))
            {
                Main.SetMaterialAt(x, checkBelow, MaterialType.Wood, Main.NextPixels);
                Main.SetMaterialAt(x, y, MaterialType.Plant, Main.NextPixels);
                return true;
            }

            MoveDown(x, y, material);
            return true;
        }

        private int CountAdjacentMaterials(int x, int y, MaterialType materialToCount)
        {
            int count = 0;
            foreach (Vector2I direction in Main.Directions)
            {
                int checkX = x + direction.X;
                int checkY = y + direction.Y;
                
                if (!Main.IsInBounds(checkX, checkY))
                    continue;

                if (Main.GetMaterialAt(checkX, checkY) == materialToCount)
                    count++;
            }
            return count;
        }

        public static bool IsGrowable(MaterialType materialToTest)
        {
            return materialToTest switch 
            {
                MaterialType.Sand => true,
                MaterialType.Rock => true,
                _ => false
            };
        }
    }
}
