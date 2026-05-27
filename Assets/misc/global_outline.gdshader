shader_type spatial;
render_mode unshaded, cull_front; // Removed 'render_to_sizes'

uniform vec4 outline_color : source_color = vec4(0.0, 1.0, 0.0, 1.0); // Bright green interact line
uniform float outline_thickness : hint_range(0.0, 0.1) = 0.005;

void vertex() {
    // Expand the vertices along their normals to create an outer shell
    VERTEX += NORMAL * outline_thickness;
}

void fragment() {
    ALBEDO = outline_color.rgb;
    ALPHA = outline_color.a;
}