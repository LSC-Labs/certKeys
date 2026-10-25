#!/usr/bin/env python3
"""Build the standalone release executable using only the Python standard library."""

from pathlib import Path
import re
import shutil


def main():
    root = Path(__file__).resolve().parents[1]
    source = (root / "src" / "certKeys").read_text()
    library = (root / "src" / "LScriptLibV1.sh").read_text()
    windows_source = root / "src" / "certKeys.ps1"
    bash_version = re.search(r'^Prog_Version=(.+)$', source, re.MULTILINE).group(1)
    windows_version = re.search(r"^\$Prog_Version = '([^']+)'$", windows_source.read_text(), re.MULTILINE).group(1)
    if bash_version != windows_version:
        raise SystemExit("Bash and PowerShell versions must match")
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
    shutil.copyfile(windows_source, output.parent / "certKeys.ps1")
    launcher = (root / "src" / "certKeys.bat").read_text()
    (output.parent / "certKeys.bat").write_bytes(launcher.replace("\n", "\r\n").encode("ascii"))
    print(f"Built {output}")
    print(f"Built {output.parent / 'certKeys.ps1'}")
    print(f"Built {output.parent / 'certKeys.bat'}")


if __name__ == "__main__":
    main()
