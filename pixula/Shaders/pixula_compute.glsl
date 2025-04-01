#[compute]

#version 450

#define MAX_MOUSE_POSITIONS 200

#include "compute_helper.gdshaderinc"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

struct Pixel {
    int material;
    int frame;
    int color_index;
    float velocity_x;
    float velocity_y;
    int anything;
    float accumulated_velocity_x; 
    float accumulated_velocity_y;  
};

layout(set = 0, binding = 0, std430) restrict buffer InputBuffer {
    Pixel pixels[];
} input_buffer;

layout(set = 0, binding = 1, std430) buffer OutputBuffer {
    Pixel pixels[];
} output_buffer;

layout(set = 0, binding = 2, std430) restrict buffer MousePosBuffer {
    int count;
    int x[MAX_MOUSE_POSITIONS];
    int y[MAX_MOUSE_POSITIONS];
} mouse_buffer;

// keep size under 128 bytes
layout(push_constant, std430) uniform Params {
    int width;
    int height;
    int is_spawning;
    int spawn_radius;   
    int spawn_material;
    int random_spawning_value;
} p;

const int SOLID = 100;
const int LIQUID = 101;
const int GAS = 102;
const int UNSWAPPABLE = -999;

const float STATIONARY_DRAG_X = 0.9;
const float STATIONARY_DRAG_Y = 0.9;

const float BOOST_THRESHOLD = 0.1;
const float INITIAL_BOOST = 1.0;     
const float ACCELERATION = 0.3;     
const float DRAG_X = 0.90;
const float DRAG_Y = 0.99;

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
        case WATER:     return 0.1; // Basically drag, lower val = higher drag
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

uint getIndexFromPosition(ivec2 position) {
    return position.y * p.width + position.x;
}

bool inBounds(ivec2 pos) {
    return pos.x < p.width && pos.y < p.height && pos.x >= 0 && pos.y >= 0;
}

bool canSwap(int source_material, int destination_material) {
    if (source_material == destination_material) return false;
    if (source_material == AIR || destination_material == AIR) return true;

    int source_type = getMaterialType(source_material);
    int destination_type = getMaterialType(destination_material);
    if (source_type == UNSWAPPABLE || destination_type == UNSWAPPABLE) return false;
    if (source_type == SOLID && destination_type == LIQUID) return true;
    if (source_type == LIQUID && destination_type == GAS) return true;

    // Rock is heavier than sand
    if (source_type == SOLID && destination_type == SOLID) {
        return getMaterialWeight(source_material) >= getMaterialWeight(destination_material);
    }

    // Lava is more visquis (heavier?) than water
    if (source_type == LIQUID && destination_type == LIQUID) {
        return getLiquidViscosity(source_material) <= getLiquidViscosity(destination_material);
    }

    // Fire is denser than air
    if (source_type == GAS && destination_type == GAS) {
        return getGasDensity(source_material) >= getGasDensity(destination_material);
    }

    return false;
}

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

    // UNLOCKS it
    atomicExchange(output_buffer.pixels[source_index].material, other_pixel.material);
}

bool trySwap(ivec2 source, ivec2 destination, Pixel source_pixel) {
    if (!inBounds(source) || !inBounds(destination)) return false;

    uint source_index = getIndexFromPosition(source);
    uint destination_index = getIndexFromPosition(destination);
    Pixel destination_pixel = input_buffer.pixels[destination_index];

    if (source_pixel.material == destination_pixel.material) return false;
    if (!canSwap(source_pixel.material, destination_pixel.material)) return false;

    // Lock source so it cant be swapped away
    if (!lockPixel(source_index, source_pixel.material)) return false; 
    
    // Lock destination for the same reason
    if (!lockPixel(destination_index, destination_pixel.material)) {
        unlockPixel(source_index, source_pixel.material); // ABORT
        return false;
    }

    Pixel temp_source = source_pixel;
    Pixel temp_dest = destination_pixel;

    setPixelDataAndUnlock(source_index, temp_dest);
    setPixelDataAndUnlock(destination_index, temp_source);

    return true;
}

bool updateVelocities(ivec2 source, Pixel pixel) {
    uint source_index = getIndexFromPosition(source);
    if (!lockPixel(source_index, pixel.material)) return false;
    output_buffer.pixels[source_index].velocity_x = pixel.velocity_x;
    output_buffer.pixels[source_index].velocity_y = pixel.velocity_y;
    output_buffer.pixels[source_index].accumulated_velocity_x = pixel.accumulated_velocity_x;
    output_buffer.pixels[source_index].accumulated_velocity_y = pixel.accumulated_velocity_y;
    unlockPixel(source_index, pixel.material);
    return true;
}

bool passVelocity(Pixel source_pixel, ivec2 destination) {
    uint destination_index = getIndexFromPosition(destination);
    Pixel destination_pixel = input_buffer.pixels[destination_index];
    if (!lockPixel(destination_index, destination_pixel.material)) return false;
    output_buffer.pixels[destination_index].velocity_x += source_pixel.velocity_x;
    output_buffer.pixels[destination_index].velocity_y += source_pixel.velocity_y;
    output_buffer.pixels[destination_index].accumulated_velocity_x += source_pixel.accumulated_velocity_x;
    output_buffer.pixels[destination_index].accumulated_velocity_y += source_pixel.accumulated_velocity_y;
    unlockPixel(destination_index, destination_pixel.material);
    return true;
}


bool updateAnything(ivec2 source, Pixel pixel) {
    uint source_index = getIndexFromPosition(source);
    if (!lockPixel(source_index, pixel.material)) return false;
    output_buffer.pixels[source_index].anything = pixel.anything;
    unlockPixel(source_index, pixel.material);
    return true;
}

vec2 getAdditionalDrag(Pixel source_pixel, ivec2 destination) {
    vec2 additional_drag = vec2(1.0, 1.0);
    Pixel destination_pixel = input_buffer.pixels[getIndexFromPosition(destination)];

    int source_type = getMaterialType(source_pixel.material);
    int destination_type = getMaterialType(destination_pixel.material);
    if (source_type == SOLID && destination_type == LIQUID) {
        additional_drag.y = min(1.0, getMaterialWeight(source_pixel.material) * getLiquidViscosity(destination_pixel.material));
        additional_drag.x = min(1.0, additional_drag.y * 5.0); // less drag in X
    }

    if (source_type == SOLID && destination_type == SOLID) {
        // Destination must be heavier! This is assumed
        additional_drag.y = min(1.0, getMaterialWeight(destination_pixel.material) / (getMaterialWeight(source_pixel.material) * 50.0));
        additional_drag.x = min(1.0, additional_drag.y * 0.5);
    }
    
    return additional_drag;
}


void moveAlongAxis(inout ivec2 current_pos, inout Pixel source_pixel, int steps, bool is_x_axis) {
    if (steps == 0) return;
    
    int dir = sign(steps);
    
    for (int step = 0; step != steps; step += dir) {
        ivec2 step_dir = is_x_axis ? ivec2(dir, 0) : ivec2(0, dir);
        ivec2 destination = current_pos + step_dir;
        
        // Try to move
        if (!trySwap(current_pos, destination, source_pixel)) {
            // Collision
            if (is_x_axis) {
                source_pixel.velocity_x *= DRAG_X;
                source_pixel.accumulated_velocity_x = 0.0;
            } else {
                source_pixel.velocity_y *= DRAG_Y;
                source_pixel.accumulated_velocity_y = 0.0;
            }
            break;
        }

        vec2 additional_drag = getAdditionalDrag(source_pixel, destination);
        if (is_x_axis) {
            source_pixel.velocity_x *= DRAG_X * additional_drag.x;
        } else {
            source_pixel.velocity_y *= DRAG_Y * additional_drag.y;
        }
        current_pos = destination;
    }
}

void moveWithVelocity(ivec2 source, Pixel source_pixel) {

    source_pixel.accumulated_velocity_x += source_pixel.velocity_x;
    source_pixel.accumulated_velocity_y += source_pixel.velocity_y;
    
    int steps_x = int(source_pixel.accumulated_velocity_x);
    int steps_y = int(source_pixel.accumulated_velocity_y);
    
    source_pixel.accumulated_velocity_x -= float(steps_x);
    source_pixel.accumulated_velocity_y -= float(steps_y);
    
    int dir_x = sign(steps_x);
    int dir_y = sign(steps_y);
    
    ivec2 current_pos = source;
    moveAlongAxis(current_pos, source_pixel, steps_x, true);
    moveAlongAxis(current_pos, source_pixel, steps_y, false);
    updateVelocities(current_pos, source_pixel);
}


bool canSwapWithDestination(ivec2 source, Pixel pixel, ivec2 destination) {
    if (!inBounds(source) || !inBounds(destination)) return false;
    int destination_material = input_buffer.pixels[getIndexFromPosition(destination)].material;
    return canSwap(pixel.material, destination_material);
}

bool moveDown(ivec2 source, Pixel pixel) {
    ivec2 direction = ivec2(0, 1);
    if (canSwapWithDestination(source, pixel, source + direction)) {
        if (abs(pixel.velocity_y) < BOOST_THRESHOLD) 
            pixel.velocity_y = INITIAL_BOOST; 
        else 
            pixel.velocity_y += direction.y * ACCELERATION * getMaterialWeight(pixel.material);
            pixel.velocity_y *= getAdditionalDrag(pixel, source + direction).y;
        moveWithVelocity(source, pixel);
        return true;
    }
    return false;
}

bool moveDiagonal(ivec2 source, Pixel pixel) {
    ivec2 direction;
    if (chance(source, pixel.frame, 0.5))
        direction = ivec2(-1, 1);
    else
        direction = ivec2(1, 1);

    if (canSwapWithDestination(source, pixel, source + direction)) {
        // Apply jump start for diagonal movement
        float speed = length(vec2(pixel.velocity_x, pixel.velocity_y));
        if (speed < BOOST_THRESHOLD) {
            pixel.velocity_x = direction.x * INITIAL_BOOST * 0.1;
            pixel.velocity_y = direction.y * INITIAL_BOOST;
        } else {
            pixel.velocity_x += direction.x * ACCELERATION;
            pixel.velocity_x *= getAdditionalDrag(pixel, source + direction).x;
            pixel.velocity_y += direction.y * ACCELERATION * getMaterialWeight(pixel.material);
            pixel.velocity_y *= getAdditionalDrag(pixel, source + direction).y;
        }
        moveWithVelocity(source, pixel);
        return true;
    }
    return false;
}

bool moveHorizontal(ivec2 source, Pixel pixel) {
    int dir = pixel.anything;
    if (canSwapWithDestination(source, pixel, source + ivec2(dir, 0))) {
        if (abs(pixel.velocity_x) < BOOST_THRESHOLD) {
            pixel.velocity_x = dir * INITIAL_BOOST * 0.1;
        } else {
            pixel.velocity_x += dir * ACCELERATION * 0.5;
            pixel.velocity_x *= getAdditionalDrag(pixel, source + ivec2(dir, 0)).x;
        }
        moveWithVelocity(source, pixel);
        return true;
    } else {
        pixel.anything = pixel.anything * -1;
        updateAnything(source, pixel);
    }
    return false;
}

bool waterMechanic(ivec2 source, Pixel pixel) {
    if (pixel.anything == 0) {
        pixel.anything = (source.y) % 2 == 0 ? -1 : 1;
        updateAnything(source, pixel);
    }

    if (moveDown(source, pixel)) return true;
    return moveDiagonal(source, pixel) || moveHorizontal(source, pixel);
}


bool sandMechanic(ivec2 source, Pixel pixel) {
    return moveDown(source, pixel) || moveDiagonal(source, pixel);
}

bool rockMechanic(ivec2 source, Pixel pixel) {
    return moveDown(source, pixel) || moveDiagonal(source, pixel);
}


void spawn_in_radius(uint source_index, ivec2 source, ivec2 center, int radius, int spawn_material) {
    int distance_to_center = int(length(vec2(source - center)));
	if (distance_to_center < radius) {
        int rand_val = random_range(source, p.random_spawning_value, 1, 100);

        Pixel current_pixel = input_buffer.pixels[source_index];
        Pixel spawn_pixel = Pixel(spawn_material, rand_val, -1, 0.0, 0.0, 0, 0.0, 0.0);
        if (current_pixel.material == spawn_pixel.material) return;
        if (!lockPixel(source_index, current_pixel.material)) return;
        
        setPixelDataAndUnlock(source_index, spawn_pixel);
	}
}

void try_spawning(uint index, ivec2 pos) {
    // Mouse Spawning
    int count = min(mouse_buffer.count, MAX_MOUSE_POSITIONS);
    for (int i = 0; i < count; i++) {
        ivec2 mouse_pos = ivec2(mouse_buffer.x[i], mouse_buffer.y[i]);
        spawn_in_radius(index, pos, mouse_pos, p.spawn_radius, p.spawn_material);
    }
}

Pixel applStationaryDrag(Pixel pixel) {
    pixel.velocity_x *= STATIONARY_DRAG_X;
    pixel.velocity_y *= STATIONARY_DRAG_Y;
    return pixel;
}

// bool indicates if it moved at all
bool doMechanics(ivec2 pos, Pixel pixel) {
    switch (pixel.material) {
        case SAND: return sandMechanic(pos, pixel);
        case WATER: return waterMechanic(pos, pixel);
        case ROCK: return rockMechanic(pos, pixel);
    }
}

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.x, gl_GlobalInvocationID.y);
    uint index = getIndexFromPosition(pos);
    try_spawning(index, pos);

    Pixel pixel = input_buffer.pixels[index];

    if (chance(pos, pixel.frame, 0.005)) return;

    bool has_moved = doMechanics(pos, pixel);
    if (!has_moved) {
        pixel = applStationaryDrag(pixel);
        updateVelocities(pos, pixel);
    }
}