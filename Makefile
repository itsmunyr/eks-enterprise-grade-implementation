# Makefile for Laravel DevOps project

.PHONY: help
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Docker commands
.PHONY: build
build: ## Build Docker image
	docker build -t laravel-app -f docker/app/Dockerfile .

.PHONY: build-dev
build-dev: ## Build development Docker image
	docker build -t laravel-app:dev -f Dockerfile.dev .

.PHONY: up
up: ## Start local environment with docker-compose
	docker-compose up -d

.PHONY: down
down: ## Stop local environment
	docker-compose down

.PHONY: logs
logs: ## Show container logs
	docker-compose logs -f

.PHONY: shell
shell: ## Access application shell
	docker-compose exec app sh

# Terraform commands
.PHONY: tf-init
tf-init: ## Initialize Terraform
	cd terraform && terraform init

.PHONY: tf-plan
tf-plan: ## Plan Terraform changes
	cd terraform && terraform plan -var-file=environments/$(ENV)/terraform.tfvars

.PHONY: tf-apply
tf-apply: ## Apply Terraform changes
	cd terraform && terraform apply -var-file=environments/$(ENV)/terraform.tfvars

.PHONY: tf-destroy
tf-destroy: ## Destroy Terraform resources
	cd terraform && terraform destroy -var-file=environments/$(ENV)/terraform.tfvars

# Kubernetes commands
.PHONY: k8s-context
k8s-context: ## Update kubeconfig for EKS
	aws eks update-kubeconfig --name laravel-eks-$(ENV) --region $(AWS_REGION)

.PHONY: k8s-deploy
k8s-deploy: ## Deploy application with Helm
	helm upgrade --install laravel-app ./helm/charts/laravel-app \
		--namespace laravel-$(ENV) \
		--create-namespace \
		--values ./helm/values/$(ENV).yaml

.PHONY: k8s-status
k8s-status: ## Check deployment status
	kubectl get pods -n laravel-$(ENV)
	kubectl get svc -n laravel-$(ENV)

.PHONY: k8s-logs
k8s-logs: ## Show pod logs
	kubectl logs -f -l app=laravel -n laravel-$(ENV)

# Testing commands
.PHONY: test
test: ## Run all tests
	./vendor/bin/phpunit

.PHONY: test-unit
test-unit: ## Run unit tests
	./vendor/bin/phpunit --testsuite=Unit

.PHONY: test-feature
test-feature: ## Run feature tests
	./vendor/bin/phpunit --testsuite=Feature

.PHONY: lint
lint: ## Run code linting
	./vendor/bin/phpcs --standard=PSR12 app/
	./vendor/bin/php-cs-fixer fix --dry-run --diff

.PHONY: lint-fix
lint-fix: ## Fix code style
	./vendor/bin/php-cs-fixer fix

# Security commands
.PHONY: security-scan
security-scan: ## Run security scan on Docker image
	trivy image laravel-app:latest

.PHONY: composer-audit
composer-audit: ## Check for vulnerable dependencies
	composer audit

# Utility commands
.PHONY: clean
clean: ## Clean build artifacts
	docker-compose down -v
	docker system prune -f

.PHONY: create-iam-user
create-iam-user: ## Create IAM user for evaluation
	./scripts/create-iam-user.sh

.PHONY: migrate
migrate: ## Run database migrations
	docker-compose exec app php artisan migrate

.PHONY: seed
seed: ## Seed the database
	docker-compose exec app php artisan db:seed

# Environment variables
ENV ?= dev
AWS_REGION ?= us-east-1