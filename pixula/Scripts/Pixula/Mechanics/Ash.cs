using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Ash(MainSharp main) : MaterialMechanic(main) 
    {
        private static readonly Vector2I[] WATER_ABSORB_DIRECTIONS = 
        [
            new Vector2I(0, -1),
            new Vector2I(0, 1),
            new Vector2I(-1, 0),
            new Vector2I(1, 0)
        ];

        public override bool Update(int x, int y, MaterialType material)
        {

            Vector2I absorbPosition = WATER_ABSORB_DIRECTIONS[GD.RandRange(0, WATER_ABSORB_DIRECTIONS.Length - 1)] + new Vector2I(x, y);
            MaterialType targetMaterial = Main.GetMaterialAt(absorbPosition.X, absorbPosition.Y);
            
            if (targetMaterial == MaterialType.Water)
            {
                Main.ConvertTo(absorbPosition.X, absorbPosition.Y, MaterialType.Sand);
                Main.ConvertTo(x, y, MaterialType.Air);
            }

            // Do nothing
            if (Chance(0.55f))
            {
                Main.ActivateCell(new Godot.Vector2I(x, y));
                return true;
            }



            if (Chance(0.7f)) return MoveDown(x, y, material);
            return MoveDiagonalDown(x, y, material);
        }
    }
}
