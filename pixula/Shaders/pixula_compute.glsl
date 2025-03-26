#[compute]

#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer InputBuffer {
    int data[];
} input_buffer;

layout(set = 0, binding = 1, std430) buffer OutputBuffer {
    int data[];
} output_buffer;

// keep size under 128 bytes
layout(push_constant, std430) uniform Params {
    ivec2 grid_size;
} params;


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
    return pos.x < params.grid_size.x && pos.y < params.grid_size.y;
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
    
    uint source_index = source.y * params.grid_size.x + source.x;
    uint destination_index = destination.y * params.grid_size.x + destination.x;
    
    // Get materials
    int source_material = input_buffer.data[source_index];
    int destination_material = input_buffer.data[destination_index];
    
    // Skip if cannot swap
    if (source_material == destination_material || !canSwap(source_material, destination_material)) return false;
    
    // Step 1: mark source UNSWAPPABLE
    int source_original = atomicCompSwap(output_buffer.data[source_index], source_material, UNSWAPPABLE);
    
    // someone else modified source already abort!
    if (source_original != source_material) return false;
    
    // Step 2: Try to swap with target
    int target_original = atomicCompSwap(output_buffer.data[destination_index], destination_material, source_material);
    
    if (target_original == destination_material) {
        // Target swapped, set source to target material
        atomicExchange(output_buffer.data[source_index], destination_material);

        return true;
    } else {
        // Failed to swap, restore source to original material
        atomicExchange(output_buffer.data[source_index], source_material);
        return false;
    }
}


void sandMechanic(ivec2 source, int material) {
    if (material == SAND) {
        ivec2 down = source + ivec2(0, 1);
        if (tryMove(source, down)) return;
        
        ivec2 down_left = source + ivec2(-1, 1);
        if (tryMove(source, down_left)) return;
        
        ivec2 down_right = source + ivec2(1, 1);
        if (tryMove(source, down_right)) return;
    }
}

void main() {
    uint index = gl_GlobalInvocationID.y * params.grid_size.x + gl_GlobalInvocationID.x;
    ivec2 self_pos = ivec2(gl_GlobalInvocationID.x, gl_GlobalInvocationID.y);
    
    int material = input_buffer.data[index];
    sandMechanic(self_pos, material);
}