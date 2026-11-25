#!/usr/bin/env bash
# Live check: does the deployed HAProxy admit at most `backend maxconn`
# requests to the origin and queue the rest, instead of dumping them all in?
#
# Fires N concurrent generations at the real Service and then reads HAProxy's
# own log, which is the authority: the Tw field is queue time, and srv_conn must
# never exceed the configured backend maxconn.
#
# The cap matters less than it did against the old one-slot llama.cpp origin --
# SGLang batches --max-running-requests concurrently and queues the remainder
# itself -- but it matters differently: over the cap the surplus waits INSIDE
# sglang where no metric here can see it, so this is what keeps the queue
# observable.
#
# API_KEY is required (the server runs with --api-key).
#   API_KEY=<key> ./verify-live-queue.sh [concurrency]
#
# Targets the cluster the proxy runs in. That is ~/.kube/hungary unless
# KUBECONFIG already points somewhere with the release in it; an inherited
# KUBECONFIG for a DIFFERENT cluster is the common way this "cannot find the
# pod", so it is checked rather than assumed.
set -uo pipefail
: "${API_KEY:?set API_KEY (the sglang server api key)}"
NS=network
N=${1:-4}
rc=0

find_pod() { kubectl get pods -n $NS -l app.kubernetes.io/name=pai-sho-proxy \
             -o jsonpath='{.items[0].metadata.name}' 2>/dev/null; }
POD=$(find_pod)
if [ -z "$POD" ]; then
  export KUBECONFIG="$HOME/.kube/hungary"
  POD=$(find_pod)
  [ -n "$POD" ] && echo "note: pod not in the inherited KUBECONFIG, using $KUBECONFIG"
fi
[ -n "$POD" ] || { echo "proxy pod not found in ${KUBECONFIG:-default kubeconfig}"; exit 1; }
MAXCONN=$(kubectl get cm -n $NS pai-sho-proxy-haproxy -o jsonpath='{.data.haproxy\.cfg}' \
          | grep -oE 'server tunnel [^ ]+ maxconn [0-9]+' | grep -oE '[0-9]+$' | head -1)
echo "pod=$POD  backend maxconn=${MAXCONN:-<unset>}  concurrency=$N"
[ -n "$MAXCONN" ] || { echo "FAIL backend maxconn is not set in the deployed config"; exit 1; }

MARK="qcheck-$(date +%s)"
echo "=== firing $N concurrent generations (marker $MARK)"
# Short max_tokens: this measures queueing, not generation quality.
kubectl run "$MARK" -n $NS --rm -i --restart=Never --image=curlimages/curl:latest \
  --env="API_KEY=$API_KEY" --env="N=$N" --command -- sh -c '
    i=1
    while [ $i -le "$N" ]; do
      ( curl -s -m 300 -o /tmp/out.$i -w "  req '"'"'$i'"'"' HTTP=%{http_code} total=%{time_total}s ttfb=%{time_starttransfer}s\n" \
          -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
          -X POST "http://pai-sho-proxy.network.svc.cluster.local:8080/v1/chat/completions" \
          -d "{\"model\":\"deepseek-flash\",\"max_tokens\":24,\"messages\":[{\"role\":\"user\",\"content\":\"count to five\"}]}" ) &
      i=$((i+1))
    done
    wait' 2>&1 | grep -E 'HTTP=|error' || true

echo "=== HAProxy log for those requests"
# Tq/Tw/Tc/Tr/Tt is field 5; actconn/feconn/beconn/srv_conn/retries is field 11.
logs=$(kubectl logs -n $NS "$POD" -c proxy --tail=400 \
       | grep 'chat/completions' | tail -"$N")
if [ -z "$logs" ]; then
  echo "  FAIL  no request lines found in the proxy log"; exit 1
fi
echo "$logs" | awk '{split($5,t,"/"); split($11,c,"/");
  printf "  Tw(queue)=%7sms  Tr(ttfb)=%7sms  Tt=%7sms  srv_conn=%s  status=%s\n", t[2], t[4], t[5], c[4], $6}'

maxsrv=$(echo "$logs" | awk '{split($11,c,"/"); if (c[4]+0>m) m=c[4]+0} END{print m+0}')
maxtw=$(echo "$logs"  | awk '{split($5,t,"/");  if (t[2]+0>m) m=t[2]+0} END{print m+0}')
bad=$(echo "$logs"    | grep -cvE ' (200|201) ')

echo "=== verdict"
# srv_conn counts connections already on the server, so admitted concurrency is
# srv_conn+1. It must never exceed the configured cap.
if [ "$((maxsrv + 1))" -le "$MAXCONN" ]; then
  echo "  PASS  admitted concurrency stayed within maxconn ($((maxsrv + 1)) <= $MAXCONN)"
else
  echo "  FAIL  server saw $((maxsrv + 1)) concurrent requests, above maxconn=$MAXCONN"; rc=1
fi
if [ "$N" -gt "$MAXCONN" ]; then
  if [ "$maxtw" -gt 0 ]; then
    echo "  PASS  excess requests waited in HAProxy's queue (max Tw=${maxtw}ms)"
  else
    echo "  FAIL  nothing queued despite concurrency $N > maxconn $MAXCONN"; rc=1
  fi
fi
if [ "$bad" -eq 0 ]; then
  echo "  PASS  all requests returned 2xx"
else
  echo "  FAIL  $bad request(s) did not return 2xx"; rc=1
fi
[ $rc -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $rc
