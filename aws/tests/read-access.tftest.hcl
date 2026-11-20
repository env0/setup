# Runs the module on a mocked AWS provider, so the read access switch is proven without AWS.
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
  env0_oidc_subject      = "auth0|oidc-user-1"
  env0_organization_id   = "8c5b3f6e-0d1a-4e2b-9f3c-1a2b3c4d5e6f"
  deploy_account_ids     = ["222222222222"]
  deploy_project_ids     = ["0b5f7c2e-4d1a-4c3b-8e9f-1a2b3c4d5e6f"]
  read_access            = false
}

run "plans_no_read_resource_for_an_organization_without_read_access" {
  command = plan
  assert {
    condition = (
      length(aws_iam_role.read) == 0 &&
      length(aws_iam_role_policy.default_deny) == 0 &&
      length(aws_iam_role_policy.cur_read) == 0 &&
      length(aws_cloudformation_stack_set.cloud_compass_read) == 0 &&
      length(aws_cloudformation_stack_set_instance.cloud_compass_read_root) == 0 &&
      length(aws_cloudformation_stack_instances.cloud_compass_read) == 0 &&
      length(aws_s3_bucket.cur) == 0 &&
      length(aws_bcmdataexports_export.cur) == 0
    )
    error_message = "no read role, StackSet, bucket or export"
  }
}

run "keeps_the_deploy_roles_without_read_access" {
  command = plan
  assert {
    condition     = length(aws_cloudformation_stack_set.deploy_roles) == 1 && length(aws_cloudformation_stack_instances.deploy_roles) == 1
    error_message = "the deploy StackSet does not depend on read access"
  }
}

run "outputs_nothing_of_cloud_compass_without_read_access" {
  command = apply
  assert {
    condition = (
      output.role_arn == null &&
      output.cur_export_name == null &&
      output.cur_bucket == null &&
      output.cur_prefix == null
    )
    error_message = "the read outputs are null"
  }
  assert {
    condition     = output.account_id == "111111111111" && output.organization_id == "o-abc1234567"
    error_message = "the account and Organization are still reported"
  }
}

run "plans_no_read_resource_for_one_account_without_read_access" {
  command = apply
  variables {
    account_mode          = "single"
    deploy_account_ids    = []
    deploy_single_account = true
  }
  assert {
    condition = (
      length(aws_iam_role.read) == 0 &&
      length(aws_s3_bucket.cur) == 0 &&
      length(aws_iam_role.deploy) == 1 &&
      output.role_arn == null &&
      output.account_id == "111111111111" &&
      output.organization_id == null
    )
    error_message = "one account without read access creates only the deploy role"
  }
}

run "plans_the_read_role_again_with_read_access" {
  command = plan
  variables {
    read_access = true
  }
  assert {
    condition     = length(aws_iam_role.read) == 1 && length(aws_cloudformation_stack_set.cloud_compass_read) == 1 && length(aws_s3_bucket.cur) == 1
    error_message = "read access is on by default"
  }
}
