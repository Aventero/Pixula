using System;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class AcidCloud(MainSharp main) : MaterialMechanic(main) 
    {
        public override bool Update(int x, int y, MaterialType material)
        {
            return AcidCloudMechanics(x, y, material);
        }

        private bool AcidCloudMechanics(int x, int y, MaterialType processMaterial)
        {
            Main.ActivateCell(new Vector2I(x, y));

            // Chance to spawn acid underneath
            if (Chance(0.005f)) 
            {
                if (!Main.IsInBounds(x, y + 1))
                    return true;

                // Check if space below is empty
                if (Main.GetMaterialAt(x, y + 1) == MaterialType.Air)
                    Main.ConvertTo(x, y + 1, MaterialType.Acid);
            }

            for (int i = 0; i < 2; i++) 
            {
                if (Main.AttractTowardsMaterial(x, y, 2, 8, MaterialType.AcidCloud))
                    return true;
            }

            // Dying with 0.25% chance per update
            if (Chance(0.0025f))
            {
                Main.ConvertTo(x, y, MaterialType.Air);
                return true;
            }

            // Do nothing
            if (Chance(0.4f))
                return true;

            return MoveUp(x, y, processMaterial) || MoveDiagonalUp(x, y, processMaterial);
        }
    }
}
