#!/usr/bin/env bash
set -euo pipefail

readonly project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly expected_asset_sha="7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35"
readonly expected_oracle_sha="778a46c266d66dcc16c484cd6931505059d86ba7ed9f9e43f540c869a8a7406c"

asset=""
oracle=""
while (($#)); do
  case "$1" in
    --asset) asset="$2"; shift 2 ;;
    --oracle) oracle="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -f "$asset" && -f "$oracle" ]] || {
  echo "usage: run_exact_headless_gate.sh --asset FILE --oracle FILE" >&2
  exit 2
}
[[ "$(shasum -a 256 "$asset" | awk '{print $1}')" == "$expected_asset_sha" ]] || {
  echo "asset SHA-256 mismatch" >&2
  exit 1
}
[[ "$(shasum -a 256 "$oracle" | awk '{print $1}')" == "$expected_oracle_sha" ]] || {
  echo "oracle SHA-256 mismatch" >&2
  exit 1
}

mkdir -p "$project_dir/build/tools"
readonly public_binary="$project_dir/build/tools/test_goblin_headless"
readonly oracle_binary="$project_dir/build/tools/verify_exact_keyed_runtime"
nim c --hints:off --mm:orc --out:"$public_binary" \
  "$project_dir/tests/integration/test_goblin_headless.nim"
nim c --hints:off --mm:orc --out:"$oracle_binary" \
  "$project_dir/tools/verify_exact_keyed_runtime.nim"
"$public_binary" --asset:"$asset" --require-private-fixture
"$oracle_binary" "$asset" "$oracle"
echo "exact goblin headless readiness gate passed"
