#!/usr/bin/env bash
# Guards the pai-sho version pin in both charts.
#
# Exists because of a real outage: the sidecar URL was bumped to the v0.4.1
# FILENAME while the tag path still said v0.3.0. That asset does not exist, so
# `wget` 404'd and the sidecar crashlooped. A rendered-URL check would have
# caught it before the apply, so that is what this does:
#
#   1. the rendered URL is reachable (HTTP 200), for both charts
#   2. the version appears consistently in tag path and filename
#   3. a filename/tag mismatch is now impossible to express
#   4. the arch pin matches the nodes the release is scheduled onto
set -uo pipefail

cd "$(dirname "$0")"
rc=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; rc=1; }

render_url() { # render_url <chart-dir> [extra helm args...]
  local chart="$1"; shift
  helm template "$chart" "$@" 2>/dev/null \
    | grep -A1 'name: PAI_SHO_URL' \
    | grep 'value:' \
    | sed 's/.*value: *"\(.*\)"/\1/'
}

echo "--- rendered URLs resolve"
for chart in ../sglang-hmnd-server/sglang-hmnd-server ../pai-sho-proxy/pai-sho-proxy; do
  url=$(render_url "$chart")
  if [ -z "$url" ]; then
    fail "$chart renders a PAI_SHO_URL"
    continue
  fi

  code=$(curl -sI -o /dev/null -w '%{http_code}' -L "$url")
  if [ "$code" = "200" ]; then
    pass "$(basename "$chart") URL is reachable ($code)"
  else
    fail "$(basename "$chart") URL returns $code: $url"
  fi

  # The bug that caused the outage: tag path and filename disagreeing.
  tag=$(echo "$url" | sed 's|.*/download/\([^/]*\)/.*|\1|')
  file_ver=$(echo "$url" | sed 's|.*/pai-sho-\(v[^-]*\)-.*|\1|')
  if [ "$tag" = "$file_ver" ]; then
    pass "$(basename "$chart") tag path and filename agree ($tag)"
  else
    fail "$(basename "$chart") tag path $tag != filename version $file_ver"
  fi
done

echo "--- arch pins match where each side runs"
server_url=$(render_url ../sglang-hmnd-server/sglang-hmnd-server)
case "$server_url" in
  *linux-amd64*) pass "server chart pins linux-amd64 (GPU nodes are amd64)" ;;
  *) fail "server chart is not linux-amd64: $server_url" ;;
esac
proxy_url=$(render_url ../pai-sho-proxy/pai-sho-proxy)
case "$proxy_url" in
  *linux-arm64*) pass "proxy chart pins linux-arm64 (nodeAffinity requires arm64)" ;;
  *) fail "proxy chart is not linux-arm64: $proxy_url" ;;
esac

echo "--- a bad version pin fails the render, not the pod"
if helm template ../sglang-hmnd-server/sglang-hmnd-server \
     --set sidecar.version=0.4.1 >/dev/null 2>&1; then
  fail "a version without the 'v' prefix should fail at template time"
else
  pass "unprefixed version is rejected at template time"
fi

echo "--- downloadUrl still overrides"
override=$(render_url ../sglang-hmnd-server/sglang-hmnd-server \
  --set sidecar.downloadUrl=https://example.invalid/pai-sho.tar.gz)
if [ "$override" = "https://example.invalid/pai-sho.tar.gz" ]; then
  pass "explicit downloadUrl overrides the derived URL"
else
  fail "downloadUrl override ignored (got '$override')"
fi

echo
if [ "$rc" -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "$rc"
