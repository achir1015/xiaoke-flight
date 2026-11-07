shader_type spatial;
render_mode diffuse_burley;

// 城市大樓：窗格與夜間燈光（MultiMesh 顏色＝外牆色）
uniform float night = 0.0;

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 tint;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = COLOR.rgb;
}

void fragment() {
	vec3 c = tint;
	float roof = step(0.7, wnrm.y);
	float h = (abs(wnrm.x) > 0.5) ? wpos.z : wpos.x;
	vec2 g = vec2(h / 3.2, wpos.y / 3.4);
	vec2 f = fract(g);
	float win = step(0.18, f.x) * step(f.x, 0.82) * step(0.25, f.y) * step(f.y, 0.8) * (1.0 - roof);
	float lit = step(0.55, hash(floor(g) + floor(wpos.xz / 50.0)));
	c = mix(c, c * 0.45 + vec3(0.05, 0.08, 0.12), win * 0.75);
	c = mix(c, vec3(0.35, 0.36, 0.38), roof);
	ALBEDO = c;
	ROUGHNESS = mix(0.8, 0.25, win);
	EMISSION = vec3(1.0, 0.85, 0.55) * win * lit * night * 1.2;
}
