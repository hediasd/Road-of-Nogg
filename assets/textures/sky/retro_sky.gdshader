shader_type sky;

uniform vec3 top_color : source_color = vec3(0.04, 0.20, 0.45);
uniform vec3 bottom_color : source_color = vec3(0.25, 0.60, 0.90);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float cloud_scale : hint_range(0.1, 100.0) = 15.0;
uniform float cloud_speed : hint_range(0.0, 10.0) = 0.5;
uniform float cloud_density : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_sharpness : hint_range(0.0, 1.0) = 0.7;

// Basic noise function for procedural clouds
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 x) {
    vec2 p = floor(x);
    vec2 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(p + vec2(0.0, 0.0)), hash(p + vec2(1.0, 0.0)), f.x),
        mix(hash(p + vec2(0.0, 1.0)), hash(p + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

float fbm(vec2 p) {
    float f = 0.0;
    f += 0.5000 * noise(p); p = p * 2.02;
    f += 0.2500 * noise(p); p = p * 2.03;
    f += 0.1250 * noise(p); p = p * 2.01;
    f += 0.0625 * noise(p);
    return f / 0.9375;
}

void sky() {
    // Determine the position in the sky (y is vertical)
    float v = clamp(EYEDIR.y, 0.0, 1.0);
    
    // Gradient background (PS1 style simple gradient)
    vec3 color = mix(bottom_color, top_color, pow(v, 0.7));
    
    // Cloud UV mapping (plane above viewer)
    // Avoid drawing clouds at the very bottom (horizon)
    if (EYEDIR.y > 0.0) {
        vec2 cloud_uv = EYEDIR.xz / EYEDIR.y;
        cloud_uv *= cloud_scale;
        
        // Scrolling animation
        cloud_uv.x += TIME * cloud_speed;
        cloud_uv.y += TIME * (cloud_speed * 0.2);
        
        // Generate noise
        float n = fbm(cloud_uv);
        
        // Shape clouds based on density and sharpness
        float cloud_val = smoothstep(1.0 - cloud_density, (1.0 - cloud_density) + (1.0 - cloud_sharpness), n);
        
        // Fade clouds near horizon
        float horizon_fade = smoothstep(0.0, 0.3, EYEDIR.y);
        cloud_val *= horizon_fade;
        
        // Mix cloud color
        color = mix(color, cloud_color, cloud_val);
    }
    
    COLOR = color;
}
