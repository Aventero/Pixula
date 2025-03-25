#[compute]

#version 450

// Basically number of threads on the GPU
// one warp = 32 threads (NVIDEA)
// so multiples of 32 is good -> 256 invocations
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer InputBuffer {
    int data[];
} input_buffer;

layout(set = 0, binding = 1, std430) buffer OutputBuffer {
    int data[];
} output_buffer;


const uint width = 8;

// Materials
const int AIR = 0;
const int SAND = 1;
const int WATER = 2;
const int WALL = 4;

const int SOLID = 100;
const int LIQUID = 101;
const int GAS = 102;
const int UNSWAPPABLE = -999;

// uint atomicCompSwap(	inout uint mem, uint compare, uint data);
// int atomicCompSwap(	inout int mem, int compare, int data);
// if mem == compare -> data written to mem
// else mem not modified

// First, define your material type system
int getMaterialType(int material) {
    if (material == AIR) return GAS;
    if (material == SAND) return SOLID;
    if (material == WATER) return LIQUID;
    if (material == WALL) return UNSWAPPABLE;
    return UNSWAPPABLE;
}

// Check if two materials can swap positions
bool canSwap(int source_material, int destination_material) {
    // Air can always be swapped with anything
    if (source_material == AIR || destination_material == AIR) return true;
    
    int source_type = getMaterialType(source_material);
    int destination_type = getMaterialType(destination_material);
    
    // Unswappable materials cannot be moved
    if (source_type == UNSWAPPABLE || destination_type == UNSWAPPABLE) return false;
    
    // Define your swapping rules here
    if (source_type == SOLID && destination_type == LIQUID) return true;
    if (source_type == LIQUID && destination_type == GAS) return true;
    
    return false;
}

bool tryMove(ivec2 source, ivec2 destination) {
    uint source_index = source.y * width + source.x;
    uint destination_index = destination.y * width + destination.x;
    
    // Check bounds
    if (destination_index >= output_buffer.data.length()) return false;
    
    // Get materials from the input buffer
    int source_material = input_buffer.data[source_index];
    int destination_material = input_buffer.data[destination_index];
    
    // Skip if no movement needed or can't swap
    if (source_material == destination_material || !canSwap(source_material, destination_material)) return false;
    

    // Step 1: Try to mark our source as UNSWAPPABLE atomically
    int source_original = atomicCompSwap(output_buffer.data[source_index], source_material, UNSWAPPABLE);
    
    // If we couldn't mark our source (someone else modified it), abort
    if (source_original != source_material) return false;
    
    // Step 2: Try to swap with target
    int target_original = atomicCompSwap(output_buffer.data[destination_index], destination_material, source_material);
    
    // Step 3: Handle the results
    if (target_original == destination_material) {
        // Success! Target was swapped, now set source to target material
        atomicExchange(output_buffer.data[source_index], destination_material);
        return true;
    } else {
        // Failed to swap with target, restore source to original material
        atomicExchange(output_buffer.data[source_index], source_material);
        return false;
    }
}



void main() {
    uint index = gl_GlobalInvocationID.y * width + gl_GlobalInvocationID.x;
    ivec2 self_pos = ivec2(gl_GlobalInvocationID.x, gl_GlobalInvocationID.y);
    
    int material = input_buffer.data[index];
    
    // Skip empty spaces or walls
    if (material == AIR || material == WALL) return;
    
    // Try to move down
    if (material == SAND) {
        ivec2 down = self_pos + ivec2(0, 1);
        if (tryMove(self_pos, down)) return;
        
        // Try diagonal moves if direct down fails
        ivec2 down_left = self_pos + ivec2(-1, 1);
        if (tryMove(self_pos, down_left)) return;
        
        ivec2 down_right = self_pos + ivec2(1, 1);
        if (tryMove(self_pos, down_right)) return;
    }
}