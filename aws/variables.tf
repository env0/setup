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

variable "context_layer_sign_in_method" {
  description = "How the Context Layer signs in to the Cloud Compass read role: assume_role, as its sync role with the External ID, or oidc, with the workspace's web identity."
  type        = string
  default     = "assume_role"
}

variable "context_layer_role_arn" {
  description = "With assume_role: ARN of the Context Layer sync role that can assume the Cloud Compass read role."
  type        = string
  default     = null
}

variable "external_id" {
  description = "With assume_role: External ID that the Context Layer sync role must send (sts:ExternalId)."
  type        = string
  default     = null
  sensitive   = true
}

variable "context_layer_oidc_issuer" {
  description = "With oidc: the OpenID Connect issuer of the Context Layer workspace, without https://."
  type        = string
  default     = null
}

variable "context_layer_oidc_audience" {
  description = "With oidc: the audience of the Context Layer workspace tokens."
  type        = string
  default     = null
}

variable "context_layer_oidc_subject" {
  description = "With oidc: the subject of the Context Layer workspace tokens."
  type        = string
  default     = null
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
  description = "Name of the deploy role in each member account. Give each setup its own, so two can share an account."
  type        = string
  default     = "env0-deploy"

  validation {
    condition     = can(regex("^[\\w+=,.@-]{1,64}$", var.deploy_role_name))
    error_message = "deploy_role_name must be 1 to 64 letters, digits or + = , . @ _ -."
  }
}

variable "deploy_role_policy_arns" {
  description = "AWS managed policies of the deploy roles. Null gives AdministratorAccess. A customer managed policy's ARN names one account, so it cannot reach the others."
  type        = list(string)
  default     = null

  validation {
    # Terraform 1.5.7 evaluates both sides of ||, so a null list is swapped for a valid one rather than short-circuited.
    condition = (
      length(var.deploy_role_policy_arns == null ? ["default"] : var.deploy_role_policy_arns) <= 10 &&
      alltrue([
        for arn in(var.deploy_role_policy_arns == null ? ["arn:aws:iam::aws:policy/AdministratorAccess"] : var.deploy_role_policy_arns) :
        can(regex("^arn:aws[a-z-]*:iam::aws:policy/[^,]+$", arn))
      ]) &&
      length(var.deploy_role_policy_arns == null ? ["default"] : var.deploy_role_policy_arns) > 0
    )
    error_message = "deploy_role_policy_arns must hold 1 to 10 AWS managed policy ARNs."
  }
}

variable "deploy_role_permissions_boundary_arn" {
  description = "Permissions boundary of the deploy roles: a customer managed policy whose path and name each member account must have. Empty for none."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^(arn:aws[a-z-]*:iam::\\d{12}:policy/([\\w+=,.@-]+/)*[\\w+=,.@-]+)?$", var.deploy_role_permissions_boundary_arn))
    error_message = "deploy_role_permissions_boundary_arn must be a customer managed policy ARN, or empty."
  }
}

variable "deploy_roles_region" {
  description = "Region the deploy role stacks run in. IAM is global; the Organization's SCPs must allow this region."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-\\d$", var.deploy_roles_region))
    error_message = "deploy_roles_region must be an AWS region, such as us-east-1."
  }
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
  description = "How env zero signs in to the deploy roles. oidc: with the OIDC tokens of deployments in deploy_project_ids. assume_role: as deploy_trusted_principal_arn, the organization's self-hosted agent role."
  type        = string
  default     = "oidc"

  validation {
    condition     = contains(["oidc", "assume_role"], var.deploy_sign_in_method)
    error_message = "deploy_sign_in_method must be oidc or assume_role."
  }
}

# The trust inputs of AdministratorAccess roles: the issuer must be env zero's, and each other input only its own shape.
variable "env0_oidc_issuer" {
  description = "env zero's OpenID Connect issuer without the scheme, with its trailing slash."
  type        = string
  default     = "login.app.env0.com/"

  validation {
    condition     = contains(["login.app.env0.com/", "login.dev.env0.com/"], var.env0_oidc_issuer)
    error_message = "env0_oidc_issuer must be env zero's OpenID Connect issuer."
  }
}

variable "env0_oidc_subject" {
  description = "Subject of the env zero organization's OIDC tokens. Needed for deploy roles with oidc."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^(auth0\\|[A-Za-z0-9_-]+)?$", var.env0_oidc_subject))
    error_message = "env0_oidc_subject must be the subject of an env zero organization's OIDC tokens."
  }
}

variable "deploy_project_ids" {
  description = "With oidc: the env zero projects whose deployments may sign in to the deploy roles, by the projectId session tag of their tokens. Another project needs this module applied again."
  type        = list(string)
  default     = []

  validation {
    condition = (
      length(var.deploy_project_ids) <= 20 &&
      length(distinct(var.deploy_project_ids)) == length(var.deploy_project_ids) &&
      alltrue([for id in var.deploy_project_ids : can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))])
    )
    error_message = "deploy_project_ids must hold up to 20 distinct env zero project IDs."
  }
}

variable "deploy_trusted_principal_arn" {
  description = "With assume_role: the IAM role of the organization's self-hosted env zero agent, which signs in with the organization ID as External ID."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^(arn:aws[a-z-]*:iam::\\d{12}:role/[\\w+=,.@/-]+)?$", var.deploy_trusted_principal_arn))
    error_message = "deploy_trusted_principal_arn must be an IAM role ARN, or empty."
  }
}

variable "env0_organization_id" {
  description = "The env zero organization ID, the External ID of deploy roles with assume_role."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})?$", var.env0_organization_id))
    error_message = "env0_organization_id must be an env zero organization ID."
  }
}
