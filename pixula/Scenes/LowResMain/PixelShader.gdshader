shader_type canvas_item;
uniform usampler2D state_texture;
uniform vec4 test_color : source_color;

void fragment() {
    ivec2 pos = ivec2(UV * vec2(textureSize(state_texture, 0)));
    uint value = texelFetch(state_texture, pos, 0).r;
    vec3 color = vec3(1);  

    if(value == 0u) {  // EMPTYasd
        color = vec3(0.1);  // Dark gray
    } else if(value == 1u) {  // SAND dasd
        color = vec3(0.8, 0.7, 0.2);  // Sandy color
    } else if(value == 2u) {  // WATER
        color = vec3(0.2, 0.4, 0.8);  // Blue
    } else if(value == 3u) {  // STONE  <-- Changed from 2u to 3u
        color = vec3(0.5);  // Gray
    }
	
	// asdasdasdasd asdasdasdasd dasdasddd a dasdasddddasdasdasdasdadadddasdsdadaddddddddddddddasdwdasd

    COLOR = vec4(color, 1.0);
}