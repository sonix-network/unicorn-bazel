"""Write or check each module version's source.json overlay pins.

    python3 dev/tools/pin_sources.py          # rewrite source.json files
    python3 dev/tools/pin_sources.py --check  # fail if any pin is stale

The upstream archive URL, integrity and strip_prefix are kept as written;
only the "overlay" map is derived from the files under overlay/.
"""

import argparse
import base64
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]


def integrity(data):
    return "sha256-" + base64.b64encode(hashlib.sha256(data).digest()).decode()


def expected(version_dir):
    source = json.loads((version_dir / "source.json").read_text())
    overlay = version_dir / "overlay"
    source["overlay"] = {
        path.relative_to(overlay).as_posix(): integrity(path.read_bytes())
        for path in sorted(overlay.rglob("*"))
        if path.is_file()
    }
    return json.dumps(source, indent=4) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    stale = []
    for source in sorted(ROOT.glob("modules/*/*/source.json")):
        text = expected(source.parent)
        if source.read_text() != text:
            if args.check:
                stale.append(source.relative_to(ROOT))
            else:
                source.write_text(text)
                print(f"updated {source.relative_to(ROOT)}")
    if stale:
        print("stale overlay pins: " + ", ".join(map(str, stale)), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
