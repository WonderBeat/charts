#!/usr/bin/env python3

oracle_denis = [
    (
        "oracle",
        {
            "multicloud_gateway": True,
        },
    ),
    (
        "nagi",
        {
            "k8s_master": True,
            "multicloud_gateway": True,
            "v2ray": True,
        },
    ),
    (
        "ks2",
        {},
    ),
    (
        "kesaram",
        {"k8s_master": True, "multicloud_gateway": False, "v2ray": True},
    ),
]

oracle_andrey = ["o1", "o2", "o3"]
hetzner_eu = ["ks2", "apol"]

home = ["xpand"]

misc = [
    ("orange", {"keep_alive": True, "awg-address": "10.77.101.38"}),
    ("orange2", {"keep_alive": True, "awg-address": "10.77.101.39"}),
]
