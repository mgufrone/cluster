plan:
	terraform plan -var-file=secrets.tfvars
apply:
	terraform apply -var-file=secrets.tfvars
commit:
	terraform apply -auto-approve -var-file=secrets.tfvars
destroy:
	terraform destroy -var-file=secrets.tfvars
purge:
	terraform destroy -auto-approve -var-file=secrets.tfvars
