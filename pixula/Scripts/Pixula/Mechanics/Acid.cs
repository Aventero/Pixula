using System;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Acid(MainSharp main) : MaterialMechanic(main) 
    {
        public override bool Update(int x, int y, MaterialType material)
        {
            return AcidMechanics(x, y, material);
        }

        private bool AcidMechanics(int x, int y, MaterialType currentMaterial)
        {
            if (MoveDown(x, y, currentMaterial)) return true;
            // Do nothing
            if (Chance(0.8f))
            {
                Main.ActivateCell(new Vector2I(x, y));
                return false;
            }
            
            // Can't move? Try dissolving what's below
            int newX = x;
            int newY = y + 1;
            if (Chance(0.2f) && IsDissolvable(Main.GetMaterialAt(newX, newY)))
            {
                Main.ConvertTo(newX, newY, MaterialType.AcidVapor);

                // Chance to Disappear
                if (Chance(0.25f)) Main.ConvertTo(x, y, MaterialType.Air);
                return true;
            }

            // Try diagonal movement/dissolving
            var direction = (x + y) % 2 == 0 ? new Vector2I(-1, 1) : new Vector2I(1, 1);
            var newPos = new Vector2I(x, y) + direction;
            if (Main.MoveTo(x, y, newPos.X, newPos.Y, currentMaterial)) return true;
            if (IsDissolvable(Main.GetMaterialAt(newPos.X, newPos.Y)))
            {
                Main.ConvertTo(newPos.X, newPos.Y, MaterialType.AcidVapor);
                
                // Chance to Disappear
                if (Chance(0.25f)) Main.ConvertTo(x, y, MaterialType.Air);
                return true;
            }

            // Try horizontal movement/dissolving
            int xDirection = y % 2 == 0 ? 1 : -1;
            newX = x + xDirection;
            if (Main.MoveTo(x, y, newX, y, currentMaterial)) return true;
            if (IsDissolvable(Main.GetMaterialAt(newX, y)))
            {
                Main.ConvertTo(newX, y, MaterialType.AcidVapor);

                // Chance to Disappear
                if (Chance(0.25f)) Main.ConvertTo(x, y, MaterialType.Air);
                return true;
            }

            return false;
        }

        public static bool IsDissolvable(MaterialType processMaterial) 
        {
            return processMaterial switch
            {
                MaterialType.Acid => false,
                MaterialType.Water => false,
                MaterialType.Lava => false,
                MaterialType.Air => false,
                MaterialType.Wall => false,
                MaterialType.Mimic => false,
                MaterialType.Void => false,
                _ => true
            };
        }
    }
}
