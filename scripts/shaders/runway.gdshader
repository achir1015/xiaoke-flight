shader_type spatial;
render_mode diffuse_burley;

// UV.x：沿跑道 0..len 公尺；UV.y：橫向 -w/2..w/2 公尺
uniform float len = 3000.0;
uniform float wid = 45.0;
uniform float wet = 0.0;
uniform float snow = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float av = abs(v);
	float n = hash(floor(vec2(u, v) * 2.0)) * 0.06;
	vec3 c = vec3(0.2, 0.2, 0.21) + n;
	// 輪胎痕
	float tz = smoothstep(250.0, 400.0, u) * (1.0 - smoothstep(700.0, 1100.0, u)) + smoothstep(250.0, 400.0, len - u) * (1.0 - smoothstep(700.0, 1100.0, len - u));
	c = mix(c, vec3(0.1), tz * 0.6 * (1.0 - smoothstep(4.0, 9.0, av)));
	float white = 0.0;
	white += step(wid * 0.5 - 1.2, av);
	white += step(av, 0.45) * step(0.5, fract(u / 60.0)) * step(180.0, u) * step(180.0, len - u);
	float th = step(8.0, u) * step(u, 50.0) + step(8.0, len - u) * step(len - u, 50.0);
	white += th * step(3.0, av) * step(fract(av / 3.4), 0.55) * step(av, wid * 0.5 - 3.0);
	float aim = step(300.0, u) * step(u, 360.0) + step(300.0, len - u) * step(len - u, 360.0);
	white += aim * step(6.0, av) * step(av, 15.0);
	for (int k = 1; k <= 3; k++) {
		float d = 150.0 * float(k) + (k >= 2 ? 300.0 : 0.0);
		float tzm = step(d, u) * step(u, d + 22.0) + step(d, len - u) * step(len - u, d + 22.0);
		white += tzm * step(5.0, av) * step(av, 9.0);
	}
	c = mix(c, vec3(0.92), clamp(white, 0.0, 1.0));
	c = mix(c, vec3(0.92, 0.94, 0.97), snow * 0.7 * (1.0 - tz));
	ALBEDO = c;
	ROUGHNESS = mix(0.9, 0.2, wet);
	SPECULAR = 0.3 + wet * 0.5;
}
