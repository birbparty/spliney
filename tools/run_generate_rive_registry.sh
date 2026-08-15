#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_RUNTIME_SHA="372b8092e940f32cf84499ae23a4899ec66a9ab1"

runtime_path=""
output_path=""
check_only="false"
while (($#)); do
  case "$1" in
    --runtime) runtime_path="$2"; shift 2 ;;
    --output) output_path="$2"; shift 2 ;;
    --check) check_only="true"; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$runtime_path" || -z "$output_path" ]]; then
  echo "usage: $0 --runtime DIR --output FILE" >&2
  exit 2
fi
actual_runtime_sha="$(git -C "$runtime_path" rev-parse HEAD)"
[[ "$actual_runtime_sha" == "$EXPECTED_RUNTIME_SHA" ]] || {
  echo "runtime hash mismatch: expected $EXPECTED_RUNTIME_SHA, got $actual_runtime_sha" >&2
  exit 2
}

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly project_dir
readonly defs_dir="$runtime_path/dev/defs"
defs_sha="$(
  cd "$defs_dir"
  find . -type f -name '*.json' -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}'
)"
readonly defs_sha
temporary_output="$(mktemp "${TMPDIR:-/tmp}/spliney-registry.XXXXXX")"
readonly temporary_output
trap 'rm -f "$temporary_output"' EXIT

nim c -r --hints:off --mm:orc --outdir:"$project_dir/build/tools" \
  "$project_dir/tools/generate_rive_registry.nim" -- \
  --defs "$defs_dir" \
  --output "$temporary_output" \
  --runtime-sha "$EXPECTED_RUNTIME_SHA" \
  --defs-sha "$defs_sha"
if [[ "$check_only" == "true" ]]; then
  cmp "$output_path" "$temporary_output"
else
  mkdir -p "$(dirname "$output_path")"
  cp -f "$temporary_output" "$output_path"
fi

second_output="$(mktemp "${TMPDIR:-/tmp}/spliney-registry-second.XXXXXX")"
readonly second_output
nim c -r --hints:off --mm:orc --outdir:"$project_dir/build/tools" \
  "$project_dir/tools/generate_rive_registry.nim" -- \
  --defs "$defs_dir" \
  --output "$second_output" \
  --runtime-sha "$EXPECTED_RUNTIME_SHA" \
  --defs-sha "$defs_sha"
cmp "$output_path" "$second_output"
rm -f "$second_output"

echo "registry: $output_path"
echo "defs aggregate SHA-256: $defs_sha"
echo "reproducibility: byte-for-byte verified"
