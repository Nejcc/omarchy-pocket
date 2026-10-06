"""Offline checks: python tests/check.py (requires Lua, luac, bash, and jq)."""
import json
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / 'manifest.json').read_text())
assert manifest['schemaVersion'] == 1
assert manifest['id'] == 'nejcc.pocket'
assert re.fullmatch(r'\d+\.\d+\.\d+', manifest['version'])
assert manifest['kinds'] == ['service']
assert set(manifest['entryPoints']) == {'service'}
assert (root / manifest['entryPoints']['service']).is_file()
for command in [
    ['luac', '-p', 'pocket.lua'],
    ['luac', '-p', 'tests/pocket.test.lua'],
    ['bash', '-n', 'tests/stress.sh'],
    ['lua', 'tests/pocket.test.lua'],
    [sys.executable, 'tests/stress-guards.py'],
]:
    subprocess.run(command, cwd=root, check=True)
print('All offline Pocket checks passed.')
