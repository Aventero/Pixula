shader_type canvas_item;

// Input state texture and simulation parameters
uniform sampler2D state_texture;
uniform int iteration_count;

// spawning
uniform bool is_spawning;
uniform int spawn_radius;
uniform int spawn_material;
uniform ivec2 mouse_pos;

const int SPAWN_FILLER = -99;

const int AIR = 0;
const int SAND = 1;
const int WATER = 2;
const int WALL = 4;

const int SOLID = 100;
const int LIQUID = 101;
const int GAS = 102;
const int UNSWAPPABLE = -999;

// Just random wont work
// As 4 pixels pixels can have different random values -> removes/adds pixels
// But if its in the same block every pixel gets the same value (like a seed)
float rand_value_for_block(ivec2 block_pos) {
    // Use the block position, not the pixel position
    vec2 seed = vec2(float(block_pos.x * 31 + iteration_count * 13),
                     float(block_pos.y * 53 + iteration_count * 7));
    return fract(sin(dot(seed, vec2(12.9898, 78.233))) * 43758.5453);
}

// Get material at position
int get_material(ivec2 pos) {
    // Check if position is within bounds
    ivec2 texture_size = textureSize(state_texture, 0);
    if (pos.x < 0 || pos.y < 0 || pos.x >= texture_size.x || pos.y >= texture_size.y) {
        return WALL;
    }

    vec3 material_color = texelFetch(state_texture, pos, 0).rgb;
    if (abs(material_color.r - 1.0) < 0.001 && material_color.b <= 0.001)
        return SAND;
    if (material_color.r <= 0.001 && abs(material_color.b - 1.0) < 0.001)
        return WATER;

    return AIR;
}

// 01
// 23

// 21
// 03
void process_solid_block(ivec2 block_pos, inout int block_materials[4], inout int block_states[4]) {
    float rand = rand_value_for_block(block_pos);
	int TL = block_states[0];
	int TR = block_states[1];
	int BL = block_states[2];
	int BR = block_states[3];

	int TL_MAT = block_materials[0];
	int TR_MAT = block_materials[1];
	int BL_MAT = block_materials[2];
	int BR_MAT = block_materials[3];

    // FALLING
    // SX
    // XX
    if (TL == SOLID && TR > SOLID &&
		BL >  SOLID && BR > SOLID) {
		block_materials[0] = BL_MAT;
		block_materials[2] = TL_MAT;
        return;
    }

    // FALLING
    // XS
    // XX
    if (TL > SOLID && TR == SOLID &&
		BL > SOLID && BR >  SOLID) {
		block_materials[1] = BR_MAT;
		block_materials[3] = TR_MAT;
        return;
    }

    // SS
    // XX
    if (TL == SOLID && TR == SOLID &&
		BL >  SOLID && BR >  SOLID) {
		block_materials[0] = BL_MAT;
		block_materials[1] = BR_MAT;
		block_materials[2] = TL_MAT;
		block_materials[3] = TR_MAT;
        return;
    }

    // SS
    // XS
    if (TL == SOLID && TR == SOLID &&
		BL >  SOLID && BR == SOLID) {
		block_materials[0] = BL_MAT;
		block_materials[2] = TL_MAT;
        return;
    }

    // SS
    // SX
    if (TL == SOLID && TR == SOLID &&
		BL == SOLID && BR >  SOLID) {
		block_materials[1] = BR_MAT;
		block_materials[3] = TR_MAT;
        return;
    }

    // XS
    // SX
    if (TL >  SOLID && TR == SOLID &&
		BL == SOLID && BR >  SOLID) {
		block_materials[1] = BR_MAT;
		block_materials[3] = TR_MAT;
        return;
    }

    // SX
    // XS
    if (TL == SOLID && TR >  SOLID &&
		BL >  SOLID && BR == SOLID) {
		block_materials[0] = BL_MAT;
		block_materials[2] = TL_MAT;
        return;
    }

    // TOPPLING
    // XS
    // XS
    if (TL > SOLID && TR == SOLID &&
		BL > SOLID && BR == SOLID && rand <= 0.75) {
		block_materials[1] = BL_MAT;
		block_materials[2] = TR_MAT;
        return;
    }
    // SX
    // SX
    if (TL == SOLID && TR > SOLID &&
		BL == SOLID && BR > SOLID && rand <= 0.75) {
		block_materials[0] = BR_MAT;
		block_materials[3] = TL_MAT;
        return;
    }
}

void process_liquid_block(ivec2 block_pos, inout int block_materials[4], inout int block_states[4]) {
    float rand = rand_value_for_block(block_pos);
	int TL = block_states[0];
	int TR = block_states[1];
	int BL = block_states[2];
	int BR = block_states[3];

	int TL_MAT = block_materials[0];
	int TR_MAT = block_materials[1];
	int BL_MAT = block_materials[2];
	int BR_MAT = block_materials[3];


    // FALLING
    // LX
    // XX
    if (TL == LIQUID &&
        BL >  LIQUID) {
        block_materials[0] = BL_MAT;
        block_materials[2] = TL_MAT;
        return;
    }
    // FALLING
    // XL
    // XX
    if (TR == LIQUID &&
        BR >  LIQUID) {
        block_materials[1] = BR_MAT;
        block_materials[3] = TR_MAT;
        return;
    }

    // LL
    // XX
    if (TL == LIQUID && TR == LIQUID &&
        BL >  LIQUID && BR >  LIQUID) {
        block_materials[0] = BL_MAT;
        block_materials[1] = BR_MAT;
        block_materials[2] = TL_MAT;
        block_materials[3] = TR_MAT;
        return;
    }

    // LL  LS
    // XL  XS
    if (TL == LIQUID && TR < GAS &&
        BL >  LIQUID && BR < GAS) {
        block_materials[0] = BL_MAT;
        block_materials[2] = TL_MAT;
        return;
    }

    // LL  SL
    // LX  SX
    if (TL < GAS && TR == LIQUID &&
        BL < GAS && BR >  LIQUID) {
        block_materials[1] = BR_MAT;
        block_materials[3] = TR_MAT;
        return;
    }

    // XL
    // LX
    if (TL >  LIQUID && TR == LIQUID &&
        BL <  GAS    && BR >  LIQUID) {
        block_materials[1] = BR_MAT;
        block_materials[3] = TR_MAT;
        return;
    }
    // LX
    // XL
    if (TL == LIQUID && TR >  LIQUID &&
        BL >  LIQUID && BR <  GAS) {
        block_materials[0] = BL_MAT;
        block_materials[2] = TL_MAT;
        return;
    }
    // TOPPLING
    // XL
    // XL
    if (TL > LIQUID && TR == LIQUID &&
        BL > LIQUID && BR <  GAS && rand <= 0.75) {
        block_materials[1] = BL_MAT;
        block_materials[2] = TR_MAT;
        return;
    }
    // LX
    // LX
    if (TL == LIQUID && TR > LIQUID &&
        BL <  GAS && BR > LIQUID && rand <= 0.75) {
        block_materials[0] = BR_MAT;
        block_materials[3] = TL_MAT;
        return;
    }


    // For determining direction based on y-coordinate:
    bool is_even_height = (block_pos.y % 2 == 0);

    // LIQUID FLOWING LEFT (y is even)
    // LX
    // SS
    if (TL == LIQUID && TR >  LIQUID &&
        BL <  GAS    && BR <  GAS &&
        is_even_height && rand <= 0.95) {
        block_materials[0] = TR_MAT;
        block_materials[1] = TL_MAT;
        return;
    }

    // LIQUID FLOWING RIGHT (y is odd)
    // XL
    // SS
    if (TL >  LIQUID && TR == LIQUID &&
        BL <  GAS    && BR <  GAS &&
        !is_even_height && rand <= 0.95) {
        block_materials[0] = TR_MAT;
        block_materials[1] = TL_MAT;
        return;
    }
}

void process_block(ivec2 block_pos, inout int block_materials[4], inout int block_states[4]) {
    process_solid_block(block_pos, block_materials, block_states);
	process_liquid_block(block_pos, block_materials, block_states);
}

ivec2 get_block_position(ivec2 pos, int phase) {
    switch (phase)
    {
        case 0: return ivec2(pos.x - (pos.x % 2), pos.y - (pos.y % 2));             // ORIGIN
        case 1: return ivec2(pos.x - ((pos.x + 1) % 2), pos.y - ((pos.y + 1) % 2)); // BOTTOM RIGHT
        case 2: return ivec2(pos.x - (pos.x % 2), pos.y - ((pos.y + 1) % 2));       // BOTTOM
        case 3: return ivec2(pos.x - ((pos.x + 1) % 2), pos.y - ((pos.y) % 2));     // RIGHT
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

// Get material color for visualization
vec3 get_material_color(int material) {
    switch (material)
    {
        case AIR: return vec3(0.1);
        case SAND: return vec3(1.0, 0.8, 0.0);           // Yellow sand
        case WATER: return vec3(0.0, 0.6, 1.0);          // Blue water
        case WALL: return vec3(0.3);
    }
    return vec3(0.0, 1.0, 0.0);  // Green for debugging
}

int get_material_state(int material_type) {
	switch (material_type) {
		case SAND: return SOLID;
		case AIR: return GAS;
		case WATER: return LIQUID;
		case WALL: return UNSWAPPABLE;
	}
	return GAS;
}

void spawn_in_radius(ivec2 pos, ivec2 block_pos, ivec2 center, int radius, int material_type, ivec2 texture_size, inout int block_materials[4], inout int block_states[4]) {
	// 0 to not get out of the screen
	// texture_size is the most right / top, again to not get out of screen
	// center - radius = most left/bottom side of the circle
	// center + radius = most right/top side of the circle
	ivec2 pos_min = max(ivec2(0, 0), ivec2(center) - ivec2(radius));
	ivec2 pos_max = min(texture_size, ivec2(center) + ivec2(radius + 1));
	int distance_to_center = int(length(vec2(pos - center)));
	
	// is the fragment in this circle?
	// yes -> place the material_type in the block
    int index = get_own_index_in_block(pos, block_pos);
	if (distance_to_center < radius) {
		// Inside circle!
        block_materials[index] = material_type;
        block_states[index] = get_material_state(material_type);
	}
}


void fragment() {
    // Get current pixel position
    ivec2 texture_size = textureSize(state_texture, 0);
    ivec2 pos = ivec2(UV * vec2(texture_size));
    int phase = iteration_count % 4;

    // In which block does the fragment reside in
    ivec2 block_pos = get_block_position(pos, phase);

    // TL TR     S X
	// BL BR     X X
	int block_materials[4];
	block_materials[0] = get_material(block_pos + ivec2(0, 0));
	block_materials[1] = get_material(block_pos + ivec2(1, 0));
	block_materials[2] = get_material(block_pos + ivec2(0, 1));
	block_materials[3] = get_material(block_pos + ivec2(1, 1));

    // TL TR    SOLID GAS
	// BL BR    GAS   GAS
	int block_states[4];
	block_states[0] = get_material_state(block_materials[0]);
	block_states[1] = get_material_state(block_materials[1]);
	block_states[2] = get_material_state(block_materials[2]);
	block_states[3] = get_material_state(block_materials[3]);

    // Check for spawned materials
    if (is_spawning) {
		spawn_in_radius(pos, block_pos, mouse_pos, spawn_radius, spawn_material, texture_size, block_materials, block_states);
    }

    process_block(block_pos, block_materials, block_states);

    int index = get_own_index_in_block(pos, block_pos);
    int material_type_in_block = block_materials[index]; // Find my material in the block
    vec3 color = get_material_color(material_type_in_block);

    COLOR = vec4(color, 1.0);
}