#!/usr/bin/env python3

from pyinfra.operations import server

server.reboot(delay=10, interval=1, reboot_timeout=300, _sudo=True)
