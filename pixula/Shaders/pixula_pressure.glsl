#[compute]

#version 450

#define MAX_MOUSE_POSITIONS 200

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

#include "compute_helper.gdshaderinc"

layout(set = 0, binding = 0, std430) restrict buffer InputBuffer {
    Pixel pixels[];
} input_buffer;

layout(set = 0, binding = 1, std430) buffer OutputBuffer {
    Pixel pixels[];
} output_buffer;

layout(set = 0, binding = 2, std430) restrict buffer MousePosBuffer {
    int count;
    int x[MAX_MOUSE_POSITIONS];
    int y[MAX_MOUSE_POSITIONS];
} mouse_buffer;


// keep size under 128 bytes
layout(push_constant, std430) uniform Params {
    int width;
    int height;
    int is_spawning;
    int spawn_radius;   
    int spawn_material;
    int random_spawning_value;
} p;

#include "compute_core.gdshaderinc"


int getAirNeighbors(ivec2 pos) {
    int air_neighbors = 0;
    for (int y = -5; y <= 0; y++) {
        for (int x = -1; x <= 1; x++) {
            if (x == 0 && y == 0) continue;
            
            ivec2 check_pos = pos + ivec2(x, y);
            if (!inBounds(check_pos)) continue;
            
            if (getMaterialType(input_buffer.pixels[getIndexFromPosition(check_pos)].material) != LIQUID) {
                air_neighbors++;
            }
        }
    }
    return air_neighbors;
}

float calcDensity(ivec2 pos) {
    int liquids = 0;
    int cells = 0;
    int area = 3;

    for (int y = -area; y <= area; y++) {
        for (int x = -area; x <= area; x++) {
            if (x == 0 && y == 0) continue;
            
            ivec2 check_pos = pos + ivec2(x, y);
            if (!inBounds(check_pos)) continue;
            
            cells++;
            if (getMaterialType(input_buffer.pixels[getIndexFromPosition(check_pos)].material) == LIQUID) {
                liquids++;
            }
        }
    }
    
    return float(liquids) / float(cells);
}

void calculatePressure(uint index, ivec2 pos) {
    Pixel pixel = input_buffer.pixels[index];
    if (lockPixel(index, pixel.material)) {
        output_buffer.pixels[index].pressure_x = 0.0;
        output_buffer.pixels[index].pressure_y = 0.0;
        unlockPixel(index, pixel.material);
    }
    
    if (getMaterialType(pixel.material) == LIQUID) {
        float pressure_x = 0.0;
        float pressure_y = 0.0;
        
        bool is_surface_particle = false;
        int depth = 0;
        int air_neighbors = getAirNeighbors(pos);
        
        is_surface_particle = (air_neighbors > 0);
        
         // 0 - 1 how much water is around this pixel -> "compactness"
        float density = calcDensity(pos);

        // This is how the liquid would like to behave
        // Higher -> More attraction
        float ideal_density = 0.1; 

        // Resulting in compression which "pushes liquid apart" to get "ideal" again (Alot of water around)
        // Or it might pull together in negative values (little water around)
        float compression = density - ideal_density;
        
        // Calculate the pressure that this pixel receives
        // positive is attraction towards the other pixel
        // negative is the repulsion of that pixel from 
        int pressure_area = 3;
        for (int y = -pressure_area; y <= pressure_area; y++) {
            for (int x = -pressure_area; x <= pressure_area; x++) {
                if (x == 0 && y == 0) continue;
                
                ivec2 check_pos = pos + ivec2(x, y);
                if (!inBounds(check_pos)) continue;
                
                uint check_index = getIndexFromPosition(check_pos);
                int material = input_buffer.pixels[check_index].material;
                
                // The further away, less power
                float distance = length(vec2(x, y));
                float weight = 1.0 / max(1.0, distance * 1.5);
                
                int material_type = getMaterialType(material);
                if (material_type == LIQUID) {
                    float attraction = compression * 0.8;
                    pressure_x -= float(x) * weight * attraction;
                    pressure_y -= float(y) * weight * attraction * 1.0/(air_neighbors + 1.0);
                } 
                else if (material_type == SOLID) {
                    pressure_x -= float(x) * weight * 0.3;
                    pressure_y -= float(y) * weight * 0.3 * 1.0/(air_neighbors + 1.0);;
                }
                else if (getMaterialType(material) == GAS) {
                    pressure_x -= float(x) * weight * 0.01;
                }
            }
        }
        pressure_y += 0.3;
        
        // Store
        if (lockPixel(index, pixel.material)) {
            output_buffer.pixels[index].pressure_x = pressure_x;
            output_buffer.pixels[index].pressure_y = pressure_y;
            unlockPixel(index, pixel.material);
        }
    }
}

void spawn_in_radius(uint source_index, ivec2 source, ivec2 center, int radius, int spawn_material) {
    int distance_to_center = int(length(vec2(source - center)));
	if (distance_to_center < radius) {
        int rand_val = random_range(source, p.random_spawning_value, 1, 100);

        Pixel current_pixel = input_buffer.pixels[source_index];
        Pixel spawn_pixel = Pixel(spawn_material, rand_val, -1, 0.0, 0.0, 0, 0.0, 0.0, 0.0, 0.0);
        if (current_pixel.material == spawn_pixel.material) return;
        if (!lockPixel(source_index, current_pixel.material)) return;
        
        setPixelDataAndUnlock(source_index, spawn_pixel);
	}
}

void try_spawning(uint index, ivec2 pos) {
    // Mouse Spawning
    int count = min(mouse_buffer.count, MAX_MOUSE_POSITIONS);
    for (int i = 0; i < count; i++) {
        ivec2 mouse_pos = ivec2(mouse_buffer.x[i], mouse_buffer.y[i]);
        spawn_in_radius(index, pos, mouse_pos, p.spawn_radius, p.spawn_material);
    }
}

// In the main function, branch based on current pass
void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.x, gl_GlobalInvocationID.y);
    uint index = getIndexFromPosition(pos);
    try_spawning(index, pos);
    barrier();
    calculatePressure(index, pos);
}

