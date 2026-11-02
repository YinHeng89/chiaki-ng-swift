import json
from pathlib import Path
import shlex
import subprocess
import sys


def analyze(arguments, **kwargs):
    result = subprocess.run(arguments, text=True, capture_output=True, **kwargs)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    if result.returncode or "warning:" in result.stderr or "error:" in result.stderr:
        raise SystemExit(result.returncode or 1)


project = Path(__file__).resolve().parents[2]
commands = json.loads((project / '.build/native-core/compile_commands.json').read_text())
checked = 0
seen = set()
for entry in commands:
    source = Path(entry['file']).resolve()
    if not source.is_relative_to(project / 'lib/bridge'):
        continue
    if source in seen:
        continue
    seen.add(source)
    arguments = entry.get('arguments') or shlex.split(entry['command'])
    filtered = []
    skip = False
    for argument in arguments:
        if skip:
            skip = False
            continue
        if argument in ('-o', '-MF', '-MT', '-MQ'):
            skip = True
            continue
        if argument in ('-c', '-MD', '-MMD'):
            continue
        filtered.append(argument)
    analyze(filtered + ['--analyze', '-Xanalyzer', '-analyzer-output=text', '-Werror'],
                   cwd=entry['directory'])
    checked += 1
expected = sum(
    1 for path in (project / 'lib/bridge').rglob('*') if path.suffix in ('.c', '.cpp', '.m', '.mm')
)
if checked != expected:
    raise RuntimeError(f'Expected {expected} bridge translation units, found {checked}')
print(f'PASS: Clang static analysis of {checked} bridge files')
