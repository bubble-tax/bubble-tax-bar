"""Sign nested code inside-out; SIGNING_IDENTITY defaults to local ad-hoc signing."""
import os
from pathlib import Path
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
identity = os.environ.get("SIGNING_IDENTITY", "-")
options = ["--force", "--sign", identity]
if identity != "-":
    options += ["--options", "runtime", "--timestamp"]

def sign(path):
    subprocess.run(["/usr/bin/codesign", *options, str(path)], check=True)

# Sign each real Mach-O once; never traverse framework/resource symlinks.
for path in sorted(app.rglob("*")):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open("rb") as stream:
        magic = stream.read(4)
    if magic in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
        sign(path)

bundles = [path for path in app.rglob("*") if path.is_dir() and not path.is_symlink()
           and path.suffix in (".framework", ".app", ".bundle")]
for path in sorted(bundles, key=lambda item: len(item.parts), reverse=True):
    sign(path)
sign(app)
subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print("Verified Developer ID signature." if identity != "-" else "Verified ad-hoc signature.")
