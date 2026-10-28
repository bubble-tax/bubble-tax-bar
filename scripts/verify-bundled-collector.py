"""Relocate the packaged helper and test it without an external Python or user state."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

source = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='bubble-tax-no-python-') as temporary:
    root = Path(temporary)
    relocated = root / 'Relocated app with spaces' / 'BubbleTaxCollector.app'
    shutil.copytree(source, relocated, symlinks=True)
    binary = relocated / 'Contents/MacOS/BubbleTaxCollector'
    home = root / 'isolated home'
    home.mkdir()
    env = {'HOME': str(home), 'PATH': '/usr/bin:/bin', 'LANG': 'en_US.UTF-8',
           'PYTHONHOME': '/nonexistent-python', 'PYTHONPATH': '/nonexistent-modules'}
    def run(args, raw=None):
        return subprocess.run([str(binary), *args], input=raw, env=env, cwd=root,
                              capture_output=True, check=True, timeout=15).stdout
    logs = root / 'logs'; logs.mkdir()
    (logs / 'session.jsonl').write_text(json.dumps({
        'type': 'assistant', 'timestamp': '2026-10-01T16:00:00Z',
        'message': {'id': 'fixture', 'content': [{'text': 'PRIVATE PROMPT'}],
                    'usage': {'input_tokens': 10, 'output_tokens': 5}}})+'\n')
    snapshot = json.loads(run(['collect', '--claude-folder', str(logs), '--timezone', 'Asia/Seoul']))
    assert snapshot['days'] == [{'provider': 'claude', 'day': '2026-10-02', 'tokens': 15, 'requests': 1}], snapshot
    assert 'PRIVATE PROMPT' not in json.dumps(snapshot)
    # Own the quota display without executing the previous command; restore it on remove.
    settings = home / '.claude/settings.json'; settings.parent.mkdir()
    marker = root / 'previous-command-ran'
    previous = 'printf original; touch ' + shlex.quote(str(marker))
    original = {'theme': 'dark', 'statusLine': {'type': 'command', 'command': previous, 'padding': 2}}
    settings.write_text(json.dumps(original))
    assert json.loads(run(['statusline', 'install']))['enabled']
    assert json.loads(run(['statusline', 'status']))['enabled']
    assert json.loads(run(['statusline', 'install']))['enabled']
    command = json.loads(settings.read_text())['statusLine']['command']
    assert shlex.split(command) == [str(binary.resolve()), 'statusline', 'capture']
    payload = json.dumps({'prompt': 'PRIVATE', 'rate_limits': {'five_hour': {'used_percentage': 25, 'resets_at': time.time()+1000}}}).encode()
    output = subprocess.run(command, shell=True, input=payload, env=env, capture_output=True, check=True, timeout=15).stdout
    assert output == b'5h 75% left\n', output
    assert not marker.exists(), 'Previous statusline must never be executed'
    cache = home / 'Library/Application Support/BubbleTaxBar/claude-statusline/quota.json'
    assert json.loads(cache.read_text())['windows'][0]['usedPercent'] == 25
    assert 'PRIVATE' not in cache.read_text()
    assert not json.loads(run(['statusline', 'remove']))['enabled']
    assert json.loads(settings.read_text()) == original
    assert not cache.exists()
    # A user replacement must remain intact.
    run(['statusline', 'install'])
    changed = dict(original, statusLine={'type': 'command', 'command': 'printf replacement'})
    settings.write_text(json.dumps(changed))
    run(['statusline', 'remove'])
    assert json.loads(settings.read_text()) == changed
print('PASS: relocated packaged collector, timezone parsing, private data filtering, bridge capture/restoration and user edits; no external Python.')
