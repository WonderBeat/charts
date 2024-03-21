#!/usr/bin/env python3

from pyinfra.operations import apt, files, server, systemd

apt.packages(
    name="Ensure installed",
    packages=["ntp"],
    _sudo=True,
)

systemd.service(
    name="Start NTP daemon",
    service="ntp.service",
    running=True,
    restarted=True,
    enabled=True,
    _sudo=True,
)
