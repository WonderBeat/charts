#!/usr/bin/env bash
# Validate rendered haproxy.cfg with the real haproxy binary, for both the
# default single-port case and a mixed http+tcp multi-port case.
#
# A rendered config that Helm accepts can still be rejected by haproxy, which
# would crashloop the pod. `haproxy -c` is the only check that actually proves
# the generated config is loadable.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
CHART=./pai-sho-proxy
IMG=haproxy:3.0-alpine
rc=0

render_cfg() {
  helm template pai-sho-proxy "$CHART" "$@" | python3 -c "
import sys,yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d.get('kind')=='ConfigMap': print(d['data']['haproxy.cfg'])
"
}

check_cfg() { # $1 = label, rest = helm args
  local label=$1; shift
  local tmp; tmp=$(mktemp -d)
  render_cfg "$@" > "$tmp/haproxy.cfg" 2>"$tmp/err" || {
    echo "  FAIL  $label: render failed"; sed 's/^/        /' "$tmp/err" | head -5; rc=1
    rm -rf "$tmp"; return
  }
  # POD_IP is substituted by haproxy at runtime from the env; provide a dummy.
  if docker run --rm -e POD_IP=127.0.0.1 -v "$tmp:/cfg:ro" "$IMG" \
       haproxy -c -f /cfg/haproxy.cfg >"$tmp/out" 2>&1; then
    echo "  PASS  $label ($(grep -c '^frontend' "$tmp/haproxy.cfg") frontends)"
  else
    echo "  FAIL  $label: haproxy rejected the config"
    sed 's/^/        /' "$tmp/out" | head -10; rc=1
  fi
  rm -rf "$tmp"
}

echo "=== haproxy -c on rendered configs ==="
check_cfg "default (single http port)"
check_cfg "multi-port http+tcp" \
  --set 'ports[0].name=llama' --set 'ports[0].port=8080' --set 'ports[0].mode=http' \
  --set 'ports[1].name=postgres' --set 'ports[1].port=5432' --set 'ports[1].mode=tcp' \
  --set 'ports[2].name=ssh' --set 'ports[2].port=2222' --set 'ports[2].mode=tcp'
check_cfg "port with distinct targetPort" \
  --set 'ports[0].name=api' --set 'ports[0].port=9000' \
  --set 'ports[0].targetPort=8080' --set 'ports[0].mode=http'

echo "=== template-time validation ==="
if helm template pai-sho-proxy "$CHART" --set 'ports[0].name=x' \
     --set 'ports[0].port=1' --set 'ports[0].mode=udp' >/dev/null 2>/tmp/_e; then
  echo "  FAIL  invalid mode was accepted"; rc=1
else
  echo "  PASS  invalid mode rejected: $(grep -o "mode \"udp\".*" /tmp/_e | head -1)"
fi
if helm template pai-sho-proxy "$CHART" --set 'ports=[]' >/dev/null 2>/tmp/_e2; then
  echo "  FAIL  empty ports accepted"; rc=1
else
  echo "  PASS  empty ports rejected"
fi
rm -f /tmp/_e /tmp/_e2

echo "=== multi-port Service/container ports ==="
helm template pai-sho-proxy "$CHART" \
  --set 'ports[0].name=llama' --set 'ports[0].port=8080' --set 'ports[0].mode=http' \
  --set 'ports[1].name=postgres' --set 'ports[1].port=5432' --set 'ports[1].mode=tcp' \
  | python3 -c "
import sys,yaml
for d in yaml.safe_load_all(sys.stdin):
    if not d: continue
    if d['kind']=='Service':
        print('  service   :',[(p['name'],p['port'],p['targetPort']) for p in d['spec']['ports']])
        print('  selector  :',d['spec']['selector'])
    if d['kind']=='Deployment':
        c=[x for x in d['spec']['template']['spec']['containers'] if x['name']=='proxy'][0]
        print('  container :',[(p['name'],p['containerPort']) for p in c['ports']])
        v=[x for x in d['spec']['template']['spec']['volumes'] if x['name']=='pai-sho-state'][0]
        print('  claim     :',v['persistentVolumeClaim']['claimName'])
        print('  strategy  :',d['spec'].get('strategy'))
"
exit $rc
