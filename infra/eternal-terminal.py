#!/usr/bin/env python3

from pyinfra.api import deploy
from pyinfra.operations import apt, server, python


@deploy("Install Eternal Terminal")
def install_eternal_terminal():
    """
    Install Eternal Terminal (et) - a remote shell that automatically reconnects
    without interrupting the session.

    Install steps per https://eternalterminal.dev/install/
    """
    apt.packages(
        name="Install prerequisites",
        packages=["software-properties-common"],
        update=True,
        _sudo=True,
    )

    server.shell(
        name="Add Eternal Terminal PPA",
        commands=[
            "add-apt-repository -y ppa:jgmath2000/et",
        ],
        _sudo=True,
    )

    apt.packages(
        name="Install Eternal Terminal",
        packages=["et"],
        update=True,
        _sudo=True,
    )

    server.service(
        name="Enable and start Eternal Terminal service",
        service="et",
        running=True,
        enabled=True,
        _sudo=True,
    )


install_eternal_terminal()
