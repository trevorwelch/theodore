#!/bin/bash

# Theodore: extract and validate a challenge-plan code block.

set -euo pipefail

INPUT_PATH=""

usage() {
  cat >&2 <<'EOF'
Usage:
  extract-challenge-plan.sh --input <selector-output.txt>

Prints a compact JSON object with strategy, reason, and max_probes.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$INPUT_PATH" ]]; then
  echo "Error: --input is required" >&2
  usage
  exit 1
fi

if [[ ! -f "$INPUT_PATH" ]]; then
  echo "Error: input file not found: $INPUT_PATH" >&2
  exit 1
fi

python3 - "$INPUT_PATH" <<'PY'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
match = re.search(r"```challenge-plan\s*(.*?)\s*```", text, re.S)
if not match:
    print("Error: missing challenge-plan code block", file=sys.stderr)
    sys.exit(2)

plan = {}
for raw_line in match.group(1).splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    if ":" not in line:
        print(f"Error: invalid challenge-plan line: {raw_line}", file=sys.stderr)
        sys.exit(3)
    key, value = line.split(":", 1)
    plan[key.strip()] = value.strip()

strategy = plan.get("strategy")
if strategy not in {"logic-mutation", "skip"}:
    print("Error: strategy must be logic-mutation or skip", file=sys.stderr)
    sys.exit(4)

reason = plan.get("reason", "")
if not reason:
    print("Error: reason is required", file=sys.stderr)
    sys.exit(5)

try:
    max_probes = int(plan.get("max_probes", "0"))
except ValueError:
    print("Error: max_probes must be numeric", file=sys.stderr)
    sys.exit(6)

if strategy == "logic-mutation" and max_probes <= 0:
    print("Error: logic-mutation requires max_probes > 0", file=sys.stderr)
    sys.exit(7)

if max_probes < 0:
    print("Error: max_probes cannot be negative", file=sys.stderr)
    sys.exit(8)

print(json.dumps(
    {"strategy": strategy, "reason": reason, "max_probes": max_probes},
    separators=(",", ":"),
))
PY
