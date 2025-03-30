shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float glow_intensity : hint_range(0.0, 2.0) = 0.4;
uniform float glow_threshold : hint_range(0.0, 1.0) = 0.5;
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    // Get the original scene color
    vec4 original_color = texture(screen_texture, SCREEN_UV);

    // Extract bright areas (anything over the threshold)
    float brightness = max(max(original_color.r, original_color.g), original_color.b);
    vec4 bright_areas = (brightness > glow_threshold) ? original_color : vec4(0.0);

    // Blur the bright areas (simplified blur using adjacent pixels)
    vec4 blur = vec4(0.0);
    float blur_size = 0.015;

    for(float x = -2.0; x <= 2.0; x++) {
        for(float y = -2.0; y <= 2.0; y++) {
            vec2 offset = vec2(x, y) * blur_size;
            blur += texture(screen_texture, SCREEN_UV + offset) *
                   (brightness > glow_threshold ? 1.0 : 0.0);
        }
    }
    blur /= 25.0; // Average of the samples

    // Mix the original color with the glow effect
    vec4 glow = blur * glow_intensity * glow_color;
    COLOR = original_color + glow;
}