shader_type canvas_item;

// Uniform to control the scroll speed.
// Positive x scrolls texture to the right (background moves left).
// Positive y scrolls texture down (background moves up).
uniform vec2 scroll_speed = vec2(0.05, 0.05); // Adjust x for horizontal, y for vertical speed

void fragment() {
    // Calculate the new UV coordinates by adding an offset based on TIME and scroll_speed.
    // TIME is a built-in variable that increases every frame.
    vec2 scrolled_uv = UV + TIME * scroll_speed;

    // Sample the texture using the new, scrolled UV coordinates.
    // Because the texture is set to repeat, UVs outside the 0-1 range will wrap around.
    COLOR = texture(TEXTURE, scrolled_uv);
}