resource "aws_cloudformation_stack_set" "deploy_roles" {
  count            = local.deploy_roles ? 1 : 0
  name             = local.deploy_stack_set_name
  description      = "env zero deploy role in each member account env zero deploys to."
  permission_model = "SERVICE_MANAGED"
  call_as          = "SELF"
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  template_body    = local.deploy_template

  parameters = {
    RoleName                      = local.deploy_role_name
    ManagedPolicyArns             = join(",", local.deploy_role_policy_arns)
    PermissionsBoundaryPolicyName = local.deploy_permissions_boundary
    MaxSessionDuration            = var.deploy_role_max_session_duration
    SignInMethod                  = var.deploy_sign_in_method
    OidcIssuer                    = var.env0_oidc_issuer
    OidcAudience                  = "sts.amazonaws.com"
    OidcSubject                   = var.env0_oidc_subject
    AllowedProjectIds             = local.deploy_template_by_account ? "" : join(",", var.deploy_project_ids)
    TrustedPrincipalArn           = var.deploy_trusted_principal_arn
    Env0OrganizationId            = var.env0_organization_id
    RedeployToken                 = var.deploy_roles_redeploy_token
  }

  # Only the picked accounts, so a new account in the Organization gets no deploy role.
  auto_deployment {
    enabled = false
  }

  operation_preferences {
    failure_tolerance_percentage = 100
    max_concurrent_percentage    = 100
    region_concurrency_type      = "PARALLEL"
  }

  managed_execution {
    active = true
  }

  timeouts {
    update = "2h"
  }

  lifecycle {
    precondition {
      condition = (
        local.deploy_oidc
        ? var.env0_oidc_subject != "" && (var.deploy_project_ids_by_account != null || length(var.deploy_project_ids) > 0)
        : var.env0_organization_id != "" && var.deploy_trusted_principal_arn != ""
      )
      error_message = "Deploy roles need env0_oidc_subject and deploy_project_ids or deploy_project_ids_by_account with oidc, or env0_organization_id and deploy_trusted_principal_arn with assume_role."
    }

    precondition {
      condition     = local.deploy_template_bytes <= local.deploy_template_limit
      error_message = "The deploy role template for ${length(local.deploy_mapping_accounts)} accounts, with up to ${max(local.deploy_project_counts...)} projects in one account, is ${local.deploy_template_bytes} bytes, over the ${local.deploy_template_limit} bytes AWS allows. Give fewer accounts or projects access."
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

module "deploy_oidc_provider" {
  count  = local.deploy_in_this_account && local.deploy_oidc ? 1 : 0
  source = "https://env0-cloud-compass-templates-prod.s3.amazonaws.com/6ffd4753b268/cloud-compass-opentofu.zip//cloud-compass-oidc-provider"

  name     = "${var.name}-deploy"
  issuer   = var.env0_oidc_issuer
  audience = "sts.amazonaws.com"
}

data "aws_iam_policy_document" "deploy_trust" {
  count = local.deploy_in_this_account ? 1 : 0

  dynamic "statement" {
    for_each = local.deploy_oidc ? [1] : []

    content {
      effect  = "Allow"
      actions = ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"]

      principals {
        type        = "Federated"
        identifiers = [module.deploy_oidc_provider[0].provider_arn]
      }

      condition {
        test     = "StringEquals"
        variable = "${var.env0_oidc_issuer}:aud"
        values   = ["sts.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "${var.env0_oidc_issuer}:sub"
        values   = [var.env0_oidc_subject]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/projectId"
        values   = length(local.deploy_project_ids_here) > 0 ? local.deploy_project_ids_here : [local.no_project_id]
      }
    }
  }

  dynamic "statement" {
    for_each = local.deploy_oidc ? [] : [1]

    content {
      effect  = "Allow"
      actions = ["sts:AssumeRole"]

      principals {
        type        = "AWS"
        identifiers = [var.deploy_trusted_principal_arn]
      }

      condition {
        test     = "StringEquals"
        variable = "sts:ExternalId"
        values   = [var.env0_organization_id]
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.deploy_oidc ? var.env0_oidc_subject != "" : var.env0_organization_id != "" && var.deploy_trusted_principal_arn != ""
      error_message = "The deploy role needs env0_oidc_subject with oidc, or env0_organization_id and deploy_trusted_principal_arn with assume_role."
    }
  }
}

resource "aws_iam_role" "deploy" {
  count                = var.deploy_single_account && !local.organization ? 1 : 0
  name                 = local.deploy_role_name
  max_session_duration = var.deploy_role_max_session_duration
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust[0].json
  permissions_boundary = local.deploy_permissions_boundary == "" ? null : "arn:${local.partition}:iam::${local.account_id}:policy/${local.deploy_permissions_boundary}"
}

resource "aws_iam_role" "deploy_management" {
  count                = var.deploy_management_account && local.organization ? 1 : 0
  name                 = local.deploy_role_name
  max_session_duration = var.deploy_role_max_session_duration
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust[0].json
  permissions_boundary = local.deploy_permissions_boundary == "" ? null : "arn:${local.partition}:iam::${local.account_id}:policy/${local.deploy_permissions_boundary}"

  lifecycle {
    precondition {
      condition     = data.aws_organizations_organization.current[0].master_account_id == local.account_id
      error_message = "Apply this module in the AWS Organizations management account to give it a deploy role."
    }
  }
}

resource "aws_iam_role_policy_attachment" "deploy" {
  for_each   = var.deploy_single_account && !local.organization ? toset(local.deploy_role_policy_arns) : toset([])
  role       = aws_iam_role.deploy[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "deploy_management" {
  for_each   = var.deploy_management_account && local.organization ? toset(local.deploy_role_policy_arns) : toset([])
  role       = aws_iam_role.deploy_management[0].name
  policy_arn = each.value
}
