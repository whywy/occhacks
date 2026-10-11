shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 side_color : source_color = vec4(0.15, 0.55, 1.0, 1.0);
uniform vec3 ball_world_position = vec3(0.0);
uniform float border_width = 0.018;
uniform float base_alpha = 0.22;
uniform float border_alpha = 0.88;
uniform float proximity_start = 0.35;
uniform float proximity_end = 5.0;
uniform float rainbow_speed = 0.12;
uniform float rainbow_glow = 2.4;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float edge_distance = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float border = 1.0 - smoothstep(border_width * 0.65, border_width, edge_distance);
	float ball_distance = distance(world_position, ball_world_position);
	float proximity = 1.0 - smoothstep(proximity_start, proximity_end, ball_distance);
	float face_brightness = 0.45 + proximity * 1.8;

	// Walk around the square UV perimeter so every edge forms one continuous rainbow.
	float perimeter_position;
	if (UV.y <= UV.x && UV.y <= 1.0 - UV.x) {
		perimeter_position = UV.x;
	} else if (UV.x >= UV.y && UV.x >= 1.0 - UV.y) {
		perimeter_position = 1.0 + UV.y;
	} else if (UV.y >= UV.x && UV.y >= 1.0 - UV.x) {
		perimeter_position = 2.0 + (1.0 - UV.x);
	} else {
		perimeter_position = 3.0 + (1.0 - UV.y);
	}
	float hue = fract(perimeter_position * 0.25 + TIME * rainbow_speed);
	vec3 rainbow = 0.5 + 0.5 * cos(6.2831853 * (hue + vec3(0.0, 0.6666667, 0.3333333)));

	ALBEDO = mix(side_color.rgb * face_brightness, rainbow, border);
	EMISSION = mix(side_color.rgb * (0.06 + proximity * 0.48), rainbow * rainbow_glow, border);
	ALPHA = mix(base_alpha, border_alpha, border);
}
