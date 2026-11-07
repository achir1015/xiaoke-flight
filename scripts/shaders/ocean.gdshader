shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D hmap : filter_linear, repeat_disable;
uniform vec4 hrect = vec4(-21000.0, -25500.0, 36000.0, 51000.0);
uniform float storm = 0.0;
uniform float night = 0.0;
uniform vec3 deep_col = vec3(0.03, 0.17, 0.33);
uniform vec3 shallow_col = vec3(0.1, 0.48, 0.55);

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float waves(vec2 p, float t) {
	float a = vnoise(p * 0.035 + vec2(t * 0.05, t * 0.03));
	a += vnoise(p * 0.11 - vec2(t * 0.09, -t * 0.04)) * 0.5;
	a += vnoise(p * 0.4 + vec2(t * 0.2, t * 0.13)) * 0.25;
	return a;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 p = wpos.xz;
	float e = 1.5;
	float s = 1.0 + storm * 2.5;
	float h0 = waves(p, t);
	float hx = waves(p + vec2(e, 0.0), t);
	float hz = waves(p + vec2(0.0, e), t);
	vec3 wn = normalize(vec3((h0 - hx) * s * 1.6, 1.0, (h0 - hz) * s * 1.6));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	vec2 uv = (p - hrect.xy) / hrect.zw;
	float depth = 40.0;
	if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
		float hh = texture(hmap, uv).r * 80.0 - 40.0;
		depth = -hh;
	}
	float sh = 1.0 - smoothstep(0.0, 22.0, depth);
	vec3 col = mix(deep_col, shallow_col, sh);
	col = mix(col, vec3(0.2, 0.24, 0.27), storm * 0.55);
	float foam = smoothstep(2.5, 0.0, depth) * (0.5 + 0.5 * vnoise(p * 0.2 + t * 0.3));
	foam += storm * smoothstep(0.78, 0.95, vnoise(p * 0.05 + t * 0.1) * 0.6 + vnoise(p * 0.3) * 0.4) * 0.8;
	col = mix(col, vec3(0.9, 0.93, 0.95), clamp(foam, 0.0, 1.0));
	float dist = length(CAMERA_POSITION_WORLD - wpos);
	ALBEDO = col * (1.0 - night * 0.6);
	ROUGHNESS = mix(0.06, 0.25, storm) + smoothstep(3000.0, 20000.0, dist) * 0.2;
	METALLIC = 0.0;
	SPECULAR = 0.65;
	float fres = pow(1.0 - clamp(dot(normalize(CAMERA_POSITION_WORLD - wpos), wn), 0.0, 1.0), 4.0);
	EMISSION = vec3(0.35, 0.5, 0.65) * fres * 0.25 * (1.0 - night);
}
