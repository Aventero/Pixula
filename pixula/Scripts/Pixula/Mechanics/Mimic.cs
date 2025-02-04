using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Mimic(MainSharp main) : MaterialMechanic(main) 
    {

        public static bool IsCopyable(MaterialType materialToTest)
        {
            return materialToTest switch 
            {
                MaterialType.Air => false,
                MaterialType.Wall => false,
                MaterialType.Mimic => false,
                _ => true
            };
        }

        public override bool Update(int x, int y, MaterialType material)
        {
            Pixel p = Main.GetPixel(x, y, Main.CurrentPixels);
            
            // Default is Air (unset)
            // Mimic has been set already -> return
            if (p.various != (int)MaterialType.Air)
            {
                if (Chance(0.7f)) return true;

                // Do the spawning
                Vector2I spawnLocation = Main.Directions[GD.RandRange(0, 7)] + new Vector2I(x, y);
                if (Main.IsInBounds(spawnLocation.X, spawnLocation.Y) && Main.GetMaterialAt(spawnLocation.X, spawnLocation.Y) == MaterialType.Air)
                    Main.SetMaterialAt(spawnLocation.X, spawnLocation.Y, (MaterialType)p.various, Main.NextPixels);

                return true;
            }

            // Check surrounding pixels
            Vector2I direction = Main.Directions[GD.RandRange(0, 7)];
            int checkX = x + direction.X;
            int checkY = y + direction.Y;
            
            if (!Main.IsInBounds(checkX, checkY)) return true;

            MaterialType possibleCopyMaterial = Main.GetMaterialAt(checkX, checkY);
            
            if (!IsCopyable(possibleCopyMaterial)) return true;
            
            p.various = (int)possibleCopyMaterial;
            Main.SetPixelAt(x, y, p, Main.NextPixels);
            return true;
        }

        
    }
}
