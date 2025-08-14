#!/usr/bin/env python3

from pyinfra import host
from pyinfra.operations import apt, files, server

apt.packages(
    name="Ensure installed",
    packages=["nftables", "mtr", "hping3", "net-tools", "tcpdump"],
    _sudo=True,
)

new_conf = files.template(
    name="Generate nftables rules",
    src="templates/nftables.j2.conf.secret",
    dest="/etc/nftables.conf",
    k8s_port_open=(host.data.get("k8s_master") is True),
    v2ray=(host.data.get("v2ray") is True),
    mode=700,
    _sudo=True,
)


server.systemd.service(
    name="Restart nftables",
    service="nftables",
    daemon_reload=new_conf.changed,
    running=True,
    restarted=new_conf.changed,
    enabled=True,
    _sudo=True,
)

server.sysctl(
    "net.ipv4.tcp_rmem",
    "10240 187380 12582912",
    persist=True,
    persist_file="/etc/sysctl.conf",
    _sudo=True,
)

server.sysctl(
    "net.ipv4.tcp_wmem",
    "10240 187380 12582912",
    persist=True,
    persist_file="/etc/sysctl.conf",
    _sudo=True,
)

server.sysctl(
    "net.core.wmem_max",
    "12582912",
    persist=True,
    persist_file="/etc/sysctl.conf",
    _sudo=True,
)
