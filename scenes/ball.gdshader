shader_type spatial;

uniform vec4 center_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.85, 0.1, 1.0);
uniform float edge_power : hint_range(0.5, 8.0) = 2.0;
uniform float energy : hint_range(0.0, 10.0) = 3.0;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), edge_power);
	vec3 col = mix(center_color.rgb, edge_color.rgb, fresnel);
	ALBEDO = col;
	EMISSION = col * energy;
}