#!/usr/bin/env python3

oracle_denis = [
    ("oracle", {"multicloud_gateway": True}),
    ("nagi", {"k8s_master": True, "multicloud_gateway": True}),
    ("kesaram", {"k8s_master": True, "multicloud_gateway": True}),
]

oracle_andrey = ["o1", "o2", "o3"]
hezner_eu = ["ks2"]
hezner_us = ["usa1"]


# SSH config
#
# Host oracle
#     HostName 158.101.197.223
#     User ubuntu

# Host o1
#     HostName 129.151.192.84
#     User ubuntu

# Host o2
#     HostName 129.151.195.73
#     User ubuntu

# Host o3
#     HostName 129.151.200.240
#     User ubuntu

# Host o4
#     HostName 207.127.92.17
#     User ubuntu

# Host kesaram
#     # HostName 10.69.101.44
#     HostName 193.123.56.221
#     User ubuntu

# Host usa1
#     HostName 5.161.98.176
#     User root

# Host nagi
#     HostName 143.47.182.88
#     User ubuntu

# Host ks1
#     HostName 135.181.35.17
#     User root

# Host ks2
#     HostName 135.181.155.159
#     User root

# Host ks3
#     HostName 65.109.226.136
#     User root
