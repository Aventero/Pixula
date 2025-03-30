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

int getMaterialType(int material) {
    if (material == AIR) return GAS;
    if (material == SAND) return SOLID;
    if (material == WATER) return LIQUID;
    if (material == WALL) return UNSWAPPABLE;
    return UNSWAPPABLE;
}

uint getIndexFromPosition(ivec2 position) {
    return position.y * p.width + position.x;
}

bool inBounds(ivec2 pos) {
    return pos.x < p.width && pos.y < p.height && pos.x >= 0 && pos.y >= 0;
}

bool canSwap(int source_material, int destination_material) {
    if (source_material == AIR || destination_material == AIR) return true;
    int source_type = getMaterialType(source_material);
    int destination_type = getMaterialType(destination_material);
    if (source_type == UNSWAPPABLE || destination_type == UNSWAPPABLE) return false;
    if (source_type == SOLID && destination_type == LIQUID) return true;
    if (source_type == LIQUID && destination_type == GAS) return true;
    return false;
}

// Locks the pixel no matter what is there as it will be overwritten anyway
void lockPixelForced(uint index) {
    atomicExchange(output_buffer.pixels[index].material, UNSWAPPABLE);
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
void setPixelDataAndUnlock(uint index, int material, int frame, int color_index, float velocity_x, float velocity_y) {
    
    // Non atomic is fine, as the lock is still on the material
    output_buffer.pixels[index].frame = frame;
    output_buffer.pixels[index].color_index = color_index;
    output_buffer.pixels[index].velocity_x = velocity_x;
    output_buffer.pixels[index].velocity_y = velocity_y;

    // UNLOCKS it
    atomicExchange(output_buffer.pixels[index].material, material);
}

bool tryMove(ivec2 source, ivec2 destination, Pixel source_pixel) {

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
    
    // Set pixel data for source and destination (swaps it)
    setPixelDataAndUnlock(source_index, destination_pixel.material, destination_pixel.frame, destination_pixel.color_index, destination_pixel.velocity_x, destination_pixel.velocity_y);
    setPixelDataAndUnlock(destination_index, source_pixel.material, source_pixel.frame, source_pixel.color_index, source_pixel.velocity_x, source_pixel.velocity_y);

    return true;
}

bool updateVelocity(ivec2 source, Pixel pixel) {
    uint source_index = getIndexFromPosition(source);
    if (!lockPixel(source_index, pixel.material)) return false; 
    output_buffer.pixels[source_index].velocity_x = pixel.velocity_x;
    output_buffer.pixels[source_index].velocity_y = pixel.velocity_y;
    unlockPixel(source_index, pixel.material);
    return true;
}

bool moveWithVelocity(ivec2 source, Pixel source_pixel) {

    int steps_x = int(source_pixel.velocity_x);
    int steps_y = int(source_pixel.velocity_y);
    
    steps_x = clamp(steps_x, -3, 3);
    steps_y = clamp(steps_y, -3, 3);
    
    // If no movement possible, just update the velocity in place
    if (steps_x == 0 && steps_y == 0) {
        updateVelocity(source, source_pixel);
        return false;
    }
    
    int dir_x = sign(steps_x);
    int dir_y = sign(steps_y);
    
    ivec2 current_pos = source;
    
    // X movement
    for (int x = 0; x != steps_x; x += dir_x) {
        ivec2 destination = current_pos + ivec2(dir_x, 0);
        if (!tryMove(current_pos, destination, source_pixel)) {
            // Bonked.
            source_pixel.velocity_x *= 0.5;
            updateVelocity(source, source_pixel);
            return false;
        }
        current_pos = destination;
    }
    
    // Y movement 
    for (int y = 0; y != steps_y; y += dir_y) {
        ivec2 destination = current_pos + ivec2(0, dir_y);
        if (!tryMove(current_pos, destination, source_pixel)) {
            // Bonked.
            source_pixel.velocity_y *= 0.5;
            updateVelocity(source, source_pixel);
            return false;
        } 
        current_pos = destination;
    }
    
    // All movement steps succeeded!
    return true;
}


bool moveDown(ivec2 source, Pixel pixel) {
    return tryMove(source, source + ivec2(0, 1), pixel);
}

bool moveDiagonal(ivec2 source, Pixel pixel) {

    ivec2 direction;
    if (chance(source, pixel.frame, 0.5))
        direction = ivec2(-1, 1);
    else
        direction = ivec2(1, 1);

    return tryMove(source, source + direction, pixel);
}

bool moveDownLeft(ivec2 source, Pixel pixel) {
    return tryMove(source, source + ivec2(-1, 1), pixel);
}

bool moveDownRight(ivec2 source, Pixel pixel) {
    return tryMove(source, source + ivec2(1, 1), pixel);
}

bool moveHorizontal(ivec2 source, Pixel pixel) {
    int direction = source.y % 2 == 0 ? 1 : -1;
    return tryMove(source, source + ivec2(direction, 0), pixel);
}

bool sandMechanic(ivec2 source, Pixel pixel) {
    return moveDown(source, pixel) || moveDiagonal(source, pixel);
}

bool waterMechanic(ivec2 source, Pixel pixel) {
    return moveDown(source, pixel) || moveDiagonal(source, pixel) || moveHorizontal(source, pixel);
}

void spawn_in_radius(uint source_index, ivec2 source, ivec2 center, int radius, int spawn_material) {
    int distance_to_center = int(length(vec2(source - center)));
	if (distance_to_center < radius) {
        int rand_val = random_range(source, p.random_spawning_value, 1, 100);
        lockPixelForced(source_index);
        setPixelDataAndUnlock(source_index, spawn_material, rand_val, -1, 0.0, 0.0);
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

Pixel applyGravity(Pixel pixel) {
    if (pixel.material != AIR && pixel.material != WALL && getMaterialType(pixel.material) != UNSWAPPABLE) {
        float gravity_factor = 0.1;
        pixel.velocity_y += gravity_factor;
    }
    return pixel;
}

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.x, gl_GlobalInvocationID.y);
    uint index = getIndexFromPosition(pos);
    try_spawning(index, pos);

    Pixel pixel = input_buffer.pixels[index];


    if (chance(pos, pixel.frame, 0.005)) return;
    pixel = applyGravity(pixel);

    if (!moveWithVelocity(pos, pixel)) {
        switch (pixel.material) {
            case SAND: sandMechanic(pos, pixel); break;
            case WATER: waterMechanic(pos, pixel); break;
        }
    }

}