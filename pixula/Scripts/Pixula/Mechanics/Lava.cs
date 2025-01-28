using System;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Lava(MainSharp main) : MaterialMechanic(main) 
    {
        public override bool Update(int x, int y, MaterialType material)
        {
            return LavaMechanics(x, y, material);
        }

        private bool LavaMechanics(int x, int y, MaterialType currentMaterial)
        {

            // Look for neighboring Water.
            if (ExtinguishLava(x, y))
                return false; // was extinguished

            // Spread to flammable materials
            Main.SpreadFire(x, y);

            if (Chance(0.7f) && MoveDown(x, y, currentMaterial))
                return true;

            // Do nothing
            if (Chance(0.7f))
            {
                Main.ActivateCell(new Vector2I(x, y));
                return false;
            }

            return MoveDiagonalDown(x, y, currentMaterial) || MoveHorizontal(x, y, currentMaterial);
        }

    	public bool ExtinguishLava(int x, int y) 
        {
            foreach (Vector2I direction in Main.Directions) 
            {
                int checkX = x + direction.X;
                int checkY = y + direction.Y;
                if (!Main.IsInBounds(checkX, checkY))
                    continue;
                
                if (Main.GetMaterialAt(checkX, checkY) == MaterialType.Water)
                {
                    if (Chance(0.1f)) Main.ConvertTo(x, y, MaterialType.Rock);
                    Main.ConvertTo(checkX, checkY, MaterialType.WaterVapor);

                    foreach (Vector2I dirAroundWater in Main.Directions)
                    {
                        int checkVaporX = checkX + dirAroundWater.X;
                        int checkVaporY = checkY + dirAroundWater.Y;
                        if (!Main.IsInBounds(checkVaporX, checkVaporY))
                            continue;

                        if (Main.GetMaterialAt(checkVaporX, checkVaporY) == MaterialType.Air)
                            Main.ConvertTo(checkVaporX, checkVaporY, MaterialType.WaterVapor);
                    }
                    return true;
                } 
            }
            return false;
        }
    }
}
