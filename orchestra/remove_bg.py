#!/usr/bin/env python3
"""Remove the background of an image, producing a transparent PNG.

Runs inside the rembg venv (Pillow + rembg + onnxruntime). The bridge
(orchestra/asset_mcp.py) invokes this helper as a subprocess:

    <rembg python> remove_bg.py INPUT OUTPUT [--model NAME] [--trim]
    <rembg python> remove_bg.py split INPUT OUTDIR [--method ...] [--tolerance T] [--model NAME] [--min-area F]
    <rembg python> remove_bg.py contact OUTPUT LABEL=PATH [LABEL=PATH ...]

Exit codes:
    0  success; stdout = one JSON line
       {"width": w, "height": h, "model": NAME, "opaque_ratio": r}
       (color method adds "method": "color", "bg": [r,g,b])
    1  any other failure (stderr: "error: <message>"); OUTPUT not created
    2  invalid --model (argparse choices)
    3  background removal left an empty image; OUTPUT not created
"""

import argparse
import json
import math
import os
import sys
import tempfile
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

try:
    import rembg
except ImportError:
    rembg = None

MODELS = (
    "u2net",
    "u2netp",
    "silueta",
    "isnet-general-use",
    "isnet-anime",
)
DEFAULT_MODEL = "isnet-general-use"
MIN_OPAQUE_RATIO = 0.01
DEFAULT_TOLERANCE = 38.0
AUTO_THRESHOLD = 0.90
DEFAULT_MIN_AREA_FRACTION = 0.002


def parse_args(argv):
    if not argv:
        parser = argparse.ArgumentParser(prog="orchestra/remove_bg.py", add_help=False)
        parser.error("no arguments provided")

    first = argv[0]
    if first in ("split", "contact"):
        parser = argparse.ArgumentParser(prog="orchestra/remove_bg.py", add_help=False)
        parser.add_argument("command", choices=("split", "contact"), help=argparse.SUPPRESS)
        parser.add_argument("input", help=argparse.SUPPRESS)
        parser.add_argument("output", nargs="?", help=argparse.SUPPRESS)
        parser.add_argument("--model", choices=MODELS, default=DEFAULT_MODEL)
        parser.add_argument("--trim", action="store_true")
        parser.add_argument("--method", choices=("ai", "color", "auto"), default="ai")
        parser.add_argument("--tolerance", type=float, default=DEFAULT_TOLERANCE)
        parser.add_argument("--min-area", type=float, default=DEFAULT_MIN_AREA_FRACTION, dest="min_area")
        args, remaining = parser.parse_known_args(argv)
        if args.command == "split":
            if args.input is None or args.output is None:
                parser.error("split requires INPUT OUTDIR")
            args.mode = "split"
        else:
            if args.input is None:
                parser.error("contact requires OUTPUT")
            args.mode = "contact"
            # For contact, the remaining args are the LABEL=PATH pairs
            args.pairs = [args.output] + remaining
            args.output = None
    else:
        parser = argparse.ArgumentParser(prog="orchestra/remove_bg.py", add_help=False)
        parser.add_argument("input", help=argparse.SUPPRESS)
        parser.add_argument("output", help=argparse.SUPPRESS)
        parser.add_argument("--model", choices=MODELS, default=DEFAULT_MODEL)
        parser.add_argument("--trim", action="store_true")
        parser.add_argument("--method", choices=("ai", "color", "auto"), default="ai")
        parser.add_argument("--tolerance", type=float, default=DEFAULT_TOLERANCE)
        parser.add_argument("--min-area", type=float, default=DEFAULT_MIN_AREA_FRACTION, dest="min_area")
        args, remaining = parser.parse_known_args(argv)
        if remaining:
            parser.error(f"unrecognized arguments: {' '.join(remaining)}")
        args.mode = "legacy"

    return args


def trim_padding(image):
    larger = max(image.width, image.height)
    return max(2, round(larger * 0.02))


def trim_to_subject(image, alpha):
    bbox = alpha.getbbox()
    if bbox is None:
        return image
    pad = trim_padding(image)
    return image.crop((
        max(0, bbox[0] - pad),
        max(0, bbox[1] - pad),
        min(image.width, bbox[2] + pad),
        min(image.height, bbox[3] + pad),
    ))


def opaque_ratio(alpha):
    total = alpha.width * alpha.height
    if total == 0:
        return 0.0
    opaque = sum(1 for value in alpha.tobytes() if value >= 128)
    return opaque / total


def border_color_key(image):
    """Return per-channel median of the 4-pixel image border as (r,g,b) ints."""
    arr = np.array(image.convert("RGB"))
    h, w = arr.shape[:2]
    border_pixels = []
    border_pixels.extend(arr[0:4, :].reshape(-1, 3))
    border_pixels.extend(arr[h-4:h, :].reshape(-1, 3))
    border_pixels.extend(arr[4:h-4, 0:4].reshape(-1, 3))
    border_pixels.extend(arr[4:h-4, w-4:w].reshape(-1, 3))
    border_arr = np.array(border_pixels)
    key = np.median(border_arr, axis=0).astype(int)
    return tuple(int(c) for c in key)


def color_key_remove(image, tolerance):
    """Remove background by color keying. Returns RGBA image."""
    rgb = image.convert("RGB")
    arr = np.array(rgb).astype(float)
    h, w = arr.shape[:2]

    key = border_color_key(image)
    key_arr = np.array(key, dtype=float)

    dist = np.sqrt(np.sum((arr - key_arr) ** 2, axis=2))

    bg_candidate = dist < (2 * tolerance)
    # Use 4-connectivity (cross structure) as per spec
    structure = np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]], dtype=bool)
    labeled, num_features = ndimage.label(bg_candidate, structure=structure)

    border_labels = set()
    border_labels.update(labeled[0, :])
    border_labels.update(labeled[h-1, :])
    border_labels.update(labeled[:, 0])
    border_labels.update(labeled[:, w-1])
    border_labels.discard(0)

    bg_mask = np.isin(labeled, list(border_labels))

    alpha = np.ones((h, w), dtype=float)
    alpha[bg_mask] = np.clip((dist[bg_mask] - tolerance) / tolerance, 0, 1)

    result_arr = arr.copy()
    for c in range(3):
        channel = result_arr[:, :, c]
        bg_pixels = bg_mask & (alpha > 0) & (alpha < 1)
        if np.any(bg_pixels):
            channel[bg_pixels] = np.clip(
                (channel[bg_pixels] - (1 - alpha[bg_pixels]) * key_arr[c]) / alpha[bg_pixels],
                0, 255
            )

    result_rgb = np.clip(result_arr, 0, 255).astype(np.uint8)
    result_alpha = np.clip(alpha * 255, 0, 255).astype(np.uint8)

    result = Image.fromarray(np.dstack([result_rgb, result_alpha]), "RGBA")
    return result, key


def auto_method(image, tolerance):
    """Decide between color and ai based on border uniformity."""
    rgb = image.convert("RGB")
    arr = np.array(rgb).astype(float)
    h, w = arr.shape[:2]

    key = border_color_key(image)
    key_arr = np.array(key, dtype=float)

    border_pixels = []
    border_pixels.extend(arr[0, :])
    border_pixels.extend(arr[h-1, :])
    border_pixels.extend(arr[1:h-1, 0])
    border_pixels.extend(arr[1:h-1, w-1])
    border_arr = np.array(border_pixels)

    dist = np.sqrt(np.sum((border_arr - key_arr) ** 2, axis=1))
    uniform_fraction = np.mean(dist < tolerance)

    return "color" if uniform_fraction >= AUTO_THRESHOLD else "ai"


def split_blobs(image, tolerance, min_area_fraction):
    """Split image into separate blob images. Returns list of (bbox, cropped_image)."""
    alpha = np.array(image.getchannel("A"))
    h, w = alpha.shape
    mask = alpha >= 128

    merge_dist = max(2, round(0.004 * max(w, h)))
    if merge_dist > 0:
        structure = ndimage.generate_binary_structure(2, 2)
        dilated = ndimage.binary_dilation(mask, structure=structure, iterations=merge_dist)
    else:
        dilated = mask

    labeled, num_features = ndimage.label(dilated, structure=np.ones((3, 3)))

    min_area = min_area_fraction * w * h
    blobs = []

    for label_id in range(1, num_features + 1):
        blob_mask = (labeled == label_id)
        if np.sum(blob_mask) < min_area:
            continue

        rows = np.where(np.any(blob_mask, axis=1))[0]
        cols = np.where(np.any(blob_mask, axis=0))[0]
        y1, y2 = rows[0], rows[-1] + 1
        x1, x2 = cols[0], cols[-1] + 1

        pad = max(2, round(0.02 * max(x2 - x1, y2 - y1)))
        y1 = max(0, y1 - pad)
        y2 = min(h, y2 + pad)
        x1 = max(0, x1 - pad)
        x2 = min(w, x2 + pad)

        cropped = image.crop((x1, y1, x2, y2))
        blobs.append(((y1, x1, y2, x2), cropped))

    blobs.sort(key=lambda b: (b[0][0], b[0][1]))

    grouped = []
    for bbox, img in blobs:
        y_center = (bbox[0] + bbox[2]) / 2
        placed = False
        for row in grouped:
            row_y_min = min(b[0][0] for b in row)
            row_y_max = max(b[0][2] for b in row)
            if row_y_min <= y_center <= row_y_max:
                row.append((bbox, img))
                placed = True
                break
        if not placed:
            grouped.append([(bbox, img)])

    result = []
    for row in grouped:
        row.sort(key=lambda b: b[0][1])
        for bbox, img in row:
            result.append(img)

    return result


def contact_sheet(output_path, items):
    """Create a contact sheet from LABEL=PATH pairs. items is list of (label, path)."""
    cell_size = 160
    label_height = 18
    max_cols = 6
    gap = 0

    n = len(items)
    cols = min(max_cols, n)
    rows = (n + cols - 1) // cols

    sheet_w = cols * cell_size
    sheet_h = rows * (cell_size + label_height)

    sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()

    checker_light = (200, 200, 200, 255)
    checker_dark = (160, 160, 160, 255)
    checker_size = 8

    for idx, (label, path) in enumerate(items):
        row = idx // cols
        col = idx % cols
        x = col * cell_size
        y = row * (cell_size + label_height)

        for cy in range(cell_size):
            for cx in range(cell_size):
                checker_x = (x + cx) // checker_size
                checker_y = (y + cy) // checker_size
                color = checker_light if (checker_x + checker_y) % 2 == 0 else checker_dark
                sheet.putpixel((x + cx, y + cy), color)

        try:
            with Image.open(path) as img:
                if img.mode != "RGBA":
                    img = img.convert("RGBA")
                img.thumbnail((cell_size, cell_size), Image.Resampling.LANCZOS)
                paste_x = x + (cell_size - img.width) // 2
                paste_y = y + (cell_size - img.height) // 2
                sheet.alpha_composite(img, (paste_x, paste_y))
        except Exception:
            pass

        text_bbox = draw.textbbox((0, 0), label, font=font)
        text_w = text_bbox[2] - text_bbox[0]
        text_h = text_bbox[3] - text_bbox[1]
        if text_w > cell_size - 4:
            while text_w > cell_size - 4 and len(label) > 1:
                label = label[:-1]
                text_bbox = draw.textbbox((0, 0), label, font=font)
                text_w = text_bbox[2] - text_bbox[0]
        text_x = x + (cell_size - text_w) // 2
        text_y = y + cell_size + (label_height - text_h) // 2
        draw.text((text_x, text_y), label, fill=(0, 0, 0, 255), font=font)

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    sheet.save(output_path, "PNG")


def run_legacy(args, image):
    if args.method == "auto":
        method = auto_method(image, args.tolerance)
    else:
        method = args.method

    if method == "color":
        result, key = color_key_remove(image, args.tolerance)
        json_extra = {"method": "color", "bg": list(key)}
    else:
        if rembg is None:
            print("error: rembg not available for ai method", file=sys.stderr)
            return 1
        session = rembg.new_session(args.model)
        result = rembg.remove(image, session=session)
        if result.mode != "RGBA":
            result = result.convert("RGBA")
        json_extra = {"method": "ai", "bg_model": args.model}

    if args.trim:
        result = trim_to_subject(result, result.getchannel("A"))

    ratio = opaque_ratio(result.getchannel("A"))
    if ratio < MIN_OPAQUE_RATIO:
        print("error: background removal left an empty image", file=sys.stderr)
        return 3

    output = os.path.abspath(args.output)
    parent = os.path.dirname(output) or "."
    os.makedirs(parent, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=parent, prefix=".remove-bg-", suffix=".png")
    try:
        with os.fdopen(fd, "wb") as fh:
            result.save(fh, format="PNG")
        os.replace(tmp_path, output)
    except BaseException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

    json_out = {
        "width": result.width,
        "height": result.height,
        "model": args.model,
        "opaque_ratio": round(ratio, 3),
        **json_extra,
    }
    sys.stdout.write(json.dumps(json_out) + "\n")
    return 0


def run_split(args, image):
    if args.method == "auto":
        method = auto_method(image, args.tolerance)
    else:
        method = args.method

    if method == "color":
        processed, key = color_key_remove(image, args.tolerance)
        json_extra = {"method": "color", "bg": list(key)}
    else:
        if rembg is None:
            print("error: rembg not available for ai method", file=sys.stderr)
            return 1
        session = rembg.new_session(args.model)
        processed = rembg.remove(image, session=session)
        if processed.mode != "RGBA":
            processed = processed.convert("RGBA")
        json_extra = {"method": "ai", "bg_model": args.model}

    blobs = split_blobs(processed, args.tolerance, args.min_area)
    if not blobs:
        print("error: no icons found in the sheet", file=sys.stderr)
        return 3

    outdir = os.path.abspath(args.output)
    os.makedirs(outdir, exist_ok=True)

    for i, blob_img in enumerate(blobs, 1):
        name = f"{i:02d}.png" if len(blobs) <= 99 else f"{i:03d}.png"
        out_path = os.path.join(outdir, name)
        blob_img.save(out_path, "PNG")

    contact_path = os.path.join(outdir, "_contact.png")
    items = [(f"{i:02d}" if len(blobs) <= 99 else f"{i:03d}", os.path.join(outdir, f"{i:02d}.png" if len(blobs) <= 99 else f"{i:03d}.png")) for i in range(1, len(blobs) + 1)]
    contact_sheet(contact_path, items)

    json_out = {
        "count": len(blobs),
        "method": json_extra["method"],
        "items": [
            {"index": i, "file": f"{i:02d}.png" if len(blobs) <= 99 else f"{i:03d}.png", "width": img.width, "height": img.height}
            for i, img in enumerate(blobs, 1)
        ],
        "contact": "_contact.png",
    }
    if "bg" in json_extra:
        json_out["bg"] = json_extra["bg"]
    sys.stdout.write(json.dumps(json_out) + "\n")
    return 0


def run_contact(args):
    pairs = []
    for pair in args.pairs:
        if "=" not in pair:
            print(f"error: invalid LABEL=PATH pair: {pair}", file=sys.stderr)
            return 1
        label, path = pair.split("=", 1)
        if not os.path.exists(path):
            print(f"error: input file not found: {path}", file=sys.stderr)
            return 1
        pairs.append((label, path))

    output = os.path.abspath(args.input)
    contact_sheet(output, pairs)

    sys.stdout.write(json.dumps({"count": len(pairs)}) + "\n")
    return 0


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]
    args = parse_args(argv)

    try:
        if args.mode == "legacy":
            with Image.open(args.input) as source:
                if source.mode != "RGBA":
                    source = source.convert("RGBA")
                return run_legacy(args, source)
        elif args.mode == "split":
            with Image.open(args.input) as source:
                if source.mode != "RGBA":
                    source = source.convert("RGBA")
                return run_split(args, source)
        elif args.mode == "contact":
            return run_contact(args)
    except Exception as err:
        print(f"error: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())