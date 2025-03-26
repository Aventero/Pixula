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
    ivec2 grid_size;    // 8
    int is_spawning;    // 4
    int spawn_radius;   // 4
    int spawn_material; // 4
    ivec2 mouse_pos;    // 8
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


bool moveDown(ivec2 source) {
    return tryMove(source, source + ivec2(0, 1));
}

bool moveDiagonal(ivec2 source) {
    ivec2 direction = (source.x + source.y) % 2 == 0 ? ivec2(-1, 1) : ivec2(1, 1);
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
	ivec2 pos_min = max(ivec2(0, 0), ivec2(center) - ivec2(radius));
	ivec2 pos_max = min(params.grid_size, ivec2(center) + ivec2(radius + 1));
	float distance_to_center = length(vec2(source - center));
	
    // Inside circle!
	if (distance_to_center < float(radius)) {
        atomicExchange(output_buffer.data[source_index], spawn_material);
	}
}



void main() {
    uint index = gl_GlobalInvocationID.y * params.grid_size.x + gl_GlobalInvocationID.x;
    ivec2 pos = ivec2(gl_GlobalInvocationID.x, gl_GlobalInvocationID.y);
    
    // if (params.is_spawning == 1) {
    //     spawn_in_radius(index, self_pos, params.mouse_pos, params.spawn_radius, params.spawn_material);
    // }


    // In your main shader function
    if (pos.x == 0 && pos.y == 0) {
        // Debug output at a known position - this should always appear
        atomicExchange(output_buffer.data[index], WALL);
    }

    if (pos.x == params.mouse_pos.x && pos.y == params.mouse_pos.y) {
        // This should mark where the mouse actually is
        atomicExchange(output_buffer.data[index], WATER);
    }

    // Test to see where mouse coordinates are in the shader's understanding
    if (pos.x == 10 && pos.y == 10) {
        // Mark a reference point to understand coordinate system   
        atomicExchange(output_buffer.data[index], SAND);
    }

    // int material = input_buffer.data[index];
    // switch (material) {
    //     case SAND: sandMechanic(self_pos); return;
    //     case WATER: waterMechanic(self_pos); return;
    // }
}