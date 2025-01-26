using System;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Vapor(MainSharp main) : MaterialMechanic(main) 
    {
        public override bool Update(int x, int y, MaterialType material)
        {
            return VaporMechanics(x, y, material);
        }

        private bool VaporMechanics(int x, int y, MaterialType currentMaterial) 
        {
            Main.ActivateCell(new Vector2I(x, y));

            // Small chance to disappear
            if (Random.Shared.NextDouble() < 0.01f) 
            {
                Main.SetMaterialAt(x, y, MaterialType.Air, Main.NextPixels);
                return true;
            }

            for (int i = 0; i < 2; i++) 
            {
                if (Main.AttractTowardsMaterial(x, y, 2, 12, MaterialType.WaterVapor))
                    return true;
            }

            // Chance to turn itself to cloud, based on surroundings
            Main.FormCloud(x, y, MaterialType.WaterVapor, MaterialType.WaterCloud);
            // Do nothing -> slow
            if (Random.Shared.NextDouble() < 0.5f) return true;

            if (Random.Shared.NextDouble() < 0.8f && MoveUp(x, y, currentMaterial)) return true; 

            return MoveDiagonalUp(x, y, currentMaterial) || MoveHorizontal(x, y, currentMaterial);
        }
    }
}
