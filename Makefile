.PHONY: check init plan apply

check:
	@aws sts get-caller-identity > /dev/null || (echo "AWS credentials not working" && exit 1)

init: check
	terraform init

plan: check
	terraform plan -input=false -out=tfplan

apply: check
	terraform apply -input=false tfplan
