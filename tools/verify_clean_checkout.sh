#!/usr/bin/env bash
set -euo pipefail

readonly project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly expected_asset_sha="7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35"
readonly expected_oracle_sha="778a46c266d66dcc16c484cd6931505059d86ba7ed9f9e43f540c869a8a7406c"
readonly expected_naylib_sha="a705b3fc7987785b6609780a0237e92f380705a357faee8a30af8b26275dc1ae"

asset=""
wire_audit=""
oracle=""
reference_dir=""
baseline=""
naylib_dir=""
output_dir=""
while (($#)); do
  case "$1" in
    --asset) asset="$2"; shift 2 ;;
    --wire-audit) wire_audit="$2"; shift 2 ;;
    --oracle) oracle="$2"; shift 2 ;;
    --reference-dir) reference_dir="$2"; shift 2 ;;
    --baseline) baseline="$2"; shift 2 ;;
    --naylib-dir) naylib_dir="$2"; shift 2 ;;
    --output-dir) output_dir="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -f "$asset" && -f "$wire_audit" && -f "$oracle" &&
    -d "$reference_dir" && -f "$baseline" && -d "$naylib_dir" &&
    -n "$output_dir" && "$output_dir" != "/" ]] || {
  echo "usage: verify_clean_checkout.sh --asset FILE --wire-audit FILE --oracle FILE --reference-dir DIR --baseline FILE --naylib-dir DIR --output-dir DIR" >&2
  exit 2
}
asset="$(cd "$(dirname "$asset")" && pwd)/$(basename "$asset")"
wire_audit="$(cd "$(dirname "$wire_audit")" && pwd)/$(basename "$wire_audit")"
oracle="$(cd "$(dirname "$oracle")" && pwd)/$(basename "$oracle")"
reference_dir="$(cd "$reference_dir" && pwd)"
baseline="$(cd "$(dirname "$baseline")" && pwd)/$(basename "$baseline")"
naylib_dir="$(cd "$naylib_dir" && pwd)"
if [[ "$output_dir" != /* ]]; then
  output_dir="$project_dir/$output_dir"
fi
[[ "$output_dir" != "$project_dir" && "$output_dir" != "$(dirname "$project_dir")" ]] || {
  echo "output directory is too broad" >&2
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
actual_naylib_sha="$(cd "$naylib_dir" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}')"
[[ "$actual_naylib_sha" == "$expected_naylib_sha" ]] || {
  echo "naylib source hash mismatch" >&2
  exit 1
}

readonly source_sha="$(git -C "$project_dir" rev-parse HEAD)"
[[ -z "$(git -C "$project_dir" status --porcelain=v1)" ]] || {
  echo "source checkout must be clean before reproduction" >&2
  exit 1
}

rm -rf "$output_dir"
mkdir -p "$output_dir/logs"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/spliney-clean.XXXXXX")"
cleanup() {
  rm -rf "$temporary_root"
}
trap cleanup EXIT

readonly checkout="$temporary_root/spliney"
readonly dependency_dir="$temporary_root/dependencies"
readonly clean_naylib="$dependency_dir/naylib"
readonly consumer_dir="$temporary_root/goblin-consumer"
readonly clean_nimble_dir="$temporary_root/nimble-cache"
mkdir -p "$dependency_dir" "$clean_nimble_dir"
# Nimble 0.20.1 prompts to download its registry even with --offline when the
# cache is completely absent. Seed an intentionally empty registry: this
# package's only declared dependency is the system Nim compiler, while every
# non-core dependency is supplied below by a pinned explicit source path.
jq -n '[]' > "$clean_nimble_dir/packages_official.json"
jq -n '[]' > "$clean_nimble_dir/packages_temp.json"
git clone --quiet --no-local "$project_dir" "$checkout"
git -C "$checkout" checkout --quiet --detach "$source_sha"
cp -Rf "$naylib_dir" "$clean_naylib"
cp -Rf "$checkout/tests/consumer/goblin_demo" "$consumer_dir"

copied_naylib_sha="$(cd "$clean_naylib" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}')"
[[ "$copied_naylib_sha" == "$expected_naylib_sha" ]]
[[ -z "$(find "$clean_nimble_dir" -mindepth 1 -maxdepth 1 -type d -print -quit)" ]]

export NIMBLE_DIR="$clean_nimble_dir"
(
  cd "$checkout"
  nimble --offline check
  nimble --offline dump --json 2> "$output_dir/logs/nimble-dump.log" |
    sed -n '/^{/,$p' > "$output_dir/nimble-package.json"
  jq -e '.name == "spliney" and .requires == [{"name":"nim","str":">= 2.0.0","ver":{"kind":"verEqLater","ver":"2.0.0"}}]' \
    "$output_dir/nimble-package.json" >/dev/null
  nimble --offline test -y
) 2>&1 | tee "$output_dir/logs/core.log"

nim c --hints:off --mm:orc --noNimblePath \
  --path:"$checkout/src" --out:"$temporary_root/verify_goblin_gate0" \
  "$checkout/tools/verify_goblin_gate0.nim" 2>&1 |
  tee "$output_dir/logs/gate0-build.log"
"$temporary_root/verify_goblin_gate0" \
  --wire:"$wire_audit" --oracle:"$oracle" --baseline:"$baseline" 2>&1 |
  tee "$output_dir/logs/gate0.log"

"$checkout/tools/run_exact_headless_gate.sh" \
  --asset "$asset" --oracle "$oracle" 2>&1 |
  tee "$output_dir/logs/headless.log"

"$checkout/tools/run_exact_raylib_capture.sh" \
  --asset "$asset" --oracle "$oracle" --reference-dir "$reference_dir" \
  --naylib-dir "$clean_naylib" --output-dir "$output_dir/capture" 2>&1 |
  tee "$output_dir/logs/capture.log"

"$checkout/tools/run_exact_lifecycle.sh" \
  --asset "$asset" --naylib-dir "$clean_naylib" \
  --output-dir "$output_dir/lifecycle" 2>&1 |
  tee "$output_dir/logs/lifecycle.log"

(
  cd "$consumer_dir"
  nimble --offline check
  nim c --hints:off -d:release --mm:orc --noNimblePath -d:useNaylib \
    --path:"$checkout/src" --path:"$clean_naylib" \
    --out:"$temporary_root/goblin-consumer-bin" src/goblin_demo.nim
  caffeinate -u "$temporary_root/goblin-consumer-bin" "$asset"
) 2>&1 | tee "$output_dir/logs/consumer.log"

[[ -z "$(git -C "$checkout" status --porcelain=v1)" ]]
if [[ -d "$clean_nimble_dir/pkgs2" ]]; then
  [[ -z "$(find "$clean_nimble_dir/pkgs2" -mindepth 1 -maxdepth 1 -print -quit)" ]]
fi
readonly capture_metrics_sha="$(shasum -a 256 "$output_dir/capture/first/capture-metrics.json" | awk '{print $1}')"
readonly lifecycle_metrics_sha="$(shasum -a 256 "$output_dir/lifecycle/normal/lifecycle-metrics.json" | awk '{print $1}')"
readonly consumer_source_sha="$(shasum -a 256 "$checkout/tests/consumer/goblin_demo/src/goblin_demo.nim" | awk '{print $1}')"
readonly wire_sha="$(shasum -a 256 "$wire_audit" | awk '{print $1}')"
readonly baseline_sha="$(shasum -a 256 "$baseline" | awk '{print $1}')"

jq -n \
  --arg sourceSha "$source_sha" \
  --arg assetSha "$expected_asset_sha" \
  --arg oracleSha "$expected_oracle_sha" \
  --arg wireSha "$wire_sha" \
  --arg baselineSha "$baseline_sha" \
  --arg naylibSha "$expected_naylib_sha" \
  --arg captureMetricsSha "$capture_metrics_sha" \
  --arg lifecycleMetricsSha "$lifecycle_metrics_sha" \
  --arg consumerSourceSha "$consumer_source_sha" \
  '{
    schemaVersion: 1,
    testedSourceSha: $sourceSha,
    cleanCheckout: true,
    cleanNimblePackageCacheAtStart: true,
    dependencyResolution: {
      nim: "system Nim 2.2.10",
      spliney: "explicit clean-checkout src path",
      naylib: "explicit copied source path",
      offlineRegistrySeed: "empty",
      naylibAggregateSha256: $naylibSha,
      undeclaredNimblePackages: 0
    },
    inputs: {
      assetSha256: $assetSha,
      oracleSha256: $oracleSha,
      wireAuditSha256: $wireSha,
      siblingBaselineSha256: $baselineSha
    },
    gates: {
      core: "pass",
      gate0: "pass",
      headless: "pass",
      macosCapture: "pass",
      lifecycleLeaks: "pass",
      independentConsumer: "pass"
    },
    outputSha256: {
      captureMetrics: $captureMetricsSha,
      lifecycleMetrics: $lifecycleMetricsSha,
      consumerSource: $consumerSourceSha
    },
    checkoutCleanAfterRun: true
  }' > "$output_dir/clean-checkout-results.json"

echo "clean-checkout and independent-consumer reproduction passed: $source_sha"
