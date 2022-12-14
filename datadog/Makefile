.DEFAULT_GOAL := help

help:
	cat README.md

repo:
	@sh -c "helm repo list | grep -q 'datadog' || { helm repo add datadog https://helm.datadoghq.com && helm repo update; };"

install:
	@make repo
	@helm install datadog --namespace default -f values.yaml datadog/datadog

upgrade:
	@make repo
	@helm upgrade datadog --namespace default -f values.yaml datadog/datadog

clean:
	helm delete datadog --namespace default
