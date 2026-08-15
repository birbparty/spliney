#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_RUNTIME_SHA="372b8092e940f32cf84499ae23a4899ec66a9ab1"
readonly EXPECTED_ASSET_SHA="7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35"

asset_path=""
runtime_path=""
output_dir=""
while (($#)); do
  case "$1" in
    --asset) asset_path="$2"; shift 2 ;;
    --runtime) runtime_path="$2"; shift 2 ;;
    --output-dir) output_dir="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$asset_path" || -z "$runtime_path" || -z "$output_dir" ]]; then
  echo "usage: $0 --asset PATH --runtime PATH --output-dir PATH" >&2
  exit 2
fi

actual_asset_sha="$(shasum -a 256 "$asset_path" | awk '{print $1}')"
actual_runtime_sha="$(git -C "$runtime_path" rev-parse HEAD)"
[[ "$actual_asset_sha" == "$EXPECTED_ASSET_SHA" ]] || {
  echo "asset hash mismatch: expected $EXPECTED_ASSET_SHA, got $actual_asset_sha" >&2
  exit 2
}
[[ "$actual_runtime_sha" == "$EXPECTED_RUNTIME_SHA" ]] || {
  echo "runtime hash mismatch: expected $EXPECTED_RUNTIME_SHA, got $actual_runtime_sha" >&2
  exit 2
}

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly project_dir
readonly source_dir="$project_dir/tools/rive_oracle_probe"
readonly build_dir="$project_dir/build/tools/rive_oracle_probe"
readonly isolated_runtime="$build_dir/runtime"
readonly staged_source="$build_dir/probe-source"
readonly binary="$build_dir/out/release/rive_oracle_probe"
readonly first_dir="$output_dir/first"
readonly second_dir="$output_dir/second"

mkdir -p "$build_dir" "$staged_source" "$first_dir/reference" "$second_dir/reference"
if [[ ! -d "$isolated_runtime/.git" ]]; then
  git clone --local --no-hardlinks "$runtime_path" "$isolated_runtime"
fi
git -C "$isolated_runtime" checkout --detach "$EXPECTED_RUNTIME_SHA"
cp -f "$source_dir/main.cpp" "$staged_source/main.cpp"
cp -f "$source_dir/premake5.lua" "$staged_source/premake5.lua"

export RIVE_RUNTIME_PATH="$isolated_runtime"
export RIVE_OUT="../out/release"
export RIVE_PREMAKE_ARGS=""
(
  cd "$staged_source"
  "$isolated_runtime/build/build_rive.sh" release -- rive_oracle_probe
)

run_probe() {
  local run_dir="$1"
  "$binary" \
    --asset "$asset_path" \
    --output "$run_dir/oracle.json" \
    --reference-dir "$run_dir/reference" \
    --runtime-sha "$EXPECTED_RUNTIME_SHA"
}
run_probe "$first_dir"
run_probe "$second_dir"
cmp "$first_dir/oracle.json" "$second_dir/oracle.json"
diff -rq "$first_dir/reference" "$second_dir/reference"

echo "oracle: $first_dir/oracle.json"
echo "reference frames: $first_dir/reference"
echo "reproducibility: byte-for-byte verified"
