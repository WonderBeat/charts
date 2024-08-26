#!/usr/bin/env python3

from pyinfra import host
from pyinfra.facts.server import Command, Hostname
from pyinfra.operations import apt, files, server
from pyinfra.facts.files import File, FindInFile
from pyinfra import logger
import random


apt.packages(
    name="wireguard",
    packages=["wireguard"],
    _sudo=True,
)
wg_config = "/etc/wireguard/wg0.conf"
wg_config_attrs = host.get_fact(File, wg_config, _sudo=True)
hostname = host.get_fact(Hostname)

host_ips = host.get_fact(
    Command,
    "ip -4 -o addr show scope global"
    # Command, "ip -4 -o addr show scope global | awk '{gsub(/\\/.*/," ",$4); print $4}'"
)

public_ip = host.get_fact(Command, "curl https://ipinfo.io/ip")

wg_private_key = None
wg_public_key = None
wg_address = None
if wg_config_attrs:
    wg_private_key = host.get_fact(
        Command,
        "grep -E '^PrivateKey\s?=\s?.+$' /etc/wireguard/wg0.conf | rev | xargs | cut -d ' ' -f1 |rev | xargs",
        _sudo=True,
    )
    wg_public_key = host.get_fact(
        Command,
        "echo '%s' |wg pubkey" % wg_private_key,
        _sudo=True,
    )
    wg_address = host.get_fact(
        Command,
        "grep -E '^Address\s?=\s?.+$' /etc/wireguard/wg0.conf | rev | xargs | cut -d '=' -f1 | rev | xargs",
        _sudo=True,
    )
    # wg_address = wg_address.replace("10.77", "10.69")
    # print(f"wg_address {wg_address}")
    # if wg_address.startswith("10.77"):
    #     print("Err")
else:
    logger.warn("Bootstrapping new peer %s" % hostname)
    wg_private_key = host.get_fact(
        Command,
        "wg genkey",
    )
    wg_public_key = host.get_fact(
        Command,
        "echo '%s' |wg pubkey" % wg_private_key,
        _sudo=True,
    )
    random.seed(hash(hostname))
    suffix = random.randrange(2, 255)
    wg_address = "10.69.101.%s" % suffix

assert wg_private_key
assert wg_public_key
assert wg_address
logger.info(
    (
        "[Peer] #{0}\n" + "PublicKey = {1}\n"
        "AllowedIPs = {2}/32\n" + "Endpoint = {3}:6969\n"
    ).format(hostname, wg_public_key, wg_address, public_ip)
)

newconf = files.template(
    name="Wg reconfigure",
    src="templates/wg0.conf.secret",
    dest="/etc/wireguard/wg0.conf",
    private_key=wg_private_key,
    mode=700,
    address=wg_address,
    is_multicloud_gateway=host.data.get("multicloud_gateway"),
    host_ips=host_ips,
    _sudo=True,
)
server.systemd.service(
    name="Restart wireguard",
    service="wg-quick@wg0.service",
    running=False,
    restarted=newconf.changed,
    enabled=False,
    _sudo=True,
)
