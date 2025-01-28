using System;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Wood(MainSharp main) : MaterialMechanic(main) 
    {
        public override bool Update(int x, int y, MaterialType material)
        {
            return WoodMechanics(x, y, material);
        }

        private bool WoodMechanics(int x, int y, MaterialType currentMaterial)
        {

            // Very high chance to do nothing
            if (Chance(0.995f))
            {
                Main.ActivateCell(new Vector2I(x, y));
                return true;
            }
            
            // GROW!
            int randomDirection = Random.Shared.Next(0, Main.Directions.Length);
            Vector2I checkPosition = Main.Directions[randomDirection] + new Vector2I(x, y);

            if (!Main.IsInBounds(checkPosition.X, checkPosition.Y))
                return false;
            

            MaterialType mat = Main.GetMaterialAt(checkPosition.X, checkPosition.Y);
            if (IsGrowable(mat))
            {
                Main.ConvertTo(checkPosition.X, checkPosition.Y, MaterialType.Wood);
                return true;
            }

            return false;
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
