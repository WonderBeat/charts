.DEFAULT_GOAL := help

help:
	cat README.md

repo:
	@sh -c "helm repo list | grep -q 'tailzip' || { helm repo add tailzip https://tailzip.github.io/dnscrypt-proxy/ && helm repo update; };"

install:
	@make repo
	@helm install dnscrypt -f values.yaml tailzip/dnscrypt-proxy

upgrade:
	@make repo
	@helm upgrade dnscrypt -f values.yaml tailzip/dnscrypt-proxy
clean:
	helm delete dnscrypt
