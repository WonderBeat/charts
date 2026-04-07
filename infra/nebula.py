#!/usr/bin/env python3

from pyinfra import host
from pyinfra.operations import apt, files, systemd, server
from pyinfra.facts.server import LinuxDistribution

# Determine user based on OS
nebula_user = (
    "nebula-mesh"
    if "nix" in host.get_fact(LinuxDistribution)["name"].lower()
    else "root"
)

files.directory(
    name="Ensure Nebula config directory exists",
    path="/etc/nebula",
    mode="700",
    user=nebula_user,
    group="root",
    _sudo=True,
)

files.put(
    name="Upload CA certificate",
    src="../nebula/secretdir/ca.crt",
    dest="/etc/nebula/ca.crt",
    mode="600",
    user=nebula_user,
    group="root",
    _sudo=True,
)

files.put(
    name="Upload host certificate",
    src=f"../nebula/secretdir/{host.name}.crt",
    dest="/etc/nebula/host.crt",
    mode="600",
    user=nebula_user,
    group="root",
    _sudo=True,
)

files.put(
    name="Upload host key",
    src=f"../nebula/secretdir/{host.name}.key",
    dest="/etc/nebula/host.key",
    mode="600",
    user=nebula_user,
    group="root",
    _sudo=True,
)

if (
    "nix"
    not in host.get_fact(
        LinuxDistribution,
    )["name"].lower()
):
    # For Linux systems, download and install Nebula manually
    nebula_version = "v1.9.7"

    # Detect architecture and download appropriate Nebula binary
    server.shell(
        name="Detect architecture and download Nebula",
        commands=[
            """
            ARCH=$(uname -m)
            if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
                ARCH_SUFFIX="arm64"
            else
                ARCH_SUFFIX="amd64"
            fi
            echo "Detected architecture: $ARCH_SUFFIX"
            wget "https://github.com/slackhq/nebula/releases/download/v1.9.7/nebula-linux-${ARCH_SUFFIX}.tar.gz" -O "/tmp/nebula-linux-${ARCH_SUFFIX}.tar.gz"
            """
        ],
        _sudo=True,
    )

    server.shell(
        name="Extract Nebula archive to /tmp",
        commands=[
            """
            ARCH=$(uname -m)
            if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
                ARCH_SUFFIX="arm64"
            else
                ARCH_SUFFIX="amd64"
            fi
            tar -xzf "/tmp/nebula-linux-${ARCH_SUFFIX}.tar.gz" -C /tmp
            """
        ],
        _sudo=True,
    )

    server.shell(
        name="Install Nebula binaries to /usr/local/bin",
        commands=[
            "mv /tmp/nebula /usr/local/bin/",
            "mv /tmp/nebula-cert /usr/local/bin/",
        ],
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

files.template(
    name="Create Nebula config file",
    src=f"templates/{host.name}.nebula.secret",
    dest="/etc/nebula/config.yaml",
    mode="600",
    user="root",
    group="root",
    _sudo=True,
)
