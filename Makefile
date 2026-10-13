ENV       ?= dev
ENV_DIR   := envs/$(ENV)
ROOTS     := bootstrap envs/dev envs/prod

.PHONY: help fmt fmt-check validate lint scan plan clean

help: ## Show available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

fmt: ## Format all Terraform files
	terraform fmt -recursive

fmt-check: ## Fail if any file is not formatted
	terraform fmt -check -recursive

validate: ## init (no backend) + validate every root module
	@for d in $(ROOTS); do \
		echo "==> $$d"; \
		terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
		terraform -chdir=$$d validate || exit 1; \
	done

lint: ## Run tflint on every root module (and the local modules they call)
	tflint --init --config="$(CURDIR)/.tflint.hcl"
	@for d in $(ROOTS); do \
		echo "==> $$d"; \
		tflint --chdir=$$d --config="$(CURDIR)/.tflint.hcl" || exit 1; \
	done

scan: ## Static security scan with Checkov
	checkov -d . --framework terraform --quiet

plan: ## Plan one environment: make plan ENV=dev (needs backend.hcl + terraform.tfvars)
	terraform -chdir=$(ENV_DIR) init -backend-config=backend.hcl -input=false
	terraform -chdir=$(ENV_DIR) plan -out=tfplan

clean: ## Remove local .terraform directories and plan files
	find . -type d -name .terraform -prune -exec rm -rf {} +
	find . -type f -name tfplan -delete
