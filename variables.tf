variable "location" {
  type        = string
  description = "Azure region where to create resources."
  default     = "westeurope"
}

variable "appname" {
  type        = string
  description = "application name."
  default     = "my-app"
}

### AKS configuration params ###
variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version of the node pool"
  default     = "1.27.9"
}

variable "vm_size_node_pool" {
  type        = string
  description = "VM Size of the node pool"
  default     = "Standard_B2s"
}

### Secrets needed by AKS infra apps
variable "cloudflare-api-key" {
  type        = string
}

variable "cloudflare-api-token" {
  type        = string
}

variable "github-oauth-argo-client-id" {
  type        = string
}

variable "github-oauth-argo-client-secret" {
  type        = string
}