.DEFAULT_GOAL := help

help:
	cat README.md

repo:
	@sh -c "helm repo list | grep -q 'cetic' || { helm repo add cetic https://cetic.github.io/helm-charts && helm repo update; };"

install:
	@make repo
	@helm install nifi --namespace default -f values.yaml cetic/nifi

upgrade:
	@make repo
	@helm upgrade nifi --namespace default -f values.yaml cetic/nifi

clean:
	helm delete nifi --namespace default
