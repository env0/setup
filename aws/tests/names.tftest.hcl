# Runs the module on a mocked AWS provider, so the resource names is proven without AWS.
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
  account_mode              = "organization"
  context_layer_role_arn    = "arn:aws:iam::123456789012:role/syncs"
  external_id               = "external-id"
  env0_oidc_subject         = "auth0|oidc-user-1"
  env0_organization_id      = "8c5b3f6e-0d1a-4e2b-9f3c-1a2b3c4d5e6f"
  deploy_account_ids        = ["222222222222"]
  deploy_project_ids        = ["0b5f7c2e-4d1a-4c3b-8e9f-1a2b3c4d5e6f"]
  deploy_management_account = true
}

run "takes_every_visible_name_from_names" {
  command = plan
  variables {
    names = {
      read_role        = "env-zero-cloud-compass-ab12cd"
      read_stack_set   = "env-zero-cloud-compass-read-ab12cd"
      cur_bucket       = "env-zero-cur-111111111111-ab12cd"
      cur_export       = "env-zero-cur-ab12cd"
      cur_policy       = "env-zero-cur-read"
      deploy_role      = "env-zero-deploy-ab12cd"
      deploy_stack_set = "env-zero-deploy-roles-ab12cd"
    }
  }
  assert {
    condition = (
      aws_iam_role.read["organization"].name == "env-zero-cloud-compass-ab12cd" &&
      aws_cloudformation_stack_set.cloud_compass_read[0].name == "env-zero-cloud-compass-read-ab12cd" &&
      aws_cloudformation_stack_set.cloud_compass_read[0].parameters["RoleName"] == "env-zero-cloud-compass-ab12cd" &&
      aws_s3_bucket.cur["organization"].bucket == "env-zero-cur-111111111111-ab12cd" &&
      aws_bcmdataexports_export.cur["organization"].export[0].name == "env-zero-cur-ab12cd" &&
      aws_iam_role_policy.cur_read["organization"].name == "env-zero-cur-read"
    )
    error_message = "the read side takes the names"
  }
  assert {
    condition = (
      aws_iam_role.deploy_management[0].name == "env-zero-deploy-ab12cd" &&
      aws_cloudformation_stack_set.deploy_roles[0].name == "env-zero-deploy-roles-ab12cd" &&
      aws_cloudformation_stack_set.deploy_roles[0].parameters["RoleName"] == "env-zero-deploy-ab12cd"
    )
    error_message = "the deploy side takes the names"
  }
}

run "names_the_one_account_read_role_too" {
  command = plan
  variables {
    account_mode              = "single"
    deploy_account_ids        = []
    deploy_management_account = false
    deploy_single_account     = true
    names = {
      read_role        = "env-zero-cloud-compass-ab12cd"
      read_stack_set   = "env-zero-cloud-compass-read-ab12cd"
      cur_bucket       = "env-zero-cur-111111111111-ab12cd"
      cur_export       = "env-zero-cur-ab12cd"
      cur_policy       = "env-zero-cur-read"
      deploy_role      = "env-zero-deploy-ab12cd"
      deploy_stack_set = "env-zero-deploy-roles-ab12cd"
    }
  }
  assert {
    condition = (
      aws_iam_role.read["single"].name == "env-zero-cloud-compass-ab12cd" &&
      aws_iam_role.deploy[0].name == "env-zero-deploy-ab12cd"
    )
    error_message = "one account's read and deploy roles take the names"
  }
}

run "keeps_the_names_of_a_setup_from_before_the_variable" {
  command = plan
  variables {
    name             = "env0-cloud-compass-abcd1234"
    deploy_role_name = "env0-deploy-abcd1234"
  }
  assert {
    condition = (
      aws_iam_role.read["organization"].name == "env0-cloud-compass-read" &&
      aws_cloudformation_stack_set.cloud_compass_read[0].name == "env0-cloud-compass-abcd1234" &&
      aws_s3_bucket.cur["organization"].bucket_prefix == "env0-cloud-compass-abcd1234-cur-" &&
      aws_bcmdataexports_export.cur["organization"].export[0].name == "cq-cur-env0-cloud-compass-abcd1234" &&
      aws_iam_role_policy.cur_read["organization"].name == "cur-read" &&
      aws_iam_role.deploy_management[0].name == "env0-deploy-abcd1234" &&
      aws_cloudformation_stack_set.deploy_roles[0].name == "env0-cloud-compass-abcd1234-deploy-roles"
    )
    error_message = "without names every name is the one an earlier setup got"
  }
}

run "keeps_a_generated_read_role_name_for_one_account_without_names" {
  command = plan
  variables {
    account_mode              = "single"
    deploy_account_ids        = []
    deploy_management_account = false
    name                      = "env0-cloud-compass-abcd1234"
  }
  assert {
    condition     = aws_iam_role.read["single"].name_prefix == "env0-cloud-compass-abcd1234-read-"
    error_message = "one account's read role keeps its generated name"
  }
}

run "refuses_a_bucket_name_with_capitals" {
  command = plan
  variables {
    names = {
      read_role        = "env-zero-cloud-compass-ab12cd"
      read_stack_set   = "env-zero-cloud-compass-read-ab12cd"
      cur_bucket       = "Env-Zero-Cur"
      cur_export       = "env-zero-cur-ab12cd"
      cur_policy       = "env-zero-cur-read"
      deploy_role      = "env-zero-deploy-ab12cd"
      deploy_stack_set = "env-zero-deploy-roles-ab12cd"
    }
  }
  expect_failures = [var.names]
}
