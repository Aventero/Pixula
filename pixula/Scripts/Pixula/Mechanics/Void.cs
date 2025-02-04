using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Void(MainSharp main) : MaterialMechanic(main) 
    {
        private Vector2I[] simpleDirections = 
        {
            Vector2I.Up,
            Vector2I.Down,
            Vector2I.Left,
            Vector2I.Right
        };

        public override bool Update(int x, int y, MaterialType material)
        {
            // Check surrounding pixels
            Vector2I checkLocation = simpleDirections[GD.RandRange(0, simpleDirections.Length - 1)] + new Vector2I(x, y);

            // Has to activate the location beyond the void spot.
            Vector2I furtherLocation = checkLocation + (checkLocation - new Vector2I(x, y));
            Main.ActivateCell(furtherLocation);

            MaterialType mat = Main.GetMaterialAt(checkLocation.X, checkLocation.Y);
            if (mat == MaterialType.Void || mat == MaterialType.Air)
                return true;

            Main.SetMaterialAt(checkLocation.X, checkLocation.Y, MaterialType.Air, Main.NextPixels);
            return true;
        }
    }
}
