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

HAProxy rather than socat because the tunnel flaps: `retries 75` with
`timeout connect 1s` absorbs roughly 75s of downtime, retrying instead of
returning a connection error. `pai-sho` outages observed up to ~60s.

## Adding a port

Both sides must agree. The peer has to expose it, and it has to be listed here.

```yaml
ports:
  - name: llama          # also the Service/container port name, max 15 chars
    port: 8080           # listen port, and by default the peer port
    mode: http           # http | tcp
    comment: optional note rendered into haproxy.cfg

  - name: postgres
    port: 5432
    mode: tcp            # blind byte pipe, no HTTP parsing
```

On the server chart, expose the matching port via `sidecar.exposePorts`.

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

## Verifying

```bash
./verify-config.sh   # renders each case and validates it with `haproxy -c`
```

This runs the real HAProxy binary against the rendered config, which is the only
check that proves the generated config is loadable. Covers single-port,
mixed http+tcp, distinct `targetPort`, and both template-time rejections.

## The identity key, and why persistence matters

`/root/.local/state/pai-sho/key` is a 32-byte private key identifying this
endpoint to its peer. Lose it and the tunnel must be re-enrolled from the peer
side. It lives on a 1Mi PVC.

`persistence.existingClaim` is currently `llama-hmnd-client-state`: the claim
predates the rename and is kept so the identity survived it. Set it to `""` to
have the chart create and own `<fullname>-state` instead.

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
