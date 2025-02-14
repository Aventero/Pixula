using Godot;


namespace Pixula.Mechanics
{
    public class Poison(MainSharp main) : MaterialMechanic(main) 
    {
        private int InitialPoison = 6;

        public override bool Update(int x, int y, MaterialType material)
        {

            Vector2I spreadPos = Main.Directions[GD.RandRange(0, Main.Directions.Length - 1)] + new Vector2I(x, y);
            MaterialType targetMaterial = Main.GetMaterialAt(spreadPos.X, spreadPos.Y);
            if (IsSpreadable(targetMaterial))
            {
                Pixel poisonPixel = new(MaterialType.Poison, Main.GetRandomVariant(MaterialType.Poison), InitialPoison);
                Main.SetPixelAt(spreadPos.X, spreadPos.Y, poisonPixel, Main.NextPixels);
                return true;
            }

            // Do nothing
            if (Chance(0.95f))
            {
                Main.ActivateCell(new Vector2I(x, y));
                return true;
            }

            Pixel sourcePixel = Main.GetPixel(x, y, Main.CurrentPixels);


            if (sourcePixel.various <= 3)
            {
                sourcePixel.various = InitialPoison;
                Main.SetPixelAt(x, y, sourcePixel, Main.NextPixels);
            }

            if (sourcePixel.various > 3)
            {
                sourcePixel.various -= 1;
                Main.SetPixelAt(x, y, sourcePixel, Main.NextPixels);
            }


            return MoveDown(x, y, material) || MoveDiagonalDown(x, y, material);
        }

        public static bool IsSpreadable(MaterialType materialToTest)
        {
            return materialToTest switch 
            {
                MaterialType.Wood => true,
                MaterialType.Plant => true,
                _ => false
            };
        }
    }
}
