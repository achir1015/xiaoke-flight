shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float snow = 0.0;
uniform float snow_line = 900.0;
uniform float wet = 0.0;
uniform float night = 0.0;

varying vec3 wpos;
varying vec2 fu;
varying vec3 vcol;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	fu = UV;
	vcol = COLOR.rgb;
}

void fragment() {
	vec3 c = vcol;
	float n = vnoise(wpos.xz * 0.004) * 0.45 + vnoise(wpos.xz * 0.03) * 0.3 + vnoise(wpos.xz * 0.25) * 0.25;
	c *= 0.8 + 0.4 * n;
	vec3 emit = vec3(0.0);
	if (fu.x > 0.01) {
		vec2 g = wpos.xz / vec2(190.0, 130.0);
		g.x += floor(g.y) * 0.37;
		vec2 id = floor(g);
		float h = hash(id);
		vec3 fc = mix(vec3(0.42, 0.53, 0.22), vec3(0.6, 0.6, 0.33), h);
		if (h > 0.72) fc = vec3(0.3, 0.46, 0.2);
		if (h < 0.12) fc = vec3(0.52, 0.45, 0.32);
		if (h > 0.9) fc = vec3(0.35, 0.5, 0.55);
		vec2 f = fract(g);
		float edge = smoothstep(0.0, 0.035, f.x) * smoothstep(0.0, 0.05, f.y);
		fc *= 0.82 + 0.18 * edge;
		c = mix(c, fc * (0.88 + 0.24 * n), fu.x);
	}
	if (fu.y > 0.01) {
		vec2 g = wpos.xz / 48.0;
		vec2 f = fract(g);
		float road = 1.0 - step(0.12, f.x) * step(0.12, f.y);
		float hb = hash(floor(g));
		float hb2 = hash(floor(g * 0.25) + 7.0);
		vec3 uc = mix(vec3(0.36, 0.36, 0.36), vec3(0.56, 0.54, 0.5), hb);
		uc *= 0.85 + 0.3 * hash(floor(wpos.xz / 9.0));
		if (hb > 0.8 || hb2 > 0.88) uc = vec3(0.26, 0.38, 0.22);
		uc = mix(uc, vec3(0.2, 0.2, 0.22), road);
		c = mix(c, uc, fu.y);
		emit = night * fu.y * (road * vec3(1.0, 0.72, 0.38) * 0.9 + (1.0 - road) * step(0.78, hb) * vec3(1.0, 0.9, 0.62) * 0.35);
	}
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float s = smoothstep(snow_line, snow_line + 160.0, wpos.y + n * 120.0) * smoothstep(0.5, 0.8, wn.y);
	c = mix(c, vec3(0.93, 0.95, 0.98), clamp(s * snow, 0.0, 1.0));
	ALBEDO = c * (1.0 - wet * 0.25);
	ROUGHNESS = 0.95 - wet * 0.35;
	SPECULAR = 0.2 + wet * 0.3;
	EMISSION = emit;
}
