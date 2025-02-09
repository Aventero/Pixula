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
            MaterialType belowMaterial = Main.GetMaterialAt(x, checkBelow);

            CanGrowMore(x, y, material);

            if (IsGrowable(belowMaterial) && Chance(0.5f))
            {
                Main.ConvertTo(x, y, MaterialType.Plant);
                return true;
            }

            if (IsGrowable(belowMaterial) && Chance(0.25f))
            {
                Main.SetMaterialAt(x, checkBelow, MaterialType.Wood, Main.NextPixels);
                Main.SetMaterialAt(x, y - 1, MaterialType.Wood, Main.NextPixels);
                return true;   
            }

            if (Chance(0.9f)) return MoveDown(x, y, material);
            return MoveDiagonalDown(x, y, material);
        }

        private int CountAdjacentMaterials(int x, int y, MaterialType materialToCount)
        {
            int count = 0;
            foreach (Vector2I direction in Main.Directions)
            {
                int checkX = x + direction.X;
                int checkY = y + direction.Y;
                
                if (Main.GetMaterialAt(checkX, checkY) == materialToCount)
                    count++;
            }
            return count;
        }

        private bool CanGrowMore(int x, int y, MaterialType material)
        {
            int plantCount = CountAdjacentMaterials(x, y, MaterialType.Plant);
            int woodCount = CountAdjacentMaterials(x, y, MaterialType.Wood);
            
            return (material == MaterialType.Plant && plantCount < 2) || 
                (material == MaterialType.Wood && woodCount < 1);
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
