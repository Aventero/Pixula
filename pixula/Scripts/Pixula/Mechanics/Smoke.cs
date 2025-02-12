namespace Pixula.Mechanics
{
    public class Smoke(MainSharp main) : MaterialMechanic(main) 
    {
        public override bool Update(int x, int y, MaterialType material)
        {

            Main.ActivateCell(new Godot.Vector2I(x, y));

            // Small chance to disappear
            if (Chance(0.02f)) 
            {
                Main.SetMaterialAt(x, y, MaterialType.Air, Main.NextPixels);
                return true;
            }
            
            if (Chance(0.5f))
                return true;

            if (Chance(0.5f)) return MoveUp(x, y, material);
            if (Chance(0.5f)) return MoveDiagonalUp(x, y, material);
            return MoveHorizontal(x, y, material);
        }
    }
}
