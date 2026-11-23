#!/usr/bin/env python3
"""Regenerate launcher icons from assets/icon/app_icon.png.

The source picture is provisional. Replace that file and run this script.
It cuts the M and magnifier out of the white rounded square, keeps that
artwork inside the Android adaptive-icon safe zone (the center 66dp of the
108dp layer), and runs flutter_launcher_icons for Android, iOS, and Windows.
Linux copies the same source during its bundle install.

Requires Pillow, and Flutter on PATH for the platform icon step.
"""

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops

APP_DIR = Path(__file__).resolve().parents[1]
SOURCE = APP_DIR / "assets" / "icon" / "app_icon.png"
FOREGROUND = APP_DIR / "assets" / "icon" / "app_icon_foreground.png"

# Pixels at or below this chroma are the white tile or its neutral shadow.
CHROMA_CUT = 4
# At or above this chroma the pixel is solid artwork, not an antialiased edge.
CHROMA_SOLID = 22
# Android safe zone: a 66dp circle on the 108dp adaptive layer.
SAFE_ZONE_DIAMETER = 66 / 108
# Launcher viewport is the inner 72dp of that layer. Masks apply there.
VIEWPORT = 72 / 108


def _unpremultiply(channel: int, alpha: float) -> int:
    value = (channel / 255.0 - (1.0 - alpha)) / alpha
    return max(0, min(255, int(round(value * 255))))


def cut_out_artwork(source: Image.Image) -> Image.Image:
    """M and magnifier on transparency. The white rounded square is removed."""
    rgb = source.convert("RGB")
    pixels = rgb.load()
    width, height = rgb.size
    cut = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    out = cut.load()
    for y in range(height):
        for x in range(width):
            red, green, blue = pixels[x, y]
            chroma = max(red, green, blue) - min(red, green, blue)
            if chroma <= CHROMA_CUT:
                continue
            if chroma >= CHROMA_SOLID:
                out[x, y] = (red, green, blue, 255)
                continue
            alpha = int(
                round((chroma - CHROMA_CUT) * 255 / (CHROMA_SOLID - CHROMA_CUT))
            )
            alpha_f = alpha / 255.0
            out[x, y] = (
                _unpremultiply(red, alpha_f),
                _unpremultiply(green, alpha_f),
                _unpremultiply(blue, alpha_f),
                alpha,
            )
    return cut


def place_in_safe_zone(artwork: Image.Image) -> Image.Image:
    """Scale the cut-out so every solid pixel stays inside the 66dp circle."""
    width, height = artwork.size
    center_x = (width - 1) / 2.0
    center_y = (height - 1) / 2.0
    pixels = artwork.load()
    max_distance = 0.0
    for y in range(height):
        for x in range(width):
            if pixels[x, y][3] < 128:
                continue
            distance = math.hypot(x - center_x, y - center_y)
            if distance > max_distance:
                max_distance = distance
    if max_distance <= 0:
        raise SystemExit(f"{SOURCE} has no artwork to cut out")

    safe_radius = SAFE_ZONE_DIAMETER * width / 2.0
    # One percent inside the circle so the scaled edge stays in the safe zone.
    scale = (safe_radius * 0.99) / max_distance
    scaled_size = (
        max(1, int(round(width * scale))),
        max(1, int(round(height * scale))),
    )
    scaled = artwork.resize(scaled_size, Image.Resampling.LANCZOS)
    foreground = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    foreground.alpha_composite(
        scaled,
        ((width - scaled_size[0]) // 2, (height - scaled_size[1]) // 2),
    )
    return foreground


def _circle_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    pixels = mask.load()
    radius = (size - 1) / 2.0
    for y in range(size):
        for x in range(size):
            distance = math.hypot(x - radius, y - radius)
            if distance <= radius - 0.75:
                pixels[x, y] = 255
            elif distance >= radius + 0.75:
                pixels[x, y] = 0
            else:
                pixels[x, y] = int(round(255 * (radius + 0.75 - distance) / 1.5))
    return mask


def _squircle_mask(size: int, exponent: float = 5.0) -> Image.Image:
    """Superellipse inscribed in the viewport. Exponent 2 is a circle."""
    mask = Image.new("L", (size, size), 0)
    pixels = mask.load()
    half = (size - 1) / 2.0
    for y in range(size):
        for x in range(size):
            nx = abs(x - half) / half
            ny = abs(y - half) / half
            value = nx**exponent + ny**exponent
            if value <= 0.985:
                pixels[x, y] = 255
            elif value >= 1.02:
                pixels[x, y] = 0
            else:
                pixels[x, y] = int(round(255 * (1.02 - value) / 0.035))
    return mask


def _apply_mask(image: Image.Image, mask: Image.Image) -> Image.Image:
    red, green, blue, alpha = image.convert("RGBA").split()
    masked = Image.merge("RGBA", (red, green, blue, ImageChops.multiply(alpha, mask)))
    return masked


def render_previews(foreground: Image.Image, round_path: Path, squircle_path: Path) -> None:
    """Adaptive icon (white background, safe-zone foreground) under two masks."""
    preview = 1024
    layer_size = int(round(preview * 108 / 72))
    layer = Image.new("RGBA", (layer_size, layer_size), (255, 255, 255, 255))
    scaled = foreground.resize((layer_size, layer_size), Image.Resampling.LANCZOS)
    layer.alpha_composite(scaled)
    left = (layer_size - preview) // 2
    viewport = layer.crop((left, left, left + preview, left + preview))

    def present(masked: Image.Image, path: Path) -> None:
        # Gray outside the mask so the white icon shape stays visible.
        canvas = Image.new("RGBA", masked.size, (228, 228, 228, 255))
        canvas.alpha_composite(masked)
        path.parent.mkdir(parents=True, exist_ok=True)
        canvas.convert("RGB").save(path)

    present(_apply_mask(viewport, _circle_mask(preview)), round_path)
    present(_apply_mask(viewport, _squircle_mask(preview)), squircle_path)


def build_foreground() -> Image.Image:
    if not SOURCE.is_file():
        raise SystemExit(f"missing source artwork: {SOURCE}")
    foreground = place_in_safe_zone(cut_out_artwork(Image.open(SOURCE)))
    FOREGROUND.parent.mkdir(parents=True, exist_ok=True)
    foreground.save(FOREGROUND)
    return foreground


def repair_generated_project_files() -> None:
    """Undo two things flutter_launcher_icons 0.14.4 rewrites badly."""
    project = APP_DIR / "ios" / "Runner.xcodeproj" / "project.pbxproj"
    text = project.read_text()
    # The generator replaces every ASSETCATALOG assignment, including this flag.
    text = text.replace(
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon;",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;",
    )
    project.write_text(text)

    contents_path = (
        APP_DIR
        / "ios"
        / "Runner"
        / "Assets.xcassets"
        / "AppIcon.appiconset"
        / "Contents.json"
    )
    contents = json.loads(contents_path.read_text())
    contents_path.write_text(json.dumps(contents, indent=2) + "\n")

    colors = APP_DIR / "android" / "app" / "src" / "main" / "res" / "values" / "colors.xml"
    color_text = colors.read_text()
    if not color_text.endswith("\n"):
        colors.write_text(color_text + "\n")


def run_flutter_launcher_icons() -> None:
    subprocess.run(["flutter", "pub", "get"], cwd=APP_DIR, check=True)
    subprocess.run(["dart", "run", "flutter_launcher_icons"], cwd=APP_DIR, check=True)
    repair_generated_project_files()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--previews",
        nargs=2,
        metavar=("ROUND", "SQUIRCLE"),
        help="Also write masked adaptive-icon previews to these PNG paths",
    )
    parser.add_argument(
        "--skip-platforms",
        action="store_true",
        help="Only rebuild the adaptive foreground, not the platform icons",
    )
    args = parser.parse_args()

    foreground = build_foreground()
    if args.previews:
        render_previews(foreground, Path(args.previews[0]), Path(args.previews[1]))
    if not args.skip_platforms:
        run_flutter_launcher_icons()


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
