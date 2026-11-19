locals {
  read_stack_set = local.organization && var.read_access
  read_by_unit   = local.read_stack_set && var.read_organization_unit_ids != null
}

# Service-managed StackSets do not deploy to the management account, which gets its read role from aws_iam_role.read.
# No region pin: the stack set instance resource has no API region argument, so both use the provider's region.
resource "aws_cloudformation_stack_set" "cloud_compass_read" {
  count            = local.read_stack_set ? 1 : 0
  name             = local.read_stack_set_name
  description      = "env0 Cloud Compass read role in each member account."
  permission_model = "SERVICE_MANAGED"
  call_as          = "SELF"
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  template_body    = file("${path.module}/member-role.yaml")

  # The provider needs every template parameter set. With OIDC the tenant signs in to the management read role, which
  # then assumes the member roles, as the template does.
  parameters = {
    CloudQueryRoleArn = local.oidc ? "arn:${local.partition}:iam::${local.account_id}:role/${local.read_role_name}" : var.context_layer_role_arn
    SignInMethod      = var.context_layer_sign_in_method
    ExternalId        = local.oidc ? "" : var.external_id
    RoleName          = local.read_role_name
    IncludeCostData   = var.include_cost_data ? "true" : "false"
    # A new token updates the StackSet, which deploys every member stack again in place: a failed one is created, and
    # the others keep their role. An apply with no change leaves a failed account OUTDATED.
    RedeployToken = var.read_roles_redeploy_token
  }

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  managed_execution {
    active = true
  }

  operation_preferences {
    failure_tolerance_percentage = 100
    max_concurrent_percentage    = 100
    region_concurrency_type      = "PARALLEL"
  }

  lifecycle {
    # A delegated administrator can deploy service-managed StackSets too, but this one uses call_as SELF.
    precondition {
      condition     = data.aws_organizations_organization.current[0].master_account_id == local.account_id
      error_message = "Apply this module in the AWS Organizations management account."
    }
  }
}

# Every member account, so one that fails costs the others nothing: the apply succeeds and the instance stays OUTDATED.
# env zero reads each account's instance from AWS to name the failed ones.
resource "aws_cloudformation_stack_set_instance" "cloud_compass_read_root" {
  count                     = local.read_stack_set && var.read_organization_unit_ids == null ? 1 : 0
  stack_set_name            = aws_cloudformation_stack_set.cloud_compass_read[0].name
  call_as                   = "SELF"
  stack_set_instance_region = local.read_region

  deployment_targets {
    organizational_unit_ids = [data.aws_organizations_organization.current[0].roots[0].id]
  }

  operation_preferences {
    failure_tolerance_percentage = 100
    max_concurrent_percentage    = 100
    region_concurrency_type      = "PARALLEL"
  }
}

resource "aws_cloudformation_stack_instances" "cloud_compass_read" {
  count          = local.read_by_unit && length(var.read_organization_unit_ids) > 0 ? 1 : 0
  stack_set_name = aws_cloudformation_stack_set.cloud_compass_read[0].name
  call_as        = "SELF"
  regions        = [local.read_region]

  depends_on = [aws_cloudformation_stack_set_instance.cloud_compass_read_root]

  deployment_targets {
    organizational_unit_ids = var.read_organization_unit_ids
  }

  operation_preferences {
    failure_tolerance_percentage = 100
    max_concurrent_percentage    = 100
    region_concurrency_type      = "PARALLEL"
  }
}
