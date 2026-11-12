"""Generate legacy (non asset catalog) iOS app icons from the site logo."""
import sys
from pathlib import Path

from PIL import Image

ICON_SPECS = [
    ("AppIcon60x60@2x.png", 120),
    ("AppIcon60x60@3x.png", 180),
    ("AppIcon76x76@2x~ipad.png", 152),
    ("AppIcon83.5x83.5@2x~ipad.png", 167),
]


def main():
    logo_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])

    logo = Image.open(logo_path).convert("RGBA")

    for file_name, size in ICON_SPECS:
        # ios icons must be opaque, so flatten onto the terminal's black background
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 255))
        padding = round(size * 0.1)
        inner_size = size - padding * 2
        scaled_logo = logo.resize((inner_size, inner_size), Image.LANCZOS)
        canvas.alpha_composite(scaled_logo, (padding, padding))
        canvas.convert("RGB").save(output_dir / file_name)


if __name__ == "__main__":
    main()
