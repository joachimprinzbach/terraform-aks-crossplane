terraform {

  required_version = ">=1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.73.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.42.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.10.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

resource "random_pet" "prefix" {}

data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

data "azurerm_subscription" "current" {}

resource "azuread_group" "group-aks-cluster-admins" {
  display_name     = "group-aks-cluster-admins"
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]
  members          = [data.azuread_client_config.current.object_id]
}

resource "azurerm_resource_group" "default" {
  name     = "rg-${random_pet.prefix.id}"
  location = var.location
}

resource "azurerm_user_assigned_identity" "aks_identity" {
  resource_group_name = azurerm_resource_group.default.name
  location            = var.location

  name = "mid-${random_pet.prefix.id}-aks_identity"
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                      = "aks-${random_pet.prefix.id}"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.default.name
  dns_prefix                = "aks-dns-${random_pet.prefix.id}"
  kubernetes_version        = var.kubernetes_version
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    type            = "VirtualMachineScaleSets"
    name            = "default"
    node_count      = 2
    vm_size         = var.vm_size_node_pool
    os_disk_size_gb = 30
  }

  azure_active_directory_role_based_access_control {
    managed                = true
    azure_rbac_enabled     = true
    admin_group_object_ids = [azuread_group.group-aks-cluster-admins.object_id]
  }

  identity {
    type = "UserAssigned"
    identity_ids = tolist([azurerm_user_assigned_identity.aks_identity.id])
  }
}

resource "azurerm_role_assignment" "clusteradmin" {
  scope                = azurerm_kubernetes_cluster.aks.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = azuread_group.group-aks-cluster-admins.object_id
}

resource "azurerm_role_assignment" "clusteruser" {
  scope                = azurerm_kubernetes_cluster.aks.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azuread_group.group-aks-cluster-admins.object_id
}

resource "azurerm_user_assigned_identity" "crossplane" {
  location            = var.location
  name                = "mid-${random_pet.prefix.id}-crossplane"
  resource_group_name = azurerm_resource_group.default.name
}

resource "azurerm_role_assignment" "crossplane" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Owner"
  principal_id         = azurerm_user_assigned_identity.crossplane.principal_id
}

resource "azurerm_federated_identity_credential" "crossplane" {
  name                = "fedid-${random_pet.prefix.id}-crossplane"
  resource_group_name = azurerm_resource_group.default.name
  parent_id           = azurerm_user_assigned_identity.crossplane.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject             = "system:serviceaccount:azureserviceoperator-system:azureserviceoperator-default"
}

resource "azurerm_key_vault" "default" {
  location            = var.location
  name                = "kv-${random_pet.prefix.id}"
  resource_group_name = azurerm_resource_group.default.name
  sku_name            = "standard"
  tenant_id           = data.azurerm_subscription.current.tenant_id
}

# Create a Default Azure Key Vault access policy with Admin permissions
# This policy must be kept for a proper run of the "destroy" process
resource "azurerm_key_vault_access_policy" "default_policy" {
  key_vault_id = azurerm_key_vault.default.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  lifecycle {
    create_before_destroy = true
  }

  key_permissions = [
    "Backup", "Create", "Decrypt", "Delete", "Encrypt", "Get", "Import", "List", "Purge",
    "Recover", "Restore", "Sign", "UnwrapKey", "Update", "Verify", "WrapKey"
  ]
  secret_permissions      = ["Backup", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Set"]
  certificate_permissions = [
    "Create", "Delete", "DeleteIssuers", "Get", "GetIssuers", "Import", "List", "ListIssuers",
    "ManageContacts", "ManageIssuers", "Purge", "Recover", "SetIssuers", "Update", "Backup", "Restore"
  ]
  storage_permissions = [
    "Backup", "Delete", "DeleteSAS", "Get", "GetSAS", "List", "ListSAS",
    "Purge", "Recover", "RegenerateKey", "Restore", "Set", "SetSAS", "Update"
  ]

}

resource "azurerm_user_assigned_identity" "extsecrets" {
  location            = var.location
  name                = "mid-${random_pet.prefix.id}-extsecrets"
  resource_group_name = azurerm_resource_group.default.name
}

resource "azurerm_key_vault_access_policy" "extsecrets" {
  key_vault_id = azurerm_key_vault.default.id
  tenant_id    = data.azurerm_subscription.current.tenant_id
  object_id    = azurerm_user_assigned_identity.extsecrets.principal_id

  secret_permissions = [
    "Get"
  ]
}

resource "azurerm_key_vault_secret" "subscription_id" {
  key_vault_id = azurerm_key_vault.default.id
  name         = "subscription-id"
  value        = data.azurerm_subscription.current.subscription_id

  depends_on = [azurerm_key_vault_access_policy.default_policy]
}

resource "azurerm_key_vault_secret" "tenant_id" {
  key_vault_id = azurerm_key_vault.default.id
  name         = "tenant-id"
  value        = data.azurerm_subscription.current.tenant_id

  depends_on = [azurerm_key_vault_access_policy.default_policy]
}

resource "azurerm_key_vault_secret" "client_id" {
  key_vault_id = azurerm_key_vault.default.id
  name         = "crossplane-managed-identity-client-id"
  value        = azurerm_user_assigned_identity.crossplane.client_id

  depends_on = [azurerm_key_vault_access_policy.default_policy]
}

resource "azurerm_key_vault_secret" "crossplane-use_workload_id" {
  key_vault_id = azurerm_key_vault.default.id
  name         = "crossplane-use-workload-identity-auth"
  value        = "true"

  depends_on = [azurerm_key_vault_access_policy.default_policy]
}

resource "azurerm_key_vault_secret" "cloudflare-api-key" {
  key_vault_id = azurerm_key_vault.default.id
  name         = "cloudflare-api-key"
  value        = var.cloudflare-api-key

  depends_on = [azurerm_key_vault_access_policy.default_policy]
}

resource "azurerm_key_vault_secret" "cloudflare-api-token" {
  key_vault_id = azurerm_key_vault.default.id
  name         = "cloudflare-api-token"
  value        = var.cloudflare-api-token

  depends_on = [azurerm_key_vault_access_policy.default_policy]
}

resource "azurerm_key_vault_secret" "github-oauth-argo-client-id" {
  key_vault_id = azurerm_key_vault.default.id
  name         = "github-oauth-argo-client-id"
  value        = var.github-oauth-argo-client-id

  depends_on = [azurerm_key_vault_access_policy.default_policy]
}

resource "azurerm_key_vault_secret" "github-oauth-argo-client-secret" {
  key_vault_id = azurerm_key_vault.default.id
  name         = "github-oauth-argo-client-secret"
  value        = var.github-oauth-argo-client-secret

  depends_on = [azurerm_key_vault_access_policy.default_policy]
}

resource "azurerm_federated_identity_credential" "extsecrets" {
  name                = "fedid-${random_pet.prefix.id}-extsecrets"
  resource_group_name = azurerm_resource_group.default.name
  parent_id           = azurerm_user_assigned_identity.extsecrets.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject             = "system:serviceaccount:${kubernetes_service_account.extsecrets.metadata.0.namespace}:${kubernetes_service_account.extsecrets.metadata.0.name}"
}

resource "helm_release" "external-secrets" {
  name              = "external-secrets"
  repository        = "https://charts.external-secrets.io"
  chart             = "external-secrets"
  version           = "v0.9.13"
  dependency_update = true
  force_update      = true
  wait              = true
  namespace         = "external-secrets"
  create_namespace  = true

  depends_on = [azurerm_kubernetes_cluster.aks]
}

resource "kubernetes_service_account" "extsecrets" {
  metadata {
    name        = "externalsecretsoperator-default"
    namespace   = helm_release.external-secrets.namespace
    annotations = {
      "azure.workload.identity/client-id" : azurerm_user_assigned_identity.extsecrets.client_id
      "azure.workload.identity/tenant-id" : azurerm_user_assigned_identity.extsecrets.tenant_id
    }
  }
}

resource "kubectl_manifest" "external_secrets_cluster_store" {
  yaml_body = <<-EOF
    apiVersion: external-secrets.io/v1alpha1
    kind: ClusterSecretStore
    metadata:
      name: azure-key-vault-store
      namespace: ${kubernetes_service_account.extsecrets.metadata.0.namespace}
    spec:
      provider:
        azurekv:
          authType: WorkloadIdentity
          vaultUrl: ${azurerm_key_vault.default.vault_uri}
          serviceAccountRef:
            name: externalsecretsoperator-default
            namespace: ${kubernetes_service_account.extsecrets.metadata.0.namespace}
EOF
}
