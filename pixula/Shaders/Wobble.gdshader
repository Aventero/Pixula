shader_type spatial;

float random (vec2 uv) {
    return fract(sin(dot(uv.xy,
        vec2(12.9898,78.233))) * 43758.5453123);
}
float noise(vec2 uv) {
    vec2 uv_index = floor(uv);
    vec2 uv_fract = fract(uv);

    // Four corners in 2D of a tile
    float a = random(uv_index);
    float b = random(uv_index + vec2(1.0, 0.0));
    float c = random(uv_index + vec2(0.0, 1.0));
    float d = random(uv_index + vec2(1.0, 1.0));

    vec2 blur = smoothstep(0.0, 1.0, uv_fract);

    return mix(a, b, blur.x) +
            (c - a) * blur.y * (1.0 - blur.x) +
            (d - b) * blur.x * blur.y;
}
float fbm(vec2 uv) {
    int octaves = 6;
    float amplitude = 0.5;
    float frequency = 3.0;
	float value = 0.0;
	
    for(int i = 0; i < octaves; i++) {
        value += amplitude * noise(frequency * uv);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// shine
uniform vec4 shine_color: source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float cycle_interval: hint_range(0.5, 5.0) = 10.0;
uniform float shine_speed: hint_range(1.0, 5.0) = 0.1;
uniform float shine_width: hint_range(1.0, 100.0) = 100.0;
uniform float shine_smoothness: hint_range(0.0, 1.0) = 0.5;
uniform float emission_strength: hint_range(0.0, 5.0) = 1.0;
uniform float view_falloff: hint_range(0.0, 5.0) = 1.0;

// up down
group_uniforms Sine;
uniform bool do_abs;
uniform bool do_quantize;
uniform float quantize_to : hint_range(0, 2, 0.01) = 10;
uniform vec2 sine_amplitude = vec2(0.1, 0.0);
uniform vec2 sine_speed = vec2(1.0, 0.0);

void vertex() {
	vec2 s = sin(TIME * sine_speed);
	if (do_abs) {
		s = abs(s);
	}
	VERTEX.yz = VERTEX.yz + (s * sine_amplitude);
	if (do_quantize) {
		VERTEX = round(VERTEX / quantize_to);
		VERTEX *= quantize_to;
	}
	
	//VERTEX = VERTEX + (VERTEX * fbm(VERTEX.xy) * 1.5);
	// Called for every vertex the material is visible on.
}

void fragment() {
 vec3 vertex = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float width = shine_width * 0.001 * cycle_interval;
	float frequency = smoothstep(-1.0, 1.0, sin(vertex.z * cycle_interval + TIME * shine_speed * cycle_interval)) * width;
    ALBEDO = COLOR.rgb;
	float view_dot = pow(1.0 - dot(NORMAL, VIEW), view_falloff);
    float shine = smoothstep(0.01, shine_smoothness, view_dot * frequency);
    EMISSION = shine_color.rgb * shine * emission_strength;
}

