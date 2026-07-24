shader_type canvas_item;

uniform vec3 top_color : source_color = vec3(0.04, 0.20, 0.45);
uniform vec3 bottom_color : source_color = vec3(0.25, 0.60, 0.90);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float cloud_scale : hint_range(0.1, 100.0) = 4.0;
uniform float cloud_speed : hint_range(0.0, 10.0) = 0.5;
uniform float cloud_density : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_sharpness : hint_range(0.0, 1.0) = 0.7;

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

void fragment() {
    vec2 uv = UV;
    
    // Gradient background
    vec3 color = mix(top_color, bottom_color, uv.y);
    
    // Cloud UV mapping (simulating perspective above viewer)
    // We want the clouds to look flat and recede into the horizon
    float horizon = 0.8; // Where the clouds fade out
    if (uv.y < horizon) {
        // Pseudo-perspective projection for the sky plane
        vec2 cloud_uv = uv;
        
        // Offset Y so clouds stretch as they approach the horizon
        float depth = max(0.01, horizon - uv.y);
        cloud_uv.y = 1.0 / depth;
        cloud_uv.x = (uv.x - 0.5) / depth * 0.5;
        
        cloud_uv *= cloud_scale;
        
        // Scrolling animation
        cloud_uv.x += TIME * cloud_speed;
        cloud_uv.y += TIME * (cloud_speed * 0.2);
        
        // Generate noise
        float n = fbm(cloud_uv);
        
        // Shape clouds based on density and sharpness
        float cloud_val = smoothstep(1.0 - cloud_density, (1.0 - cloud_density) + (1.0 - cloud_sharpness), n);
        
        // Fade clouds near horizon
        float horizon_fade = smoothstep(0.0, 0.3, depth);
        cloud_val *= horizon_fade;
        
        // Mix cloud color
        color = mix(color, cloud_color, cloud_val);
    }
    
    COLOR = vec4(color, 1.0);
}
