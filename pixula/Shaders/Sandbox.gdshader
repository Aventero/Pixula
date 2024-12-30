shader_type canvas_item;

uniform float scale : hint_range(0.1, 10.0) = 2.0;

void vertex() {
}

float mySine() {
	return (sin(TIME) + 1.0) * 0.5;
}

void fragment() {
	vec4 pixelColor = texture(TEXTURE, UV * scale * mySine());
	COLOR = pixelColor * mySine();
}
