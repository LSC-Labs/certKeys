"""Run on Windows: verify CMD argument forwarding, paths and exit codes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

launcher = (Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / 'src/certKeys.bat').resolve()
if os.name != 'nt':
    raise SystemExit('This test requires Windows cmd.exe and Windows PowerShell.')


def run(batch, arguments=''):
    # /s /c requires an outer quote pair around a quoted executable plus arguments.
    command = f'"{os.environ["COMSPEC"]}" /d /s /c ""{batch}" {arguments}"'
    return subprocess.run(command,
                          text=True, capture_output=True, timeout=30)


result = run(launcher, 'help')
assert result.returncode == 0 and 'createKeys' in result.stdout, (result.stdout, result.stderr)
with tempfile.TemporaryDirectory(prefix='certKeys CMD test ') as temp:
    root = Path(temp) / 'folder with spaces & symbols'
    root.mkdir()
    batch = root / 'certKeys.bat'
    shutil.copyfile(launcher, batch)
    missing = run(batch, 'help')
    assert missing.returncode == 1 and 'certKeys.ps1' in missing.stderr
    script = root / 'certKeys.ps1'
    script.write_text("if ($args.Count -gt 0 -and $args[0] -eq 'fail') { exit 37 }\n"
                      "ConvertTo-Json -InputObject @($args) -Compress\n", encoding='utf-8')
    result = run(batch, 'getPublicSSHKey -target "C:\\export folder\\key.pub" -context "A & B!"')
    assert result.returncode == 0, (result.stdout, result.stderr)
    assert json.loads(result.stdout) == ['getPublicSSHKey', '-target',
                                         'C:\\export folder\\key.pub', '-context', 'A & B!']
    assert run(batch).returncode == 0
    assert run(batch, 'fail').returncode == 37
print('PASS: CMD launcher, missing script, spaces, argument forwarding and exit codes.')
