shader_type canvas_item;
render_mode blend_add;

// Holographic/foil overlay for One Piece TCG cards.
// Additive blend preserves full card brightness while projecting moving holographic sheens.

uniform sampler2D u_source : hint_default_black;
uniform vec2 u_mouse = vec2(0.5, 0.5);     // pointer position in UV space [0, 1]
uniform float u_strength = 1.0;            // 0 disables, 1 full foil
uniform int u_style = 0;                   // 0: Rainbow Wave, 1: Starlight Streaks, 2: Cosmo Glitter, 3: Liquid Gold Caustics
uniform float u_parallel = 0.0;            // extra sheen intensity
uniform float u_prize = 0.0;               // prize / gold enhancement
uniform float u_speed = 0.6;               // animation speed

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = sin(dot(p, vec2(127.1, 311.7)));
	return fract(vec2(269.5, 183.3) * n);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = rot * p * 2.0;
		a *= 0.5;
	}
	return v;
}

// Cosine spectrum for smooth optical thin-film interference
vec3 rainbow_palette(float hue) {
	return 0.5 + 0.5 * cos(6.28318 * (hue + vec3(0.0, 0.33, 0.67)));
}

// 4-point sparkling star for galaxy/cosmo foil
float star(vec2 p, float flare) {
	float d = length(p);
	float l = 0.015 / (d + 0.005);
	float cross_beam = max(
		1.0 / (abs(p.x) * 35.0 + abs(p.y) * 4.0 + 0.04),
		1.0 / (abs(p.y) * 35.0 + abs(p.x) * 4.0 + 0.04)
	) * flare;
	return clamp(l + cross_beam * 0.4, 0.0, 2.5);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (base.a < 0.02) {
		base = texture(u_source, UV);
	}

	float visible = step(0.02, base.a) * step(0.01, u_strength);
	if (visible < 0.5) {
		COLOR = vec4(0.0);
	} else {
		float t = TIME * u_speed;
		vec2 mouse_offset = (u_mouse - vec2(0.5)) * 0.4;
		vec2 uv = UV;
		vec3 holo = vec3(0.0);

		// Light reflection hotspot following mouse
		vec2 cursor = u_mouse;
		if (cursor.x < 0.0) {
			cursor = vec2(0.5 + 0.35 * sin(t * 0.7), 0.5 + 0.35 * cos(t * 0.5));
		}
		float sheen = exp(-dot(uv - cursor, uv - cursor) * 16.0);

		if (u_style == 1) {
			// ==============================================================
			// STYLE 1: Secret Rare / Starlight Streaks & Diagonal Gratings
			// ==============================================================
			float diag1 = uv.x + uv.y + t * 0.25 + mouse_offset.x * 0.8;
			float diag2 = uv.x - uv.y - t * 0.18 + mouse_offset.y * 0.8;

			// Micro-groove grating reflection
			float lines1 = abs(sin(diag1 * 45.0));
			float lines2 = abs(cos(diag2 * 35.0));
			float grating = pow(lines1 * lines2, 3.0) * 2.2;

			// Broad diagonal light sweep beams
			float beam1 = pow(0.5 + 0.5 * sin(diag1 * 3.5), 6.0);
			float beam2 = pow(0.5 + 0.5 * cos(diag2 * 4.0), 5.0);

			float hue = fract(diag1 * 1.5 + diag2 * 0.8);
			vec3 spec = rainbow_palette(hue);

			// Sparkle speckles along the diffraction lines
			float n = vnoise(uv * 40.0 + vec2(t * 0.8, -t * 0.5));
			float sparkle = smoothstep(0.70, 0.85, n) * 1.8;

			holo = spec * (beam1 * 0.35 + beam2 * 0.25 + grating * 0.20 + sheen * 0.30);
			holo += mix(vec3(1.0), spec, 0.5) * sparkle * 0.45;

		} else if (u_style == 2) {
			// ==============================================================
			// STYLE 2: Cosmo / Galaxy Glitter & Starbursts
			// ==============================================================
			vec2 moved_uv = uv * 6.0 + vec2(t * 0.15, -t * 0.12) + mouse_offset;
			vec2 cell_id = floor(moved_uv);
			vec2 cell_f = fract(moved_uv);

			float stars_accum = 0.0;
			vec3 star_color_accum = vec3(0.0);

			// Check 3x3 neighboring cells for stars/sparkles
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					vec2 g = vec2(float(dx), float(dy));
					vec2 rand_p = hash22(cell_id + g);
					vec2 star_pos = g + rand_p - cell_f;

					// Twinkle phase
					float twinkle = sin(t * 2.5 + rand_p.x * 6.28) * 0.5 + 0.5;
					twinkle = pow(twinkle, 3.0);

					float s = star(star_pos, twinkle);
					stars_accum += s * 0.25;

					vec3 c_spec = rainbow_palette(rand_p.y + t * 0.1);
					star_color_accum += c_spec * s * 0.25;
				}
			}

			// Floating soft cosmic orbs
			float orb_noise = vnoise(uv * 7.0 + vec2(sin(t * 0.4), cos(t * 0.3)) * 0.5);
			float orb = smoothstep(0.55, 0.75, orb_noise);
			vec3 orb_spec = rainbow_palette(uv.x * 1.5 + t * 0.2);

			holo = star_color_accum * 0.85 + vec3(stars_accum * 0.35);
			holo += orb_spec * orb * 0.25;
			holo += rainbow_palette(uv.y * 2.0 + t * 0.3) * sheen * 0.35;

		} else if (u_style == 3) {
			// ==============================================================
			// STYLE 3: Liquid Gold / Caustic Relief (Special / Leader / Alt-Art)
			// ==============================================================
			vec2 warp_uv = uv * 3.5 + mouse_offset;
			float q = fbm(warp_uv + vec2(t * 0.2, t * 0.15));
			float r = fbm(warp_uv + vec2(q * 2.0, q * 2.0) - vec2(t * 0.1, -t * 0.25));
			float wave = pow(r, 2.2) * 2.5;

			vec3 gold_dark = vec3(0.85, 0.60, 0.15);
			vec3 gold_bright = vec3(1.0, 0.92, 0.55);
			vec3 gold = mix(gold_dark, gold_bright, wave);

			float edge_dist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
			float edge_mask = 1.0 - smoothstep(0.02, 0.09, edge_dist);

			vec3 fringe = rainbow_palette(wave * 2.0 + t * 0.2);

			holo = gold * wave * 0.45;
			holo += mix(gold, fringe, 0.4) * sheen * 0.50;
			holo += gold_bright * edge_mask * 0.40;

		} else {
			// ==============================================================
			// STYLE 0 (Default): Super Rare Rainbow Wave
			// ==============================================================
			float hue = fract(uv.x * 2.2 + uv.y * 1.1 + t * 0.30 + mouse_offset.x);
			vec3 spectrum = rainbow_palette(hue);

			float grain = vnoise(uv * 32.0 + vec2(t * 0.9, -t * 0.7));
			float sparkle = smoothstep(0.65, 0.80, grain);
			vec3 spark_col = mix(vec3(1.0), spectrum, 0.6);

			float diag_sweep = fract((uv.x + uv.y) * 0.8 - t * 0.22);
			float sweep_beam = exp(-pow(diag_sweep - 0.5, 2.0) * 28.0);

			holo = spectrum * (0.15 + 0.20 * u_parallel);
			holo += spectrum * sheen * (0.18 + 0.28 * u_parallel);
			holo += spectrum * sweep_beam * 0.30;
			holo += spark_col * sparkle * 0.30;
		}

		// Global prize boost
		if (u_prize > 0.0) {
			vec3 gold_accent = vec3(1.0, 0.85, 0.35);
			holo = mix(holo, gold_accent * length(holo) * 1.4, 0.35 * u_prize);
		}

		float alpha = base.a * clamp(u_strength, 0.0, 1.0);
		COLOR = vec4(holo * alpha, 1.0);
	}
}