#!/usr/bin/env python3
from pyinfra.operations import apt, files, server

apt.update(name="Update apt repositories", cache_time=3600, _sudo=True, _parallel=True)

apt.upgrade(_sudo=True, _parallel=True)
