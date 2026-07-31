#!/usr/bin/env python3
"""
gen_hero.py — generate a GrowSense blog hero with OpenAI's image model
(gpt-image-1 — the same engine behind ChatGPT image generation) and
auto-resize it to the house hero spec, saved straight into blog/.

House spec enforced in code: 1600x900, JPEG, quality <=92, <290 KB
(the same numbers we resize to by hand today).

Usage:
    export OPENAI_API_KEY=sk-...                 # your key; never hardcoded
    python tools/gen_hero.py gs-065 "A calm, warm photo of ..."
    python tools/gen_hero.py gs-065 "..." --quality medium
    python tools/gen_hero.py gs-065 "..." --edit blog/gs-065-hero.jpg  # iterate on a prior image

Requires:  pip install openai pillow
The API key is read from OPENAI_API_KEY only — this file never stores it.
It writes the JPEG and STOPS. You review it, then commit/deploy by hand —
the human accuracy check is deliberately not automated (a wrong medical
image is the one thing a pipeline must never ship silently).
"""

import argparse
import base64
import io
import os
import sys
from pathlib import Path

from openai import OpenAI
from PIL import Image

BLOG_DIR = Path(__file__).resolve().parents[1] / "blog"
TARGET = (1600, 900)          # 16:9
MAX_KB = 290
GEN_SIZE = "1536x1024"        # closest landscape gpt-image-1 offers; cropped to 16:9


def crop_to_16x9(im: Image.Image) -> Image.Image:
    ratio = 16 / 9
    w, h = im.size
    if w / h > ratio:                      # too wide -> trim sides
        nw = int(h * ratio)
        x = (w - nw) // 2
        return im.crop((x, 0, x + nw, h))
    nh = int(w / ratio)                    # too tall -> trim top/bottom
    y = (h - nh) // 2
    return im.crop((0, y, w, y + nh))


def save_to_spec(im: Image.Image, dst: Path):
    im = crop_to_16x9(im).resize(TARGET, Image.LANCZOS).convert("RGB")
    q = 92
    for q in (92, 88, 85, 82, 78):
        im.save(dst, "JPEG", quality=q, optimize=True, progressive=True)
        if dst.stat().st_size <= MAX_KB * 1024:
            break
    return q, dst.stat().st_size // 1024


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("slug", help="e.g. gs-065  ->  blog/gs-065-hero.jpg")
    ap.add_argument("prompt")
    ap.add_argument("--quality", default="high", choices=["low", "medium", "high"])
    ap.add_argument("--edit", help="path to a prior image to iterate on")
    args = ap.parse_args()

    if not os.getenv("OPENAI_API_KEY"):
        sys.exit("Set OPENAI_API_KEY first (your key; never hardcode it).")

    client = OpenAI()
    if args.edit:
        with open(args.edit, "rb") as f:
            resp = client.images.edit(
                model="gpt-image-1", image=f, prompt=args.prompt,
                size=GEN_SIZE, quality=args.quality, n=1,
            )
    else:
        resp = client.images.generate(
            model="gpt-image-1", prompt=args.prompt,
            size=GEN_SIZE, quality=args.quality, n=1,
        )

    raw = base64.b64decode(resp.data[0].b64_json)
    im = Image.open(io.BytesIO(raw))
    dst = BLOG_DIR / f"{args.slug}-hero.jpg"
    q, kb = save_to_spec(im, dst)
    print(f"saved {dst}  ->  1600x900  q{q}  {kb} KB")
    print("Review it before committing — the accuracy check is yours, not the script's.")


if __name__ == "__main__":
    main()
