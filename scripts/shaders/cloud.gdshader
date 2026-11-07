shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix, shadows_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec3 lit = vec3(1.0, 1.0, 1.0);
uniform vec3 shade = vec3(0.62, 0.66, 0.74);
uniform float dark = 0.0;

varying float fade;

void vertex() {
	// 面向攝影機的公告板，尺寸取自實例縮放
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = wp + (right * VERTEX.x + up * VERTEX.y) * sc;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	float d = length(CAMERA_POSITION_WORLD - wp);
	fade = smoothstep(sc * 0.2, sc * 0.8, d) * (1.0 - smoothstep(26000.0, 34000.0, d));
}

void fragment() {
	vec4 t = texture(tex, UV);
	vec3 c = mix(shade, lit, clamp(1.0 - UV.y * 0.9 + t.r * 0.25, 0.0, 1.0));
	c = mix(c, c * vec3(0.45, 0.47, 0.52), dark);
	ALBEDO = c * COLOR.rgb;
	ALPHA = t.a * fade * COLOR.a;
}
