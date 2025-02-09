using System;
using Godot;
using Godot.Bridge;

namespace Pixula.Mechanics
{
    public abstract class MaterialMechanic(MainSharp main)
    {
        protected MainSharp Main { get; } = main;

        public abstract bool Update(int x, int y, MaterialType material);

        public bool MoveHorizontal(int x, int y, MaterialType processMaterial)
        {
            // Direction not yet set.
            Pixel p = Main.GetPixel(x, y, Main.CurrentPixels);
            if (p.various == 0)
            {
                int xDirection = y % 2 == 0 ? 1 : -1;
                p.various = xDirection;
            }

            // Various is the direction
            // Try moving into the direction
            bool ableToMoveHorizontal = Main.MoveTo(x, y, x + p.various, y, processMaterial);

            if (!ableToMoveHorizontal)
            {
                // Bounce!
                p.various *= -1;
                Main.SetPixelAt(x, y, p, Main.NextPixels);
                return true;
            }

            return ableToMoveHorizontal;
        }

        public bool MoveDown(int x, int y, MaterialType processMaterial)
        {
            return Main.MoveTo(x, y, x, y + 1, processMaterial);
        }

        public bool MoveUp(int x, int y, MaterialType processMaterial)
        {
            return Main.MoveTo(x, y, x, y - 1, processMaterial);
        }

        public bool MoveDiagonalDown(int x, int y, MaterialType processMaterial)
        {
            Vector2I direction = (x + y) % 2 == 0 ? new Vector2I(-1, 1) : new Vector2I(1, 1);
            Vector2I newPos = new Vector2I(x, y) + direction;
            return Main.MoveTo(x, y, newPos.X, newPos.Y, processMaterial);
        }

        public bool MoveDiagonalUp(int x, int y, MaterialType processMaterial)
        {
            Vector2I direction = (x + y) % 2 == 0 ? new Vector2I(-1, -1) : new Vector2I(1, -1);
            Vector2I newPos = new Vector2I(x, y) + direction;
            return Main.MoveTo(x, y, newPos.X, newPos.Y, processMaterial);
        }

        public static bool Chance(float probability)
        {
            return Random.Shared.NextSingle() < probability;
        }

        Vector2I[] groupFallDirections = 
        [
            new Vector2I(0, 1),   // Down
            new Vector2I(-1, 1),  // Down-left
            new Vector2I(1, 1),   // Down-right
        ];

        public bool FallAsGroup(int x, int y, MaterialType sourceMaterial)
        {
            bool hasAnySupport = false;
            
            foreach (Vector2I dir in groupFallDirections)
            {
                Vector2I woodLocation = new(dir.X + x, dir.Y + y);
                
                // Check if there's support at this position
                if (Main.GetMaterialAt(woodLocation.X, woodLocation.Y) == sourceMaterial)
                {
                    hasAnySupport = true;
                    break; // Found support, no need to check further
                }
            }

            // If no support was found, move down
            if (!hasAnySupport)
            {
                return MoveDown(x, y, sourceMaterial);
            }

            return false;
        }
    
    

    }
}
