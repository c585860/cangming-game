shader_type canvas_item;
render_mode unshaded, blend_disabled;

varying vec3 owner;

void vertex() {
	owner = COLOR.rgb;
}

void fragment() {
	if (texture(TEXTURE, UV).a < 0.45) {
		discard;
	}
	COLOR = vec4(owner, 1.0);
}
