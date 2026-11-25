# pai-sho-proxy

Routes Kubernetes Services to ports exposed by a [pai-sho](https://github.com/cablehead/pai-sho)
tunnel peer.

Previously `llama-hmnd-client`, which hardcoded a single llama.cpp port. It is
now a general router: any number of ports, each in `http` or `tcp` mode.

## How it works

```
Service :8080  ->  HAProxy (pod IP :8080)  ->  pai-sho (127.0.0.1:8080)  ->  peer
```

The remote peer exposes a port (`pai-sho daemon -e 8080`). This daemon then
forwards that port on **127.0.0.1 only** (hardcoded in pai-sho's `tunnel.rs`,
regardless of `--host`). Kubernetes Services cannot target a pod's loopback, so
HAProxy bridges pod-IP to loopback.

HAProxy rather than socat because the tunnel flaps: `retries` with a short
`timeout connect` absorbs roughly one second of downtime per retry, retrying
instead of returning a connection error. `pai-sho` outages observed up to ~60s,
and `proxy.retries: 5` covers ~5s of that; raise it if outages get longer.

## Concurrency: why the backend has `maxconn`

This is the setting that made the path stop feeling unstable, so it is worth
understanding before changing anything here.

The llama server runs `--parallel 1`, so `n_slots = 1` and it serves **one
request at a time**. It still *accepts* every connection offered, which means
extra requests wait invisibly inside the server. Measured over 48h of production
traffic through this proxy (284 requests):

| in flight | requests | mean TTFB | max TTFB |
|---|---|---|---|
| 1 | 190 | 1.5s | 30.2s |
| 2 | 76 | 18.0s | 109.1s |
| 4 | 15 | 67.7s | 107.0s |
| 6 | 2 | 83.9s | 136.9s |

Every client abort in that window (8 of 284) was one of these slow requests, and
3 exceeded 100s, which is where callers and Cloudflare give up. There were **zero
5xx, zero server-side aborts, and zero retries**: nothing was actually breaking.
The tunnel was up for 5h straight with no flap. It was a queueing problem wearing
the costume of a connection problem.

HAProxy's own queue time was `0ms` for all 284 requests, which is the tell: it
was not throttling anything, it was feeding a one-slot server in parallel.

`proxy.backendMaxconn: 1` admits one request at a time and queues the rest in
HAProxy, where the wait is bounded by `timeouts.queue`, visible in the `Tw` log
field, and FIFO. Verified on the live release with 4 concurrent generations:

```
Tw(queue)=      0ms  Tr(ttfb)=   3110ms  srv_conn=0  status=200
Tw(queue)=   3087ms  Tr(ttfb)=    774ms  srv_conn=0  status=200
Tw(queue)=   3855ms  Tr(ttfb)=    775ms  srv_conn=0  status=200
Tw(queue)=   4623ms  Tr(ttfb)=    774ms  srv_conn=0  status=200
```

TTFB collapses to a stable 774ms once requests are served one at a time, instead
of every request degrading together. Total time for the last request is
unchanged, as it must be: the server is the bottleneck either way. What changes
is that no request is starved, and the wait is now measurable.

**Keep `backendMaxconn` equal to the server's `--parallel`.** Higher restores the
invisible queue; lower leaves slots idle. Both halves are in the helmfiles.

### Was it SSE breaking?

No, and this was the first hypothesis. Worth recording because the evidence is
easy to misread:

- `gomodel` logged 2 `client_disconnected` and 2 `stream_error` in 48h. The
  `client_disconnected` entries are callers hanging up, mostly on requests that
  had already run over 100s.
- One `stream_error` read `use of closed network connection`. That is the idle
  keep-alive race described below, not a mid-stream failure.
- A tunnel that dies mid-stream truncates the SSE response *without an error*:
  the client sees a clean EOF and a short generation. `verify-backend-queue.sh`'s
  sibling experiments confirmed this is unavoidable at the proxy layer, since
  the response has already started and cannot be replayed. Recovery for that
  case belongs in the client, as a resumed or retried request.

## Idle keep-alive: who closes first

`timeout http-keep-alive` was unset, so HAProxy fell back to
`timeout http-request` (30s) for idle client connections, while Go's default
`http.Transport` keeps one pooled for `IdleConnTimeout` = 90s. For 60s a client
could hold a socket HAProxy had already closed, and writing to it fails with
`use of closed network connection`.

`./verify-keepalive-race.sh` proves the close really happened (a bare socket sees
`RAW_CLOSED`) **and** that a Go client survives it anyway, because it retries on
a fresh connection. So this was one real error in 48h, not the instability. It is
fixed to `10m` because it costs nothing and the failure it removes is confusing
out of proportion to its frequency.

The rule: **HAProxy's keep-alive must outlast every client's idle pool**, so the
client is the party that closes. Only the client knows whether it is about to
reuse the socket. `_helpers.tpl` fails the render if this drops below either
`httpRequest` or Go's 90s.


## Adding a port

Both sides must agree. The peer has to expose it, and it has to be listed here.

Edit `helmfile.yaml`, not the chart's `values.yaml`. The deployed list lives in
the helmfile so it is visible at the deploy entry point, and because a Helm list
value **replaces** the chart default wholesale rather than merging, whatever
helmfile passes is exactly what runs. Editing `values.yaml` alone does nothing.

```yaml
# pai-sho-proxy/helmfile.yaml
      - ports:
          - name: llama          # also the Service/container port name, max 15 chars
            port: 8080           # listen port, and by default the peer port
            mode: http           # http | tcp
            comment: optional note rendered into haproxy.cfg

          - name: postgres
            port: 5432
            mode: tcp            # blind byte pipe, no HTTP parsing
```

```yaml
# sglang-hmnd-server/helmfile.yaml.gotmpl  <- the other half
      - sidecar:
          exposePorts: "8080,5432"
```

A port listed on the proxy but not exposed on the peer binds locally and then
refuses connections, which surfaces as HAProxy retrying for ~5s (proxy.retries) and then 503.

`mode` picks the HAProxy proxying mode:

| | `http` | `tcp` |
|---|---|---|
| logging | `option httplog` | `option tcplog` |
| streaming | unbuffered, SSE-safe | inherently a stream |
| `httpRequest` timeout | applied | n/a |
| use for | REST, SSE, anything HTTP | databases, SSH, TLS passthrough |

An invalid mode fails at template time rather than producing a config that
crashloops the pod.

`proxy.healthPort` (8081) serves HAProxy's own `/healthz` and must not collide
with any entry in `ports`. It is deliberately not in the Service: probes must
succeed while the tunnel is down, so the pod is not restarted during an outage.

Applying a port change recreates the pod (`strategy: Recreate`, see below), so
expect a brief outage.

## Verifying

```bash
./verify-helmfile.sh                      # port config in helmfile takes effect
./verify-config.sh                        # render + `haproxy -c` on each case
./verify-backend-queue.sh                 # concurrency cap improves the tail
./verify-keepalive-race.sh                # idle connections stay reusable
API_KEY=<key> ./verify-runtime.sh         # traffic really flows on an added port
API_KEY=<key> ./verify-live-queue.sh 4    # the DEPLOYED proxy really queues
```

`verify-backend-queue.sh` and `verify-keepalive-race.sh` need only docker, and
each one first demonstrates the OLD behaviour before asserting the new one. That
ordering is deliberate: a test that only checks the fixed config would pass just
as happily against a config where the setting does nothing.

`verify-live-queue.sh` is the one that closes the loop, because it reads
HAProxy's own log from the running pod: `srv_conn` must stay within
`backendMaxconn`, and excess requests must show non-zero `Tw` queue time.

`verify-helmfile.sh` guards the two silent failure modes of configuring ports at
the helmfile level: that the server's `sidecar.exposePorts` merges with
`secret.yaml`'s `sidecar.ticket` instead of clobbering it (a lost ticket means
the tunnel just never connects), and that the helmfile `ports` list actually
reaches the templates. Needs no cluster.

`verify-config.sh` runs the real HAProxy binary against the rendered config,
which is the only check that proves the generated config is loadable. Covers
single-port, mixed http+tcp, distinct `targetPort`, and both template-time
rejections.

`verify-runtime.sh` goes further: it temporarily adds a second port in `tcp`
mode against the live release, confirms HAProxy binds it and that both ports
serve traffic, then reverts. Verified output:

```
haproxy listeners:  10.45.7.120:8080  10.45.7.120:9090  0.0.0.0:8081
PASS  port 8080 answered      (http mode)
PASS  port 9090 answered      (tcp mode)
```

It tests from inside the pod against the pod IP on purpose. HAProxy binds the
pod IP rather than `0.0.0.0` so pai-sho keeps loopback, and an earlier version of
this test failed misleadingly by pointing a `tcp` backend at HAProxy's own health
frontend, which binds `0.0.0.0:8081` and so is not reachable on `127.0.0.1`.

## Upgrading pai-sho

Two things have bitten us here. Both now have a check that runs without a
cluster.

**The version is pinned once, not written into a URL.** A release URL repeats
the version in the tag path *and* the filename:

```
.../releases/download/v0.4.1/pai-sho-v0.4.1-linux-amd64.tar.gz
                      ^^^^^^          ^^^^^^
```

Bumping only the filename produces a URL that 404s, and because the download
happens in the container's command, nothing fails at render or apply time. It
shows up as a crashlooping sidecar with one line of output:

```
wget: server returned error: HTTP/1.1 404 Not Found
```

So both charts derive the URL from `paiSho.version` + `paiSho.arch`
(`sidecar.version` / `sidecar.arch` on the server chart). Bump the version key.
`./verify-pai-sho-version.sh` renders both charts and checks the URL actually
resolves.

**0.4.0 moved where forwarded ports bind.** Peers are now auto-projected onto
their own surface address (`127.0.1.x`) so two peers can serve the same port.
Before 0.4.0 a forwarded port landed on `127.0.0.1`, which is what the HAProxy
backend names. After it, the daemon logs look completely healthy:

```
auto-projected a1c1d947... to 127.0.1.2
bound 127.0.1.2:8080
```

while `server tunnel 127.0.0.1:8080` gets connection refused, so every request
retries for ~5s (proxy.retries) and then 503s. The failure is silent in exactly the place you
would look first.

The tunnel container therefore runs a reconcile loop that repins the peer's
surface to `127.0.0.1` (`paiSho.loopbackPeer` selects which peer, since only one
can own that address). `./verify-loopback-pin.sh` extracts the *rendered*
container script and runs it against a real peer in Docker, asserting the port is
reachable on `127.0.0.1` both initially and after the peer reconnects.

## The identity key, and why persistence matters

`/root/.local/state/pai-sho/key` is a 32-byte private key identifying this
endpoint to its peer. Lose it and the tunnel must be re-enrolled from the peer
side. It lives on a 1Mi PVC.

`persistence.existingClaim` is `llama-hmnd-client-state`, named after a release
that no longer exists. **That name is load-bearing, not leftover.** The claim
holds three files, and only the first is an identity:

| file | what it is |
|---|---|
| `key` | this endpoint's 32-byte private key |
| `key.peers.json` | the enrolled peer's public key and label |
| `key.surfaces.json` | that peer's pinned `127.0.0.1` surface |

Provisioning a fresh claim mints a new keypair *and* drops the enrollment, so
the far side keeps dialling a peer key that no longer exists and logs
`failed to add peer <key>: failed to connect to peer` while looking otherwise
healthy on both ends. To move it, copy all three files first.

Hard-won detail from that rename, worth knowing before renaming again: a rename
cannot be a `helm upgrade`, because a Deployment's `spec.selector` is immutable
and the selector labels change with the release name. It is uninstall plus
install, and **`helm.sh/resource-policy: keep` added to an already-tracked PVC
does not save it**: helm had recorded the claim as release-owned, and uninstall
deleted it anyway. What actually saved the data was patching the PV to
`persistentVolumeReclaimPolicy: Retain` first, which left it `Released` with the
files intact, so a new PVC could be bound to it by `volumeName`.

If you ever need to repeat that:

```bash
# 1. before uninstalling
kubectl patch pv <pv> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
kubectl exec <pod> -c tunnel -- tar -cf - -C /root/.local/state/pai-sho . > backup.tar

# 2. after uninstall, PV is Released; clear the stale claimRef
kubectl patch pv <pv> --type json -p '[{"op":"remove","path":"/spec/claimRef"}]'

# 3. create a PVC with volumeName: <pv>, then verify the key is unchanged
kubectl exec <pod> -c tunnel -- sha256sum /root/.local/state/pai-sho/key
```

The chart's own PVC now ships with `helm.sh/resource-policy: keep` from the
start, which does work for claims helm creates with it.

## Notes

- `strategy: Recreate`, not RollingUpdate: the key is a single ReadWriteOnce
  volume and the daemon owns its socket exclusively, so two pods would deadlock.
- The pinned pai-sho binary is `linux-arm64`, hence the arm64 node affinity. The
  local-path PV is also bound to one node (`oracle2`).
- Clients should use the model name `deepseek-flash`, which the server chart
  pins via `--alias` so it survives quant and profile switches.
