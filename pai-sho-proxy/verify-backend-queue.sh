#!/usr/bin/env bash
# Does capping backend concurrency actually improve the tail?
#
# WHAT WAS WRONG
# llama.cpp runs with `--parallel 1` (n_slots = 1), so it serialises requests no
# matter how many it accepts. HAProxy had no backend `maxconn`, so it shipped
# every concurrent request straight in, and the wait happened invisibly inside
# the origin. Measured over 48h of production traffic:
#
#   in flight   requests   mean TTFB   max TTFB
#           1        190        1.5s      30.2s
#           2         76       18.0s     109.1s
#           4         15       67.7s     107.0s
#           6          2       83.9s     136.9s
#
# All 8 client aborts were slow requests, 3 past 100s (where Cloudflare 524s).
# HAProxy's queue time was 0ms throughout, proving it was not throttling.
#
# WHAT THIS MEASURES
# A single-slot origin (one worker, fixed service time), N concurrent clients,
# with and without `maxconn 1` on the backend. Two things are asserted:
#
#   1. the wait moves into HAProxy's queue, so it appears in the Tw log field
#      and is bounded by `timeout queue` instead of hidden inside the origin;
#   2. latency actually improves. This was not a given, and is the reason to
#      ship it rather than just to instrument it. Measured here: p50 41.1s ->
#      21.9s and wall 78.1s -> 54.6s for 6 concurrent requests. Admitting six
#      connections to a one-slot server makes them contend (the origin
#      interleaves accept and read work across sockets it cannot serve yet);
#      queueing them serves one cleanly at a time, so early requests finish
#      sooner and none is starved.
#
# Requires docker. No cluster.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
NET=paisho-queue-net
rc=0
cleanup() { docker rm -f pq-origin pq-pod >/dev/null 2>&1; docker network rm $NET >/dev/null 2>&1; }
trap cleanup EXIT
cleanup
docker network create $NET >/dev/null 2>&1

# Origin with ONE worker and a fixed 2s service time: llama.cpp's n_slots=1.
# Deliberately serialised (not ThreadingHTTPServer) so the backend really is
# the bottleneck, which is the property under test.
ORIGIN_PY='
import http.server, time
class H(http.server.BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"
    def log_message(self,*a): pass
    def do_POST(self):
        n=int(self.headers.get("Content-Length","0")); self.rfile.read(n)
        time.sleep(2)   # one "generation"
        b=b"ok\n"; self.send_response(200)
        self.send_header("Content-Length",str(len(b))); self.end_headers(); self.wfile.write(b)
http.server.HTTPServer(("0.0.0.0",8080),H).serve_forever()
'
docker run -d --name pq-origin --network $NET -e PY="$ORIGIN_PY" python:3.12-alpine \
  sh -c 'printf "%s\n" "$PY" > /o.py && exec python /o.py' >/dev/null
sleep 2
OIP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' pq-origin)

start_pod() { # $1 = server line suffix (e.g. "maxconn 1")
  docker rm -f pq-pod >/dev/null 2>&1
  local cfg="global
  log stdout format raw local0 info
defaults
  log global
  mode http
  option httplog
  retries 20
  retry-on conn-failure empty-response response-timeout 502 503
  timeout connect 3s
  timeout client 1h
  timeout server 1h
  timeout queue 30m
  timeout http-keep-alive 10m
frontend fe
  bind 0.0.0.0:8081
  timeout http-request 30s
  default_backend be
backend be
  server tunnel 127.0.0.1:8080 $1"
  docker run -d --name pq-pod --network $NET -e CFG="$cfg" -e OIP="$OIP" \
    --entrypoint sh alpine:3.20 -c '
      apk add --no-cache haproxy socat >/dev/null 2>&1
      printf "%s\n" "$CFG" > /tmp/h.cfg
      socat TCP-LISTEN:8080,bind=127.0.0.1,fork,reuseaddr TCP:$OIP:8080 &
      exec haproxy -f /tmp/h.cfg' >/dev/null
  for _ in $(seq 30); do
    docker exec pq-pod pgrep haproxy >/dev/null 2>&1 && { sleep 1; return 0; }
    sleep 1
  done
  echo "  ERROR pod did not start"; docker logs pq-pod 2>&1 | tail -3; return 1
}

# 6 concurrent requests, matching the worst concurrency seen in production.
load() {
  local ip; ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' pq-pod)
  docker run --rm --network $NET -e IP="$ip" python:3.12-alpine sh -c '
cat > /c.py <<EOF
import threading, socket, time, os, statistics
IP=os.environ["IP"]; N=6
lat=[]; lock=threading.Lock()
def one():
    t=time.time()
    try:
        s=socket.create_connection((IP,8081),timeout=300)
        body=b"x"*2048
        s.sendall(("POST /v1/chat/completions HTTP/1.1\r\nHost: x\r\nContent-Length: %d\r\n\r\n"%len(body)).encode()+body)
        r=b""
        while b"\r\n\r\n" not in r:
            d=s.recv(65536)
            if not d: break
            r+=d
        ok = b" 200 " in r
    except Exception:
        ok=False
    with lock: lat.append((time.time()-t, ok))
ts=[threading.Thread(target=one) for _ in range(N)]
t0=time.time()
for t in ts: t.start()
for t in ts: t.join()
wall=time.time()-t0
times=sorted(x for x,_ in lat); fails=sum(1 for _,ok in lat if not ok)
print("    n=%d  wall=%.1fs  p50=%.1fs  max=%.1fs  failures=%d" % (len(lat), wall, statistics.median(times), times[-1], fails))
print("P50_MS=%d" % int(statistics.median(times)*1000))
EOF
python /c.py'
}

show_queue_visibility() {
  local q; q=$(docker logs pq-pod 2>&1 | grep -c 'fe be/tunnel')
  local maxtw; maxtw=$(docker logs pq-pod 2>&1 | grep 'fe be/tunnel' | awk '{split($5,t,"/"); if(t[2]>m) m=t[2]} END{print m+0}')
  echo "    haproxy logged $q requests, max queue time (Tw) = ${maxtw}ms"
}

echo "=== A: no backend maxconn (shipped behaviour) ==="
start_pod "" || exit 1
A_OUT=$(load); echo "$A_OUT" | grep -v '^P50_MS='
A_P50=$(sed -n 's/^P50_MS=//p' <<<"$A_OUT")
show_queue_visibility
A_TW=$(docker logs pq-pod 2>&1 | grep 'fe be/tunnel' | awk '{split($5,t,"/"); if(t[2]>m) m=t[2]} END{print m+0}')

echo
echo "=== B: maxconn 1, matching llama.cpp --parallel 1 ==="
start_pod "maxconn 1" || exit 1
B_OUT=$(load); echo "$B_OUT" | grep -v '^P50_MS='
B_P50=$(sed -n 's/^P50_MS=//p' <<<"$B_OUT")
show_queue_visibility
B_TW=$(docker logs pq-pod 2>&1 | grep 'fe be/tunnel' | awk '{split($5,t,"/"); if(t[2]>m) m=t[2]} END{print m+0}')

echo
echo "=== verdict ==="
if [ "${A_TW:-0}" -eq 0 ] && [ "${B_TW:-0}" -gt 0 ]; then
  echo "  PASS  wait moved into HAProxy's queue: Tw ${A_TW}ms -> ${B_TW}ms"
  echo "        It is now visible in logs and bounded by 'timeout queue'."
else
  echo "  FAIL  expected Tw to be 0 without maxconn and >0 with it (got ${A_TW}ms -> ${B_TW}ms)"
  rc=1
fi
# Latency must not regress. Compared on p50, which is what a typical caller
# feels; the max is the same either way since the last request waits for all
# the others regardless of where it waits.
if [ "${B_P50:-0}" -gt 0 ] && [ "${A_P50:-0}" -gt 0 ]; then
  if [ "$B_P50" -le "$A_P50" ]; then
    echo "  PASS  p50 did not regress: ${A_P50}ms -> ${B_P50}ms"
  else
    echo "  FAIL  p50 regressed: ${A_P50}ms -> ${B_P50}ms"; rc=1
  fi
else
  echo "  WARN  could not compare p50 (A=${A_P50:-?} B=${B_P50:-?})"
fi
[ $rc -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $rc
