shader_type canvas_item;

uniform sampler2D state_texture;
uniform int iteration_count;

void fragment() {
    // Just display the input texture with some modification
    vec4 color = texture(state_texture, UV);
    // Add a slowly moving effect to confirm updates are happening
    float time_effect = float(iteration_count % 100) / 100.0;
    COLOR = color + vec4(time_effect, 0.0, 0.0, 0.0);
}