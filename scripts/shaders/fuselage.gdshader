shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 機身塗裝（以模型座標計算）：白色機身、橘藍腰線、窗戶列、機腹灰、駕駛艙窗、艙門
uniform vec3 stripe1 : source_color = vec3(0.95, 0.53, 0.2);
uniform vec3 stripe2 : source_color = vec3(0.18, 0.43, 0.82);
uniform vec3 body : source_color = vec3(0.96, 0.97, 0.98);
uniform float nose_z = -28.5;
uniform float len = 57.0;
uniform float radius = 2.9;
uniform float night = 0.0;

varying vec3 lp;

void vertex() { lp = VERTEX; }

void fragment() {
	float t = (lp.z - nose_z) / len;
	vec3 c = body;
	float y = lp.y;
	float r = radius;
	c = mix(c, vec3(0.78, 0.8, 0.84), smoothstep(-0.25 * r, -0.45 * r, y));
	float s1 = step(-0.36 * r, y) * step(y, -0.26 * r);
	float s2 = step(-0.5 * r, y) * step(y, -0.38 * r);
	float sm = step(0.1, t) * step(t, 0.86);
	c = mix(c, stripe1, s1 * sm);
	c = mix(c, stripe2, s2 * sm);
	float wy = step(0.08 * r, y) * step(y, 0.24 * r);
	float wz = step(0.17, t) * step(t, 0.84);
	float f = fract(lp.z / 0.95);
	float win = wy * wz * step(0.32, f) * step(f, 0.68);
	float door = 0.0;
	for (int k = 0; k < 4; k++) {
		float dz = nose_z + len * (0.16 + float(k) * 0.215);
		float dd = abs(lp.z - dz);
		door += step(0.88, dd) * step(dd, 0.98) * step(-0.3 * r, y) * step(y, 0.4 * r);
		door += step(dd, 0.98) * step(0.38 * r, y) * step(y, 0.41 * r);
		win *= step(1.2, dd);
	}
	c = mix(c, vec3(0.06, 0.08, 0.12), win);
	c = mix(c, vec3(0.6, 0.63, 0.68), clamp(door, 0.0, 1.0));
	float cw = step(0.012, t) * step(t, 0.05) * step(0.1 * r, y) * step(y, 0.36 * r);
	c = mix(c, vec3(0.05, 0.07, 0.11), cw);
	ALBEDO = c;
	ROUGHNESS = mix(0.32, 0.08, clamp(win + cw, 0.0, 1.0));
	METALLIC = 0.05;
	EMISSION = vec3(1.0, 0.86, 0.6) * win * night * 0.9;
}
