shader_type canvas_item;

void fragment() {
    // Get the texture color at the current UV coordinate
    vec4 tex_color = texture(TEXTURE, UV);
    COLOR = tex_color;
}