#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_RUNTIME_SHA="372b8092e940f32cf84499ae23a4899ec66a9ab1"
readonly EXPECTED_ASSET_SHA="7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35"

asset_path=""
runtime_path=""
output_path=""

while (($#)); do
  case "$1" in
    --asset)
      asset_path="$2"
      shift 2
      ;;
    --runtime)
      runtime_path="$2"
      shift 2
      ;;
    --output)
      output_path="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$asset_path" || -z "$runtime_path" || -z "$output_path" ]]; then
  echo "usage: $0 --asset PATH --runtime PATH --output PATH" >&2
  exit 2
fi

actual_asset_sha="$(shasum -a 256 "$asset_path" | awk '{print $1}')"
if [[ "$actual_asset_sha" != "$EXPECTED_ASSET_SHA" ]]; then
  echo "asset hash mismatch: expected $EXPECTED_ASSET_SHA, got $actual_asset_sha" >&2
  exit 2
fi

actual_runtime_sha="$(git -C "$runtime_path" rev-parse HEAD)"
if [[ "$actual_runtime_sha" != "$EXPECTED_RUNTIME_SHA" ]]; then
  echo "runtime hash mismatch: expected $EXPECTED_RUNTIME_SHA, got $actual_runtime_sha" >&2
  exit 2
fi

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$(dirname "$output_path")"
readonly project_dir output_dir
readonly verify_path="$output_dir/.rive-wire-audit-verify.json"

mkdir -p "$project_dir/build/tools" "$output_dir"
nim c --hints:off --mm:orc --out:"$project_dir/build/tools/rive_wire_audit" \
  "$project_dir/tools/rive_wire_audit.nim"

run_audit() {
  "$project_dir/build/tools/rive_wire_audit" \
    --asset:"$asset_path" \
    --defs:"$runtime_path/dev/defs" \
    --output:"$1" \
    --runtime-sha:"$EXPECTED_RUNTIME_SHA"
}

run_audit "$output_path"
run_audit "$verify_path"
cmp "$output_path" "$verify_path"
rm -f "$verify_path"

echo "asset: $EXPECTED_ASSET_SHA"
echo "runtime: $EXPECTED_RUNTIME_SHA"
echo "wire audit reproducibility: byte-for-byte verified"
