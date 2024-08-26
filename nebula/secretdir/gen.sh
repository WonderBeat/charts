#!/usr/bin/env sh

nebula-cert ca -name "Gladiators" -duration 20000h0m0s
nebula-cert sign -name "lighthouse" -ip "10.88.101.1/24" -duration 19000h0m0s
nebula-cert sign -name "kesaram" -ip "10.88.101.2/24" -duration 19000h0m0s -groups "k8s,gateway" -subnets '0.0.0.0/0'
nebula-cert sign -name "fold" -ip "10.88.101.4/24" -duration 19000h0m0s -groups "mobile,vpn"
nebula-cert sign -name "jonapot" -ip "10.88.101.5/24" -duration 19000h0m0s -groups "k8s"
nebula-cert sign -name "k8s-2" -ip "10.88.101.6/24" -duration 19000h0m0s -groups "k8s,gateway" -subnets '0.0.0.0/0'
nebula-cert sign -name "k8s-usa-1" -ip "10.88.101.7/24" -duration 19000h0m0s -groups "k8s"
nebula-cert sign -name "nagi" -ip "10.88.101.8/24" -duration 19000h0m0s -groups "k8s"
nebula-cert sign -name "oracle1" -ip "10.88.101.9/24" -duration 19000h0m0s -groups "k8s"
nebula-cert sign -name "oracle2" -ip "10.88.101.10/24" -duration 19000h0m0s -groups "k8s"
nebula-cert sign -name "oracle3" -ip "10.88.101.11/24" -duration 19000h0m0s -groups "k8s"
nebula-cert sign -name "xpand" -ip "10.88.101.12/24" -duration 19000h0m0s -groups "k8s,homelab"
nebula-cert sign -name "nasduck" -ip "10.88.101.13/24" -duration 19000h0m0s -groups "homelab"
nebula-cert sign -name "julia-iphone" -ip "10.88.101.14/24" -duration 19000h0m0s -groups "mobile,vpn"
