float hash1D(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffff);
}

float random(ivec2 pos, int frame) {
    uint combined = uint((pos.x + frame) * 1973 + (pos.y + frame) * 9277);
    return hash1D(combined);
}