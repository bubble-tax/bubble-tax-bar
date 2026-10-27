"""Entry point for the app's self-contained local collector."""
import json
from pathlib import Path
import sys
import collector
import claude_statusline


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("collect", "statusline"):
        raise ValueError("Unknown collector operation")
    mode = sys.argv.pop(1)
    if mode == "collect":
        collector.main()
    else:
        if len(sys.argv) != 2 or sys.argv[1] not in ("install", "remove", "status", "migrate", "capture"):
            raise ValueError("Unknown statusline operation")
        action = sys.argv[1]
        if action == "capture":
            claude_statusline.capture(Path.home(), sys.stdin.buffer.read(2 * 1024 * 1024))
        else:
            print(json.dumps({"enabled": claude_statusline.configure(action, Path.home(), executable=sys.executable)}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, AttributeError):
        print("Local collection could not complete. Check selected folders or Claude settings.", file=sys.stderr)
        sys.exit(1)
