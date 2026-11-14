SHELL := /bin/bash
CHART := charts/podinfo-slo
PROMTOOL ?= promtool

.PHONY: help infra kubeconfig platform load test-rules lint destroy

help: ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

infra: ## create VPC + EKS (needs infra/backend.hcl and infra/terraform.tfvars)
	cd infra && terraform init -backend-config=backend.hcl && terraform apply

kubeconfig: ## point kubectl at the cluster
	$$(cd infra && terraform output -raw configure_kubectl)

platform: ## install kube-prometheus-stack and the podinfo SLO chart
	./platform/install.sh

load: ## 5 minutes of traffic, 5% of it hitting a 500 endpoint so the burn-rate alerts fire
	kubectl -n demo run load --rm -i --restart=Never --image=curlimages/curl:8.11.1 -- \
	  sh -c 'end=$$(( $$(date +%s) + 300 )); while [ $$(date +%s) -lt $$end ]; do \
	    for i in $$(seq 1 19); do curl -s -o /dev/null http://podinfo:9898/; done; \
	    curl -s -o /dev/null http://podinfo:9898/status/500; done'

test-rules: ## render the SLO rules and run the promtool unit tests
	helm template podinfo $(CHART) -s templates/slo-rules.yaml \
	  | yq '{"groups": .spec.groups}' > tests/rendered-rules.yaml
	$(PROMTOOL) check rules tests/rendered-rules.yaml
	cd tests && $(PROMTOOL) test rules slo_rules_test.yaml

lint: ## terraform fmt/validate and helm lint
	terraform -chdir=infra fmt -check
	terraform -chdir=infra init -backend=false -input=false >/dev/null
	terraform -chdir=infra validate
	helm lint $(CHART) --strict

destroy: ## tear everything down
	helm -n demo uninstall podinfo || true
	helm -n monitoring uninstall kps || true
	cd infra && terraform destroy
