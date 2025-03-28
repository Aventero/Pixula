#[compute]

#version 450

#define MAX_MOUSE_POSITIONS 200

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

struct Pixel {
    int material;
    int frame;
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

float hash1D(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffff);
}

float random(ivec2 position) {
    uint combined = uint((position.x) * 1973 + (position.y) * 9277);
    return hash1D(combined);
}

// keep size under 128 bytes
layout(push_constant, std430) uniform Params {
    int width;
    int height;
    int is_spawning;
    int spawn_radius;   
    int spawn_material; 
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

bool inBounds(ivec2 pos) {
    return pos.x < p.width && pos.y < p.height;
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

bool tryMove(ivec2 source, ivec2 destination) {
    if (!inBounds(source) || !inBounds(destination)) return false;
    
    uint source_index = source.y * p.width + source.x;
    uint destination_index = destination.y * p.width + destination.x;
    
    // Get materials
    int source_material = input_buffer.pixels[source_index].material;
    int destination_material = input_buffer.pixels[destination_index].material;
    
    // Skip if cannot swap
    if (source_material == destination_material || !canSwap(source_material, destination_material)) return false;
    
    // Step 1: mark source UNSWAPPABLE
    int source_original = atomicCompSwap(output_buffer.pixels[source_index].material, source_material, UNSWAPPABLE);
    
    // someone else modified source already abort!
    if (source_original != source_material) return false;
    
    // Step 2: Try to swap with target
    int target_original = atomicCompSwap(output_buffer.pixels[destination_index].material, destination_material, source_material);
    
    if (target_original == destination_material) {
        // Target swapped, set source to target pixels
        atomicExchange(output_buffer.pixels[source_index].material, destination_material);
        return true;
    } else {
        // Failed to swap, restore source to original pixels
        atomicExchange(output_buffer.pixels[source_index].material, source_material);
        return false;
    }
}

bool moveDown(ivec2 source) {
    return tryMove(source, source + ivec2(0, 1));
}

bool moveDiagonal(ivec2 source) {

    ivec2 direction;
    if ((source.x + source.y) % 2 == 0)
        direction = ivec2(-1, 1);
    else
        direction = ivec2(1, 1);

    return tryMove(source, source + direction);
}

bool moveDownLeft(ivec2 source) {
    return tryMove(source, source + ivec2(-1, 1));
}

bool moveDownRight(ivec2 source) {
    return tryMove(source, source + ivec2(1, 1));
}

bool moveHorizontal(ivec2 source) {
    int direction = source.y % 2 == 0 ? 1 : -1;
    return tryMove(source, source + ivec2(direction, 0));
}

bool sandMechanic(ivec2 source) {
    return moveDown(source) || moveDiagonal(source);
}

bool waterMechanic(ivec2 source) {
    return moveDown(source) || moveDiagonal(source) || moveHorizontal(source);
}

void spawn_in_radius(uint source_index, ivec2 source, ivec2 center, int radius, int spawn_material) {
    float distance_to_center = length(vec2(source - center));
	if (distance_to_center < float(radius)) {
        atomicExchange(output_buffer.pixels[source_index].material, spawn_material);
	}
}

void main() {
    uint index = gl_GlobalInvocationID.y * p.width + gl_GlobalInvocationID.x;
    ivec2 pos = ivec2(gl_GlobalInvocationID.x, gl_GlobalInvocationID.y);

    int count = min(mouse_buffer.count, MAX_MOUSE_POSITIONS);

    for (int i = 0; i < count; i++) {
        ivec2 mouse_pos = ivec2(mouse_buffer.x[i], mouse_buffer.y[i]);
        spawn_in_radius(index, pos, mouse_pos, p.spawn_radius, p.spawn_material);
    }

    int pixel = input_buffer.pixels[index].material;
    switch (pixel) {
        case SAND: sandMechanic(pos); return;
        case WATER: waterMechanic(pos); return;
    }
}