# Runs the module on a mocked AWS provider, so the deploy role gating and the account checks are proven without AWS.
# CI runs it with `tofu test` (.github/workflows/cloud-compass-templates.yml).

mock_provider "aws" {
  mock_data "aws_organizations_organization" {
    defaults = {
      id                = "o-abc1234567"
      master_account_id = "111111111111"
      roots             = [{ id = "r-root", arn = "arn:aws:organizations::111111111111:root/o-abc1234567/r-root", name = "Root", policy_types = [] }]
      non_master_accounts = [
        { id = "222222222222", arn = "a", email = "a@x", name = "a", status = "ACTIVE", state = "ACTIVE", joined_method = "CREATED", joined_timestamp = "2020-01-01T00:00:00Z" },
        { id = "333333333333", arn = "b", email = "b@x", name = "b", status = "ACTIVE", state = "ACTIVE", joined_method = "CREATED", joined_timestamp = "2020-01-01T00:00:00Z" },
        { id = "444444444444", arn = "c", email = "c@x", name = "c", status = "ACTIVE", state = "ACTIVE", joined_method = "CREATED", joined_timestamp = "2020-01-01T00:00:00Z" }
      ]
    }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com", id = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/mock" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::111111111111:policy/mock" }
  }
  mock_data "aws_region" {
    defaults = { name = "us-east-1", region = "us-east-1" }
  }
}

variables {
  account_mode           = "organization"
  context_layer_role_arn = "arn:aws:iam::123456789012:role/syncs"
  external_id            = "external-id"
  env0_oidc_subject      = "auth0|oidc-user-1"
  env0_organization_id   = "8c5b3f6e-0d1a-4e2b-9f3c-1a2b3c4d5e6f"
  deploy_account_ids     = ["222222222222", "333333333333"]
  deploy_project_ids     = ["0b5f7c2e-4d1a-4c3b-8e9f-1a2b3c4d5e6f", "9e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6b"]
}

run "targets_only_the_picked_accounts" {
  command = plan
  assert {
    condition = (
      aws_cloudformation_stack_instances.deploy_roles[0].deployment_targets[0].accounts == toset(["222222222222", "333333333333"]) &&
      aws_cloudformation_stack_instances.deploy_roles[0].deployment_targets[0].account_filter_type == "INTERSECTION" &&
      aws_cloudformation_stack_instances.deploy_roles[0].deployment_targets[0].organizational_unit_ids == toset(["r-root"])
    )
    error_message = "the root OU intersected with the picked accounts, and nothing else"
  }
}

run "apply_two_accounts" {
  command = apply
}

run "adding_an_account_keeps_the_filter" {
  command = apply
  variables {
    deploy_account_ids = ["222222222222", "333333333333", "444444444444"]
  }
  assert {
    condition = (
      length(aws_cloudformation_stack_instances.deploy_roles) == 1 &&
      aws_cloudformation_stack_instances.deploy_roles[0].deployment_targets[0].accounts == toset(["222222222222", "333333333333", "444444444444"]) &&
      aws_cloudformation_stack_instances.deploy_roles[0].deployment_targets[0].account_filter_type == "INTERSECTION"
    )
    error_message = "adding an account updates the one resource and keeps INTERSECTION"
  }
}

run "no_deploy_roles_without_picked_accounts" {
  command = plan
  variables {
    deploy_account_ids = []
  }
  assert {
    condition     = length(aws_cloudformation_stack_set.deploy_roles) == 0 && length(aws_cloudformation_stack_instances.deploy_roles) == 0
    error_message = "an Organization with no picked accounts gets no StackSet"
  }
}

run "refuses_the_management_account" {
  command = plan
  variables {
    deploy_account_ids = ["111111111111"]
  }
  expect_failures = [aws_cloudformation_stack_instances.deploy_roles]
}

run "refuses_member_accounts_for_one_account" {
  command = plan
  variables {
    account_mode       = "single"
    deploy_account_ids = ["222222222222"]
  }
  expect_failures = [output.deploy_role_arns]
}

run "passes_the_role_settings_to_the_stack_set" {
  command = plan
  variables {
    name             = "env0-cloud-compass-abcd1234"
    deploy_role_name = "env0-deploy-abcd1234"
  }
  assert {
    condition = (
      aws_cloudformation_stack_set.deploy_roles[0].name == "env0-cloud-compass-abcd1234-deploy-roles" &&
      aws_cloudformation_stack_set.deploy_roles[0].parameters["RoleName"] == "env0-deploy-abcd1234" &&
      aws_cloudformation_stack_set.deploy_roles[0].parameters["MaxSessionDuration"] == "18000" &&
      aws_cloudformation_stack_set.deploy_roles[0].parameters["OidcAudience"] == "sts.amazonaws.com" &&
      aws_cloudformation_stack_set.deploy_roles[0].auto_deployment[0].enabled == false
    )
    error_message = "the StackSet takes the setup's names, the 5-hour session, and no auto-deployment"
  }
}

run "gives_each_picked_account_its_role_arn" {
  command = apply
  variables {
    deploy_role_name = "env0-deploy-abcd1234"
  }
  override_resource {
    target = aws_cloudformation_stack_instances.deploy_roles
    values = {
      stack_instance_summaries = [
        { account_id = "222222222222", region = "us-east-1", status = "CURRENT", detailed_status = "SUCCEEDED", status_reason = "", drift_status = "NOT_CHECKED", organizational_unit_id = "r-root", stack_id = "", stack_set_id = "" },
        { account_id = "333333333333", region = "us-east-1", status = "CURRENT", detailed_status = "SUCCEEDED", status_reason = "", drift_status = "NOT_CHECKED", organizational_unit_id = "r-root", stack_id = "", stack_set_id = "" },
      ]
    }
  }
  assert {
    condition = output.deploy_role_arns == {
      "222222222222" = "arn:aws:iam::222222222222:role/env0-deploy-abcd1234"
      "333333333333" = "arn:aws:iam::333333333333:role/env0-deploy-abcd1234"
    }
    error_message = "one deploy role ARN per picked account"
  }
}

run "leaves_out_an_account_whose_stack_is_not_current" {
  command = apply
  variables {
    deploy_role_name = "env0-deploy-abcd1234"
  }
  override_resource {
    target = aws_cloudformation_stack_instances.deploy_roles
    values = {
      stack_instance_summaries = [
        { account_id = "222222222222", region = "us-east-1", status = "CURRENT", detailed_status = "SUCCEEDED", status_reason = "", drift_status = "NOT_CHECKED", organizational_unit_id = "r-root", stack_id = "", stack_set_id = "" },
        { account_id = "333333333333", region = "us-east-1", status = "OUTDATED", detailed_status = "FAILED", status_reason = "", drift_status = "NOT_CHECKED", organizational_unit_id = "r-root", stack_id = "", stack_set_id = "" },
        { account_id = "444444444444", region = "us-east-1", status = "CURRENT", detailed_status = "SUCCEEDED", status_reason = "", drift_status = "NOT_CHECKED", organizational_unit_id = "r-root", stack_id = "", stack_set_id = "" },
      ]
    }
  }
  assert {
    condition = output.deploy_role_arns == {
      "222222222222" = "arn:aws:iam::222222222222:role/env0-deploy-abcd1234"
    }
    error_message = "a failed account and an account outside the list get no ARN"
  }
}

run "reports_the_stack_instance_status_of_every_account" {
  command = apply
  override_resource {
    target = aws_cloudformation_stack_instances.deploy_roles
    values = {
      stack_instance_summaries = [
        { account_id = "222222222222", region = "us-east-1", status = "CURRENT", detailed_status = "SUCCEEDED", status_reason = "", drift_status = "NOT_CHECKED", organizational_unit_id = "r-root", stack_id = "", stack_set_id = "" },
        { account_id = "333333333333", region = "us-east-1", status = "OUTDATED", detailed_status = "FAILED", status_reason = "", drift_status = "NOT_CHECKED", organizational_unit_id = "r-root", stack_id = "", stack_set_id = "" },
      ]
    }
  }
  assert {
    condition     = output.deploy_stack_instance_statuses == { "222222222222" = "CURRENT", "333333333333" = "OUTDATED" }
    error_message = "an account whose update failed is reported, so its earlier role is not taken for gone"
  }
}

run "reads_only_the_module_region_of_an_account_with_instances_in_two" {
  command = apply
  override_resource {
    target = aws_cloudformation_stack_instances.deploy_roles
    values = {
      stack_instance_summaries = [
        { account_id = "222222222222", region = "us-east-1", status = "CURRENT", detailed_status = "SUCCEEDED", status_reason = "", drift_status = "NOT_CHECKED", organizational_unit_id = "r-root", stack_id = "", stack_set_id = "" },
        { account_id = "222222222222", region = "eu-west-1", status = "CURRENT", detailed_status = "SUCCEEDED", status_reason = "", drift_status = "NOT_CHECKED", organizational_unit_id = "r-root", stack_id = "", stack_set_id = "" },
      ]
    }
  }
  assert {
    condition = (
      output.deploy_stack_instance_statuses == { "222222222222" = "CURRENT" } &&
      keys(output.deploy_role_arns) == ["222222222222"]
    )
    error_message = "an instance made outside the module in another region neither breaks nor changes the outputs"
  }
}

run "rolls_out_to_every_account_at_once" {
  command = plan
  assert {
    condition = (
      aws_cloudformation_stack_instances.deploy_roles[0].operation_preferences[0].concurrency_mode == "SOFT_FAILURE_TOLERANCE" &&
      aws_cloudformation_stack_instances.deploy_roles[0].operation_preferences[0].max_concurrent_percentage == 100
    )
    error_message = "strict mode would run one account at a time"
  }
}

run "no_deploy_roles_for_one_account" {
  command = plan
  variables {
    account_mode       = "single"
    deploy_account_ids = []
  }
  assert {
    condition     = length(aws_cloudformation_stack_set.deploy_roles) == 0 && output.deploy_role_arns == {}
    error_message = "one account gets no StackSet"
  }
}

run "refuses_a_repeated_account" {
  command = plan
  variables {
    deploy_account_ids = ["222222222222", "222222222222"]
  }
  expect_failures = [var.deploy_account_ids]
}

run "refuses_a_malformed_account" {
  command = plan
  variables {
    deploy_account_ids = ["2222"]
  }
  expect_failures = [var.deploy_account_ids]
}

run "refuses_another_issuer" {
  command = plan
  variables {
    env0_oidc_issuer = "token.example.com/"
  }
  expect_failures = [var.env0_oidc_issuer]
}

run "lets_in_only_the_picked_projects_with_oidc" {
  command = plan
  assert {
    condition = (
      aws_cloudformation_stack_set.deploy_roles[0].parameters["SignInMethod"] == "oidc" &&
      aws_cloudformation_stack_set.deploy_roles[0].parameters["AllowedProjectIds"] == "0b5f7c2e-4d1a-4c3b-8e9f-1a2b3c4d5e6f,9e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6b" &&
      aws_cloudformation_stack_set.deploy_roles[0].parameters["TrustedPrincipalArn"] == ""
    )
    error_message = "OIDC deploy roles take the picked projects"
  }
}

run "refuses_oidc_without_projects" {
  command = plan
  variables {
    deploy_project_ids = []
  }
  expect_failures = [aws_cloudformation_stack_set.deploy_roles]
}

run "refuses_a_project_id_that_is_not_one" {
  command = plan
  variables {
    deploy_project_ids = ["project-1\",\"*"]
  }
  expect_failures = [var.deploy_project_ids]
}

run "refuses_a_repeated_project" {
  command = plan
  variables {
    deploy_project_ids = ["0b5f7c2e-4d1a-4c3b-8e9f-1a2b3c4d5e6f", "0b5f7c2e-4d1a-4c3b-8e9f-1a2b3c4d5e6f"]
  }
  expect_failures = [var.deploy_project_ids]
}

run "trusts_the_self_hosted_agent_role_with_assume_role" {
  command = plan
  variables {
    deploy_sign_in_method        = "assume_role"
    deploy_project_ids           = []
    deploy_trusted_principal_arn = "arn:aws:iam::444455556666:role/env0-agent"
  }
  assert {
    condition = (
      aws_cloudformation_stack_set.deploy_roles[0].parameters["TrustedPrincipalArn"] == "arn:aws:iam::444455556666:role/env0-agent" &&
      aws_cloudformation_stack_set.deploy_roles[0].parameters["Env0OrganizationId"] == "8c5b3f6e-0d1a-4e2b-9f3c-1a2b3c4d5e6f"
    )
    error_message = "assume-role deploy roles trust the given agent role with the organization ID"
  }
}

run "refuses_assume_role_without_a_trusted_principal" {
  command = plan
  variables {
    deploy_sign_in_method = "assume_role"
  }
  expect_failures = [aws_cloudformation_stack_set.deploy_roles]
}

run "refuses_a_trusted_principal_that_is_not_a_role" {
  command = plan
  variables {
    deploy_sign_in_method        = "assume_role"
    deploy_trusted_principal_arn = "arn:aws:iam::111111111111:root"
  }
  expect_failures = [var.deploy_trusted_principal_arn]
}

run "refuses_a_malformed_subject" {
  command = plan
  variables {
    env0_oidc_subject = "auth0|x\",\"Principal\":\"*"
  }
  expect_failures = [var.env0_oidc_subject]
}

run "refuses_a_malformed_organization_id" {
  command = plan
  variables {
    env0_organization_id = "org-1"
  }
  expect_failures = [var.env0_organization_id]
}

run "gives_the_deploy_roles_administrator_access_by_default" {
  command = plan
  assert {
    condition = (
      aws_cloudformation_stack_set.deploy_roles[0].parameters["RoleName"] == "env0-deploy" &&
      aws_cloudformation_stack_set.deploy_roles[0].parameters["ManagedPolicyArns"] == "arn:aws:iam::aws:policy/AdministratorAccess" &&
      aws_cloudformation_stack_set.deploy_roles[0].parameters["PermissionsBoundaryPolicyName"] == "" &&
      aws_cloudformation_stack_instances.deploy_roles[0].regions == toset(["us-east-1"])
    )
    error_message = "env0-deploy, AdministratorAccess, no boundary and us-east-1 unless told otherwise"
  }
}

run "takes_the_given_policies_boundary_and_region" {
  command = plan
  variables {
    deploy_role_policy_arns              = ["arn:aws:iam::aws:policy/PowerUserAccess", "arn:aws:iam::aws:policy/ReadOnlyAccess"]
    deploy_role_permissions_boundary_arn = "arn:aws:iam::111111111111:policy/env0/boundary"
    deploy_roles_region                  = "eu-west-1"
  }
  assert {
    condition = (
      aws_cloudformation_stack_set.deploy_roles[0].parameters["ManagedPolicyArns"] == "arn:aws:iam::aws:policy/PowerUserAccess,arn:aws:iam::aws:policy/ReadOnlyAccess" &&
      aws_cloudformation_stack_set.deploy_roles[0].parameters["PermissionsBoundaryPolicyName"] == "env0/boundary" &&
      aws_cloudformation_stack_instances.deploy_roles[0].regions == toset(["eu-west-1"])
    )
    error_message = "the given policies, boundary and region reach the StackSet"
  }
}

run "refuses_a_policy_that_is_not_an_arn" {
  command = plan
  variables {
    deploy_role_policy_arns = ["AdministratorAccess"]
  }
  expect_failures = [var.deploy_role_policy_arns]
}

run "refuses_no_policies" {
  command = plan
  variables {
    deploy_role_policy_arns = []
  }
  expect_failures = [var.deploy_role_policy_arns]
}

run "refuses_a_boundary_that_is_not_an_arn" {
  command = plan
  variables {
    deploy_role_permissions_boundary_arn = "boundary"
  }
  expect_failures = [var.deploy_role_permissions_boundary_arn]
}

run "refuses_a_region_that_is_not_one" {
  command = plan
  variables {
    deploy_roles_region = "everywhere"
  }
  expect_failures = [var.deploy_roles_region]
}

run "refuses_a_customer_managed_policy_that_names_one_account" {
  command = plan
  variables {
    deploy_role_policy_arns = ["arn:aws:iam::111111111111:policy/deploy"]
  }
  expect_failures = [var.deploy_role_policy_arns]
}

run "refuses_an_aws_managed_boundary" {
  command = plan
  variables {
    deploy_role_permissions_boundary_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
  }
  expect_failures = [var.deploy_role_permissions_boundary_arn]
}

run "refuses_a_role_name_with_a_space" {
  command = plan
  variables {
    deploy_role_name = "env zero deploy"
  }
  expect_failures = [var.deploy_role_name]
}

run "refuses_a_role_name_longer_than_64" {
  command = plan
  variables {
    deploy_role_name = "env0-deploy-01234567890123456789012345678901234567890123456789012"
  }
  expect_failures = [var.deploy_role_name]
}

run "refuses_a_boundary_with_a_space" {
  command = plan
  variables {
    deploy_role_permissions_boundary_arn = "arn:aws:iam::111111111111:policy/env0 boundary"
  }
  expect_failures = [var.deploy_role_permissions_boundary_arn]
}

run "refuses_a_boundary_ending_in_a_slash" {
  command = plan
  variables {
    deploy_role_permissions_boundary_arn = "arn:aws:iam::111111111111:policy/env0/"
  }
  expect_failures = [var.deploy_role_permissions_boundary_arn]
}

run "refuses_a_policy_with_a_comma" {
  command = plan
  variables {
    deploy_role_policy_arns = ["arn:aws:iam::aws:policy/PowerUserAccess,ReadOnlyAccess"]
  }
  expect_failures = [var.deploy_role_policy_arns]
}
