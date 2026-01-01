#!/usr/bin/env python3
import sys

from svgpathtools import svg2paths
from svgpathtools import wsvg


def center_svg(input_file, output_file, viewbox_size=24, padding=2):
    # 1. Parse paths
    paths, attributes = svg2paths(input_file)

    if not paths:
        print("No paths found.")
        return

    # 2. Calculate current bounding box of all paths
    # bbox() returns (xmin, xmax, ymin, ymax)
    bboxes = [path.bbox() for path in paths]
    min_x = min(bb[0] for bb in bboxes)
    max_x = max(bb[1] for bb in bboxes)
    min_y = min(bb[2] for bb in bboxes)
    max_y = max(bb[3] for bb in bboxes)

    width = max_x - min_x
    height = max_y - min_y

    # 3. Calculate Scale to fit viewbox minus padding
    target_dim = viewbox_size - (padding * 2)
    scale = target_dim / max(width, height)

    # 4. Translate and Scale paths
    new_paths = []
    for path in paths:
        # Move to origin (0,0)
        path = path.translated(complex(-min_x, -min_y))
        # Scale
        path = path.scaled(scale)
        # Center in viewbox
        # Calculate new offset to center it
        new_width = width * scale
        new_height = height * scale
        offset_x = (viewbox_size - new_width) / 2
        offset_y = (viewbox_size - new_height) / 2
        path = path.translated(complex(offset_x, offset_y))
        new_paths.append(path)

    # 5. Write new file with fixed 24x24 viewBox
    wsvg(new_paths, attributes=attributes, filename=output_file, viewbox=f"0 0 {viewbox_size} {viewbox_size}")
    print(f"Saved centered SVG to {output_file}")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python center-svg.py <input.svg> <output.svg> <viewbox_size> [padding]")
        print("  viewbox_size: Size of the square viewBox (e.g., 512, 24, 32)")
        print("  padding: Optional padding from edges (default: 2)")
        print("\nExample: python center-svg.py icon.svg icon-centered.svg 512 10")
    else:
        input_file = sys.argv[1]
        output_file = sys.argv[2]
        viewbox_size = int(sys.argv[3])
        padding = int(sys.argv[4]) if len(sys.argv) > 4 else 2
        center_svg(input_file, output_file, viewbox_size, padding)
