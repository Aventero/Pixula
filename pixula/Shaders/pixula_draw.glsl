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

const int AIR = 0;
const int SAND = 1;
const int WATER = 2;
const int WALL = 4;

// keep size under 128 bytes
layout(push_constant, std430) uniform Params {
    int width;
    int height;
    int is_spawning;
    int spawn_radius;   
    int spawn_material;
    int random_spawning_value;
} p;


int get_initial_color_index(int material, ivec2 pos, int frame) {
    int color_index = 44;
    switch (material) {
        case SAND: color_index = 21; break;
        case WATER: color_index = 0; break;
        case AIR: color_index = 37; break;
    }

    return random_range(pos, frame, color_index, color_index + 1);
}

void updateImage(ivec2 pos, int color_index) {
    vec4 color = texelFetch(color_palette, ivec2(color_index, 0), 0);
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

void visualizeAccessPattern(ivec2 scrambled_pos) {
    // Original position
    ivec2 original_pos = ivec2(gl_GlobalInvocationID.xy);
    
    // Calculate the distance between original and scrambled positions using GLSL's distance function
    float distance = distance(vec2(original_pos), vec2(scrambled_pos));
    
    // Normalize the distance
    float max_distance = length(vec2(p.width, p.height)) * 0.5;
    float normalized_distance = distance / max_distance;
    
    // Create grayscale color based on distance
    float value = clamp(normalized_distance, 0.0, 1.0);
    
    imageStore(output_image, scrambled_pos, vec4(value, value, value, 1.0));
}

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.x, gl_GlobalInvocationID.y);
    uint pixel_index = getIndexFromPosition(pos);

    int material = simulation_buffer.data[pixel_index].material;
    int frame = simulation_buffer.data[pixel_index].frame;
    int color_index = simulation_buffer.data[pixel_index].color_index;

    
    if (false) {
        visualizeAccessPattern(pos);
        return;
    }

    if (color_index == -1) {
        color_index = setup_pixel(pos, pixel_index, material, frame);
    } 
    
    updateImage(pos, color_index);
    simulation_buffer.data[pixel_index].frame++;
}