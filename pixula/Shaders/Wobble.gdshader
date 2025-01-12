shader_type canvas_item;

void vertex() {
	float vertical_movement = 1.0;
	float interval = PI;
	float inner_wobble_amount = (UV.x) * 1.5;
	
	// Start of the sin
	float sin_start = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y * 0.2;
	VERTEX.y = VERTEX.y + vertical_movement * (sin(sin_start + (TIME * interval) + inner_wobble_amount));
}
