# record-audio.sh

Quickly record audio on a PulseAudio/PipeWire system: system playback (what you
hear), the microphone, or both mixed into a single file.

Script lives at `~/bin/record-audio.sh` (on `PATH`). Output is a timestamped WAV
in `$HOME`. Stop any recording with **Ctrl-C**.

## Usage

```bash
record-audio.sh             # record system playback (default output monitor)
record-audio.sh -m          # record the microphone (default input) instead
record-audio.sh -b          # record BOTH mic + playback, mixed (needs ffmpeg)
record-audio.sh -d DEVICE   # record from an explicit PulseAudio source
record-audio.sh -o FILE     # write to FILE instead of ~/recording-<timestamp>.wav
record-audio.sh -l          # list available sources and exit
record-audio.sh -h          # help
```

## Notes

- The device is auto-detected from the current default sink/source, so it follows
  whichever card is active (e.g. USB headset vs. built-in) without editing.
- Playback is captured via the sink's `.monitor` source.
- `-b` (both) uses `ffmpeg`'s `amix` filter with `normalize=0`, keeping both
  streams at full volume so the mic stays audible over system audio. If the mix
  clips/distorts, drop `normalize=0` to balance the levels down instead.

## Requirements

- `parecord`, `pactl` (PulseAudio utils) — playback/mic modes
- `ffmpeg` — only for `-b` (both) mode
