#!/usr/bin/env python3

from pyinfra import host
from pyinfra.operations import apt, files, systemd

apt.packages(
    name="Ensure installed",
    packages=["nebula"],
    _sudo=True,
)

files.directory(
    name="Ensure Nebula config directory exists",
    path="/etc/nebula",
    mode="700",
    user="root",
    group="root",
    _sudo=True,
)

files.put(
    name="Upload CA certificate",
    src="../nebula/secretdir/ca.crt",
    dest="/etc/nebula/ca.crt",
    mode="600",
    user="root",
    group="root",
    _sudo=True,
)

files.put(
    name="Upload host certificate",
    src=f"../nebula/secretdir/{host.name}.crt",
    dest="/etc/nebula/host.crt",
    mode="600",
    user="root",
    group="root",
    _sudo=True,
)

files.put(
    name="Upload host key",
    src=f"../nebula/secretdir/{host.name}.key",
    dest="/etc/nebula/host.key",
    mode="600",
    user="root",
    group="root",
    _sudo=True,
)

files.template(
    name="Create Nebula config file",
    src="templates/nebula_config.yaml.j2",
    dest="/etc/nebula/config.yaml",
    mode="600",
    user="root",
    group="root",
    _sudo=True,
)

files.template(
    name="Create systemd service file",
    src="templates/nebula.service.j2",
    dest="/etc/systemd/system/nebula.service",
    mode="644",
    user="root",
    group="root",
    _sudo=True,
)

systemd.service(
    name="Enable and start Nebula service",
    service="nebula",
    running=True,
    enabled=True,
    daemon_reload=True,
    _sudo=True,
)
