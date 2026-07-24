shader_type spatial;
render_mode unshaded, cull_front;


uniform vec4 aura_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float thickness : hint_range(0.0, 1.0) = 0.05;
uniform float pixel_size : hint_range(1.0, 64.0) = 16.0;
uniform float animation_speed : hint_range(0.0, 10.0) = 2.0;

void vertex() {
	// Expand the mesh outwards
	VERTEX += NORMAL * thickness;
}

void fragment() {
	// Pixelate the world coordinates for a retro wobble effect
	vec2 uv = UV * pixel_size;
	vec2 pixelated_uv = floor(uv) / pixel_size;
	
	// Add some time-based pulsing based on the pixelated coords
	float pulse = (sin(TIME * animation_speed + pixelated_uv.x * 10.0 + pixelated_uv.y * 10.0) + 1.0) * 0.5;
	
	// Keep the color fixed to white (as requested), but alpha pulses slightly
	ALBEDO = aura_color.rgb;
	ALPHA = aura_color.a * (0.6 + 0.4 * pulse);
}
