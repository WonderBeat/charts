#!/usr/bin/env bash
# Verify the helmfile-level tunnel port config.
#
# Ports are configured in the helmfiles (both halves: the proxy's `ports` list
# and the server's `sidecar.exposePorts`) so they are visible where deploys
# happen. Two things can go wrong silently, so both are asserted here:
#
#   1. The server release passes `sidecar.exposePorts` from helmfile while
#      secret.yaml separately passes sidecar.ticket/enrollToken. If those maps
#      replaced each other instead of merging, the tunnel would lose its ticket
#      and quietly fail to connect.
#   2. A Helm list value REPLACES the chart default rather than merging, so the
#      helmfile list must be what actually reaches the templates. If it did not,
#      editing helmfile.yaml would appear to do nothing.
#
# Run from this directory. No cluster required.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
SERVER=../llama-hmnd-server
rc=0

echo "=== server: sidecar maps merge (exposePorts AND ticket both survive) ==="
(cd "$SERVER" && helmfile template 2>/dev/null) | python3 -c "
import sys,yaml
sts=[d for d in yaml.safe_load_all(sys.stdin) if d and d.get('kind')=='StatefulSet'][0]
c=[x for x in sts['spec']['template']['spec']['containers'] if x['name']=='tunnel'][0]
env={e['name']:e for e in c['env']}
expose=env.get('PAI_SHO_EXPOSE',{}).get('value')
ticket='valueFrom' in env.get('PAI_SHO_TICKET',{})
print('  PAI_SHO_EXPOSE:',expose)
print('  PAI_SHO_TICKET:','secretKeyRef preserved' if ticket else 'MISSING -> tunnel would not connect')
sys.exit(0 if expose and ticket else 1)
" && echo "  PASS" || { echo "  FAIL"; rc=1; }

echo "=== proxy: helmfile ports reach the templates ==="
helmfile template 2>/dev/null | python3 -c "
import sys,yaml
docs=[d for d in yaml.safe_load_all(sys.stdin) if d]
svc=[d for d in docs if d['kind']=='Service'][0]
cfg=[d for d in docs if d['kind']=='ConfigMap'][0]['data']['haproxy.cfg']
names=[p['name'] for p in svc['spec']['ports']]
fes=[l.split()[1] for l in cfg.splitlines() if l.startswith('frontend')]
print('  service ports    :',names)
print('  haproxy frontends:',fes)
missing=[n for n in names if f'fe-{n}' not in fes]
if missing: print('  MISSING frontends for:',missing)
sys.exit(0 if names and not missing else 1)
" && echo "  PASS" || { echo "  FAIL"; rc=1; }

echo "=== proxy: a helmfile edit propagates (add a tcp port) ==="
cp helmfile.yaml /tmp/_hf.orig
python3 - <<'PY'
p='helmfile.yaml'
s=open(p).read()
s=s.replace("""          # - name: postgres
          #   port: 5432
          #   mode: tcp
          #   comment: postgres wire protocol, must not be HTTP-parsed""",
"""          - name: postgres
            port: 5432
            mode: tcp
            comment: postgres wire protocol, must not be HTTP-parsed""")
open(p,'w').write(s)
PY
helmfile template 2>/dev/null | python3 -c "
import sys,yaml
docs=[d for d in yaml.safe_load_all(sys.stdin) if d]
svc=[d for d in docs if d['kind']=='Service'][0]
cfg=[d for d in docs if d['kind']=='ConfigMap'][0]['data']['haproxy.cfg']
names=[p['name'] for p in svc['spec']['ports']]
fes=[l.split()[1] for l in cfg.splitlines() if l.startswith('frontend')]
modes=sorted({l.strip() for l in cfg.splitlines() if l.strip().startswith('mode ')})
print('  service ports:',names)
print('  frontends    :',fes)
print('  modes        :',modes)
sys.exit(0 if 'postgres' in names and 'fe-postgres' in fes and 'mode tcp' in modes else 1)
" && echo "  PASS: edit propagated, tcp mode rendered" || { echo "  FAIL"; rc=1; }
cp /tmp/_hf.orig helmfile.yaml && rm -f /tmp/_hf.orig
echo "  (helmfile.yaml restored)"

echo
[ $rc -eq 0 ] && echo "HELMFILE PORT CONFIG VERIFIED" || echo "FAILURES ABOVE"
exit $rc
