using Pixula;


namespace Pixula.Mechanics
{
    public class Rock(MainSharp main) : MaterialMechanic(main) 
    {
        public override bool Update(int x, int y, MaterialType material)
        {
            return MoveDown(x, y, material);
        }
    }
}
