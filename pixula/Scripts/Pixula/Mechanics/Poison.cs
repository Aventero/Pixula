using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Poison(MainSharp main) : MaterialMechanic(main) 
    {
        public override bool Update(int x, int y, MaterialType material)
        {
            return false;
        }
    }
}