# terraform-aks-crossplane

Setup of an aks cluster with terraform.

## Local setup

You need:
- azure cli
- terraform cli
- kubectl

Setup the variables in a `terraform.tfvars` file, see the example `terraform.example.tfvars`.

### Initial Whitelist of Keyvault
```bash
az provider register --namespace Microsoft.KeyVault
```

### Login
```bash
az login --tenant 922474ff-3ade-465e-9be4-04730b10a029
```

### Switch to your subscription
```bash
az account set --subscription="3e4d97c2-8bd1-4b12-99ed-303d1b77c4cc"
```

### Initialize terraform and providers
```bash
terraform init
```

### apply scripts and start provisioning (takes ~8 minutes)
```bash
terraform apply --auto-approve
```

### Cleanup afterwards to destroy all ressources
```bash
terraform destroy --auto-approve
```