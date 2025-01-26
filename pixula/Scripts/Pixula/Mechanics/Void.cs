using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Void(MainSharp main) : MaterialMechanic(main) 
    {
        public override bool Update(int x, int y, MaterialType material)
        {
            // Check surrounding pixels
            Vector2I checkLocation = Main.Directions[GD.RandRange(0, 7)] + new Vector2I(x, y);
            if (!Main.IsInBounds(checkLocation.X, checkLocation.Y))
                return true;
            
            MaterialType mat = Main.GetMaterialAt(checkLocation.X, checkLocation.Y);
            if (mat == MaterialType.Void || mat == MaterialType.Air)
                return true;

            Main.SetMaterialAt(checkLocation.X, checkLocation.Y, MaterialType.Air, Main.NextPixels);
            return true;
        }
    }
}
