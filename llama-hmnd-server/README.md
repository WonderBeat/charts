# llama-hmnd-server

DeepSeek-V4-Flash on H100s via `llama.cpp` server, exposed through a `pai-sho`
tunnel sidecar.

## Deploying

```bash
helmfile apply                      # 1gpu profile (default)
GPU_PROFILE=2gpu helmfile apply     # 2gpu profile
```

## GPU profiles

`gpuProfile` selects a block under `.Values.profiles`, merged over
`server` / `resources` / `affinity`. Only the deltas live in each profile.

| | `1gpu` | `2gpu` |
|---|---|---|
| GPUs | 1 x H100 80GB | 2 x H100 80GB, one pod |
| model | `UD-IQ4_XS` (127.3 GiB) | `UD-Q8_K_XL` (150.8 GiB) |
| context | 2 slots x 131072 | 2 slots x 262144 |
| `-c` total | 262144 | 524288 |
| `--n-cpu-moe` | 20 | 16 |
| `--split-mode` | (unset) | `layer` |
| host RAM req/lim | 80Gi / 110Gi | 96Gi / 140Gi |
| status | **measured** | **derived, unverified** |

The `1gpu` profile is deployed and in sync: `helmfile diff` reports no changes,
and after the profile refactor the pod came back with `n_slots = 2,
n_ctx_slot = 131072` at 78369/81559 MiB, identical to the pre-refactor figures.

### Why 2 GPUs is one pod, not two

KV lives inside a single `llama.cpp` process. Two 1-GPU pods would give two
independent 131072 pools, not one 262144 pool, so they cannot deliver "2x
context". `--split-mode layer` splits layers *and* KV across both cards, which
is what makes the larger context fit.

Nodes here carry 8 GPUs, so both cards come from one node by construction. The
`requiredDuringScheduling` podAffinity on `kubernetes.io/hostname` is the guard
that keeps this true if `replicaCount` is ever raised above 1: a 2-GPU model
cannot be served by pods that landed on different nodes.

### Before trusting the 2gpu numbers

Capacity is not the blocker: nodes carry 8 GPUs and 11 of them had >=2 free at
the time of writing, including `gpu-014` where the pod currently runs (5/8 used),
so `nvidia.com/gpu: 2` schedules in place without evicting anything. Re-check
before switching:

```bash
./check-gpu-capacity.sh   # exits non-zero if no node can fit a 2-GPU pod
```

What is unverified is the VRAM arithmetic.
These are calculations, not measurements, because a first deploy re-downloads
150.8 GiB. `cpuMoeLayers: 16` carries ~15 GiB of deliberate margin. After a
first deploy, verify as was done for `1gpu`:

```bash
# slots and per-slot context actually granted
kubectl logs dego-dev-throwaway-0 -c server | grep n_slots

# VRAM on BOTH cards, at idle and under load
kubectl exec dego-dev-throwaway-0 -c server -- nvidia-smi \
  --query-gpu=index,memory.used,memory.total --format=csv

# then saturate both slots and re-check; VRAM should not grow, since
# llama.cpp allocates KV and compute buffers up front
```

If both cards show plenty free, lower `cpuMoeLayers` a few layers to buy decode
speed. If it CUDA-OOMs at startup, raise it. A CUDA OOM is loud and happens at
startup; it does not corrupt output.

## Verifying changes

```bash
./verify-profiles.sh      # 12 render checks, incl. live-pod arg equivalence
./verify-helmfile.sh      # toggle works through the real deploy path
./check-gpu-capacity.sh   # a 2-GPU pod can actually be scheduled
```

`verify-profiles.sh` compares args as *sets* of flag/value pairs rather than as
ordered lists. Hardware-dependent flags are rendered after `extraArgs`, so a
plain `helmfile diff` shows a large cosmetic reordering; the script answers
whether behaviour actually changed.

## Tuning notes

The heavily commented `values.yaml` is the real documentation. Two things worth
knowing before touching it:

- **Check the live args before re-tuning.** A tuned sampling config once sat
  undeployed for two days while long-context looping was blamed on sampling
  values that were never in effect. `/props` reports the *server default*, which
  hides this. Use
  `kubectl get pod dego-dev-throwaway-0 -o jsonpath='{.spec.containers[0].args}'`.
- **Client requests override server sampling defaults.** Any client sending
  `temperature` overrides the CLI value, and almost none send `repeat_penalty`.
