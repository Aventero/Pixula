shader_type canvas_item;

uniform float speed_multiplier : hint_range(0.1, 10.0) = 1.0;

float random (vec2 uv) {
    return fract(sin(dot(uv.xy,
        vec2(12.9898,78.233))) * 43758.5453123);
}

void vertex() {
	float vertical_movement = random(UV) * PI;
	float speed = 2.5 * speed_multiplier;
	float inner_wobble_amount = (UV.x) * 1.2;

	// Start of the sind
	float sin_start = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y * 0.2;
	VERTEX.y = VERTEX.y + vertical_movement * (sin(sin_start + (TIME * speed) + inner_wobble_amount));
}