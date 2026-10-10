#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
bash "$project_dir/scripts/build-app.sh"
open "$project_dir/dist/Bubble Tax.app"
