#[compute]
#version 450

#include "compute_helper.gdshaderinc"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

struct Pixel {
    int material;
    int frame;
    int color_index;
    float velocity_x;
    float velocity_y;
};

layout(set = 0, binding = 0, std430) buffer SimulationBuffer {
    Pixel data[];
} simulation_buffer;

layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(set = 0, binding = 2) uniform sampler2D color_palette;

const int PALETTE_WIDTH = 46;

// should be smaller than 128 bytes cause vulcan things
layout(push_constant, std430) uniform Params {
    int width;
    int height;
    int is_spawning;
    int spawn_radius;   
    int spawn_material;
    int random_spawning_value;
} p;


int get_initial_color_index(int material, ivec2 pos, int frame) {
    ivec2 start_and_stride = ivec2(44, 0);
    switch (material) {
        case SAND: start_and_stride =           ivec2(22,   1); break;
        case WATER: start_and_stride =          ivec2(2,    1); break;
        case AIR: start_and_stride =            ivec2(36,   0); break;
        case ROCK: start_and_stride =           ivec2(18,   0); break;
        case WALL: start_and_stride =           ivec2(38,   0); break;
        case WOOD: start_and_stride =           ivec2(12,   1); break;
        case FIRE: start_and_stride =           ivec2(27,   1); break;
        case WATER_VAPOR: start_and_stride =    ivec2(44,   1); break;
        case WATER_CLOUD: start_and_stride =    ivec2(1,    0); break;
        case LAVA: start_and_stride =           ivec2(25,   1); break;
        case ACID: start_and_stride =           ivec2(9,    1); break;
        case ACID_VAPOR: start_and_stride =     ivec2(10,   0); break;
        case ACID_CLOUD: start_and_stride =     ivec2(6,    0); break;
        case VOID: start_and_stride =           ivec2(30,   0); break;
        case MIMIC: start_and_stride =          ivec2(31,   0); break;
        case SEED: start_and_stride =           ivec2(14,   0); break;
        case PLANT: start_and_stride =          ivec2(7,    1); break;
        case POISON: start_and_stride =         ivec2(33,   0); break;
        case ASH: start_and_stride =            ivec2(42,   1); break;
        case OIL: start_and_stride =            ivec2(24,   0); break;
        case EMBER: start_and_stride =          ivec2(24,   2); break;
        case SMOKE: start_and_stride =          ivec2(37,   0); break;
    }

    ivec2 random_index_pos = ivec2(random_range(pos, frame, start_and_stride.x, start_and_stride.x + start_and_stride.y),  random_range(pos, frame + 1, 0, 1));
    int color_index = (random_index_pos.y * PALETTE_WIDTH) + random_index_pos.x;
    return color_index;
}

ivec2 unconvert_color_index(int color_index) {
    return ivec2(color_index % PALETTE_WIDTH, int(color_index / PALETTE_WIDTH));
}

vec4 srgbToLinear(vec4 srgbColor) {
    vec3 linearRGB;
    linearRGB.r = srgbColor.r <= 0.04045 ? srgbColor.r / 12.92 : pow((srgbColor.r + 0.055) / 1.055, 2.4);
    linearRGB.g = srgbColor.g <= 0.04045 ? srgbColor.g / 12.92 : pow((srgbColor.g + 0.055) / 1.055, 2.4);
    linearRGB.b = srgbColor.b <= 0.04045 ? srgbColor.b / 12.92 : pow((srgbColor.b + 0.055) / 1.055, 2.4);
    return vec4(linearRGB, srgbColor.a);
}

uint getIndexFromPosition(ivec2 position) {
    return position.y * p.width + position.x;
}

void updateImage(ivec2 pos, ivec2 color_index) {
    uint index = getIndexFromPosition(pos);
    vec4 color = texelFetch(color_palette, color_index, 0);
    vec4 linear_color = srgbToLinear(color) * (1.0 + (simulation_buffer.data[index].velocity_y / 4.0));
    imageStore(output_image, pos, linear_color);
}

int setup_pixel(ivec2 pos, uint pixel_index, int material, int frame) {
    int random_color_index = get_initial_color_index(material, pos, frame);
    simulation_buffer.data[pixel_index].color_index = random_color_index;
    return random_color_index;
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