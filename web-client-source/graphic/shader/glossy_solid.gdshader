shader_type canvas_item;

uniform sampler2D palette;
uniform vec2 node_size = vec2(1.0, 1.0);
//uniform float shader_size : hint_range(0.0, 1.0) = 1.0;
uniform float x_corner_margin : hint_range(0.0, 0.5) = 0.25;
uniform float x_shift = 0.0;
uniform float x_scale = 1.0;
uniform float y_corner_margin : hint_range(0.0, 0.5) = 0.25;
uniform float y_shift = 0.0;
uniform float y_scale = 1.0;
uniform bool dont_merge_black = true;
uniform float alpha_value : hint_range(0.0, 1.0) = 1.0;

group_uniforms Center_Detail;
uniform bool use_center_detail = false;
uniform vec4 center_color : source_color = vec4(1.0);
uniform float center_falloff : hint_range(0.0, 2.0) = 1.0;
uniform float center_x_corner_margin : hint_range(0.0, 0.5) = 0.25;
uniform float center_x_shift = 0.0;
uniform float center_x_scale = 1.0;
uniform float center_y_corner_margin : hint_range(0.0, 0.5) = 0.25;
uniform float center_y_shift = 0.0;
uniform float center_y_scale = 1.0;

group_uniforms Reflection;
uniform bool use_reflection = false;
uniform vec4 reflection_color : source_color = vec4(1.0);
uniform float reflection_falloff : hint_range(0.0, 2.0) = 1.0;
uniform float reflection_x_corner_margin : hint_range(0.0, 0.5) = 0.25;
uniform float reflection_x_shift = 0.0;
uniform float reflection_x_scale = 1.0;
uniform float reflection_y_corner_margin : hint_range(0.0, 0.5) = 0.25;
uniform float reflection_y_shift = 0.0;
uniform float reflection_y_scale = 1.0;


vec4 merge(vec4 first, vec4 second, float factor) {
	// The factor is generally anticipated to be the alpha of the second value, but is not necessary
	if (dont_merge_black && first.xyz == vec3(0.0) && first.a > 0.0) {
		return vec4(vec3(0.0), first.a);
	}
	return first * (1.0 - factor) + vec4(second.r, second.g, second.b, first.a) * factor;
}


float shift_scale_mirror(float canvas_value, float margin, float shift, float scale) {
	canvas_value -= shift;
	float pin = 0.5;
	canvas_value -= pin;
	canvas_value /= scale;
	canvas_value += pin;

	if (canvas_value > margin) {
		canvas_value = 1.0 - canvas_value;
	}
	canvas_value /= margin;
	canvas_value = clamp(canvas_value, 0.0, 1.0);
	return canvas_value;
}


vec2 vec2_shift_scale_mirror(vec2 canvas, vec2 margin, vec2 shift, vec2 scale) {
	canvas.x = shift_scale_mirror(canvas.x, margin.x, shift.x, scale.x);
	canvas.y = shift_scale_mirror(canvas.y, margin.y, shift.y, scale.y);
	canvas = clamp(vec2(1.0 - length(canvas - vec2(1.0))), 0.0, 1.0);
	return canvas;
}


void fragment() {
	float aspect = node_size.x / node_size.y;
	vec2 st = UV;

	// Apply transformations
	st = vec2_shift_scale_mirror(st, vec2(x_corner_margin / aspect, y_corner_margin), vec2(x_shift, y_shift), vec2(x_scale, y_scale));
	vec4 gradient = textureLod(palette, st, 0.0);

	// Apply center detail
	if (use_center_detail) {
		vec2 center = vec2_shift_scale_mirror(UV, vec2(center_x_corner_margin / aspect, center_y_corner_margin),
				vec2(center_x_shift, center_y_shift), vec2(center_x_scale, center_y_scale));
		float value = smoothstep(0.0, center_falloff, center.x); // ???
		gradient = merge(gradient, center_color, value * center_color.a);
	}

	// Apply reflection
	if (use_reflection) {
		vec2 reflection = vec2_shift_scale_mirror(UV, vec2(reflection_x_corner_margin / aspect, reflection_y_corner_margin),
				vec2(reflection_x_shift, reflection_y_shift), vec2(reflection_x_scale, reflection_y_scale));
		float value = smoothstep(0.0, reflection_falloff, reflection.x); // ???
		gradient = merge(gradient, reflection_color, value * reflection_color.a);
	}

	// Alpha value for tweening transparencies
	gradient = vec4(gradient.rgb, alpha_value * gradient.a);

	COLOR = gradient;
}