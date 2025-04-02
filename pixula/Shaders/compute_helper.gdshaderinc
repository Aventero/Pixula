float hash1D(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffff);
}

float random(ivec2 pos, int frame) {
    uint combined = uint((pos.x + frame) * 1973 + (pos.y + frame) * 9277);
    return hash1D(combined);
}

int random_range(ivec2 pos, int frame, int min_val, int max_val) {
    float rnd = random(pos, frame);
    int range = max_val - min_val + 1;
    return min_val + int(rnd * range);
}

bool chance(ivec2 pos, int frame, float probability) {
    return random(pos, frame) <= probability;
}

const int AIR = 0;
const int SAND = 1;
const int WATER = 2;
const int ROCK = 3;
const int WALL = 4;
const int WOOD = 5;
const int FIRE = 6;
const int WATER_VAPOR = 7;
const int WATER_CLOUD = 8;
const int LAVA = 9;
const int ACID = 10;
const int ACID_VAPOR = 11;
const int ACID_CLOUD = 12;
const int VOID = 13;
const int MIMIC = 14;
const int SEED = 15;
const int PLANT = 16;
const int POISON = 17;
const int ASH = 18;
const int OIL = 19;
const int EMBER = 20;
const int SMOKE = 21;

const int SOLID = 100;
const int LIQUID = 101;
const int GAS = 102;
const int UNSWAPPABLE = -999;

struct Pixel {
    int material;
    int frame;
    int color_index;
    float velocity_x;
    float velocity_y;
    int anything;
    float accumulated_velocity_x;
    float accumulated_velocity_y;
    float pressure_x;
    float pressure_y;
};