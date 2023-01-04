.DEFAULT_GOAL := help

help:
	cat README.md

repo:
	@sh -c "helm repo list | grep -q 'juicefs' || { helm repo add juicefs https://juicedata.github.io/charts/ && helm repo update; };"

install-keydb:
	@helmfile apply

install:
	@make repo
	@helm install juicefs-csi-driver juicefs/juicefs-csi-driver --create-namespace -n juicefs -f values.yaml -f secret.yaml

upgrade:
	@make repo
	@helm upgrade juicefs-csi-driver --namespace juicefs -f values.yaml -f secret.yaml juicefs/juicefs-csi-driver

clean:
	helm delete juicefs-csi-driver --namespace juicefs
