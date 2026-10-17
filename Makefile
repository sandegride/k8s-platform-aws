TF_DIR := terraform

.PHONY: init plan apply destroy kubeconfig bootstrap addons lint

init:
	terraform -chdir=$(TF_DIR) init -backend-config=backend.hcl

plan:
	terraform -chdir=$(TF_DIR) plan -out=tfplan

apply:
	terraform -chdir=$(TF_DIR) apply tfplan

destroy:
	terraform -chdir=$(TF_DIR) destroy

kubeconfig:
	$$(terraform -chdir=$(TF_DIR) output -raw kubeconfig_command)

bootstrap:
	kubectl apply -f k8s/storageclass-gp3.yaml

addons:
	helmfile apply
	kubectl apply -f k8s/cluster-issuers.yaml
	kubectl apply -f k8s/kyverno-policies.yaml

lint:
	terraform -chdir=$(TF_DIR) fmt -check -recursive
	terraform -chdir=$(TF_DIR) validate
	helmfile lint
