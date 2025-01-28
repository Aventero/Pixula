using System;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Fire(MainSharp main) : MaterialMechanic(main) 
    {
        public override bool Update(int x, int y, MaterialType material)
        {
            return FireMechanic(x, y, material);
        }

        private bool FireMechanic(int x, int y, MaterialType currentMaterial)
        {
            // Always keep fire active!
            Main.ActivateCell(new Vector2I(x, y));

            // Chance to go out
            if (Chance(0.025f))
            {
                Main.ConvertTo(x, y, MaterialType.Air);
                return true;
            }

            // Look for neighboring Water.
            if (ExtinguishFire(x, y))
                return true;

            // Spread to flammable materials
            Main.SpreadFire(x, y);

            // Do nothing
            if (Chance(0.3f))
                return true;

            // Try to move
            if (Chance(0.1f) && MoveDown(x, y, currentMaterial)) return true;

            // Try to move
            if (Chance(0.6f) && MoveUp(x, y, currentMaterial)) return true;
                
            if (MoveDiagonalUp(x, y, currentMaterial)) return true;
            
            if (MoveHorizontal(x, y, currentMaterial)) return true;

            return false;
        }

        private bool ExtinguishFire(int x, int y) 
        {
            foreach (Vector2I direction in Main.Directions) 
            {
                var checkX = x + direction.X;
                var checkY = y + direction.Y;
                if (!Main.IsInBounds(checkX, checkY))
                    continue;
                
                if (Main.GetMaterialAt(checkX, checkY) == MaterialType.Water)
                {
                    Main.ConvertTo(x, y, MaterialType.WaterVapor);
                    Main.ConvertTo(checkX, checkY, MaterialType.WaterVapor);
                    return true;
                } 
            }
            return false;
        }
    }
}

