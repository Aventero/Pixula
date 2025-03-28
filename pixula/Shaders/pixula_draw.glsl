#[compute]
#version 450

#include "compute_helper.gdshaderinc"


layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

struct Pixel {
    int material;
    int frame;
    int color_index;
};

layout(set = 0, binding = 0, std430) restrict buffer SimulationBuffer {
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
    ivec2 grid_size;
    bool is_spawning;
    int spawn_radius;
    int spawn_material;
    ivec2 mouse_pos;
} params;

void updateImage(ivec2 self_pos, int material, int color_index) {
    vec4 color;
    switch(material) {
        case AIR:
            color = vec4(0.0, 0.0, 0.0, 0.0); 
            break;
        case SAND:
            if (color_index == -1) {
                color = vec4(1.0, 1.0, 1.0, 1.0);
                break;
            }
            color = vec4(0.76, 0.7, 0.5, 1.0);
            break;
        case WATER:
            color = vec4(0.3, 0.5, 0.8, 0.8); 
            break;
        case WALL:
            color = vec4(1.0, 0.5, 0.5, 1.0);
            break;
        default:
            color = vec4(1.0, 0.0, 1.0, 1.0);
    }
    imageStore(output_image, self_pos, color);
}

int material_color_index_lookup(int material) {
    switch (material) {
        case SAND: return 1;
    }

    return 0;
}

void setup_pixel(int pixel_index, int color_index) {
    if (color_index == -1) {
        material_color_index_lookup(simulation_buffer.data[pixel_index].material);
    }
}

void main() {
    uint index = gl_GlobalInvocationID.y * params.grid_size.x + gl_GlobalInvocationID.x;
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    
    int source_material = simulation_buffer.data[index].material;
    int color_index = simulation_buffer.data[index].color_index;
    updateImage(pos, source_material, color_index);
}