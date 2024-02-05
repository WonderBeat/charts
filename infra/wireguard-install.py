#!/usr/bin/env python3

from pyinfra import host
from pyinfra.facts.server import Command, Hostname
from pyinfra.operations import apt, files, server
from pyinfra.facts.files import File, FindInFile
from pyinfra import logger
import random


apt.packages(
    name="Ensure installed",
    packages=["wireguard"],
    _sudo=True,
)
