"""Build the 1920x1080 assignment video from evaluation clips, with a short heading per segment.

Clips are the 768x256 three-camera videos LabUtopia writes (front | top | wrist). Each is scaled 2.5x into
a 1920x640 band; the heading, a one-line note and camera labels are drawn on the bars above and below.
Uses the ffmpeg bundled with imageio-ffmpeg and Noto Sans CJK for Japanese text.

Usage: python scripts/make_video.py <segments.json> <output.mp4>
segments.json: [{"kind": "card", "lines": [...], "seconds": 4} |
                {"kind": "clip", "path": "...mp4", "start": 0, "end": null, "heading": "...", "note": "..."}]
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont

W, H, BAND_H = 1920, 1080, 640
BAND_Y = (H - BAND_H) // 2
FPS = 30
BG, FG, SUB, ACCENT, LABEL = (17, 24, 26), (245, 247, 247), (196, 208, 210), (60, 160, 172), (150, 165, 168)
BOLD = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
REGULAR = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
CAMERAS = ["正面カメラ（方策の入力）", "真上カメラ（方策の入力）", "手首カメラ（記録のみ）"]
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()


def font(path, size):
    return ImageFont.truetype(path, size, index=0)  # index 0 = Japanese face in the Noto CJK collection


def centered(draw, y, text, fnt, fill):
    w = draw.textlength(text, font=fnt)
    draw.text(((W - w) / 2, y), text, font=fnt, fill=fill)


def overlay_png(heading, note, path):
    img = Image.new("RGBA", (W, H), BG + (255,))
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, BAND_Y, W, BAND_Y + BAND_H], fill=(0, 0, 0, 0))  # transparent band for the video
    draw.rectangle([96, 92, 104, 156], fill=ACCENT)
    draw.text((128, 84), heading, font=font(BOLD, 52), fill=FG)
    if note:
        draw.text((128, 160), note, font=font(REGULAR, 32), fill=SUB)
    for i, label in enumerate(CAMERAS):
        w = draw.textlength(label, font=font(REGULAR, 28))
        draw.text((i * W / 3 + (W / 3 - w) / 2, BAND_Y + BAND_H + 18), label, font=font(REGULAR, 28), fill=LABEL)
    img.save(path)


def card_png(lines, path):
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    sizes = {"title": (BOLD, 72, FG), "h": (BOLD, 44, FG), "p": (REGULAR, 34, SUB), "small": (REGULAR, 28, LABEL)}
    blocks = [(sizes[kind], text) for kind, text in lines]
    heights = [s[1] * 1.7 for s, _ in blocks]
    y = (H - sum(heights)) / 2
    for ((path_, size, fill), text), h in zip(blocks, heights):
        if text:
            centered(draw, y, text, font(path_, size), fill)
        y += h
    img.save(path)


def run(args):
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def main():
    segments = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    out = Path(sys.argv[2])
    tmp = Path(tempfile.mkdtemp(prefix="pai_video_"))
    parts = []
    for i, seg in enumerate(segments):
        part = tmp / f"part{i:02d}.mp4"
        if seg["kind"] == "card":
            png = tmp / f"card{i:02d}.png"
            card_png(seg["lines"], png)
            run(["-loop", "1", "-t", str(seg["seconds"]), "-i", str(png), "-r", str(FPS),
                 "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", str(part)])
        else:
            png = tmp / f"overlay{i:02d}.png"
            overlay_png(seg["heading"], seg.get("note", ""), png)
            trim = ["-ss", str(seg.get("start", 0))] + (["-to", str(seg["end"])] if seg.get("end") else [])
            run([*trim, "-i", seg["path"], "-i", str(png), "-filter_complex",
                 f"[0:v]fps={FPS},scale={W}:{BAND_H}:flags=lanczos,pad={W}:{H}:0:{BAND_Y}[v];[v][1:v]overlay=0:0",
                 "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-an", str(part)])
        parts.append(part)
    listing = tmp / "parts.txt"
    listing.write_text("".join(f"file '{p}'\n" for p in parts), encoding="utf-8")
    out.parent.mkdir(parents=True, exist_ok=True)
    run(["-f", "concat", "-safe", "0", "-i", str(listing), "-c", "copy", "-movflags", "+faststart", str(out)])
    print("written", out)


if __name__ == "__main__":
    main()
