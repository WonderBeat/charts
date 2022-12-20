.DEFAULT_GOAL := help

help:
	cat README.md

install:
	@helm install dnsmasq -f values.yaml ./

upgrade:
	@helm upgrade dnsmasq -f values.yaml ./
clean:
	helm delete dnsmasq
