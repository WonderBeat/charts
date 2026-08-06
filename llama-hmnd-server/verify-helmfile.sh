#!/usr/bin/env bash
# Verify the toggle is reachable through the ACTUAL deploy path (helmfile), not
# just via `helm template --set`. Renders each profile the way a deploy would and
# reports the flags that distinguish them.
set -uo pipefail
cd "$(dirname "$0")" || exit 1

for prof in "" 1gpu 2gpu; do
  label=${prof:-"(unset -> default)"}
  echo "=== GPU_PROFILE=$label ==="
  if [ -z "$prof" ]; then unset GPU_PROFILE; else export GPU_PROFILE="$prof"; fi
  helmfile template 2>/dev/null | python3 -c "
import sys,yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d.get('kind')=='StatefulSet':
        t=d['spec']['template']
        for c in t['spec']['containers']:
            if c['name']=='server':
                a=c['args']
                g=lambda f: a[a.index(f)+1] if f in a else None
                print('   model      ', g('-hf').split(':')[-1])
                print('   ctx total  ', g('-c'), '/ parallel', g('--parallel'),
                      '=> per-req', int(g('-c'))//int(g('--parallel')))
                print('   n-cpu-moe  ', g('--n-cpu-moe'))
                print('   split-mode ', g('--split-mode'))
                print('   gpus       ', c['resources']['requests']['nvidia.com/gpu'])
                print('   affinity   ', 'yes' if t['spec'].get('affinity') else 'none')
" || echo "   FAILED to render"
done
