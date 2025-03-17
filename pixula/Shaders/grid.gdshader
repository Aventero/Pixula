shader_type canvas_item;

// Basic grid parameters
uniform bool show_grid = true;
uniform int grid_scale = 8; // Cell size in pixels
uniform int current_phase = 0; // 0-3 for Margolus phases
uniform float line_width = 1.0; // Width of grid lines



void fragment() {
    // Sample the base texture
    vec4 color = texture(TEXTURE, UV);

    // Only draw grid if enabled
    if (show_grid) {
        // Convert UV to pixel position
        vec2 pixel_pos = UV * vec2(textureSize(TEXTURE, 0));

        // Get grid cell size and phase offset
        float cell_size = float(grid_scale);
        float half_cell = cell_size / 2.0;

        // Phase offsets
        vec2 offset = vec2(0.0, 0.0);
        if (current_phase % 4 == 1) {
            offset = vec2(half_cell, half_cell); // 1, 1
        } else if (current_phase % 4 == 2) {
            offset = vec2(0.0, half_cell); 		// 0, 1
        } else if (current_phase % 4 == 3) {
            offset = vec2(half_cell, 0.0); 		// 1, 0
        }

        // Apply offset to position
        pixel_pos -= offset;

        // Simple grid check
        bool on_grid = false;
        if (mod(pixel_pos.x, cell_size) < line_width || mod(pixel_pos.y, cell_size) < line_width) {
            on_grid = true;
        }

        // Set grid color based on phase
        vec4 grid_color;
        if (current_phase % 4 == 0)
            grid_color = vec4(1.0, 0.0, 0.0, 0.1); // RED
        else if (current_phase % 4 == 1)
            grid_color = vec4(0.0, 1.0, 0.0, 0.1); // GREEN
        else if (current_phase % 4 == 2)
            grid_color = vec4(0.0, 0.0, 1.0, 0.1); // BLUE
        else
            grid_color = vec4(1.0, 1.0, 0.0, 0.1); // YELLOW

        // Draw grid lines
        if (on_grid) {
            color = grid_color;
        }
    }

    COLOR = color;
}