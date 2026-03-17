#!/usr/bin/env python3
"""
Generate a high-quality macOS app icon in the style of Apple's built-in apps like News.
Creates a modern, vibrant icon with gradient background and bold design.
"""

import os
import math
from PIL import Image, ImageDraw, ImageFilter

# Icon sizes needed for macOS app icon set
# Format: (actual_pixel_size, nominal_size) - @2x images are 2x the nominal size
SIZES = [
    (16, 16),      # 16x16 @1x
    (32, 16),      # 16x16 @2x = 32px actual
    (32, 32),      # 32x32 @1x
    (64, 32),      # 32x32 @2x = 64px actual
    (128, 128),    # 128x128 @1x
    (256, 128),    # 128x128 @2x = 256px actual
    (256, 256),    # 256x256 @1x
    (512, 256),    # 256x256 @2x = 512px actual
    (512, 512),    # 512x512 @1x
    (1024, 512),   # 512x512 @2x = 1024px actual
    (1024, 1024),  # 1024x1024 @1x (App Store)
]

def create_icon(size):
    """Create a single icon at the given size."""
    # Create image with transparency for rounded corners
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Calculate corner radius (Apple uses about 22% of size)
    corner_radius = int(size * 0.22)

    # Create gradient background similar to News app (warm coral/pink gradient)
    # News app uses a warm gradient from coral to pink/orange
    colors = [
        (255, 107, 107),  # Coral red
        (255, 145, 164),  # Pink
        (255, 177, 131),  # Warm orange
    ]

    # Draw gradient background with rounded corners
    for y in range(size):
        # Interpolate colors based on y position
        progress = y / size
        if progress < 0.5:
            c1 = colors[0]
            c2 = colors[1]
            t = progress * 2
        else:
            c1 = colors[1]
            c2 = colors[2]
            t = (progress - 0.5) * 2

        r = int(c1[0] + (c2[0] - c1[0]) * t)
        g = int(c1[1] + (c2[1] - c1[1]) * t)
        b = int(c1[2] + (c2[2] - c1[2]) * t)

        # Draw line with rounded corners consideration
        for x in range(size):
            # Check if we're in a corner that should be transparent
            in_corner = False
            if x < corner_radius and y < corner_radius:
                dist = math.sqrt((corner_radius - x) ** 2 + (corner_radius - y) ** 2)
                in_corner = dist > corner_radius
            elif x >= size - corner_radius and y < corner_radius:
                dist = math.sqrt((x - (size - corner_radius - 1)) ** 2 + (corner_radius - y) ** 2)
                in_corner = dist > corner_radius
            elif x < corner_radius and y >= size - corner_radius:
                dist = math.sqrt((corner_radius - x) ** 2 + (y - (size - corner_radius - 1)) ** 2)
                in_corner = dist > corner_radius
            elif x >= size - corner_radius and y >= size - corner_radius:
                dist = math.sqrt((x - (size - corner_radius - 1)) ** 2 + (y - (size - corner_radius - 1)) ** 2)
                in_corner = dist > corner_radius

            if not in_corner:
                draw.point((x, y), fill=(r, g, b, 255))

    # Add subtle inner glow/shadow for depth
    # Create a radial gradient overlay
    center = size // 2
    max_dist = size // 2

    # Draw abstract "L" shape for LocalMind
    # Using white with transparency for a clean Apple-style look
    padding = int(size * 0.15)
    stroke_width = int(size * 0.12)

    # Draw a stylized brain/mind symbol - concentric circles representing knowledge
    # This is abstract and modern, like the News app's dots
    circle_spacing = int(size * 0.12)
    num_circles = 3
    base_radius = int(size * 0.08)

    # Draw circles in a triangular formation (like news dots but more dynamic)
    # White with varying opacity
    for i in range(num_circles):
        offset_x = int((i - 1) * circle_spacing * 1.5)
        offset_y = int((1 - abs(i - 1)) * circle_spacing)

        cx = center + offset_x
        cy = center + offset_y + int(size * 0.05)
        radius = base_radius + i * int(size * 0.04)

        # Draw circle
        draw.ellipse(
            [cx - radius, cy - radius, cx + radius, cy + radius],
            fill=(255, 255, 255, 220 - i * 40)
        )

    # Add a subtle highlight at the top
    highlight_height = int(size * 0.15)
    for i in range(highlight_height):
        alpha = int(30 * (1 - i / highlight_height))
        draw.rectangle(
            [0, i, size, i + 1],
            fill=(255, 255, 255, alpha)
        )

    return img


def main():
    # Output directory
    output_dir = '/Users/thotas/Development/Claude/LocalMind/LocalMind/Resources/Assets.xcassets/AppIcon.appiconset'

    # Make sure output directory exists
    os.makedirs(output_dir, exist_ok=True)

    # Filenames for each size
    filenames = [
        'icon_16x16.png',
        'icon_16x16@2x.png',
        'icon_32x32.png',
        'icon_32x32@2x.png',
        'icon_128x128.png',
        'icon_128x128@2x.png',
        'icon_256x256.png',
        'icon_256x256@2x.png',
        'icon_512x512.png',
        'icon_512x512@2x.png',
        'icon_1024x1024.png',
    ]

    print("Generating app icons...")

    for (size, _), filename in zip(SIZES, filenames):
        img = create_icon(size)
        output_path = os.path.join(output_dir, filename)
        img.save(output_path, 'PNG', optimize=True)
        print(f"Created: {filename} ({size}x{size})")

    print("\nAll icons generated successfully!")
    print(f"Icons saved to: {output_dir}")


if __name__ == '__main__':
    main()
