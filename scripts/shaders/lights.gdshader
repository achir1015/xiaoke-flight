shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// 跑道燈與航行燈：遠處保持最小可見大小
uniform float intensity = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float min_px = 0.0022;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float base = length(MODEL_MATRIX[0].xyz);
	float d = length(CAMERA_POSITION_WORLD - wp);
	float sc = max(base, d * min_px);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = wp + (right * VERTEX.x + up * VERTEX.y) * sc;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float a = clamp(1.0 - r, 0.0, 1.0);
	a = a * a;
	ALBEDO = COLOR.rgb * tint * a * intensity * 2.0;
	ALPHA = a;
}
