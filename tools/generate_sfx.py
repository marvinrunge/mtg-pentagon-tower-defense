"""Generates the game's missing sound effects through ElevenLabs.

Reads tools/sfx_prompts.json and writes N takes per event to
assets/soundeffects/generated/<event>/<event>_<n>.mp3.

RESUMABLE ON PURPOSE. Every take costs credits, so a file that already exists is never
regenerated - rerunning after an interrupted run, or after adding one new event to the
JSON, only pays for what is actually missing. Delete a file (or a whole event folder) to
buy a fresh take of exactly that.

Usage, from the repo root:

    $env:ELEVENLABS_API_KEY = [Environment]::GetEnvironmentVariable('ElevenLabsApiKey','User')
    python tools/generate_sfx.py            # everything still missing
    python tools/generate_sfx.py spell_fog  # only these events

The key is passed in the environment rather than read from a file, so it never lands in
the repo and never appears in a command line that a shell would record in its history.
"""

import io
import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = "https://api.elevenlabs.io/v1/sound-generation"
PROMPTS = os.path.join("tools", "sfx_prompts.json")
OUT_ROOT = os.path.join("assets", "soundeffects", "generated")

# ElevenLabs rate-limits bursts. One second between calls is enough to stay under it and
# costs nothing worth optimising for a run of sixty.
DELAY_SECONDS = 1.0


def generate(api_key, text, duration, influence):
    body = json.dumps({
        "text": text,
        "duration_seconds": duration,
        "prompt_influence": influence,
    }).encode("utf-8")
    request = urllib.request.Request(
        API_URL,
        data=body,
        headers={"xi-api-key": api_key, "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        return response.read()


def main():
    api_key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not api_key:
        print("ELEVENLABS_API_KEY is not set - see the module docstring.")
        return 1

    with io.open(PROMPTS, encoding="utf-8") as handle:
        config = json.load(handle)
    defaults = config["defaults"]
    events = config["events"]

    wanted = sys.argv[1:]
    if wanted:
        missing = [name for name in wanted if name not in events]
        if missing:
            print("No such event(s): %s" % ", ".join(missing))
            return 1
        events = {name: events[name] for name in wanted}

    made = 0
    skipped = 0
    failed = []

    for name in sorted(events):
        spec = events[name]
        variants = int(spec.get("variants", defaults["variants"]))
        influence = float(spec.get("prompt_influence", defaults["prompt_influence"]))
        duration = float(spec["duration_seconds"])
        folder = os.path.join(OUT_ROOT, name)
        if not os.path.isdir(folder):
            os.makedirs(folder)

        for index in range(1, variants + 1):
            path = os.path.join(folder, "%s_%d.mp3" % (name, index))
            if os.path.exists(path) and os.path.getsize(path) > 0:
                skipped += 1
                continue
            try:
                audio = generate(api_key, spec["prompt"], duration, influence)
            except urllib.error.HTTPError as error:
                detail = error.read().decode("utf-8", "replace")[:200]
                print("  FAIL %s take %d: HTTP %s %s" % (name, index, error.code, detail))
                failed.append(path)
                continue
            except Exception as error:  # noqa: BLE001 - a run of sixty should not die on one
                print("  FAIL %s take %d: %s" % (name, index, error))
                failed.append(path)
                continue

            # A JSON error body would be a few hundred bytes and is NOT audio. Writing it
            # to a .mp3 would leave a file that exists, so the resume logic would skip it
            # forever and the event would be silently missing a take.
            if len(audio) < 2000:
                print("  FAIL %s take %d: %d bytes, not audio" % (name, index, len(audio)))
                failed.append(path)
                continue

            with open(path, "wb") as handle:
                handle.write(audio)
            made += 1
            print("  ok   %s take %d  (%.1f KB)" % (name, index, len(audio) / 1024.0))
            time.sleep(DELAY_SECONDS)

    print("\ngenerated %d, already had %d, failed %d" % (made, skipped, len(failed)))
    for path in failed:
        print("  missing: %s" % path)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
