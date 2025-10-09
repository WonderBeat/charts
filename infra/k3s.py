#!/usr/bin/env python3

from pyinfra import host
from pyinfra.operations import apt, files, server
from pyinfra.facts.server import Command
from pyinfra.facts.files import File, FindInFile


newconf = files.put(
    name="Copy k3s config",
    src=f"templates/{host.name}.k3s.secret",
    dest="/etc/rancher/k3s/config.yaml",
    mode=644,
    _sudo=True,
)

regconf = files.template(
    name="K3S custom registry on localhost",
    src="templates/registry.yaml.j2.secret",
    dest="/etc/rancher/k3s/registries.yaml",
    mode=644,
    _sudo=True,
)

# _ = server.shell(
#     name="drop caches",
#     commands=["crictl rmi --prune"],
#     _sudo=True,
#     _if=[regconf.did_change],
# )


k3s_version_check = host.get_fact(
    Command,
    "k3s --version 2>/dev/null | head -1 | awk '{print $3}' || echo 'not_installed'",
).strip()

k3s_target_version = "v1.33.5+k3s1"

if host.data.get("k8s_master") and k3s_version_check != "not_installed":
    server.shell(
        name="Backup etcd service to home folder",
        commands=[
            "k3s etcd-snapshot save",
        ],
        _if=[lambda: k3s_version_check != k3s_target_version],
        _sudo=True,
    )

# Get system architecture
arch_check = host.get_fact(
    Command, "uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/'"
).strip()

# Determine the correct binary name based on architecture
binary_suffix = "" if arch_check == "amd64" else "-arm64"
download_url = f"https://github.com/k3s-io/k3s/releases/download/{k3s_target_version}/k3s{binary_suffix}"

updated = server.shell(
    name=f"Download and install k3s version {k3s_target_version}",
    commands=[
        f"curl -sfL -o /tmp/k3s {download_url}",
        "chmod --reference=/usr/local/bin/k3s /tmp/k3s 2>/dev/null || chmod +x /tmp/k3s",
        "mv /tmp/k3s /usr/local/bin/k3s",
    ],
    _if=[lambda: k3s_version_check != k3s_target_version],
    _sudo=True,
)

if host.data.get("k8s_master"):
    server.systemd.service(
        name="Restart k3s",
        service="k3s",
        daemon_reload=newconf.changed or regconf.changed or updated.changed,
        running=True,
        restarted=newconf.changed or regconf.changed or updated.changed,
        enabled=True,
        _sudo=True,
    )
else:
    server.systemd.service(
        name="Restart k3s",
        service="k3s-agent",
        daemon_reload=newconf.changed or regconf.changed or updated.changed,
        running=True,
        restarted=newconf.changed or regconf.changed or updated.changed,
        enabled=True,
        _sudo=True,
    )

server.shell(
    name="Clean systemd logs older than 3 days",
    commands=["journalctl --vacuum-time=3d"],
    _sudo=True,
)
