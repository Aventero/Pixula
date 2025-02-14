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
                Main.ConvertTo(x, y, MaterialType.Smoke);
                return true;
            }

            // Look for neighboring Water.
            if (ExtinguishFire(x, y))
                return true;

            // Spread to flammable materials
            SpreadFire(x, y, currentMaterial);

            // Do nothing
            if (Chance(0.5f))
                return true;

            // Try to move
            if (Chance(0.15f) && MoveDown(x, y, currentMaterial)) return true;

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
                
                if (Main.GetMaterialAt(checkX, checkY) == MaterialType.Water)
                {
                    Main.ConvertTo(x, y, MaterialType.WaterVapor);
                    Main.ConvertTo(checkX, checkY, MaterialType.WaterVapor);
                    return true;
                } 
            }
            return false;
        }

        public static bool IsFlammable(MaterialType processMaterial) 
        {
            return processMaterial switch
            {
                MaterialType.Wood => true,
                MaterialType.Seed => true,
                MaterialType.Plant => true,
                MaterialType.Poison => true,
                MaterialType.Oil => true,
                _ => false
            };
        }

        public static float BurnChance(MaterialType processMaterial)
        {
            return processMaterial switch
            {
                MaterialType.Wood => 0.5f,
                MaterialType.Seed => 0.25f,
                MaterialType.Plant => 0.5f,
                MaterialType.Poison => 0.4f,
                MaterialType.Oil => 1.0f,
                MaterialType.Ember => 0.1f,
                _ => 0f,
            };
        }

        public static MaterialType BurnProduct(MaterialType processMaterial)
        {
            return processMaterial switch
            {
                MaterialType.Wood => MaterialType.Ember,
                MaterialType.Seed => MaterialType.Ember,
                MaterialType.Plant => MaterialType.Ember,
                MaterialType.Poison => MaterialType.Air,
                MaterialType.Oil => MaterialType.Air,
                _ => MaterialType.Air,
            };
        }
    }
}

