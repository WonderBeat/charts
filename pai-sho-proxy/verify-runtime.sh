#!/usr/bin/env bash
# Runtime proof that multi-port routing works, against the live deployment.
#
# verify-config.sh proves the rendered config is valid; this proves traffic
# actually flows on an added port. It temporarily adds a second entry in tcp mode
# pointing at the same tunnel port, checks both ports answer from inside the pod,
# then reverts to the committed config.
#
# Tested from inside the pod on the pod IP, deliberately: HAProxy binds the pod
# IP (not 0.0.0.0) so that pai-sho keeps loopback, and going through
# port-forward/Service adds failure modes unrelated to what is being tested.
#
# Requires: KUBECONFIG for the cluster running this release, and API_KEY set to
# the upstream llama-server key (any value works for /v1/models reachability, but
# a wrong one returns 401 instead of the model list).
set -uo pipefail
cd "$(dirname "$0")" || exit 1
NS=${NS:-network}
REL=${REL:-pai-sho-proxy}
if [ -z "${API_KEY:-}" ]; then
  echo "set API_KEY to the upstream llama-server key, e.g. API_KEY=... $0" >&2
  exit 2
fi
rc=0
trap 'echo "=== revert to committed config ==="; helmfile apply 2>&1 | tail -2' EXIT

echo "=== add a 2nd port in tcp mode (9090 -> same tunnel port 8080) ==="
helm -n "$NS" upgrade "$REL" ./pai-sho-proxy --reuse-values \
  --set 'ports[0].name=llama'    --set 'ports[0].port=8080' --set 'ports[0].mode=http' \
  --set 'ports[1].name=llamatcp' --set 'ports[1].port=9090' --set 'ports[1].mode=tcp' \
  --set 'ports[1].targetPort=8080' >/dev/null 2>&1 || { echo "  FAIL: upgrade"; exit 1; }
kubectl -n "$NS" rollout status "deploy/$REL" --timeout=240s 2>&1 | tail -1
kubectl -n "$NS" wait --for=condition=Ready pod \
  -l "app.kubernetes.io/name=$REL" --timeout=180s 2>&1 | tail -1
POD=$(kubectl -n "$NS" get pod -l "app.kubernetes.io/name=$REL" -o jsonpath='{.items[0].metadata.name}')

echo "=== haproxy listeners (expect pod-IP:8080, pod-IP:9090, 0.0.0.0:health) ==="
kubectl -n "$NS" exec "$POD" -c proxy -- sh -c 'netstat -tln 2>/dev/null || ss -tln' \
  | awk '/LISTEN/ {print "  "$4}'

echo "=== haproxy startup complaints (expect none) ==="
LOGS=$(kubectl -n "$NS" logs "$POD" -c proxy --tail=40 2>&1 | grep -iE "warn|error|alert|unable|cannot" | head -5)
if [ -n "$LOGS" ]; then echo "$LOGS" | sed 's/^/  /'; rc=1; else echo "  clean"; fi

echo "=== both ports serve the model from inside the pod ==="
OUT=$(kubectl -n "$NS" exec "$POD" -c tunnel -- sh -c "
  IP=\$(hostname -i)
  for p in 8080 9090; do
    printf '%s:' \"\$p\"
    wget -qO- --timeout=25 --header='Authorization: Bearer $API_KEY' \
      \"http://\$IP:\$p/v1/models\" 2>/dev/null | head -c 40
    echo ''
  done" 2>&1)
for p in 8080 9090; do
  if echo "$OUT" | grep -q "^$p:.*models"; then
    echo "  PASS  port $p answered"
  else
    echo "  FAIL  port $p: $(echo "$OUT" | grep "^$p:")"; rc=1
  fi
done

echo
[ $rc -eq 0 ] && echo "MULTI-PORT ROUTING VERIFIED (http + tcp)" || echo "FAILURES ABOVE"
exit $rc
