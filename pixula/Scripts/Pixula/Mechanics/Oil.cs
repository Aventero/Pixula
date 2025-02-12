using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Oil(MainSharp main) : MaterialMechanic(main) 
    {
        public override bool Update(int x, int y, MaterialType material)
        {
           return MoveDown(x, y, material) ||
                MoveDiagonalDown(x, y, material) ||
                MoveHorizontal(x, y, material);
        }
    }
}
