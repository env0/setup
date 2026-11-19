# Runs the module on a mocked AWS provider, so which member accounts get the read role is proven without AWS.
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
  mock_resource "aws_cloudformation_stack" {
    defaults = { outputs = { ProviderArn = "arn:aws:iam::111111111111:oidc-provider/login.app.env0.com/" } }
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
  include_cost_data      = false
}

run "targets_only_the_picked_units_with_auto_deployment" {
  command = plan
  variables {
    read_organization_unit_ids = ["ou-ab12-cdef3456", "ou-ab12-gh789012"]
  }
  assert {
    condition = (
      length(aws_cloudformation_stack_instances.cloud_compass_read) == 1 &&
      aws_cloudformation_stack_instances.cloud_compass_read[0].deployment_targets[0].organizational_unit_ids == toset(["ou-ab12-cdef3456", "ou-ab12-gh789012"]) &&
      aws_cloudformation_stack_instances.cloud_compass_read[0].regions == toset(["us-east-1"]) &&
      aws_cloudformation_stack_set.cloud_compass_read[0].auto_deployment[0].enabled == true
    )
    error_message = "instances on exactly the picked units, and new accounts in them get the role"
  }
  assert {
    condition     = length(aws_cloudformation_stack_set_instance.cloud_compass_read_root) == 0
    error_message = "no instance on the root, which would give every member account the role"
  }
}

run "targets_the_root_without_a_pick" {
  command = plan
  assert {
    condition = (
      length(aws_cloudformation_stack_set_instance.cloud_compass_read_root) == 1 &&
      aws_cloudformation_stack_set_instance.cloud_compass_read_root[0].deployment_targets[0].organizational_unit_ids == toset(["r-root"]) &&
      length(aws_cloudformation_stack_instances.cloud_compass_read) == 0
    )
    error_message = "a setup from before the variable keeps its one instance on the root"
  }
}

run "gives_no_member_account_the_role_for_an_empty_pick" {
  command = plan
  variables {
    read_organization_unit_ids = []
  }
  assert {
    condition = (
      length(aws_cloudformation_stack_set_instance.cloud_compass_read_root) == 0 &&
      length(aws_cloudformation_stack_instances.cloud_compass_read) == 0 &&
      length(aws_cloudformation_stack_set.cloud_compass_read) == 1
    )
    error_message = "no instance, so no member account"
  }
}

run "always_reads_the_management_account" {
  command = plan
  variables {
    read_organization_unit_ids = []
  }
  assert {
    condition     = length(aws_iam_role.read) == 1 && length(aws_iam_role_policy.default_deny) == 1
    error_message = "the management account's read role does not depend on the pick"
  }
}

run "reports_nothing_from_the_instances_so_a_new_account_changes_no_output" {
  command = apply
  variables {
    read_organization_unit_ids = ["ou-ab12-cdef3456"]
  }
  override_resource {
    target = aws_cloudformation_stack_instances.cloud_compass_read
    values = {
      stack_instance_summaries = [
        { account_id = "222222222222", region = "us-east-1", status = "CURRENT", detailed_status = "SUCCEEDED", status_reason = "", drift_status = "NOT_CHECKED", organizational_unit_id = "ou-ab12-cdef3456", stack_id = "", stack_set_id = "" },
        { account_id = "333333333333", region = "us-east-1", status = "CURRENT", detailed_status = "SUCCEEDED", status_reason = "", drift_status = "NOT_CHECKED", organizational_unit_id = "ou-ab12-cdef3456", stack_id = "", stack_set_id = "" },
      ]
    }
  }
  assert {
    condition     = output.deploy_role_arns == {} && output.deploy_stack_instance_statuses == {}
    error_message = "a member account added by auto-deployment shows in no output"
  }
}

run "refuses_a_unit_id_that_is_not_one" {
  command = plan
  variables {
    read_organization_unit_ids = ["not-an-ou"]
  }
  expect_failures = [var.read_organization_unit_ids]
}
