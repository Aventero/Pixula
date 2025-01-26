using System;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Cloud(MainSharp main) : MaterialMechanic(main) 
    {
        public override bool Update(int x, int y, MaterialType material)
        {
            return CloudMechanics(x, y, material);
        }

        private bool CloudMechanics(int x, int y, MaterialType processMaterial)
        {
            Main.ActivateCell(new Vector2I(x, y));

            // Chance to spawn water underneath
            if (Random.Shared.NextDouble() < 0.01f) 
            {
                if (!Main.IsInBounds(x, y + 1))
                    return true;
                    
                // Check if space below is empty
                if (Main.GetMaterialAt(x, y + 1) == MaterialType.Air)
                    Main.ConvertTo(x, y + 1, MaterialType.Water);
            }

            for (int i = 0; i < 2; i++) 
            {
                if (Main.AttractTowardsMaterial(x, y, 2, 8, MaterialType.WaterCloud))
                    return true;
            }

            // Dying with 0.5% chance per update
            if (Random.Shared.NextDouble() < 0.005f)
            {
                Main.ConvertTo(x, y, MaterialType.Air);
                return true;
            }

            // Do nothing
            if (Random.Shared.NextDouble() < 0.6f)
                return true;

            return MoveUp(x, y, processMaterial) || MoveDiagonalUp(x, y, processMaterial);
        }
    }
}
