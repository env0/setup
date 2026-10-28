variable "account_mode" {
  description = "single for one AWS account, organization for the AWS Organization whose management account env zero deploys in."
  type        = string

  validation {
    condition     = contains(["single", "organization"], var.account_mode)
    error_message = "account_mode must be single or organization."
  }
}

variable "name" {
  description = "Prefix of the Cloud Compass resource names, unique in the AWS account."
  type        = string
  default     = "env0-cloud-compass"
}

variable "cloudquery_role_arn" {
  description = "ARN of the CloudQuery sync role that can assume the Cloud Compass read role."
  type        = string
}

variable "external_id" {
  description = "External ID that the CloudQuery sync role must send (sts:ExternalId)."
  type        = string
  sensitive   = true
}

variable "include_cost_data" {
  description = "Create the CUR 2.0 export, its S3 bucket and the read role's CUR read policy."
  type        = bool
  default     = true
}

variable "deploy_account_ids" {
  description = "Organization member accounts that get a deploy role. The management account deploys with the role env zero already has there."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.deploy_account_ids : can(regex("^\\d{12}$", id))])
    error_message = "deploy_account_ids must hold 12-digit AWS account IDs."
  }

  validation {
    condition     = length(distinct(var.deploy_account_ids)) == length(var.deploy_account_ids)
    error_message = "deploy_account_ids must not repeat an account."
  }
}

variable "deploy_role_name" {
  description = "Name of the deploy role in each member account."
  type        = string
  default     = "env-zero-deploy"
}

variable "deploy_role_max_session_duration" {
  description = "Longest session, in seconds, env zero can ask for with a deploy role. env zero asks for 18000 unless the credential sets its own duration."
  type        = number
  default     = 18000

  validation {
    condition     = var.deploy_role_max_session_duration >= 3600 && var.deploy_role_max_session_duration <= 43200
    error_message = "deploy_role_max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "deploy_sign_in_method" {
  description = "How env zero signs in to the deploy roles: oidc or assume_role, as the deployment credential that runs this template."
  type        = string
  default     = "oidc"

  validation {
    condition     = contains(["oidc", "assume_role"], var.deploy_sign_in_method)
    error_message = "deploy_sign_in_method must be oidc or assume_role."
  }
}

variable "env0_oidc_issuer" {
  description = "env zero's OpenID Connect issuer without the scheme, with its trailing slash."
  type        = string
  default     = "login.app.env0.com/"
}

variable "env0_oidc_subject" {
  description = "Subject of the env zero organization's OIDC tokens. Needed for deploy roles with oidc."
  type        = string
  default     = ""
}

variable "env0_aws_account_id" {
  description = "env zero's AWS account, trusted by deploy roles with assume_role."
  type        = string
  default     = "913128560467"
}

variable "env0_organization_id" {
  description = "The env zero organization ID, the External ID of deploy roles with assume_role."
  type        = string
  default     = ""
}
