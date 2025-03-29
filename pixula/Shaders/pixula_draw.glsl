#[compute]
#version 450

#include "compute_helper.gdshaderinc"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

struct Pixel {
    int material;
    int frame;
    int color_index;
};

layout(set = 0, binding = 0, std430) buffer SimulationBuffer {
    Pixel data[];
} simulation_buffer;

layout(rgba8, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(set = 0, binding = 2) uniform sampler2D color_palette;

const int PALETTE_WIDTH = 46;

// Materials


// should be smaller than 128 bytes cause vulcan things
layout(push_constant, std430) uniform Params {
    int width;
    int height;
    int is_spawning;
    int spawn_radius;   
    int spawn_material;
    int random_spawning_value;
} p;

// 	{ MaterialType.Air, new[] { 36, 0 } },
// 	{ MaterialType.Sand, new[] { 22, 1 } },
// 	{ MaterialType.Water, new[] { 2, 1 } },
// 	{ MaterialType.Rock, new[] { 18, 0 } },
// 	{ MaterialType.Wall, new[] { 38, 0 } },
// 	{ MaterialType.Wood, new[] { 12, 1} },
// 	{ MaterialType.Fire, new[] { 27, 1} },
// 	{ MaterialType.WaterVapor, new[] { 44, 1} },
// 	{ MaterialType.WaterCloud, new[] { 1, 0} },
// 	{ MaterialType.Lava, new[] { 25, 1} },
// 	{ MaterialType.Acid, new[] { 9, 1} },
// 	{ MaterialType.AcidVapor, new[] { 10, 0} },
// 	{ MaterialType.AcidCloud, new[] { 6, 0} },
// 	{ MaterialType.Void, new[] { 30, 0} },
// 	{ MaterialType.Mimic, new[] { 31, 0} },
// 	{ MaterialType.Seed, new[] { 14, 0} },
// 	{ MaterialType.Plant, new[] { 7, 1} },
// 	{ MaterialType.Poison, new[] { 33, 0} },
// 	{ MaterialType.Ash, new[] { 42, 1} },
// 	{ MaterialType.Oil, new[] { 24, 0} },
// 	{ MaterialType.Ember, new[] { 24, 2} },
// 	{ MaterialType.Smoke, new[] { 37, 0} },


int get_initial_color_index(int material, ivec2 pos, int frame) {
    ivec2 start_and_stride = ivec2(44, 0);
    switch (material) {
        case SAND: start_and_stride = ivec2(22, 1); break;
        case WATER: start_and_stride = ivec2(2, 1); break;
        case AIR: start_and_stride = ivec2(36, 0); break;
    }

    ivec2 random_index_pos = ivec2(random_range(pos, frame, start_and_stride.x, start_and_stride.x + start_and_stride.y),  random_range(pos, frame + 1, 0, 1));
    int color_index = (random_index_pos.y * PALETTE_WIDTH) + random_index_pos.x;
    return color_index;
}

ivec2 unconvert_color_index(int color_index) {
    return ivec2(color_index % PALETTE_WIDTH, int(color_index / PALETTE_WIDTH));
}

void updateImage(ivec2 pos, ivec2 color_index) {
    vec4 color = texelFetch(color_palette, color_index, 0);
    imageStore(output_image, pos, color);
}

int setup_pixel(ivec2 pos, uint pixel_index, int material, int frame) {
    int random_color_index = get_initial_color_index(material, pos, frame);
    simulation_buffer.data[pixel_index].color_index = random_color_index;
    return random_color_index;
}

uint getIndexFromPosition(ivec2 position) {
    return position.y * p.width + position.x;
}

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.x, gl_GlobalInvocationID.y);
    uint pixel_index = getIndexFromPosition(pos);

    int material = simulation_buffer.data[pixel_index].material;
    int frame = simulation_buffer.data[pixel_index].frame;
    int color_index = simulation_buffer.data[pixel_index].color_index;
    
    if (color_index == -1) {
        color_index = setup_pixel(pos, pixel_index, material, frame);
    } 
    
    ivec2 atlas_pos = unconvert_color_index(color_index);
    updateImage(pos, atlas_pos);
    simulation_buffer.data[pixel_index].frame++;
}