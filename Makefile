#!/usr/bin/env make

# set required build variables if env variables aren't set yet
ifndef BUILD_VERSION
	BUILD_VERSION := latest
endif

ifndef REPOSITORY_NAME
	REPOSITORY_NAME := terraform-aws-s3-bucket
endif

ifndef DOCKER_CACHE_IMAGE
	DOCKER_CACHE_IMAGE := ${REPOSITORY_NAME}-${BUILD_VERSION}.tar
endif

ifndef TERRAFORM_PLAN_FILENAME
	TERRAFORM_PLAN_FILENAME := tfplan
endif

# builds the image
docker-build:
	docker build -t ${REPOSITORY_NAME}:latest -t ${REPOSITORY_NAME}:${BUILD_VERSION} .

# saves docker image to disk
docker-save:
	docker save ${REPOSITORY_NAME}:${BUILD_VERSION} > ${DOCKER_CACHE_IMAGE}

# load saved image
docker-load:
	docker load < ${DOCKER_CACHE_IMAGE}

# Run pre-commit hooks
docker-run-pre-commit-hooks: docker-build
	docker run --rm \
		${REPOSITORY_NAME}:${BUILD_VERSION} \
		pre-commit run --all-files

# Run pre-commit hooks using a cached image
docker-run-pre-commit-hooks-from-cache: docker-load
	docker run --rm \
		${REPOSITORY_NAME}:${BUILD_VERSION} \
		pre-commit run --all-files

# Run go test
docker-run-tests: docker-build
	docker run --rm \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		${REPOSITORY_NAME}:${BUILD_VERSION} \
		go test -v test/terraform_aws_s3_bucket_test.go

# Run go test using a cached image
docker-run-tests-from-cache: docker-load
	docker run --rm \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		${REPOSITORY_NAME}:${BUILD_VERSION} \
		go test -v test/terraform_aws_s3_bucket_test.go

# Run terraform plan
docker-run-terraform-plan: docker-build
	docker run --rm \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		${REPOSITORY_NAME}:${BUILD_VERSION} \
		sh -c "terraform init -input=false && terraform plan -input=false"

# Run terraform plan using a cached image
docker-run-terraform-plan-from-cache: docker-load
	docker run --rm \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		${REPOSITORY_NAME}:${BUILD_VERSION} \
		sh -c "terraform init -input=false && terraform plan -input=false"


.PHONY: docker-build docker-save docker-load docker-run-pre-commit-hooks docker-run-pre-commit-hooks-from-cache \
 docker-run-tests docker-run-tests-from-cache docker-run-terraform-plan docker-run-terraform-plan-from-cache