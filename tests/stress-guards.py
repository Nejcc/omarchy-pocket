"""Check the live stress test's guards without touching the desktop."""
import os
from pathlib import Path
import subprocess
import tempfile

script = Path(__file__).with_name('stress.sh')
with tempfile.TemporaryDirectory(prefix='pocket-guards-') as tmp:
    fake = Path(tmp) / 'hyprctl'
    fake.write_text('''#!/bin/sh
case "$1:$2" in
  repl:'return type(pocket)') echo table ;;
  repl:'return #pocket.windows()') echo "$TEST_POCKET_COUNT" ;;
  clients:-j) printf '%s\\n' "$TEST_CLIENTS" ;;
  *) echo 'Unexpected mutation' >&2; exit 99 ;;
esac
''')
    fake.chmod(0o755)
    for count, clients, expected in [
        ('1', '[]', 'current pocket'),
        ('0', '[{"workspace":{"id":8}}]', 'must be empty'),
        ('0', '[{"workspace":{"id":9}}]', 'must be empty'),
        ('0', 'broken', 'must be empty'),
    ]:
        env = dict(os.environ, PATH=tmp + ':/usr/bin:/bin',
                   TEST_POCKET_COUNT=count, TEST_CLIENTS=clients)
        result = subprocess.run(['bash', str(script)], env=env,
                                capture_output=True, text=True, timeout=3)
        assert result.returncode == 0 and expected in result.stdout, result
        assert 'Unexpected mutation' not in result.stderr, result
print('Pocket: four stress-test guard checks passed.')
