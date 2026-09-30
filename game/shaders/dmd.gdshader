shader_type canvas_item;
render_mode unshaded;

// Dot-matrix display: `dmd_tex` is the 128x32 frame buffer (L8, one texel per
// dot, value = brightness). Every dot is drawn as a round amber LED with a
// soft glow that bleeds into its neighbours.
//
// Background: fully transparent — except a dark "stroke" that hugs whatever is
// lit (up to 2 dots around it), like outlined text. Without it the amber dots
// vanished against the bright gold artwork of the table; with it the display
// still floats over the playfield with no black panel behind it.

uniform sampler2D dmd_tex : filter_nearest, repeat_disable;
uniform vec2 grid = vec2(128.0, 32.0);
uniform vec4 lit_color : source_color = vec4(1.0, 0.666667, 0.0, 1.0);
uniform vec4 backdrop_color : source_color = vec4(0.03, 0.015, 0.0, 1.0);
uniform float backdrop_alpha = 0.82;
uniform float dot_radius = 0.42;
uniform float glow_strength = 0.7;
uniform float off_alpha = 0.08;
uniform float master_alpha = 1.0;

float level_at(vec2 cell) {
	if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= grid.x || cell.y >= grid.y) {
		return 0.0;
	}
	return texture(dmd_tex, (cell + 0.5) / grid).r;
}

float bleed_from(vec2 cell, vec2 local, vec2 offset) {
	vec2 d = local - offset;
	return level_at(cell + offset) * exp(-dot(d, d) * 5.0);
}

void fragment() {
	vec2 g = UV * grid;
	vec2 cell = floor(g);
	vec2 local = fract(g) - 0.5;
	float d = length(local);
	float v = level_at(cell);

	// nearest lit dot within 2 cells -> dark stroke behind the content
	float near = 0.0;
	for (int dy = -2; dy <= 2; dy++) {
		for (int dx = -2; dx <= 2; dx++) {
			float w = (abs(dx) == 2 || abs(dy) == 2) ? 0.6 : 1.0;
			near = max(near, level_at(cell + vec2(float(dx), float(dy))) * w);
		}
	}
	float back_a = smoothstep(0.0, 0.2, near) * backdrop_alpha;

	float core = 1.0 - smoothstep(dot_radius - 0.08, dot_radius + 0.02, d);
	float halo = exp(-d * d * 6.0) * v * glow_strength;
	float bleed = bleed_from(cell, local, vec2(1.0, 0.0))
		+ bleed_from(cell, local, vec2(-1.0, 0.0))
		+ bleed_from(cell, local, vec2(0.0, 1.0))
		+ bleed_from(cell, local, vec2(0.0, -1.0));
	bleed *= 0.25 * glow_strength;

	float off_a = core * (off_alpha + 0.12 * back_a) * (1.0 - v);
	float dot_a = clamp(core * v + halo + bleed + off_a, 0.0, 1.0);
	// brighter dots run slightly hotter (towards yellow-white), like real plasma
	vec3 dot_col = lit_color.rgb * (0.55 + 0.6 * v) + vec3(0.3, 0.22, 0.08) * core * v * v;

	// "dot over backdrop" composite, non-premultiplied output
	float out_a = dot_a + back_a * (1.0 - dot_a);
	vec3 out_col = out_a > 0.0
		? (dot_col * dot_a + backdrop_color.rgb * back_a * (1.0 - dot_a)) / out_a
		: dot_col;
	COLOR = vec4(out_col, out_a * master_alpha);
}
