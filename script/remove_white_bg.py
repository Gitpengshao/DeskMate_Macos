#!/usr/bin/env python3
"""
Remove white background from all PNG images in the target directory.

Strategy:
Only pixels that are both "white enough" AND connected to the image border
are treated as background. This preserves white areas inside the foreground
content (e.g. white text, highlights, clothing details, etc.).
"""

import os
import sys
from collections import deque
from pathlib import Path
from PIL import Image

# Target directory containing PNG images
TARGET_DIR = Path("/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/image")

# Pixels with RGB values >= this are considered "white" and candidates for removal.
WHITE_THRESHOLD = 240


def is_whiteish(r: int, g: int, b: int, threshold: int) -> bool:
    return r >= threshold and g >= threshold and b >= threshold


def remove_border_white_background(input_path: Path, output_path: Path, threshold: int = 240) -> None:
    with Image.open(input_path) as img:
        if img.mode != "RGBA":
            img = img.convert("RGBA")
        else:
            img = img.copy()

        pixels = img.load()
        width, height = img.size

        # visited marks pixels already known to be background
        visited = [[False] * height for _ in range(width)]
        queue = deque()

        # Seed from all four borders
        for x in range(width):
            for y in (0, height - 1):
                if not visited[x][y]:
                    r, g, b, _ = pixels[x, y]
                    if is_whiteish(r, g, b, threshold):
                        visited[x][y] = True
                        queue.append((x, y))
        for y in range(height):
            for x in (0, width - 1):
                if not visited[x][y]:
                    r, g, b, _ = pixels[x, y]
                    if is_whiteish(r, g, b, threshold):
                        visited[x][y] = True
                        queue.append((x, y))

        # 4-directional flood fill over white-ish pixels
        while queue:
            x, y = queue.popleft()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < width and 0 <= ny < height and not visited[nx][ny]:
                    r, g, b, _ = pixels[nx, ny]
                    if is_whiteish(r, g, b, threshold):
                        visited[nx][ny] = True
                        queue.append((nx, ny))

        # Erode foreground by 1 pixel to clean up remaining edge artifacts
        edge_pixels = set()
        for y in range(height):
            for x in range(width):
                if not visited[x][y]:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if nx < 0 or nx >= width or ny < 0 or ny >= height or visited[nx][ny]:
                            edge_pixels.add((x, y))
                            break

        # Apply transparency to all visited background pixels + 1px inward edge
        for y in range(height):
            for x in range(width):
                if visited[x][y] or (x, y) in edge_pixels:
                    r, g, b, a = pixels[x, y]
                    max_channel = max(r, g, b)
                    whiteness = (max_channel - threshold) / (255 - threshold)
                    new_alpha = int(a * (1 - whiteness))
                    pixels[x, y] = (r, g, b, new_alpha)

        img.save(output_path, "PNG")


def main() -> int:
    if not TARGET_DIR.is_dir():
        print(f"Error: target directory does not exist: {TARGET_DIR}", file=sys.stderr)
        return 1

    png_files = sorted(TARGET_DIR.glob("*.png"))
    if not png_files:
        print(f"No PNG files found in {TARGET_DIR}")
        return 0

    for png_path in png_files:
        temp_path = png_path.with_suffix(".tmp.png")
        try:
            remove_border_white_background(png_path, temp_path, threshold=WHITE_THRESHOLD)
            png_path.unlink()
            temp_path.rename(png_path)
            print(f"Processed: {png_path.name}")
        except Exception as e:
            print(f"Error processing {png_path.name}: {e}", file=sys.stderr)
            if temp_path.exists():
                temp_path.unlink()
            return 1

    print(f"Done. {len(png_files)} file(s) processed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
