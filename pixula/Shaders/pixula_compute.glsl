#[compute]

#version 450

#define MAX_MOUSE_POSITIONS 200

#include "compute_helper.gdshaderinc"
// float random(ivec2 pos, int frame) -> 0 - 1

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

struct Pixel {
    int material;
    int frame;
    int color_index;
};

layout(set = 0, binding = 0, std430) buffer InputBuffer {
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


// Materials
const int AIR = 0;
const int SAND = 1;
const int WATER = 2;
const int WALL = 4;

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
void setPixelData(uint index, int material, int frame, int color_index) {
    atomicExchange(output_buffer.pixels[index].frame, frame);
    atomicExchange(output_buffer.pixels[index].color_index, color_index);
    atomicExchange(output_buffer.pixels[index].material, material);
}

bool tryMove(ivec2 source, ivec2 destination) {
    if (!inBounds(source) || !inBounds(destination)) return false;
    
    uint source_index = getIndexFromPosition(source);
    uint destination_index = getIndexFromPosition(destination);
    
    Pixel source_pixel = input_buffer.pixels[source_index];
    Pixel destination_pixel = input_buffer.pixels[destination_index];
    
    // Skip if it cannot swap with the target
    if (source_pixel.material == destination_pixel.material || 
        !canSwap(source_pixel.material, destination_pixel.material)) {
        return false;
    }
    
    // Lock source so others cannot swap it away
    if (!lockPixel(source_index, source_pixel.material)) {
        // Another thread already changed it
        return false; 
    }
    
    // Lock destination for the same reason
    if (!lockPixel(destination_index, destination_pixel.material)) {
        // Another thread already changed it, ABORT!
        unlockPixel(source_index, source_pixel.material); 
        return false;
    }
    
    // Set pixel data for both pixels (This also unlocks them automatically.)
    setPixelData(source_index, destination_pixel.material, destination_pixel.frame, destination_pixel.color_index);
    setPixelData(destination_index, source_pixel.material, source_pixel.frame, source_pixel.color_index);
    
    return true;
}


bool moveDown(ivec2 source, Pixel pixel) {
    return tryMove(source, source + ivec2(0, 1));
}

bool moveDiagonal(ivec2 source, Pixel pixel) {

    ivec2 direction;
    if (chance(source, pixel.frame, 0.5))
        direction = ivec2(-1, 1);
    else
        direction = ivec2(1, 1);

    return tryMove(source, source + direction);
}

bool moveDownLeft(ivec2 source, Pixel pixel) {
    return tryMove(source, source + ivec2(-1, 1));
}

bool moveDownRight(ivec2 source, Pixel pixel) {
    return tryMove(source, source + ivec2(1, 1));
}

bool moveHorizontal(ivec2 source, Pixel pixel) {
    int direction = source.y % 2 == 0 ? 1 : -1;
    return tryMove(source, source + ivec2(direction, 0));
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
        atomicExchange(output_buffer.pixels[source_index].material, spawn_material);
        atomicExchange(output_buffer.pixels[source_index].frame, rand_val);
        atomicExchange(output_buffer.pixels[source_index].color_index, -1);
	}
}



void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.x, gl_GlobalInvocationID.y);
    uint index = getIndexFromPosition(pos);

    int count = min(mouse_buffer.count, MAX_MOUSE_POSITIONS);
    for (int i = 0; i < count; i++) {
        ivec2 mouse_pos = ivec2(mouse_buffer.x[i], mouse_buffer.y[i]);
        spawn_in_radius(index, pos, mouse_pos, p.spawn_radius, p.spawn_material);
    }

    Pixel pixel = input_buffer.pixels[index];
    int material = input_buffer.pixels[index].material;

    // Somtimes do nothing.
    if (chance(pos, pixel.frame, 0.005)) return;

    switch (material) {
        case SAND: sandMechanic(pos, pixel); break;
        case WATER: waterMechanic(pos, pixel); break;
    }
}