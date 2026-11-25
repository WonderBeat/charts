#!/usr/bin/env bash
# Guard: an idle pooled connection through HAProxy stays reusable.
#
# BACKGROUND
# gomodel logged one
#   "read tcp ...->10.46.243.254:8080: use of closed network connection"
# in 48h. That error means the client wrote a request into a socket the proxy
# had already closed. HAProxy shipped without `timeout http-keep-alive`, which
# makes it fall back to `timeout http-request` (30s) for idle keep-alive, while
# Go's default http.Transport pools an idle connection for 90s. So there was a
# 60s window in which the client believed a closed socket was usable.
#
# HONEST FINDING: this script could NOT turn that timeout into a user-visible
# error, even with a non-replayable POST body and the race compressed to
# 20s vs 30s. Go detects the closed pooled connection and retries on a fresh
# one. So the keep-alive timeout was a sharp edge worth removing, but it was
# NOT the cause of the observed instability; that was backend concurrency, see
# ./verify-backend-queue.sh.
#
# The script is kept as a REGRESSION GUARD in the direction that matters: after
# a long idle period, connection reuse must still work. It also prints what the
# old config did, so the reasoning stays checkable rather than folkloric.
#
# Requires docker. No cluster.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
NET=paisho-verify-net
rc=0
cleanup() { docker rm -f psv-origin psv-pod >/dev/null 2>&1; docker network rm $NET >/dev/null 2>&1; }
trap cleanup EXIT
cleanup
docker network create $NET >/dev/null 2>&1

ORIGIN_PY='
import http.server
class H(http.server.BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"
    def log_message(self,*a): pass
    def do_POST(self):
        n=int(self.headers.get("Content-Length","0")); self.rfile.read(n)
        b=b"ok\n"; self.send_response(200)
        self.send_header("Content-Length",str(len(b))); self.end_headers(); self.wfile.write(b)
http.server.ThreadingHTTPServer(("0.0.0.0",8080),H).serve_forever()
'
docker run -d --name psv-origin --network $NET -e PY="$ORIGIN_PY" python:3.12-alpine \
  sh -c 'printf "%s\n" "$PY" > /o.py && exec python /o.py' >/dev/null
sleep 2
OIP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' psv-origin)

# haproxy + a socat "tunnel" on 127.0.0.1:8080 in ONE netns, the real topology
# (pai-sho binds loopback, haproxy binds the pod IP).
start_pod() { # $1 = extra defaults lines
  docker rm -f psv-pod >/dev/null 2>&1
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
$1
frontend fe
  bind 0.0.0.0:8081
  timeout http-request 20s
  default_backend be
backend be
  server tunnel 127.0.0.1:8080"
  docker run -d --name psv-pod --network $NET -e CFG="$cfg" -e OIP="$OIP" \
    --entrypoint sh alpine:3.20 -c '
      apk add --no-cache haproxy socat >/dev/null 2>&1
      printf "%s\n" "$CFG" > /tmp/h.cfg
      socat TCP-LISTEN:8080,bind=127.0.0.1,fork,reuseaddr TCP:$OIP:8080 &
      exec haproxy -f /tmp/h.cfg' >/dev/null
  for _ in $(seq 30); do
    docker exec psv-pod pgrep haproxy >/dev/null 2>&1 && { sleep 1; return 0; }
    sleep 1
  done
  echo "  ERROR pod did not start"; docker logs psv-pod 2>&1 | tail -3; return 1
}

# Two probes:
#   go   - real client semantics, including its own retry. This is what users see.
#   raw  - a bare socket with NO retry logic, which exposes whether the proxy
#          closed the idle connection at all. Without this, a passing `go` result
#          cannot distinguish "proxy kept it open" from "client papered over it".
GO_SRC='
package main

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

func post(c *http.Client, url string) (string, error) {
	// io.NopCloser hides Rewind, so net/http marks this non-replayable.
	body := io.NopCloser(bytes.NewReader(make([]byte, 4096)))
	req, _ := http.NewRequest("POST", url, body)
	req.ContentLength = 4096
	r, err := c.Do(req)
	if err != nil {
		return "", err
	}
	defer r.Body.Close()
	io.Copy(io.Discard, r.Body)
	return r.Status, nil
}

func main() {
	url := "http://" + os.Getenv("IP") + ":8081/v1/chat/completions"
	tr := http.DefaultTransport.(*http.Transport).Clone()
	tr.IdleConnTimeout = 30 * time.Second // scaled stand-in for Go default 90s
	c := &http.Client{Transport: tr}
	if _, err := post(c, url); err != nil {
		fmt.Printf("UNEXPECTED first request failed: %v\n", err)
		os.Exit(2)
	}
	time.Sleep(25 * time.Second) // past a 20s proxy keep-alive, inside the 30s pool
	if s, err := post(c, url); err != nil {
		fmt.Printf("GO_FAILED %v\n", err)
	} else {
		fmt.Printf("GO_OK %s\n", s)
	}
}
'
run_go() {
  local ip; ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' psv-pod)
  docker run --rm --network $NET -e IP="$ip" -e SRC="$GO_SRC" golang:1.23-alpine sh -c \
    'mkdir -p /a && cd /a && printf "%s\n" "$SRC" > main.go && go mod init a >/dev/null 2>&1 && go run main.go' 2>&1 | grep -v '^go:'
}
run_raw() {
  local ip; ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' psv-pod)
  docker run --rm --network $NET -e IP="$ip" python:3.12-alpine sh -c '
cat > /c.py <<EOF
import socket, time, os
def req(s):
    s.sendall(b"POST /v1/x HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\nConnection: keep-alive\r\n\r\nhi")
    return s.recv(4096)
s = socket.create_connection((os.environ["IP"], 8081), timeout=60)
assert b" 200 " in req(s)
time.sleep(25)
try:
    r = req(s)
    print("RAW_OK" if b" 200 " in r else ("RAW_CLOSED" if r == b"" else "RAW_ODD"))
except Exception as e:
    print("RAW_ERROR %s" % e)
EOF
python /c.py'
}

echo "=== old behaviour: no timeout http-keep-alive (falls back to 20s) ==="
start_pod "" || exit 1
raw=$(run_raw); go=$(run_go)
echo "    raw socket (no client retry): $raw"
echo "    go client   (has retry)     : $go"
case "$raw" in
  RAW_CLOSED) echo "    NOTE  proxy DID close the idle connection, as suspected" ;;
  RAW_OK)     echo "    NOTE  proxy kept it open even without the directive" ;;
esac
case "$go" in
  GO_OK*) echo "    NOTE  Go still succeeded: it retries a dead pooled connection," ;;
esac
echo "          which is why this alone does not explain the production error."

echo
echo "=== current config: timeout http-keep-alive 10m ==="
start_pod "  timeout http-keep-alive 10m
  timeout tunnel 1h
  option srvtcpka
  option clitcpka
  option redispatch" || exit 1
raw=$(run_raw); go=$(run_go)
echo "    raw socket (no client retry): $raw"
echo "    go client   (has retry)     : $go"
# The guard: with the directive, the proxy must NOT close an idle connection
# that is well inside the configured keep-alive window.
if [ "$raw" = "RAW_OK" ]; then
  echo "    PASS  idle connection survived on a bare socket, no client retry needed"
else
  echo "    FAIL  proxy closed an idle connection inside timeout http-keep-alive ($raw)"; rc=1
fi
case "$go" in
  GO_OK*) echo "    PASS  Go client reuse works" ;;
  *)      echo "    FAIL  Go client reuse broke: $go"; rc=1 ;;
esac

echo
[ $rc -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $rc
