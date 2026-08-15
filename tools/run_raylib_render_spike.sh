#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_ASSET_SHA="7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35"
readonly EXPECTED_RUNTIME_SHA="372b8092e940f32cf84499ae23a4899ec66a9ab1"
readonly EXPECTED_NAYLIB_DIR="naylib-26.08.0-19dd4e7e34c705c677e89b3a6516846c9f2e0125"

oracle_path=""
reference_dir=""
output_dir=""
while (($#)); do
  case "$1" in
    --oracle) oracle_path="$2"; shift 2 ;;
    --reference-dir) reference_dir="$2"; shift 2 ;;
    --output-dir) output_dir="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$oracle_path" || -z "$reference_dir" || -z "$output_dir" ]]; then
  echo "usage: $0 --oracle FILE --reference-dir DIR --output-dir DIR" >&2
  exit 2
fi

actual_asset_sha="$(jq -r .assetSha256 "$oracle_path")"
actual_runtime_sha="$(jq -r .officialRuntimeSha "$oracle_path")"
[[ "$actual_asset_sha" == "$EXPECTED_ASSET_SHA" ]] || {
  echo "oracle asset hash mismatch" >&2
  exit 2
}
[[ "$actual_runtime_sha" == "$EXPECTED_RUNTIME_SHA" ]] || {
  echo "oracle runtime hash mismatch" >&2
  exit 2
}

naylib_path="$(nimble path naylib)"
[[ "$(basename "$naylib_path")" == "$EXPECTED_NAYLIB_DIR" ]] || {
  echo "naylib revision mismatch: $naylib_path" >&2
  exit 2
}

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly project_dir
readonly binary="$project_dir/build/tools/raylib_render_spike"
readonly first_dir="$output_dir/first"
readonly second_dir="$output_dir/second"
mkdir -p "$first_dir" "$second_dir" "$(dirname "$binary")"

nim c --hints:off --mm:orc -d:useNaylib \
  --out:"$binary" "$project_dir/tools/raylib_render_spike.nim"

run_spike() {
  local run_dir="$1"
  # GLFW cannot enumerate a sleeping macOS display. Waking it is deterministic
  # and avoids hiding that the selected production adapter requires a context.
  caffeinate -u -t 5 &
  "$binary" \
    --oracle "$oracle_path" \
    --reference-dir "$reference_dir" \
    --output-dir "$run_dir"
}
run_spike "$first_dir"
run_spike "$second_dir"
cmp "$first_dir/metrics.json" "$second_dir/metrics.json"
cmp "$first_dir/raylib-render-spike.png" \
  "$second_dir/raylib-render-spike.png"

echo "metrics: $first_dir/metrics.json"
echo "capture: $first_dir/raylib-render-spike.png"
echo "reproducibility: byte-for-byte verified"
