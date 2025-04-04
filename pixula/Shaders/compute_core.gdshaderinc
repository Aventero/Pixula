// Locking via setting the material type
bool lockPixel(uint index, int expected_material) {
    int original = atomicCompSwap(output_buffer.pixels[index].material, expected_material, UNSWAPPABLE);
    return original == expected_material;
}

// Unlocking through setting the original material
void unlockPixel(uint index, int original_material) {
    atomicExchange(output_buffer.pixels[index].material, original_material);
}

// Order is important, as material is the lock
void setPixelDataAndUnlock(uint source_index, Pixel other_pixel) {
    
    // Non atomic is fine, as the lock is still on the material
    output_buffer.pixels[source_index].frame = other_pixel.frame;
    output_buffer.pixels[source_index].color_index = other_pixel.color_index;
    
    output_buffer.pixels[source_index].velocity_x = other_pixel.velocity_x;
    output_buffer.pixels[source_index].velocity_y = other_pixel.velocity_y;
    
    output_buffer.pixels[source_index].anything = other_pixel.anything;

    output_buffer.pixels[source_index].accumulated_velocity_x = other_pixel.accumulated_velocity_x;
    output_buffer.pixels[source_index].accumulated_velocity_y = other_pixel.accumulated_velocity_y;

    output_buffer.pixels[source_index].pressure_x = other_pixel.pressure_x;
    output_buffer.pixels[source_index].pressure_y = other_pixel.pressure_y;

    // UNLOCKS it
    atomicExchange(output_buffer.pixels[source_index].material, other_pixel.material);
}

uint getIndexFromPosition(ivec2 position) {
    return position.y * p.width + position.x;
}

bool inBounds(ivec2 pos) {
    return pos.x < p.width && pos.y < p.height && pos.x >= 0 && pos.y >= 0;
}

int getMaterialType(int material) {
    switch (material) {
        case SAND:           return SOLID;
        case ROCK:           return SOLID;
        case WOOD:           return SOLID;
        case SEED:           return SOLID;
        case PLANT:          return SOLID;
        case ASH:            return SOLID;
        case EMBER:          return SOLID;
        case WATER:          return LIQUID;
        case LAVA:           return LIQUID;
        case OIL:            return LIQUID;
        case ACID:           return LIQUID;
        case AIR:            return GAS;
        case FIRE:           return GAS;
        case WATER_VAPOR:    return GAS;
        case WATER_CLOUD:    return GAS;
        case ACID_VAPOR:     return GAS;
        case ACID_CLOUD:     return GAS;
        case SMOKE:          return GAS;
        case WALL:           return UNSWAPPABLE;
        case VOID:           return UNSWAPPABLE;
        case MIMIC:          return UNSWAPPABLE;
        case POISON:         return LIQUID;
    }
    
    return UNSWAPPABLE;
}


// 1 is no change in acceleration
// 0.5 is half as fast
// 2 is twice as fast
// -2 is reversed twice as fast
float getMaterialWeight(int material) {
    switch (material) {
        case AIR:           return 1.0;
        case FIRE:          return -4.0;
        case WATER_VAPOR:   return -2.0;
        case WATER_CLOUD:   return -1.0;
        case ACID_VAPOR:    return -0.5; 
        case ACID_CLOUD:    return -1.0; 
        case SMOKE:         return -3.0;

        case SAND:          return 1.0;
        case ROCK:          return 3.0;
        case WOOD:          return 3.0;
        case EMBER:         return 2.0;
        case ASH:           return 0.5; 
        case SEED:          return 0.5; 
        case PLANT:         return 0.5; 

        case WATER:         return 1.0;
        case POISON:        return 1.5; 
        case LAVA:          return 2.0;
        case ACID:          return 1.0; 
        case OIL:           return 1.5;
         
        case MIMIC:         return 1.0; 
        case WALL:          return 1.0;
        case VOID:          return 1.0; 
    }
    return 1.0;
}

float getLiquidViscosity(int material) {
    switch (material) {
        case WATER:     return 0.9; // Basically drag, lower val = higher drag
        case LAVA:      return 0.05; // Basically drag, lower val = higher drag
    }
    return 1.0;
}

float getGasDensity(int material) {
    switch (material) {
        case AIR:       return -1.0;
        case FIRE:      return -2.0;
    }
    return 1.0;
}
