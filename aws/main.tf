locals {
  organization = var.account_mode == "organization"
  # One account deploys with the role its deployment credential already uses.
  deploy_roles = local.organization && length(var.deploy_account_ids) > 0
  # IAM is global; the region is only where each member account's stack runs, so an SCP must allow it.
  region = var.deploy_roles_region
  deploy_role_policy_arns = (
    var.deploy_role_policy_arns != null
    ? var.deploy_role_policy_arns
    : ["arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"]
  )
}

data "aws_partition" "current" {}

# No callback: env zero reads the outputs when the deployment completes.
module "single" {
  count  = local.organization ? 0 : 1
  source = "https://env0-cloud-compass-templates-prod.s3.amazonaws.com/17802b85d9c3/cloud-compass-opentofu.zip//cloud-compass-single"

  cloudquery_role_arn = var.cloudquery_role_arn
  external_id         = var.external_id
  name                = var.name
  include_cost_data   = var.include_cost_data
}

module "organization" {
  count  = local.organization ? 1 : 0
  source = "https://env0-cloud-compass-templates-prod.s3.amazonaws.com/17802b85d9c3/cloud-compass-opentofu.zip//cloud-compass-org"

  cloudquery_role_arn = var.cloudquery_role_arn
  external_id         = var.external_id
  name                = var.name
  include_cost_data   = var.include_cost_data
}

data "aws_organizations_organization" "current" {
  count = local.deploy_roles ? 1 : 0
}

resource "aws_cloudformation_stack_set" "deploy_roles" {
  count            = local.deploy_roles ? 1 : 0
  name             = "${var.name}-deploy-roles"
  description      = "env zero deploy role in each member account env zero deploys to."
  permission_model = "SERVICE_MANAGED"
  call_as          = "SELF"
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  template_body    = file("${path.module}/deploy-role.yaml")

  parameters = {
    RoleName                      = var.deploy_role_name
    ManagedPolicyArns             = join(",", local.deploy_role_policy_arns)
    PermissionsBoundaryPolicyName = try(split(":policy/", var.deploy_role_permissions_boundary_arn)[1], "")
    MaxSessionDuration            = var.deploy_role_max_session_duration
    SignInMethod                  = var.deploy_sign_in_method
    OidcIssuer                    = var.env0_oidc_issuer
    OidcAudience                  = "sts.amazonaws.com"
    OidcSubject                   = var.env0_oidc_subject
    AllowedProjectIds             = join(",", var.deploy_project_ids)
    TrustedPrincipalArn           = var.deploy_trusted_principal_arn
    Env0OrganizationId            = var.env0_organization_id
  }

  # Only the picked accounts, so a new account in the Organization gets no deploy role.
  auto_deployment {
    enabled = false
  }

  managed_execution {
    active = true
  }

  # A template or parameter update reaches the accounts one at a time: this resource has no soft failure tolerance.
  timeouts {
    update = "2h"
  }

  lifecycle {
    precondition {
      condition = (
        var.deploy_sign_in_method == "oidc"
        ? var.env0_oidc_subject != "" && length(var.deploy_project_ids) > 0
        : var.env0_organization_id != "" && var.deploy_trusted_principal_arn != ""
      )
      error_message = "Deploy roles need env0_oidc_subject and deploy_project_ids with oidc, or env0_organization_id and deploy_trusted_principal_arn with assume_role."
    }
  }
}

# One resource for every picked account: a StackSet runs one operation at a time, and the provider's create does not
# wait out another one, so instances per account would collide. A change of the list updates it in place: the
# provider deletes only the removed accounts and creates with the whole list, both with INTERSECTION, so nothing
# reaches an account outside the list. A stack set instance would instead replace every account's stack.
resource "aws_cloudformation_stack_instances" "deploy_roles" {
  count          = local.deploy_roles ? 1 : 0
  stack_set_name = aws_cloudformation_stack_set.deploy_roles[0].name
  call_as        = "SELF"
  regions        = [local.region]

  deployment_targets {
    organizational_unit_ids = [data.aws_organizations_organization.current[0].roots[0].id]
    accounts                = var.deploy_account_ids
    account_filter_type     = "INTERSECTION"
  }

  # Under the default strict mode the concurrency is the failure tolerance plus one, so every account at once needs soft.
  operation_preferences {
    concurrency_mode             = "SOFT_FAILURE_TOLERANCE"
    failure_tolerance_percentage = 0
    max_concurrent_percentage    = 100
    region_concurrency_type      = "PARALLEL"
  }

  timeouts {
    create = "2h"
    update = "2h"
    delete = "2h"
  }

  # INTERSECTION drops an account outside the Organization, and a service-managed StackSet never deploys to the
  # management account, so either would get no role while deploy_role_arns still lists one.
  lifecycle {
    precondition {
      condition = length(setsubtract(
        var.deploy_account_ids,
        data.aws_organizations_organization.current[0].non_master_accounts[*].id
      )) == 0
      error_message = "deploy_account_ids must be member accounts of the Organization, not its management account."
    }
  }
}
