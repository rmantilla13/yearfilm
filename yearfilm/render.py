"""Follow a timeline with ffmpeg. Every segment is rendered to the same format, then joined.

Every segment comes out 1920x1080, 30 fps, yuv420p, 48 kHz stereo AAC, and its
audio is exactly as long as its picture - that is what lets the final join be a
stream copy without the sound drifting off the picture over thirty minutes.
"""
import shutil
import subprocess
import tempfile
from pathlib import Path

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"
W, H, FPS = 1920, 1080, 30
AUDIO = "aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo"
ENCODE = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p", "-r", str(FPS),
          "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2"]


def fit(label_in: str, label_out: str, dur: float) -> str:
    """Any shape into 16:9. Portrait phone video sits over a blurred fill of itself
    rather than black bars, because a TV with two black thirds looks broken."""
    return (
        f"[{label_in}]setpts=PTS-STARTPTS,split[{label_out}a][{label_out}b];"
        f"[{label_out}a]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},"
        f"boxblur=24:2,eq=brightness=-0.08[{label_out}bg];"
        f"[{label_out}b]scale={W}:{H}:force_original_aspect_ratio=decrease[{label_out}fg];"
        f"[{label_out}bg][{label_out}fg]overlay=(W-w)/2:(H-h)/2,setsar=1,fps={FPS},format=yuv420p,"
        # A clip shorter than its slot holds its last frame rather than ending the segment early.
        f"tpad=stop_mode=clone:stop_duration=2,trim=duration={dur},setpts=PTS-STARTPTS[{label_out}]"
    )


def card(tmp: Path, n: int, title: str, subtitle: str, dur: float, out: str) -> str:
    tfile, sfile = tmp / f"card{n}t.txt", tmp / f"card{n}s.txt"
    tfile.write_text(title)
    sfile.write_text(subtitle or " ")
    lines = max(1, subtitle.count("\n") + 1)
    fade = min(0.6, dur / 4)
    return (
        f"color=c=0x0b0b0c:s={W}x{H}:r={FPS}:d={dur},"
        f"drawtext=fontfile={FONT}:textfile={tfile}:fontcolor=white:fontsize=104:"
        f"x=(w-text_w)/2:y=(h-text_h)/2-{60 + 28 * (lines - 1)},"
        f"drawtext=fontfile={FONT}:textfile={sfile}:fontcolor=0xc8c2b8:fontsize=44:line_spacing=14:"
        f"text_align=C:x=(w-text_w)/2:y=h/2+40-{28 * (lines - 1)},"
        f"fade=in:st=0:d={fade},fade=out:st={dur - fade}:d={fade},format=yuv420p[{out}]"
    )


def render_montage(seg: dict, out: Path, tmp: Path) -> None:
    args, graph, vlabels = [], [], []
    n_in = 0
    for i, item in enumerate(seg["items"]):
        if "card" in item:
            graph.append(card(tmp, i, item["card"]["title"], item["card"]["subtitle"], item["dur"], f"v{i}"))
        else:
            args += ["-ss", str(item["in"]), "-t", str(item["dur"] + 0.5), "-i", item["src"]]
            graph.append(fit(f"{n_in}:v", f"v{i}", item["dur"]))
            n_in += 1
        vlabels.append(f"[v{i}]")
    total = seg["music"]["duration"]
    graph.append(f"{''.join(vlabels)}concat=n={len(vlabels)}:v=1:a=0[vout]")

    music = seg["music"]
    args += ["-ss", str(music["start"]), "-t", str(total), "-i", music["path"]]
    m = n_in
    fade_out = min(1.5, total / 3)
    graph.append(f"[{m}:a]{AUDIO},afade=in:d=0.05,afade=out:st={total - fade_out}:d={fade_out},volume=0.9[music]")

    if seg["narration"]:
        labels = []
        for j, nar in enumerate(seg["narration"]):
            args += ["-i", nar["path"]]
            ms = int(nar["at"] * 1000)
            graph.append(f"[{m + 1 + j}:a]{AUDIO},adelay=delays={ms}:all=1,volume=1.4[n{j}]")
            labels.append(f"[n{j}]")
        graph.append(f"{''.join(labels)}amix=inputs={len(labels)}:normalize=0,apad,atrim=duration={total},"
                     f"asplit[voice][key]")
        # The music steps back whenever someone speaks, and comes up between sentences.
        graph.append("[music][key]sidechaincompress=threshold=0.015:ratio=10:attack=30:release=500[ducked]")
        graph.append("[ducked][voice]amix=inputs=2:duration=first:normalize=0[amix]")
    else:
        graph.append("[music]anull[amix]")
    graph.append(f"[amix]apad,atrim=duration={total}[aout]")
    run(args, graph, out, total)


def render_scene(seg: dict, out: Path, tmp: Path) -> None:
    dur = seg["dur"]
    args = ["-ss", str(seg["in"]), "-t", str(dur + 0.5), "-i", seg["src"]]
    graph = [fit("0:v", "vout", dur)]
    if seg.get("has_audio"):
        # Short fades so a hard cut into someone mid-sentence does not click.
        graph.append(f"[0:a]{AUDIO},afade=in:d=0.12,afade=out:st={dur - 0.2}:d=0.2,apad,atrim=duration={dur}[aout]")
    else:
        args += ["-f", "lavfi", "-t", str(dur), "-i", "anullsrc=r=48000:cl=stereo"]
        graph.append(f"[1:a]{AUDIO}[aout]")
    run(args, graph, out, dur)


def run(args: list, graph: list, out: Path, dur: float) -> None:
    cmd = ["ffmpeg", "-y", "-v", "error", *args, "-filter_complex", ";".join(graph),
           "-map", "[vout]", "-map", "[aout]", "-t", str(dur), *ENCODE, str(out)]
    subprocess.run(cmd, check=True)


def render(timeline: dict, out: str, keep: bool = False, log=print) -> None:
    tmp = Path(tempfile.mkdtemp(prefix="yearfilm-"))
    parts = []
    try:
        for i, seg in enumerate(timeline["segments"]):
            if seg["kind"] == "montage" and not seg["items"]:
                continue
            part = tmp / f"seg{i:03d}.mp4"
            log(f"  [{i + 1}/{len(timeline['segments'])}] {seg['label']}")
            (render_montage if seg["kind"] == "montage" else render_scene)(seg, part, tmp)
            parts.append(part)
        listing = tmp / "parts.txt"
        listing.write_text("".join(f"file '{p}'\n" for p in parts))
        joined = tmp / "joined.mp4"
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(listing),
                        "-c", "copy", str(joined)], check=True)
        # One loudness pass over the whole film: a TV should not need the remote between scenes.
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(joined), "-c:v", "copy",
                        "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
                        "-movflags", "+faststart", str(out)], check=True)
    finally:
        if keep:
            log(f"  segments kept in {tmp}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)
