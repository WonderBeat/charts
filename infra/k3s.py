#!/usr/bin/env python3

from pyinfra import host
from pyinfra.facts.server import Command, Hostname
from pyinfra.operations import apt, files, server
from pyinfra.facts.files import File, FindInFile
from pyinfra import logger

public_ip = host.get_fact(
    Command,
    "curl ipinfo.io/ip",
)

server.shell(
    name="install k3s",
    commands={
        "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.25.3+k3s1  K3S_TOKEN=SECRETtokenk8s sh -s - agent --server https://10.98.39.235:6443 --node-ip 10.69.101.200  --node-external-ip 10.69.101.200 --snapshotter stargz --token %s"
        % token
    },
)
