#[compute]

#version 450

#define MAX_MOUSE_POSITIONS 200

#include "compute_helper.gdshaderinc"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

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

const float STATIONARY_DRAG_X = 0.95;
const float STATIONARY_DRAG_Y = 0.95;

const float BOOST_THRESHOLD = 0.1;
const float INITIAL_BOOST = 1.0;     
const float ACCELERATION = 0.3;     
const float DRAG_X = 0.99;
const float DRAG_Y = 0.99;

#include "compute_core.gdshaderinc"

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
        additional_drag.y = min(1.0, getMaterialWeight(destination_pixel.material) / (getMaterialWeight(source_pixel.material) * 10.0));
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
    
    int steps_x = clamp(int(source_pixel.accumulated_velocity_x), -4, 4);
    int steps_y = clamp(int(source_pixel.accumulated_velocity_y), -4, 4);
    
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
    vec2 pressure_vec = vec2(pixel.pressure_x, pixel.pressure_y);
    float pressure_magnitude = length(pressure_vec);
    
    if (pressure_magnitude < 0.005) return false;
    
    //pressure_vec = normalize(pressure_vec);

    // Update velocities based on pressure direction
    pixel.velocity_x += pressure_vec.x * ACCELERATION;
    pixel.velocity_y += pressure_vec.y * ACCELERATION;
    
    // Move with velocity
    moveWithVelocity(source, pixel);
    
    return true;
}

bool sandMechanic(ivec2 source, Pixel pixel) {
    return moveDown(source, pixel) || moveDiagonal(source, pixel);
}

bool rockMechanic(ivec2 source, Pixel pixel) {
    return moveDown(source, pixel) || moveDiagonal(source, pixel);
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

    Pixel pixel = input_buffer.pixels[index];

    if (chance(pos, pixel.frame, 0.005)) return;

    bool has_moved = doMechanics(pos, pixel);
    barrier();
    if (!has_moved) {
        pixel = applStationaryDrag(pixel);
        updateVelocities(pos, pixel);
    }
}