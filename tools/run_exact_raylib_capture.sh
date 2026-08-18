#!/usr/bin/env bash
set -euo pipefail

readonly project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly expected_naylib_sha="a705b3fc7987785b6609780a0237e92f380705a357faee8a30af8b26275dc1ae"

asset=""
oracle=""
reference_dir=""
output_dir=""
naylib_dir=""
while (($#)); do
  case "$1" in
    --asset) asset="$2"; shift 2 ;;
    --oracle) oracle="$2"; shift 2 ;;
    --reference-dir) reference_dir="$2"; shift 2 ;;
    --output-dir) output_dir="$2"; shift 2 ;;
    --naylib-dir) naylib_dir="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -f "$asset" && -f "$oracle" && -d "$reference_dir" && -n "$output_dir" &&
    -d "$naylib_dir" ]] || {
  echo "usage: run_exact_raylib_capture.sh --asset FILE --oracle FILE --reference-dir DIR --output-dir DIR --naylib-dir DIR" >&2
  exit 2
}
actual_naylib_sha="$(cd "$naylib_dir" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}')"
[[ "$actual_naylib_sha" == "$expected_naylib_sha" ]] || {
  echo "naylib source hash mismatch" >&2
  exit 1
}

readonly expected_asset_sha="7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35"
readonly expected_oracle_sha="778a46c266d66dcc16c484cd6931505059d86ba7ed9f9e43f540c869a8a7406c"
[[ "$(shasum -a 256 "$asset" | awk '{print $1}')" == "$expected_asset_sha" ]] || {
  echo "asset SHA-256 mismatch" >&2
  exit 1
}
[[ "$(shasum -a 256 "$oracle" | awk '{print $1}')" == "$expected_oracle_sha" ]] || {
  echo "oracle SHA-256 mismatch" >&2
  exit 1
}
while IFS=$'\t' read -r expected_sha filename; do
  [[ "$(shasum -a 256 "$reference_dir/$filename" | awk '{print $1}')" == "$expected_sha" ]] || {
    echo "reference SHA-256 mismatch: $filename" >&2
    exit 1
  }
done < <(jq -r '.animations[].referenceFrames[0,2] | [.sha256, .filename] | @tsv' "$oracle")

rm -rf "$output_dir/first" "$output_dir/second"
mkdir -p "$project_dir/build/tools" "$output_dir/first" "$output_dir/second"
readonly binary="$project_dir/build/tools/verify_exact_raylib_capture"
readonly vertex_binary="$project_dir/build/tools/verify_exact_public_playback"
nim c --hints:off --mm:orc --noNimblePath -d:useNaylib \
  --path:"$naylib_dir" --out:"$binary" \
  "$project_dir/tools/verify_exact_raylib_capture.nim"
nim c --hints:off --mm:orc --noNimblePath --out:"$vertex_binary" \
  "$project_dir/tools/verify_exact_public_playback.nim"
"$vertex_binary" "$asset"

for run in first second; do
  caffeinate -u "$binary" \
    --asset:"$asset" \
    --oracle:"$oracle" \
    --reference-dir:"$reference_dir" \
    --output-dir:"$output_dir/$run"
done

diff -qr "$output_dir/first" "$output_dir/second"
echo "repeatable exact Raylib capture: $output_dir"
