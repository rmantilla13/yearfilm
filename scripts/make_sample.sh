#!/usr/bin/env bash
# Synthesises a stand-in year so the pipeline can be run end to end without real footage:
# clips across every season (some portrait, some with "talking"), voice notes, and
# three music cues at different tempos. Replace with real files to see a real film.
set -euo pipefail
OUT=${1:-sample}
mkdir -p "$OUT/clips" "$OUT/notes" "$OUT/music"
q() { ffmpeg -y -v error "$@"; }

# date | video source | size | sound (talk = speech-band bursts, quiet = room tone)
clips=(
  "2026-01-10 testsrc2 1920x1080 quiet"
  "2026-02-14 mandelbrot 1080x1920 talk"
  "2026-03-21 life=s=1920x1080:mold=10:r=30:ratio=0.1:death_color=#204060:life_color=#ffd080 1920x1080 quiet"
  "2026-04-05 smptehdbars 1920x1080 talk"
  "2026-05-30 testsrc2 1080x1920 quiet"
  "2026-06-21 mandelbrot 1920x1080 quiet"
  "2026-07-04 cellauto=rule=110:s=1920x1080 1920x1080 talk"
  "2026-08-15 testsrc2 1920x1080 quiet"
  "2026-09-02 life=s=1920x1080:mold=5:r=30:ratio=0.2:life_color=#80ffa0 1920x1080 quiet"
  "2026-10-31 mandelbrot 1080x1920 talk"
  "2026-11-26 testsrc2 1920x1080 talk"
  "2026-12-24 smptehdbars 1920x1080 quiet"
)
for row in "${clips[@]}"; do
  read -r date src size sound <<<"$row"
  case $src in
    life*|cellauto*) v="$src" ;;
    *) v="$src=s=$size:r=30" ;;
  esac
  if [ "$sound" = talk ]; then
    # Syllable-rate bursts of band-limited noise read as "someone is talking".
    a="anoisesrc=c=white:r=48000:a=0.3,highpass=f=300,lowpass=f=3000,volume='if(lt(mod(t,0.9),0.55),1,0.05)':eval=frame"
  else
    a="anoisesrc=c=brown:r=48000:a=0.02"
  fi
  q -f lavfi -t 14 -i "$v" -f lavfi -t 14 -i "$a" \
    -vf "scale=$size,hue=h=${date:5:2}*30,format=yuv420p" -c:v libx264 -preset ultrafast -c:a aac -shortest \
    -metadata creation_time="${date}T12:00:00Z" "$OUT/clips/$date.mp4"
done

# Voice notes, one per season.
for date in 2026-02-20 2026-04-12 2026-07-06 2026-10-01 2026-12-26; do
  q -f lavfi -t 5 -i "anoisesrc=c=white:r=48000:a=0.3,highpass=f=250,lowpass=f=2500,volume='if(lt(mod(t,0.7),0.45),1,0.03)':eval=frame" \
    -c:a aac "$OUT/notes/$date.m4a"
done

# Music: a kick on every beat, a softer accent on each bar, over a chord pad.
cue() {
  local name=$1 bpm=$2 root=$3 len=$4
  local b="60/$bpm"
  q -f lavfi -t "$len" -i "aevalsrc='0.9*sin(2*PI*55*t)*exp(-25*mod(t,$b)) + 0.25*sin(2*PI*2200*t)*exp(-60*mod(t,4*$b)) + 0.08*(sin(2*PI*$root*t)+sin(2*PI*$root*1.25*t)+sin(2*PI*$root*1.5*t))|0.9*sin(2*PI*55*t)*exp(-25*mod(t,$b)) + 0.08*(sin(2*PI*$root*t)+sin(2*PI*$root*1.26*t)+sin(2*PI*$root*1.5*t))':s=44100" \
    -c:a libmp3lame -q:a 4 "$OUT/music/$name.mp3"
}
cue "first-light" 96 220 70
cue "long-days" 120 261.6 70
cue "home-again" 84 196 70
echo "sample year written to $OUT/"
