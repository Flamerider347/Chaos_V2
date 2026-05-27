shader_type sky;

// Day Colors
uniform vec3 sky_day : source_color = vec3(0.18, 0.42, 0.82);
uniform vec3 horizon_day : source_color = vec3(0.55, 0.76, 0.92);

// Sunset Colors
uniform vec3 sky_sunset : source_color = vec3(0.04, 0.08, 0.24);
uniform vec3 horizon_sunset : source_color = vec3(0.88, 0.38, 0.15);

// Night Colors
uniform vec3 sky_night : source_color = vec3(0.01, 0.01, 0.03);
uniform vec3 horizon_night : source_color = vec3(0.03, 0.04, 0.08);

// Texture Uniforms
uniform sampler2D sun_texture : filter_linear, source_color;
uniform sampler2D moon_texture : filter_linear, source_color;
uniform sampler2D cloud_texture : filter_linear, repeat_enable;

// Celestial Settings
uniform float sun_size = 0.2;
uniform float moon_size = 0.2; 

// Star Tuning Parameters
uniform float star_flicker_speed : hint_range(0.1, 10.0) = 3.5;

float hash2d(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void sky() {
    float sun_height = LIGHT0_DIRECTION.y;
    
    // --- FIXED: CINEMATIC SMOOTH TRANSITIONS ---
    // Smoothstep softens the edges where gradients switch, drawing out dawn and dusk.
    float day_weight = smoothstep(-0.1, 0.3, sun_height);
    float night_weight = smoothstep(-0.3, 0.1, -sun_height);
    
    // Sunset peaks dynamically right as the sun touches the horizon line (0.0)
    float sunset_weight = smoothstep(0.0, 1.0, 1.0 - abs(sun_height * 2.5));
    
    // Normalize weights to keep general sky luminance completely stable
    float total_weight = day_weight + sunset_weight + night_weight;
    if (total_weight > 0.0) {
        day_weight /= total_weight;
        sunset_weight /= total_weight;
        night_weight /= total_weight;
    }
    
    vec3 current_sky = (sky_day * day_weight) + (sky_sunset * sunset_weight) + (sky_night * night_weight);
    vec3 current_horizon = (horizon_day * day_weight) + (horizon_sunset * sunset_weight) + (horizon_night * night_weight);
    
    float horizon_blend = clamp(EYEDIR.y * 3.0, 0.0, 1.0);
    vec3 final_color = mix(current_horizon, current_sky, horizon_blend);
    
    // 1. TEXTURE-BASED SUN (Spherical Projection)
    if (sun_height > -0.1) {
        float cos_angle = dot(EYEDIR, LIGHT0_DIRECTION);
        float angle = acos(clamp(cos_angle, -1.0, 1.0));
        
        if (angle < sun_size) {
            vec3 sun_space = EYEDIR - LIGHT0_DIRECTION * cos_angle;
            
            if (length(sun_space) > 0.0001) {
                sun_space = normalize(sun_space);
                
                vec3 stable_right = normalize(vec3(-LIGHT0_DIRECTION.z, 0.0, LIGHT0_DIRECTION.x));
                vec3 stable_up = cross(LIGHT0_DIRECTION, stable_right);
                
                float x_offset = dot(sun_space, stable_right) * angle;
                float y_offset = dot(sun_space, stable_up) * angle;
                
                vec2 sun_uv = vec2(x_offset, y_offset) / sun_size + 0.5;
                
                if (sun_uv.x >= 0.0 && sun_uv.x <= 1.0 && sun_uv.y >= 0.0 && sun_uv.y <= 1.0) {
                    vec4 sun_tex = texture(sun_texture, sun_uv);
                    float fade = clamp(sun_height * 2.0 + 0.2, 0.0, 1.0);
                    final_color = mix(final_color, sun_tex.rgb, sun_tex.a * fade);
                }
            }
        }
    }
    
    // 2. TEXTURE-BASED MOON (Spherical Projection)
    vec3 moon_direction = -LIGHT0_DIRECTION;
    if (moon_direction.y > -0.2) {
        float cos_angle_moon = dot(EYEDIR, moon_direction);
        float angle_moon = acos(clamp(cos_angle_moon, -1.0, 1.0));
        
        if (angle_moon < moon_size) {
            vec3 moon_space = EYEDIR - moon_direction * cos_angle_moon;
            
            if (length(moon_space) > 0.0001) {
                moon_space = normalize(moon_space);
                
                vec3 stable_right_moon = normalize(vec3(-moon_direction.z, 0.0, moon_direction.x));
                vec3 stable_up_moon = cross(moon_direction, stable_right_moon);
                
                float x_offset_moon = dot(moon_space, stable_right_moon) * angle_moon;
                float y_offset_moon = dot(moon_space, stable_up_moon) * angle_moon;
                
                vec2 moon_uv = vec2(x_offset_moon, y_offset_moon) / moon_size + 0.5;
                
                if (moon_uv.x >= 0.0 && moon_uv.x <= 1.0 && moon_uv.y >= 0.0 && moon_uv.y <= 1.0) {
                    vec4 moon_tex = texture(moon_texture, moon_uv);
                    float fade_moon = clamp(night_weight * 2.0, 0.0, 1.0);
                    final_color = mix(final_color, moon_tex.rgb, moon_tex.a * fade_moon);
                }
            }
        }
    }
    
    // 3. STARS (Twinkle-enabled)
    if (EYEDIR.y > 0.0 && night_weight > 0.0) {
        vec2 star_uv = EYEDIR.xz / (EYEDIR.y + 0.05);
        
        vec2 grid1 = floor(star_uv * 200.0);
        vec2 grid2 = floor(star_uv * 80.0 + vec2(15.0));
        
        float stars1 = hash2d(grid1);
        float stars2 = hash2d(grid2);
        
        float star_intensity = 0.0;
        
        float flicker1 = sin(TIME * star_flicker_speed + (grid1.x * 23.1 + grid1.y * 42.7)) * 0.5 + 0.5;
        float flicker2 = sin(TIME * (star_flicker_speed * 0.8) + (grid2.x * 11.5 + grid2.y * 33.2)) * 0.5 + 0.5;
        
        if (stars1 > 0.996) {
            star_intensity += 0.4 * (0.3 + 0.7 * flicker1);
        }
        if (stars2 > 0.992) {
            star_intensity += 0.8 * (0.2 + 0.8 * flicker2);
        }
        
        final_color += vec3(0.9, 0.95, 1.0) * star_intensity * night_weight * EYEDIR.y;
    }
    
    // 4. TEXTURE-BASED CLOUDS
    if (EYEDIR.y > 0.0) {
        vec2 cloud_uv = EYEDIR.xz / (EYEDIR.y + 0.25);
        cloud_uv += TIME * 0.008; 
        
        vec4 cloud_tex = texture(cloud_texture, cloud_uv * 0.2);
        float cloud_density = smoothstep(0.2, 0.8, cloud_tex.g) * EYEDIR.y;
        
        vec3 cloud_lit_color = mix(vec3(1.0, 0.98, 0.95), vec3(0.95, 0.5, 0.25), sunset_weight);
        cloud_lit_color = mix(cloud_lit_color, vec3(0.12, 0.14, 0.22), night_weight);
        
        final_color = mix(final_color, cloud_lit_color, cloud_density * 0.9);
    }
    
    COLOR = final_color;
}