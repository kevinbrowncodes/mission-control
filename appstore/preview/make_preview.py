#!/usr/bin/env python3
"""Builds the Mac App Store app preview from the stills in stills/.

The stills are Hands looks taken on the Mac Studio 2022 (4K, scaled to 1920x1080); Hands
records at 4 fps, so the preview is cut from stills instead: a slow zoom on each, a short
crossfade between them, a caption bar, an end card, and a silent stereo track (App Store
Connect wants an audio track). Output: preview.mp4 next to this file (not committed).

    python3 appstore/preview/make_preview.py

Needs ffmpeg. App previews for the Mac: 1920x1080, 15-30 s, H.264, 30 fps.
"""
import os
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FPS = 30
W, H = 1920, 1080
FADE = 0.4

# (still, seconds, caption, zoom focus as fractions of the frame)
SHOTS = [
    ("01-research.jpg", 2.5, "Remoted in? Your shortcuts may not reach this Mac.", (0.5, 0.5)),
    ("02-panel-research.jpg", 3.0, "One click opens Mission Control Launcher", (0.68, 0.22)),
    ("08-mc-all-names.jpg", 3.5, "Name your Spaces", (0.5, 0.12)),
    ("03-mc-research.jpg", 2.5, "The name fills each Space's thumbnail", (0.5, 0.5)),
    ("04-writing.jpg", 2.0, "Switch Spaces with a click", (0.3, 0.3)),
    ("05-panel-writing.jpg", 2.0, "This Space ▸ Rename…", (0.68, 0.18)),
    ("06-rename-writing.jpg", 2.5, "Type a name. Press Return.", (0.5, 0.45)),
    ("07-mc-writing.jpg", 2.5, "Always know which desktop is which", (0.5, 0.5)),
]
END_SECONDS = 3.0
END_TITLE = "Mission Control Launcher"
END_SUB = "Mission Control, Spaces and apps, one click away"

def captions(tmp):
    """Draws the caption bars and the end card with the system font (captions.swift)."""
    import json
    spec = os.path.join(tmp, "captions.json")
    with open(spec, "w") as f:
        json.dump({"captions": [c for _, _, c, _ in SHOTS], "endTitle": END_TITLE, "endSub": END_SUB}, f)
    subprocess.run(["swift", os.path.join(HERE, "captions.swift"), tmp, spec], check=True)


def main():
    tmp = tempfile.mkdtemp(prefix="mcl-preview-")
    captions(tmp)
    inputs, filters, labels = [], [], []
    for i, (still, secs, _caption, (fx, fy)) in enumerate(SHOTS):
        frames = int(secs * FPS)
        inputs += ["-loop", "1", "-t", str(secs), "-i", os.path.join(HERE, "stills", still)]
        labels.append((f"v{i}", secs))
    n = len(SHOTS)
    for i in range(n):
        inputs += ["-loop", "1", "-t", str(SHOTS[i][1]), "-i", os.path.join(tmp, f"caption{i:02d}.png")]
    inputs += ["-loop", "1", "-t", str(END_SECONDS), "-i", os.path.join(tmp, "end.png")]
    for i, (_still, secs, _caption, (fx, fy)) in enumerate(SHOTS):
        frames = int(secs * FPS)
        # Slow zoom from 1.0 to 1.06 toward the shot's focus, then the caption bar on top.
        filters.append(
            f"[{i}:v]scale={W*2}:{H*2},"
            f"zoompan=z='1+0.06*on/{frames}':d=1:s={W}x{H}:fps={FPS}:"
            f"x='({fx}*iw)-({fx}*iw/zoom)':y='({fy}*ih)-({fy}*ih/zoom)',setsar=1[z{i}];"
            f"[z{i}][{n + i}:v]overlay=0:0:format=auto,format=yuv420p,setsar=1[v{i}]")
    filters.append(f"[{2 * n}:v]fps={FPS},format=yuv420p,setsar=1[v{n}]")
    labels.append((f"v{n}", END_SECONDS))

    # Chain crossfades; each offset is the running length minus the fade.
    current, length = labels[0]
    for n, (label, secs) in enumerate(labels[1:], start=1):
        out = f"x{n}"
        offset = length - FADE
        filters.append(f"[{current}][{label}]xfade=transition=fade:duration={FADE}:offset={offset:.3f}[{out}]")
        current, length = out, offset + secs

    audio = 2 * n + 1
    inputs += ["-f", "lavfi", "-t", f"{length:.3f}", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100"]
    out_path = os.path.join(HERE, "preview.mp4")
    cmd = ["ffmpeg", "-y", "-loglevel", "error", *inputs,
           "-filter_complex", ";".join(filters),
           "-map", f"[{current}]", "-map", f"{audio}:a",
           "-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p", "-r", str(FPS), "-b:v", "12M",
           "-c:a", "aac", "-b:a", "128k", "-shortest", "-movflags", "+faststart", out_path]
    subprocess.run(cmd, check=True)
    print(f"wrote {out_path} ({length:.1f} s, {W}x{H}, {FPS} fps)")


if __name__ == "__main__":
    main()
