#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
# Build dependency only: the resulting helper includes its own Python interpreter.
venv="$project_dir/.build/collector-venv"
if [[ ! -x "$venv/bin/python" ]]; then
    build_python="${BUBBLE_TAX_BUILD_PYTHON:-/usr/local/bin/python3}"
    if ! "$build_python" -c 'import sys; assert sys.version_info[:2] == (3, 12)' >/dev/null 2>&1; then
        echo "Building the bundled collector requires python.org Python 3.12 (or set BUBBLE_TAX_BUILD_PYTHON). End users do not need Python." >&2
        exit 1
    fi
    "$build_python" -m venv "$venv"
fi
if ! "$venv/bin/python" -c 'import PyInstaller; assert PyInstaller.__version__ == "6.17.0"' >/dev/null 2>&1; then
    "$venv/bin/python" -m pip install -r "$project_dir/scripts/collector-requirements.txt"
fi
"$venv/bin/python" -m PyInstaller --noconfirm --clean --onedir --windowed --osx-bundle-identifier app.bubbletaxbar.collector --target-arch arm64 \
    --name BubbleTaxCollector --distpath "$project_dir/dist/collector" \
    --workpath "$project_dir/.build/collector-freeze" --specpath "$project_dir/.build" \
    "$project_dir/Sources/BubbleTaxBar/Resources/collector_entry.py"
"$venv/bin/python" - <<'PY'
from importlib.metadata import distribution
from pathlib import Path
import sys
result = ['Bubble Tax local collector: Python 3.12 / PyInstaller 6.17.0.\n'
          'PyInstaller bootloader exception permits distribution under the app license.\n'
          'https://pyinstaller.org/en/stable/license.html\n']
for name in ['pyinstaller', 'altgraph', 'macholib']:
    d = distribution(name)
    for entry in d.files or []:
        if entry.name.lower().startswith(('license', 'copying')):
            result.append('\n'+name+' / '+str(entry)+'\n'+d.locate_file(entry).read_text())
license_path = Path(sys.base_prefix) / 'lib/python3.12/LICENSE.txt'
if not license_path.is_file():
    raise SystemExit('Python license not found; do not distribute without it')
result.append('\nPython license\n'+license_path.read_text())
third_party = Path(sys.base_prefix) / 'Resources/English.lproj/Documentation/_sources/license.rst.txt'
if not third_party.is_file():
    raise SystemExit('Python third-party notices not found')
result.append('\nPython and bundled library notices\n'+third_party.read_text())
Path('dist/collector-licenses.txt').write_text('\n'.join(result))
PY
