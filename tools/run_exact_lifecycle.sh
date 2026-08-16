#!/usr/bin/env bash
set -euo pipefail

readonly project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly expected_naylib_sha="a705b3fc7987785b6609780a0237e92f380705a357faee8a30af8b26275dc1ae"
readonly expected_asset_sha="7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35"

asset=""
output_dir=""
naylib_dir=""
while (($#)); do
  case "$1" in
    --asset) asset="$2"; shift 2 ;;
    --output-dir) output_dir="$2"; shift 2 ;;
    --naylib-dir) naylib_dir="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -f "$asset" && -n "$output_dir" && -d "$naylib_dir" ]] || {
  echo "usage: run_exact_lifecycle.sh --asset FILE --output-dir DIR --naylib-dir DIR" >&2
  exit 2
}
actual_naylib_sha="$(cd "$naylib_dir" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}')"
[[ "$actual_naylib_sha" == "$expected_naylib_sha" ]] || {
  echo "naylib source hash mismatch" >&2
  exit 1
}
[[ "$(shasum -a 256 "$asset" | awk '{print $1}')" == "$expected_asset_sha" ]] || {
  echo "asset SHA-256 mismatch" >&2
  exit 1
}

rm -rf "$output_dir/normal" "$output_dir/leaks-run"
mkdir -p "$project_dir/build/tools" "$output_dir/normal" "$output_dir/leaks-run"
readonly binary="$project_dir/build/tools/verify_exact_lifecycle"
nim c --hints:off -d:release --mm:orc --noNimblePath -d:useNaylib \
  --path:"$naylib_dir" --out:"$binary" \
  "$project_dir/tools/verify_exact_lifecycle.nim"

normal_started=$SECONDS
perl -e '$SIG{ALRM}=sub{die "120-second lifecycle timeout\n"}; alarm shift; exec @ARGV' \
  120 caffeinate -u "$binary" --asset:"$asset" \
  --output-dir:"$output_dir/normal"
normal_elapsed=$((SECONDS - normal_started))
if ((normal_elapsed >= 5)); then
  echo "lifecycle process exceeded five seconds in total" >&2
  exit 1
fi

perl -e '$SIG{ALRM}=sub{die "120-second leaks timeout\n"}; alarm shift; exec @ARGV' \
  120 leaks -e '-[LNProcessInstanceRegistryClient makeXPCConnection]' \
  --atExit -- "$binary" --asset:"$asset" \
  --output-dir:"$output_dir/leaks-run" >"$output_dir/leaks.txt" 2>&1

diff -q "$output_dir/normal/lifecycle-metrics.json" \
  "$output_dir/leaks-run/lifecycle-metrics.json"
grep -q "exact lifecycle matrix verified" "$output_dir/leaks.txt"
if grep -q '^STACK OF' "$output_dir/leaks.txt"; then
  echo "non-excluded leak stack remains" >&2
  exit 1
fi
if ! grep -q "0 leaks for 0 total leaked bytes" "$output_dir/leaks.txt" &&
    ! grep -Eq '[0-9]+ leaks excluded \(not printed\)' "$output_dir/leaks.txt"; then
  echo "leaks report has no zero-attributable result" >&2
  exit 1
fi
echo "exact lifecycle and macOS leaks gates passed: $output_dir"
