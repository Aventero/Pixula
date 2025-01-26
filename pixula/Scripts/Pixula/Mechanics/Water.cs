using Pixula;


namespace Pixula.Mechanics
{
    public class Water(MainSharp main) : MaterialMechanic(main) 
    {
        public override bool Update(int x, int y, MaterialType material)
        {
            return MoveDown(x, y, material) ||
                MoveDiagonalDown(x, y, material) ||
                MoveHorizontal(x, y, material);
        }
    }
}
