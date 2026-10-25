#!/usr/bin/env python3
"""Build the standalone release executable using only the Python standard library."""

from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[1]
    source = (root / "src" / "certKeys").read_text()
    library = (root / "src" / "LScriptLibV1.sh").read_text()
    include = 'source "$(dirname "${BASH_SOURCE[0]}")/LScriptLibV1.sh"'
    if source.count(include) != 1:
        raise SystemExit("Expected exactly one LScriptLibV1.sh include in certKeys")
    bundled = source.replace(
        include,
        "# Begin embedded LScriptLibV1.sh\n"
        + library.rstrip("\n")
        + "\n# End embedded LScriptLibV1.sh",
    )
    output = root / "release" / "certKeys"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(bundled)
    output.chmod(0o755)
    print(f"Built {output}")


if __name__ == "__main__":
    main()
