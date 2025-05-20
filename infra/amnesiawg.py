#!/usr/bin/env python3

from pyinfra import host
from pyinfra.facts.server import Command, Hostname
from pyinfra.operations import apt, files, server, systemd
from pyinfra.facts.files import File, FindInFile
from pyinfra import logger
import os

apt.repo(
    "deb https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu/ jammy main", _sudo=True
)

apt.packages(
    name="amnesia wg",
    packages=[
        "software-properties-common",
        "python3-launchpadlib",
        "gnupg2",
        "linux-headers-$(uname -r)",
        "amneziawg",
    ],
    _sudo=True,
)

# clone wg config details
wg_config = "/etc/wireguard/wg0.conf"
wg_config_attrs = host.get_fact(File, wg_config, _sudo=True)

assert wg_config_attrs is not None

wg_private_key = host.get_fact(
    Command,
    "grep -E '^PrivateKey\s?=\s?.+$' /etc/wireguard/awg0.conf | rev | xargs | cut -d ' ' -f1 |rev | xargs",
    _sudo=True,
)
wg_public_key = host.get_fact(
    Command,
    "echo '%s' |wg pubkey" % wg_private_key,
    _sudo=True,
).strip()

wg_address = (
    host.get_fact(
        Command,
        "grep -E '^Address\s?=\s?.+$' /etc/wireguard/awg0.conf | rev | xargs | cut -d '=' -f1 | rev | xargs",
        _sudo=True,
    ).strip()
    or host.data.get("awg-address")
)


new_conf = files.template(
    name="server config",
    src="templates/awg0.conf.j2.secret",
    dest="/etc/amnezia/amneziawg/awg0.conf",
    _sudo=True,
    private_key=wg_private_key,
    keepalive=
    mode=700,
    address=wg_address,
)

new_systemd = files.put(
    name="systemd service",
    src="templates/awg0.service",
    dest="/etc/systemd/system/multi-user.target.wants/awg-quick@awg0.service",
    mode=700,
    create_remote_dir=True,
    _sudo=True,
)

systemd.service(
    service="awg-quick@awg0.service",
    restarted=new_conf.changed or new_systemd.changed,
    enabled=True,
    running=True,
    daemon_reload=new_systemd.changed,
    _sudo=True,
)
