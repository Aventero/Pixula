#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer SimulationBuffer {
    int data[];
} simulation_buffer;

layout(rgba8, set = 0, binding = 1) uniform writeonly image2D output_image;

const int AIR = 0;
const int SAND = 1;
const int WATER = 2;
const int WALL = 4;

const uint WIDTH = 4096*4; 
const uint HEIGHT = 4096*4;


void updateImage(ivec2 self_pos, int material) {
    vec4 color;
    switch(material) {
        case AIR:
            color = vec4(0.0, 0.0, 0.0, 0.0); 
            break;
        case SAND:
            color = vec4(0.76, 0.7, 0.5, 1.0);
            break;
        case WATER:
            color = vec4(0.3, 0.5, 0.8, 0.8); 
            break;
        case WALL:
            color = vec4(0.5, 0.5, 0.5, 1.0);
            break;
        default:
            color = vec4(1.0, 0.0, 1.0, 1.0);
    }
    
    imageStore(output_image, self_pos, color);
}


void main() {
    uint index = gl_GlobalInvocationID.y * WIDTH + gl_GlobalInvocationID.x;
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    
    int material = simulation_buffer.data[index];
    updateImage(pos, material);
}