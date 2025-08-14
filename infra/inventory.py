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
            "multicloud_gateway": False,
            "v2ray": True,
        },
    ),
    (
        "ks2",
        {
            "multicloud_gateway": True,
        },
    ),
    (
        "kesaram",
        {
            "k8s_master": True,
            "multicloud_gateway": False,
        },
    ),
]

oracle_andrey = ["o1", "o2", "o3"]
hezner_eu = ["ks2"]

misc = [
    ("orange", {"keep_alive": True, "awg-address": "10.77.101.38"}),
    ("orange2", {"keep_alive": True, "awg-address": "10.77.101.39"}),
]
