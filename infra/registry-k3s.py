#!/usr/bin/env python3

from pyinfra.operations import apt, files, server
from pyinfra.facts.files import File, FindInFile


newconf = files.template(
    name="K3S custom registry on localhost",
    src="templates/registry.yaml.j2.secret",
    dest="/etc/rancher/k3s/registries.yaml",
    mode=644,
    _sudo=True,
)

server.systemd.service(
    name="Restart k3s",
    service="k3s-agent",
    daemon_reload=newconf.changed,
    running=True,
    restarted=True,
    enabled=True,
    _sudo=True,
)

# dragonfly-scheduler-0.scheduler.db.svc.cluster.local
