#!/usr/bin/env python3
"""Local bridge to the orchestra remote asset worker.

Stdlib-only. Turned on as either
  * an MCP stdio server speaking newline-delimited JSON-RPC 2.0 (``serve`` or no
    args) exposing the ``generate_asset`` tool, or
  * a small CLI::

      orchestra/asset_mcp.py generate PROMPT OUTPUT [--width N] [--height N]
          [--steps N] [--negative TEXT] [--seed N] [--overwrite]
      orchestra/asset_mcp.py check
"""

import argparse
import base64
import fcntl
import math
import http.client
import json
import os
import socket
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

CONFIG_MISSING = "ASSET_WORKER_URL / ASSET_WORKER_TOKEN not configured (env or ~/.config/orchestra/assets.env)"
DEFAULT_CONFIG_FILE = os.path.expanduser("~/.config/orchestra/assets.env")
TIMEOUT = 120
REMBG_TIMEOUT = 300
REMBG_DEFAULT_PYTHON = os.path.expanduser("~/.local/share/orchestra/rembg-venv/bin/python")
REMBG_INSTALL_HINT = (
    "install: python3 -m venv ~/.local/share/orchestra/rembg-venv && "
    '~/.local/share/orchestra/rembg-venv/bin/pip install "rembg[cpu]"'
)

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
JPEG_SIGNATURE = b"\xff\xd8\xff"
_REQUESTED_EXTS = (".png", ".jpg", ".jpeg", ".webp")

_FORMATS = {
    "png": {"format": "png", "mime": "image/png", "ext": ".png"},
    "jpeg": {"format": "jpeg", "mime": "image/jpeg", "ext": ".jpg"},
    "webp": {"format": "webp", "mime": "image/webp", "ext": ".webp"},
}

_SOF_MARKERS = frozenset(m for m in range(0xC0, 0xCF + 1) if m not in (0xC4, 0xC8, 0xCC))

_BG_MODELS = (
    "u2net",
    "u2netp",
    "silueta",
    "isnet-general-use",
    "isnet-anime",
)
DEFAULT_BG_MODEL = "isnet-general-use"

_BG_METHODS = ("auto", "color", "ai")
DEFAULT_BG_METHOD = "auto"
# models the Worker accepts; None = let the Worker pick its default (flux-2-klein-4b)
_IMAGE_MODELS = ("flux-2-klein-4b", "flux-2-klein-9b", "flux-1-schnell", "sdxl-lightning", "phoenix-1.0")


class AssetError(Exception):
    """Expected failure in asset generation/saving."""


# --------------------------------------------------------------------------- #
# configuration
# --------------------------------------------------------------------------- #

def _env_file_path() -> str:
    return os.environ.get("ORCHESTRA_ASSETS_ENV") or DEFAULT_CONFIG_FILE


def _parse_env_file(path: str) -> dict:
    values = {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                key, sep, value = stripped.partition("=")
                if not sep:
                    continue
                key = key.strip()
                value = value.strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
                    value = value[1:-1]
                values[key] = value
    except (OSError, UnicodeDecodeError):
        return {}
    return values


def _load_config() -> tuple[str | None, str | None]:
    """Env first, then the config file, per key."""
    file_values = _parse_env_file(_env_file_path())
    url = os.environ.get("ASSET_WORKER_URL") or file_values.get("ASSET_WORKER_URL")
    token = os.environ.get("ASSET_WORKER_TOKEN") or file_values.get("ASSET_WORKER_TOKEN")
    return url, token


# --------------------------------------------------------------------------- #
# worker HTTP
# --------------------------------------------------------------------------- #

def _request(method: str, url: str, token: str | None, payload: dict | None = None,
             timeout: float | None = None) -> tuple[int, bytes]:
    if timeout is None:
        timeout = TIMEOUT
    headers = {
        "Content-Type": "application/json",
        "User-Agent": "orchestra-assets/1.0",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as err:
        body = err.read()
        err.close()
        return err.code, body
    except socket.timeout:
        raise AssetError("worker unreachable: timed out") from None
    except urllib.error.URLError as err:
        raise AssetError(f"worker unreachable: {err.reason}") from None
    except http.client.HTTPException as err:
        raise AssetError(f"worker unreachable: {err}") from None
    except OSError as err:
        raise AssetError(f"worker unreachable: {err}") from None


def _error_text(body: bytes) -> str:
    try:
        data = json.loads(body.decode("utf-8"))
        if isinstance(data, dict) and isinstance(data.get("error"), str):
            return data["error"]
    except (ValueError, UnicodeDecodeError):
        pass
    return body.decode("utf-8", "replace")[:200]


# --------------------------------------------------------------------------- #
# paths
# --------------------------------------------------------------------------- #

def _project_root() -> str:
    return os.path.realpath(os.environ.get("ASSET_PROJECT_ROOT") or os.getcwd())


def _resolve(root: str, output_path: str) -> str:
    if os.path.isabs(output_path):
        return os.path.realpath(output_path)
    return os.path.realpath(os.path.join(root, output_path))


def _inside(root: str, resolved: str) -> bool:
    try:
        return os.path.commonpath([root, resolved]) == root
    except ValueError:
        return False


def _relpath(root: str, resolved: str) -> str:
    return Path(os.path.relpath(resolved, root)).as_posix()


# --------------------------------------------------------------------------- #
# format helpers
# --------------------------------------------------------------------------- #

def _detect_format(data: bytes) -> str | None:
    if data.startswith(PNG_SIGNATURE):
        return "png"
    if data.startswith(JPEG_SIGNATURE):
        return "jpeg"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    return None


def _suffix(output_path: str) -> str | None:
    """Lower-cased requested extension, or None if not a supported image ext."""
    lower = output_path.lower()
    for ext in _REQUESTED_EXTS:
        if lower.endswith(ext):
            return ext
    return None


def _ext_matches(fmt: str, requested_ext: str) -> bool:
    if fmt == "jpeg":
        return requested_ext in (".jpg", ".jpeg")
    return _FORMATS[fmt]["ext"] == requested_ext


def _png_dims(data: bytes) -> tuple[int, int]:
    if len(data) < 24 or data[12:16] != b"IHDR":
        return 0, 0
    width = int.from_bytes(data[16:20], "big")
    height = int.from_bytes(data[20:24], "big")
    return width, height


def _jpeg_dims(data: bytes) -> tuple[int, int]:
    if len(data) < 4 or data[:2] != b"\xff\xd8":
        return 0, 0
    i = 2
    n = len(data)
    while i + 3 < n:
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker == 0xFF:
            i += 1
            continue
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            i += 2
            continue
        if marker == 0xD9:
            return 0, 0
        if i + 3 >= n:
            return 0, 0
        length = int.from_bytes(data[i + 2 : i + 4], "big")
        if marker in _SOF_MARKERS:
            if length >= 7 and i + 8 < n:
                height = int.from_bytes(data[i + 5 : i + 7], "big")
                width = int.from_bytes(data[i + 7 : i + 9], "big")
                return width, height
            return 0, 0
        i += 2 + length
    return 0, 0


def _webp_dims(data: bytes) -> tuple[int, int]:
    if data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        return 0, 0
    tag = data[12:16]
    if tag == b"VP8X":
        if len(data) < 30:
            return 0, 0
        width = int.from_bytes(data[24:27], "little") + 1
        height = int.from_bytes(data[27:30], "little") + 1
        return width, height
    if tag == b"VP8 ":
        if len(data) < 30:
            return 0, 0
        width = int.from_bytes(data[26:28], "little") & 0x3FFF
        height = int.from_bytes(data[28:30], "little") & 0x3FFF
        return width, height
    if tag == b"VP8L":
        if len(data) < 25:
            return 0, 0
        bits = int.from_bytes(data[21:25], "little")
        width = ((bits >> 1) & 0x3FFF) + 1
        height = ((bits >> 15) & 0x3FFF) + 1
        return width, height
    return 0, 0


def _image_dims(fmt: str, data: bytes) -> tuple[int, int]:
    if fmt == "png":
        return _png_dims(data)
    if fmt == "jpeg":
        return _jpeg_dims(data)
    return _webp_dims(data)


def _format_saved(result: dict, requested_ext: str | None, *, bg_method: str | None = None, bg_model: str | None = None) -> str:
    text = (
        f"saved {result['path']} ({result['width']}x{result['height']}, "
        f"{result['bytes']} bytes, {result['format']})"
    )
    if bg_method is not None:
        if bg_method == "color":
            text += ", background removed (color key)"
        elif bg_method == "ai":
            text += f", background removed (ai: {bg_model})"
        else:  # auto
            text += f", background removed (auto)"
    if requested_ext and not _ext_matches(result["format"], requested_ext):
        text += (
            f" — extension changed from {requested_ext} to {_FORMATS[result['format']]['ext']}"
            f": reference {result['path']} in code"
        )
    return text


# --------------------------------------------------------------------------- #
# core
# --------------------------------------------------------------------------- #

def _image_model(value) -> str | None:
    """Explicit value, else ORCHESTRA_IMAGE_MODEL (env, then assets.env), else None (Worker default)."""
    if value is None:
        value = (os.environ.get("ORCHESTRA_IMAGE_MODEL")
                 or _parse_env_file(_env_file_path()).get("ORCHESTRA_IMAGE_MODEL"))
    if value is None:
        return None
    if value not in _IMAGE_MODELS:
        raise AssetError(f"image_model must be one of: {', '.join(_IMAGE_MODELS)}")
    return value


# --------------------------------------------------------------------------- #
# daily neuron budget (Cloudflare free tier: 10,000 neurons/day, account-wide;
# once exceeded EVERY model fails until 00:00 UTC). Estimates follow the official
# price list and cover only this machine's calls — a guard, not an invoice.
# --------------------------------------------------------------------------- #

DAILY_NEURONS = 10_000
USAGE_FILE = Path(os.environ.get("ORCHESTRA_USAGE_FILE",
                                 Path.home() / ".local/share/orchestra/usage.json"))


def _estimate_neurons(model: str | None, width: int, height: int, num_steps: int | None) -> float:
    tiles = math.ceil(width / 512) * math.ceil(height / 512)
    model = model or "flux-2-klein-4b"  # the Worker's default
    if model == "flux-2-klein-4b":
        return 26.05 * tiles
    if model == "flux-2-klein-9b":
        return 1363.64 + 181.82 * max(0, math.ceil(width * height / 1_048_576) - 1)
    if model == "flux-1-schnell":  # always renders 1024x1024
        return 4.80 * 4 + 9.60 * (num_steps or 4)
    if model == "phoenix-1.0":
        return 530.0 * tiles + 10.0 * (num_steps or 20)
    return 0.0  # sdxl-lightning: free while in beta


def _budget() -> float:
    try:
        return float(os.environ.get("ORCHESTRA_NEURON_BUDGET", 9000))
    except ValueError:
        return 9000.0


def _ledger(update=None) -> dict:
    """Read (and optionally update) today's usage under an exclusive file lock,
    so parallel batch threads and other Claude sessions don't lose increments."""
    today = datetime.now(timezone.utc).date().isoformat()
    USAGE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(USAGE_FILE, "a+", encoding="utf-8") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        fh.seek(0)
        try:
            data = json.loads(fh.read() or "{}")
        except ValueError:
            data = {}
        if data.get("date") != today:
            data = {"date": today, "neurons": 0.0, "images": 0, "exhausted": False}
        if update:
            update(data)
            fh.seek(0)
            fh.truncate()
            fh.write(json.dumps(data))
        return data


def _usage_note() -> str:
    d = _ledger()
    return (f"today ~{round(d['neurons'])}/{DAILY_NEURONS} neurons, {d['images']} images "
            "(estimate for this machine; resets 00:00 UTC)")


def _generate_on_worker(url: str, token: str, body: dict) -> tuple[int, bytes]:
    estimate = _estimate_neurons(body.get("model"), body["width"], body["height"], body.get("num_steps"))
    today = _ledger()
    if today.get("exhausted"):
        raise AssetError("Cloudflare daily free allocation already used up today: no image model works "
                         "until 00:00 UTC — do not retry; continue without new images or ask the user")
    if estimate and today["neurons"] + estimate > _budget():
        raise AssetError(f"daily image budget reached: ~{round(today['neurons'])} of {DAILY_NEURONS} neurons "
                         f"used today, this image needs ~{round(estimate)}. Use image_model sdxl-lightning "
                         "(free, weaker) or wait for 00:00 UTC (ORCHESTRA_NEURON_BUDGET raises the guard)")
    status, resp = _request("POST", f"{url.rstrip('/')}/generate", token, body)
    if status == 200:
        def add(d):
            d["neurons"] += estimate
            d["images"] += 1
        _ledger(add)
    elif status == 429 and b'"quota"' in resp:
        _ledger(lambda d: d.update(exhausted=True))
    return status, resp


def _worker_body(prompt: str, width: int, height: int, num_steps: int | None,
                 negative_prompt: str | None, seed: int | None, image_model: str | None) -> dict:
    # num_steps only when asked: each model has its own sensible default
    body = {"prompt": prompt, "width": width, "height": height}
    for key, value in (("num_steps", num_steps), ("negative_prompt", negative_prompt),
                       ("seed", seed), ("model", image_model)):
        if value is not None:
            body[key] = value
    return body


def _check_ints(width, height, num_steps) -> None:
    checks = [("width", width, 256, 2048), ("height", height, 256, 2048)]
    if num_steps is not None:
        checks.append(("num_steps", num_steps, 1, 50))
    for name, value, lo, hi in checks:
        if not isinstance(value, int) or isinstance(value, bool) or not (lo <= value <= hi):
            raise AssetError(f"{name} must be an integer between {lo} and {hi}")


def generate(prompt: str, output_path: str, *, width: int = 1024, height: int = 1024,
             num_steps: int | None = None, negative_prompt: str | None = None, seed: int | None = None,
             overwrite: bool = False, remove_background: bool = False,
             bg_model: str = DEFAULT_BG_MODEL, trim: bool = False,
             bg_method: str = DEFAULT_BG_METHOD, image_model: str | None = None) -> dict:
    url, token = _load_config()
    if not url or not token:
        raise AssetError(CONFIG_MISSING)
    if not prompt.strip():
        raise AssetError("prompt is required")
    requested_ext = _suffix(output_path)
    if requested_ext is None:
        raise AssetError("outputPath must end with .png, .jpg, .jpeg or .webp")
    root = _project_root()
    resolved = _resolve(root, output_path)
    if not _inside(root, resolved):
        raise AssetError(f"outputPath must stay inside {root}")
    rel = _relpath(root, resolved)
    if os.path.exists(resolved) and not overwrite:
        raise AssetError(f"exists: {rel} (pass overwrite=true)")
    _check_ints(width, height, num_steps)
    image_model = _image_model(image_model)

    if remove_background and bg_model not in _BG_MODELS:
        raise AssetError(f"bg_model must be one of: {', '.join(_BG_MODELS)}")
    if trim and not remove_background:
        raise AssetError("trim requires remove_background")
    if remove_background and bg_method not in _BG_METHODS:
        raise AssetError(f"bg_method must be one of: {', '.join(_BG_METHODS)}")

    body = _worker_body(prompt.strip(), width, height, num_steps, negative_prompt, seed, image_model)

    if remove_background:
        final = resolved[: -len(requested_ext)] + ".png"
        if not _inside(root, final):
            raise AssetError(f"outputPath must stay inside {root}")
        final_rel = _relpath(root, final)
        if os.path.exists(final) and not overwrite:
            raise AssetError(f"exists: {final_rel} (pass overwrite=true)")

    status, resp = _generate_on_worker(url, token, body)
    if status != 200:
        raise AssetError(f"worker error {status}: {_error_text(resp)}")
    fmt = _detect_format(resp)
    if fmt is None:
        raise AssetError("worker returned unknown image data")

    if remove_background:
        final_bytes, actual_method = _remove_background(resp, bg_model, trim, bg_method)

        if not _inside(root, final):
            raise AssetError(f"outputPath must stay inside {root}")
        if os.path.exists(final) and not overwrite:
            raise AssetError(f"exists: {final_rel} (pass overwrite=true)")
        _write_atomic(final, final_bytes)
        dim_w, dim_h = _image_dims("png", final_bytes)
        result = {
            "path": final_rel,
            "width": dim_w,
            "height": dim_h,
            "bytes": len(final_bytes),
            "format": "png",
            "mime": "image/png",
            "data": final_bytes,
            "method": actual_method,  # the one the helper really used (auto resolves to color/ai)
        }
        # Add prompt-length hint
        if len(prompt.strip().split()) > 55:
            result["prompt_length_hint"] = True
        return result

    if _ext_matches(fmt, requested_ext):
        final = resolved
    else:
        final = resolved[: -len(requested_ext)] + _FORMATS[fmt]["ext"]
    if not _inside(root, final):
        raise AssetError(f"outputPath must stay inside {root}")
    final_rel = _relpath(root, final)
    if os.path.exists(final) and not overwrite:
        raise AssetError(f"exists: {final_rel} (pass overwrite=true)")

    _write_atomic(final, resp)
    dim_w, dim_h = _image_dims(fmt, resp)
    return {
        "path": final_rel,
        "width": dim_w,
        "height": dim_h,
        "bytes": len(resp),
        "format": fmt,
        "mime": _FORMATS[fmt]["mime"],
        "data": resp,
    }


def _chmod_default(path: str) -> None:
    current = os.umask(0)
    os.umask(current)
    os.chmod(path, 0o666 & ~current)


def _write_atomic(final: str, data: bytes) -> None:
    parent = os.path.dirname(final) or "."
    os.makedirs(parent, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=parent, prefix=".asset-", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp_path, final)
    except BaseException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
    _chmod_default(final)


def _rembg_python() -> str:
    env = os.environ.get("ORCHESTRA_REMBG_PYTHON")
    if env:
        return env
    file_values = _parse_env_file(_env_file_path())
    path = file_values.get("ORCHESTRA_REMBG_PYTHON")
    if path:
        return path
    return REMBG_DEFAULT_PYTHON


def _remove_background(data: bytes, bg_model: str, trim: bool, bg_method: str = DEFAULT_BG_METHOD) -> tuple[bytes, str]:
    python = _rembg_python()
    if not (os.path.isfile(python) and os.access(python, os.X_OK)):
        raise AssetError(f"background removal unavailable: {python} not found ({REMBG_INSTALL_HINT})")
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "remove_bg.py")
    with tempfile.TemporaryDirectory(prefix=".asset-rembg-") as tmp_dir:
        tmp_in = os.path.join(tmp_dir, "input")
        tmp_out = os.path.join(tmp_dir, "output.png")
        with open(tmp_in, "wb") as fh:
            fh.write(data)
        cmd = [python, script, tmp_in, tmp_out, "--model", bg_model, "--method", bg_method]
        if trim:
            cmd.append("--trim")
        try:
            proc = subprocess.run(cmd, capture_output=True, timeout=REMBG_TIMEOUT)
        except subprocess.TimeoutExpired:
            raise AssetError("background removal timed out after 300 s") from None
        if proc.returncode == 3:
            raise AssetError(
                "background removal left an empty image: use a plain solid background in the prompt or remove_background=false"
            )
        if proc.returncode != 0:
            stderr = proc.stderr.decode("utf-8", "replace")
            last_nonempty = ""
            for line in stderr.splitlines():
                if line.strip():
                    last_nonempty = line.strip()
            raise AssetError(f"background removal failed: {last_nonempty}")
        with open(tmp_out, "rb") as fh:
            result_bytes = fh.read()
        # Parse JSON output to get the actual method used
        try:
            json_out = json.loads(proc.stdout.strip())
            actual_method = json_out.get("method", bg_method)
        except (json.JSONDecodeError, AttributeError):
            actual_method = bg_method
        return result_bytes, actual_method


# --------------------------------------------------------------------------- #
# MCP stdio server
# --------------------------------------------------------------------------- #

_TOOL_DESCRIPTION = (
    "Generate an image asset with the orchestra remote image worker and save it inside the "
    "project. The worker returns a raster image (PNG, JPEG or WebP); the model currently "
    "produces JPEG, so prefer the .jpg extension (output may still be saved as another "
    "format — the path returned in the result is authoritative). Write a detailed English "
    "visual prompt describing the subject, composition, style, lighting and colours. Avoid "
    "text and lettering in the image — render text in HTML/CSS instead. Pick an output path "
    "relative to the project root inside the project's asset directory (e.g. "
    "public/assets/hero.jpg) ending in .png, .jpg, .jpeg or .webp. "
    "Set remove_background=true to cut out the subject and save a transparent PNG — "
    "use for icons, sprites, logos; prompt for a plain solid background. "
    "For 2+ images use generate_assets (one call); prompts short, background and subject first."
)

_TOOL = {
    "name": "generate_asset",
    "description": _TOOL_DESCRIPTION,
    "inputSchema": {
        "type": "object",
        "properties": {
            "prompt": {"type": "string"},
            "outputPath": {
                "type": "string",
                "description": (
                    "path relative to project root, must end in .png, .jpg, .jpeg or .webp "
                    "(prefer .jpg — the model currently returns JPEG; the saved file's real "
                    "extension may differ, and the returned path is authoritative), "
                    "e.g. public/assets/hero.jpg"
                ),
            },
            "width": {"type": "integer", "minimum": 256, "maximum": 2048, "default": 1024},
            "height": {"type": "integer", "minimum": 256, "maximum": 2048, "default": 1024},
            "num_steps": {"type": "integer", "minimum": 1, "maximum": 50, "description": "omit to use the model default"},
            "image_model": {"type": "string", "enum": ["flux-2-klein-4b", "flux-2-klein-9b", "flux-1-schnell", "sdxl-lightning", "phoenix-1.0"], "description": "default flux-2-klein-4b (best prompt adherence, ~0.1 cent/image); sdxl-lightning is free but often ignores the prompt"},
            "negative_prompt": {"type": "string", "description": "what to avoid (English)"},
            "seed": {"type": "integer"},
            "overwrite": {"type": "boolean", "default": False},
            "preview": {"type": "boolean", "default": True},
            "remove_background": {
                "type": "boolean",
                "default": False,
                "description": (
                    "cut out the subject and save a transparent PNG — use for icons, "
                    "sprites, logos; prompt for a plain solid background. "
                    "auto = colour key when the background is flat (ask for 'solid plain <colour> background' FIRST in the prompt), else AI cut-out"
                ),
            },
            "bg_method": {
                "type": "string",
                "enum": ["auto", "color", "ai"],
                "default": "auto",
                "description": "background removal method: auto=color key for flat bg, ai=rembg (default auto)"
            },
            "bg_model": {
                "type": "string",
                "enum": ["u2net", "u2netp", "silueta", "isnet-general-use", "isnet-anime"],
                "default": "isnet-general-use",
            },
            "trim": {
                "type": "boolean",
                "default": False,
                "description": "crop to the subject; only with remove_background",
            },
        },
        "required": ["prompt", "outputPath"],
    },
}

_TOOL_GENERATE_ASSETS = {
    "name": "generate_assets",
    "description": ("Use for 2+ separate images (different sizes/compositions, or when each must be exact): one call, "
                    "items generated in parallel, one contact-sheet preview. For many small icons prefer generate_icon_sheet with items."),
    "inputSchema": {
        "type": "object",
        "properties": {
            "items": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "prompt": {"type": "string"},
                        "outputPath": {"type": "string"},
                    },
                    "required": ["prompt", "outputPath"],
                },
                "minItems": 1,
                "maxItems": 16,
            },
            "style": {"type": "string", "description": "shared style appended to each prompt"},
            "negative_prompt": {"type": "string", "description": "what to avoid (English)"},
            "width": {"type": "integer", "minimum": 256, "maximum": 2048, "default": 1024},
            "height": {"type": "integer", "minimum": 256, "maximum": 2048, "default": 1024},
            "num_steps": {"type": "integer", "minimum": 1, "maximum": 50, "description": "omit to use the model default"},
            "image_model": {"type": "string", "enum": ["flux-2-klein-4b", "flux-2-klein-9b", "flux-1-schnell", "sdxl-lightning", "phoenix-1.0"], "description": "default flux-2-klein-4b (best prompt adherence, ~0.1 cent/image); sdxl-lightning is free but often ignores the prompt"},
            "remove_background": {"type": "boolean", "default": False},
            "bg_method": {"type": "string", "enum": ["auto", "color", "ai"], "default": "auto"},
            "bg_model": {"type": "string", "enum": ["u2net", "u2netp", "silueta", "isnet-general-use", "isnet-anime"], "default": "isnet-general-use"},
            "trim": {"type": "boolean", "default": False},
            "overwrite": {"type": "boolean", "default": False},
            "preview": {"type": "boolean", "default": True},
        },
        "required": ["items"],
    },
}

_TOOL_GENERATE_ICON_SHEET = {
    "name": "generate_icon_sheet",
    "description": ("Cheapest way to get many icons: ONE generation, icons cut out and saved automatically, one contact-sheet preview. "
                    "With `items` (up to 24 named subjects) FLUX draws them in order in a grid — check the contact sheet and rename; "
                    "without items you get a varied set in one style to pick from."),
    "inputSchema": {
        "type": "object",
        "properties": {
            "prompt": {"type": "string", "description": "theme + style, required"},
            "outputDir": {"type": "string", "description": "directory inside project root, required"},
            "items": {"type": "array", "items": {"type": "string"}, "minItems": 2, "maxItems": 24,
                      "description": "named subjects in order (e.g. [\"sun\", \"red balloon\"]): one generation draws them in a grid; files are numbered in reading order"},
            "prefix": {"type": "string", "pattern": "^[a-z0-9][a-z0-9_-]{0,40}$", "default": "icon"},
            "background": {"type": "string", "default": "plain green"},
            "count_hint": {"type": "integer", "minimum": 2, "maximum": 40, "default": 12},
            "width": {"type": "integer", "minimum": 256, "maximum": 2048, "default": 1024},
            "height": {"type": "integer", "minimum": 256, "maximum": 2048, "default": 1024},
            "num_steps": {"type": "integer", "minimum": 1, "maximum": 50, "description": "omit to use the model default"},
            "image_model": {"type": "string", "enum": ["flux-2-klein-4b", "flux-2-klein-9b", "flux-1-schnell", "sdxl-lightning", "phoenix-1.0"], "description": "default flux-2-klein-4b (best prompt adherence, ~0.1 cent/image); sdxl-lightning is free but often ignores the prompt"},
            "negative_prompt": {"type": "string"},
            "overwrite": {"type": "boolean", "default": False},
            "preview": {"type": "boolean", "default": True},
        },
        "required": ["prompt", "outputDir"],
    },
}


def _rpc_response(rid, *, result=None, error=None) -> dict:
    msg = {"jsonrpc": "2.0", "id": rid}
    if error is not None:
        msg["error"] = error
    else:
        msg["result"] = result
    return msg


def _require_boolean(args: dict, name: str, default: bool) -> bool:
    value = args.get(name, default)
    if not isinstance(value, bool):
        raise AssetError(f"{name} must be a boolean")
    return value


def _call_generate(args: dict) -> dict:
    prompt = args.get("prompt") if isinstance(args.get("prompt"), str) else ""
    output_path = args.get("outputPath") if isinstance(args.get("outputPath"), str) else ""
    width = args.get("width", 1024)
    height = args.get("height", 1024)
    num_steps = args.get("num_steps")
    if width is None:
        width = 1024
    if height is None:
        height = 1024
    negative_prompt = args.get("negative_prompt")
    seed = args.get("seed")
    overwrite = _require_boolean(args, "overwrite", False)
    preview = _require_boolean(args, "preview", True)
    remove_background = _require_boolean(args, "remove_background", False)
    trim = _require_boolean(args, "trim", False)
    bg_model = args.get("bg_model", DEFAULT_BG_MODEL)
    if bg_model is None:
        bg_model = DEFAULT_BG_MODEL
    bg_method = args.get("bg_method", DEFAULT_BG_METHOD)
    if bg_method is None:
        bg_method = DEFAULT_BG_METHOD

    result = generate(
        prompt, output_path,
        width=width, height=height, num_steps=num_steps,
        negative_prompt=negative_prompt, seed=seed, overwrite=overwrite,
        remove_background=remove_background, bg_model=bg_model, trim=trim,
        bg_method=bg_method, image_model=args.get("image_model"),
    )
    bg_method_out = result.get("method", bg_method) if remove_background else None
    text = _format_saved(result, _suffix(output_path), bg_method=bg_method_out, bg_model=bg_model if remove_background else None)
    text += f"\n{_usage_note()}"
    if result.get("prompt_length_hint"):
        text += " — note: SDXL reads only ~60 words; put background and subject first"
    content = [{"type": "text", "text": text}]
    if preview:
        content.append({
            "type": "image",
            "data": base64.b64encode(result["data"]).decode("ascii"),
            "mimeType": result["mime"],
        })
    return {"content": content, "isError": False}


def _is_error_result(message: str) -> dict:
    return {"content": [{"type": "text", "text": message}], "isError": True}


def handle_line(line: str) -> dict | None:
    """Process one newline-delimited request; returns the response dict or None
    for notifications."""
    try:
        msg = json.loads(line)
    except ValueError:
        return _rpc_response(
            None, error={"code": -32700, "message": "Parse error"},
        )
    if not isinstance(msg, dict):
        return _rpc_response(
            None, error={"code": -32600, "message": "Invalid Request"},
        )
    if "id" not in msg:
        return None
    rid = msg["id"]
    method = msg.get("method")

    if method == "initialize":
        params = msg.get("params") if isinstance(msg.get("params"), dict) else {}
        result = {
            "protocolVersion": params.get("protocolVersion", "2024-11-05"),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "orchestra-assets", "version": "1.0.0"},
        }
        return _rpc_response(rid, result=result)
    if method == "ping":
        return _rpc_response(rid, result={})
    if method == "tools/list":
        return _rpc_response(rid, result={"tools": [_TOOL, _TOOL_GENERATE_ASSETS, _TOOL_GENERATE_ICON_SHEET]})
    if method == "tools/call":
        params = msg.get("params") if isinstance(msg.get("params"), dict) else {}
        name = params.get("name")
        raw_args = params.get("arguments")
        args = raw_args if isinstance(raw_args, dict) else {}
        try:
            if name == "generate_asset":
                result = _call_generate(args)
            elif name == "generate_assets":
                result = _call_generate_assets(args)
            elif name == "generate_icon_sheet":
                result = _call_generate_icon_sheet(args)
            else:
                return _rpc_response(
                    rid, error={"code": -32602, "message": f"Unknown tool: {name}"},
                )
        except AssetError as err:
            result = _is_error_result(str(err))
        except Exception as err:  # keep serving; surface as a tool result
            result = _is_error_result(f"internal error: {type(err).__name__}: {err}")
        return _rpc_response(rid, result=result)
    return _rpc_response(rid, error={"code": -32601, "message": "Method not found"})


def serve() -> None:
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            response = handle_line(line)
        except Exception as err:  # defensive: never take the server down on a bug
            response = _rpc_response(
                None, error={"code": -32603, "message": f"Internal error: {err}"},
            )
        if response is not None:
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

def cmd_generate(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="orchestra/asset_mcp.py generate")
    parser.add_argument("prompt")
    parser.add_argument("output")
    parser.add_argument("--width", type=int)
    parser.add_argument("--height", type=int)
    parser.add_argument("--steps", type=int, dest="num_steps")
    parser.add_argument("--negative", dest="negative_prompt")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--remove-bg", action="store_true", dest="remove_background")
    parser.add_argument("--bg-model", default=DEFAULT_BG_MODEL, dest="bg_model")
    parser.add_argument("--bg-method", choices=_BG_METHODS, default=DEFAULT_BG_METHOD, dest="bg_method")
    parser.add_argument("--trim", action="store_true")
    parser.add_argument("--image-model", choices=_IMAGE_MODELS, dest="image_model")
    args = parser.parse_args(argv)
    try:
        result = generate(
            args.prompt, args.output,
            width=args.width if args.width is not None else 1024,
            height=args.height if args.height is not None else 1024,
            num_steps=args.num_steps,
            negative_prompt=args.negative_prompt,
            seed=args.seed,
            overwrite=args.overwrite,
            remove_background=args.remove_background,
            bg_model=args.bg_model,
            trim=args.trim,
            bg_method=args.bg_method,
            image_model=args.image_model,
        )
    except AssetError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
    bg_method_out = result.get("method", args.bg_method) if args.remove_background else None
    text = _format_saved(result, _suffix(args.output), bg_method=bg_method_out, bg_model=args.bg_model if args.remove_background else None)
    if result.get("prompt_length_hint"):
        text += " — note: SDXL reads only ~60 words; put background and subject first"
    print(text)
    return 0


def cmd_check() -> int:
    url, token = _load_config()
    print(f"url: {url or 'missing'}")
    print(f"token: {'set' if token else 'missing'}")
    if not url:
        print("health: missing url")
        return 1
    try:
        status, body = _request("GET", f"{url.rstrip('/')}/health", token)
    except AssetError as err:
        print(f"health: {err}")
        return 1
    if status != 200:
        print(f"health: worker error {status}: {_error_text(body)}")
        return 1
    text = body.decode("utf-8", "replace")
    print(f"health: {text}")
    try:
        ok = json.loads(text).get("ok")
    except (ValueError, AttributeError):
        ok = False
    return 0 if ok is True else 1


# --------------------------------------------------------------------------- #
# generate_assets (batch) tool
# --------------------------------------------------------------------------- #

def _call_generate_assets(args: dict) -> dict:
    items = args.get("items")
    if not isinstance(items, list) or not (1 <= len(items) <= 16):
        return _is_error_result("items must be an array of 1–16 objects with prompt and outputPath")
    for i, item in enumerate(items):
        if not isinstance(item, dict) or not isinstance(item.get("prompt"), str) or not isinstance(item.get("outputPath"), str):
            return _is_error_result(f"items[{i}] must have string prompt and outputPath")

    style = args.get("style")
    negative_prompt = args.get("negative_prompt")
    width = args.get("width", 1024)
    height = args.get("height", 1024)
    num_steps = args.get("num_steps")
    remove_background = _require_boolean(args, "remove_background", False)
    bg_method = args.get("bg_method", DEFAULT_BG_METHOD)
    if bg_method is None:
        bg_method = DEFAULT_BG_METHOD
    bg_model = args.get("bg_model", DEFAULT_BG_MODEL)
    if bg_model is None:
        bg_model = DEFAULT_BG_MODEL
    trim = _require_boolean(args, "trim", False)
    overwrite = _require_boolean(args, "overwrite", False)
    preview = _require_boolean(args, "preview", True)

    # Validate shared args once, before any worker call
    try:
        _check_ints(width, height, num_steps)
        image_model = _image_model(args.get("image_model"))
    except AssetError as err:
        return _is_error_result(str(err))
    if remove_background and bg_model not in _BG_MODELS:
        return _is_error_result(f"bg_model must be one of: {', '.join(_BG_MODELS)}")
    if trim and not remove_background:
        return _is_error_result("trim requires remove_background")
    if bg_method not in _BG_METHODS:
        return _is_error_result(f"bg_method must be one of: {', '.join(_BG_METHODS)}")

    # Process items in parallel (up to 4)
    from concurrent.futures import ThreadPoolExecutor, as_completed
    import threading

    results = [None] * len(items)
    lock = threading.Lock()
    success_count = 0

    def process_item(idx, item):
        nonlocal success_count
        item_prompt = item["prompt"]
        item_output = item["outputPath"]
        if style:
            item_prompt = f"{item_prompt}, {style}"
        try:
            result = generate(
                item_prompt, item_output,
                width=width, height=height, num_steps=num_steps,
                negative_prompt=negative_prompt, seed=None, overwrite=overwrite,
                remove_background=remove_background, bg_model=bg_model, trim=trim,
                bg_method=bg_method, image_model=image_model,
            )
            with lock:
                success_count += 1
            return idx, result, None
        except AssetError as err:
            return idx, None, str(err)
        except Exception as err:
            return idx, None, f"internal error: {type(err).__name__}: {err}"

    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = [executor.submit(process_item, i, item) for i, item in enumerate(items)]
        for future in as_completed(futures):
            idx, result, error = future.result()
            results[idx] = (result, error)

    # Build output lines
    lines = []
    saved_files = []
    for i, (result, error) in enumerate(results):
        if error:
            lines.append(f"{i+1}. error: {error}")
        else:
            bg_method_out = result.get("method", bg_method) if remove_background else None
            text = _format_saved(result, _suffix(items[i]["outputPath"]), bg_method=bg_method_out, bg_model=bg_model if remove_background else None)
            if result.get("prompt_length_hint"):
                text += " — note: SDXL reads only ~60 words; put background and subject first"
            lines.append(f"{i+1}. {text}")
            saved_files.append(result["path"])

    lines.append(_usage_note())
    content = [{"type": "text", "text": "\n".join(lines)}]
    is_error = success_count == 0

    if preview and saved_files:
        # Create contact sheet using remove_bg.py contact
        rembg_python = _rembg_python()
        if os.path.isfile(rembg_python) and os.access(rembg_python, os.X_OK):
            script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "remove_bg.py")
            root = _project_root()
            with tempfile.TemporaryDirectory(prefix=".asset-contact-") as tmp_dir:
                contact_path = os.path.join(tmp_dir, "_contact.png")
                pairs = []
                for idx, path in enumerate(saved_files, 1):
                    label = f"{idx:02d}" if len(saved_files) <= 99 else f"{idx:03d}"
                    full_path = os.path.join(root, path)
                    if os.path.exists(full_path):
                        pairs.append(f"{label}={full_path}")
                if pairs:
                    cmd = [rembg_python, script, "contact", contact_path] + pairs
                    try:
                        subprocess.run(cmd, capture_output=True, timeout=30)
                        if os.path.exists(contact_path):
                            with open(contact_path, "rb") as fh:
                                contact_data = fh.read()
                            content.append({
                                "type": "image",
                                "data": base64.b64encode(contact_data).decode("ascii"),
                                "mimeType": "image/png",
                            })
                    except Exception:
                        pass

    return {"content": content, "isError": is_error}


# --------------------------------------------------------------------------- #
# generate_icon_sheet tool
# --------------------------------------------------------------------------- #

def _call_generate_icon_sheet(args: dict) -> dict:
    prompt = args.get("prompt") if isinstance(args.get("prompt"), str) else ""
    output_dir = args.get("outputDir") if isinstance(args.get("outputDir"), str) else ""
    prefix = args.get("prefix", "icon")
    background = args.get("background", "plain green")
    count_hint = args.get("count_hint", 12)
    named = args.get("items")  # subjects asked for (not the cut-out icons below)
    width = args.get("width")
    height = args.get("height")
    num_steps = args.get("num_steps")
    negative_prompt = args.get("negative_prompt")
    overwrite = _require_boolean(args, "overwrite", False)
    preview = _require_boolean(args, "preview", True)

    if not prompt.strip():
        return _is_error_result("prompt is required")
    if not output_dir.strip():
        return _is_error_result("outputDir is required")
    import re
    if not re.match(r"^[a-z0-9][a-z0-9_-]{0,40}$", prefix):
        return _is_error_result("prefix must match ^[a-z0-9][a-z0-9_-]{0,40}$")
    if named is not None:
        if (not isinstance(named, list) or not (2 <= len(named) <= 24)
                or not all(isinstance(i, str) and i.strip() for i in named)):
            return _is_error_result("items must be an array of 2–24 non-empty strings")
        named = [i.strip() for i in named]
        count_hint = len(named)
    if not isinstance(count_hint, int) or not (2 <= count_hint <= 40):
        return _is_error_result("count_hint must be an integer between 2 and 40")
    # grid the model is asked to draw; the canvas gets the same proportions, otherwise
    # FLUX fills a square canvas with extra rows of duplicates (seen in tests)
    cols = math.ceil(math.sqrt(count_hint))
    rows = math.ceil(count_hint / cols)
    if width is None:
        width = 1024
    if height is None:
        height = max(256, min(2048, round(width * rows / cols / 16) * 16)) if named else 1024
    try:
        _check_ints(width, height, num_steps)
        image_model = _image_model(args.get("image_model"))
    except AssetError as err:
        return _is_error_result(str(err))

    root = _project_root()
    resolved_dir = _resolve(root, output_dir)
    if not _inside(root, resolved_dir):
        return _is_error_result(f"outputDir must stay inside {root}")

    # Check if any target files exist and overwrite is false
    if not overwrite:
        for i in range(1, count_hint + 1):
            name = f"{prefix}-{i:02d}.png" if count_hint <= 99 else f"{prefix}-{i:03d}.png"
            target = os.path.join(resolved_dir, name)
            if os.path.exists(target):
                return _is_error_result(f"exists: {_relpath(root, target)} (pass overwrite=true)")

    # Build worker prompt
    if named:
        worker_prompt = (
            f"A sticker sheet with exactly {count_hint} separate {prompt} icons in a grid of "
            f"{cols} columns and {rows} rows with wide gaps, in this order: {', '.join(named)}. "
            f"Solid {background} background, white sticker outline, no text"
        )
    else:
        worker_prompt = f"solid {background} background, sticker sheet of about {count_hint} separate {prompt}, well separated, no text"
    if negative_prompt is None:
        negative_prompt = "text, letters, numbers, tiles, squares, frames, borders, gradient background, shadow, overlapping"

    # Call worker
    url, token = _load_config()
    if not url or not token:
        return _is_error_result(CONFIG_MISSING)

    body = _worker_body(worker_prompt, width, height, num_steps, negative_prompt or None, None, image_model)

    try:
        status, resp = _generate_on_worker(url, token, body)
    except AssetError as err:  # budget / quota guard, network failure
        return _is_error_result(str(err))
    if status != 200:
        return _is_error_result(f"worker error {status}: {_error_text(resp)}")
    fmt = _detect_format(resp)
    if fmt is None:
        return _is_error_result("worker returned unknown image data")

    # Save sheet to temp file and run remove_bg.py split
    rembg_python = _rembg_python()
    if not (os.path.isfile(rembg_python) and os.access(rembg_python, os.X_OK)):
        return _is_error_result(f"background removal unavailable: {rembg_python} not found ({REMBG_INSTALL_HINT})")

    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "remove_bg.py")
    with tempfile.TemporaryDirectory(prefix=".asset-sheet-") as tmp_dir:
        sheet_in = os.path.join(tmp_dir, "sheet.jpg")
        split_outdir = os.path.join(tmp_dir, "split")
        with open(sheet_in, "wb") as fh:
            fh.write(resp)
        # always colour key: an AI cut-out treats a whole sheet as ONE subject, so the
        # icons merge into a single blob (seen on real sheets whose icons touch the border)
        cmd = [rembg_python, script, "split", sheet_in, split_outdir, "--method", "color"]
        try:
            proc = subprocess.run(cmd, capture_output=True, timeout=REMBG_TIMEOUT)
        except subprocess.TimeoutExpired:
            return _is_error_result("background removal timed out after 300 s")
        if proc.returncode == 3:
            return _is_error_result("no icons found in the sheet: regenerate or change the prompt")
        if proc.returncode != 0:
            stderr = proc.stderr.decode("utf-8", "replace")
            last_nonempty = ""
            for line in stderr.splitlines():
                if line.strip():
                    last_nonempty = line.strip()
            return _is_error_result(f"background removal failed: {last_nonempty}")

        # Parse split output
        try:
            split_result = json.loads(proc.stdout.strip())
        except json.JSONDecodeError:
            return _is_error_result("failed to parse split output")

        count = split_result.get("count", 0)
        method = split_result.get("method", "auto")
        items = split_result.get("items", [])

        if count == 0:
            return _is_error_result("no icons found in the sheet: regenerate or change the prompt")

        # The sheet may hold more icons than count_hint: check every real target
        # before writing any, so nothing is overwritten silently.
        targets = [os.path.join(resolved_dir, f"{prefix}-{item['file']}") for item in items]
        if not overwrite:
            for target in targets:
                if os.path.exists(target):
                    return _is_error_result(f"exists: {_relpath(root, target)} (pass overwrite=true)")
        # copy through _write_atomic: the temp dir may be on another filesystem
        # (os.replace would fail with EXDEV) and saved assets need mode 0644
        for item, target in zip(items, targets):
            with open(os.path.join(split_outdir, item["file"]), "rb") as fh:
                _write_atomic(target, fh.read())

        # Build output text
        lines = [f"sheet: {count} icons from 1 generation (method {method})"]
        for item in items:
            rel = _relpath(root, os.path.join(resolved_dir, f"{prefix}-{item['file']}"))
            lines.append(f"{item['file'][:-4]} {rel} ({item['width']}x{item['height']})")
        if named:
            lines.append(f"asked for, in order: {', '.join(f'{n}. {it}' for n, it in enumerate(named, 1))}")
            lines.append("icons are numbered in reading order; the model may skip, repeat or reorder items: "
                         "check the contact sheet, rename files to their subjects, and ask again only for the missing ones")
        else:
            lines.append("pick what you need, delete or rename the rest")

        lines.append(_usage_note())
        content = [{"type": "text", "text": "\n".join(lines)}]

        if preview:
            contact_src = os.path.join(split_outdir, "_contact.png")
            if os.path.exists(contact_src):
                with open(contact_src, "rb") as fh:
                    contact_data = fh.read()
                content.append({
                    "type": "image",
                    "data": base64.b64encode(contact_data).decode("ascii"),
                    "mimeType": "image/png",
                })

        return {"content": content, "isError": False}


# --------------------------------------------------------------------------- #
# CLI batch and sheet commands
# --------------------------------------------------------------------------- #

def cmd_batch(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="orchestra/asset_mcp.py batch")
    parser.add_argument("file", help="JSON file with generate_assets arguments")
    args = parser.parse_args(argv)

    try:
        with open(args.file, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as err:
        print(f"error: {err}", file=sys.stderr)
        return 1

    result = _call_generate_assets(data)
    for item in result["content"]:
        if item["type"] == "text":
            print(item["text"])
    return 0 if not result["isError"] else 1


def cmd_sheet(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="orchestra/asset_mcp.py sheet")
    parser.add_argument("prompt")
    parser.add_argument("outputDir")
    parser.add_argument("--prefix", default="icon")
    parser.add_argument("--background", default="plain green")
    parser.add_argument("--count", type=int, default=12, dest="count_hint")
    parser.add_argument("--item", action="append", dest="items",
                        help="named subject, repeat in order (e.g. --item sun --item 'red balloon')")
    parser.add_argument("--image-model", choices=_IMAGE_MODELS, dest="image_model")
    parser.add_argument("--width", type=int)
    parser.add_argument("--height", type=int)
    parser.add_argument("--steps", type=int, dest="num_steps")
    parser.add_argument("--negative", dest="negative_prompt")
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args(argv)

    data = {
        "prompt": args.prompt,
        "outputDir": args.outputDir,
        "prefix": args.prefix,
        "background": args.background,
        "count_hint": args.count_hint,
        "width": args.width,
        "height": args.height,
        "num_steps": args.num_steps,
        "items": args.items,
        "image_model": args.image_model,
        "negative_prompt": args.negative_prompt,
        "overwrite": args.overwrite,
        "preview": True,
    }

    result = _call_generate_icon_sheet(data)
    for item in result["content"]:
        if item["type"] == "text":
            print(item["text"])
    return 0 if not result["isError"] else 1


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else list(argv)
    if not argv or argv[0] == "serve":
        serve()
        return 0
    if argv[0] == "generate":
        return cmd_generate(argv[1:])
    if argv[0] == "check":
        return cmd_check()
    if argv[0] == "batch":
        return cmd_batch(argv[1:])
    if argv[0] == "sheet":
        return cmd_sheet(argv[1:])
    print(f"error: unknown command: {argv[0]}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())