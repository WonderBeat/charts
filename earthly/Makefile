.DEFAULT_GOAL := help

help:
	cat README.md

install:
	@helm install earthly -f values.yaml ./
upgrade:
	@helm upgrade earthly -f values.yaml ./
clean:
	@helm delete earthly
