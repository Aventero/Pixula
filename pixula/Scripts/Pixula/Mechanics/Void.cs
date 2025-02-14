using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Void(MainSharp main) : MaterialMechanic(main) 
    {
        private static Vector2I[] simpleDirections =
        [
            new Vector2I(0, -1),   // UP
            new Vector2I(0, 1),   // DOWN
            new Vector2I(1, 0),   // Right
            new Vector2I(-1, 0),   // Left
        ];

        public override bool Update(int x, int y, MaterialType material)
        {
            foreach (Vector2I dir in simpleDirections)
            {
                // Check surrounding pixels
                Vector2I checkLocation = dir + new Vector2I(x, y);

                // Has to activate the location beyond the void spot.
                Vector2I furtherLocation = checkLocation + (checkLocation - new Vector2I(x, y));
                Main.ActivateCell(furtherLocation);

                MaterialType mat = Main.GetMaterialAt(checkLocation.X, checkLocation.Y);
                if (mat == MaterialType.Void || mat == MaterialType.Air)
                    continue;

                Main.ConvertTo(checkLocation.X, checkLocation.Y, MaterialType.Air);
            }

            return true;
         
        }
    }
}
