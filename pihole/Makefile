.DEFAULT_GOAL := help

help:
	cat README.md

install:
	@helm install pihole -f values.yaml ./

upgrade:
	@helm upgrade pihole -f values.yaml ./
clean:
	helm delete pihole
