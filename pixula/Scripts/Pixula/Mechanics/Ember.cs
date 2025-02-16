using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using Godot;
using Pixula;


namespace Pixula.Mechanics
{
    public class Ember(MainSharp main) : MaterialMechanic(main) 
    {
        private readonly int MIN_BURN_TICKS = 10;
        private readonly int MAX_BURN_TICKS = 50;


        public override bool Update(int x, int y, MaterialType material)
        {
            Pixel pixel = Main.GetPixel(x, y, Main.CurrentPixels);
            if (pixel.various == 0)
            {
                // Not initialized yet
                pixel.various = Random.Shared.Next(MIN_BURN_TICKS, MAX_BURN_TICKS);
                Main.SetPixelAt(x, y, pixel, Main.NextPixels);
            }


            // while various is >= 1, spawn fire
            if (pixel.various > MIN_BURN_TICKS && Chance(0.25f))
            {
                // Update the value
                pixel.various -= 1;
                Main.SetPixelAt(x, y, pixel, Main.NextPixels);

                SpreadFire(x, y, MaterialType.Ember, true);
                return MoveDown(x, y, material) || MoveDiagonalDown(x, y, material);
            }

            if (pixel.various <= MIN_BURN_TICKS)
            {

                // End of its lifetime
                if (Chance(0.5f))
                    Main.ConvertTo(x, y, MaterialType.Ash);
                else
                    Main.ConvertTo(x, y, MaterialType.Air);
                
                return true;
            }

            return MoveDown(x, y, material) || MoveDiagonalDown(x, y, material);
        }
    }
}
