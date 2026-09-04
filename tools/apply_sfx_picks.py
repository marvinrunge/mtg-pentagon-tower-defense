"""Chooses which generated take each sound event actually uses.

Every event in tools/sfx_prompts.json has several takes under
assets/soundeffects/generated/<event>/. Exactly one of them is wired into
SoundBank.EVENT_FILES, and this script is what writes that line - so switching a take is
never a hand edit, and the file can never drift from what is on disk.

    python tools/apply_sfx_picks.py --random
        Picks one take per event at random. What runs first, so the game is playable and
        audible before anyone has listened to anything.

    python tools/apply_sfx_picks.py spell_fog=2 boss_spawn=3
        Applies specific choices, leaving every other event alone.

    python tools/apply_sfx_picks.py --picks picks.txt
        The same, one `event=take` per line - the format the audition page copies out.

It rewrites only the lines between the BEGIN/END GENERATED PICKS markers in
scripts/sound_bank.gd, so nothing else in that file can be touched by accident.
"""

import glob
import io
import os
import random
import re
import sys

BANK = os.path.join("scripts", "sound_bank.gd")
OUT_ROOT = os.path.join("assets", "soundeffects", "generated")
BEGIN = "# BEGIN GENERATED PICKS"
END = "# END GENERATED PICKS"


def available_takes(event):
    """Take numbers on disk for `event`, ascending. Reads the filesystem rather than the
    prompt file's `variants`, because a failed generation leaves a gap and picking a take
    that does not exist would be a silent missing sound."""
    takes = []
    for path in glob.glob(os.path.join(OUT_ROOT, event, "%s_*.mp3" % event)):
        match = re.search(r"_(\d+)\.mp3$", os.path.basename(path))
        if match:
            takes.append(int(match.group(1)))
    return sorted(takes)


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 1

    picks = {}
    randomise = False
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--random":
            randomise = True
        elif arg == "--picks":
            index += 1
            with io.open(args[index], encoding="utf-8") as handle:
                for line in handle:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    event, take = line.split("=", 1)
                    picks[event.strip()] = int(take.strip())
        elif "=" in arg:
            event, take = arg.split("=", 1)
            picks[event.strip()] = int(take.strip())
        else:
            print("Unrecognised argument: %s" % arg)
            return 1
        index += 1

    with io.open(BANK, encoding="utf-8") as handle:
        source = handle.read()
    if BEGIN not in source or END not in source:
        print("Markers missing from %s - has the block been reformatted?" % BANK)
        return 1

    head, rest = source.split(BEGIN, 1)
    block, tail = rest.split(END, 1)

    changed = []
    lines = block.split("\n")
    for position, line in enumerate(lines):
        match = re.match(r'(\s*)&"([a-z_0-9]+)": \["generated/\2/\2_(\d+)\.mp3"\],\s*$', line)
        if not match:
            continue
        indent, event, current = match.group(1), match.group(2), int(match.group(3))
        takes = available_takes(event)
        if not takes:
            print("  !! %s has no takes on disk - leaving it pointing at %d" % (event, current))
            continue

        if event in picks:
            wanted = picks[event]
            if wanted not in takes:
                print("  !! %s take %d does not exist (have %s) - unchanged" % (event, wanted, takes))
                continue
        elif randomise:
            wanted = random.choice(takes)
        else:
            continue

        if wanted != current:
            changed.append("%s: %d -> %d" % (event, current, wanted))
        lines[position] = '%s&"%s": ["generated/%s/%s_%d.mp3"],' % (indent, event, event, event, wanted)

    with io.open(BANK, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(head + BEGIN + "\n".join(lines) + END + tail)

    if changed:
        print("Updated %d:" % len(changed))
        for entry in changed:
            print("  " + entry)
    else:
        print("Nothing changed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
