.DEFAULT_GOAL := help

help:
	cat README.md

repo:
	@sh -c "helm repo list | grep -q 'cloudflare' || { helm repo add cloudflare https://cloudflare.github.io/helm-charts && helm repo update; };"

install:
	@make repo
	@helm install argo --namespace default -f values.yaml -f secrets.yaml ./

upgrade:
	@make repo
	@helm upgrade argo --namespace default -f values.yaml -f secrets.yaml ./

clean:
	@helm delete argo --namespace default
