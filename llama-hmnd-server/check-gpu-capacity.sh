#!/usr/bin/env bash
# Can the 2gpu profile actually be scheduled?
#
# The profile requests nvidia.com/gpu: 2 from a single pod. Nodes here carry 8
# GPUs, so this is only a question of what is already claimed. Run this before
# switching profiles to avoid a pod that sits Pending behind a scheduler that
# cannot satisfy it.
set -uo pipefail

kubectl get pods --all-namespaces -o json | python3 -c "
import json,sys,collections
d=json.load(sys.stdin)
used=collections.Counter()
for p in d['items']:
    if p.get('status',{}).get('phase') not in ('Running','Pending'): continue
    n=p['spec'].get('nodeName')
    if not n: continue
    for c in p['spec']['containers']:
        g=(c.get('resources',{}).get('requests') or {}).get('nvidia.com/gpu')
        if g: used[n]+=int(g)

cap={}
import subprocess
nodes=json.loads(subprocess.run(['kubectl','get','nodes','-o','json'],
                 capture_output=True,text=True).stdout)
for n in nodes['items']:
    g=n['status'].get('allocatable',{}).get('nvidia.com/gpu')
    if g: cap[n['metadata']['name']]=int(g)

print(f\"{'node':36s}{'used':>6}{'cap':>5}{'free':>6}\")
fits=[]
for n in sorted(cap):
    u,c=used.get(n,0),cap[n]
    free=c-u
    mark='  <- fits 2gpu' if free>=2 else ''
    if free>=2: fits.append(n)
    print(f'{n:36s}{u:>6}{c:>5}{free:>6}{mark}')
print()
print(f'nodes with >=2 free GPUs : {len(fits)}')
print(f'2gpu profile schedulable : {bool(fits)}')
sys.exit(0 if fits else 1)
"
