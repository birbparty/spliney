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

[[ "$(jq -r .assetSha256 "$oracle_path")" == "$EXPECTED_ASSET_SHA" ]] || {
  echo "oracle asset hash mismatch" >&2
  exit 2
}
[[ "$(jq -r .officialRuntimeSha "$oracle_path")" == "$EXPECTED_RUNTIME_SHA" ]] || {
  echo "oracle runtime hash mismatch" >&2
  exit 2
}
while IFS=$'\t' read -r expected filename; do
  actual="$(shasum -a 256 "$reference_dir/$filename" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || {
    echo "encoded image hash mismatch: $filename" >&2
    exit 2
  }
done < <(jq -r '.images[] | [.encodedSha256, .encodedFilename] | @tsv' "$oracle_path")

naylib_path="$(nimble path naylib)"
[[ "$(basename "$naylib_path")" == "$EXPECTED_NAYLIB_DIR" ]] || {
  echo "naylib revision mismatch: $naylib_path" >&2
  exit 2
}

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly project_dir
readonly binary="$project_dir/build/tools/raylib_png_decode_probe"
readonly first_dir="$output_dir/first"
readonly second_dir="$output_dir/second"
readonly upload_dir="$output_dir/upload"
mkdir -p "$first_dir" "$second_dir" "$upload_dir" "$(dirname "$binary")"

nim c --hints:off --mm:orc -d:useNaylib \
  --out:"$binary" "$project_dir/tools/raylib_png_decode_probe.nim"

run_headless() {
  local run_dir="$1"
  "$binary" \
    --oracle "$oracle_path" \
    --reference-dir "$reference_dir" \
    --output-dir "$run_dir"
  (
    cd "$run_dir"
    shasum -a 256 decoded-image-*.rgba > decoded-sha256.txt
  )
}
run_headless "$first_dir"
run_headless "$second_dir"
cmp "$first_dir/decode-report.json" "$second_dir/decode-report.json"
cmp "$first_dir/decoded-sha256.txt" "$second_dir/decoded-sha256.txt"

caffeinate -u -t 5 &
"$binary" \
  --oracle "$oracle_path" \
  --reference-dir "$reference_dir" \
  --output-dir "$upload_dir" \
  --verify-upload
(
  cd "$upload_dir"
  shasum -a 256 decoded-image-*.rgba > decoded-sha256.txt
)
cmp "$first_dir/decoded-sha256.txt" "$upload_dir/decoded-sha256.txt"
[[ "$(jq -r .headlessDecodeCount "$first_dir/decode-report.json")" == 13 ]]
[[ "$(jq -r .windowCreatedForDecode "$first_dir/decode-report.json")" == false ]]
[[ "$(jq -r .gpuUploadCount "$upload_dir/decode-report.json")" == 13 ]]

echo "headless report: $first_dir/decode-report.json"
echo "decoded hashes: $first_dir/decoded-sha256.txt"
echo "upload report: $upload_dir/decode-report.json"
echo "reproducibility: two headless runs byte-for-byte verified"
