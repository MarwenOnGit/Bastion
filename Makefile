# Bastion landing zone: local developer targets.
# None of these targets talk to Azure, except bootstrap-plan and compliance, which you run
# on your laptop after `az login`.

STACKS      := governance network workload
ALL_STACKS  := bootstrap $(STACKS)
TF          ?= terraform

.PHONY: help fmt fmt-check validate lint checkov opa test static docs compliance bootstrap-plan bootstrap-apply clean

help:
	@echo "fmt            terraform fmt -recursive"
	@echo "fmt-check      fail if formatting is needed"
	@echo "validate       terraform init -backend=false + validate for every stack"
	@echo "lint           tflint on every stack"
	@echo "checkov        checkov static scan of infra/"
	@echo "opa            conftest verify (unit tests for the plan rules)"
	@echo "static         pytest tests/static"
	@echo "test           fmt-check + lint + checkov + opa + static"
	@echo "docs           documentation checks (no em dashes, links to existing files)"
	@echo "compliance     bastion-baseline compliance report (read-only, needs az login)"
	@echo "bootstrap-plan terraform plan for infra/bootstrap (run on your laptop, needs az login)"

fmt:
	$(TF) fmt -recursive infra

fmt-check:
	$(TF) fmt -recursive -check -diff infra

validate:
	@for s in $(ALL_STACKS); do \
		echo "== $$s"; \
		$(TF) -chdir=infra/$$s init -backend=false -input=false >/dev/null && \
		$(TF) -chdir=infra/$$s validate || exit 1; \
	done

lint:
	tflint --init --config "$(CURDIR)/.tflint.hcl"
	@for s in $(ALL_STACKS); do \
		echo "== $$s"; \
		tflint --chdir=infra/$$s --config "$(CURDIR)/.tflint.hcl" || exit 1; \
	done

checkov:
	checkov --directory infra --config-file .checkov.yaml

opa:
	conftest verify --policy opa

static:
	python3 -m pytest -q tests/static

docs:
	python3 -m pytest -q tests/static/test_docs.py

test: fmt-check lint checkov opa static

compliance:
	tests/policy/compliance-report.sh

bootstrap-plan:
	$(TF) -chdir=infra/bootstrap init -input=false
	$(TF) -chdir=infra/bootstrap plan -input=false -out=bootstrap.tfplan

bootstrap-apply:
	$(TF) -chdir=infra/bootstrap apply -input=false bootstrap.tfplan
