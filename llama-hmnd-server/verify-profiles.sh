#!/usr/bin/env bash
#
# Render-time checks for the gpuProfile toggle.
#
# Why this exists: the profile toggle refactor moved hardware-dependent flags
# out of the extraArgs list into structured values, which reorders the rendered
# arg list. A plain `helmfile diff` therefore shows a large, alarming, and
# entirely cosmetic diff. This script compares args as SETS of flag/value pairs
# so "did the deployed behaviour change?" can actually be answered.
#
# Run from this directory:  ./verify-profiles.sh
#
# Checks:
#   1. the profile matching the live pod renders semantically identical args
#   2. 2gpu doubles context, uses Q8_K_XL, requests 2 GPUs, splits across cards
#   3. sampling is identical across profiles (it is hardware-independent)
#   4. the 2gpu podAffinity selector actually matches the chart's own pod labels
#      (a mismatched selector matches nothing and silently fails to co-locate)
#   5. an unknown gpuProfile fails loudly instead of rendering a default
set -uo pipefail
cd "$(dirname "$0")" || exit 1

CHART=./llama-hmnd-server
RELEASE=dego-dev
POD=dego-dev-throwaway-0
LIVE_PROFILE=${LIVE_PROFILE:-1gpu}

render() {
  helm template "$RELEASE" "$CHART" --set "gpuProfile=$1" | python3 -c "
import sys,yaml,json
for d in yaml.safe_load_all(sys.stdin):
    if d and d.get('kind')=='StatefulSet':
        t=d['spec']['template']
        for c in t['spec']['containers']:
            if c['name']=='server':
                print(json.dumps({'args':c['args'],'resources':c.get('resources'),
                                  'affinity':t['spec'].get('affinity'),
                                  'podLabels':t['metadata']['labels']}))
"
}

ONE=$(render "$LIVE_PROFILE") || { echo "FAIL: could not render $LIVE_PROFILE"; exit 1; }
TWO=$(render 2gpu)            || { echo "FAIL: could not render 2gpu"; exit 1; }
LIVE=$(kubectl get pod "$POD" -o jsonpath='{.spec.containers[0].args}' 2>/dev/null)

LIVE_PROFILE="$LIVE_PROFILE" python3 - "$ONE" "$TWO" "$LIVE" <<'PY'
import json,os,sys

def pairs(args):
    """Normalize an llama-server arg list into an order-independent dict."""
    out={}; i=0
    while i < len(args):
        a=args[i]
        if a.startswith('-'):
            if i+1 < len(args) and not args[i+1].startswith('-'):
                out[a]=args[i+1]; i+=2
            else:
                out[a]=True; i+=1
        else:
            out.setdefault('_positional',[]).append(a); i+=1
    return out

one=json.loads(sys.argv[1]); two=json.loads(sys.argv[2])
live=json.loads(sys.argv[3]) if sys.argv[3].strip().startswith('[') else []
p1,p2=pairs(one['args']),pairs(two['args'])
fails=[]

live_profile=os.environ['LIVE_PROFILE']
print(f"=== {live_profile} profile vs LIVE pod ===")
if not live:
    print(f"  SKIP: no live pod {os.environ.get('POD','')} (not an error offline)")
else:
    pl=pairs(live)
    d1={k:v for k,v in p1.items() if pl.get(k)!=v}
    d2={k:v for k,v in pl.items() if p1.get(k)!=v}
    if d1 or d2:
        print(f"  rendered-only: {d1}\n  live-only    : {d2}")
        fails.append("live pod args differ from rendered profile")
    else:
        print(f"  IDENTICAL: behaviour-preserving ({len(p1)} flags)")

print("\n=== 2gpu profile ===")
for k in ['-hf','-c','--parallel','--n-cpu-moe','--split-mode','--tensor-split',
          '--cache-ram','--cache-type-k','--cache-type-v']:
    print(f"  {k:16s} {p2.get(k)}")
print(f"  per-request ctx  {int(p2['-c'])//int(p2['--parallel'])}")

def check(label, ok):
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")
    if not ok: fails.append(label)

print("\n=== checks ===")
check("2gpu context is exactly 2x", int(p2['-c'])==2*int(p1['-c']))
check("2gpu model is Q8_K_XL", 'Q8_K_XL' in p2['-hf'])
check("2gpu splits across both cards", p2.get('--split-mode')=='layer')
check("2gpu requests 2 GPUs",
      two['resources']['requests']['nvidia.com/gpu']==2 and
      two['resources']['limits']['nvidia.com/gpu']==2)
check(f"{live_profile} requests 1 GPU", one['resources']['requests']['nvidia.com/gpu']==1)
check(f"{live_profile} omits --split-mode", '--split-mode' not in p1)
check("sampling identical across profiles",
      all(p1.get(k)==p2.get(k) for k in ['--temp','--top-p','--top-k','--min-p',
          '--repeat-penalty','--repeat-last-n','--jinja','--reasoning-format']))
check("overflow guard on both", p1.get('--no-context-shift') and p2.get('--no-context-shift'))

# The stable alias is the client-facing model name. It must be present and
# IDENTICAL across profiles: switching hardware must not change what
# /v1/models advertises. (llama-server ignores the request's "model" field, so
# this affects discovery/echo only, not routing.)
check("both profiles set --alias", bool(p1.get('--alias')) and bool(p2.get('--alias')))
check("alias is 'deepseek-flash' on both",
      p1.get('--alias')=='deepseek-flash' and p2.get('--alias')=='deepseek-flash')
check("alias is not the quant-specific -hf string",
      p1.get('--alias')!=p1['-hf'] and p2.get('--alias')!=p2['-hf'])

aff=(two.get('affinity') or {}).get('podAffinity',{}).get(
     'requiredDuringSchedulingIgnoredDuringExecution',[])
check("2gpu has required podAffinity", bool(aff))
if aff:
    sel=aff[0]['labelSelector']['matchLabels']
    check("affinity selector matches own pod labels",
          all(two['podLabels'].get(k)==v for k,v in sel.items()))
    check("affinity topology is node", aff[0]['topologyKey']=='kubernetes.io/hostname')

print()
if fails:
    print("FAILED:"); [print("  -",f) for f in fails]; sys.exit(1)
print("ALL CHECKS PASSED")
PY
rc=$?

echo
echo "=== unknown profile must fail loudly ==="
if helm template "$RELEASE" "$CHART" --set gpuProfile=4gpu >/dev/null 2>/tmp/_gp.err; then
  echo "  FAIL: unknown profile rendered instead of erroring"; rc=1
else
  echo "  PASS: $(grep -o 'gpuProfile .*' /tmp/_gp.err | head -1)"
fi
rm -f /tmp/_gp.err
exit $rc
