shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// 環繞攝影機的圓筒：捲動的雨絲或雪花
uniform float amount = 0.0;
uniform float snow = 0.0;
uniform float speed = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV * vec2(60.0, 6.0);
	float a = 0.0;
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		vec2 q = uv * (1.0 + fk * 0.6) + vec2(fk * 0.37, 0.0);
		q.y += TIME * mix(4.5, 0.5, snow) * speed * (1.0 + fk * 0.3);
		q.x += snow * sin(TIME * 0.8 + q.y * 0.5 + fk) * 0.3;
		vec2 id = floor(q);
		vec2 f = fract(q);
		float h = hash(id + fk * 13.0);
		if (h > 0.55) {
			float x = abs(f.x - fract(h * 7.3));
			if (snow > 0.5) {
				float d = length(vec2(x, (f.y - fract(h * 3.1)) * 0.25));
				a += smoothstep(0.08, 0.0, d) * 0.9;
			} else {
				a += smoothstep(0.03, 0.0, x) * smoothstep(0.0, 0.3, f.y) * smoothstep(1.0, 0.6, f.y) * 0.55;
			}
		}
	}
	ALBEDO = mix(vec3(0.75, 0.8, 0.88), vec3(1.0), snow);
	ALPHA = clamp(a, 0.0, 1.0) * amount;
}
