shader_type canvas_item;

// Input state texture and simulation parameters
uniform sampler2D state_texture;
uniform int iteration_count;

// Material definitions as floats
const int EMPTY = 0;
const int SAND = 1;
const int WALL = 4;


// Just random wont work
// As 4 pixels pixels can have different random values -> removes/adds pixels
// But if its in the same block every pixel gets the same value (like a seed)
float rand_value_for_block(ivec2 block_pos) {
    // Use the block position, not the pixel position
    vec2 seed = vec2(float(block_pos.x + iteration_count * 31), 
                     float(block_pos.y + iteration_count * 53));
    return fract(sin(dot(seed, vec2(12.9898, 78.233))) * 43758.5453);
}

void process_sand_block(ivec2 block_pos, inout int TL, inout int TR, inout int BL, inout int BR) {
	float rand = rand_value_for_block(block_pos);
	
    if (TL == SAND && TR == EMPTY && BL == EMPTY && BR == EMPTY) {
		TL = EMPTY;
		TR = EMPTY;
		BL = SAND;
		BR = EMPTY;
		return;
    }

    if (TL == EMPTY && TR == SAND && BL == EMPTY && BR == EMPTY) {
		TL = EMPTY;
		TR = EMPTY;
		BL = EMPTY;
		BR = SAND;
		return;
    }
	
	// SS 
	// XX
	 
	// XX
	// SS
	if (TL == SAND && TR == SAND && BL == EMPTY && BR == EMPTY) {
		TL = EMPTY;
		TR = EMPTY;
		BL = SAND;
		BR = SAND;
		return;
	}
	
	if (TL == SAND && TR == SAND && BL == EMPTY && BR == SAND) {
		TL = EMPTY;
		TR = SAND;
		BL = SAND;
		BR = SAND;
		return;
	}

	if (TL == SAND && TR == SAND && BL == SAND && BR == EMPTY) {
		TL = SAND;
		TR = EMPTY;
		BL = SAND;
		BR = SAND;
		return;
	}

	if (TL == EMPTY && TR == SAND && BL == SAND && BR == EMPTY) {
		TL = EMPTY;
		TR = EMPTY;
		BL = SAND;
		BR = SAND;
		return;
	}

	if (TL == SAND && TR == EMPTY && BL == EMPTY && BR == SAND) {
		TL = EMPTY;
		TR = EMPTY;
		BL = SAND;
		BR = SAND;
		return;
	}

	// TOPPLING
	if (TL == EMPTY && TR == SAND && BL == EMPTY && BR == SAND && rand <= 0.75) {
		TL = EMPTY;
		TR = EMPTY;
		BL = SAND;
		BR = SAND;
		return;
	}

	if (TL == SAND && TR == EMPTY && BL == SAND && BR == EMPTY && rand <= 0.75) {
		TL = EMPTY;
		TR = EMPTY;
		BL = SAND;
		BR = SAND;
		return;
	}
}

ivec2 get_block_position(ivec2 pos, int phase) {
    switch (phase)
	{
		case 0: return ivec2(pos.x - (pos.x % 2), pos.y - (pos.y % 2)); 			// ORIGIN
		case 1: return ivec2(pos.x - ((pos.x + 1) % 2), pos.y - ((pos.y + 1) % 2)); // BOTTOM RIGHT
		case 2: return ivec2(pos.x - (pos.x % 2), pos.y - ((pos.y + 1) % 2)); 		// BOTTOM
		case 3: return ivec2(pos.x - ((pos.x + 1) % 2), pos.y - ((pos.y) % 2)); 	// RIGHT
		case 4: return ivec2(pos.x - ((pos.x - 1) % 2), pos.y - ((pos.y - 1) % 2)); // TOP LEFT
		case 5: return ivec2(pos.x - (pos.x % 2), pos.y - ((pos.y - 1) % 2)); 		// TOP
		case 6: return ivec2(pos.x - ((pos.x - 1) % 2), pos.y - (pos.y % 2)); 		// LEFT
		//case 5: return ivec2(pos.x - ((pos.x - 1) % 2), pos.y - ((pos.y + 1) % 2)); // BOTTOM LEFT
	}
    return ivec2(-1, -1); // SHOULD NOT HAPPEN
}

int get_own_index_in_block(ivec2 cell_pos, ivec2 block_pos) {
	ivec2 local_cell_pos = cell_pos - block_pos;
	if (local_cell_pos == ivec2(0, 0)) // top left
		return 0;
	if (local_cell_pos == ivec2(1, 0)) // top right
		return 1;
	if (local_cell_pos == ivec2(0, 1)) // bottom left
		return 2;
	if (local_cell_pos == ivec2(1, 1)) // bottom right
		return 3;
	
	return 0;
}

// Get material at position
int get_material(ivec2 pos) {
    // Check if position is within bounds
	ivec2 texture_size = textureSize(state_texture, 0);
    if (pos.x < 0 || pos.y < 0 || pos.x >= texture_size.x || pos.y >= texture_size.y) {
        return WALL; 
    }
	
    vec3 material_color = texelFetch(state_texture, pos, 0).rgb;
	if (material_color.r == 1.0)
		return SAND;
	return EMPTY;
}

// Get material color for visualization
vec3 get_material_color(int material) {
	
	switch (material)
	{
		case EMPTY: return vec3(0.1);
		case SAND: return vec3(1.0, 0.0, 0.0);
		case WALL: return vec3(0.3);
	}
    return vec3(0.0, 1.0, 0.0);  // Red for debugging
}


void fragment() {                  
    // Get current pixel position
	ivec2 texture_size = textureSize(state_texture, 0);
    ivec2 pos = ivec2(UV * vec2(texture_size));
    // Special handling for edge columns
    bool is_edge = (pos.x == 0 || pos.x == texture_size.x - 1);
    
    // For edges, use a consistent phase pattern 
    int phase = iteration_count % 7;

    // In which block does the fragment reside in
    ivec2 block_pos = get_block_position(pos, phase);

    int tl_material_type = get_material(block_pos + ivec2(0, 0)); 
    int tr_material_type = get_material(block_pos + ivec2(1, 0));
    int bl_material_type = get_material(block_pos + ivec2(0, 1));
    int br_material_type = get_material(block_pos + ivec2(1, 1));
    process_sand_block(block_pos, tl_material_type, tr_material_type, bl_material_type, br_material_type);

    int new_states[4];
    new_states[0] = tl_material_type;
    new_states[1] = tr_material_type;
    new_states[2] = bl_material_type;
    new_states[3] = br_material_type;

    int index = get_own_index_in_block(pos, block_pos);
    int material_type_in_block = new_states[index];
	
    vec3 color = get_material_color(material_type_in_block);
	
   	COLOR = vec4(color, 1.0);
}