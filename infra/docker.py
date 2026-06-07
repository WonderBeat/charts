from pyinfra import host
from pyinfra.api import deploy
from pyinfra.operations import apt, server
from pyinfra.facts import util
from pyinfra.facts.server import User


@deploy("Install Docker")
def install_docker():
    apt.update(cache_time=3600, _sudo=True)

    apt.packages(
        name="Install Docker",
        packages=["docker.io", "docker-compose"],
        update=False,
        _sudo=True,
    )
    USERNAME = host.get_fact(
        User,
    )

    server.shell(
        name="Add user to docker group",
        commands=[f"usermod -aG docker {USERNAME}"],
        _sudo=True,
    )

    server.service(
        name="Restart docker service",
        service="docker",
        restarted=True,
        _sudo=True,
    )


install_docker()
