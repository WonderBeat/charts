#!/usr/bin/env python3
from pyinfra.operations import apt, files, server

apt.update(name="Update apt repositories", cache_time=3600, _sudo=True)

apt.upgrade(_sudo=True, _parallel=True)

server.shell(name="vacuum", commands=["journalctl --vacuum-time=2d"], _sudo=True)
