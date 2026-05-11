#!/bin/bash

# Theodore: extract and validate a reviewer json-verdict code block.

set -euo pipefail

INPUT_PATH=""

usage() {
  cat >&2 <<'EOF'
Usage:
  extract-verdict.sh --input <review-output.txt>

Prints the json-verdict object on stdout after basic validation.
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
match = re.search(r"```json-verdict\s*(\{.*?\})\s*```", text, re.S)
if not match:
    print("Error: missing json-verdict code block", file=sys.stderr)
    sys.exit(2)

try:
    verdict = json.loads(match.group(1))
except json.JSONDecodeError as exc:
    print(f"Error: invalid json-verdict: {exc}", file=sys.stderr)
    sys.exit(3)

if verdict.get("verdict") not in {"APPROVED", "CHANGES_REQUESTED"}:
    print("Error: verdict must be APPROVED or CHANGES_REQUESTED", file=sys.stderr)
    sys.exit(4)

findings = verdict.get("findings")
if not isinstance(findings, list) or not all(isinstance(item, str) for item in findings):
    print("Error: findings must be a list of strings", file=sys.stderr)
    sys.exit(5)

print(json.dumps(verdict, separators=(",", ":")))
PY
