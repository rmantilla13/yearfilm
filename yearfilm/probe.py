"""What a file is: length, shape, sound, and the day it was filmed."""
import datetime as dt
import json
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

VIDEO_EXT = {".mp4", ".mov", ".m4v", ".mkv"}
AUDIO_EXT = {".m4a", ".mp3", ".wav", ".aac", ".ogg", ".flac"}
DATE_IN_NAME = re.compile(r"(\d{4})-?(\d{2})-?(\d{2})")


@dataclass
class Clip:
    path: str
    duration: float
    width: int
    height: int
    has_audio: bool
    date: dt.date

    @property
    def portrait(self) -> bool:
        return self.height > self.width


def ffprobe(path) -> dict:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", str(path)],
        capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(out)


def duration(path) -> float:
    return float(ffprobe(path)["format"]["duration"])


def capture_date(info: dict, path) -> dt.date:
    # Apple's creationdate carries the local offset, so its first ten characters are
    # the day it was where it was filmed; creation_time is UTC and can be a day off.
    tags = info.get("format", {}).get("tags", {})
    for key in ("com.apple.quicktime.creationdate", "creation_time"):
        value = tags.get(key)
        if value:
            try:
                return dt.date.fromisoformat(value[:10])
            except ValueError:
                pass
    m = DATE_IN_NAME.search(Path(path).name)
    if m:
        try:
            return dt.date(*map(int, m.groups()))
        except ValueError:
            pass
    return dt.date.fromtimestamp(Path(path).stat().st_mtime)


def _rotation(stream: dict) -> int:
    for side in stream.get("side_data_list", []):
        if "rotation" in side:
            return int(side["rotation"])
    return int(stream.get("tags", {}).get("rotate", 0))


def probe_clip(path) -> Clip:
    info = ffprobe(path)
    video = next(s for s in info["streams"] if s["codec_type"] == "video")
    w, h = int(video["width"]), int(video["height"])
    # Phones store portrait video as landscape pixels plus a rotation flag;
    # ffmpeg applies it on decode, so the shape we cut with is the rotated one.
    if abs(_rotation(video)) % 180 == 90:
        w, h = h, w
    return Clip(
        path=str(path),
        duration=float(info["format"]["duration"]),
        width=w,
        height=h,
        has_audio=any(s["codec_type"] == "audio" for s in info["streams"]),
        date=capture_date(info, path),
    )


def note_date(path) -> dt.date:
    return capture_date(ffprobe(path), path)


def files(folder: Path, exts: set) -> list:
    if not folder.is_dir():
        return []
    return sorted(p for p in folder.iterdir() if p.suffix.lower() in exts and not p.name.startswith("."))
